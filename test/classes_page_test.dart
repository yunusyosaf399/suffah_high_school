import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/classes_page.dart';

void main() {
  testWidgets('Class creation remains accessible while cloud data loads', (
    tester,
  ) async {
    final classes = StreamController<List<SchoolClass>>.broadcast();
    addTearDown(classes.close);

    await tester.pumpWidget(
      MaterialApp(home: ClassesPage(classesStream: classes.stream)),
    );
    expect(find.text('Add class'), findsOneWidget);
    expect(find.text('Loading classes'), findsOneWidget);
    expect(find.byTooltip('Test Firebase connection'), findsOneWidget);

    await tester.tap(find.text('Add class'));
    await tester.pumpAndSettle();
    expect(find.text('Class name'), findsOneWidget);
    expect(find.text('Save class'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Empty class list shows a create action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClassesPage(classesStream: Stream.value(<SchoolClass>[])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No classes yet'), findsOneWidget);
    expect(find.text('Create class'), findsOneWidget);
  });
}
