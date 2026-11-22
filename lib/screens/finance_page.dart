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
  int _selectedTab = 0;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    // Initialize before build, including for roles that have no finance access.
    _tabs = TabController(length: 8, vsync: this);
    _tabs.addListener(_syncTab);
  }

  void _syncTab() {
    // TabController.index changes at the start of animateTo(). Show the
    // matching content immediately instead of waiting for PageView to settle.
    if (mounted && _selectedTab != _tabs.index) {
      setState(() => _selectedTab = _tabs.index);
    }
  }

  void _changeTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _tabs.index) return;
    _tabs.animateTo(index);
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDistance < -70 || velocity < -350) {
      _changeTab(_tabs.index + 1);
    } else if (_dragDistance > 70 || velocity > 350) {
      _changeTab(_tabs.index - 1);
    }
    _dragDistance = 0;
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
    _tabs.removeListener(_syncTab);
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
            onPressed: () => _changeTab(_tabs.index - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const Key('finance_next_tab'),
            tooltip: 'Next finance tab',
            onPressed: () => _changeTab(_tabs.index + 1),
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragDistance = 0,
        onHorizontalDragUpdate: (details) =>
            _dragDistance += details.primaryDelta ?? 0,
        onHorizontalDragEnd: _handleSwipe,
        child: SizedBox.expand(
          // Build only the selected page. Keeping eight offscreen Finance
          // tabs alive simultaneously caused excessive network subscriptions
          // and could leave TabBar and TabBarView showing different pages.
          child: _buildSelectedTab(),
        ),
      ),
    );
  }
  Widget _buildSelectedTab() {
    switch (_selectedTab) {
      case 0:
        return _FinanceScopeTab(
          key: ValueKey('fee-$_scopeVersion'),
          loader: _load,
          onRetry: _reload,
          builder: (scope) => FinanceFeeSetupTab(
            scope: scope, role: widget.role, repository: _repo),
        );
      case 1:
        return FinanceGenerateTab(repository: _repo);
      case 2:
        return _FinanceScopeTab(
          key: ValueKey('one-time-$_scopeVersion'),
          loader: _load,
          onRetry: _reload,
          builder: (scope) =>
              FinanceOneTimeTab(scope: scope, repository: _repo),
        );
      case 3:
        return FinanceCollectionsTab(repository: _repo);
      case 4:
        return _FinanceScopeTab(
          key: ValueKey('salary-$_scopeVersion'),
          loader: _load,
          onRetry: _reload,
          builder: (scope) =>
              FinanceSalarySetupTab(scope: scope, repository: _repo),
        );
      case 5:
        return FinancePaySalaryTab(
          repository: _repo,
          onSwipePrevious: () => _changeTab(4),
          onSwipeNext: () => _changeTab(6),
        );
      case 6:
        return FinanceExpensesTab(repository: _repo);
      case 7:
        return FinanceAnalyticsTab(repository: _repo);
      default:
        return const FinanceEmpty('Choose a Finance tab.');
    }
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
