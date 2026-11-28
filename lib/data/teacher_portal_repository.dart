import 'dart:io';
import 'voice_cache.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Online-first, role-scoped reads. Firestore rules enforce the same limits
/// independently of the Flutter client. No Cloud Function is required.
class TeacherPortalRepository {
  TeacherPortalRepository({FirebaseFirestore? db,FirebaseAuth? auth})
      :_db=db??FirebaseFirestore.instance,_auth=auth??FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const _server=GetOptions(source:Source.server);
  static const _limit=1000;
  Future<Map<String,dynamic>> _account() async {
    final uid=_auth.currentUser?.uid;
    if(uid==null)throw StateError('Sign in again.');
    final account=(await _db.collection('users').doc(uid).get(_server)).data();
    if(account==null||account['active']!=true||account['removed']==true||account['role']!='teacher'){
      throw StateError('This teacher account is not active.');
    }
    return account;
  }
  Map<String,dynamic> _pick(Map<String,dynamic> data,List<String> fields)=>
    {for(final key in fields)if(data.containsKey(key))key:data[key]};
  Future<Map<String,dynamic>> load(String section) async {
    final account=await _account();
    final staffId=account['staffId'];
    if(staffId is! String||staffId.isEmpty)throw StateError('Ask the owner to link your staff profile.');
    final permissions=account['permissions'];
    bool allowed(String key)=>permissions is! Map||permissions[key]!=false;
    if(section=='profile'){
      if(!allowed('teacher_profile'))throw StateError('Profile access is disabled.');
      final staff=(await _db.collection('staff').doc(staffId).get(_server)).data();
      if(staff==null)throw StateError('Staff profile unavailable.');
      final contract=(await _db.collection('staff_contracts').doc(staffId).get(_server)).data()??{};
      return {'profile':_pick(staff,['fullName','staffNo','designation','joinDate','email','phone','qualification','subjectSpecialization']),
        'contract':_pick(contract,['type','startDate','endDate','details'])};
    }
    if(section=='salary'){
      if(!allowed('teacher_payroll'))throw StateError('Salary access is disabled.');
      final rate=(await _db.collection('finance_salary_rates').doc(staffId).get(_server)).data()??{};
      final bills=await _db.collection('finance_salary_bills').where('staffId',isEqualTo:staffId).limit(_limit+1).get(_server);
      final rows=bills.docs.take(_limit).map((d)=>_pick(d.data(),['title','month','category','amountMinor','paidMinor','status','currency','dueDate','basicMinor','allowanceMinor','bonusMinor'])).toList()
        ..sort((a,b)=>(b['month']??'').toString().compareTo((a['month']??'').toString()));
      return {'rate':_pick(rate,['basicMinor','allowanceMinor','bonusMinor','amountMinor','currency']),
        'rows':rows,'truncated':bills.docs.length>_limit};
    }
    if(section!='analytics')throw ArgumentError('Unknown teacher section.');
    if(!allowed('teacher_analytics')||!allowed('teacher_academics')){
      throw StateError('Performance analytics requires both analytics and academic permissions.');
    }
    final papers=await _db.collection('examinations').where('staffId',isEqualTo:staffId)
      .where('active',isEqualTo:true).limit(101).get(_server);
    var truncated=papers.docs.length>100;
    var released=0,submitted=0,count=0,skipped=0;
    double sum=0;
    final groups=<String,Map<String,dynamic>>{};
    for(final doc in papers.docs.take(100)){
      final p=doc.data();
      if(p['resultStatus']=='submitted')submitted++;
      if(p['resultStatus']!='released')continue;
      released++;
      final label='${p['className']??p['classId']} • ${p['subject']}';
      final group=groups.putIfAbsent(label,()=>{'name':label,'papers':0,'marks':0,'sum':0.0});
      group['papers']=(group['papers'] as int)+1;
      try {
        final marks=await doc.reference.collection('marks').limit(_limit+1).get(_server);
        if(marks.docs.length>_limit)truncated=true;
        for(final mark in marks.docs.take(_limit)){
          final score=mark.data()['score'],max=p['maxMarks'];
          if(score is num&&max is num&&max>0&&score>=0&&score<=max){
            final percent=100.0*score/max;
            sum+=percent;count++;
            group['sum']=(group['sum'] as double)+percent;
            group['marks']=(group['marks'] as int)+1;
          }
        }
      } on FirebaseException catch(error){
        if(error.code!='permission-denied')rethrow;
        // Historical assignments can be revoked. Do not bypass their rules.
        skipped++;
      }
    }
    return {'released':released,'submitted':submitted,'average':count==0?null:sum/count,
      'truncated':truncated,'skipped':skipped,'rows':groups.values.map((g)=>{'name':g['name'],'papers':g['papers'],
        'marks':g['marks'],'average':g['marks']==0?null:(g['sum'] as double)/(g['marks'] as int)}).toList()};
  }
}

