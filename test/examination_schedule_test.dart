import 'dart:math';
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

  test('formal exams are restricted to exam administrators', () {
    expect(canScheduleFormalExams('examiner'),isTrue);
    expect(canScheduleFormalExams('teacher'),isFalse);
    expect(canScheduleFormalExams('canteen_seller'),isFalse);
  });
}
