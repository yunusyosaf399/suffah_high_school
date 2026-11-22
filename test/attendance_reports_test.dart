import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/attendance_reports_tab.dart';

void main() {
  const roster = [
    StudentRecord(
      id: 'ST-2026-0001', admissionNo: 'ST-2026-0001',
      fullName: 'Ali Khan', classId: 'grade-5-a',
      guardianName: '', guardianPhone: '', gender: '',
      rollNo: '10001', active: true),
    StudentRecord(
      id: 'ST-2026-0002', admissionNo: 'ST-2026-0002',
      fullName: 'Aisha Khan', classId: 'grade-5-a',
      guardianName: '', guardianPhone: '', gender: '',
      rollNo: '10002', active: true),
  ];

  test('report counts saved statuses without equating unmarked and absent', () {
    final day = AttendanceDayStats.fromMarks(
      DateTime(2026, 11, 22), roster, {'ST-2026-0001': 'present'});
    expect(day.total, 2);
    expect(day.present, 1);
    expect(day.absent, 0);
    expect(day.marked, 1);
    expect(day.unmarked, 1);
    expect(day.attended, 1);
    expect(day.attendanceRate, 1);
    expect(day.completionRate, 0.5);

    final empty = AttendanceDayStats.fromMarks(
      DateTime(2026, 11, 21), roster, {});
    expect(empty.attendanceRate, isNull);
    expect(empty.marked, 0);
    expect(empty.absent, 0);
  });

  testWidgets('reports render real data as KPI widgets and two charts',
      (tester) async {
    final requested = <String>[];
    final date = DateTime(2026, 11, 22);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: AttendanceReportsTab(
        classId: 'grade-5-a',
        classLabel: 'Grade 5 – A',
        roster: roster,
        referenceDate: date,
        marksLoader: (classId, queried) async {
          expect(classId, 'grade-5-a');
          requested.add('${queried.year}-${queried.month}-${queried.day}');
          if (queried.day == 22) {
            return {'ST-2026-0001': 'present', 'ST-2026-0002': 'absent'};
          }
          return {};
        },
      ),
    )));
    await tester.pumpAndSettle();
    expect(requested.length, 7);
    expect(find.text('Attendance reports & analytics'), findsOneWidget);
    expect(find.text('7-day attendance'), findsOneWidget);
    expect(find.text('50%'), findsWidgets);
    expect(find.byKey(const Key('attendance_breakdown_chart')),
        findsOneWidget);
    expect(find.byKey(const Key('attendance_trend_2026-11-22')),
        findsOneWidget);
    expect(find.text('Absent on date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
