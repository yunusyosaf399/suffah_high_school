import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Cloud Storage is optional for completing an admission. Firebase requires
/// Blaze billing to create/access the project's default Storage bucket.
class AdmissionStorage {
  AdmissionStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String?> uploadProfilePhoto(String registrationNo) async {
    final files = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (files == null || files.files.isEmpty) return null;
    final original = files.files.single.bytes;
    if (original == null || original.isEmpty) {
      throw StateError('Could not read the selected photo.');
    }
    Uint8List? compressed;
    for (final quality in [78, 62, 48, 32, 22]) {
      final output = await FlutterImageCompress.compressWithList(
        original,
        quality: quality,
        minWidth: quality >= 48 ? 480 : 300,
        minHeight: quality >= 48 ? 480 : 300,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (output.isNotEmpty && output.lengthInBytes <= 102400) {
        compressed = output;
        break;
      }
    }
    if (compressed == null) {
      throw StateError(
        'Photo could not be reduced to 100 KB. Choose a smaller portrait photo.',
      );
    }
    final path = 'student-photos/$registrationNo.webp';
    await _storage.ref(path).putData(
      compressed,
      SettableMetadata(contentType: 'image/webp'),
    );
    return path;
  }

  Future<Map<String, dynamic>?> uploadDocument(
    String registrationNo,
    String documentKind,
  ) async {
    final files = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (files == null || files.files.isEmpty) return null;
    final selected = files.files.single;
    final bytes = selected.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not read the document.');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Choose a file no larger than 5 MB.');
    }
    final extension = selected.extension?.toLowerCase() ?? '';
    final types = <String, String>{
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final contentType = types[extension];
    if (contentType == null) throw StateError('Unsupported document format.');

    final kind = documentKind.replaceAll(RegExp(r'[^a-z_0-9-]'), '_');
    final name = selected.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final path = 'student-documents/$registrationNo/$kind-$timestamp.$extension';
    await _storage.ref(path).putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return {
      'path': path,
      'name': name,
      'bytes': bytes.length,
      'contentType': contentType,
      'kind': kind,
    };
  }
}
