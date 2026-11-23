import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/admission_storage.dart';

void main() {
  test('R2 references are stored as object keys, not public URLs', () {
    expect(AdmissionStorage.isR2Path(
      'student-photos/ST-2026-0001/1234.webp'), isTrue);
    expect(AdmissionStorage.isR2Path(
      'student-documents/ST-2026-0001/birth_certificate/1234.pdf'), isTrue);
    expect(AdmissionStorage.isR2Path('https://files.example.com/file.pdf'), isFalse);
    expect(AdmissionStorage.isR2Path('legacy/filename.pdf'), isFalse);
  });

  test('a missing Worker URL disables uploads safely', () {
    if (AdmissionStorage.workerUrl.isEmpty) {
      expect(AdmissionStorage.isConfigured, isFalse);
    }
  });
}
