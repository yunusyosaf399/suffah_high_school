import 'dart:async';
import '../data/voice_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'school_messages_page.dart';
import 'office_calls.dart';
import 'call_audio.dart';
import 'incoming_call_notifications.dart';
import '../data/teacher_portal_repository.dart';

typedef _Alerts=QuerySnapshot<Map<String,dynamic>>;

class MessageNotificationBell extends StatefulWidget {
  const MessageNotificationBell({super.key,this.admin=false});
  final bool admin;
  @override
  State<MessageNotificationBell> createState()=>_MessageNotificationBellState();
}
class _MessageNotificationBellState extends State<MessageNotificationBell> with WidgetsBindingObserver{
  String? uid;
  Timer? cacheTimer;
  StreamSubscription<_Alerts>? callSub;
  Timer? callPollTimer;
  List<QueryDocumentSnapshot<Map<String,dynamic>>> ringingCalls=[];
  String callReceiverStatus='Connecting to call receiver…';
  bool callChecking=false;
  bool get desktop=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.windows;
  bool get canReceiveCalls=>mounted&&FirebaseAuth.instance.currentUser?.uid==uid
    &&OfficeCalls.canPresent(WidgetsBinding.instance.lifecycleState,desktop:desktop);
  void receiverStatus(String value){
    if(mounted&&callReceiverStatus!=value)setState(()=>callReceiverStatus=value);
  }
  void showIncoming(){
    if(!canReceiveCalls||OfficeCalls.isOpen)return;
    for(final call in ringingCalls){
      final data=call.data();
      if(OfficeCalls.fresh(data)&&data['callId'] is String&&data['callerUid'] is String){
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(canReceiveCalls&&!OfficeCalls.isOpen)unawaited(OfficeCalls.receive(context,data['callerUid'] as String,data['callId'] as String));
        });
        WidgetsBinding.instance.ensureVisualUpdate();
        break;
      }
    }
  }
  void observeCalls(){
    if(!mounted||uid==null)return;
    final previous=callSub;
    if(previous!=null)unawaited(previous.cancel());
    callSub=OfficeCalls.incoming(widget.admin?'office':uid!).snapshots(includeMetadataChanges:true).listen((s){
      if(!mounted)return;
      // Cache events are useful hints; receive() revalidates on the server
      // before presenting a call. Metadata updates confirm connectivity.
      ringingCalls=s.docs;
      if(!s.metadata.isFromCache)receiverStatus('Office call receiver online');
      showIncoming();
    },onError:(Object e){
      receiverStatus(e is FirebaseException?'Call receiver: ${e.code}':'Call receiver unavailable');
      debugPrint('Office call listener failed.');
    });
  }
  Future<void> checkCalls({bool manual=false})async{
    if(!canReceiveCalls||callChecking||(!manual&&OfficeCalls.isOpen))return;
    callChecking=true;
    try{
      final s=await OfficeCalls.incoming(widget.admin?'office':uid!).get(const GetOptions(source:Source.server)).timeout(const Duration(seconds:12));
      if(!mounted)return;
      ringingCalls=s.docs;
      receiverStatus('Office call receiver online');
      showIncoming();
      if(manual&&mounted&&!ringingCalls.any((d)=>OfficeCalls.fresh(d.data())))ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Call receiver is online. No incoming call right now.')));
    }catch(e){
      receiverStatus(e is FirebaseException?'Call receiver: ${e.code}':'Call receiver cannot reach server');
      if(manual&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(callReceiverStatus)));
    }finally{callChecking=false;}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){showIncoming();unawaited(checkCalls());}
  }
  Stream<_Alerts>? stream;
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? readSub;
  StreamSubscription<String>? tokenSub;
  StreamSubscription<_Alerts>? deliverySub;
  final Set<String> acknowledged={};
  StreamSubscription<RemoteMessage>? pushSub,foregroundPushSub;
  StreamSubscription<Map<String,dynamic>>? localCallSub;
  Timestamp? readThrough;
  bool ready=false;
  bool fullscreenCapable=false;
  bool opening=false;
  bool get mobile=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  DocumentReference<Map<String,dynamic>> get readRef=>FirebaseFirestore.instance.collection('message_alert_reads').doc(uid!);
  @override
  void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    try{
      uid=FirebaseAuth.instance.currentUser?.uid;
      if(uid==null)return;
      {
        observeCalls();
        // Windows may miss native snapshot callbacks. A small server poll
        // is a fallback while the office dashboard is running.
        if(desktop)callPollTimer=Timer.periodic(const Duration(seconds:20),(_)=>unawaited(checkCalls()));
        WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(checkCalls());});
      }
      unawaited(VoiceCache.prune(uid!));
      cacheTimer=Timer.periodic(const Duration(minutes:1),(_){if(mounted&&uid!=null)unawaited(VoiceCache.prune(uid!));});
      Query<Map<String,dynamic>> q=FirebaseFirestore.instance.collection('message_alerts').where('fromSchool',isEqualTo:!widget.admin);
      if(!widget.admin)q=q.where('threadUid',isEqualTo:uid);
      stream=q.orderBy('createdAt',descending:true).limit(100).snapshots();
      deliverySub=stream!.listen((s){
        for(final d in s.docs){
          if(acknowledged.add(d.id))unawaited(ackDelivery(d.id,d.data()));
        }
      },onError:(Object e){});
      readSub=readRef.snapshots().listen((s){
        if(!mounted)return;
        final t=s.data()?['readThrough'];
        setState((){readThrough=t is Timestamp?t:null;ready=true;});
      },onError:(Object e){if(mounted)setState(()=>ready=true);});
      if(mobile)unawaited(register());
    }catch(_){}
  }
  Future<void> ackDelivery(String id,Map<String,dynamic> data)async{
    try{
      if(!mounted||uid==null||FirebaseAuth.instance.currentUser?.uid!=uid)return;
      final thread=data['threadUid'];if(thread is! String)return;
      await SchoolMessageRepository().receipt(thread,id);
    }catch(_){acknowledged.remove(id);}
  }
  Future<void> register()async{
    try{
      final messaging=FirebaseMessaging.instance;
      await IncomingCallNotifications.registerAccount(uid!);
      if(!mounted)return;
      localCallSub=IncomingCallNotifications.opened.stream.listen(openLocalCall);
      fullscreenCapable=await IncomingCallNotifications.initialize();
      if(!mounted)return;
      final launch=await IncomingCallNotifications.launchPayload();
      if(launch!=null&&mounted)openLocalCall(launch);
      foregroundPushSub=FirebaseMessaging.onMessage.listen((m){
        if(m.data['type']=='office_call_v2')openLocalCall(m.data);
      });
      final permission=await messaging.requestPermission(alert:true,badge:true,sound:true);
      if(!mounted||permission.authorizationStatus==AuthorizationStatus.denied)return;
      final token=await messaging.getToken();
      if(!mounted)return;
      if(token!=null)await saveToken(token);
      if(!mounted)return;
      tokenSub=messaging.onTokenRefresh.listen((t)=>unawaited(saveToken(t)));
      pushSub=FirebaseMessaging.onMessageOpenedApp.listen(openPush);
      final initial=await messaging.getInitialMessage();
      if(initial!=null&&mounted)openPush(initial);
    }catch(_){/* The Firestore dashboard still works when push is unavailable. */}
  }
  Future<void> saveToken(String token)async{
    try{
      if(!mounted||uid==null||FirebaseAuth.instance.currentUser?.uid!=uid)return;
      final channel=await SchoolCallAudio.channelId();
      if(!mounted||FirebaseAuth.instance.currentUser?.uid!=uid)return;
      await FirebaseFirestore.instance.collection('push_devices').doc(token).set({
        'uid':uid,'updatedAt':FieldValue.serverTimestamp(),'callChannel':channel,'callFullscreen':fullscreenCapable,
      });
    }catch(_){}
  }
  void openLocalCall(Map<String,dynamic> data){
    if(!mounted||FirebaseAuth.instance.currentUser?.uid!=uid||data['recipientUid']!=uid)return;
    final caller=data['callerUid'],call=data['callId'];
    if(caller is String&&call is String)unawaited(OfficeCalls.receive(context,caller,call));
  }
  void openPush(RemoteMessage message){
    // The worker supplies no private content; the account dashboard and
    // conversation queries are independently authorized by Firestore.
    if(!mounted||FirebaseAuth.instance.currentUser?.uid!=uid||message.data['recipientUid']!=uid)return;
    if(message.data['type']=='office_call_v2'){
      final caller=message.data['callerUid'],call=message.data['callId'];
      if(caller is String&&call is String)unawaited(OfficeCalls.receive(context,caller,call));
      return;
    }
    if(message.data['type']!='school_message')return;
    openChat(widget.admin?message.data['threadUid']:null);
  }
  Future<void> openChat(String? thread)async{
    if(!mounted||opening)return;
    opening=true;
    try{await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>SchoolMessagesPage(admin:widget.admin,threadUid:widget.admin?thread:null)));}
    finally{opening=false;}
  }
  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);callSub?.cancel();callPollTimer?.cancel();
    cacheTimer?.cancel();
    readSub?.cancel();tokenSub?.cancel();pushSub?.cancel();foregroundPushSub?.cancel();localCallSub?.cancel();deliverySub?.cancel();
    super.dispose();
  }
  bool unread(Map<String,dynamic> data){
    final t=data['createdAt'];
    return t is Timestamp&&(readThrough==null||t.compareTo(readThrough!)>0);
  }
  Future<void> markAll()async{
    try{await readRef.set({'readThrough':FieldValue.serverTimestamp()});}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not mark notifications as read.')));}
  }
  void history(){
    showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:SizedBox(
      height:MediaQuery.sizeOf(ctx).height*.65,child:Column(children:[
        ListTile(title:const Text('Message notifications'),trailing:TextButton(onPressed:markAll,child:const Text('Mark all read'))),
        Expanded(child:StreamBuilder<_Alerts>(stream:stream,builder:(context,s){
          if(s.hasError)return const Center(child:Text('Notification history is unavailable.'));
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final docs=s.data!.docs;
          if(docs.isEmpty)return const Center(child:Text('No new-message notifications yet.'));
          return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:readRef.snapshots(),builder:(context,read){
            final through=read.data?.data()?['readThrough'];
            return ListView.builder(itemCount:docs.length,itemBuilder:(context,i){
              final d=docs[i].data(),t=d['createdAt'];
              final fresh=t is Timestamp&&(through is! Timestamp||t.compareTo(through)>0);
              final stamp=t is Timestamp?t.toDate().toLocal():null;
              final l=MaterialLocalizations.of(context);
              return ListTile(leading:Icon(fresh?Icons.mark_chat_unread:Icons.chat_bubble_outline),
                title:const Text('New school message'),
                subtitle:Text(stamp==null?'':l.formatShortDate(stamp)+' · '+l.formatTimeOfDay(TimeOfDay.fromDateTime(stamp))),
                onTap:(){Navigator.pop(ctx);openChat(d['threadUid']?.toString());});
            });
          });
        }))
      ]))));
  }
  @override
  Widget build(BuildContext context){
    if(stream==null)return const SizedBox.shrink();
    return StreamBuilder<_Alerts>(stream:stream,builder:(context,s){
      final count=ready?(s.data?.docs.where((d)=>unread(d.data())).length??0):0;
      return Row(mainAxisSize:MainAxisSize.min,children:[
        if(widget.admin)IconButton(tooltip:callReceiverStatus,onPressed:()=>checkCalls(manual:true),icon:Icon(callReceiverStatus=='Office call receiver online'?Icons.phone_in_talk_outlined:Icons.phone_disabled_outlined)),
        if(!widget.admin)IconButton(tooltip:'Call school office',onPressed:()=>OfficeCalls.dial(context),icon:const Icon(Icons.call_outlined)),
        IconButton(tooltip:'Message notifications',onPressed:history,icon:Badge(
          isLabelVisible:count>0,label:Text(count>=100?'99+':'$count'),child:const Icon(Icons.notifications_outlined))),
      ]);
    });
  }
}

/// Called before explicit sign-out, to avoid delivery to a shared phone.
Future<void> signOutSchool()async{
  final account=FirebaseAuth.instance.currentUser?.uid;
  if(account!=null)await VoiceCache.clear(account);
  if(!kIsWeb&&defaultTargetPlatform==TargetPlatform.android){
    await IncomingCallNotifications.clearAccount();
    try{
      final messaging=FirebaseMessaging.instance;
      final token=await messaging.getToken();
      if(token!=null){
        await FirebaseFirestore.instance.collection('push_devices').doc(token).delete().timeout(const Duration(seconds:3));
      }
    }catch(_){}
    try{await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds:3));}catch(_){}
  }
  await FirebaseAuth.instance.signOut();
}
