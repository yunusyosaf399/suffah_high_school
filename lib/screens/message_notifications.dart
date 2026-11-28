import 'dart:async';
import '../data/voice_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'school_messages_page.dart';
import 'office_calls.dart';
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
  List<QueryDocumentSnapshot<Map<String,dynamic>>> ringingCalls=[];
  void showIncoming(){
    if(!mounted||!widget.admin||WidgetsBinding.instance.lifecycleState!=AppLifecycleState.resumed)return;
    for(final call in ringingCalls){
      final data=call.data();
      if(OfficeCalls.fresh(data)&&data['callId'] is String){unawaited(OfficeCalls.receive(context,call.id,data['callId'] as String));break;}
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)showIncoming();}
  Stream<_Alerts>? stream;
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? readSub;
  StreamSubscription<String>? tokenSub;
  StreamSubscription<_Alerts>? deliverySub;
  final Set<String> acknowledged={};
  StreamSubscription<RemoteMessage>? pushSub;
  Timestamp? readThrough;
  bool ready=false;
  bool opening=false;
  bool get mobile=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  DocumentReference<Map<String,dynamic>> get readRef=>FirebaseFirestore.instance.collection('message_alert_reads').doc(uid!);
  @override
  void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    try{
      uid=FirebaseAuth.instance.currentUser?.uid;
      if(uid==null)return;
      if(widget.admin)callSub=OfficeCalls.incoming.snapshots().listen((s){if(s.metadata.isFromCache)return;ringingCalls=s.docs;showIncoming();},onError:(Object e){});
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
      await FirebaseFirestore.instance.collection('push_devices').doc(token).set({
        'uid':uid,'updatedAt':FieldValue.serverTimestamp(),
      });
    }catch(_){}
  }
  void openPush(RemoteMessage message){
    // The worker supplies no private content; the account dashboard and
    // conversation queries are independently authorized by Firestore.
    if(!mounted||FirebaseAuth.instance.currentUser?.uid!=uid||message.data['recipientUid']!=uid)return;
    if(widget.admin&&message.data['type']=='office_call'){
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
    WidgetsBinding.instance.removeObserver(this);callSub?.cancel();
    cacheTimer?.cancel();
    readSub?.cancel();tokenSub?.cancel();pushSub?.cancel();deliverySub?.cancel();
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
