import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import 'finance_common.dart';

class FinanceAnalyticsTab extends StatefulWidget {
  const FinanceAnalyticsTab({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  State<FinanceAnalyticsTab> createState() => _FinanceAnalyticsTabState();
}

class _FinanceAnalyticsTabState extends State<FinanceAnalyticsTab> {
  late Future<FinanceOverview> _overview = widget.repository.loadOverview();

  void _refresh() => setState(() {
    _overview = widget.repository.loadOverview();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<FinanceOverview>(
    future: _overview,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Text(schoolErrorMessage(snapshot.error!)),
            OutlinedButton(
              onPressed: _refresh,
              child: const Text('Retry analytics')),
          ],
        ));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await _overview;
        },
        child: ListView(
          key: const Key('finance_analytics_scroll'),
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
          children: [
            Row(children: [
              Expanded(child: Text('Finance dashboard & analytics',
                style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'Refresh finance analytics',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_outlined)),
            ]),
            const SizedBox(height: 5),
            const Text('Last six months of recorded cash transactions and '
                'generated but unpaid bills. Generated obligations are '
                'not counted as credit or debit.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            _FinanceCards(data: data),
            const SizedBox(height: 14),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly credits vs debits',
                    style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 7),
                  const Text('Cash received (credit) and cash paid (debit)',
                    style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 16),
                  _FinanceMonthlyChart(data: data.months),
                ],
              ),
            )),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent ledger transactions',
                    style: Theme.of(context).textTheme.titleSmall),
                  if (data.recentEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No completed financial transactions yet.')),
                  for (final entry in data.recentEntries)
                    ListTile(
                      dense: true,
                      title: Text('${entry.displayName} · ${entry.category}'),
                      subtitle: Text(
                        '${entry.sourceType} · ${entry.postedMonth}\n'
                        'Receipt ${entry.id} · ${entry.method}'),
                      isThreeLine: true,
                      trailing: Text(
                        '${entry.direction == 'credit' ? '+' : '-'}'
                        '${financeMoney(entry.amountMinor)}',
                        style: TextStyle(
                          color: entry.direction == 'credit'
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            )),
            const SizedBox(height: 10),
            const Text('Reporting scope: 6 calendar months and the most '
                'recent 3,000 ledger entries / 4,000 student fee bills. '
                'For larger long-term reporting, server-side aggregates '
                'will be needed. Outstanding totals exclude older months.',
              style: TextStyle(fontSize: 11)),
          ],
        ),
      );
    },
  );
}

class _FinanceCards extends StatelessWidget {
  const _FinanceCards({required this.data});
  final FinanceOverview data;

  @override
  Widget build(BuildContext context) {
    final current = data.months.last;
    final metrics = <({String label, int amount, IconData icon})>[
      (label: 'Credit this month', amount: current.creditsMinor,
        icon: Icons.south_west),
      (label: 'Debit this month', amount: current.debitsMinor,
        icon: Icons.north_east),
      (label: 'Net cash this month', amount: current.netMinor,
        icon: Icons.account_balance_wallet_outlined),
      (label: 'Outstanding fees (6 mo)', amount: data.unpaidFeesMinor,
        icon: Icons.receipt_long_outlined),
      (label: 'Unpaid salaries (6 mo)', amount: data.unpaidSalariesMinor,
        icon: Icons.badge_outlined),
      (label: 'Unpaid recurring bills (6 mo)', amount: data.unpaidExpensesMinor,
        icon: Icons.home_work_outlined),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final metric in metrics)
        SizedBox(width: 175, child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(metric.icon,
                  color: Theme.of(context).colorScheme.primary, size: 21),
                const SizedBox(height: 9),
                Text(financeMoney(metric.amount),
                  style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(metric.label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        )),
    ]);
  }
}

class _FinanceMonthlyChart extends StatelessWidget {
  const _FinanceMonthlyChart({required this.data});
  final List<FinanceMonthSummary> data;

