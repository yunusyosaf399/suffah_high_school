import 'package:cloud_firestore/cloud_firestore.dart';

String classSubjectId(String name) => name.trim().toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

class ClassSubject {
  const ClassSubject({
    required this.id, required this.classId, required this.name,
    required this.active, this.code = '', this.description = '',
    this.weeklyPeriods = 0,
  });

  final String id;
  final String classId;
  final String name;
  final String code;
  final String description;
  final int weeklyPeriods;
  final bool active;

  factory ClassSubject.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return ClassSubject(
      id: snapshot.id,
      classId: (data['classId'] as String?) ?? snapshot.reference.parent.parent!.id,
      name: (data['name'] as String?) ?? '',
      code: (data['code'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      weeklyPeriods: (data['weeklyPeriods'] as num?)?.toInt() ?? 0,
      active: data['active'] != false,
    );
  }
}

class ClassSubjectRepository {
  ClassSubjectRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _subjects(String classId) =>
      _db.collection('classes').doc(classId).collection('subjects');

  Stream<List<ClassSubject>> watchSubjects(String classId) => _subjects(classId)
      .orderBy('nameKey').limit(100).snapshots()
      .map((snap) => snap.docs.map(ClassSubject.fromSnapshot).toList());

  Future<void> saveSubject({
    required String classId, required String name, required String code,
    required String description, required int weeklyPeriods, String? existingId,
  }) async {
    final cleanName = name.trim();
    final id = existingId ?? classSubjectId(cleanName);
    if (classId.isEmpty || classId.contains('/') || id.isEmpty ||
        cleanName.length < 2 || cleanName.length > 60) {
      throw ArgumentError('Enter a subject name of 2 to 60 characters.');
    }
    if (code.trim().length > 16 || description.trim().length > 500 ||
        weeklyPeriods < 0 || weeklyPeriods > 30) {
      throw ArgumentError('Check the code, description and weekly periods (0–30).');
    }
    if (existingId != null && (existingId.isEmpty || existingId.contains('/'))) {
      throw ArgumentError('Invalid subject.');
    }
    final classRef = _db.collection('classes').doc(classId);
    final ref = _subjects(classId).doc(id);
    await _db.runTransaction((tx) async {
      final schoolClass = await tx.get(classRef);
      final existing = await tx.get(ref);
      if (!schoolClass.exists || schoolClass.data()?['active'] != true) {
        throw StateError('Activate the class before managing subjects.');
      }
      if (existingId == null && existing.exists) {
        throw StateError('Subject already exists. Edit or restore it.');
      }
      if (existingId != null && (!existing.exists ||
          existing.data()?['name'] != cleanName)) {
        throw StateError('Subject names cannot be changed after creation.');
      }
      final fields = <String, dynamic>{
        'code': code.trim().toUpperCase(),
        'description': description.trim(),
        'weeklyPeriods': weeklyPeriods,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (existingId != null) {
        tx.update(ref, fields);
      } else {
        tx.set(ref, {
          ...fields,
          'classId': classId,
          'name': cleanName,
          'nameKey': cleanName.toLowerCase(),
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> setSubjectActive(ClassSubject subject, bool active) async {
    final classRef = _db.collection('classes').doc(subject.classId);
    final ref = _subjects(subject.classId).doc(subject.id);
    await _db.runTransaction((tx) async {
      final schoolClass = await tx.get(classRef);
      final current = await tx.get(ref);
      if (schoolClass.data()?['active'] != true || !current.exists) {
        throw StateError('Activate the class before changing its subjects.');
      }
      tx.update(ref, {
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
