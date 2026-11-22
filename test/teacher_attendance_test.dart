import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/attendance_class_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/teacher_attendance_page.dart';

void main() {
  const assignment = AttendanceClassAssignment(
    classId: 'grade-5-a',
    staffId: 'EMP-2026-0001',
    className: 'Grade 5 – A',
    staffName: 'Aisha Khan',
  );
  const roster = [
    StudentRecord(
      id: 'ST-2026-0001',
      admissionNo: 'ST-2026-0001',
      fullName: 'Ali Khan',
      classId: 'grade-5-a',
      guardianName: '',
      guardianPhone: '',
      gender: 'Not specified',
      rollNo: '10001',
      active: true,
    ),
  ];

  testWidgets('unassigned teacher cannot see student attendance', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TeacherAttendancePage(
      staffId: 'EMP-2026-0001',
      assignmentStream: Stream.value(null),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('No attendance class has been assigned'),
        findsOneWidget);
    expect(find.text('Ali Khan'), findsNothing);
  });

  testWidgets('teacher can mark only their assigned class', (tester) async {
    final opened = <String>[];
    String? markedClass;
    Map<String, String>? saved;
    await tester.pumpWidget(MaterialApp(home: TeacherAttendancePage(
      staffId: assignment.staffId,
      assignmentStream: Stream.value(assignment),
      rosterLoader: (classId) async {
        opened.add(classId);
        return roster;
      },
      marksLoader: (classId, date) async {
        expect(classId, assignment.classId);
        return {};
      },
      saveOverride: (classId, date, changes) async {
        markedClass = classId;
        saved = Map<String, String>.from(changes);
      },
    )));
    await tester.pumpAndSettle();
    expect(opened, ['grade-5-a']);
    expect(find.text('Ali Khan'), findsOneWidget);
    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('attendance_class_selector')));
    expect(selector.onChanged, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('mark_ST-2026-0001_present')),
      110, scrollable: find.descendant(
        of: find.byKey(const Key('attendance_scroll_view')),
        matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const Key('mark_ST-2026-0001_present')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save attendance (1 changes)'));
    await tester.pumpAndSettle();
    expect(markedClass, assignment.classId);
    expect(saved, {'ST-2026-0001': 'present'});
    expect(find.byTooltip('Assign class attendance teachers'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
