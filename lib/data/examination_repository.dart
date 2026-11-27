import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'staff_repository.dart';
import 'class_subject_repository.dart';

const examTerms = ['First Term', 'Mid Term', 'Final Term'];
const classTestTypes = ['Monthly Test', 'Weekly Test', 'Unit Test', 'Quiz', 'Other Test'];
const paperTypes = ['Theory', 'Practical / Lab', 'Oral'];

bool canScheduleFormalExams(String role) =>
    ['owner', 'principal', 'examiner'].contains(role);

String examDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ExamPaperDraft {
  ExamPaperDraft({required this.assignment, required this.date,
    this.type = 'Theory', this.maxMarks = 100, this.durationMinutes = 60,
    this.instructions = '', this.startMinute = 540});
  final TeacherAssignment assignment;
  final DateTime date;
  final String type;
  final double maxMarks;
  final int durationMinutes;
  final int startMinute;
  int get endMinute => startMinute + durationMinutes;
  final String instructions;

  ExamPaperDraft copyWith({DateTime? date, double? maxMarks, int? durationMinutes,
    String? instructions, int? startMinute}) => ExamPaperDraft(assignment: assignment,
    date: date ?? this.date, type: type, maxMarks: maxMarks ?? this.maxMarks,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    instructions: instructions ?? this.instructions, startMinute: startMinute ?? this.startMinute);
}

List<DateTime> examCalendarDays(DateTime start, DateTime end, {bool skipSunday = false, Set<String> excludedDates = const {}}) {
  final last = DateTime(end.year,end.month,end.day);
  return [
    for (var day = DateTime(start.year,start.month,start.day);
      !day.isAfter(last); day = DateTime(day.year,day.month,day.day+1))
      if ((!skipSunday || day.weekday != DateTime.sunday) && !excludedDates.contains(examDateKey(day))) day,
  ];
}

List<DateTime> examDateSlots(List<DateTime> days, int count) {
  if (count == 0) return [];
  if (days.length < count) throw ArgumentError('Choose at least $count available examination days.');
  if (count == 1) return [days.first];
  return [for (var i=0; i<count; i++) days[(i*(days.length-1)/(count-1)).floor()]];
}

List<ExamPaperDraft> generateClassExamSchedule({
  required String classId, required String className,
  required List<ClassSubject> subjects, required List<TeacherAssignment> assignments,
  required List<DateTime> days, Map<String,String> teacherNames = const {},
  String type = 'Theory', double maxMarks = 100, int durationMinutes = 60,
  String instructions = '', int startMinute = 540,
}) {
  final catalog = subjects.where((s)=>s.active && s.classId == classId).toList()
    ..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (catalog.isEmpty) throw ArgumentError('This class has no active subjects.');
  if (catalog.length > 15) throw ArgumentError('A schedule supports up to 15 papers.');
  final slots = examDateSlots(days,catalog.length);
  return [
    for (var i=0; i<catalog.length; i++)
      ExamPaperDraft(assignment: _defaultTeacher(catalog[i],className,assignments,teacherNames),
        date:slots[i],type:type,maxMarks:maxMarks,durationMinutes:durationMinutes,instructions:instructions,startMinute:startMinute),
  ];
}

TeacherAssignment _defaultTeacher(ClassSubject subject, String className,
    List<TeacherAssignment> assignments, Map<String,String> names) {
  final eligible = assignments.where((a)=>a.active && a.classId == subject.classId &&
    a.id.isNotEmpty && a.staffId.isNotEmpty && a.subject == subject.name &&
    (a.subjectId.isEmpty || a.subjectId == subject.id)).toList()
    ..sort((a,b) {
      final compare = (names[a.staffId] ?? a.staffId).compareTo(names[b.staffId] ?? b.staffId);
      return compare != 0 ? compare : a.id.compareTo(b.id);
    });
  return eligible.isNotEmpty ? eligible.first : TeacherAssignment(
    id:'',staffId:'',classId:subject.classId,className:className,
    subject:subject.name,subjectId:subject.id,active:false);
}

List<ExamPaperDraft> redistributeExamPapers(List<ExamPaperDraft> papers,List<DateTime> days) {
  final sorted = [...papers]..sort((a,b)=>a.date.compareTo(b.date));
  final slots = examDateSlots(days,sorted.length);
  return [for(var i=0;i<sorted.length;i++) sorted[i].copyWith(date:slots[i])];
}

