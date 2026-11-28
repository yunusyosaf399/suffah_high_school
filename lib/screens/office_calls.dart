import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'call_audio.dart';
import 'account_picture.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

/// Audio is transported by WebRTC, never uploaded as a voice recording.
/// Firestore contains only signaling and session state.
class OfficeCalls {
  static bool _open=false;
  static DocumentReference<Map<String,dynamic>> ref(String id)=>FirebaseFirestore.instance.collection('office_calls_v2').doc(id);
  static bool get isOpen=>_open;
  // Two equality filters use Firestore's automatic single-field indexes.
  // Expired sessions are finalized by the Worker.
  static Query<Map<String,dynamic>> incoming(String target)=>FirebaseFirestore.instance.collection('office_calls_v2')
    .where('targetUid',isEqualTo:target).where('status',isEqualTo:'ringing').limit(100);
  static bool canPresent(AppLifecycleState? state,{required bool desktop}){
    return desktop
      ? state!=AppLifecycleState.detached
      : state==AppLifecycleState.resumed;
  }
  static bool fresh(Map<String,dynamic>? data){
    final expiry=data?['expiresAt'];
    return data?['status']=='ringing'&&expiry is Timestamp&&expiry.toDate().isAfter(DateTime.now());
  }
  static Future<void> dial(BuildContext context,{String? targetUid,String? name})async{
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null||_open)return;
    await _show(context,uid:uid,callId:FirebaseFirestore.instance.collection('office_calls_v2').doc().id,incoming:false,targetUid:targetUid??'office',name:name);
  }
  static Future<void> receive(BuildContext context,String uid,String callId)async{
    if(_open||!context.mounted)return;
    _open=true;
    try{
      final data=(await ref(callId).get(const GetOptions(source:Source.server))).data();
      if(!context.mounted||!fresh(data)||data?['callId']!=callId||data?['callerUid']!=uid)return;
      await Navigator.of(context,rootNavigator:true).push<void>(MaterialPageRoute(builder:(_)=>_OfficeCallPage(callerUid:uid,callId:callId,incoming:true,targetUid:data!['targetUid'] as String)));
    }on FirebaseException catch(e){debugPrint('Office call verification failed: ${e.code}');}
    catch(_){debugPrint('Office call presentation failed.');}
    finally{_open=false;}
  }
  static Future<void> _show(BuildContext context,{required String uid,required String callId,required bool incoming,required String targetUid,String? name})async{
    if(_open)return;
    _open=true;
    try{await Navigator.of(context,rootNavigator:true).push<void>(MaterialPageRoute(builder:(_)=>_OfficeCallPage(callerUid:uid,callId:callId,incoming:incoming,targetUid:targetUid,name:name)));}
    finally{_open=false;}
  }
  static Future<http.Response> _worker(String path,Map<String,String> query)async{
    final user=FirebaseAuth.instance.currentUser;
    final token=await user?.getIdToken();
    if(token==null||user==null||FirebaseAuth.instance.currentUser?.uid!=user.uid)throw StateError('Sign in again.');
    const host=String.fromEnvironment('NOTIFICATION_WORKER_URL',defaultValue:'https://suffah-message-notifications.blog-younas.workers.dev');
    final url=Uri.parse(host);
    if(url.scheme!='https')throw StateError('Call service requires HTTPS.');
    return http.post(url.replace(path:path,queryParameters:query),headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:12));
  }
  static Future<List<dynamic>> ice()async{
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null)throw StateError('Sign in again.');
    // Direct connection can work without TURN; relay is strongly recommended.
    try{
      final response=await _worker('/v1/call-ice',{'uid':uid});
      if(response.statusCode==200){
        final result=jsonDecode(response.body);
        if(result is Map&&result['iceServers'] is List)return result['iceServers'] as List;
      }
    }catch(_){}
    return [{'urls':['stun:stun.cloudflare.com:3478']}];
  }
  static Future<void> history(String id)async{try{await _worker('/v1/call-history',{'call':id});}catch(_){}}
  static Future<void> wake(String uid,String id)async{
    try{await _worker('/v1/call-v2-wake',{'uid':uid,'call':id});}catch(_){}
  }
}

