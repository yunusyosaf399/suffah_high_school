import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/finance_scheduler_models.dart';
import '../data/school_errors.dart';

/// Owner/principal preferences. Activation is only real when backend heartbeats
/// are present; mobile never generates scheduled bills on a timer.
class FinanceMonthlySchedulerPage extends StatefulWidget {
  const FinanceMonthlySchedulerPage({
    super.key,
    required this.repository,
  });

  final FinanceRepository repository;

  @override
  State<FinanceMonthlySchedulerPage> createState() =>
      _FinanceMonthlySchedulerPageState();
}

class _FinanceMonthlySchedulerPageState
    extends State<FinanceMonthlySchedulerPage> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  FinanceAutomationSnapshot? _saved;
  Map<String, FinanceAutomationPreference> _preferences = {};
  Map<String, FinanceAutomationPlan> _plans = {};

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
  }

  Future<void> _reload({bool initial = false}) async {
    if (!initial) setState(() => _loading = true);
    try {
      final snapshot = await widget.repository.loadFinanceAutomation();
      if (!mounted) return;
      setState(() {
        _saved = snapshot;
        _preferences = {...snapshot.preferences};
        _plans = {for (final item in snapshot.plans) item.id: item};
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveGenerationSchedules(_preferences);
      final original = {
        for (final plan in _saved?.plans ?? <FinanceAutomationPlan>[])
          plan.id: plan,
      };
      for (final plan in _plans.values.where((p) => p.active)) {
        final old = original[plan.id];
        if (old != null &&
            old.scheduleDay == plan.scheduleDay &&
            old.automaticEnabled == plan.automaticEnabled) continue;
        await widget.repository.saveRecurringAutomation(
          planId: plan.id,
          scheduleDay: plan.scheduleDay,
          automaticEnabled: plan.automaticEnabled,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Monthly schedule saved. Automatic execution requires '
            'a deployed backend worker.'),
      ));
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(schoolErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workerOnline = _saved?.workerConnected(DateTime.now()) ?? false;
    final expensePlans = _plans.values.where((p) => p.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Finance Scheduler'),
        actions: [
          IconButton(
            tooltip: 'Reload schedule settings',
            onPressed: _loading || _saving ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(schoolErrorMessage(_error!)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reload, child: const Text('Retry')),
                  ]),
                ))
              : ListView(
                  key: const Key('finance_scheduler_page'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Text('Automatic monthly generation',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 7),
                    const Text('Tuition, transport, teacher salaries and '
                        'monthly expenses generate unpaid bills only. '
                        'Actual payments create separate credit/debit receipts.'),
                    const SizedBox(height: 12),
                    Card(child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(workerOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              workerOnline
                                  ? 'Automatic worker online'
                                  : 'Automatic execution not active',
                              key: const Key('finance_scheduler_worker_status'),
                              style: theme.textTheme.titleSmall,
                            )),
                          ]),
                          const SizedBox(height: 8),
                          Text(workerOnline
                              ? 'The trusted worker has recently checked '
                                'your monthly schedule.'
                              : 'Preferences can be saved, but automatic '
                                'execution requires Firebase Cloud Functions '
                                'deployment on Blaze. Continue to generate '
                                'bills manually until deployed.',
                            style: theme.textTheme.bodySmall),
                          const SizedBox(height: 7),
                          const Text('Daily check: 6:10 AM Pakistan time. '
                              'An enabled job runs on its selected date '
                              '(1–27), or catches up on the next check.',
                            style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                    const SizedBox(height: 18),
                    Text('Fees and teacher salaries',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Enable the types you want to generate '
                        'automatically and select a monthly day.'),
                    const SizedBox(height: 8),
                    for (final key in financeSchedulerCategories.keys)
                      if (_preferences.containsKey(key))
                        _SchedulerRow(
                          key: Key('scheduler_row_$key'),
                          title: financeSchedulerCategories[key]!,
                          subtitle: key == 'tuition'
                              ? 'Fixed class tuition rates'
                              : key == 'transport'
                                  ? 'Individual student transport rates'
                                  : 'Active teachers with salary setup',
                          day: _preferences[key]!.scheduleDay,
                          enabled: _preferences[key]!.automaticEnabled,
                          onDay: (day) => setState(() {
                            _preferences[key] =
                                _preferences[key]!.copyWith(scheduleDay: day);
                          }),
                          onEnabled: (enabled) => setState(() {
                            _preferences[key] = _preferences[key]!
                                .copyWith(automaticEnabled: enabled);
                          }),
                        ),
                    const SizedBox(height: 18),
                    Text('Recurring monthly expenses',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Each active expense plan can have '
                        'its own schedule day and automatic switch.'),
                    const SizedBox(height: 8),
                    if (expensePlans.isEmpty)
                      const Card(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No monthly expense plans yet. '
                            'Create one in the Expenses tab.'),
                      )),
                    for (final plan in expensePlans)
                      _SchedulerRow(
                        key: Key('scheduler_expense_${plan.id}'),
                        title: plan.name,
                        subtitle: financeMoney(plan.amountMinor),
                        day: plan.scheduleDay,
                        enabled: plan.automaticEnabled,
                        onDay: (day) => setState(() {
                          _plans[plan.id] = plan.copyWith(scheduleDay: day);
                        }),
                        onEnabled: (enabled) => setState(() {
                          _plans[plan.id] =
                              plan.copyWith(automaticEnabled: enabled);
                        }),
                      ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('finance_save_scheduler'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving
                          ? 'Saving…' : 'Save monthly schedules'),
                    ),
                    const SizedBox(height: 12),
                    Text('Existing bills, balances and receipts are never '
                        'overwritten. The latest Firestore rules must be '
                        'published before enabling automation.',
                      style: theme.textTheme.bodySmall),
                  ],
                ),
    );
  }
}

class _SchedulerRow extends StatelessWidget {
  const _SchedulerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.day,
    required this.enabled,
    required this.onDay,
    required this.onEnabled,
  });

  final String title;
  final String subtitle;
  final int day;
  final bool enabled;
  final ValueChanged<int> onDay;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: onEnabled,
          title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
        ),
        Row(children: [
          const Expanded(child: Text('Generate monthly on',
              style: TextStyle(fontSize: 12))),
          DropdownButton<int>(
            value: day,
            items: [
              for (var n = 1; n <= 27; n++)
                DropdownMenuItem(value: n, child: Text('Day $n')),
            ],
            onChanged: (v) {
              if (v != null) onDay(v);
            },
          ),
        ]),
        Text(enabled ? 'Enabled when backend is online' : 'Manual only',
          style: Theme.of(context).textTheme.labelSmall),
      ]),
    ),
  );
}
