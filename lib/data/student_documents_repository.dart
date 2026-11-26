import 'package:cloud_firestore/cloud_firestore.dart';

const studentDocumentKinds = <String, String>{
  'birth_certificate': 'Birth certificate',
  'transfer_certificate': 'Transfer certificate',
  'previous_school_certificate': 'Previous school certificate',
  'medical_report': 'Medical report',
  'other': 'Other',
};

bool canManageStudentDocuments(String role) =>
    role == 'owner' || role == 'principal';

class StudentDocumentFolder {
  const StudentDocumentFolder({
    required this.id, required this.name, required this.registrationNo,
    this.rollNo = '', this.classLabel = '', this.status = 'admitted',
    this.active = true, this.photoPath = '', this.attachments = const {},
  });
  final String id, name, registrationNo, rollNo, classLabel, status, photoPath;
  final bool active;
  final Map<String, Map<String, dynamic>> attachments;
  int get fileCount => attachments.length + (photoPath.isEmpty ? 0 : 1);

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [name, registrationNo, rollNo, classLabel,
      for (final entry in attachments.entries) ...[
        entry.value['name']?.toString() ?? '',
        documentKindLabel(entry.key, entry.value),
      ],
      if (photoPath.isNotEmpty) 'Profile photo',
    ].any((value) => value.toLowerCase().contains(q));
  }

  static String documentKindLabel(String key, Map<String, dynamic> file) =>
      studentDocumentKinds[file['kind']] ??
      studentDocumentKinds[key] ?? key.replaceAll('_', ' ');

  factory StudentDocumentFolder.fromData(String id, Map<String, dynamic> data,
      Map<String, String> classes) {
    String value(String key, [String fallback = '']) =>
        (data[key]?.toString() ?? '').trim().isEmpty
            ? fallback : data[key].toString().trim();
    final attachments = <String, Map<String, dynamic>>{};
    final raw = data['attachments'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          attachments[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    final classId = value('classId');
    return StudentDocumentFolder(
      id: id, name: value('fullName', 'Unnamed student'),
      registrationNo: value('admissionNo', id), rollNo: value('rollNo'),
      classLabel: classes[classId] ?? classId, status: value('status', 'admitted'),
      active: data['active'] != false, photoPath: value('photoPath'),
      attachments: attachments,
    );
  }
}

class StudentDocumentsRepository {
  StudentDocumentsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<List<StudentDocumentFolder>> loadFolders() async {
    // Read the existing student records, not a second copy of their files.
    // Avoid orderBy(fullName), which excludes older records lacking that field.
    final snapshot = await _db.collection('students')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 25));
    final classes = <String, String>{};
    try {
      final result = await _db.collection('classes')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      for (final doc in result.docs) {
        final data = doc.data();
        classes[doc.id] = [data['name'], data['section']]
            .where((v) => v != null && v.toString().trim().isNotEmpty)
            .join(' – ');
      }
    } catch (_) {
      // A class lookup failure must not hide existing documents.
    }
    return snapshot.docs
        .map((doc) => StudentDocumentFolder.fromData(doc.id, doc.data(), classes))
        .toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  }

  // Change only attachments, preserving admission details and identity.
  // Compare the displayed path against the latest record before overwriting.
  Future<void> changeAttachment({
    required String studentId, required String key,
    required String expectedPath, required Map<String, dynamic>? replacement,
  }) async {
    final ref = _db.collection('students').doc(studentId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('Student no longer exists.');
      final raw = snapshot.data()?['attachments'];
      final files = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final previous = files[key];
      final actual = previous is Map ? (previous['path'] ?? '').toString() : '';
      if (actual != expectedPath || (replacement == null && !files.containsKey(key))) {
        throw StateError('Document changed. Refresh the folder and try again.');
      }
      if (replacement == null) {
        files.remove(key);
      } else {
        files[key] = replacement;
      }
      transaction.update(ref, {
        'attachments': files,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
