import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import '../data/staff_repository.dart';
import 'finance_common.dart';
import 'finance_fees_tab.dart';

class FinanceSalarySetupTab extends StatefulWidget {
  const FinanceSalarySetupTab({
    super.key, required this.scope, required this.repository,
  });
  final FinanceScope scope;
  final FinanceRepository repository;
  @override
  State<FinanceSalarySetupTab> createState() => _FinanceSalarySetupTabState();
}

class _FinanceSalarySetupTabState extends State<FinanceSalarySetupTab> {
  late Future<Map<String, Map<String, dynamic>>> _rates =
      widget.repository.loadSalaryRates();

  Future<void> _setup(StaffMember teacher) async {
    Map<String, Map<String, dynamic>> rates;
    try {
      rates = await _rates;
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FinanceSalarySetupDialog(
        teacher: teacher,
        repository: widget.repository,
        rate: rates[teacher.id] ?? const {},
      ),
    );
    if (saved == true && mounted) {
      setState(() { _rates = widget.repository.loadSalaryRates(); });
      financeSnack(context, 'Monthly salary setup saved.');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Teacher salary setup',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Set basic pay, allowance and bonus for each active teacher. '
          'Creating a salary setup does not pay anyone or create a debit. '
          'Generate monthly salaries in Generate Finance.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _rates,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(
              schoolErrorMessage(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          if (widget.scope.teachers.isEmpty) {
            return const FinanceEmpty('Register an active teacher first.');
          }
          return Column(children: [
            for (final teacher in widget.scope.teachers)
              Card(child: ListTile(
                key: Key('salary_setup_${teacher.id}'),
                title: Text(teacher.fullName),
                subtitle: Text(teacher.designation),
                trailing: Text(
                  snapshot.data![teacher.id]?['amountMinor'] is num
                      ? financeMoney((snapshot.data![teacher.id]!['amountMinor'] as num).toInt())
                      : 'Not configured'),
                onTap: () => _setup(teacher),
              )),
          ]);
        },
      ),
    ],
  );
}

class FinancePaySalaryTab extends StatefulWidget {
  const FinancePaySalaryTab({
    super.key,
    required this.repository,
    this.onSwipePrevious,
    this.onSwipeNext,
  });
  final FinanceRepository repository;
  final VoidCallback? onSwipePrevious;
  final VoidCallback? onSwipeNext;
  @override
  State<FinancePaySalaryTab> createState() => _FinancePaySalaryTabState();
}

class _FinancePaySalaryTabState extends State<FinancePaySalaryTab> {
  late Future<List<FinanceBill>> _salaryRequest;
  double _horizontalSwipeDistance = 0;
  String _query = '';
  bool _includePaid = false;

  @override
  void initState() {
    super.initState();
    _salaryRequest = widget.repository.loadSalaryBills();
  }

