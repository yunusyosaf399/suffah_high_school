import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

/// Audio is transported by WebRTC, never uploaded as a voice recording.
/// Firestore contains only signaling and session state.
class OfficeCalls {
  static bool _open=false;
  static DocumentReference<Map<String,dynamic>> ref(String uid)=>FirebaseFirestore.instance.collection('office_calls').doc(uid);
  static Query<Map<String,dynamic>> get incoming=>FirebaseFirestore.instance.collection('office_calls').where('status',isEqualTo:'ringing').limit(25);
  static bool fresh(Map<String,dynamic>? data){
    final expiry=data?['expiresAt'];
    return data?['status']=='ringing'&&expiry is Timestamp&&expiry.toDate().isAfter(DateTime.now());
  }
  static Future<void> dial(BuildContext context)async{
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null||_open)return;
    await _show(context,uid:uid,callId:FirebaseFirestore.instance.collection('office_calls').doc().id,incoming:false);
  }
  static Future<void> receive(BuildContext context,String uid,String callId)async{
    if(_open||!context.mounted)return;
    _open=true;
    try{
      final data=(await ref(uid).get(const GetOptions(source:Source.server))).data();
      if(!context.mounted||!fresh(data)||data?['callId']!=callId)return;
      await Navigator.of(context,rootNavigator:true).push<void>(MaterialPageRoute(builder:(_)=>_OfficeCallPage(callerUid:uid,callId:callId,incoming:true)));
    }catch(_){/* A stale notification or a revoked permission cannot start a call. */}
    finally{_open=false;}
  }
  static Future<void> _show(BuildContext context,{required String uid,required String callId,required bool incoming})async{
    if(_open)return;
    _open=true;
    try{await Navigator.of(context,rootNavigator:true).push<void>(MaterialPageRoute(builder:(_)=>_OfficeCallPage(callerUid:uid,callId:callId,incoming:incoming)));}
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
  static Future<void> wake(String uid,String id)async{
    try{await _worker('/v1/call-wake',{'uid':uid,'call':id});}catch(_){}
  }
}

