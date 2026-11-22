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
    final current = await _rates;
    if (!mounted) return;
    final data = current[teacher.id] ?? <String, dynamic>{};
    final key = GlobalKey<FormState>();
    String textMinor(dynamic amount) {
      final x = (amount as num?)?.toInt() ?? 0;
      if (x == 0) return '0';
      return '${x ~/ 100}.${(x % 100).toString().padLeft(2, '0')}';
    }
    final basic = TextEditingController(text: textMinor(data['basicMinor']));
    final allowance = TextEditingController(text: textMinor(data['allowanceMinor']));
    final bonus = TextEditingController(text: textMinor(data['bonusMinor']));
    final notes = TextEditingController(text: (data['notes'] as String?) ?? '');
    var busy = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text('Salary setup · ${teacher.fullName}'),
          content: SizedBox(width: 420, child: Form(
            key: key, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Define a teacher’s monthly salary. Changes affect '
                    'only future generated salary records.',
                  style: TextStyle(fontSize: 12)),
                const SizedBox(height: 14),
                FinanceAmountField(
                  controller: basic, label: 'Basic monthly salary'),
                const SizedBox(height: 12),
                FinanceAmountField(
                  controller: allowance, label: 'Monthly allowances',
                  optional: true),
                const SizedBox(height: 12),
                FinanceAmountField(
                  controller: bonus, label: 'Monthly bonus',
                  optional: true),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes, maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Salary structure / notes')),
                const SizedBox(height: 10),
                Text('Total pay = basic + allowances + bonus',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          )),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
            FilledButton(
              key: const Key('save_salary_setup'),
              onPressed: busy ? null : () async {
                if (!key.currentState!.validate()) return;
                update(() => busy = true);
                try {
                  await widget.repository.setSalary(
                    teacher: teacher,
                    basicMinor: financeMinorUnits(basic.text),
                    allowanceMinor: financeOptionalAmount(allowance.text),
                    bonusMinor: financeOptionalAmount(bonus.text),
                    notes: notes.text);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (error) {
                  if (context.mounted) {
                    financeSnack(context, schoolErrorMessage(error));
                    update(() => busy = false);
                  }
                }
              },
              child: Text(busy ? 'Saving…' : 'Apply salary')),
          ],
        ),
      ),
    );
    basic.dispose();
    allowance.dispose();
    bonus.dispose();
    notes.dispose();
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
  const FinancePaySalaryTab({super.key, required this.repository});
  final FinanceRepository repository;
  @override
  State<FinancePaySalaryTab> createState() => _FinancePaySalaryTabState();
}

class _FinancePaySalaryTabState extends State<FinancePaySalaryTab> {
  String _query = '';
  bool _includePaid = false;

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
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Text('Pay monthly salaries',
          style: Theme.of(context).textTheme.titleMedium),
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
    Expanded(child: StreamBuilder<List<FinanceBill>>(
      stream: widget.repository.watchSalaryBills(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FinanceEmpty(schoolErrorMessage(snapshot.error!));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data!.where((bill) =>
          (_includePaid || !bill.isPaid) &&
          (bill.staffName.toLowerCase().contains(_query) ||
           bill.month.toLowerCase().contains(_query) ||
           bill.id.toLowerCase().contains(_query))).toList();
        if (records.isEmpty) {
          return const FinanceEmpty('No matching monthly salaries. '
              'Configure salary first, then use Generate Finance.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          itemCount: records.length,
          itemBuilder: (context, i) {
            final bill = records[i];
            return Card(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                key: Key('salary_bill_${bill.id}'),
                title: Text('${bill.staffName} · ${financeMonthLabel(bill.month)}'),
                subtitle: Text(
                  'Basic ${financeMoney(bill.basicMinor)} · '
                  'Allowances ${financeMoney(bill.allowanceMinor)} · '
                  'Bonus ${financeMoney(bill.bonusMinor)}\n'
                  'Total ${financeMoney(bill.amountMinor)} · '
                  'Paid ${financeMoney(bill.paidMinor)}\n'
                  'Remaining ${financeMoney(bill.remainingMinor)}'),
                isThreeLine: true,
                trailing: bill.isPaid
                    ? const Icon(Icons.check_circle_outline)
                    : FilledButton(
                        onPressed: () => _pay(bill),
                        child: const Text('Pay')),
              ),
            ));
          },
        );
      },
    )),
  ]);
}
