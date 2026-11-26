import 'dart:math';
import 'package:flutter/material.dart';
import 'package:suffah_high_school/screens/exam_creation_wizard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/class_subject_repository.dart';
import 'package:suffah_high_school/data/examination_repository.dart';
import 'package:suffah_high_school/data/staff_repository.dart';

void main() {
  const assignment = TeacherAssignment(id:'a', staffId:'t', classId:'c', subject:'Math', active:true);
  final start = DateTime(2026,12,1);
  final end = DateTime(2026,12,10);
  String? check(List<ExamPaperDraft> papers) => validateExamSchedule(kind:'term',
    category:'First Term', title:'Term 1', start:start, end:end,papers:papers);
  test('term schedule validates date range and duplicate subject paper', () {
    final theory = ExamPaperDraft(assignment:assignment,date:start);
    expect(check([theory]),isNull);
    expect(check([theory,theory]),isNotNull);
    expect(check([theory, ExamPaperDraft(assignment:assignment,date:end,type:'Practical / Lab')]),isNull);
    expect(check([ExamPaperDraft(assignment:assignment,date:DateTime(2026,12,11))]),isNotNull);
    expect(check([ExamPaperDraft(assignment:assignment,date:start,maxMarks:double.nan)]),isNotNull);
  });
  test('auto schedule includes every active subject, preserves settings and flags missing teachers', () {
    const subjects=[
      ClassSubject(id:'math',classId:'c',name:'Math',active:true),
      ClassSubject(id:'english',classId:'c',name:'English',active:true),
      ClassSubject(id:'science',classId:'c',name:'Science',active:true),
      ClassSubject(id:'old',classId:'c',name:'Old',active:false),
    ];
    const teachers=[
      TeacherAssignment(id:'a',staffId:'t',classId:'c',subject:'Math',subjectId:'math',active:true),
      TeacherAssignment(id:'b',staffId:'u',classId:'c',subject:'English',subjectId:'english',active:true),
    ];
    final days=examCalendarDays(start,end,skipSunday:true);
    final papers=generateClassExamSchedule(classId:'c',className:'Class C',subjects:subjects,
      assignments:teachers,days:days,maxMarks:75,durationMinutes:90);
    expect(papers.map((p)=>p.assignment.subject),['English','Math','Science']);
    expect(papers.map((p)=>p.date).toSet().length,3);
    expect(papers.every((p)=>p.date.weekday!=DateTime.sunday && p.maxMarks==75 && p.durationMinutes==90),isTrue);
    expect(papers.last.assignment.active,isFalse);
    expect(check(papers),contains('Science'));
    final customized=[papers.first.copyWith(maxMarks:50,instructions:'Custom'),...papers.skip(1)];
    final shuffled=shuffleExamPapers(customized,random:Random(42));
    expect(shuffled.map((p)=>p.assignment.subject).toList(),isNot(customized.map((p)=>p.assignment.subject).toList()));
    expect(shuffled.map((p)=>p.date),customized.map((p)=>p.date));
    expect(shuffled.firstWhere((p)=>p.assignment.subject=='English').maxMarks,50);
    expect(shuffled.firstWhere((p)=>p.assignment.subject=='English').instructions,'Custom');
    expect(()=>examDateSlots([start],3),throwsArgumentError);
    final adjusted=redistributeExamPapers(customized,examCalendarDays(DateTime(2026,12,11),DateTime(2026,12,15)));
    expect(adjusted.map((p)=>p.assignment.id),customized.map((p)=>p.assignment.id));
    expect(adjusted.first.date,DateTime(2026,12,11));
  });

  test('term papers cannot share a date', () {
    const other=TeacherAssignment(id:'b',staffId:'u',classId:'c',subject:'English',active:true);
    expect(check([ExamPaperDraft(assignment:assignment,date:start),
      ExamPaperDraft(assignment:other,date:start)]),contains('one paper'));
  });

  testWidgets('select multiple classes and edit and shuffle the combined timetable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500,1200));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    const c1=[
      ClassSubject(id:'math',classId:'c',name:'Math',active:true),
      ClassSubject(id:'english',classId:'c',name:'English',active:true),
    ];
    const c2=[
      ClassSubject(id:'math2',classId:'d',name:'Math',active:true),
      ClassSubject(id:'science',classId:'d',name:'Science',active:true),
    ];
    const teachers=[
      TeacherAssignment(id:'a',staffId:'t',classId:'c',subject:'Math',subjectId:'math',active:true),
      TeacherAssignment(id:'b',staffId:'u',classId:'c',subject:'English',subjectId:'english',active:true),
      TeacherAssignment(id:'d',staffId:'v',classId:'d',subject:'Science',subjectId:'science',active:true),
      TeacherAssignment(id:'e',staffId:'w',classId:'d',subject:'Math',subjectId:'math2',active:true),
    ];
    await tester.pumpWidget(MaterialApp(home:ExamCreationWizard(role:'owner',
      assignments:teachers,classSubjects:{'c':c1,'d':c2},classNames:{'c':'Class 5-A','d':'Class 6-A'},
      initialDateRange:DateTimeRange(start:start,end:end))));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exam_class_c')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 classes selected'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exam_class_d')));
    await tester.pumpAndSettle();
    expect(find.text('4 generated papers • 10 available examination days'),findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable),findsOneWidget);
    expect(find.text('2 classes • 4 papers'),findsOneWidget);
    final before=tester.widget<DataTable>(find.byType(DataTable)).rows.map((r)=>
      (r.cells[2].child as Text).data).toList();
    await tester.tap(find.text('Shuffle subjects'));
    await tester.pumpAndSettle();
    final after=tester.widget<DataTable>(find.byType(DataTable)).rows.map((r)=>
      (r.cells[2].child as Text).data).toList();
    expect(after,isNot(before));
    expect(after.where((s)=>s=='Math').length,2);
    expect(find.byTooltip('Edit paper'),findsNWidgets(4));
    expect(tester.takeException(),isNull);
  });

  test('multi-class shuffle preserves each class calendar and subject details', () {
    const other=TeacherAssignment(id:'b',staffId:'u',classId:'d',subject:'Math',active:true);
    const second=TeacherAssignment(id:'c',staffId:'v',classId:'c',subject:'English',active:true);
    final papers=[ExamPaperDraft(assignment:assignment,date:start,maxMarks:75),
      ExamPaperDraft(assignment:second,date:end),
      ExamPaperDraft(assignment:other,date:start,startMinute:600)];
    final result=groupExamPapersByClass(shuffleClassSchedules(papers,random:Random(1)));
    expect(result.keys.toSet(),{'c','d'});
    expect(result['c']!.first.assignment.subject,'English');
    expect(result['c']!.last.maxMarks,75);
    expect(result['d']!.single.date,start);
    expect(result['d']!.single.startMinute,600);
  });

  test('school holidays are excluded from automatic date generation', () {
    final days=examCalendarDays(start,end,skipSunday:true,excludedDates:{'2026-12-03','2026-12-05'});
    expect(days.map(examDateKey),isNot(contains('2026-12-03')));
    expect(days.map(examDateKey),isNot(contains('2026-12-05')));
    expect(days.every((d)=>d.weekday!=DateTime.sunday),isTrue);
    expect(examDateSlots(days,3).map(examDateKey).toSet().length,3);
  });

  test('paper time validation and shuffle preserve timings', () {
    final paper=ExamPaperDraft(assignment:assignment,date:start,startMinute:600,durationMinutes:120);
    expect(paper.endMinute,720);
    expect(examClock(paper.startMinute),'10:00');
    expect(examInstant(start,paper.startMinute),DateTime.utc(2026,12,1,5));
    expect(check([paper]),isNull);
    expect(check([paper.copyWith(startMinute:1430)]),isNotNull);
    final moved=paper.copyWith(date:end);
    expect(moved.startMinute,600);
    expect(moved.durationMinutes,120);
  });

  test('term closure requires all planned classes and every paper released', () {
    final cycle=<String,dynamic>{'status':'active','plannedClassIds':['C1','C2'],
      'classIds':['C1'],'paperIds':['P1','P2'],'releasedPaperIds':['P1']};
    expect(termReadyToClose(cycle),isFalse);
    cycle['classIds']=['C1','C2'];
    expect(termReadyToClose(cycle),isFalse);
    cycle['releasedPaperIds']=['P1','P2'];
    expect(termReadyToClose(cycle),isTrue);
    cycle['status']='closed';
    expect(termReadyToClose(cycle),isFalse);
    expect(termCycleId(2026,'First Term'),'2026_first');
  });

  test('formal exams are restricted to exam administrators', () {
    expect(canScheduleFormalExams('examiner'),isTrue);
    expect(canScheduleFormalExams('teacher'),isFalse);
    expect(canScheduleFormalExams('canteen_seller'),isFalse);
  });
}
