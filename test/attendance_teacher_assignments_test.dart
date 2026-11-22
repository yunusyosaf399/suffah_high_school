import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/attendance_class_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/data/staff_repository.dart';
import 'package:suffah_high_school/screens/attendance_teacher_assignments_page.dart';

void main() {
  const teacher = StaffMember(
    id: 'EMP-2026-0001', staffNo: 'EMP-2026-0001',
    firstName: 'Aisha', lastName: 'Khan', fullName: 'Aisha Khan',
    designation: 'Teacher', roleType: 'teacher', phone: '03001112222',
    joinDate: '2026-11-20', active: true);
  const schoolClass = SchoolClass(
    id: 'grade-5-a', name: 'Grade 5', section: 'A', active: true);
  const assignment = AttendanceClassAssignment(
    classId: 'grade-5-a', staffId: 'EMP-2026-0001',
    className: 'Grade 5 – A', staffName: 'Aisha Khan');

  test('attendance mappings preserve class and teacher identity', () {
    final copy = AttendanceClassAssignment.fromMap({
      'classId': 'grade-5-a', 'staffId': 'EMP-2026-0001',
      'className': 'Grade 5 – A', 'staffName': 'Aisha Khan', 'active': true,
    });
    expect(copy.classId, 'grade-5-a');
    expect(copy.staffId, 'EMP-2026-0001');
    expect(copy.active, isTrue);
    expect(AttendanceClassAssignment.fromMap({}).active, isFalse);
  });

  for (final role in ['owner', 'principal']) {
    testWidgets('$role can assign one attendance class to a teacher',
        (tester) async {
      String? staffId;
      String? classId;
      await tester.pumpWidget(MaterialApp(home: AttendanceTeacherAssignmentsPage(
        role: role,
        staffStream: Stream.value(const [teacher]),
        classesStream: Stream.value(const [schoolClass]),
        assignmentsStream: Stream.value(const <AttendanceClassAssignment>[]),
        onAssign: (staff, school) async {
          staffId = staff;
          classId = school;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign_attendance_teacher')));
      await tester.pumpAndSettle();
      expect(find.text('Assign attendance class'), findsWidgets);
      await tester.tap(find.byKey(const Key('save_attendance_teacher')));
      await tester.pumpAndSettle();
      expect(staffId, teacher.id);
      expect(classId, schoolClass.id);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('owner can remove attendance responsibility, preserving history',
      (tester) async {
    String? removed;
    await tester.pumpWidget(MaterialApp(home: AttendanceTeacherAssignmentsPage(
      staffStream: Stream.value(const [teacher]),
      classesStream: Stream.value(const [schoolClass]),
      assignmentsStream: Stream.value(const [assignment]),
      onRemove: (id) async => removed = id,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Attendance teacher: Aisha Khan'), findsOneWidget);
    await tester.tap(find.byTooltip('Attendance class options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove teacher'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_remove_attendance_teacher')));
    await tester.pumpAndSettle();
    expect(removed, schoolClass.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other roles cannot open attendance responsibility management',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AttendanceTeacherAssignmentsPage(role: 'teacher')));
    await tester.pumpAndSettle();
    expect(find.text('Only the owner or principal can assign attendance teachers.'),
      findsOneWidget);
    expect(find.byKey(const Key('assign_attendance_teacher')), findsNothing);
  });
}
