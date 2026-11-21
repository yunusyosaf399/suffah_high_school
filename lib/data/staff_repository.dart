import 'package:cloud_firestore/cloud_firestore.dart';

const staffTypes = <String, String>{
  'teacher': 'Teacher',
  'administration': 'Administration',
  'office': 'Office staff',
  'support': 'Support staff',
};

String staffDisplayName(String first, String middle, String last) =>
    [first.trim(), middle.trim(), last.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');

String staffNumber(int year, int sequence) {
  if (year < 2000 || year > 2200 || sequence < 1 || sequence > 9999) {
    throw ArgumentError('Invalid staff registration sequence.');
  }
  return 'EMP-${year}-${sequence.toString().padLeft(4, '0')}';
}

String teacherAssignmentId(String staffId, String classId, String subject) {
  if (staffId.isEmpty || classId.isEmpty ||
      staffId.contains('/') || classId.contains('/')) {
    throw ArgumentError('Choose a valid staff member and class.');
  }
  final name = subject.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (name.isEmpty) {
    throw ArgumentError('Enter a subject for this assignment.');
  }
  return '${staffId}__${classId}__${name}';
}

class StaffInput {
  const StaffInput({
    required this.firstName,
    required this.lastName,
    required this.roleType,
    required this.designation,
    required this.phone,
    required this.joinDate,
    this.middleName = '',
    this.email = '',
    this.whatsapp = '',
    this.qualification = '',
    this.address = '',
    this.guardianName = '',
    this.dateOfBirth = '',
    this.gender = '',
    this.nationality = '',
    this.alternateEmail = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.presentAddress = '',
    this.permanentAddress = '',
    this.city = '',
    this.postalCode = '',
    this.country = '',
    this.highestQualification = '',
    this.educationDetails = '',
    this.subjectSpecialization = '',
    this.experienceYears = '',
    this.previousEmployer = '',
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String roleType;
  final String designation;
  final String phone;
  final String email;
  final String whatsapp;
  final String joinDate;
  final String qualification;
  final String address;
  final String guardianName;
  final String dateOfBirth;
  final String gender;
  final String nationality;
  final String alternateEmail;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String presentAddress;
  final String permanentAddress;
  final String city;
  final String postalCode;
  final String country;
  final String highestQualification;
  final String educationDetails;
  final String subjectSpecialization;
  final String experienceYears;
  final String previousEmployer;

  String get fullName => staffDisplayName(firstName, middleName, lastName);

  String? validate() {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      return 'Enter staff first and last name.';
    }
    if (!staffTypes.containsKey(roleType)) return 'Choose a staff category.';
    if (designation.trim().isEmpty) return 'Enter the staff designation.';
    if (phone.trim().isEmpty) return 'Enter a contact phone number.';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (email.trim().isNotEmpty && !emailPattern.hasMatch(email.trim())) {
      return 'Enter a valid email address.';
    }
    if (alternateEmail.trim().isNotEmpty &&
        !emailPattern.hasMatch(alternateEmail.trim())) {
      return 'Enter a valid alternate email address.';
    }
    final parsed = DateTime.tryParse(joinDate);
    if (parsed == null || parsed.year < 1950 ||
        parsed.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      return 'Choose a valid date of joining.';
    }
    return null;
  }

  Map<String, dynamic> toFirestoreFields() => {
    'firstName': firstName.trim(),
    'middleName': middleName.trim(),
    'lastName': lastName.trim(),
    'fullName': fullName,
    'searchName': fullName.toLowerCase(),
    'roleType': roleType,
    'designation': designation.trim(),
    'phone': phone.trim(),
    'email': email.trim().toLowerCase(),
    'alternateEmail': alternateEmail.trim().toLowerCase(),
    'whatsapp': whatsapp.trim(),
    'joinDate': joinDate,
    'qualification': highestQualification.trim().isEmpty
        ? qualification.trim() : highestQualification.trim(),
    'highestQualification': highestQualification.trim().isEmpty
        ? qualification.trim() : highestQualification.trim(),
    'address': presentAddress.trim().isEmpty
        ? address.trim() : presentAddress.trim(),
    'guardianName': guardianName.trim(),
    'dateOfBirth': dateOfBirth.trim(),
    'gender': gender.trim(),
    'nationality': nationality.trim(),
    'emergencyContactName': emergencyContactName.trim(),
    'emergencyContactPhone': emergencyContactPhone.trim(),
    'presentAddress': presentAddress.trim().isEmpty
        ? address.trim() : presentAddress.trim(),
    'permanentAddress': permanentAddress.trim(),
    'city': city.trim(),
    'postalCode': postalCode.trim(),
    'country': country.trim(),
    'educationDetails': educationDetails.trim(),
    'subjectSpecialization': subjectSpecialization.trim(),
    'experienceYears': experienceYears.trim(),
    'previousEmployer': previousEmployer.trim(),
  };
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.staffNo,
    required this.fullName,
    required this.roleType,
    required this.designation,
    required this.phone,
    required this.active,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.email = '',
    this.whatsapp = '',
    this.joinDate = '',
    this.qualification = '',
    this.address = '',
    this.guardianName = '',
    this.dateOfBirth = '',
    this.gender = '',
    this.nationality = '',
    this.alternateEmail = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.presentAddress = '',
    this.permanentAddress = '',
    this.city = '',
    this.postalCode = '',
    this.country = '',
    this.highestQualification = '',
    this.educationDetails = '',
    this.subjectSpecialization = '',
    this.experienceYears = '',
    this.previousEmployer = '',
  });

  final String id;
  final String staffNo;
  final String fullName;
  final String roleType;
  final String designation;
  final String phone;
  final bool active;
  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String whatsapp;
  final String joinDate;
  final String qualification;
  final String address;
  final String guardianName;
  final String dateOfBirth;
  final String gender;
  final String nationality;
  final String alternateEmail;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String presentAddress;
  final String permanentAddress;
  final String city;
  final String postalCode;
  final String country;
  final String highestQualification;
  final String educationDetails;
  final String subjectSpecialization;
  final String experienceYears;
  final String previousEmployer;

  bool get isTeacher => roleType == 'teacher';

  List<String> get accountEmails => [email, alternateEmail]
      .map((value) => value.trim().toLowerCase())
      .where((value) =>
          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value))
      .toSet()
      .toList();

  StaffInput get asInput => StaffInput(
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
    roleType: roleType,
    designation: designation,
    phone: phone,
    email: email,
    alternateEmail: alternateEmail,
    whatsapp: whatsapp,
    joinDate: joinDate,
    qualification: qualification,
    address: address,
    guardianName: guardianName,
    dateOfBirth: dateOfBirth,
    gender: gender,
    nationality: nationality,
    emergencyContactName: emergencyContactName,
    emergencyContactPhone: emergencyContactPhone,
    presentAddress: presentAddress,
    permanentAddress: permanentAddress,
    city: city,
    postalCode: postalCode,
    country: country,
    highestQualification: highestQualification,
    educationDetails: educationDetails,
    subjectSpecialization: subjectSpecialization,
    experienceYears: experienceYears,
    previousEmployer: previousEmployer,
  );

  factory StaffMember.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    String value(String key) => (data[key] as String?) ?? '';
    return StaffMember(
      id: snapshot.id,
      staffNo: value('staffNo').isEmpty ? snapshot.id : value('staffNo'),
      fullName: value('fullName'),
      firstName: value('firstName'),
      middleName: value('middleName'),
      lastName: value('lastName'),
      roleType: value('roleType'),
      designation: value('designation'),
      phone: value('phone'),
      email: value('email'),
      alternateEmail: value('alternateEmail'),
      whatsapp: value('whatsapp'),
      joinDate: value('joinDate'),
      qualification: value('qualification'),
      address: value('address'),
      guardianName: value('guardianName'),
      dateOfBirth: value('dateOfBirth'),
      gender: value('gender'),
      nationality: value('nationality'),
      emergencyContactName: value('emergencyContactName'),
      emergencyContactPhone: value('emergencyContactPhone'),
      presentAddress: value('presentAddress'),
      permanentAddress: value('permanentAddress'),
      city: value('city'),
      postalCode: value('postalCode'),
      country: value('country'),
      highestQualification: value('highestQualification'),
      educationDetails: value('educationDetails'),
      subjectSpecialization: value('subjectSpecialization'),
      experienceYears: value('experienceYears'),
      previousEmployer: value('previousEmployer'),
      active: data['active'] != false,
    );
  }
}

