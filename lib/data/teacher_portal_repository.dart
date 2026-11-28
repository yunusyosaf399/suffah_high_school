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
      return {'rows':result.docs.take(1000).where((d)=>d.data()['active']==true&&d.data()['removed']!=true
        &&(d.data()['permissions'] is! Map||(d.data()['permissions'] as Map)['messages']!=false))
        .map((d)=>{'uid':d.id,'name':d.data()['displayName']??d.id,'role':d.data()['role']}).toList(),
        'truncated':result.docs.length>1000};
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
    .orderBy('createdAt',descending:true).limit(limit).snapshots();
  Stream<QuerySnapshot<Map<String,dynamic>>> hidden(String? uid)=>thread(uid).collection('hidden').doc(_uid).collection('items').snapshots();
  Stream<QuerySnapshot<Map<String,dynamic>>> scheduled(String? uid)=>thread(uid).collection('scheduled').where('senderUid',isEqualTo:_uid).snapshots();
  Future<void> hide(String? uid,String id)=>thread(uid).collection('hidden').doc(_uid).collection('items').doc(id)
    .set({'hiddenAt':FieldValue.serverTimestamp()});
  Future<void> retract(String? uid,String id)=>thread(uid).collection('messages').doc(id).update({
    'text':'','kind':'text','attachment':FieldValue.delete(),'deleted':true,'deletedAt':FieldValue.serverTimestamp()
  });
  Future<void> cancel(String? uid,String id)=>thread(uid).collection('scheduled').doc(id).delete();
  Future<void> send(String? threadUid,String text,{String kind='text',Map<String,dynamic>? attachment,DateTime? sendAt})async{
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
    final batch=_db.batch();
    batch.set(thread,{'uid':target,...metadata,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
    batch.set(thread.collection('messages').doc(),{'text':text.trim(),'kind':kind,if(attachment!=null)'attachment':attachment,'senderUid':uid,'fromSchool':admin,'createdAt':FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