class _OfficeCallPage extends StatefulWidget{
  const _OfficeCallPage({required this.callerUid,required this.callId,required this.incoming,required this.targetUid,this.name});
  final String callerUid,callId,targetUid;
  final String? name;
  final bool incoming;
  @override
  State<_OfficeCallPage> createState()=>_OfficeCallPageState();
}
class _OfficeCallPageState extends State<_OfficeCallPage> with WidgetsBindingObserver{
  DocumentReference<Map<String,dynamic>> get ref=>OfficeCalls.ref(widget.callId);
  final me=FirebaseAuth.instance.currentUser?.uid;
  RTCPeerConnection? peer;
  MediaStream? microphone;
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? subscription;
  StreamSubscription<User?>? authSubscription;
  Timer? ticker,connectionTimer;
  final callAudio=SchoolCallAudio();
  bool serviceStarted=false;
  // Serialize native peer operations and teardown. Closing a connection while
  // setRemoteDescription/createAnswer is in flight can race native plugins.
  Future<void> mediaTail=Future<void>.value();
  Future<T> mediaOperation<T>(Future<T> Function() work){
    final next=mediaTail.then((_)=>work());
    mediaTail=next.then<void>((_){},onError:(Object _,StackTrace __){});
    return next;
  }
  Future<void>? closingMedia;
  void trace(String stage){debugPrint('Office call: $stage');}
  void checkOpen(){if(finished||closing)throw StateError('Call closed.');}
  DateTime? connectedAt;
  Map<String,dynamic>? latest;
  String title='School office',status='Preparing call…';
  bool accepting=false,published=false,finished=false,closing=false,remoteSet=false,muted=false,speaker=false;
  bool get mobile=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  @override
  void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    ticker=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted||finished)return;
      final expiry=latest?['expiresAt'];
      if(expiry is Timestamp&&expiry.toDate().isBefore(DateTime.now())){unawaited(end(connectedAt==null?'missed':'ended'));return;}
      setState((){});
    });
    authSubscription=FirebaseAuth.instance.authStateChanges().listen((u){if(u?.uid!=me)unawaited(end('ended',write:false));});
    if(widget.incoming){
      title=widget.targetUid=='office'?'Incoming school call':'School office';status='Incoming voice call';
      watch();unawaited(loadCaller());
      unawaited(callAudio.ring());
    }else{title=widget.name??'School office';unawaited(startCaller());}
  }
  Future<void> loadCaller()async{
    if(widget.targetUid!='office')return;
    try{
      final d=(await FirebaseFirestore.instance.collection('users').doc(widget.callerUid).get()).data();
      if(mounted&&d!=null)setState(()=>title=d['displayName']?.toString()??'School user');
    }catch(_){if(mounted&&widget.targetUid!='office')setState(()=>title='School office');}
  }
  void update(String value){if(mounted&&!finished)setState(()=>status=value);}
  void watch(){
    subscription=ref.snapshots(includeMetadataChanges:true).listen((snapshot){unawaited(handle(snapshot));},onError:(Object e){unawaited(fail('Call signaling unavailable.'));});
  }
  Future<void> handle(DocumentSnapshot<Map<String,dynamic>> snapshot)async{
    if(finished||snapshot.metadata.isFromCache||snapshot.metadata.hasPendingWrites)return;
    final data=snapshot.data();
    if(data==null||data['callId']!=widget.callId){if(published||widget.incoming)await end('ended',write:false);return;}
    latest=data;
    final state=data['status'];
    if(['ended','declined','missed'].contains(state)){
      await end(state.toString(),write:false);return;
    }
    if(widget.incoming&&(state=='answering'||state=='connected')&&data['acceptedBy']!=me){await end('ended',write:false,message:'Answered by another office device.');return;}
    if(state=='answering'||state=='connected')unawaited(callAudio.stop());
    if(!widget.incoming&&state=='answering')update('Answering…');
    if(!widget.incoming&&state=='connected'&&!remoteSet&&peer!=null&&data['answer'] is String){
      remoteSet=true;
      try{
        await mediaOperation(()async{
          checkOpen();
          trace('applying remote answer');
          await peer!.setRemoteDescription(RTCSessionDescription(data['answer'] as String,'answer'));
        });
        if(!finished){if(connectedAt==null)update('Connecting audio…');armConnectionTimeout();}
      }catch(_){if(!finished)await fail('Could not connect audio.');}
    }
    if(mounted&&!finished)setState((){});
  }
  void armConnectionTimeout(){
    if(connectedAt!=null)return;
    connectionTimer?.cancel();
    connectionTimer=Timer(const Duration(seconds:35),(){if(!finished&&connectedAt==null)unawaited(fail('Could not establish audio. Try another network or configure TURN.'));});
  }
  Future<void> markMediaConnected()async{
    try{await FirebaseFirestore.instance.runTransaction((tx)async{
      final d=(await tx.get(ref)).data();
      if(d?['status']=='connected'&&d?['mediaConnectedAt']==null)tx.update(ref,{'mediaConnectedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
    });}catch(_){}
  }
  Future<RTCPeerConnection> prepare()async{
    trace('requesting ICE configuration');
    final ice=await OfficeCalls.ice();
    checkOpen();
    trace('opening microphone');
    final stream=await navigator.mediaDevices.getUserMedia({'audio':true,'video':false});
    microphone=stream;
    checkOpen();
    if(mobile){serviceStarted=await SchoolCallAudio.startService();if(!serviceStarted)debugPrint('Call background service unavailable.');}
    checkOpen();
    trace('creating peer connection');
    final pc=await createPeerConnection({'iceServers':ice,'sdpSemantics':'unified-plan'});
    peer=pc;
    checkOpen();
    pc.onConnectionState=(state){
      if(finished)return;
      trace('peer state $state');
      if(state==RTCPeerConnectionState.RTCPeerConnectionStateConnected){
        connectionTimer?.cancel();
        if(mounted)setState((){connectedAt??=DateTime.now();status='Connected';});
        unawaited(markMediaConnected());
      }else if(state==RTCPeerConnectionState.RTCPeerConnectionStateFailed){unawaited(fail('Audio connection failed.')); }
      else if(state==RTCPeerConnectionState.RTCPeerConnectionStateDisconnected){update('Connection interrupted…');connectionTimer?.cancel();connectionTimer=Timer(const Duration(seconds:20),(){if(!finished)unawaited(fail('Audio connection lost.'));});}
    };
    // Native WebRTC renders remote audio tracks; no video renderer is needed.
    for(final track in stream.getAudioTracks()){checkOpen();await pc.addTrack(track,stream);}
    trace('peer ready');return pc;
  }
  Future<String> gathered(RTCPeerConnection pc,RTCSessionDescription description)async{
    final complete=Completer<void>();
    pc.onIceGatheringState=(state){
      if(state==RTCIceGatheringState.RTCIceGatheringStateComplete&&!complete.isCompleted)complete.complete();
    };
    trace('setting local description');
    await pc.setLocalDescription(description);
    trace('gathering ICE candidates');
    await complete.future.timeout(const Duration(seconds:12),onTimeout:(){});
    if(finished||closing)throw StateError('Call closed.');
    final local=await pc.getLocalDescription();
    final sdp=local?.sdp;
    if(sdp==null||sdp.isEmpty||sdp.length>60000)throw StateError('Could not prepare voice connection.');
    trace('local description ready');
    return sdp;
  }
  Future<void> startCaller()async{
    try{
      update('Preparing microphone and network…');
      final offer=await mediaOperation(()async{
        checkOpen();
        final pc=await prepare();
        checkOpen();
        update('Preparing call connection…');
        trace('creating local offer');
        return gathered(pc,await pc.createOffer({'offerToReceiveAudio':true,'offerToReceiveVideo':false}));
      });
      if(finished||closing)return;
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final expiry=Timestamp.fromDate(DateTime.now().add(const Duration(seconds:60)));
        if(closing||finished)throw StateError('Call closed.');
        tx.set(ref,{'callerUid':widget.callerUid,'targetUid':widget.targetUid,'threadUid':widget.targetUid=='office'?widget.callerUid:widget.targetUid,'callId':widget.callId,'status':'ringing','offer':offer,'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp(),'expiresAt':expiry,'historyDueAt':expiry});
      });
      published=true;
      if(finished||closing){await finishRemote('ended');return;}
      latest={'expiresAt':Timestamp.fromDate(DateTime.now().add(const Duration(seconds:60)))};
      update('Ringing…');watch();unawaited(callAudio.ring(outgoing:true));
      unawaited(OfficeCalls.wake(widget.callerUid,widget.callId));
    }catch(e){if(!finished&&!closing)await fail('Could not start call: $e');}
  }
  Future<void> accept()async{
    if(accepting||finished||closing)return;
    setState((){accepting=true;status='Answering…';});await callAudio.stop();
    try{
      final offer=await FirebaseFirestore.instance.runTransaction<String>((tx)async{
        final d=(await tx.get(ref)).data();
        if(!OfficeCalls.fresh(d)||d?['callId']!=widget.callId||d?['offer'] is! String)throw StateError('This call is no longer ringing.');
        final expiry=Timestamp.fromDate(DateTime.now().add(const Duration(minutes:55)));
        tx.update(ref,{'status':'answering','acceptedBy':me,'updatedAt':FieldValue.serverTimestamp(),'expiresAt':expiry,'historyDueAt':expiry});
        return d!['offer'] as String;
      });
      published=true;
      if(finished||closing){await finishRemote('ended');return;}
      final answer=await mediaOperation(()async{
        checkOpen();
        final pc=await prepare();
        checkOpen();
        trace('applying remote offer');
        await pc.setRemoteDescription(RTCSessionDescription(offer,'offer'));
        checkOpen();
        trace('creating local answer');
        return gathered(pc,await pc.createAnswer({'offerToReceiveAudio':true,'offerToReceiveVideo':false}));
      });
      if(finished||closing)return;
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final d=(await tx.get(ref)).data();
        if(d?['callId']!=widget.callId||d?['status']!='answering'||d?['acceptedBy']!=me)throw StateError('Call was cancelled.');
        tx.update(ref,{'status':'connected','answer':answer,'updatedAt':FieldValue.serverTimestamp()});
      });
      if(connectedAt==null)update('Connecting audio…');else unawaited(markMediaConnected());armConnectionTimeout();
    }catch(e){if(!finished&&!closing)await fail('Could not answer call: $e');}
  }
  Future<void> finishRemote(String state)async{
    try{
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final d=(await tx.get(ref)).data();
        if(d?['callId']!=widget.callId||!['ringing','answering','connected'].contains(d?['status']))return;
        if(widget.incoming&&d?['status']!='ringing'&&d?['acceptedBy']!=me)return;
        tx.update(ref,{'status':state,'updatedAt':FieldValue.serverTimestamp(),'historyDueAt':FieldValue.serverTimestamp(),'offer':FieldValue.delete(),'answer':FieldValue.delete()});
      }).timeout(const Duration(seconds:5));
      unawaited(OfficeCalls.history(widget.callId));
    }catch(_){}
  }
  Future<void> closeMedia()=>closingMedia??=mediaOperation(()async{
    trace('closing media');
    await callAudio.stop();
    final pc=peer;peer=null;
    final stream=microphone;microphone=null;
    // Stop callbacks before disposing native objects. Keep the source alive
    // until the peer has released its references to the audio tracks.
    if(pc!=null){
      pc.onConnectionState=null;
      pc.onIceGatheringState=null;
      try{await pc.close();}catch(_){trace('peer close failed');}
      try{await pc.dispose();}catch(_){trace('peer dispose failed');}
    }
    if(stream!=null){
      for(final track in stream.getTracks()){try{await track.stop();}catch(_){}}
      try{await stream.dispose();}catch(_){trace('microphone dispose failed');}
    }
    if(mobile){
      try{await Helper.setSpeakerphoneOn(false);}catch(_){}
      if(serviceStarted){await SchoolCallAudio.stopService();serviceStarted=false;}
    }
    trace('media closed');
  });
  Future<void> fail(String message)=>end('ended',message:message);
  Future<void> end(String state,{bool write=true,String? message})async{
    if(finished||closing)return;
    closing=true;
    connectionTimer?.cancel();
    if(mounted)setState((){finished=true;status=message??(state=='missed'?'No answer':state=='declined'?'Call declined':'Call ended');});
    // Release remote ringing immediately even if a native operation is slow.
    final remote=write&&(published||widget.incoming)?finishRemote(state):Future<void>.value();
    await closeMedia();
    await remote;
    if(mounted)setState(()=>closing=false);else closing=false;
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.detached||(mobile&&state==AppLifecycleState.paused&&!serviceStarted)){unawaited(end('ended'));}
  }
  void toggleMute(){
    if(microphone==null)return;
    setState(()=>muted=!muted);
    unawaited(mediaOperation(()async{if(finished)return;for(final track in microphone?.getAudioTracks()??<MediaStreamTrack>[]){track.enabled=!muted;}}).catchError((Object _){trace('mute update failed');}));
  }
  Future<void> toggleSpeaker()async{
    try{await mediaOperation(()async{if(!finished){await Helper.setSpeakerphoneOn(!speaker);if(mounted&&!finished)setState(()=>speaker=!speaker);}});}catch(_){}
  }
  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);ticker?.cancel();connectionTimer?.cancel();
    unawaited(subscription?.cancel()??Future<void>.value());unawaited(authSubscription?.cancel()??Future<void>.value());
    if(!finished){finished=true;if(published||widget.incoming)unawaited(finishRemote('ended'));}
    unawaited(closeMedia().whenComplete(callAudio.dispose));
    super.dispose();
  }
  String get elapsed{
    final seconds=DateTime.now().difference(connectedAt??DateTime.now()).inSeconds.clamp(0,3600).toInt();
    return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
  }
  Widget action(IconData icon,String label,VoidCallback? tap,{Color color=const Color(0xff45635c)}){
    return Column(mainAxisSize:MainAxisSize.min,children:[
      SizedBox(width:64,height:64,child:IconButton.filled(style:IconButton.styleFrom(backgroundColor:color,foregroundColor:Colors.white),onPressed:tap,icon:Icon(icon,size:28))),
      const SizedBox(height:8),Text(label,style:const TextStyle(color:Colors.white70)),
    ]);
  }
  @override
  Widget build(BuildContext context){
    final ringing=widget.incoming&&!accepting&&!finished;
    final other=widget.incoming?widget.callerUid:widget.targetUid;
    return PopScope(canPop:finished,onPopInvokedWithResult:(didPop,_){if(!didPop)unawaited(end('ended'));},child:Scaffold(
      backgroundColor:const Color(0xff102e28),
      body:SafeArea(child:LayoutBuilder(builder:(context,limits)=>SingleChildScrollView(child:Center(child:ConstrainedBox(constraints:BoxConstraints(maxWidth:560,minHeight:limits.maxHeight),child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.lock_outline,size:14,color:Colors.white54),SizedBox(width:8),Text('School voice call',style:TextStyle(color:Colors.white70))]),
        const SizedBox(height:40),
        AccountPicture(uid:other=='office'?'':other,name:title,radius:64),
        const SizedBox(height:24),Text(title,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w600,color:Colors.white),textAlign:TextAlign.center),
        const SizedBox(height:12),Text(connectedAt!=null&&!finished?elapsed:status,style:const TextStyle(color:Colors.white70,fontSize:16),textAlign:TextAlign.center),
        const SizedBox(height:56),
        if(finished)FilledButton(onPressed:closing?null:()=>Navigator.pop(context),child:const Text('Close'))
        else if(ringing)Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
          action(Icons.call_end,'Decline',()=>end('declined'),color:const Color(0xffd13f43)),
          action(Icons.call,'Accept',accept,color:const Color(0xff259e65)),
        ])
        else Wrap(spacing:24,runSpacing:16,alignment:WrapAlignment.center,children:[
          action(muted?Icons.mic_off:Icons.mic,muted?'Unmute':'Mute',microphone==null?null:toggleMute,color:muted?const Color(0xff78988f):const Color(0xff45635c)),
          if(mobile)action(speaker?Icons.volume_up:Icons.volume_down,'Speaker',toggleSpeaker,color:speaker?const Color(0xff78988f):const Color(0xff45635c)),
          action(Icons.call_end,'End call',()=>end('ended'),color:const Color(0xffd13f43)),
        ]),
        const SizedBox(height:24),const Text('Internet call · Audio is not recorded',style:TextStyle(color:Colors.white54,fontSize:12)),
      ])))))))));
  }
}
