import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_repository.dart';
import 'package:suffah_high_school/data/finance_scheduler_models.dart';
import 'package:suffah_high_school/screens/finance_monthly_scheduler_page.dart';

class _FakeSchedulerRepository extends FinanceRepository {
  int loads = 0;
  int saves = 0;
  int expenseSaves = 0;
  Map<String, FinanceAutomationPreference>? savedCategories;
  final savedExpenses = <String, FinanceAutomationPlan>{};

  @override
  Future<FinanceAutomationSnapshot> loadFinanceAutomation() async {
    loads++;
    return FinanceAutomationSnapshot(
      preferences: {
        for (final category in financeSchedulerCategories.keys)
          category: FinanceAutomationPreference(
            category: category,
            scheduleDay: category == 'tuition' ? 5 : 10,
            automaticEnabled: category == 'tuition',
          ),
      },
      plans: const [
        FinanceAutomationPlan(
          id: 'rent-1',
          name: 'Building Rent',
          amountMinor: 2400000,
          scheduleDay: 12,
          active: true,
          automaticEnabled: false,
        ),
      ],
    );
  }

  @override
  Future<void> saveGenerationSchedules(
      Map<String, FinanceAutomationPreference> preferences) async {
    saves++;
    savedCategories = {...preferences};
  }

  @override
  Future<void> saveRecurringAutomation({
    required String planId,
    required int scheduleDay,
    required bool automaticEnabled,
  }) async {
    expenseSaves++;
    savedExpenses[planId] = FinanceAutomationPlan(
      id: planId, name: 'Building Rent', amountMinor: 2400000,
      scheduleDay: scheduleDay, active: true,
      automaticEnabled: automaticEnabled,
    );
  }
}

void main() {
  test('backend heartbeat must be recent for active status', () {
    final now = DateTime.utc(2026, 11, 23, 10);
    const noWorker = FinanceAutomationSnapshot(
      preferences: {}, plans: [],
    );
    expect(noWorker.workerConnected(now), isFalse);
    final recent = FinanceAutomationSnapshot(
      preferences: const {}, plans: const [],
      lastHeartbeat: now.subtract(const Duration(hours: 6)),
    );
    expect(recent.workerConnected(now), isTrue);
    final stale = FinanceAutomationSnapshot(
      preferences: const {}, plans: const [],
      lastHeartbeat: now.subtract(const Duration(days: 3)),
    );
    expect(stale.workerConnected(now), isFalse);
  });

  testWidgets('all four scheduling types have safe on/off and day controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _FakeSchedulerRepository();

    await tester.pumpWidget(MaterialApp(
      home: FinanceMonthlySchedulerPage(repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Monthly Finance Scheduler'), findsOneWidget);
    expect(find.text('Automatic execution not active'), findsOneWidget);
    expect(find.byKey(const Key('scheduler_row_tuition')), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const Key('finance_scheduler_page')),
      matching: find.byType(Scrollable),
    ).first;

    final tuition = find.descendant(
      of: find.byKey(const Key('scheduler_row_tuition')),
      matching: find.byType(SwitchListTile),
    );
    expect(tuition, findsOneWidget);
    await tester.tap(tuition);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('scheduler_row_transport')),
      140, scrollable: scrollable,
    );
    final transport = find.descendant(
      of: find.byKey(const Key('scheduler_row_transport')),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(transport);
    await tester.tap(transport);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('scheduler_row_salary')),
      140, scrollable: scrollable,
    );
    expect(find.byKey(const Key('scheduler_row_salary')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('scheduler_expense_rent-1')),
      140, scrollable: scrollable,
    );
    final rent = find.descendant(
      of: find.byKey(const Key('scheduler_expense_rent-1')),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(rent);
    await tester.tap(rent);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('finance_save_scheduler')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('finance_scheduler_page')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.tap(find.byKey(const Key('finance_save_scheduler')));
    await tester.pumpAndSettle();

    expect(repo.saves, 1);
    expect(repo.savedCategories!['tuition']!.automaticEnabled, false);
    expect(repo.savedCategories!['transport']!.automaticEnabled, true);
    expect(repo.savedCategories!['salary']!.automaticEnabled, false);
    expect(repo.savedCategories!['salary']!.scheduleDay, 10);
    expect(repo.expenseSaves, 1);
    expect(repo.savedExpenses['rent-1']!.automaticEnabled, true);
    expect(tester.takeException(), isNull);
  });
}
