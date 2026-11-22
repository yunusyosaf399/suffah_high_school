import 'package:flutter/material.dart';

import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import 'finance_analytics_tab.dart';
import 'finance_common.dart';
import 'finance_expenses_tab.dart';
import 'finance_fees_tab.dart';
import 'finance_salary_tab.dart';

/// School financial management: obligations are separate from cash movements.
class FinancePage extends StatefulWidget {
  const FinancePage({
    super.key,
    required this.role,
    this.scopeLoader,
    this.repository,
  });
  final String role;
  final Future<FinanceScope> Function()? scopeLoader;
  final FinanceRepository? repository;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage>
    with SingleTickerProviderStateMixin {
  late final _repo = widget.repository ?? FinanceRepository();
  late final TabController _tabs;
  Future<FinanceScope>? _scope;
  int _scopeVersion = 0;

  @override
  void initState() {
    super.initState();
    // Initialize before build, including for roles that have no finance access.
    _tabs = TabController(length: 8, vsync: this);
  }

  bool get _canManage => widget.role == 'owner' || widget.role == 'principal';

  Future<FinanceScope> _load() => _scope ??= _fetchScope();

  Future<FinanceScope> _fetchScope() async {
    if (widget.scopeLoader != null) return widget.scopeLoader!();
    // Start these reads concurrently; do not make every tab wait for them.
    final students = _repo.loadStudents();
    final classes = _repo.loadClasses();
    final teachers = _repo.loadTeachers();
    return FinanceScope(
      classes: await classes,
      students: await students,
      teachers: await teachers,
    );
  }

  void _reload() => setState(() {
    _scope = null;
    _scopeVersion++;
  });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManage) {
      return const Scaffold(
        body: FinanceEmpty('Only the school owner or principal can manage finances.'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fees & Finance'),
        actions: [
          IconButton(
            key: const Key('finance_previous_tab'),
            tooltip: 'Previous finance tab',
            onPressed: () {
              if (_tabs.index > 0) _tabs.animateTo(_tabs.index - 1);
            },
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const Key('finance_next_tab'),
            tooltip: 'Next finance tab',
            onPressed: () {
              if (_tabs.index < _tabs.length - 1) {
                _tabs.animateTo(_tabs.index + 1);
              }
            },
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Reload students, classes and staff',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Fee Setup'),
            Tab(text: 'Generate Finance'),
            Tab(text: 'One-time Fees'),
            Tab(text: 'Collections'),
            Tab(text: 'Salary Setup'),
            Tab(text: 'Pay Salary'),
            Tab(text: 'Expenses'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const PageScrollPhysics(),
        children: [
          _FinanceScopeTab(
            key: ValueKey('fee-$_scopeVersion'),
            loader: _load,
            onRetry: _reload,
            builder: (scope) => FinanceFeeSetupTab(
              scope: scope, role: widget.role, repository: _repo),
          ),
          FinanceGenerateTab(repository: _repo),
          _FinanceScopeTab(
            key: ValueKey('one-time-$_scopeVersion'),
            loader: _load,
            onRetry: _reload,
            builder: (scope) =>
                FinanceOneTimeTab(scope: scope, repository: _repo),
          ),
          FinanceCollectionsTab(repository: _repo),
          _FinanceScopeTab(
            key: ValueKey('salary-$_scopeVersion'),
            loader: _load,
            onRetry: _reload,
            builder: (scope) =>
                FinanceSalarySetupTab(scope: scope, repository: _repo),
          ),
          FinancePaySalaryTab(repository: _repo),
          FinanceExpensesTab(repository: _repo),
          FinanceAnalyticsTab(repository: _repo),
        ],
      ),
    );
  }
}


/// Only tabs that need student, class and staff rosters wait for those reads.
/// Collection, payments, analytics and generation remain immediately accessible.
class _FinanceScopeTab extends StatefulWidget {
  const _FinanceScopeTab({
    super.key,
    required this.loader,
    required this.builder,
    required this.onRetry,
  });

  final Future<FinanceScope> Function() loader;
  final Widget Function(FinanceScope) builder;
  final VoidCallback onRetry;

  @override
  State<_FinanceScopeTab> createState() => _FinanceScopeTabState();
}

class _FinanceScopeTabState extends State<_FinanceScopeTab> {
  late final Future<FinanceScope> _future = widget.loader();

  @override
  Widget build(BuildContext context) => FutureBuilder<FinanceScope>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(schoolErrorMessage(snapshot.error!)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: widget.onRetry,
              child: const Text('Retry loading school records'),
            ),
          ]),
        ));
      }
      if (!snapshot.hasData) {
        return const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading students, classes and staff…'),
          ],
        ));
      }
      return widget.builder(snapshot.data!);
    },
  );
}
