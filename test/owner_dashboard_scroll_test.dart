import 'dart:async';
import 'package:suffah_high_school/screens/owner_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/owner_dashboard.dart';

void main() {
  testWidgets('desktop sidebar remains mounted on module and detail routes',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: OwnerDashboard(
      displayName: 'School Owner',
      summaryLoader: () async => const SchoolSummary(students: 3, classes: 11),
      financePreview: const SizedBox(height: 100),
      moduleBuilder: (index) => Scaffold(
        appBar: AppBar(title: Text('Module $index')),
        body: Builder(builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => const Scaffold(body: Center(child: Text('Detail route'))),
          )),
          child: const Text('Open detail'),
        )),
      ),
    )));
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const Key('persistent_school_sidebar'));
    await tester.tap(find.descendant(of: sidebar, matching: find.text('Students')));
    await tester.pumpAndSettle();
    expect(find.text('Module 0'), findsOneWidget);
    expect(sidebar, findsOneWidget);
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail route'), findsOneWidget);
    expect(sidebar, findsOneWidget);
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Detail route'), findsOneWidget);
    expect(sidebar, findsOneWidget);
    await tester.tap(find.descendant(of: sidebar, matching: find.byTooltip('Dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner_dashboard_scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar toggles between expanded and compact navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: OwnerDashboard(
      displayName: 'School Owner',
      summaryLoader: () async => const SchoolSummary(students: 3, classes: 11),
      financePreview: const SizedBox(height: 100),
    )));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pin expanded navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Pin expanded navigation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse navigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('school summary uses a skeleton while data is pending', (tester) async {
    final pending = Completer<SchoolSummary>();
    await tester.pumpWidget(MaterialApp(home: OwnerDashboard(
      displayName: 'School Owner',
      summaryLoader: () => pending.future,
      financePreview: const SizedBox(height: 100),
    )));
    await tester.pump();
    expect(find.byType(DashboardSkeleton), findsOneWidget);
    pending.complete(const SchoolSummary(students: 3, classes: 11));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardSkeleton), findsNothing);
    expect(find.text('Student records'), findsOneWidget);
  });

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
    expect(find.text('School management'), findsWidgets);

    await tester.drag(dashboard, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(350));
    expect(find.text('Fees & Finance'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