List<ExamPaperDraft> shuffleExamPapers(List<ExamPaperDraft> papers,{Random? random}) {
  final sorted = [...papers]..sort((a,b)=>a.date.compareTo(b.date));
  if(sorted.length<2) return sorted;
  final shuffled = [...sorted]..shuffle(random);
  if (List.generate(sorted.length,(i)=>identical(sorted[i],shuffled[i])).every((v)=>v)) {
    shuffled.add(shuffled.removeAt(0));
  }
  return [for(var i=0;i<sorted.length;i++) shuffled[i].copyWith(date:sorted[i].date)];
}


Map<String,List<ExamPaperDraft>> groupExamPapersByClass(List<ExamPaperDraft> papers) {
  final groups=<String,List<ExamPaperDraft>>{};
  for(final paper in papers) {
    groups.putIfAbsent(paper.assignment.classId,()=>[]).add(paper);
  }
  return groups;
}

List<ExamPaperDraft> shuffleClassSchedules(List<ExamPaperDraft> papers,{Random? random}) =>
    [for(final group in groupExamPapersByClass(papers).values) ...shuffleExamPapers(group,random:random)];

String? validateExamSchedule({
  required String kind, required String category, required String title,
  required DateTime start, required DateTime end,
  required List<ExamPaperDraft> papers,
}) {
  if (title.trim().isEmpty || title.trim().length > 100) return 'Enter an exam title (up to 100 characters).';
  if (end.isBefore(start)) return 'End date must be on or after the start date.';
  if (kind == 'term' ? !examTerms.contains(category) : !classTestTypes.contains(category)) {
    return 'Choose an assessment category.';
  }
  if (papers.isEmpty || papers.length > 15) return 'Add 1–15 papers per schedule.';
  if (kind == 'test' && papers.length != 1) return 'A class test has one subject paper.';
  final seen = <String>{};
  final dates = <String>{};
  for (final paper in papers) {
    final a = paper.assignment;
    if (!a.active || a.id.isEmpty || a.staffId.isEmpty) return 'Assign a teacher to ${a.subject} before publishing.';
    if (a.classId != papers.first.assignment.classId) return 'Choose active assignments for one class.';
    if (paper.date.isBefore(start) || paper.date.isAfter(end)) return 'Every paper date must be inside the exam date range.';
    if (kind == 'term' && !dates.add(examDateKey(paper.date))) return 'Only one paper per class per day is allowed.';
    if (!paperTypes.contains(paper.type) || !paper.maxMarks.isFinite ||
        paper.maxMarks <= 0 || paper.maxMarks > 1000 ||
        paper.durationMinutes < 1 || paper.durationMinutes > 600 || paper.startMinute < 0 || paper.endMinute >= 1440) {
      return 'Check paper type, marks (1–1000) and duration (1–600 minutes).';
    }
    if (!seen.add('${a.subject.toLowerCase()}|${paper.type}')) {
      return 'A subject and paper type cannot be added twice.';
    }
  }
  return null;
}

// School timetable is in Pakistan Standard Time, independent of the device zone.
DateTime schoolExamNow() => DateTime.now().toUtc().add(const Duration(hours:5));
DateTime examInstant(DateTime date,int minute) =>
    DateTime.utc(date.year,date.month,date.day).add(Duration(minutes:minute-300));
String examClock(int minute) =>
    '${(minute~/60).toString().padLeft(2,'0')}:${(minute%60).toString().padLeft(2,'0')}';
String examTiming(Map<String,dynamic> d) => d['startMinute'] is int && d['endMinute'] is int
    ? '${examClock(d['startMinute'] as int)}–${examClock(d['endMinute'] as int)} PKT' : 'Time not set';
String termCycleId(int year,String term) => '${year}_${const {'First Term':'first','Mid Term':'mid','Final Term':'final'}[term]}';
String examSlot(String classId,String date) => '${classId}__$date';
List<String> examStrings(dynamic value) => value is List ? value.whereType<String>().toList() : <String>[];
Map<String,String> examStringMap(dynamic value) => value is Map
    ? value.map((k,v)=>MapEntry(k.toString(),v.toString())) : <String,String>{};

bool termReadyToClose(Map<String,dynamic> cycle) {
  final papers=examStrings(cycle['paperIds']).toSet();
  final released=examStrings(cycle['releasedPaperIds']).toSet();
  final planned=examStrings(cycle['plannedClassIds']).toSet();
  final scheduled=examStrings(cycle['classIds']).toSet();
  return cycle['status']=='active' && papers.isNotEmpty && planned.isNotEmpty &&
    papers.length==released.length && released.containsAll(papers) &&
    scheduled.containsAll(planned);
}

