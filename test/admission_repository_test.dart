import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/admission_repository.dart';

void main() {
  test('registration sequence uses ST-YYYY-XXXX', () {
    expect(registrationNumberFor(2026, 1), 'ST-2026-0001');
    expect(registrationNumberFor(2026, 52), 'ST-2026-0052');
    expect(registrationNumberFor(2027, 9999), 'ST-2027-9999');
    expect(() => registrationNumberFor(2026, 10000), throwsRangeError);
  });

  test('roll numbers begin at 10000 and are five digits', () {
    expect(rollNumberFor(10000), '10000');
    expect(rollNumberFor(10001), '10001');
    expect(() => rollNumberFor(9999), throwsRangeError);
    expect(() => rollNumberFor(100000), throwsRangeError);
  });

  test('optional middle name does not insert empty whitespace', () {
    expect(admissionFullName({
      'firstName': 'Aisha', 'middleName': '', 'lastName': 'Khan',
    }), 'Aisha Khan');
    expect(admissionFullName({
      'firstName': 'Ali', 'middleName': 'Raza', 'lastName': 'Yousaf',
    }), 'Ali Raza Yousaf');
  });

  test('draft fields may be empty but completion checks essentials', () {
    expect(admissionValidationMessage({}), contains('student'));
    final sections = {
      'student': {
        'firstName': 'Ali',
        'middleName': '',
        'lastName': 'Khan',
        'dateOfBirth': '2017-05-04',
      },
      'academic': {
        'classId': 'grade-1-a',
        'campus': 'Main',
      },
      'guardian': {
        'firstName': 'Yousaf',
        'lastName': 'Khan',
        'phone': '03001234567',
        'relationship': 'Father',
      },
    };
    expect(admissionValidationMessage(sections), isNull);
    sections['guardian']!['phone'] = '';
    expect(admissionValidationMessage(sections), contains('guardian'));
  });

  test('legacy student records can be opened in admission wizard', () {
    final legacy = AdmissionRecord.fromData('OLD-001', {
      'fullName': 'Mariam Saleem',
      'guardianName': 'Mohammad Saleem',
      'guardianPhone': '03000000000',
      'classId': 'grade-1-a',
      'rollNo': '10000',
    });
    expect(legacy.status, 'admitted');
    expect(legacy.registrationNo, 'OLD-001');
    expect(legacy.details['student']!['firstName'], 'Mariam');
    expect(legacy.details['academic']!['classId'], 'grade-1-a');
  });
}
