import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'school_portal_client.dart';
import 'admission_repository.dart';
import 'parent_portal_repository.dart';

const schoolOwnerUid = 'tQt6vca2zuagZipvknBwcmSRcrc2';

const schoolRoles = <String, String>{
  'principal': 'Principal',
  'examiner': 'Examiner',
  'accountant': 'Accountant',
  'teacher': 'Teacher',
  'clerk': 'Office staff',
  'parent': 'Parent / guardian',
  'canteen_seller': 'Canteen seller',
  'inventory_manager': 'Inventory manager',
};

// Role ceilings are fixed. The owner may disable these specific capabilities;
// a permission switch never grants a capability outside its role.
const schoolPermissionLabels=<String,Map<String,String>>{
  'parent':{
    'parent_profile':'Child profile','parent_fees':'Fees and dues',
    'parent_attendance':'Attendance','parent_exams':'Examinations and released marks',
    'parent_documents':'Child documents','messages':'School messages',
  },
  'teacher':{
    'teacher_profile':'Own profile and contract','teacher_payroll':'Own salary',
    'teacher_academics':'Assigned examinations, marks and class tests',
    'teacher_classwork':'Homework and assignments','teacher_attendance':'Assigned attendance',
    'teacher_analytics':'Own teaching outcomes','messages':'School messages',
  },
  'principal':{'principal_exams':'Formal examinations and results','messages':'School messages'},
};
Map<String,bool> accountPermissions(dynamic value)=>value is Map
  ?{for(final entry in value.entries) if(entry.key is String && entry.value is bool) (entry.key as String):(entry.value as bool)}
  :<String,bool>{};
bool schoolPermission(Map<String,bool> permissions,String key)=>permissions[key]!=false;

class SchoolUserAccount {
  const SchoolUserAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.staffId = '',
    this.staffNo = '',
    this.removed=false,this.linkedStudentIds=const [],this.permissions=const {},
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final String staffId;
  final String staffNo;
  final bool removed;
  final List<String> linkedStudentIds;
  final Map<String,bool> permissions;
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
      removed:data['removed']==true,
      linkedStudentIds:(data['linkedStudentIds'] as List? ?? []).whereType<String>().toList(),
      permissions:accountPermissions(data['permissions']),
    );
  }
}


class ParentChildOption {
  const ParentChildOption({required this.id,required this.name,this.classId='',
    this.guardianName='',this.relationship='',this.phone='',this.email=''});
  final String id,name,classId,guardianName,relationship,phone,email;

  factory ParentChildOption.fromData(String id,Map<String,dynamic> data) {
    final details=AdmissionRecord.parseDetails(data);
    final guardian=details['guardian']??const <String,String>{};
    final name=admissionFullName(guardian);
    String value(String key)=>data[key]?.toString().trim()??'';
    return ParentChildOption(id:id,name:value('fullName').isEmpty
      ?admissionFullName(details['student']??{}):value('fullName'),
      classId:value('classId').isEmpty ? (details['academic']?['classId']??'') : value('classId'),
      guardianName:name.isEmpty?value('guardianName'):name,
      relationship:guardian['relationship']??'',
      phone:(guardian['phone']??value('guardianPhone')).trim(),
      email:(guardian['email']??value('guardianEmail')).trim());
  }

  bool sameGuardian(ParentChildOption other)=>guardianName==other.guardianName &&
    relationship==other.relationship && phone==other.phone && email==other.email;
}

Map<String,dynamic> guardianEmailUpdate(Map<String,dynamic> data,String email) {
  // Preserve every other detail, including the legacy admission fallback.
  final raw=data['details'];
  final details=raw is Map && raw.isNotEmpty
    ?Map<String,dynamic>.from(raw)
    :<String,dynamic>{...AdmissionRecord.parseDetails(data)};
  final guardian=details['guardian'];
  details['guardian']={
    if(guardian is Map)...Map<String,dynamic>.from(guardian)
    else ...?AdmissionRecord.parseDetails(data)['guardian'],
    'email':email,
  };
  return {'details':details,if(data.containsKey('guardianEmail'))'guardianEmail':email};
}