class ExaminationRepository {
  ExaminationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String,dynamic>> get termControl => db.collection('exam_term_control').doc('current');
  CollectionReference<Map<String,dynamic>> get terms => db.collection('exam_term_cycles');

  Future<Map<String,dynamic>?> loadActiveTerm() async {
    final control=await termControl.get(const GetOptions(source:Source.server));
    final id=control.data()?['cycleId'];
    if(id is! String || id.isEmpty) return null;
    final cycle=await terms.doc(id).get(const GetOptions(source:Source.server));
    if(!cycle.exists) throw StateError('The examination control record is incomplete.');
    final data=cycle.data()!;
    return data['status']=='active'?{...data,'id':cycle.id}:null;
  }

  // Keep the existing security-checked class transaction. A whole-school
  // schedule may exceed Firestore's atomic rule lookup/write budgets.
  // The selected class plan is locked by the first transaction; remaining
  // classes can be resumed in the same annual cycle, never a second term.
  Future<void> publishClassSchedules({
    required String role, required String category, required String title,
    required DateTime start, required DateTime end, required int academicYear,
    required List<ExamPaperDraft> papers, required List<String> plannedClassIds,
    required Map<String,String> excludedDates, required bool skipSunday,
    String? activeCycleId, void Function(String classId)? onClassPublished,
  }) async {
    final groups=groupExamPapersByClass(papers);
    if(groups.isEmpty) throw ArgumentError('Select at least one class.');
    final plan=plannedClassIds.toSet();
    if(!plan.containsAll(groups.keys) ||
       (activeCycleId==null && !groups.keys.toSet().containsAll(plan))) {
      throw StateError('The reviewed papers must cover the selected classes.');
    }
    for(final entry in groups.entries) {
      final label=entry.value.first.assignment.className;
      final error=validateExamSchedule(kind:'term',category:category,title:title,
        start:start,end:end,papers:entry.value);
      if(error!=null) throw ArgumentError('${label.isEmpty?entry.key:label}: $error');
      if(entry.value.any((p)=>excludedDates.containsKey(examDateKey(p.date)) ||
          (skipSunday && p.date.weekday==DateTime.sunday))) {
        throw ArgumentError('A paper is scheduled on an excluded date.');
      }
    }
    // Preflight every selected roster before making the first write.
    // The individual transactions also validate their own roster.
    for(final entry in groups.entries) {
      final roster=await db.collection('class_rosters').doc(entry.key).collection('students')
        .where('active',isEqualTo:true).limit(1001).get(const GetOptions(source:Source.server));
      if(roster.docs.isEmpty || roster.docs.length>1000) {
        final label=entry.value.first.assignment.className;
        throw StateError('Sync the student roster for ${label.isEmpty?entry.key:label} (1–1000 active students). No new class schedules were published.');
      }
    }
    var cycle=activeCycleId;
    for(final entry in groups.entries) {
      await publishSchedule(role:role,kind:'term',category:category,title:title,start:start,end:end,
        papers:entry.value,academicYear:academicYear,activeCycleId:cycle,
        plannedClassIds:plannedClassIds,excludedDates:excludedDates,skipSunday:skipSunday);
      cycle=termCycleId(academicYear,category);
      onClassPublished?.call(entry.key);
    }
  }

