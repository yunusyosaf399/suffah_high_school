import 'package:cloud_firestore/cloud_firestore.dart';

String registrationNumberFor(int year, int sequence) {
  if (year < 2000 || year > 9999 || sequence < 1 || sequence > 9999) {
    throw RangeError('Registration sequence must be 0001–9999.');
  }
  return 'ST-$year-${sequence.toString().padLeft(4, '0')}';
}

String rollNumberFor(int number) {
  if (number < 10000 || number > 99999) {
    throw RangeError('Roll number must be five digits.');
  }
  return number.toString();
}

String admissionFullName(Map<String, String> student) => [
  student['firstName'] ?? '',
  student['middleName'] ?? '',
  student['lastName'] ?? '',
].map((p) => p.trim()).where((p) => p.isNotEmpty).join(' ');

String? admissionValidationMessage(
  Map<String, Map<String, String>> details,
) {
  String value(String section, String key) =>
      (details[section]?[key] ?? '').trim();

  if (value('student', 'firstName').isEmpty ||
      value('student', 'lastName').isEmpty) {
    return 'Enter the student’s first and last name.';
  }
  if (value('student', 'dateOfBirth').isEmpty) {
    return 'Choose the date of birth.';
  }
  if (value('academic', 'classId').isEmpty) {
    return 'Choose a class and section.';
  }
  if (value('academic', 'campus').isEmpty) {
    return 'Enter a campus.';
  }
  if (value('guardian', 'firstName').isEmpty ||
      value('guardian', 'lastName').isEmpty ||
      value('guardian', 'relationship').isEmpty) {
    return 'Enter the guardian’s name and relationship.';
  }
  if (value('guardian', 'phone').isEmpty) {
    return 'Enter the guardian’s phone number.';
  }
  for (final email in [value('contact', 'email'), value('guardian', 'email')]) {
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
  }
  return null;
}

class AdmissionRecord {
  const AdmissionRecord({
    required this.id,
    required this.registrationNo,
    required this.rollNo,
    required this.status,
    required this.step,
    required this.details,
    this.photoPath = '',
    this.attachments = const {},
    this.active = true,
  });

  final String id;
  final String registrationNo;
  final String rollNo;
  final String status;
  final int step;
  final Map<String, Map<String, String>> details;
  final String photoPath;
  final Map<String, Map<String, dynamic>> attachments;
  final bool active;

  bool get isDraft => status != 'admitted';

  static Map<String, Map<String, String>> parseDetails(Map<String, dynamic> data) {
    final raw = data['details'];
    final parsed = <String, Map<String, String>>{};
    if (raw is Map) {
      for (final section in ['student', 'contact', 'guardian', 'academic', 'health']) {
        final source = raw[section];
        if (source is Map) {
          parsed[section] = source.map((key, value) =>
              MapEntry(key.toString(), value?.toString() ?? ''));
        }
      }
    }
    if (parsed.isEmpty) {
      final fullName = (data['fullName'] as String? ?? '').trim();
      final parts = fullName.isEmpty ? <String>[] : fullName.split(RegExp(r'\s+'));
      parsed['student'] = {
        'firstName': parts.isEmpty ? '' : parts.first,
        'lastName': parts.length > 1 ? parts.last : '',
        'middleName': parts.length > 2
            ? parts.sublist(1, parts.length - 1).join(' ') : '',
        'gender': (data['gender'] as String?) ?? 'Not specified',
      };
      parsed['guardian'] = {
        'firstName': (data['guardianName'] as String?) ?? '',
        'phone': (data['guardianPhone'] as String?) ?? '',
        'email': (data['guardianEmail'] as String?) ?? '',
      };
      parsed['academic'] = {'classId': (data['classId'] as String?) ?? ''};
    }
    return parsed;
  }

  factory AdmissionRecord.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => AdmissionRecord.fromData(snapshot.id, snapshot.data() ?? {});

