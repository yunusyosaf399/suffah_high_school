import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/staff_repository.dart';

void main() {
  test('staff IDs are stable, chronological and never zero', () {
    expect(staffNumber(2026, 1), 'EMP-2026-0001');
    expect(staffNumber(2026, 45), 'EMP-2026-0045');
    expect(staffNumber(2027, 1), 'EMP-2027-0001');
    expect(() => staffNumber(2026, 0), throwsArgumentError);
    expect(() => staffNumber(2026, 10000), throwsArgumentError);
  });

  test('display names omit optional blank middle names', () {
    expect(staffDisplayName(' Aisha ', ' ', ' Khan '), 'Aisha Khan');
    expect(staffDisplayName('Ali', 'Raza', 'Khan'), 'Ali Raza Khan');
  });

  test('staff form validates mandatory details and email', () {
    final valid = StaffInput(
      firstName: 'Aisha',
      lastName: 'Khan',
      roleType: 'teacher',
      designation: 'Mathematics Teacher',
      phone: '03001234567',
      joinDate: '2026-11-20',
    );
    expect(valid.validate(), isNull);
    expect(valid.toFirestoreFields()['searchName'], 'aisha khan');
    final invalid = StaffInput(
      firstName: '', lastName: 'Khan', roleType: 'teacher',
      designation: '', phone: '', joinDate: 'not-a-date',
    );
    expect(invalid.validate(), isNotNull);
    final badEmail = StaffInput(
      firstName: 'Aisha', lastName: 'Khan',
      roleType: 'teacher', designation: 'Teacher',
      phone: '03001234567', joinDate: '2026-11-20',
      email: 'incorrect-email',
    );
    expect(badEmail.validate(), 'Enter a valid email address.');
  });

  test('assignment keys are deterministic per teacher class and subject', () {
    final a = teacherAssignmentId(
      'EMP-2026-0001', 'grade-5-a', 'Mathematics');
    final b = teacherAssignmentId(
      'EMP-2026-0001', 'grade-5-a', ' mathematics ');
    expect(a, b);
    expect(a, 'EMP-2026-0001__grade-5-a__mathematics');
    expect(teacherAssignmentId(
      'EMP-2026-0001', 'grade-5-b', 'Mathematics'), isNot(a));
    expect(() => teacherAssignmentId('', 'grade-1-a', 'English'),
      throwsArgumentError);
    expect(() => teacherAssignmentId(
      'EMP-2026-0001', 'grade-1-a', ''), throwsArgumentError);
  });
}