  Future<void> publishSchedule({required String role, required String kind,
    required String category, required String title, required DateTime start,
    required DateTime end, required List<ExamPaperDraft> papers,
    int? academicYear, String? activeCycleId, List<String> plannedClassIds = const [],
    Map<String,String> excludedDates = const {}, bool skipSunday = false}) async {
    if (kind != 'term' && kind != 'test') throw ArgumentError('Unsupported assessment type.');
    if (kind == 'term' && !canScheduleFormalExams(role)) throw StateError('Only exam administrators can schedule term examinations.');
    final error = validateExamSchedule(kind: kind, category: category, title: title,
      start: start, end: end, papers: papers);
    if (error != null) throw ArgumentError(error);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in again.');
    final exams = db.collection('examinations');
    final sessionId = exams.doc().id;
    final refs = List.generate(papers.length, (_) => exams.doc());
    Map<String,dynamic> fields(ExamPaperDraft paper) {
      final a=paper.assignment;
      return {
        'sessionId':sessionId,'kind':kind,'category':category,
        'sessionTitle':title.trim(),'title':'${title.trim()} – ${a.subject}',
        'startDate':examDateKey(start),'endDate':examDateKey(end),
        'examDate':examDateKey(paper.date),'paperType':paper.type,
        'startMinute':paper.startMinute,'endMinute':paper.endMinute,
        'endAt':Timestamp.fromDate(examInstant(paper.date,paper.endMinute)),
        'durationMinutes':paper.durationMinutes,'instructions':paper.instructions.trim(),
        'assignmentId':a.id,'staffId':a.staffId,'classId':a.classId,
        'className':a.className,'subject':a.subject,
        'maxMarks':paper.maxMarks,'active':true,'resultStatus':'draft',
        'createdBy':user.uid,'createdAt':FieldValue.serverTimestamp(),
        'updatedAt':FieldValue.serverTimestamp(),
      };
    }
    if(kind=='test') {
      final batch=db.batch();
      for(var i=0;i<papers.length;i++) {batch.set(refs[i],fields(papers[i]));}
      await batch.commit(); return;
    }
    final year=academicYear ?? start.year;
    if(year<2000 || year>2100) throw ArgumentError('Choose a valid academic year.');
    final id=termCycleId(year,category);
    if(activeCycleId!=null && activeCycleId!=id) throw StateError('Select the current active examination.');
    final cycleRef=terms.doc(id);
    final classId=papers.first.assignment.classId;
    final planned=plannedClassIds.toSet().toList()..sort();
    if(activeCycleId==null && !planned.contains(classId)) throw StateError('Choose an active planned class.');
    // Existing pre-cycle exams are preserved. Finish their active papers before opening a new cycle.
    if(activeCycleId==null) {
      final existing=await exams.where('active',isEqualTo:true).get(const GetOptions(source:Source.server));
      if(existing.docs.any((d)=>d.data()['kind']!='test' && d.data()['cycleId']==null && d.data()['resultStatus']!='released')) {
        throw StateError('Finish and release the existing legacy examination papers before opening a new term.');
      }
    }
    final roster=await db.collection('class_rosters').doc(classId).collection('students')
      .where('active',isEqualTo:true).get(const GetOptions(source:Source.server));
    final students=<String,dynamic>{for(final doc in roster.docs) doc.id:{
      'fullName':(doc.data()['fullName']??'Student').toString(),
      'rollNo':(doc.data()['rollNo']??'').toString(),
    }};
    if(students.isEmpty || students.length>1000) throw StateError('Sync the active student roster before scheduling this class (1–1000 students).');
    final paperIds=refs.map((r)=>r.id).toList();
    await db.runTransaction((tx) async {
      final control=await tx.get(termControl);
      final currentId=control.data()?['cycleId'];
      final existing=await tx.get(cycleRef);
      final old=existing.data();
      Map<String,dynamic>? previous;
      if(currentId is String && currentId!=id) previous=(await tx.get(terms.doc(currentId))).data();
      if(activeCycleId==null) {
        if(old!=null) throw StateError('$category for $year–${year+1} already exists. Open the existing examination.');
        if(currentId!=null && (previous==null || previous['status']!='closed')) {
          throw StateError('An examination is still active. Complete and close it before creating another.');
        }
      } else {
        if(currentId!=id || old==null || old['status']!='active') throw StateError('The examination is no longer active.');
        if(!examStrings(old['plannedClassIds']).contains(classId)) throw StateError('This class was not included in the examination plan.');
        if(examStrings(old['classIds']).contains(classId)) throw StateError('This class already has a published date sheet.');
      }
      final off=old==null?excludedDates:examStringMap(old['excludedDates']);
      final skip=old==null?skipSunday:old['skipSunday']==true;
      final allowedStart=old==null?examDateKey(start):(old['startDate'] as String);
      final allowedEnd=old==null?examDateKey(end):(old['endDate'] as String);
      for(final p in papers) {
        final day=examDateKey(p.date);
        if(day.compareTo(allowedStart)<0 || day.compareTo(allowedEnd)>0 || off.containsKey(day) ||
          (skip && p.date.weekday==DateTime.sunday)) throw StateError('Paper date $day is outside the active examination calendar.');
      }
      final slots=examStringMap(old?['slots']);
      for(var i=0;i<papers.length;i++) {
        final slot=examSlot(classId,examDateKey(papers[i].date));
        if(slots.containsKey(slot)) throw StateError('The class already has a paper on this date.');
        slots[slot]=refs[i].id;
      }
      if(old==null) {
        tx.set(cycleRef,{
          'academicYear':year,'category':category,'title':title.trim(),'status':'active',
          'startDate':allowedStart,'endDate':allowedEnd,'excludedDates':off,'skipSunday':skip,
          'plannedClassIds':planned,'classIds':[classId],'paperIds':paperIds,
          'releasedPaperIds':<String>[],'slots':slots,'lastClassId':classId,
          'createdBy':user.uid,'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp(),
        });
        tx.set(termControl,{'cycleId':id,'updatedAt':FieldValue.serverTimestamp()});
      } else {
        tx.update(cycleRef,{'classIds':FieldValue.arrayUnion([classId]),
          'paperIds':FieldValue.arrayUnion(paperIds),'slots':slots,'lastClassId':classId,
          'updatedAt':FieldValue.serverTimestamp()});
      }
      for(var i=0;i<papers.length;i++) {
        tx.set(refs[i],{...fields(papers[i]),'cycleId':id,'expectedStudentIds':students.keys.toList(),
          'rosterSnapshot':students,'markedStudentIds':<String>[]});
      }
    });
  }