class TeacherAssignment {
  const TeacherAssignment({
    required this.id,
    required this.staffId,
    required this.classId,
    required this.subject,
    required this.active,
    this.className = '',
  });

  final String id;
  final String staffId;
  final String classId;
  final String subject;
  final bool active;
  final String className;

  factory TeacherAssignment.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return TeacherAssignment(
      id: snapshot.id,
      staffId: (data['staffId'] as String?) ?? '',
      classId: (data['classId'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      active: data['active'] != false,
      className: (data['className'] as String?) ?? '',
    );
  }
}

/// Online-first staff and assignment catalog. Records are soft-archived.
class StaffRepository {
  StaffRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<StaffMember>> watchStaff() => _db
      .collection('staff')
      .orderBy('searchName')
      .limit(500)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(StaffMember.fromSnapshot).toList());

  Stream<List<TeacherAssignment>> watchAssignments() => _db
      .collection('teacher_assignments')
      .limit(1000)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(TeacherAssignment.fromSnapshot).toList());

  Stream<List<TeacherAssignment>> watchAssignmentsForStaff(String staffId) =>
      _db.collection('teacher_assignments')
          .where('staffId', isEqualTo: staffId)
          .limit(1000)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(TeacherAssignment.fromSnapshot)
              .where((assignment) => assignment.active)
              .toList());

  Future<void> createStaff(StaffInput input) async {
    final error = input.validate();
    if (error != null) throw ArgumentError(error);
    final year = DateTime.now().year;
    final counter = _db.collection('counters')
        .doc('staff_registration_${year}');
    try {
      await _db.runTransaction((transaction) async {
        final counterSnapshot = await transaction.get(counter);
        final next = ((counterSnapshot.data()?['last'] as num?)?.toInt() ?? 0) + 1;
        final number = staffNumber(year, next);
        final staffRef = _db.collection('staff').doc(number);
        final existing = await transaction.get(staffRef);
        if (existing.exists) {
          throw StateError(
            'Staff number already exists. Check the staff registration counter.',
          );
        }
        transaction.set(counter, {
          'last': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(staffRef, {
          ...input.toFirestoreFields(),
          'staffNo': number,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'Staff registration was blocked by Firestore Rules. Publish the '
          'latest firestore.rules from GitHub in Firebase Console, then '
          'confirm you are signed in as the approved school owner.',
        );
      }
      rethrow;
    }
  }

  Future<void> updateStaff(String id, StaffInput input) async {
    final error = input.validate();
    if (error != null) throw ArgumentError(error);
    if (id.isEmpty || id.contains('/')) throw ArgumentError('Invalid staff ID');
    await _db.collection('staff').doc(id).update({
      ...input.toFirestoreFields(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setStaffActive(String id, bool active) async {
    await _db.collection('staff').doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _classLabel(Map<String, dynamic> data) {
    final name = (data['name'] as String?) ?? '';
    final section = (data['section'] as String?) ?? '';
    return [name, section].where((value) => value.isNotEmpty).join(' – ');
  }

  Future<void> assignTeacher({
    required String staffId,
    required String classId,
    required String subject,
  }) async {
    final cleanSubject = subject.trim();
    if (cleanSubject.isEmpty || cleanSubject.length > 60) {
      throw ArgumentError('Enter a subject of 1 to 60 characters.');
    }
    final assignmentId = teacherAssignmentId(staffId, classId, cleanSubject);
    final assignmentRef = _db.collection('teacher_assignments').doc(assignmentId);
    final staffRef = _db.collection('staff').doc(staffId);
    final classRef = _db.collection('classes').doc(classId);

    await _db.runTransaction((transaction) async {
      final staffSnapshot = await transaction.get(staffRef);
      final classSnapshot = await transaction.get(classRef);
      final existing = await transaction.get(assignmentRef);
      if (!staffSnapshot.exists ||
          staffSnapshot.data()?['active'] != true ||
          staffSnapshot.data()?['roleType'] != 'teacher') {
        throw StateError('Choose an active teaching staff member.');
      }
      if (!classSnapshot.exists || classSnapshot.data()?['active'] != true) {
        throw StateError('Choose an active class and section.');
      }
      if (existing.exists && existing.data()?['active'] != false) {
        throw StateError('This teacher already teaches that subject here.');
      }
      final className = _classLabel(classSnapshot.data() ?? {});
      if (existing.exists) {
        transaction.update(assignmentRef, {
          'active': true,
          'subject': cleanSubject,
          'className': className,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(assignmentRef, {
          'staffId': staffId,
          'classId': classId,
          'className': className,
          'subject': cleanSubject,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> setAssignmentActive(String id, bool active) async {
    if (id.isEmpty || id.contains('/')) {
      throw ArgumentError('Invalid assignment.');
    }
    await _db.collection('teacher_assignments').doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
