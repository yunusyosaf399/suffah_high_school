import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';

void main() {
  group('School record validation', () {
    test('normalizes admission numbers but preserves leading zeros', () {
      expect(normalizedAdmissionNo(' shs-0004 '), 'SHS-0004');
      expect(validAdmissionNo(' shs-0004 '), isTrue);
    });

    test('rejects invalid IDs that cannot become Firestore document paths', () {
      expect(validAdmissionNo('SHS/4'), isFalse);
      expect(validAdmissionNo(''), isFalse);
      expect(validAdmissionNo('A-B'), isTrue);
    });

    test('builds stable class-section identifiers', () {
      expect(classDocumentId('Grade 5', 'A'), 'grade-5-a');
      expect(classDocumentId('Grade 5', ' B '), 'grade-5-b');
      expect(classDocumentId('Grade 1', ''), 'grade-1');
    });
  });
}