  Future<void> setTermResult(String examId,{required bool release}) async {
    final paperRef=db.collection('examinations').doc(examId);
    await db.runTransaction((tx) async {
      final paper=(await tx.get(paperRef)).data();
      if(paper==null) throw StateError('Paper not found.');
      final id=paper['cycleId'];
      if(id is! String) {
        tx.update(paperRef,{'resultStatus':release?'released':'draft','updatedAt':FieldValue.serverTimestamp()});
        return;
      }
      final ref=terms.doc(id);
      final cycle=(await tx.get(ref)).data();
      if(cycle==null || cycle['status']!='active') throw StateError('This examination is closed.');
      final expected=examStrings(paper['expectedStudentIds']);
      final marked=examStrings(paper['markedStudentIds']);
      if(release && (paper['resultStatus']!='submitted' || expected.isEmpty || !marked.toSet().containsAll(expected))) {
        throw StateError('All student marks must be submitted before releasing results.');
      }
      if(release && (cycle['excludedDates'] as Map).containsKey(paper['examDate'])) throw StateError('Reschedule the paper from the school closure date first.');
      if(release && (paper['endAt'] as Timestamp).toDate().isAfter(DateTime.now())) throw StateError('The paper has not ended yet.');
      tx.update(paperRef,{'resultStatus':release?'released':'draft','updatedAt':FieldValue.serverTimestamp()});
      tx.update(ref,{'releasedPaperIds':release?FieldValue.arrayUnion([examId]):FieldValue.arrayRemove([examId]),
        'lastPaperId':examId,'updatedAt':FieldValue.serverTimestamp()});
    });
  }

  Future<void> closeTerm(String id) async {
    final user=_auth.currentUser;
    if(user==null) throw StateError('Sign in again.');
    await db.runTransaction((tx) async {
      final ref=terms.doc(id);
      final cycle=(await tx.get(ref)).data();
      if(cycle==null || !termReadyToClose(cycle)) throw StateError('Schedule every planned class and release every paper result before closing.');
      tx.update(ref,{'status':'closed','closedBy':user.uid,'closedAt':FieldValue.serverTimestamp(),
        'updatedAt':FieldValue.serverTimestamp()});
    });
  }

  Future<void> markSchoolClosure(String id,String date,String reason) async {
    if(reason.trim().isEmpty || reason.length>200) throw ArgumentError('Enter a reason (up to 200 characters).');
    final affected=await db.collection('examinations').where('cycleId',isEqualTo:id)
      .get(const GetOptions(source:Source.server));
    if(affected.docs.any((doc) { final p=doc.data(); return p['examDate']==date &&
      (p['resultStatus']!='draft' || examStrings(p['markedStudentIds']).isNotEmpty); })) {
      throw StateError('A paper on this date already has recorded marks or released results. Choose another closure date.');
    }
    await db.runTransaction((tx) async {
      final ref=terms.doc(id);
      final cycle=(await tx.get(ref)).data();
      if(cycle==null || cycle['status']!='active') throw StateError('The examination is closed.');
      final off=examStringMap(cycle['excludedDates']);
      off[date]=reason.trim();
      tx.update(ref,{'excludedDates':off,'updatedAt':FieldValue.serverTimestamp()});
    });
  }

