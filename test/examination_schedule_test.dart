import 'package:flutter_test/flutter_test.dart';
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
  test('formal exams are restricted to exam administrators', () {
    expect(canScheduleFormalExams('examiner'),isTrue);
    expect(canScheduleFormalExams('teacher'),isFalse);
    expect(canScheduleFormalExams('canteen_seller'),isFalse);
  });
}
