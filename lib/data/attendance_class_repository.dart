import 'package:cloud_firestore/cloud_firestore.dart';

/// Homeroom/attendance responsibility is separate from subject teaching.
/// Each active teacher can manage attendance for at most one class and
/// each class has at most one designated attendance teacher.
class AttendanceClassAssignment {
  const AttendanceClassAssignment({
    required this.classId,
    required this.staffId,
    required this.className,
    required this.staffName,
    this.active = true,
  });

  final String classId;
  final String staffId;
  final String className;
  final String staffName;
  final bool active;

  factory AttendanceClassAssignment.fromMap(Map<String, dynamic> data) =>
      AttendanceClassAssignment(
        classId: (data['classId'] as String?) ?? '',
        staffId: (data['staffId'] as String?) ?? '',
        className: (data['className'] as String?) ?? '',
        staffName: (data['staffName'] as String?) ?? '',
        active: data['active'] == true,
      );
}

class AttendanceClassRepository {
  AttendanceClassRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _db.collection('attendance_class_assignments');
  CollectionReference<Map<String, dynamic>> get _teacherLinks =>
      _db.collection('attendance_teacher_links');

  Stream<List<AttendanceClassAssignment>> watchAssignments() => _assignments
      .limit(300)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => AttendanceClassAssignment.fromMap(doc.data()))
          .where((record) => record.active)
          .toList());

  /// A teacher can read only their own link; they never enumerate all classes.
  Stream<AttendanceClassAssignment?> watchForTeacher(String staffId) {
    if (staffId.isEmpty || staffId.contains('/')) {
      throw ArgumentError('Invalid staff member.');
    }
    return _teacherLinks.doc(staffId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final record = AttendanceClassAssignment.fromMap(
          snapshot.data() ?? <String, dynamic>{});
      return record.active && record.staffId == staffId ? record : null;
    });
  }

  Future<void> assignClass({
    required String staffId,
    required String classId,
  }) async {
    if (staffId.isEmpty || staffId.contains('/') ||
        classId.isEmpty || classId.contains('/')) {
      throw ArgumentError('Select a valid teacher and class.');
    }
    final staffRef = _db.collection('staff').doc(staffId);
    final classRef = _db.collection('classes').doc(classId);
    final teacherLink = _teacherLinks.doc(staffId);
    final classAssignment = _assignments.doc(classId);

    await _db.runTransaction((tx) async {
      final staff = await tx.get(staffRef);
      final schoolClass = await tx.get(classRef);
      final currentTeacher = await tx.get(teacherLink);
      final currentClass = await tx.get(classAssignment);

      if (staff.data()?['active'] != true ||
          staff.data()?['roleType'] != 'teacher') {
        throw StateError('Select an active teacher.');
      }
      if (schoolClass.data()?['active'] != true) {
        throw StateError('Select an active class.');
      }

      final oldClassId =
          (currentTeacher.data()?['classId'] as String?) ?? '';
      final oldStaffId =
          (currentClass.data()?['staffId'] as String?) ?? '';

      DocumentSnapshot<Map<String, dynamic>>? oldClassAssignment;
      DocumentSnapshot<Map<String, dynamic>>? oldTeacherLink;
      if (oldClassId.isNotEmpty && oldClassId != classId) {
        oldClassAssignment = await tx.get(_assignments.doc(oldClassId));
        if (oldClassAssignment.data()?['staffId'] != staffId) {
          throw StateError('Existing attendance responsibility is inconsistent. '
              'Ask the owner to check the class assignments.');
        }
      }
      if (oldStaffId.isNotEmpty && oldStaffId != staffId) {
        oldTeacherLink = await tx.get(_teacherLinks.doc(oldStaffId));
        if (oldTeacherLink.data()?['classId'] != classId) {
          throw StateError('Existing class teacher link is inconsistent. '
              'Ask the owner to check the class assignments.');
        }
      }

      // All reads are complete. Reassignment removes the superseded links in
      // the same transaction; neither historical attendance nor staff is deleted.
      if (oldClassAssignment != null) {
        tx.delete(_assignments.doc(oldClassId));
      }
      if (oldTeacherLink != null) {
        tx.delete(_teacherLinks.doc(oldStaffId));
      }

      final classData = schoolClass.data() ?? <String, dynamic>{};
      final className = [
        (classData['name'] as String?) ?? '',
        (classData['section'] as String?) ?? '',
      ].where((part) => part.isNotEmpty).join(' – ');
      final data = <String, dynamic>{
        'classId': classId,
        'className': className,
        'staffId': staffId,
        'staffName': (staff.data()?['fullName'] as String?) ?? '',
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(classAssignment, data, SetOptions(merge: true));
      tx.set(teacherLink, data, SetOptions(merge: true));
    });
  }

  Future<void> removeClass(String classId) async {
    if (classId.isEmpty || classId.contains('/')) {
      throw ArgumentError('Invalid class.');
    }
    final assignmentRef = _assignments.doc(classId);
    await _db.runTransaction((tx) async {
      final assignment = await tx.get(assignmentRef);
      if (!assignment.exists) return;
      final staffId = (assignment.data()?['staffId'] as String?) ?? '';
      if (staffId.isEmpty) {
        throw StateError('The assignment has no teacher.');
      }
      final linkRef = _teacherLinks.doc(staffId);
      final link = await tx.get(linkRef);
      if (link.data()?['classId'] != classId) {
        throw StateError('The attendance assignment link is inconsistent.');
      }
      tx.delete(assignmentRef);
      tx.delete(linkRef);
    });
  }
}