  Future<void> removeSchoolClosure(String id,String date) async {
    await db.runTransaction((tx) async {
      final ref=terms.doc(id);
      final cycle=(await tx.get(ref)).data();
      if(cycle==null || cycle['status']!='active') throw StateError('The examination is closed.');
      final off=examStringMap(cycle['excludedDates']);
      off.remove(date);
      tx.update(ref,{'excludedDates':off,'updatedAt':FieldValue.serverTimestamp()});
    });
  }

  Future<void> reschedulePaper(String examId,DateTime newDate,int startMinute,int endMinute,String reason) async {
    final user=_auth.currentUser;
    if(user==null) throw StateError('Sign in again.');
    if(reason.trim().isEmpty || reason.length>200 || startMinute<0 || endMinute>=1440 ||
       endMinute<=startMinute || endMinute-startMinute>600) throw ArgumentError('Enter a reason and valid paper times.');
    await db.runTransaction((tx) async {
      final ref=db.collection('examinations').doc(examId);
      final paper=(await tx.get(ref)).data();
      if(paper==null || paper['cycleId'] is! String) throw StateError('Only active term-cycle papers can be rescheduled.');
      final cycleRef=terms.doc(paper['cycleId'] as String);
      final cycle=(await tx.get(cycleRef)).data();
      if(cycle==null || cycle['status']!='active' || paper['resultStatus']!='draft' ||
        examStrings(paper['markedStudentIds']).isNotEmpty) throw StateError('Only unmarked draft papers can be rescheduled.');
      final day=examDateKey(newDate);
      if(day.compareTo(cycle['startDate'] as String)<0 || (cycle['excludedDates'] as Map).containsKey(day) ||
        (cycle['skipSunday']==true && newDate.weekday==DateTime.sunday)) throw StateError('Choose an available examination day.');
      if(!examInstant(newDate,endMinute).isAfter(DateTime.now())) throw StateError('Choose a future examination time.');
      final slots=examStringMap(cycle['slots']);
      final oldSlot=examSlot(paper['classId'] as String,paper['examDate'] as String);
      final newSlot=examSlot(paper['classId'] as String,day);
      if(slots.containsKey(newSlot) && slots[newSlot]!=examId) throw StateError('This class already has a paper on that date.');
      slots.remove(oldSlot); slots[newSlot]=examId;
      final end=(cycle['endDate'] as String).compareTo(day)<0?day:cycle['endDate'];
      final history=List<dynamic>.from(paper['rescheduleHistory'] as List? ?? []);
      history.add({'previousDate':paper['examDate'],'previousStartMinute':paper['startMinute'],
        'previousEndMinute':paper['endMinute'],'newDate':day,'newStartMinute':startMinute,
        'newEndMinute':endMinute,'reason':reason.trim(),'by':user.uid,'at':Timestamp.now()});
      tx.update(ref,{'examDate':day,'startMinute':startMinute,'endMinute':endMinute,
        'durationMinutes':endMinute-startMinute,'endAt':Timestamp.fromDate(examInstant(newDate,endMinute)),
        'endDate':end,'rescheduleReason':reason.trim(),'rescheduleHistory':history,
        'updatedAt':FieldValue.serverTimestamp()});
      tx.update(cycleRef,{'slots':slots,'endDate':end,'lastPaperId':examId,'updatedAt':FieldValue.serverTimestamp()});
    });
  }

  Future<void> createAssignment({required TeacherAssignment assignment,
    required String title, required String instructions, required DateTime dueDate}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in again.');
    if (title.trim().isEmpty || title.trim().length > 100) throw ArgumentError('Enter an assignment title.');
    await db.collection('classwork').add({
      'kind': 'assignment', 'title': title.trim(), 'instructions': instructions.trim(),
      'dueDate': examDateKey(dueDate), 'assignmentId': assignment.id,
      'staffId': assignment.staffId, 'teacherUid': user.uid,
      'classId': assignment.classId, 'className': assignment.className,
      'subject': assignment.subject, 'active': true,
      'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Only owner/principal may copy a teacher name into the limited directory.
  // Examiner never reads full staff profiles.
  Future<int> syncTeacherNames() async {
    final staff = await db.collection('staff').get(const GetOptions(source: Source.server));
    var batch = db.batch();
    var pending = 0;
    var total = 0;
    for (final doc in staff.docs) {
      final data = doc.data();
      if (data['roleType'] != 'teacher') continue;
      batch.set(db.collection('exam_teacher_directory').doc(doc.id), {
        'name': (data['fullName'] ?? doc.id).toString(),
        'active': data['active'] == true,
      });
      total++;
      if (++pending == 10) {
        await batch.commit();
        batch = db.batch(); pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
    return total;
  }
}