/// Teacher/parent and administrator conversations are isolated by Auth UID.
/// Only the owner can enumerate user accounts. Principals can reply to
/// existing conversations without access to the private user directory.
class SchoolMessageRepository {
  SchoolMessageRepository({FirebaseFirestore? db,FirebaseAuth? auth})
      :_db=db??FirebaseFirestore.instance,_auth=auth??FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const _server=GetOptions(source:Source.server);
  String get _uid=>_auth.currentUser?.uid??(throw StateError('Sign in again.'));
  Future<Map<String,dynamic>> threads()async{
    final self=(await _db.collection('users').doc(_uid).get(_server)).data()??{};
    if(self['role']=='owner'){
      final result=await _db.collection('users').where('role',whereIn:['parent','teacher']).limit(1001).get(_server);
      final existing=await _db.collection('portal_threads').limit(1001).get(_server);
      final rows=<String,Map<String,dynamic>>{
        for(final d in existing.docs.take(1000))d.id:{'uid':d.id,'name':d.data()['name']??d.id,'role':d.data()['role']??'Archived conversation'},
        for(final d in result.docs.take(1000))
          if(d.data()['active']==true&&d.data()['removed']!=true&&(d.data()['permissions'] is! Map||(d.data()['permissions'] as Map)['messages']!=false))
            d.id:{'uid':d.id,'name':d.data()['displayName']??d.id,'role':d.data()['role']},
      };
      return {'rows':rows.values.toList(),'truncated':result.docs.length>1000||existing.docs.length>1000};
    }
    final result=await _db.collection('portal_threads').orderBy('updatedAt',descending:true).limit(1001).get(_server);
    return {'rows':result.docs.take(1000).map((d)=>{'uid':d.id,'name':d.data()['name']??d.id,'role':d.data()['role']??'School account'}).toList(),
      'truncated':result.docs.length>1000};
  }
  Future<Map<String,dynamic>> messages(String? threadUid)async{
    final thread=_db.collection('portal_threads').doc(threadUid??_uid);
    final docs=await thread.collection('messages').orderBy('createdAt',descending:true).limit(100).get(_server);
    return {'rows':docs.docs.reversed.map((d){
      final m=d.data(),date=d.data()['createdAt'];
      return {'text':m['text'],'fromSchool':m['fromSchool'],'date':date is Timestamp?date.toDate().toLocal().toString():''};
    }).toList(),'truncated':docs.docs.length==100};
  }
  String get currentUid=>_uid;
  DocumentReference<Map<String,dynamic>> thread(String? uid)=>_db.collection('portal_threads').doc(uid??_uid);
  Stream<QuerySnapshot<Map<String,dynamic>>> watch(String? uid,int limit)=>thread(uid).collection('messages')
    .orderBy('createdAt',descending:true).limit(limit).snapshots(includeMetadataChanges:true).map((snapshot){
      if(!snapshot.metadata.isFromCache){
        final account=_auth.currentUser?.uid;
        if(account!=null){
          for(final change in snapshot.docChanges){
            final m=change.doc.data();
            if(change.type==DocumentChangeType.removed||m?['deleted']==true){
              unawaited(VoiceCache.remove(account,uid??account,change.doc.id));
            }else if(m?['kind']=='voice'&&m?['readAt']!=null){
              unawaited(_checkCachedVoice(account,uid??account,change.doc.id));
            }
          }
        }
      }
      return snapshot;
    });
  Stream<QuerySnapshot<Map<String,dynamic>>> hidden(String? uid)=>thread(uid).collection('hidden').doc(_uid).collection('items').snapshots();
  Stream<QuerySnapshot<Map<String,dynamic>>> scheduled(String? uid)=>thread(uid).collection('scheduled').where('senderUid',isEqualTo:_uid).snapshots();
  Future<void> hide(String? uid,String id)=>thread(uid).collection('hidden').doc(_uid).collection('items').doc(id)
    .set({'hiddenAt':FieldValue.serverTimestamp()});
  Future<void> retract(String? uid,String id) async {
    final ref=thread(uid).collection('messages').doc(id);
    await _db.runTransaction((tx)async{
      final data=(await tx.get(ref)).data();
      if(data==null)return;
      final job=_db.collection('voice_jobs').doc(id);
      final exists=data['kind']=='voice'&&(await tx.get(job)).exists;
      tx.update(ref,{'text':'','kind':'text','attachment':FieldValue.delete(),'deleted':true,'deletedAt':FieldValue.serverTimestamp(),if(data['kind']=='voice')'voiceRetracted':true});
      if(exists)tx.update(job,{'expiresAt':FieldValue.serverTimestamp()});
    });
  }
  DocumentReference<Map<String,dynamic>> get cleanupRequest=>_db.collection('chat_cleanup').doc('current');
  Future<void> deleteConversations(String? threadUid)async{
    if(!await isOwner())throw StateError('Only the owner can delete conversations.');
    await _db.runTransaction((tx)async{
      final existing=(await tx.get(cleanupRequest)).data();
      if(existing!=null&&existing['status']!='done')throw StateError('Another conversation deletion is in progress.');
      tx.set(cleanupRequest,{'scope':threadUid==null?'all':'thread','threadUid':threadUid??'','status':'queued','requestedAt':FieldValue.serverTimestamp()});
    });
  }
  Future<void> resumeConversationCleanup()async{
    final token=await _voiceToken();
    final endpoint=_voiceEndpoint('/v1/cleanup','','').replace(query:'');
    final result=await http.post(endpoint,headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:40));
    if(result.statusCode!=204)throw StateError('Cleanup service HTTP ${result.statusCode}. Check the Worker deployment.');
  }
  Future<bool> isOwner()async=>(await _db.collection('users').doc(_uid).get(_server)).data()?['role']=='owner';
  DocumentReference<Map<String,dynamic>> get voiceSettings=>_db.collection('voice_settings').doc('global');
  Future<void> receipt(String? uid,String id,{bool read=false,bool played=false})async{
    final ref=thread(uid).collection('messages').doc(id);
    final me=_uid;
    final removeLocal=await _db.runTransaction<bool>((tx)async{
      final m=(await tx.get(ref)).data();
      if(m==null||m['senderUid']==me||m['deleted']==true)return false;
      final changes=<String,dynamic>{};
      if(m['deliveredAt']==null)changes['deliveredAt']=FieldValue.serverTimestamp();
      final markRead=(read&&(m['kind']!='voice'||played)&&m['readAt']==null);
      final job=_db.collection('voice_jobs').doc(id);
      final j=markRead&&m['kind']=='voice'?(await tx.get(job)).data():null;
      if(markRead)changes['readAt']=FieldValue.serverTimestamp();
      if(changes.isNotEmpty)tx.update(ref,changes);
      if(j?['mode']=='played')tx.update(job,{'expiresAt':FieldValue.serverTimestamp()});
      return j?['mode']=='played';
    });
    if(removeLocal)await VoiceCache.remove(me,uid??me,id);
  }
  Uri _voiceEndpoint(String path,String threadId,String messageId){
    const configured=String.fromEnvironment('NOTIFICATION_WORKER_URL',
      defaultValue:'https://suffah-message-notifications.blog-younas.workers.dev');
    final endpoint=Uri.parse(configured);
    if(endpoint.scheme!='https')throw StateError('Voice service requires HTTPS.');
    return endpoint.replace(path:path,queryParameters:{'thread':threadId,'message':messageId});
  }
  Future<String> _voiceToken()async{
    final token=await _auth.currentUser?.getIdToken();
    if(token==null)throw StateError('Sign in again.');
    return token;
  }
  String reserveMessageId(String? uid)=>thread(uid).collection('messages').doc().id;
  Future<void> discardVoiceCache(String? uid,String id)=>VoiceCache.remove(_uid,uid??_uid,id);
  Future<DateTime> _voiceExpiry(String account,String target,String id)async{
    try{
      final m=(await thread(target).collection('messages').doc(id).get(_server)).data();
      if(m==null||m['kind']!='voice'||m['deleted']==true)throw StateError('Voice message expired.');
      final j=(await _db.collection('voice_jobs').doc(id).get(_server)).data();
      final expiry=j?['expiresAt'];
      if(j==null||j['ready']!=true||j['threadUid']!=target||expiry is! Timestamp||!expiry.toDate().isAfter(DateTime.now()))throw StateError('Voice message expired.');
      if(_auth.currentUser?.uid!=account)throw StateError('Account changed.');
      return expiry.toDate();
    }on FirebaseException catch(e){
      if(e.code=='permission-denied'||e.code=='not-found')await VoiceCache.remove(account,target,id);
      rethrow;
    }on StateError{
      await VoiceCache.remove(account,target,id);
      rethrow;
    }
  }
  Future<void> _checkCachedVoice(String account,String target,String id)async{
    try{if(await VoiceCache.read(account,target,id)!=null)await _voiceExpiry(account,target,id);}catch(_){}
  }
  // Verify small server metadata for revocation, but never re-download cached audio.
  Future<File> voiceFile(String? uid,String id)async{
    final account=_uid,target=uid??account;
    final expiry=await _voiceExpiry(account,target,id);
    final cached=await VoiceCache.read(account,target,id);
    if(cached!=null){
      await cached.setLastModified(expiry);
      return cached;
    }
    final result=await http.get(_voiceEndpoint('/v1/voice',target,id),
      headers:{'Authorization':'Bearer ${await _voiceToken()}'}).timeout(const Duration(seconds:30));
    if(result.statusCode!=200)throw StateError('Voice message expired or is unavailable.');
    if(_auth.currentUser?.uid!=account)throw StateError('Account changed.');
    return VoiceCache.store(account,target,id,result.bodyBytes,expiry);
  }
  Future<void> cancel(String? uid,String id)=>thread(uid).collection('scheduled').doc(id).delete();
  Future<void> send(String? threadUid,String text,{String kind='text',Map<String,dynamic>? attachment,DateTime? sendAt,Uint8List? voice,String? messageId})async{
    final uid=_uid;
    final target=threadUid??uid;
    final self=(await _db.collection('users').doc(uid).get(_server)).data()??{};
    final admin=self['role']=='owner'||self['role']=='principal';
    final thread=_db.collection('portal_threads').doc(target);
    Map<String,dynamic> metadata;
    if(!admin||self['role']=='owner'){
      final account=target==uid?self:(await _db.collection('users').doc(target).get(_server)).data()??{};
      metadata={'name':account['displayName']??'','role':account['role']};
    }else{
      final existing=(await thread.get(_server)).data();
      if(existing==null||existing['role']==null)throw StateError('This conversation needs a new message from the participant before replying.');
      metadata={'name':existing['name']??'','role':existing['role']};
    }
    if(sendAt!=null){
      await thread.collection('scheduled').doc().set({'text':text.trim(),'kind':kind,'senderUid':uid,
        'fromSchool':admin,'sendAt':Timestamp.fromDate(sendAt),'createdAt':FieldValue.serverTimestamp()});
      return;
    }
    final message=thread.collection('messages').doc(messageId);
    if(kind=='voice'){
      if(messageId!=null){
        final existing=(await message.get(_server)).data();
        if(existing!=null){
          if(existing['senderUid']!=uid||existing['kind']!='voice')throw StateError('Message reference already used.');
          return; // A previous attempt committed before its response arrived.
        }
      }
      if(voice==null||voice.isEmpty||voice.length>3000000)throw StateError('Recording is too large.');
      await thread.set({'uid':target,...metadata,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      final result=await http.put(_voiceEndpoint('/v1/voice',target,message.id),
        headers:{'Authorization':'Bearer ${await _voiceToken()}','Content-Type':'audio/mp4'},
        body:voice).timeout(const Duration(seconds:45));
      if(result.statusCode!=201){
        // A retry may reuse an already uploaded, uncommitted recording.
        var reusable=false;
        if(result.statusCode==409){
          try{
            final j=(await _db.collection('voice_jobs').doc(message.id).get(_server)).data();
            final expiry=j?['expiresAt'];
            reusable=j?['ready']==true&&j?['threadUid']==target&&j?['senderUid']==uid&&expiry is Timestamp&&expiry.toDate().isAfter(DateTime.now());
          }catch(_){}
        }
        if(!reusable)throw StateError('Voice upload failed (HTTP ${result.statusCode}). Try again.');
      }
    }
    final batch=_db.batch();
    batch.set(thread,{'uid':target,...metadata,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
    batch.set(message,{'text':text.trim(),'kind':kind,if(attachment!=null)'attachment':attachment,'senderUid':uid,'fromSchool':admin,'createdAt':FieldValue.serverTimestamp()});
    batch.set(_db.collection('message_alerts').doc(message.id),{
      'threadUid':target,'senderUid':uid,'fromSchool':admin,
      'createdAt':FieldValue.serverTimestamp(),'pushPending':true,
    });
    await batch.commit();
    unawaited(_wakeNotification(target,message.id,uid));
    if(kind=='voice'&&voice!=null){
      try{
        final expiry=await _voiceExpiry(uid,target,message.id);
        await VoiceCache.store(uid,target,message.id,voice,expiry);
      }catch(_){/* A local cache failure must not fail a committed message. */}
    }
  }
  // Push is best-effort. A successful message write must never appear failed
  // because the notification service is offline; cron retries queued events.
  Future<void> _wakeNotification(String threadId,String messageId,String senderUid)async{
    try{
      final user=_auth.currentUser;
      if(user==null||user.uid!=senderUid)return;
      final token=await user.getIdToken();
      if(token==null||_auth.currentUser?.uid!=senderUid)return;
      const configured=String.fromEnvironment('NOTIFICATION_WORKER_URL',
        defaultValue:'https://suffah-message-notifications.blog-younas.workers.dev');
      final endpoint=Uri.tryParse(configured);
      if(endpoint==null||endpoint.scheme!='https'||endpoint.host.isEmpty)return;
      await http.post(endpoint.replace(path:'/v1/wake',queryParameters:{
        'thread':threadId,'message':messageId,
      }),headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:8));
    }catch(_){/* The queued event is still available to cron. */}
  }

}
