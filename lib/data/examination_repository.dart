import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'staff_repository.dart';

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
    this.instructions = ''});
  final TeacherAssignment assignment;
  final DateTime date;
  final String type;
  final double maxMarks;
  final int durationMinutes;
  final String instructions;
}

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
  for (final paper in papers) {
    final a = paper.assignment;
    if (!a.active || a.classId != papers.first.assignment.classId) return 'Choose active assignments for one class.';
    if (paper.date.isBefore(start) || paper.date.isAfter(end)) return 'Every paper date must be inside the exam date range.';
    if (!paperTypes.contains(paper.type) || !paper.maxMarks.isFinite ||
        paper.maxMarks <= 0 || paper.maxMarks > 1000 ||
        paper.durationMinutes < 1 || paper.durationMinutes > 600) {
      return 'Check paper type, marks (1–1000) and duration (1–600 minutes).';
    }
    if (!seen.add('${a.subject.toLowerCase()}|${paper.type}')) {
      return 'A subject and paper type cannot be added twice.';
    }
  }
  return null;
}

class ExaminationRepository {
  ExaminationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore db;
  final FirebaseAuth _auth;

  Future<void> publishSchedule({required String role, required String kind,
    required String category, required String title, required DateTime start,
    required DateTime end, required List<ExamPaperDraft> papers}) async {
    if (kind != 'term' && kind != 'test') throw ArgumentError('Unsupported assessment type.');
    if (kind == 'term' && !canScheduleFormalExams(role)) throw StateError('Only exam administrators can schedule term examinations.');
    final error = validateExamSchedule(kind: kind, category: category, title: title,
      start: start, end: end, papers: papers);
    if (error != null) throw ArgumentError(error);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in again.');
    final exams = db.collection('examinations');
    final sessionId = exams.doc().id;
    final batch = db.batch();
    for (final paper in papers) {
      final a = paper.assignment;
      batch.set(exams.doc(), {
        'sessionId': sessionId, 'kind': kind, 'category': category,
        'sessionTitle': title.trim(), 'title': '${title.trim()} – ${a.subject}',
        'startDate': examDateKey(start), 'endDate': examDateKey(end),
        'examDate': examDateKey(paper.date), 'paperType': paper.type,
        'durationMinutes': paper.durationMinutes, 'instructions': paper.instructions.trim(),
        'assignmentId': a.id, 'staffId': a.staffId, 'classId': a.classId,
        'className': a.className, 'subject': a.subject,
        'maxMarks': paper.maxMarks, 'active': true, 'resultStatus': 'draft',
        'createdBy': user.uid, 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
