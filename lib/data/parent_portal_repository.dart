import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// These views deliberately exclude other students, internal notes and full
// class rosters. Do not grant parents access to students or examinations.
Map<String,dynamic> parentPick(Map<String,dynamic> d,List<String> keys)=>
  {for(final key in keys)if(d.containsKey(key))key:d[key]};
Map<String,dynamic> _map(dynamic v)=>v is Map?Map<String,dynamic>.from(v):{};
const parentPaperFields=['classId','title','sessionTitle','kind','category','subject','examDate','paperType',
  'startMinute','endMinute','maxMarks','resultStatus','active','cycleId','rescheduleReason'];
const parentCycleFields=['status','category','startDate','endDate','excludedDates'];
const parentAttendanceFields=['studentId','classId','date','status'];

void writeParentChildViews(void Function(DocumentReference<Map<String,dynamic>>,Map<String,dynamic>) set,
    FirebaseFirestore db,String id,Map<String,dynamic> d,{List<String>? history,String? className}) {
  final details=_map(d['details']);
  final student=_map(details['student']),academic=_map(details['academic']);
  final classId=(d['classId']??academic['classId']??'').toString();
  final profile={...parentPick(d,['fullName','admissionNo','rollNo','gender','status','active']),
    ...parentPick(student,['dateOfBirth','gender','nationality']),
    'classId':classId,
    if(academic['admissionDate']!=null)'admissionDate':academic['admissionDate'],
    if(academic['admissionDate']==null&&d['admittedAt'] is Timestamp)
      'admissionDate':(d['admittedAt'] as Timestamp).toDate().toIso8601String().split('T').first,
  };
  final child=db.collection('parent_children').doc(id);
  set(child,{'fullName':d['fullName']??'Student','classId':classId,'className':className??classId,
    if(history!=null)'historyClassIds':FieldValue.arrayUnion(history)});
  set(db.collection('parent_profiles').doc(id),profile);
  set(db.collection('parent_documents').doc(id),{'photoPath':d['photoPath']??'','attachments':_map(d['attachments'])});
}
class ParentPortalRepository {
  ParentPortalRepository({FirebaseFirestore? db,FirebaseAuth? auth})
    :db=db??FirebaseFirestore.instance,auth=auth??FirebaseAuth.instance;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  static const server=GetOptions(source:Source.server);
  String get uid=>auth.currentUser?.uid??(throw StateError('Sign in again.'));
  Future<Map<String,dynamic>> _account()async{
    final account=(await db.collection('users').doc(uid).get(server)).data();
    if(account==null||account['active']!=true||account['removed']==true||account['role']!='parent'){
      throw StateError('This parent account is not active.');
    }
    return account;
  }
  List<String> _ids(Map<String,dynamic> a)=>(a['linkedStudentIds'] as List? ?? []).whereType<String>().toSet().toList();
  Future<Map<String,dynamic>> children()async{
    final a=await _account(),rows=<Map<String,dynamic>>[];
    for(final id in _ids(a)){
      final d=(await db.collection('parent_children').doc(id).get(server)).data();
      rows.add({'id':id,'name':d?['fullName']??id,'needsSync':d==null});
    }
    return {'rows':rows};
  }
  Future<Map<String,dynamic>> section(String id,String section)async{
    final a=await _account();
    if(!_ids(a).contains(id))throw StateError('This student is not linked to your account.');
    final key=const {'profile':'parent_profile','fees':'parent_fees','attendance':'parent_attendance',
      'exams':'parent_exams','tests':'parent_exams','assignments':'parent_exams','homework':'parent_exams','documents':'parent_documents'}[section];
    if(key==null||_map(a['permissions'])[key]==false)throw StateError('This section is unavailable.');
    if(section=='profile'){
      final p=(await db.collection('parent_profiles').doc(id).get(server)).data();
      if(p==null)throw StateError('Ask the school owner to sync parent records.');
      final c=(await db.collection('parent_children').doc(id).get(server)).data();
      return {'profile':{...p,'className':c?['className']??p['classId']}};
    }
    if(section=='documents'){
      final p=(await db.collection('parent_documents').doc(id).get(server)).data();
      if(p==null)throw StateError('Ask the school owner to sync parent records.');
      final files=_map(p['attachments']).values.whereType<Map>().map((f)=>Map<String,dynamic>.from(f)).toList();
      if(p['photoPath'] is String&&(p['photoPath'] as String).isNotEmpty){
        files.add({'path':p['photoPath'],'name':'Profile photo.webp','contentType':'image/webp'});
      }
      return {'rows':files.where((f)=>f['path'] is String&&
        ((f['path'] as String).startsWith('student-documents/$id/')||(f['path'] as String).startsWith('student-photos/$id/'))).toList()};
    }
    if(section=='fees'){
      final bills=await _all(db.collection('finance_fee_bills').where('studentId',isEqualTo:id));
      final sales=await _all(db.collection('inventory_sales').where('customerType',isEqualTo:'student').where('customerId',isEqualTo:id));
      final rows=<Map<String,dynamic>>[
        for(final d in bills) parentPick(d.data(),['title','month','category','amountMinor','paidMinor','status','currency','dueDate']),
        for(final d in sales) {
          'title':'${d.data()['itemName']} × ${d.data()['quantity']}',
          'category':d.data()['department']??'stationery',
          'month':_month(d.data()['soldAt']),
          'amountMinor':d.data()['totalMinor'],
          'paidMinor':d.data()['paidMinor']??d.data()['totalMinor'],
          'status':d.data()['paymentStatus']??'paid',
          'currency':d.data()['currency'],
        },
      ]..sort((a,b)=>(b['month']??'').toString().compareTo((a['month']??'').toString()));
      return {'rows':rows};
    }
    if(section=='attendance'){
      final docs=await _all(db.collection('parent_attendance').doc(id).collection('days'));
      final rows=docs.map((d)=>d.data()).where((d)=>d['status']!='unmarked').toList()
        ..sort((a,b)=>(b['date']??'').toString().compareTo((a['date']??'').toString()));
      return {'rows':rows};
    }
    final child=(await db.collection('parent_children').doc(id).get(server)).data();
    if(child==null)throw StateError('Ask the school owner to sync parent records.');
    final current=child['classId']?.toString()??'';
    if(section=='assignments'||section=='homework'){
      if(current.isEmpty)return {'rows':[]};
      await db.collection('parent_class_grants').doc(uid).collection('classes').doc(current).set({'studentId':id});
      final work=await _all(db.collection('classwork').where('classId',isEqualTo:current));
      final rows=work.map((d)=>d.data()).where((d)=>d['kind']==(section=='assignments'?'assignment':'homework')).map((d)=>parentPick(d,['title','subject','instructions','dueDate','active','kind'])).toList()
        ..sort((a,b)=>(b['dueDate']??'').toString().compareTo((a['dueDate']??'').toString()));
      return {'rows':rows};
    }
    final classes={current,...(child['historyClassIds'] as List? ?? []).whereType<String>()}..remove('');
    final rows=<Map<String,dynamic>>[];
    final cycles=<String,Map<String,dynamic>>{};
    for(final classId in classes){
      // Grants are not trusted claims: rules verify the linked child and
      // current or historical roster on every timetable read.
      await db.collection('parent_class_grants').doc(uid).collection('classes').doc(classId).set({'studentId':id});
      final docs=await _all(db.collection('parent_class_schedules').doc(classId).collection('papers'));
      for(final doc in docs){
        final paper=doc.data();
        if(section=='tests' ? paper['kind']!='test' : paper['kind']=='test')continue;
        if(paper['active']!=true&&paper['resultStatus']!='released')continue;
        Map<String,dynamic>? mark;
        if(paper['resultStatus']=='released'){
          try{
            mark=(await db.collection('examinations').doc(doc.id).collection('marks').doc(id).get(server)).data();
          }on FirebaseException catch(e){if(e.code!='permission-denied')rethrow;}
        }
        // Never show an old class's paper unless this child has a released mark.
        if(classId!=current&&mark==null)continue;
        final cycleId=paper['cycleId'];
        if(cycleId is String&&cycleId.isNotEmpty&&!cycles.containsKey(cycleId)){
          cycles[cycleId]=(await db.collection('parent_term_summaries').doc(cycleId).get(server)).data()??{};
        }
        final cycle=cycles[cycleId]??{};
        rows.add({...paper,'cycleStatus':cycle['status']??'',
          'schoolClosure':_map(cycle['excludedDates'])[paper['examDate']]??'',
          if(mark?['score'] is num)'score':mark!['score']});
      }
    }
    rows.sort((a,b)=>(b['examDate']??'').toString().compareTo((a['examDate']??'').toString()));
    return {'rows':rows};
  }

