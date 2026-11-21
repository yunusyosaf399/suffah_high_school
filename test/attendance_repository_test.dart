import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/attendance_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';

void main() {
  const roster = [
    StudentRecord(
      id: 'ST-2026-0001',
      admissionNo: 'ST-2026-0001',
      fullName: 'Ali Khan',
      classId: 'grade-1-a',
      guardianName: 'Yousaf Khan',
      guardianPhone: '03001234567',
      gender: 'Male',
      rollNo: '10000',
      active: true,
    ),
    StudentRecord(
      id: 'ST-2026-0002',
      admissionNo: 'ST-2026-0002',
      fullName: 'Aisha Khan',
      classId: 'grade-1-a',
      guardianName: 'Yousaf Khan',
      guardianPhone: '03001234567',
      gender: 'Female',
      rollNo: '10001',
      active: true,
    ),
  ];

  test('attendance uses deterministic class and date paths', () {
    expect(attendanceDateKey(DateTime(2026, 11, 21)), '2026-11-21');
    expect(attendanceDayId('grade-1-a', DateTime(2026, 11, 21)),
        'grade-1-a_20261121');
    expect(() => attendanceDayId('', DateTime.now()), throwsArgumentError);
    expect(() => attendanceDayId('invalid/class', DateTime.now()),
        throwsArgumentError);
  });

  test('unmarked students are NOT automatically absent', () {
    final summary = AttendanceSummary.fromMarks(
      roster, {'ST-2026-0001': 'present'});
    expect(summary.total, 2);
    expect(summary.present, 1);
    expect(summary.absent, 0);
    expect(summary.unmarked, 1);
    expect(summary.complete, isFalse);
  });

  test('marked attendance totals and completeness are accurate', () {
    final summary = AttendanceSummary.fromMarks(roster, {
      'ST-2026-0001': 'absent',
      'ST-2026-0002': 'late',
      'unknown-student': 'present',
    });
    expect(summary.present, 0);
    expect(summary.absent, 1);
    expect(summary.late, 1);
    expect(summary.leave, 0);
    expect(summary.marked, 2);
    expect(summary.unmarked, 0);
    expect(summary.complete, isTrue);
  });

  test('attendance write access is reserved for owner and principal', () {
    expect(canManageAttendance('owner'), isTrue);
    expect(canManageAttendance('principal'), isTrue);
    expect(canManageAttendance('teacher'), isFalse);
    expect(canManageAttendance('parent'), isFalse);
    expect(canManageAttendance('accountant'), isFalse);
  });
}