bool eligibleParentChild(Map<String,dynamic> data)=>
    (data['status']??'admitted')=='admitted' && data['active']!=false;

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

  Stream<List<ParentChildOption>> watchParentChildren()=>_db.collection('students').snapshots()
    .map((snapshot)=>snapshot.docs.where((d)=>eligibleParentChild(d.data()))
      .map((d)=>ParentChildOption.fromData(d.id,d.data())).toList()..sort((a,b)=>a.name.compareTo(b.name)));

  Future<CreatedSchoolUser> createAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    String? staffId,
    List<ParentChildOption> children=const [],
    bool guardianConfirmed=false,
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
    final childIds=children.map((c)=>c.id).toSet().toList();
    if(role=='parent') {
      if(!guardianConfirmed || children.isEmpty || childIds.length!=children.length || childIds.length>50 ||
        childIds.any((id)=>id.isEmpty || id.contains('/'))) {
        throw ArgumentError('Select 1–50 children and confirm the guardian identity and email.');
      }
      // Check the selections before creating any Firebase sign-in.
      for(final child in children) {
        final data=(await _db.collection('students').doc(child.id).get(const GetOptions(source:Source.server))).data();
        if(data==null || !eligibleParentChild(data) || !child.sameGuardian(ParentChildOption.fromData(child.id,data))) {
          throw StateError('Student or guardian information changed. Reopen the form and select the child again.');
        }
      }
    } else if(children.isNotEmpty) {
      throw ArgumentError('Only parent accounts may link children.');
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
      final linkedUsers = await _db.collection('users')
          .where('staffId', isEqualTo: staffId)
          .get(const GetOptions(source: Source.server));
      if (linkedUsers.docs.any((doc)=>doc.data()['removed']!=true)) {
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
        final profile=<String,dynamic>{
          'displayName': cleanName,
          'email': cleanEmail,
          'role': role,
          'active': true,
          'linkedStudentIds': childIds,
          if (staffId != null && role == 'teacher') ...{
            'staffId': staffId,
            'staffNo': linkedStaffNo,
          },
          'createdBy': schoolOwnerUid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final userRef=_db.collection('users').doc(createdUser.uid);
        if(role=='parent') {
          // All student email updates and the role record commit together.
          await _db.runTransaction((tx) async {
            final records=<String,Map<String,dynamic>>{};
            for(final child in children) {
              final data=(await tx.get(_db.collection('students').doc(child.id))).data();
              if(data==null || !eligibleParentChild(data) ||
                 !child.sameGuardian(ParentChildOption.fromData(child.id,data))) {
                throw StateError('Guardian information changed while creating the account. Select the child again.');
              }
              records[child.id]=data;
            }
            tx.set(userRef,profile);
            for(final child in children) {
              tx.update(_db.collection('students').doc(child.id),{
                ...guardianEmailUpdate(records[child.id]!,cleanEmail),
                'updatedAt':FieldValue.serverTimestamp(),
              });
              writeParentChildViews((ref,value)=>tx.set(ref,value,SetOptions(merge:true)),_db,child.id,records[child.id]!);
            }
          });
        } else {
          await userRef.set(profile);
        }
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
    if (account.isOwner || account.removed) {
      throw StateError('The school owner cannot be disabled here.');
    }
    await _db.collection('users').doc(account.uid).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  void _requireOwner(SchoolUserAccount account) {
    if(_mainAuth.currentUser?.uid!=schoolOwnerUid || account.isOwner)throw StateError('Only the owner may manage non-owner accounts.');
  }

  Future<void> saveAccess(SchoolUserAccount account,Map<String,bool> permissions,List<String> childIds) async {
    _requireOwner(account);
    if(account.removed)throw StateError('This account has been removed.');
    final allowed=schoolPermissionLabels[account.role]??{};
    if(!allowed.keys.toSet().containsAll(permissions.keys))throw ArgumentError('Unsupported permission.');
    final ids=childIds.toSet().toList()..sort();
    if(ids.length>50 || (account.role!='parent' && ids.isNotEmpty))throw ArgumentError('Invalid child links.');
    final batch=_db.batch();
    if(account.role=='parent') {
      for(final id in ids) {
        final child=await _db.collection('students').doc(id).get(const GetOptions(source:Source.server));
        if(!child.exists || child.data()?['status']=='draft')throw StateError('Choose existing admitted children.');
        writeParentChildViews((ref,data)=>batch.set(ref,data,SetOptions(merge:true)),_db,id,child.data()!);
      }
    }
    batch.update(_db.collection('users').doc(account.uid),{
      'permissions':permissions,'linkedStudentIds':ids,'updatedAt':FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> removeAccount(SchoolUserAccount account,{bool deleteAuthentication=false}) async {
    _requireOwner(account);
    if(!account.removed) {
      await _db.collection('users').doc(account.uid).update({
        'active':false,'removed':true,'removedAt':FieldValue.serverTimestamp(),
        'updatedAt':FieldValue.serverTimestamp(),
      });
    }
    if(deleteAuthentication) {
      try {await SchoolPortalClient().request('deleteAuthAccount',{'uid':account.uid});}
      catch(error){throw StateError('School access removed, but Firebase Authentication deletion failed. Reopen the removed account to retry. $error');}
    }
  }

}
