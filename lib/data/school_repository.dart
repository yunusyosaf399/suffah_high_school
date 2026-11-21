import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Small typed model for the school's long-lived class/section catalog.
class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    required this.section,
    required this.active,
  });

  final String id;
  final String name;
  final String section;
  final bool active;

  String get label => section.isEmpty ? name : '$name – $section';

  factory SchoolClass.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return SchoolClass(
      id: snapshot.id,
      name: (data['name'] as String?) ?? '',
      section: (data['section'] as String?) ?? '',
      active: data['active'] != false,
    );
  }
}

class StudentRecord {
  const StudentRecord({
    required this.id,
    required this.admissionNo,
    required this.fullName,
    required this.classId,
    required this.guardianName,
    required this.guardianPhone,
    required this.gender,
    required this.rollNo,
    required this.active,
    this.status = 'admitted',
  });

  final String id;
  final String admissionNo;
  final String fullName;
  final String classId;
  final String guardianName;
  final String guardianPhone;
  final String gender;
  final String rollNo;
  final bool active;
  final String status;
  bool get isDraft => status == 'draft';

  factory StudentRecord.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return StudentRecord(
      id: snapshot.id,
      admissionNo: (data['admissionNo'] as String?) ?? snapshot.id,
      fullName: (data['fullName'] as String?) ?? '',
      classId: (data['classId'] as String?) ?? '',
      guardianName: (data['guardianName'] as String?) ?? '',
      guardianPhone: (data['guardianPhone'] as String?) ?? '',
      gender: (data['gender'] as String?) ?? 'Not specified',
      rollNo: (data['rollNo'] as String?) ?? '',
      active: data['active'] != false,
      status: (data['status'] as String?) ?? 'admitted',
    );
  }
}

class SchoolSummary {
  const SchoolSummary({required this.students, required this.classes});
  final int students;
  final int classes;
}

/// Keep admission number as a stable document ID to reject duplicates.
String normalizedAdmissionNo(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

bool validAdmissionNo(String value) =>
    RegExp(r'^[A-Z0-9-]{1,24}$').hasMatch(normalizedAdmissionNo(value));

String classDocumentId(String name, String section) {
  final key = [name.trim(), section.trim()].where((s) => s.isNotEmpty).join('-');
  return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class SchoolRepository {
  SchoolRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _classes =>
      _db.collection('classes');

  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection('students');

  // Start with a bounded online read, then attach live updates. This avoids
  // relying solely on the first snapshot event on Android.
  Stream<List<SchoolClass>> watchClasses() async* {
    final query = _classes.orderBy('sortKey');
    final first = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    yield first.docs.map(SchoolClass.fromSnapshot).toList();
    yield* query.snapshots().map(
      (snap) => snap.docs.map(SchoolClass.fromSnapshot).toList(),
    );
  }

  Stream<List<StudentRecord>> watchStudents() async* {
    final query = _students.orderBy('fullName').limit(1000);
    final first = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    yield first.docs.map(StudentRecord.fromSnapshot).toList();
    yield* query.snapshots().map(
      (snap) => snap.docs.map(StudentRecord.fromSnapshot).toList(),
    );
  }

  Future<SchoolSummary> loadSummary() async {
    final totals = await Future.wait([
      _students.count().get(),
      _classes.count().get(),
    ]);
    return SchoolSummary(
      students: totals[0].count ?? 0,
      classes: totals[1].count ?? 0,
    );
  }

  /// Explicit server read to distinguish offline/permission failures from
  /// an empty class list. Nothing is written during this check.
  Future<void> verifyFirestoreConnection() async {
    await _classes
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
  }

  Future<void> createClass({required String name, String section = ''}) async {
    final cleanName = name.trim();
    final cleanSection = section.trim().toUpperCase();
    final id = classDocumentId(cleanName, cleanSection);
    if (cleanName.isEmpty || id.isEmpty) {
      throw ArgumentError('Enter a valid class name.');
    }
    final ref = _classes.doc(id);
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        throw StateError('This class and section already exist.');
      }
      transaction.set(ref, {
        'name': cleanName,
        'section': cleanSection,
        'sortKey': [cleanName, cleanSection].join(' ').toLowerCase(),
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setClassActive(String id, bool active) =>
      _classes.doc(id).update({'active': active});

  Future<void> saveStudent({
    String? existingId,
    required String admissionNo,
    required String fullName,
    required String classId,
    required String guardianName,
    required String guardianPhone,
    required String gender,
    required String rollNo,
  }) async {
    final normalized = normalizedAdmissionNo(admissionNo);
    if (!validAdmissionNo(normalized)) {
      throw ArgumentError('Admission number must use letters, digits or hyphens.');
    }
    final name = fullName.trim();
    if (name.isEmpty || classId.isEmpty) {
      throw ArgumentError('Student name and class are required.');
    }
    final fields = <String, dynamic>{
      'fullName': name,
      'searchName': name.toLowerCase(),
      'classId': classId,
      'guardianName': guardianName.trim(),
      'guardianPhone': guardianPhone.trim(),
      'gender': gender,
      'rollNo': rollNo.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existingId != null) {
      // Admission number is fixed after creation to prevent broken references.
      await _students.doc(existingId).update(fields);
      return;
    }

    final ref = _students.doc(normalized);
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        throw StateError('This admission number is already used.');
      }
      transaction.set(ref, {
        ...fields,
        'admissionNo': normalized,
        'active': true,
        'parentUids': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setStudentActive(String id, bool active) =>
      _students.doc(id).update({
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