  @override
  Widget build(BuildContext context) {
    final ceiling = math.max(1, data.fold<int>(0, (peak, month) =>
        math.max(peak, math.max(month.creditsMinor, month.debitsMinor))));
    return Column(
      children: [
        Row(children: [
          Icon(Icons.circle, color: Colors.green.shade700, size: 12),
          const Text(' Credits', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 16),
          Icon(Icons.circle,
              color: Theme.of(context).colorScheme.error, size: 12),
          const Text(' Debits', style: TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final month in data)
                SizedBox(width: 72, child: Column(
                  children: [
                    SizedBox(height: 148, child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          key: Key('finance_credit_bar_${month.month}'),
                          width: 24,
                          height: math.max(3, 134 * month.creditsMinor / ceiling),
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          key: Key('finance_debit_bar_${month.month}'),
                          width: 24,
                          height: math.max(3, 134 * month.debitsMinor / ceiling),
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ],
                    )),
                    const SizedBox(height: 7),
                    Text(month.month.substring(5),
                      style: const TextStyle(fontSize: 11)),
                  ],
                )),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact owner/principal overview with persisted card choices and optional
/// 10-second rotation. No timers are started when rotation is off.
class FinanceDashboardPreview extends StatefulWidget {
  const FinanceDashboardPreview({super.key});
  @override
  State<FinanceDashboardPreview> createState() => _FinanceDashboardPreviewState();
}

class _FinanceDashboardPreviewState extends State<FinanceDashboardPreview> {
  final FinanceRepository _repo = FinanceRepository();
  late Future<FinanceOverview> _overview = _repo.loadOverview();
  final Set<String> _shown = {'credit', 'debit', 'net', 'fees'};
  bool _rotate = false;
  int _rotationIndex = 0;
  Timer? _timer;

  static const options = <String, String>{
    'credit': 'Credit this month',
    'debit': 'Debit this month',
    'net': 'Net cash this month',
    'fees': 'Outstanding fees (6 mo)',
    'salaries': 'Unpaid salaries (6 mo)',
    'expenses': 'Unpaid recurring expenses (6 mo)',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final saved = await _repo.loadDashboardPreferences();
      if (!mounted || saved == null) return;
      final stored = (saved['visibleCards'] as List?)
          ?.whereType<String>()
          .where(options.containsKey)
          .toSet();
      setState(() {
        if (stored != null && stored.isNotEmpty) {
          _shown
            ..clear()
            ..addAll(stored);
        }
        _rotate = saved['rotate'] == true;
      });
      _syncTimer();
    } catch (_) {
      // No persisted preferences yet; default cards remain available.
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_rotate || _shown.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _rotationIndex++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _customize() async {
    final selected = {..._shown};
    var rotate = _rotate;
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('Customize finance cards'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in options.entries)
                CheckboxListTile(
                  value: selected.contains(entry.key),
                  title: Text(entry.value,
                    style: const TextStyle(fontSize: 12)),
                  onChanged: (v) => update(() {
                    if (v == true) {
                      selected.add(entry.key);
                    } else if (selected.length > 1) {
                      selected.remove(entry.key);
                    }
                  }),
                ),
              SwitchListTile(
                value: rotate,
                title: const Text('Rotate cards every 10 seconds'),
                subtitle: const Text('Show one selected metric at a time'),
                onChanged: (v) => update(() => rotate = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
            FilledButton(
              key: const Key('finance_save_dashboard_preferences'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply cards')),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _shown
        ..clear()
        ..addAll(selected);
      _rotate = rotate;
      _rotationIndex = 0;
    });
    _syncTimer();
    try {
      await _repo.saveDashboardPreferences(
        visibleCards: _shown.toList(),
        rotate: _rotate,
      );
    } catch (error) {
      if (mounted) financeSnack(context,
          'Cards changed for this session, but preferences were not saved: '
          '${schoolErrorMessage(error)}');
    }
  }

  List<({String key, String label, int minor, IconData icon})>
      _metrics(FinanceOverview data) {
    final now = data.months.last;
    return [
      (key: 'credit', label: options['credit']!,
       minor: now.creditsMinor, icon: Icons.south_west),
      (key: 'debit', label: options['debit']!,
       minor: now.debitsMinor, icon: Icons.north_east),
      (key: 'net', label: options['net']!,
       minor: now.netMinor, icon: Icons.account_balance_wallet_outlined),
      (key: 'fees', label: options['fees']!,
       minor: data.unpaidFeesMinor, icon: Icons.receipt_long_outlined),
      (key: 'salaries', label: options['salaries']!,
       minor: data.unpaidSalariesMinor, icon: Icons.badge_outlined),
      (key: 'expenses', label: options['expenses']!,
       minor: data.unpaidExpensesMinor, icon: Icons.home_work_outlined),
    ];
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('Finance at a glance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700))),
            IconButton(
              key: const Key('finance_dashboard_customize'),
              tooltip: 'Show/hide or rotate finance cards',
              icon: const Icon(Icons.tune_outlined),
              onPressed: _customize),
            IconButton(
              tooltip: 'Refresh financial data',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _overview = _repo.loadOverview();
              })),
          ]),
          FutureBuilder<FinanceOverview>(
            future: _overview,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(schoolErrorMessage(snapshot.error!),
                  style: const TextStyle(fontSize: 11));
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final metrics = _metrics(snapshot.data!)
                  .where((metric) => _shown.contains(metric.key)).toList();
              final displayed = _rotate && metrics.isNotEmpty
                  ? [metrics[_rotationIndex % metrics.length]]
                  : metrics;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_rotate)
                    const Text('Rotating selected cards every 10 seconds',
                      style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 9),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final metric in displayed)
                      SizedBox(width: 160, child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(metric.icon, size: 20),
                            const SizedBox(height: 6),
                            Text(financeMoney(metric.minor),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                            Text(metric.label,
                              style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                      )),
                  ]),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
