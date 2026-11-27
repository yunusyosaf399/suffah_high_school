import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/examination_repository.dart';
import '../data/finance_models.dart';
import '../data/inventory_department_analytics.dart';
import '../data/school_errors.dart';

const dashboardPurple = Color(0xFF6325A6);

/// Static chart-shaped placeholders: no looping animation or fake values.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key, this.full = false});
  final bool full;

  @override
  Widget build(BuildContext context) {
    Widget block(double height, {double? width}) => Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9E4F0),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: 'Loading school data',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              block(18, width: 155),
              const SizedBox(height: 12),
              block(12, width: 100),
              if (full) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: block(70)),
                  const SizedBox(width: 12),
                  Expanded(child: block(70)),
                ]),
              ],
              const SizedBox(height: 18),
              SizedBox(height: 108, child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in [35.0, 76.0, 52.0, 95.0, 68.0, 105.0])
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: block(h),
                    )),
                ],
              )),
              const SizedBox(height: 12),
              block(10, width: 115),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, {this.money = false, this.percent = false});
  final String label;
  final double value;
  final bool money, percent;
  String get formatted => money ? financeMoney(value.round()) :
      percent ? '${value.toStringAsFixed(1)}%' : value.toStringAsFixed(0);
}

class _Report {
  const _Report(this.title, this.subtitle, this.metrics, {this.note = ''});
  final String title, subtitle, note;
  final List<_Metric> metrics;
}

class OwnerAnalytics extends StatefulWidget {
  const OwnerAnalytics({super.key, required this.slideshow});
  final bool slideshow;

  @override
  State<OwnerAnalytics> createState() => _OwnerAnalyticsState();
}

class _OwnerAnalyticsState extends State<OwnerAnalytics> with AutomaticKeepAliveClientMixin<OwnerAnalytics> {
  @override
  bool get wantKeepAlive => true;
  final _db = FirebaseFirestore.instance;
  final _now = schoolExamNow();
  late final _finance = _loadFinance();
  late final _canteen = _loadInventory('canteen');
  late final _stationery = _loadInventory('stationery');
  late final _attendance = _loadAttendance();
  late final _exams = _loadExams();
  Timer? _timer;
  int _index = 0;
  int _animationRevision = 0;
  static const _titles = [
    'Cash flow', 'Tuition fees', 'Transport fees', 'Other fees',
    'Salary', 'Expenses', 'Canteen sales', 'Stationery sales',
    'Attendance', 'Examination status', 'Marks completion', 'Marks performance',
  ];

