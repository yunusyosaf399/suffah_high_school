import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/students_page.dart';

void main() {
  testWidgets('Student actions remain visible before Firestore loads', (tester) async {
    // Broadcast controllers close immediately even if widgets unsubscribe.
    // A single-subscription controller can leave close() waiting forever.
    final classes = StreamController<List<SchoolClass>>.broadcast();
    final students = StreamController<List<StudentRecord>>.broadcast();
    addTearDown(() async {
      await classes.close();
      await students.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StudentsPage(
          classesStream: classes.stream,
          studentsStream: students.stream,
        ),
      ),
    );
    expect(find.text('Add student'), findsOneWidget);
    expect(find.text('Manage classes & sections'), findsOneWidget);
    expect(find.text('Loading classes'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Missing class shows actionable setup rather than blank screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudentsPage(
          classesStream: Stream.value(<SchoolClass>[]),
          studentsStream: Stream.value(<StudentRecord>[]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Create your first class'), findsOneWidget);
    expect(find.text('Create a class'), findsOneWidget);
    expect(find.text('Add student'), findsOneWidget);
  });

  testWidgets('Empty student list gives a clear admission action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudentsPage(
          classesStream: Stream.value(const [
            SchoolClass(id: 'grade-1-a', name: 'Grade 1', section: 'A', active: true),
          ]),
          studentsStream: Stream.value(<StudentRecord>[]),
        ),
      ),
    );
    // The class snapshot must render before the nested students stream binds.
    await tester.pumpAndSettle();
    expect(find.text('No students yet'), findsOneWidget);
    expect(find.text('Admit first student'), findsOneWidget);
  });
}
