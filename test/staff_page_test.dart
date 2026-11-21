import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/data/staff_repository.dart';
import 'package:suffah_high_school/screens/staff_page.dart';

void main() {
  const teacher = StaffMember(
    id: 'EMP-2026-0001',
    staffNo: 'EMP-2026-0001',
    firstName: 'Aisha',
    lastName: 'Khan',
    fullName: 'Aisha Khan',
    designation: 'Mathematics Teacher',
    roleType: 'teacher',
    phone: '03001234567',
    joinDate: '2026-11-20',
    active: true,
  );
  const classes = [
    SchoolClass(
      id: 'grade-5-a', name: 'Grade 5', section: 'A', active: true),
  ];

  testWidgets('staff page has a visible action and useful empty state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        staffStream: Stream.value(<StaffMember>[]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(<SchoolClass>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Staff & teachers'), findsOneWidget);
    expect(find.text('No staff members yet'), findsOneWidget);
    expect(find.text('Add staff'), findsOneWidget);
    expect(find.byKey(const Key('staff_scroll_view')), findsOneWidget);
    await tester.tap(find.text('Add staff'));
    await tester.pumpAndSettle();
    expect(find.text('Add staff member'), findsOneWidget);
    expect(find.text('Save staff'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can create a staff profile without Storage', (tester) async {
    StaffInput? submitted;
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        staffStream: Stream.value(<StaffMember>[]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(classes),
        onSaveStaff: (input, id) async {
          expect(id, isNull);
          submitted = input;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add staff'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name *'), 'Aisha');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name *'), 'Khan');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number *'), '03001234567');
    await tester.tap(find.text('Save staff'));
    await tester.pumpAndSettle();
    expect(submitted?.fullName, 'Aisha Khan');
    expect(submitted?.roleType, 'teacher');
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff profile is read-only and has edit action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        staffStream: Stream.value(const [teacher]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(classes),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('staff_item_EMP-2026-0001')));
    await tester.pumpAndSettle();
    expect(find.text('EMP-2026-0001 · Teacher'), findsOneWidget);
    expect(find.text('03001234567'), findsOneWidget);
    expect(find.text('Edit staff details'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('teacher can be assigned to class and subject', (tester) async {
    String? staffId;
    String? classId;
    String? subject;
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        staffStream: Stream.value(const [teacher]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(classes),
        onAssignTeacher: (staff, schoolClass, taughtSubject) async {
          staffId = staff;
          classId = schoolClass;
          subject = taughtSubject;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignments'));
    await tester.pumpAndSettle();
    expect(find.text('No teacher assignments yet'), findsOneWidget);
    expect(find.text('Assign teacher'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assign_teacher')));
    await tester.pumpAndSettle();
    expect(find.text('Class & section *'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Subject *'), 'Mathematics');
    await tester.tap(find.text('Save assignment'));
    await tester.pumpAndSettle();
    expect(staffId, teacher.id);
    expect(classId, 'grade-5-a');
    expect(subject, 'Mathematics');
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher role cannot create staff or assignments',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        role: 'teacher',
        staffStream: Stream.value(const [teacher]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(classes),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Add staff'), findsNothing);
    await tester.tap(find.text('Assignments'));
    await tester.pumpAndSettle();
    expect(find.text('Assign teacher'), findsNothing);
  });
}