  @override
  void didUpdateWidget(covariant FinancePaySalaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _salaryRequest = widget.repository.loadSalaryBills();
    }
  }

  void _refreshBills() {
    setState(() {
      _salaryRequest = widget.repository.loadSalaryBills();
    });
  }

  Future<void> _pay(FinanceBill bill) async {
    final receipt = await showDialog<String>(
      context: context,
      builder: (_) => FinancePaymentDialog(
        bill: bill,
        title: 'Pay teacher salary',
        submitLabel: 'Pay salary & record debit',
        onPay: (amount, method, reference, notes, payerName) =>
            widget.repository.paySalary(
              billId: bill.id,
              amountMinor: amount,
              method: method,
              reference: reference,
              notes: notes,
            ),
      ),
    );
    if (receipt != null && mounted) {
      financeSnack(context, 'Salary payment saved. Debit receipt: $receipt');
      _refreshBills();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    // The nested salary list can win gestures over TabBarView. Explicitly
    // handle horizontal drags here so adjacent Finance tabs remain reachable.
    onHorizontalDragStart: (widget.onSwipePrevious != null ||
            widget.onSwipeNext != null)
        ? (_) => _horizontalSwipeDistance = 0
        : null,
    onHorizontalDragUpdate: (widget.onSwipePrevious != null ||
            widget.onSwipeNext != null)
        ? (details) {
            _horizontalSwipeDistance += details.primaryDelta ?? 0;
          }
        : null,
    onHorizontalDragEnd: (widget.onSwipePrevious != null ||
            widget.onSwipeNext != null)
        ? (details) {
            final speed = details.primaryVelocity ?? 0;
            if (_horizontalSwipeDistance > 70 || speed > 350) {
              widget.onSwipePrevious?.call();
            } else if (_horizontalSwipeDistance < -70 || speed < -350) {
              widget.onSwipeNext?.call();
            }
            _horizontalSwipeDistance = 0;
          }
        : null,
    child: ListView(
      key: const Key('salary_pay_scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
    Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Pay monthly salaries',
            style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            key: const Key('finance_refresh_salaries'),
            tooltip: 'Reload generated salary bills',
            onPressed: _refreshBills,
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Only confirmed payments go into the Debit ledger. '
            'Partial salary payment and remaining balances are tracked.',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          key: const Key('salary_bill_search'),
          decoration: const InputDecoration(
            labelText: 'Search teacher, month or salary ID',
            prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        CheckboxListTile(
          dense: true,
          value: _includePaid,
          title: const Text('Show fully paid salaries'),
          onChanged: (v) => setState(() => _includePaid = v ?? false)),
      ]),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Text(
        'Salary records · finance_salary_bills · Server view v3',
        key: const Key('salary_server_view_version'),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
    FutureBuilder<List<FinanceBill>>(
      future: _salaryRequest,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 36),
              const SizedBox(height: 10),
              const Text('Unable to load saved salary bills',
                style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(schoolErrorMessage(snapshot.error!),
                textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Source: finance_salary_bills (Firestore server)',
                style: TextStyle(fontSize: 11)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: const Key('finance_salary_retry'),
                onPressed: _refreshBills,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading salaries'),
              ),
            ]),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Checking saved salaries on Firestore server…'),
            ],
          ));
        }
        final records = snapshot.data!.where((bill) =>
          (_includePaid || !bill.isPaid) &&
          (bill.staffName.toLowerCase().contains(_query) ||
           bill.month.toLowerCase().contains(_query) ||
           bill.id.toLowerCase().contains(_query))).toList();
        if (records.isEmpty) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${snapshot.data!.length} salary bills loaded from Firestore',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_query.isNotEmpty
                    ? 'No salaries match this search. Clear the search or show paid records.'
                    : snapshot.data!.isEmpty
                        ? 'No saved salary bills were returned by the server. '
                            'Check the finance_salary_bills collection and sign-in account.'
                        : 'All fetched salaries are paid or filtered. '
                            'Enable Show fully paid salaries to inspect them.',
                  textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _refreshBills,
                child: const Text('Refresh salary bills'),
              ),
            ],
          ));
        }
        return ListView.builder(
          key: const Key('salary_cards_list'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          itemCount: records.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(
                  '${snapshot.data!.length} saved salaries loaded · '
                  '${records.length} shown',
                  key: const Key('salary_loaded_count'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }
            final bill = records[i - 1];
            return Card(
              key: Key('salary_bill_${bill.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bill.staffName} · ${financeMonthLabel(bill.month)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Basic ${financeMoney(bill.basicMinor)} · '
                      'Allowances ${financeMoney(bill.allowanceMinor)} · '
                      'Bonus ${financeMoney(bill.bonusMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total ${financeMoney(bill.amountMinor)} · '
                      'Paid ${financeMoney(bill.paidMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(child: Text(
                        'Remaining ${financeMoney(bill.remainingMinor)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                      const SizedBox(width: 8),
                      if (bill.isPaid)
                        const Icon(Icons.check_circle_outline, size: 22)
                      else
                        FilledButton(
                          key: Key('finance_pay_salary_${bill.id}'),
                          onPressed: () => _pay(bill),
                          child: const Text('Pay'),
                        ),
                    ]),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  ]),
  );
}

/// The salary form owns its controllers until its dialog route is disposed.
class _FinanceSalarySetupDialog extends StatefulWidget {
  const _FinanceSalarySetupDialog({
    required this.teacher,
    required this.repository,
    required this.rate,
  });
  final StaffMember teacher;
  final FinanceRepository repository;
  final Map<String, dynamic> rate;

  @override
  State<_FinanceSalarySetupDialog> createState() => _FinanceSalarySetupDialogState();
}

class _FinanceSalarySetupDialogState extends State<_FinanceSalarySetupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _basic;
  late final TextEditingController _allowance;
  late final TextEditingController _bonus;
  late final TextEditingController _notes;
  bool _saving = false;

  String _minorText(dynamic amount) {
    final minor = (amount as num?)?.toInt() ?? 0;
    if (minor == 0) return '0';
    return '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _basic = TextEditingController(text: _minorText(widget.rate['basicMinor']));
    _allowance = TextEditingController(text: _minorText(widget.rate['allowanceMinor']));
    _bonus = TextEditingController(text: _minorText(widget.rate['bonusMinor']));
    _notes = TextEditingController(text: (widget.rate['notes'] as String?) ?? '');
  }

  @override
  void dispose() {
    _basic.dispose();
    _allowance.dispose();
    _bonus.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setSalary(
        teacher: widget.teacher,
        basicMinor: financeMinorUnits(_basic.text),
        allowanceMinor: financeOptionalAmount(_allowance.text),
        bonusMinor: financeOptionalAmount(_bonus.text),
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        financeSnack(context, schoolErrorMessage(error));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Salary setup · ${widget.teacher.fullName}'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Define a teacher’s monthly salary. Changes affect only '
            'future generated salary records.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
          FinanceAmountField(controller: _basic, label: 'Basic monthly salary'),
          const SizedBox(height: 12),
          FinanceAmountField(
            controller: _allowance,
            label: 'Monthly allowances',
            optional: true,
          ),
          const SizedBox(height: 12),
          FinanceAmountField(
            controller: _bonus,
            label: 'Monthly bonus',
            optional: true,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Salary structure / notes',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total pay = basic + allowances + bonus',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ]),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save_salary_setup'),
        onPressed: _saving ? null : _apply,
        child: Text(_saving ? 'Saving…' : 'Apply salary'),
      ),
    ],
  );
}