  static String _month(dynamic value){
    if(value is! Timestamp)return '';
    final date=value.toDate().toUtc().add(const Duration(hours:5));
    return '${date.year}-${date.month.toString().padLeft(2,'0')}';
  }
  static Future<List<QueryDocumentSnapshot<Map<String,dynamic>>>> _all(Query<Map<String,dynamic>> query)async{
    final result=<QueryDocumentSnapshot<Map<String,dynamic>>>[];
    final ordered=query.orderBy(FieldPath.documentId);
    while(true){
      final page=await (result.isEmpty?ordered:ordered.startAfterDocument(result.last)).limit(250).get(server);
      result.addAll(page.docs);
      if(page.docs.length<250)return result;
    }
  }

  static Future<String> classLabel(FirebaseFirestore db,String id)async{
    if(id.isEmpty)return '';
    final c=(await db.collection('classes').doc(id).get(server)).data();
    if(c==null)return id;
    final name=[c['name'],c['section']].whereType<String>().where((s)=>s.isNotEmpty).join(' – ');
    return name.isEmpty?id:name;
  }
  static Future<void> syncPaper(FirebaseFirestore db,String id)async{
    final p=(await db.collection('examinations').doc(id).get(server)).data();
    if(p==null||p['classId'] is! String)return;
    await db.collection('parent_class_schedules').doc(p['classId'] as String).collection('papers').doc(id).set(parentPick(p,parentPaperFields));
  }
  static Future<void> syncCycle(FirebaseFirestore db,String id)async{
    final p=(await db.collection('exam_term_cycles').doc(id).get(server)).data();
    if(p!=null)await db.collection('parent_term_summaries').doc(id).set(parentPick(p,parentCycleFields));
  }

