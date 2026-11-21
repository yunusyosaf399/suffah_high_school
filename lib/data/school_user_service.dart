import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

const schoolOwnerUid = 'tQt6vca2zuagZipvknBwcmSRcrc2';

const schoolRoles = <String, String>{
  'principal': 'Principal',
  'accountant': 'Accountant',
  'teacher': 'Teacher',
  'clerk': 'Office staff',
  'parent': 'Parent / guardian',
};

class SchoolUserAccount {
  const SchoolUserAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.staffId = '',
    this.staffNo = '',
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final String staffId;
  final String staffNo;
  bool get isOwner => role == 'owner' || uid == schoolOwnerUid;

  factory SchoolUserAccount.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return SchoolUserAccount(
      uid: snapshot.id,
      name: (data['displayName'] as String?) ?? 'Unnamed account',
      email: (data['email'] as String?) ?? '',
      role: (data['role'] as String?) ?? 'unknown',
      active: data['active'] == true,
      staffId: (data['staffId'] as String?) ?? '',
      staffNo: (data['staffNo'] as String?) ?? '',
    );
  }
}

class CreatedSchoolUser {
  const CreatedSchoolUser({
    required this.uid,
    required this.email,
    required this.resetEmailSent,
  });
  final String uid;
  final String email;
  final bool resetEmailSent;
}

/// Firebase Auth has no client-side admin-create API. Creating the account on
/// a SECONDARY Firebase app keeps the owner signed into the primary session.
/// Only the owner may write Firestore role documents (enforced by rules).
class SchoolUserService {
  SchoolUserService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _mainAuth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _mainAuth;

  Stream<List<SchoolUserAccount>> watchUsers() => _db
      .collection('users')
      .orderBy('displayName')
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(SchoolUserAccount.fromSnapshot).toList());

  Future<CreatedSchoolUser> createAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    String? staffId,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();

    if (_mainAuth.currentUser?.uid != schoolOwnerUid) {
      throw StateError('Only the school owner may create user accounts.');
    }
    if (cleanName.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail) ||
        !schoolRoles.containsKey(role)) {
      throw ArgumentError('Enter a name, valid email and supported role.');
    }
    if (password.length < 12) {
      throw ArgumentError('The temporary password must be at least 12 characters.');
    }
    DocumentReference<Map<String, dynamic>>? linkedStaffRef;
    String linkedStaffNo = '';
    if (role == 'teacher') {
      if (staffId == null || staffId.trim().isEmpty) {
        throw ArgumentError('Select an active teacher profile first.');
      }
      linkedStaffRef = _db.collection('staff').doc(staffId);
      final staffSnapshot = await linkedStaffRef.get(
        const GetOptions(source: Source.server),
      );
      final staff = staffSnapshot.data();
      if (!staffSnapshot.exists || staff == null ||
          staff['active'] != true || staff['roleType'] != 'teacher') {
        throw StateError('The selected teacher is no longer active.');
      }
      final emails = [
        (staff['email'] as String?) ?? '',
        (staff['alternateEmail'] as String?) ?? '',
      ].map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty);
      if (!emails.contains(cleanEmail)) {
        throw StateError('Choose an email address saved on this teacher profile.');
      }
      final linkedUid = (staff['accountUid'] as String?) ?? '';
      if (linkedUid.isNotEmpty) {
        throw StateError('This teacher already has a linked user account.');
      }
      if (((staff['fullName'] as String?) ?? '').trim() != cleanName) {
        throw StateError('The selected teacher name changed. Select the teacher again.');
      }
      linkedStaffNo = (staff['staffNo'] as String?) ?? staffId;
    } else if (staffId != null && staffId.isNotEmpty) {
      throw ArgumentError('Only teacher accounts can be linked to staff profiles.');
    }

    const appName = 'suffah-account-provisioning';
    final matches = Firebase.apps.where((app) => app.name == appName);
    final secondaryApp = matches.isNotEmpty
        ? matches.first
        : await Firebase.initializeApp(
            name: appName,
            options: Firebase.app().options,
          );
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    await secondaryAuth.signOut();

    User? createdUser;
    try {
      final created = await secondaryAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      createdUser = created.user;
      if (createdUser == null) {
        throw StateError('Firebase did not return the newly created account.');
      }
      try {
        await _db.collection('users').doc(createdUser.uid).set({
          'displayName': cleanName,
          'email': cleanEmail,
          'role': role,
          'active': true,
          'linkedStudentIds': <String>[],
          'createdBy': schoolOwnerUid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        // Without this rollback, the app could leave an Auth account with
        // no corresponding school role after a Firestore permissions failure.
        try {
          await createdUser.delete();
        } catch (_) {
          throw StateError(
            'Auth account created, but its school role could not be saved. '
            'Check Firebase Authentication Users for $cleanEmail and remove '
            'the incomplete account before retrying.',
          );
        }
        rethrow;
      }
    } finally {
      await secondaryAuth.signOut();
    }

    bool resetEmailSent = false;
    try {
      await _mainAuth.sendPasswordResetEmail(email: cleanEmail);
      resetEmailSent = true;
    } catch (_) {
      // The account remains usable with its temporary password.
      // Delivery may fail until email templates are configured.
    }
    return CreatedSchoolUser(
      uid: createdUser.uid,
      email: cleanEmail,
      resetEmailSent: resetEmailSent,
    );
  }

  Future<void> setActive(SchoolUserAccount account, bool active) async {
    if (_mainAuth.currentUser?.uid != schoolOwnerUid) {
      throw StateError('Only the school owner may update user accounts.');
    }
    if (account.isOwner) {
      throw StateError('The school owner cannot be disabled here.');
    }
    await _db.collection('users').doc(account.uid).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