  @override
  void initState() {
    super.initState();
    // Start all reports once, even if the saved slideshow opens on only one.
    // Attach an error listener now; each FutureBuilder still receives its error.
    for (final future in [_finance, _canteen, _stationery, _attendance, _exams]) {
      unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    }
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant OwnerAnalytics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slideshow != widget.slideshow) {
      _index = 0;
      _animationRevision++;
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (widget.slideshow) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _advance(1);
      });
    }
  }

  void _advance(int delta) => setState(() {
    _index = (_index + delta) % _titles.length;
    _animationRevision++;
  });

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<_Report>> _loadFinance() async {
    final month = financeMonth(_now);
    final db = _db;
    final results = await Future.wait([
      for (final collection in [
        'finance_ledger', 'finance_fee_bills', 'finance_salary_bills',
        'finance_recurring_bills',
      ])
        db.collection(collection)
          .where(collection == 'finance_ledger' ? 'postedMonth' : 'month',
              isEqualTo: month)
          .get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 30));
    final ledger = results[0].docs.map(FinanceEntry.fromSnapshot).toList();
    final fees = results[1].docs.map(FinanceBill.fromSnapshot).toList();
    final salaries = results[2].docs.map(FinanceBill.fromSnapshot).toList();
    final expenses = results[3].docs.map(FinanceBill.fromSnapshot).toList();
    final label = financeMonthLabel(month);
    _Metric cash(String label, int amount) => _Metric(label, amount.toDouble(), money: true);
    int sumEntries(bool Function(FinanceEntry) include) => ledger.where(include)
        .fold<int>(0, (sum, entry) => sum + entry.amountMinor);
    final credit = sumEntries((e) => e.direction == 'credit');
    final debit = sumEntries((e) => e.direction == 'debit');
    List<_Metric> billMetrics(Iterable<FinanceBill> bills) {
      final total = bills.fold<int>(0, (s, b) => s + b.amountMinor);
      final paid = bills.fold<int>(0, (s, b) => s + b.paidMinor);
      return [cash('Billed', total), cash('Paid against bills', paid),
        cash('Outstanding', bills.fold<int>(0, (s, b) => s + math.max(0, b.remainingMinor)))];
    }
    final other = fees.where((b) => b.category == 'one_time').toList();
    return [
      _Report('Cash flow', '$label • posted cash transactions', [
        cash('Credit', credit), cash('Debit', debit), cash('Net cash flow', credit - debit),
      ]),
      for (final category in ['tuition', 'transport'])
        _Report(category == 'tuition' ? 'Tuition fees' : 'Transport fees',
          '$label • bills issued for this month',
          billMetrics(fees.where((b) => b.category == category))),
      _Report('Other fees', '$label • amount billed by fee type', [
        ...billMetrics(other),
        for (final type in {...financeOneTimeCategories, ...other.map((b) => b.subcategory)})
          if (type.isNotEmpty)
            cash(type, other.where((b) => b.subcategory == type)
              .fold<int>(0, (sum, b) => sum + b.amountMinor)),
      ], note: 'Fee type bars show billed amounts, not additional revenue.'),
      _Report('Salary', '$label • salary bills', billMetrics(salaries)),
      _Report('Expenses', '$label • recurring bills and cash payments', [
        ...billMetrics(expenses),
        cash('Non-salary cash debits', sumEntries((e) => e.direction == 'debit' && e.category != 'salary')),
      ], note: 'Cash payments and bill totals are different measures; do not add them.'),
    ];
  }

  Future<List<_Report>> _loadInventory(String department) async {
    final data = await InventoryDepartmentAnalyticsRepository(firestore: _db).load(
      department: department, period: InventoryReportPeriod.month,
      year: _now.year, month: _now.month,
    ).timeout(const Duration(seconds: 30));
    final title = department == 'canteen' ? 'Canteen sales' : 'Stationery sales';
    return [
      _Report(title, '${financeMonthLabel(financeMonth(_now))} • PKR', [
        _Metric('Sales value', data.salesMinor.toDouble(), money: true),
        _Metric('Stock purchases', data.purchaseMinor.toDouble(), money: true),
        if (data.completeCostCoverage)
          _Metric('Estimated gross profit', data.estimatedProfitMinor.toDouble(), money: true),
      ], note: '${data.stockUnits} units in stock now • ${data.soldUnits} units sold.'
          '${data.completeCostCoverage ? '' : ' Profit unavailable: purchase costs missing.'}'
          '${data.limited ? ' History limit reached; totals may be incomplete.' : ''}'
          ' Profit is estimated using current purchase costs.'),
    ];
  }

  Future<List<_Report>> _loadAttendance() async {
    final today = attendanceDateKey(_now);
    final days = await _db.collection('attendance_days')
        .where('date', isEqualTo: today)
        .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 25));
    final snapshots = await Future.wait([
      for (final day in days.docs)
        day.reference.collection('marks').get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 25));
    final counts = <String,int>{};
    for (final snapshot in snapshots) {
      for (final mark in snapshot.docs) {
        final status = mark.data()['status'];
        if (status is String) counts.update(status, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return [_Report('Attendance', '$today • recorded class registers', [
      for (final status in ['present', 'absent', 'late', 'leave', 'unmarked'])
        _Metric(status[0].toUpperCase() + status.substring(1), (counts[status] ?? 0).toDouble()),
    ], note: '${days.docs.length} class registers recorded. Missing registers are not counted as absences.')];
  }

  Future<List<_Report>> _loadExams() async {
    final repo = ExaminationRepository(firestore: _db);
    final cycle = await repo.loadActiveTerm().timeout(const Duration(seconds: 20));
    final query = await _db.collection('examinations').where('active', isEqualTo: true)
        .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 25));
    // Closed annual cycles keep their paper documents for historical results.
    final papers = query.docs.where((p) {
      final id = p.data()['cycleId'];
      return id == null || id == cycle?['id'];
    }).toList();
    int status(String value) => papers.where((p) => (p.data()['resultStatus'] ?? 'draft') == value).length;
    final managed = papers.where((p) => p.data()['cycleId'] != null).toList();
    final expected = managed.fold<int>(0, (n, p) => n + examStrings(p.data()['expectedStudentIds']).length);
    final marked = managed.fold<int>(0, (n, p) {
      final d = p.data();
      return n + examStrings(d['markedStudentIds']).toSet()
        .intersection(examStrings(d['expectedStudentIds']).toSet()).length;
    });
    final eligible = query.docs.where((p) => p.data()['resultStatus'] == 'released').toList()
      ..sort((a,b) => (b.data()['examDate'] ?? '').toString().compareTo((a.data()['examDate'] ?? '').toString()));
    final sample = eligible.take(10).toList();
    List<_Metric> performance = [];
    var performanceUnavailable = false;
    try {
    final scoresByPaper = await Future.wait([
      for (final p in sample) () async {
        final max = p.data()['maxMarks'];
        final scores = await p.reference.collection('marks').get(const GetOptions(source: Source.server));
        final values = scores.docs.map((d) => d.data()['score']).whereType<num>()
            .where((v) => max is num && max > 0 && v >= 0 && v <= max).toList();
        if (max is! num || max <= 0 || values.isEmpty) return null;
        return _Metric('${p.data()['className'] ?? ''} • ${p.data()['subject'] ?? p.id}',
          values.fold<double>(0, (s, v) => s + v.toDouble()) / values.length / max * 100,
          percent: true);
      }(),
    ]).timeout(const Duration(seconds: 25));
    performance = scoresByPaper.whereType<_Metric>().toList();
    } catch (_) {
      performanceUnavailable = true;
    }
    return [
      _Report('Examination status', cycle == null ? 'No active annual term • active papers and tests'
          : '${cycle['category']} • ${cycle['startDate']} – ${cycle['endDate']}', [
        _Metric('Draft papers', status('draft').toDouble()),
        _Metric('Submitted for review', status('submitted').toDouble()),
        _Metric('Released papers', status('released').toDouble()),
      ], note: cycle == null ? '${papers.length} active papers and tests.' :
        '${examStrings(cycle['classIds']).length}/${examStrings(cycle['plannedClassIds']).length} classes scheduled • '
        '${examStrings(cycle['releasedPaperIds']).length}/${examStrings(cycle['paperIds']).length} term results released.'),
      _Report('Marks completion', 'Active managed term papers', [
        _Metric('Marks recorded', marked.toDouble()),
        _Metric('Marks pending', math.max(0, expected - marked).toDouble()),
      ], note: 'Based on the examination roster ledger; excludes older unmanaged papers.'),
      _Report('Marks performance', 'Mean percentage • latest 10 released papers in loaded records', performance,
        note: performanceUnavailable ? 'Marks could not be loaded. Refresh to retry.' : 'Only recorded valid scores are included. Not a school-wide average.'),
    ];
  }

  Widget _report(int index) {
    final (future, offset) = switch (index) {
      <= 5 => (_finance, index),
      6 => (_canteen, 0),
      7 => (_stationery, 0),
      8 => (_attendance, 0),
      _ => (_exams, index - 9),
    };
    return FutureBuilder<List<_Report>>(
      key: ValueKey(index),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Card(child: ListTile(
          title: Text(_titles[index]), subtitle: Text(schoolErrorMessage(snapshot.error!)),
        ));
        if (!snapshot.hasData) return const DashboardSkeleton();
        return _ReportCard(
          key: ValueKey('$index-$_animationRevision'),
          report: snapshot.data![offset],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        const Expanded(child: Text('School analytics', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (widget.slideshow) ...[
          IconButton(tooltip: 'Previous graph', onPressed: () => _advance(-1), icon: const Icon(Icons.chevron_left)),
          Text('${_index + 1}/${_titles.length}'),
          IconButton(tooltip: 'Next graph', onPressed: () => _advance(1), icon: const Icon(Icons.chevron_right)),
        ],
      ]),
      if (widget.slideshow) ...[
        const Text('Slideshow • changes every 10 seconds'),
        const SizedBox(height: 8),
        _report(_index),
      ] else LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860 ? 2 : 1;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < _titles.length; i++)
            SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns,
              child: _report(i)),
        ]);
      }),
    ],
  );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({super.key, required this.report});
  final _Report report;
  @override
  Widget build(BuildContext context) {
    final max = report.metrics.fold<double>(1, (v,m) => math.max(v, m.value.abs()));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(report.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(report.subtitle, style: const TextStyle(color: Color(0xFF68647D), fontSize: 11)),
          const SizedBox(height: 16),
          if (report.metrics.isEmpty) const Text('No records available for this report.'),
          for (final metric in report.metrics) ...[
            Row(children: [
              Expanded(child: Text(metric.label)),
              const SizedBox(width: 8),
              Text(metric.formatted, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: metric.value.abs() / max),
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (context, fraction, _) => Container(
                height: 9,
                decoration: BoxDecoration(color: const Color(0xFFECE8F4), borderRadius: BorderRadius.circular(5)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0).toDouble(),
                  child: DecoratedBox(decoration: BoxDecoration(
                    color: metric.value < 0 ? const Color(0xFFC54859) : dashboardPurple,
                    borderRadius: BorderRadius.circular(5),
                  )),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (report.note.isNotEmpty) Text(report.note, style: const TextStyle(fontSize: 11, color: Color(0xFF68647D))),
        ]),
      ),
    );
  }
}
