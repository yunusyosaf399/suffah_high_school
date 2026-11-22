import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/data/class_subject_repository.dart';
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
    expect(find.text('Staff registration'), findsOneWidget);
    expect(find.text('Name & Guardian'), findsWidgets);
    expect(find.byKey(const Key('next_staff_registration')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can complete the five-step staff registration', (tester) async {
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

    await tester.enterText(find.byKey(const Key('staff_firstName_field')), 'Aisha');
    await tester.enterText(find.byKey(const Key('staff_lastName_field')), 'Khan');
    await tester.enterText(find.byKey(const Key('staff_guardianName_field')), 'Ahmed Khan');
    final birthDate = find.byKey(const Key('staff_birth_date'));
    await tester.ensureVisible(birthDate);
    await tester.tap(birthDate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next_staff_registration')));
    await tester.pumpAndSettle();
    expect(find.text('Contact'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('staff_phone_field')), '03001234567');
    await tester.enterText(find.byKey(const Key('staff_email_field')), 'aisha@example.com');
    final emergencyPhone = find.byKey(const Key('staff_emergencyContactPhone_field'));
    if (emergencyPhone.evaluate().isEmpty) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(emergencyPhone);
    await tester.enterText(emergencyPhone, '03007654321');
    await tester.tap(find.byKey(const Key('next_staff_registration')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('staff_presentAddress_field')), 'Main Street');
    await tester.tap(find.byKey(const Key('next_staff_registration')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('staff_highestQualification_field')), 'BS Mathematics');
    await tester.tap(find.byKey(const Key('next_staff_registration')));
    await tester.pumpAndSettle();

    expect(find.text('Review your information'), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit_staff_registration')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_staff_registration')));
    await tester.pumpAndSettle();

    expect(submitted?.fullName, 'Aisha Khan');
    expect(submitted?.guardianName, 'Ahmed Khan');
    expect(submitted?.email, 'aisha@example.com');
    expect(submitted?.presentAddress, 'Main Street');
    expect(submitted?.highestQualification, 'BS Mathematics');
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

  testWidgets('teacher chooses a subject from the class catalog', (tester) async {
    final assigned = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: StaffPage(
        staffStream: Stream.value(const [teacher]),
        assignmentsStream: Stream.value(<TeacherAssignment>[]),
        classesStream: Stream.value(classes),
        subjectsForClass: (_) => Stream.value(const [
          ClassSubject(id: 'mathematics', classId: 'grade-5-a',
            name: 'Mathematics', active: true),
        ]),
        onAssignTeacher: (staffId, classId, subject) async {
          expect(staffId, teacher.id);
          assigned.add('$classId:$subject');
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign_teacher')));
    await tester.pumpAndSettle();
    expect(find.text('Class & section *'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick_subject_grade-5-a_mathematics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_teacher_subjects')));
    await tester.pumpAndSettle();
    expect(assigned, ['grade-5-a:Mathematics']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner assigns multiple subjects across two classes at once',
      (tester) async {
    final assigned = <String>[];
    const bothClasses = [
      SchoolClass(id: 'grade-5-a', name: 'Grade 5', section: 'A', active: true),
      SchoolClass(id: 'grade-6-b', name: 'Grade 6', section: 'B', active: true),
    ];
    await tester.pumpWidget(MaterialApp(home: StaffPage(
      staffStream: Stream.value(const [teacher]),
      assignmentsStream: Stream.value(<TeacherAssignment>[]),
      classesStream: Stream.value(bothClasses),
      subjectsForClass: (classId) => Stream.value(classId == 'grade-5-a'
        ? const [
            ClassSubject(id: 'mathematics', classId: 'grade-5-a',
                name: 'Mathematics', active: true),
            ClassSubject(id: 'english', classId: 'grade-5-a',
                name: 'English', active: true),
          ] : const [
            ClassSubject(id: 'science', classId: 'grade-6-b',
                name: 'Science', active: true),
          ]),
      onAssignTeacher: (staff, classId, subject) async {
        assigned.add('$classId:$subject');
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign_teacher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_subject_grade-5-a_mathematics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_subject_grade-5-a_english')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment_class_grade-5-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 6 – B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_subject_grade-6-b_science')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_teacher_subjects')));
    await tester.pumpAndSettle();
    expect(assigned, containsAll([
      'grade-5-a:Mathematics',
      'grade-5-a:English',
      'grade-6-b:Science',
    ]));
    expect(assigned.length, 3);
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
