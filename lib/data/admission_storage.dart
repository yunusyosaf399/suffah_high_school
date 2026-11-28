import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

/// Student files live in a private R2 bucket. The APK contains only a Worker
/// URL; every request is authorized with the signed-in user's Firebase token.
class AdmissionStorage {
  AdmissionStorage({FirebaseAuth? auth, http.Client? client})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  static const String workerUrl = String.fromEnvironment('R2_WORKER_URL');
  static const int maxPhotoBytes = 100 * 1024;
  static const int maxDocumentBytes = 5 * 1024 * 1024;

  final FirebaseAuth _auth;
  final http.Client _client;

  static bool get isConfigured => workerUrl.trim().isNotEmpty;

  Uri _endpoint(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw StateError(
        'Cloudflare R2 is not configured in this APK. '
        'Set R2_WORKER_URL and install the updated APK.',
      );
    }
    final base = Uri.tryParse(workerUrl.trim());
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw StateError('R2_WORKER_URL must be an HTTPS Cloudflare Worker URL.');
    }
    final cleanBase = workerUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse(cleanBase + path).replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers([String? contentType]) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before accessing student files.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not obtain a school authentication token.');
    }
    return {
      'Authorization': 'Bearer ' + token,
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  void _verify(http.Response response, {int successCode = 200}) {
    if (response.statusCode == successCode) return;
    String message = 'Cloudflare storage error (' +
        response.statusCode.toString() + ').';
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed['error'] is String) {
        message = parsed['error'] as String;
      }
    } catch (_) {
      // Show a generic status message for non-JSON responses.
    }
    throw StateError(message);
  }

  Future<UploadedProfilePhoto?> uploadProfilePhoto(String registrationNo) async {
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
      if (output.isNotEmpty && output.lengthInBytes <= maxPhotoBytes) {
        compressed = output;
        break;
      }
    }
    if (compressed == null) {
      throw StateError(
        'Photo could not be compressed below 100 KB. Choose a smaller photo.',
      );
    }
    final response = await _client.put(
      _endpoint('/v1/students/' + Uri.encodeComponent(registrationNo) + '/photo'),
      headers: {
        ...await _headers('image/webp'),
        'X-File-Name': 'profile.webp',
      },
      body: compressed,
    ).timeout(const Duration(seconds: 45));
    _verify(response, successCode: 201);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadedProfilePhoto(
      path: data['path'] as String,
      bytes: compressed,
    );
  }

  Future<Map<String, dynamic>?> uploadDocument(
    String registrationNo,
    String documentKind,
  ) async {
    const allowedKinds = {
      'birth_certificate', 'transfer_certificate',
      'previous_school_certificate', 'medical_report', 'other',
    };
    if (!allowedKinds.contains(documentKind)) {
      throw ArgumentError('Unsupported document category.');
    }
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
      throw StateError('Could not read the selected document.');
    }
    if (bytes.length > maxDocumentBytes) {
      throw StateError('Choose a document no larger than 5 MB.');
    }
    const types = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final extension = selected.extension?.toLowerCase() ?? '';
    final contentType = types[extension];
    if (contentType == null) throw StateError('Unsupported document format.');
    final response = await _client.put(
      _endpoint('/v1/students/' + Uri.encodeComponent(registrationNo) +
          '/documents/' + Uri.encodeComponent(documentKind)),
      headers: {
        ...await _headers(contentType),
        'X-File-Name': Uri.encodeComponent(selected.name),
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    _verify(response, successCode: 201);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'path': data['path'],
      'name': selected.name.replaceAll(RegExp(r'[\r\n]'), ' ').trim(),
      'bytes': data['bytes'],
      'contentType': data['contentType'],
      'kind': documentKind,
    };
  }

  Future<Uint8List> downloadStudentPhoto(String studentId) async {
    final response = await _client.get(
      _endpoint('/v1/student-photo', {'studentId': studentId}),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 20));
    _verify(response);
    return response.bodyBytes;
  }

  void close() => _client.close();

  Future<Uint8List> downloadFile(String path,{bool parentReadOnly=false}) async {
    final response = await _client.get(
      _endpoint(parentReadOnly?'/v1/parent-files':'/v1/files', {'path': path}),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 40));
    _verify(response);
    return response.bodyBytes;
  }

  Future<bool> saveDocumentToDevice(Map<String, dynamic> document,{bool parentReadOnly=false}) async {
    final path = (document['path'] ?? '').toString();
    final name = (document['name'] ?? 'document.pdf')
        .toString().replaceAll(RegExp(r'[/\\\r\n]'), '_');
    final bytes = await downloadFile(path,parentReadOnly:parentReadOnly);
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save student document',
      fileName: name,
      bytes: bytes,
    );
    return savedPath != null;
  }

  /// The Worker refuses deletion of a still-referenced Firestore file.
  Future<void> deleteFile(String path) async {
    if (!isR2Path(path)) return;
    final response = await _client.delete(
      _endpoint('/v1/files', {'path': path}),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 30));
    _verify(response, successCode: 204);
  }

  static bool isR2Path(String path) =>
      path.startsWith('student-photos/') || path.startsWith('student-documents/');
}

class UploadedProfilePhoto {
  const UploadedProfilePhoto({required this.path, required this.bytes});
  final String path;
  final Uint8List bytes;
}
