import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/owner_dashboard.dart';

void main() {
  testWidgets('school dashboard scrolls past finance metrics to all modules',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: OwnerDashboard(
        displayName: 'School Owner',
        role: 'owner',
        summaryLoader: () async => const SchoolSummary(
          students: 3, classes: 11),
        financePreview: const SizedBox(
          height: 340,
          child: Center(child: Text('Finance at a glance')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final dashboard = find.byKey(const Key('owner_dashboard_scroll'));
    expect(dashboard, findsOneWidget);
    expect(find.text('School overview'), findsOneWidget);
    expect(find.text('Finance at a glance'), findsOneWidget);
    final scrollable = find.descendant(
      of: dashboard, matching: find.byType(Scrollable)).first;
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.pixels, 0);
    await tester.drag(dashboard, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(200));
    expect(find.text('School management'), findsOneWidget);

    await tester.drag(dashboard, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(600));
    expect(find.text('Fees & Finance'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