  factory AdmissionRecord.fromData(String id, Map<String, dynamic> data) {
    final attachments = <String, Map<String, dynamic>>{};
    final source = data['attachments'];
    if (source is Map) {
      for (final entry in source.entries) {
        if (entry.value is Map) {
          attachments[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return AdmissionRecord(
      id: id,
      registrationNo: (data['admissionNo'] as String?) ?? id,
      rollNo: (data['rollNo'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'admitted',
      active: data['active'] != false,
      step: (data['currentStep'] as int?) ?? 0,
      details: parseDetails(data),
      attachments: attachments,
      photoPath: (data['photoPath'] as String?) ?? '',
    );
  }
}

class AdmissionRepository {
  AdmissionRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection('students');

  /// Server-side reservation in one transaction prevents duplicate IDs even
  /// when multiple administrators open draft forms at the same time.
  Future<AdmissionRecord> startDraft({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final year = today.year;
    final registrationCounter =
        _db.collection('counters').doc('student_registration_$year');
    final rollCounter = _db.collection('counters').doc('student_roll_global');
    final date = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    return _db.runTransaction((tx) async {
      final regSnapshot = await tx.get(registrationCounter);
      final rollSnapshot = await tx.get(rollCounter);
      final regSeq = ((regSnapshot.data()?['last'] as num?)?.toInt() ?? 0) + 1;
      final rollSeq = ((rollSnapshot.data()?['last'] as num?)?.toInt() ?? 9999) + 1;
      final registrationNo = registrationNumberFor(year, regSeq);
      final rollNo = rollNumberFor(rollSeq);
      final doc = _students.doc(registrationNo);
      final existing = await tx.get(doc);
      if (existing.exists) {
        throw StateError('Registration number exists. Check the counters.');
      }

      tx.set(registrationCounter, {
        'last': regSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(rollCounter, {
        'last': rollSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(doc, {
        'admissionNo': registrationNo,
        'rollNo': rollNo,
        'fullName': 'Draft – $registrationNo',
        'searchName': '',
        'guardianName': '',
        'guardianPhone': '',
        'classId': '',
        'status': 'draft',
        'currentStep': 0,
        'active': false,
        'parentUids': <String>[],
        'details': {
          'student': <String, String>{},
          'contact': <String, String>{},
          'guardian': <String, String>{},
          'academic': <String, String>{'admissionDate': date, 'campus': 'Main'},
          'health': <String, String>{},
        },
        'attachments': <String, dynamic>{},
        'photoPath': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return AdmissionRecord(
        id: registrationNo,
        registrationNo: registrationNo,
        rollNo: rollNo,
        status: 'draft',
        active: false,
        step: 0,
        details: {
          'student': {},
          'contact': {},
          'guardian': {},
          'academic': {'admissionDate': date, 'campus': 'Main'},
          'health': {},
        },
      );
    });
  }

  Future<AdmissionRecord> load(String id) async {
    final snapshot = await _students.doc(id)
        .get(const GetOptions(source: Source.server));
    if (!snapshot.exists) throw StateError('Admission not found.');
    return AdmissionRecord.fromSnapshot(snapshot);
  }

  /// Registration and roll numbers are never updated from form inputs.
  Future<void> save({
    required AdmissionRecord admission,
    required Map<String, Map<String, String>> details,
    required int currentStep,
    required bool complete,
    Map<String, Map<String, dynamic>>? attachments,
    String? photoPath,
  }) async {
    final validation = complete ? admissionValidationMessage(details) : null;
    if (validation != null) throw ArgumentError(validation);

    String value(String section, String key) =>
        (details[section]?[key] ?? '').trim();
    final name = admissionFullName(details['student'] ?? {});
    final guardianName = admissionFullName(details['guardian'] ?? {});
    final data = <String, dynamic>{
      'details': details,
      'currentStep': currentStep.clamp(0, 6),
      'fullName': name.isEmpty ? 'Draft – ${admission.registrationNo}' : name,
      'searchName': name.toLowerCase(),
      'guardianName': guardianName,
      'guardianPhone': value('guardian', 'phone'),
      'classId': value('academic', 'classId'),
      'gender': value('student', 'gender'),
      'status': complete ? 'admitted' : admission.status,
      // Preserve archival state when editing an already admitted student.
      'active': admission.status == 'admitted'
          ? admission.active
          : complete,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (complete && admission.status != 'admitted') {
      data['admittedAt'] = FieldValue.serverTimestamp();
    }
    if (attachments != null) data['attachments'] = attachments;
    if (photoPath != null) data['photoPath'] = photoPath;
    final batch = _db.batch();
    final studentRef = _students.doc(admission.id);
    batch.update(studentRef, data);
    if (complete) {
      final previousClassId =
          (admission.details['academic']?['classId'] ?? '').trim();
      final nextClassId = value('academic', 'classId');
      if (previousClassId.isNotEmpty && previousClassId != nextClassId) {
        batch.set(
          _db.collection('class_rosters').doc(previousClassId)
              .collection('students').doc(admission.id),
          {
            'studentId': admission.id,
            'fullName': name,
            'rollNo': admission.rollNo,
            'classId': previousClassId,
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      if (nextClassId.isNotEmpty) {
        batch.set(
          _db.collection('class_rosters').doc(nextClassId)
              .collection('students').doc(admission.id),
          {
            'studentId': admission.id,
            'fullName': name,
            'rollNo': admission.rollNo,
            'classId': nextClassId,
            'active': data['active'] == true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }
    await batch.commit();

    // Separate best-effort synchronization protects admission saves even
    // before updated inventory directory rules are deployed. The directory
    // deliberately contains no private guardian, health or contact details.
    if (complete) {
      try {
        await _db.collection('inventory_student_directory')
            .doc(admission.id).set({
          'studentId': admission.id,
          'fullName': name,
          'rollNo': admission.rollNo,
          'classId': value('academic', 'classId'),
          'active': data['active'] == true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Owner can retry using Inventory -> Sync students for checkout.
        // Do not fail a successfully saved student admission.
      }
    }
  }
}