class _OfficeCallPage extends StatefulWidget{
  const _OfficeCallPage({required this.callerUid,required this.callId,required this.incoming});
  final String callerUid,callId;
  final bool incoming;
  @override
  State<_OfficeCallPage> createState()=>_OfficeCallPageState();
}
class _OfficeCallPageState extends State<_OfficeCallPage> with WidgetsBindingObserver{
  DocumentReference<Map<String,dynamic>> get ref=>OfficeCalls.ref(widget.callerUid);
  final me=FirebaseAuth.instance.currentUser?.uid;
  RTCPeerConnection? peer;
  MediaStream? microphone;
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? subscription;
  StreamSubscription<User?>? authSubscription;
  Timer? ticker,ringTimer,connectionTimer;
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
      title='Incoming school call';status='Incoming voice call';
      watch();unawaited(loadCaller());
      ringTimer=Timer.periodic(const Duration(seconds:3),(_){if(mounted&&!accepting&&!finished&&latest?['status']=='ringing')unawaited(SystemSound.play(SystemSoundType.alert));});
    }else{unawaited(startCaller());}
  }
  Future<void> loadCaller()async{
    try{
      final d=(await FirebaseFirestore.instance.collection('users').doc(widget.callerUid).get()).data();
      if(mounted&&d!=null)setState(()=>title=d['displayName']?.toString()??'School user');
    }catch(_){}
  }
  void update(String value){if(mounted&&!finished)setState(()=>status=value);}
  void watch(){
    subscription=ref.snapshots().listen((snapshot){unawaited(handle(snapshot));},onError:(Object e){unawaited(fail('Call signaling unavailable.'));});
  }
  Future<void> handle(DocumentSnapshot<Map<String,dynamic>> snapshot)async{
    if(finished||snapshot.metadata.isFromCache)return;
    final data=snapshot.data();
    if(data==null||data['callId']!=widget.callId){if(published||widget.incoming)await end('ended',write:false);return;}
    latest=data;
    final state=data['status'];
    if(['ended','declined','missed'].contains(state)){
      await end(state.toString(),write:false);return;
    }
    if(widget.incoming&&(state=='answering'||state=='connected')&&data['acceptedBy']!=me){await end('ended',write:false,message:'Answered by another office device.');return;}
    if(!widget.incoming&&state=='answering')update('Office is answering…');
    if(!widget.incoming&&state=='connected'&&!remoteSet&&peer!=null&&data['answer'] is String){
      remoteSet=true;
      try{await peer!.setRemoteDescription(RTCSessionDescription(data['answer'] as String,'answer'));update('Connecting audio…');armConnectionTimeout();}
      catch(_){await fail('Could not connect audio.');}
    }
    if(mounted&&!finished)setState((){});
  }
  void armConnectionTimeout(){
    if(connectedAt!=null)return;
    connectionTimer?.cancel();
    connectionTimer=Timer(const Duration(seconds:35),(){if(!finished&&connectedAt==null)unawaited(fail('Could not establish audio. Try another network or configure TURN.'));});
  }
  Future<RTCPeerConnection> prepare()async{
    final ice=await OfficeCalls.ice();
    if(finished||closing)throw StateError('Call closed.');
    final stream=await navigator.mediaDevices.getUserMedia({'audio':true,'video':false});
    if(finished||closing){for(final track in stream.getTracks()){await track.stop();}await stream.dispose();throw StateError('Call closed.');}
    microphone=stream;
    final pc=await createPeerConnection({'iceServers':ice,'sdpSemantics':'unified-plan'});
    if(finished||closing){await pc.close();await pc.dispose();throw StateError('Call closed.');}
    peer=pc;
    pc.onConnectionState=(state){
      if(finished)return;
      if(state==RTCPeerConnectionState.RTCPeerConnectionStateConnected){
        connectionTimer?.cancel();
        if(mounted)setState((){connectedAt??=DateTime.now();status='Connected';});
      }else if(state==RTCPeerConnectionState.RTCPeerConnectionStateFailed){unawaited(fail('Audio connection failed.')); }
      else if(state==RTCPeerConnectionState.RTCPeerConnectionStateDisconnected){update('Connection interrupted…');connectionTimer?.cancel();connectionTimer=Timer(const Duration(seconds:20),(){if(!finished)unawaited(fail('Audio connection lost.'));});}
    };
    // Native WebRTC renders remote audio tracks; no video renderer is needed.
    for(final track in stream.getAudioTracks()){await pc.addTrack(track,stream);}
    return pc;
  }
  Future<String> gathered(RTCPeerConnection pc,RTCSessionDescription description)async{
    final complete=Completer<void>();
    pc.onIceGatheringState=(state){
      if(state==RTCIceGatheringState.RTCIceGatheringStateComplete&&!complete.isCompleted)complete.complete();
    };
    await pc.setLocalDescription(description);
    await complete.future.timeout(const Duration(seconds:12),onTimeout:(){});
    if(finished||closing)throw StateError('Call closed.');
    final local=await pc.getLocalDescription();
    final sdp=local?.sdp;
    if(sdp==null||sdp.isEmpty||sdp.length>60000)throw StateError('Could not prepare voice connection.');
    return sdp;
  }
  Future<void> startCaller()async{
    try{
      final pc=await prepare();
      final offer=await gathered(pc,await pc.createOffer({'offerToReceiveAudio':true,'offerToReceiveVideo':false}));
      if(finished||closing)return;
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final old=(await tx.get(ref)).data();
        final expiry=old?['expiresAt'];
        if(old!=null&&!['ended','declined','missed'].contains(old['status'])&&expiry is Timestamp&&expiry.toDate().isAfter(DateTime.now()))throw StateError('You already have an active call.');
        if(closing||finished)throw StateError('Call closed.');
        tx.set(ref,{'callerUid':widget.callerUid,'callId':widget.callId,'status':'ringing','offer':offer,'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp(),'expiresAt':Timestamp.fromDate(DateTime.now().add(const Duration(seconds:60)))});
      });
      published=true;
      if(finished||closing){await finishRemote('ended');return;}
      update('Calling school office…');watch();
      unawaited(OfficeCalls.wake(widget.callerUid,widget.callId));
    }catch(e){if(!finished&&!closing)await fail('Could not start call: $e');}
  }
  Future<void> accept()async{
    if(accepting||finished||closing)return;
    setState((){accepting=true;status='Answering…';});ringTimer?.cancel();
    try{
      final offer=await FirebaseFirestore.instance.runTransaction<String>((tx)async{
        final d=(await tx.get(ref)).data();
        if(!OfficeCalls.fresh(d)||d?['callId']!=widget.callId||d?['offer'] is! String)throw StateError('This call is no longer ringing.');
        tx.update(ref,{'status':'answering','acceptedBy':me,'updatedAt':FieldValue.serverTimestamp(),'expiresAt':Timestamp.fromDate(DateTime.now().add(const Duration(minutes:55)))});
        return d!['offer'] as String;
      });
      published=true;
      if(finished||closing){await finishRemote('ended');return;}
      final pc=await prepare();
      await pc.setRemoteDescription(RTCSessionDescription(offer,'offer'));
      final answer=await gathered(pc,await pc.createAnswer({'offerToReceiveAudio':true,'offerToReceiveVideo':false}));
      if(finished||closing)return;
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final d=(await tx.get(ref)).data();
        if(d?['callId']!=widget.callId||d?['status']!='answering'||d?['acceptedBy']!=me)throw StateError('Call was cancelled.');
        tx.update(ref,{'status':'connected','answer':answer,'updatedAt':FieldValue.serverTimestamp()});
      });
      if(connectedAt==null)update('Connecting audio…');armConnectionTimeout();
    }catch(e){if(!finished&&!closing)await fail('Could not answer call: $e');}
  }
  Future<void> finishRemote(String state)async{
    try{
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final d=(await tx.get(ref)).data();
        if(d?['callId']!=widget.callId||!['ringing','answering','connected'].contains(d?['status']))return;
        if(widget.incoming&&d?['status']!='ringing'&&d?['acceptedBy']!=me)return;
        tx.update(ref,{'status':state,'updatedAt':FieldValue.serverTimestamp(),'offer':FieldValue.delete(),'answer':FieldValue.delete()});
      }).timeout(const Duration(seconds:5));
    }catch(_){}
  }
  Future<void> closeMedia()async{
    final pc=peer;peer=null;final stream=microphone;microphone=null;
    if(stream!=null){for(final track in stream.getTracks()){try{await track.stop();}catch(_){}}try{await stream.dispose();}catch(_){}}
    if(pc!=null){try{await pc.close();await pc.dispose();}catch(_){}}
    if(mobile){try{await Helper.setSpeakerphoneOn(false);}catch(_){}}
  }
  Future<void> fail(String message)=>end('ended',message:message);
  Future<void> end(String state,{bool write=true,String? message})async{
    if(finished||closing)return;
    closing=true;
    ringTimer?.cancel();connectionTimer?.cancel();
    if(mounted)setState((){finished=true;status=message??(state=='missed'?'No answer':state=='declined'?'Call declined':'Call ended');});
    await closeMedia();
    if(write&&(published||widget.incoming))await finishRemote(state);
    if(mounted)setState(()=>closing=false);else closing=false;
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused||state==AppLifecycleState.detached){unawaited(end('ended'));}
  }
  void toggleMute(){
    if(microphone==null)return;
    setState(()=>muted=!muted);
    for(final track in microphone!.getAudioTracks()){track.enabled=!muted;}
  }
  Future<void> toggleSpeaker()async{
    try{await Helper.setSpeakerphoneOn(!speaker);if(mounted)setState(()=>speaker=!speaker);}catch(_){}
  }
  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);ticker?.cancel();ringTimer?.cancel();connectionTimer?.cancel();
    unawaited(subscription?.cancel()??Future<void>.value());unawaited(authSubscription?.cancel()??Future<void>.value());
    if(!finished){finished=true;if(published||widget.incoming)unawaited(finishRemote('ended'));unawaited(closeMedia());}
    super.dispose();
  }
  String get elapsed{
    final seconds=DateTime.now().difference(connectedAt??DateTime.now()).inSeconds.clamp(0,3600).toInt();
    return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
  }
  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final ringing=widget.incoming&&!accepting&&!finished;
    return PopScope(canPop:finished,onPopInvokedWithResult:(didPop,_){if(!didPop)unawaited(end('ended'));},child:Scaffold(
      appBar:AppBar(title:const Text('School office call'),automaticallyImplyLeading:false),
      body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        CircleAvatar(radius:54,backgroundColor:scheme.primaryContainer,child:Icon(Icons.phone_in_talk,size:48,color:scheme.onPrimaryContainer)),
        const SizedBox(height:24),Text(title,style:Theme.of(context).textTheme.headlineSmall,textAlign:TextAlign.center),
        const SizedBox(height:12),Text(status,textAlign:TextAlign.center),
        if(connectedAt!=null&&!finished)Padding(padding:const EdgeInsets.all(12),child:Text(elapsed,style:Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height:32),
        if(finished)FilledButton(onPressed:closing?null:()=>Navigator.pop(context),child:const Text('Close'))
        else if(ringing)Wrap(spacing:24,children:[
          FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:scheme.error,foregroundColor:scheme.onError),onPressed:()=>end('declined'),icon:const Icon(Icons.call_end),label:const Text('Decline')),
          FilledButton.icon(onPressed:accept,icon:const Icon(Icons.call),label:const Text('Accept')),
        ])
        else Wrap(spacing:16,runSpacing:12,alignment:WrapAlignment.center,children:[
          OutlinedButton.icon(onPressed:microphone==null?null:toggleMute,icon:Icon(muted?Icons.mic_off:Icons.mic),label:Text(muted?'Unmute':'Mute')),
          if(mobile)OutlinedButton.icon(onPressed:toggleSpeaker,icon:Icon(speaker?Icons.volume_up:Icons.volume_down),label:const Text('Speaker')),
          FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:scheme.error,foregroundColor:scheme.onError),onPressed:()=>end('ended'),icon:const Icon(Icons.call_end),label:const Text('End call')),
        ]),
        const SizedBox(height:24),Text('Internet voice call · audio is not recorded',style:Theme.of(context).textTheme.bodySmall),
      ]))))));
  }
}