  // One-time repair for pre-existing records, also usable after old app builds.
  // Only owner can enumerate parent accounts. Writes are idempotent.
  Future<int> syncExisting()async{
    final users=await db.collection('users').where('role',isEqualTo:'parent').get(server);
    final ids=<String>{for(final u in users.docs)if(u.data()['removed']!=true)
      ...(u.data()['linkedStudentIds'] as List? ?? []).whereType<String>()};
    final classes=await db.collection('classes').get(server);
    for(final id in ids){
      final child=(await db.collection('students').doc(id).get(server)).data();
      if(child==null||child['status']=='draft')continue;
      final history=<String>[];
      for(final c in classes.docs){
        if((await db.collection('class_rosters').doc(c.id).collection('students').doc(id).get(server)).exists)history.add(c.id);
      }
      final batch=db.batch();
      writeParentChildViews((ref,data)=>batch.set(ref,data,ref.parent.id=='parent_children'?SetOptions(merge:true):null),db,id,child,history:history);
      final classId=child['classId'];
      final klass=classes.docs.where((d)=>d.id==classId).firstOrNull?.data();
      if(klass!=null)batch.set(db.collection('parent_children').doc(id),{'className':
        [klass['name'],klass['section']].whereType<String>().where((s)=>s.isNotEmpty).join(' – ')},SetOptions(merge:true));
      await batch.commit();
      final marks=await db.collectionGroup('marks').where('studentId',isEqualTo:id).get(server);
      for(final m in marks.docs){
        final parent=m.reference.parent.parent;
        if(parent==null||parent.parent.id!='attendance_days'||m.id!=id)continue;
        await db.collection('parent_attendance').doc(id).collection('days').doc(parent.id).set(parentPick(m.data(),parentAttendanceFields));
      }
    }
    final papers=await db.collection('examinations').get(server);
    for(final p in papers.docs){await syncPaper(db,p.id);}
    final cycles=await db.collection('exam_term_cycles').get(server);
    for(final c in cycles.docs){await syncCycle(db,c.id);}
    return ids.length;
  }
}
