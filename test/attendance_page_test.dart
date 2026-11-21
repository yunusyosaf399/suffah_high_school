import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/attendance_page.dart';

void main() {
  const classes = [
    SchoolClass(id: 'grade-1-a', name: 'Grade 1', section: 'A', active: true),
  ];
  const roster = [
    StudentRecord(
      id: 'ST-2026-0001',
      admissionNo: 'ST-2026-0001',
      fullName: 'Ali Khan',
      classId: 'grade-1-a',
      guardianName: 'Yousaf Khan',
      guardianPhone: '',
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
      guardianPhone: '',
      gender: 'Female',
      rollNo: '10001',
      active: true,
    ),
  ];

  testWidgets('no classes shows a useful setup action, never a blank page',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AttendancePage(
        classesLoader: () async => <SchoolClass>[],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Daily class register'), findsOneWidget);
    expect(find.text('Create your first class'), findsOneWidget);
    expect(find.byKey(const Key('attendance_scroll_view')), findsOneWidget);
    expect(find.text('Attendance saved'), findsOneWidget);
  });

  testWidgets('can mark and save only changed student records', (tester) async {
    Map<String, String>? submitted;
    await tester.pumpWidget(MaterialApp(
      home: AttendancePage(
        classesLoader: () async => classes,
        rosterLoader: (_) async => roster,
        marksLoader: (_, __) async => {'ST-2026-0001': 'present'},
        saveOverride: (classId, date, changes) async {
          expect(classId, 'grade-1-a');
          submitted = Map<String, String>.from(changes);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Daily class register'), findsOneWidget);
    expect(find.text('1 / 2 marked'), findsOneWidget);
    expect(find.text('Unmarked: 1'), findsOneWidget);
    expect(find.text('Absent: 0'), findsOneWidget);
    expect(find.text('Ali Khan'), findsOneWidget);
    // The register is deliberately scrollable; this student may be below
    // the initial viewport on a compact phone.
    await tester.scrollUntilVisible(
      find.byKey(const Key('attendance_student_ST-2026-0002')),
      130,
      scrollable: find.descendant(
        of: find.byKey(const Key('attendance_scroll_view')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Aisha Khan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mark_ST-2026-0002_absent')));
    await tester.pumpAndSettle();
    expect(find.text('Save attendance (1 changes)'), findsOneWidget);
    expect(find.text('Absent: 1'), findsOneWidget);
    await tester.tap(find.text('Save attendance (1 changes)'));
    await tester.pumpAndSettle();
    expect(submitted, {'ST-2026-0002': 'absent'});
    expect(find.text('Attendance saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mark remaining present does not overwrite absence', (tester) async {
    Map<String, String>? changes;
    await tester.pumpWidget(MaterialApp(
      home: AttendancePage(
        classesLoader: () async => classes,
        rosterLoader: (_) async => roster,
        marksLoader: (_, __) async => {'ST-2026-0001': 'absent'},
        saveOverride: (_, __, updates) async => changes =
            Map<String, String>.from(updates),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark remaining present'));
    await tester.pumpAndSettle();
    expect(find.text('Absent: 1'), findsOneWidget);
    expect(find.text('Present: 1'), findsOneWidget);
    expect(find.text('0 / 2 marked'), findsNothing);
    await tester.tap(find.text('Save attendance (1 changes)'));
    await tester.pumpAndSettle();
    expect(changes, {'ST-2026-0002': 'present'});
  });

  testWidgets('restricted roles cannot alter attendance', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AttendancePage(
        role: 'parent',
        classesLoader: () async => classes,
        rosterLoader: (_) async => roster,
        marksLoader: (_, __) async => {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Attendance saved'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
  });
}
