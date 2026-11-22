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
  late final TabController _tabs = TabController(length: 8, vsync: this);
  late Future<FinanceScope> _scope = _load();

  bool get _canManage => widget.role == 'owner' || widget.role == 'principal';

  Future<FinanceScope> _load() async {
    if (widget.scopeLoader != null) return widget.scopeLoader!();
    final students = await _repo.loadStudents();
    final classes = await _repo.loadClasses();
    final teachers = await _repo.loadTeachers();
    return FinanceScope(
      classes: classes, students: students, teachers: teachers);
  }

  void _reload() => setState(() => _scope = _load());

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
            tooltip: 'Reload students, classes and staff',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded)),
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
      body: FutureBuilder<FinanceScope>(
        future: _scope,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(schoolErrorMessage(snapshot.error!)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _reload,
                  child: const Text('Retry finance setup')),
              ]),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading finance records…'),
              ],
            ));
          }
          final scope = snapshot.data!;
          return TabBarView(
            controller: _tabs,
            children: [
              FinanceFeeSetupTab(
                scope: scope, role: widget.role, repository: _repo),
              FinanceGenerateTab(repository: _repo),
              FinanceOneTimeTab(scope: scope, repository: _repo),
              FinanceCollectionsTab(repository: _repo),
              FinanceSalarySetupTab(scope: scope, repository: _repo),
              FinancePaySalaryTab(repository: _repo),
              FinanceExpensesTab(repository: _repo),
              FinanceAnalyticsTab(repository: _repo),
            ],
          );
        },
      ),
    );
  }
}
