import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'school_repository.dart';

/// One Firestore document per student per school day, nested under a class/day
/// reference. Parent access can later be scoped to just that student's mark.
const attendanceStatuses = <String>[
  'present',
  'absent',
  'late',
  'leave',
];

const attendanceStatusLabels = <String, String>{
  'present': 'Present',
  'absent': 'Absent',
  'late': 'Late',
  'leave': 'Leave',
  'unmarked': 'Not marked',
};

bool canManageAttendance(String role) =>
    role == 'owner' || role == 'principal';

String attendanceDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String attendanceDayId(String classId, DateTime date) {
  if (classId.isEmpty || classId.contains('/') || classId.length > 100) {
    throw ArgumentError('Select a valid class.');
  }
  return '${classId}_${attendanceDateKey(date).replaceAll('-', '')}';
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
    required this.leave,
  });

  final int total;
  final int present;
  final int absent;
  final int late;
  final int leave;

  int get marked => present + absent + late + leave;
  int get unmarked => total - marked;
  bool get complete => total > 0 && unmarked == 0;

  factory AttendanceSummary.fromMarks(
    List<StudentRecord> roster,
    Map<String, String> marks,
  ) {
    var present = 0;
    var absent = 0;
    var late = 0;
    var leave = 0;
    for (final student in roster) {
      switch (marks[student.id]) {
        case 'present':
          present++;
        case 'absent':
          absent++;
        case 'late':
          late++;
        case 'leave':
          leave++;
      }
    }
    return AttendanceSummary(
      total: roster.length,
      present: present,
      absent: absent,
      late: late,
      leave: leave,
    );
  }
}

/// Uses one direct class query plus one direct class/day subcollection query.
/// No cross-collection scan or composite index is needed to load a register.
class AttendanceRepository {
  AttendanceRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<List<StudentRecord>> loadRoster(String classId) async {
    if (classId.isEmpty) throw ArgumentError('Select a class first.');
    final snap = await _db
        .collection('students')
        .where('classId', isEqualTo: classId)
        .limit(1000)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    final roster = snap.docs
        .map(StudentRecord.fromSnapshot)
        .where((record) => record.active && !record.isDraft)
        .toList();

    roster.sort((a, b) {
      final aRoll = int.tryParse(a.rollNo);
      final bRoll = int.tryParse(b.rollNo);
      if (aRoll != null && bRoll != null && aRoll != bRoll) {
        return aRoll.compareTo(bRoll);
      }
      if (aRoll != null && bRoll == null) return -1;
      if (aRoll == null && bRoll != null) return 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return roster;
  }

  /// Teachers receive only the safe name/roll-number projection.
  /// Guardian contacts, addresses and other student details are not read.
  Future<List<StudentRecord>> loadSafeRoster(String classId) async {
    if (classId.isEmpty || classId.contains('/')) {
      throw ArgumentError('Select a valid class.');
    }
    final snap = await _db.collection('class_rosters').doc(classId)
        .collection('students')
        .where('active', isEqualTo: true)
        .limit(1000)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    final roster = snap.docs.map(StudentRecord.fromSnapshot).toList();
    roster.sort((a, b) {
      final aRoll = int.tryParse(a.rollNo);
      final bRoll = int.tryParse(b.rollNo);
      if (aRoll != null && bRoll != null && aRoll != bRoll) {
        return aRoll.compareTo(bRoll);
      }
      if (aRoll != null && bRoll == null) return -1;
      if (aRoll == null && bRoll != null) return 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return roster;
  }

  Future<Map<String, String>> loadMarks(
    String classId,
    DateTime date, {
    bool forAttendanceTeacher = false,
  }) async {
    final id = attendanceDayId(classId, date);
    final marksQuery = _db.collection('attendance_days').doc(id)
        .collection('marks');
    // The class filter lets Firestore prove the teacher's permitted scope.
    final snap = await (forAttendanceTeacher
        ? marksQuery.where('classId', isEqualTo: classId)
        : marksQuery)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return {
      for (final doc in snap.docs)
        if (attendanceStatuses.contains(doc.data()['status']))
          doc.id: doc.data()['status'] as String,
    };
  }

  /// Save only changed students, preserving previously recorded marks.
  ///
  /// 400 student writes per batch stay well under Firestore's 500-operation
  /// limit; for exceptionally large classes batches are committed sequentially.
  /// A retry is safe: the same student/day IDs are overwritten, not duplicated.
  Future<void> saveChanges({
    required String classId,
    required DateTime date,
    required Map<String, String> changes,
    bool forAttendanceTeacher = false,
  }) async {
    if (changes.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (DateTime(date.year, date.month, date.day).isAfter(today)) {
      throw ArgumentError('Future attendance cannot be recorded.');
    }
    attendanceDayId(classId, date);
    for (final entry in changes.entries) {
      if (entry.key.isEmpty || entry.key.contains('/')) {
        throw ArgumentError('Invalid student registration ID.');
      }
      if (!attendanceStatuses.contains(entry.value) &&
          entry.value != 'unmarked') {
        throw ArgumentError('Invalid attendance status.');
      }
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before recording attendance.');

    final dayRef = _db
        .collection('attendance_days')
        .doc(attendanceDayId(classId, date));
    final entries = changes.entries.toList();
    // Teacher writes check each student's safe roster record in Rules.
    // Keep these batches small to respect Firestore's per-batch read limits.
    final batchSize = forAttendanceTeacher ? 4 : 10;

    for (var start = 0; start < entries.length; start += batchSize) {
      final end = start + batchSize < entries.length
          ? start + batchSize
          : entries.length;
      final batch = _db.batch();
      batch.set(dayRef, {
        'classId': classId,
        'date': attendanceDateKey(date),
        'lastEditedAt': FieldValue.serverTimestamp(),
        'lastEditedBy': user.uid,
      }, SetOptions(merge: true));

      for (final entry in entries.sublist(start, end)) {
        batch.set(dayRef.collection('marks').doc(entry.key), {
          'studentId': entry.key,
          'classId': classId,
          'date': attendanceDateKey(date),
          'status': entry.value,
          'updatedBy': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.set(_db.collection('parent_attendance').doc(entry.key).collection('days').doc(dayRef.id),{
          'studentId':entry.key,'classId':classId,'date':attendanceDateKey(date),'status':entry.value,
        });
      }
      await batch.commit().timeout(const Duration(seconds: 30));
    }
  }
}
