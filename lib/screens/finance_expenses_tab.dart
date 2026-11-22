import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import 'finance_common.dart';
import 'finance_fees_tab.dart';

class FinanceExpensesTab extends StatefulWidget {
  const FinanceExpensesTab({super.key, required this.repository});
  final FinanceRepository repository;
  @override
  State<FinanceExpensesTab> createState() => _FinanceExpensesTabState();
}

class _FinanceExpensesTabState extends State<FinanceExpensesTab> {
  late Future<List<QueryExpensePlan>> _plans;

  @override
  void initState() {
    super.initState();
    _plans = _fetchPlans();
  }

  void _loadPlans() {
    setState(() { _plans = _fetchPlans(); });
  }

  Future<List<QueryExpensePlan>> _fetchPlans() async {
    final snapshot = await widget.repository.recurringPlans
        .limit(500).get();
    return snapshot.docs.map((doc) => QueryExpensePlan(
      id: doc.id,
      name: (doc.data()['name'] as String?) ?? '',
      category: (doc.data()['category'] as String?) ?? '',
      subcategory: (doc.data()['subcategory'] as String?) ?? '',
      amountMinor: (doc.data()['amountMinor'] as num?)?.toInt() ?? 0,
      day: (doc.data()['scheduleDay'] as num?)?.toInt() ?? 1,
      active: doc.data()['active'] == true,
    )).toList();
  }

  Future<void> _addExpense({required bool monthly}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ExpenseEntryDialog(
        monthly: monthly, repository: widget.repository),
    );
    if (result == null || !mounted) return;
    if (monthly) _loadPlans();
    financeSnack(context, monthly
        ? 'Monthly expense setup saved. Use Generate Finance for a monthly bill.'
        : 'Expense paid and recorded in the Debit ledger. Entry: $result');
  }

  Future<void> _disable(QueryExpensePlan plan) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop recurring expense?'),
        content: Text('Stop future generation for ${plan.name}? '
            'Historical monthly bills and payments will be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop plan')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await widget.repository.disableRecurringExpense(plan.id);
      if (mounted) _loadPlans();
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
    }
  }

  Future<void> _pay(FinanceBill bill) async {
    final receipt = await showDialog<String>(
      context: context,
      builder: (_) => FinancePaymentDialog(
        bill: bill,
        title: 'Pay monthly expense',
        submitLabel: 'Pay expense & record debit',
        onPay: (amount, method, reference, notes, payerName) =>
            widget.repository.payRecurringExpense(
              billId: bill.id, amountMinor: amount,
              method: method, reference: reference, notes: notes),
      ),
    );
    if (receipt != null && mounted) {
      financeSnack(context,
        'Monthly expense payment recorded in Debit. Receipt: $receipt');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 15, 14, 40),
    children: [
      Text('Expenses and recurring bills',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 7),
      const Text('Direct expenses are paid immediately and recorded as '
          'debits. Monthly plans create bills only; pay those bills separately.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: const Text('Record direct expense'),
        subtitle: const Text('WiFi, stationery, lab, fuel, maintenance and more'),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () => _addExpense(monthly: false),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.calendar_month_outlined),
        title: const Text('Monthly expense setup'),
        subtitle: const Text('Rent, regular bills and other monthly obligations'),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () => _addExpense(monthly: true),
      )),
      const SizedBox(height: 14),
      Text('Recurring expense plans',
        style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      FutureBuilder<List<QueryExpensePlan>>(
        future: _plans,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(schoolErrorMessage(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          final plans = snapshot.data!.where((e) => e.active).toList();
          if (plans.isEmpty) {
            return const Text('No monthly expense plans configured.',
              style: TextStyle(fontSize: 12));
          }
          return Column(children: [
            for (final plan in plans)
              Card(child: ListTile(
                title: Text(plan.name),
                subtitle: Text(
                  '${plan.category} / ${plan.subcategory} · '
                  'Generation day ${plan.day}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (_) => _disable(plan),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'disable',
                      child: Text('Stop future charges')),
                  ],
                ),
                leading: Text(financeMoney(plan.amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
          ]);
        },
      ),
      const SizedBox(height: 12),
      Text('Generated monthly expense bills',
        style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      StreamBuilder<List<FinanceBill>>(
        stream: widget.repository.watchRecurringBills(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(schoolErrorMessage(snapshot.error!));
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final due = snapshot.data!.where((b) => !b.isPaid).toList();
          if (due.isEmpty) {
            return const Text('No unpaid recurring bills. Generate monthly '
                'expenses in the Generate Finance tab.',
              style: TextStyle(fontSize: 12));
          }
          return Column(children: [
            for (final bill in due)
              Card(child: ListTile(
                title: Text(bill.title),
                subtitle: Text('${financeMonthLabel(bill.month)} · '
                    'Total ${financeMoney(bill.amountMinor)} · '
                    'Paid ${financeMoney(bill.paidMinor)}'),
                trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(financeMoney(bill.remainingMinor),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton(onPressed: () => _pay(bill),
                    child: const Text('Pay')),
                ]),
              )),
          ]);
        },
      ),
      const SizedBox(height: 14),
      const Text('Automatic generation is not active yet. The planned day '
          '(1–27) is saved for future Firebase Functions scheduling; '
          'until billing is configured, run Generate Finance manually.',
        style: TextStyle(fontSize: 11)),
    ],
  );
}

class QueryExpensePlan {
  const QueryExpensePlan({
    required this.id, required this.name, required this.category,
    required this.subcategory, required this.amountMinor,
    required this.day, required this.active,
  });
  final String id;
  final String name;
  final String category;
  final String subcategory;
  final int amountMinor;
  final int day;
  final bool active;
}

class _ExpenseEntryDialog extends StatefulWidget {
  const _ExpenseEntryDialog({
    required this.monthly,
    required this.repository,
  });
  final bool monthly;
  final FinanceRepository repository;

  @override
  State<_ExpenseEntryDialog> createState() => _ExpenseEntryDialogState();
}

class _ExpenseEntryDialogState extends State<_ExpenseEntryDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  String _category = financeExpenseCategories.keys.first;
  late String _subcategory = financeExpenseCategories[_category]!.first;
  String _method = financePaymentMethods.first;
  int _day = 1;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final amount = financeMinorUnits(_amount.text);
      final id = widget.monthly
          ? await widget.repository.setRecurringExpense(
              name: _name.text,
              category: _category,
              subcategory: _subcategory,
              description: _description.text,
              amountMinor: amount,
              scheduleDay: _day,
            )
          : await widget.repository.recordExpense(
              category: _category,
              subcategory: _subcategory,
              description: _description.text,
              amountMinor: amount,
              method: _method,
              reference: _reference.text,
            );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        financeSnack(context, schoolErrorMessage(error));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.monthly
        ? 'Monthly expense setup' : 'Record expense payment'),
    content: SizedBox(width: 450, child: Form(
      key: _form, child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.monthly) ...[
            TextFormField(
              key: const Key('expense_plan_name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Monthly expense name (e.g. Building rent)'),
              validator: (v) => v?.trim().isEmpty == true
                  ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            key: const Key('expense_category'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Expense category'),
            isExpanded: true,
            items: [
              for (final category in financeExpenseCategories.keys)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: _busy ? null : (value) {
              if (value == null) return;
              setState(() {
                _category = value;
                _subcategory = financeExpenseCategories[value]!.first;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_category),
            initialValue: _subcategory,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Subcategory'),
            items: [
              for (final part in financeExpenseCategories[_category]!)
                DropdownMenuItem(value: part, child: Text(part)),
            ],
            onChanged: _busy ? null : (v) {
              if (v != null) setState(() => _subcategory = v);
            },
          ),
          const SizedBox(height: 12),
          FinanceAmountField(controller: _amount,
            label: widget.monthly ? 'Monthly expense amount' : 'Amount paid'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description / notes'),
            validator: (v) => _subcategory == 'Other' &&
                    (v == null || v.trim().isEmpty)
                ? 'Enter a description for Other.' : null,
          ),
          if (widget.monthly) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _day,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Planned monthly generation day'),
              items: [
                for (var day = 1; day <= 27; day++)
                  DropdownMenuItem(value: day, child: Text('Day $day')),
              ],
              onChanged: (v) => setState(() => _day = v ?? 1),
            ),
            const SizedBox(height: 8),
            const Text('Day is saved as a schedule preference only. '
                'Automatic execution needs a future backend worker.',
              style: TextStyle(fontSize: 11)),
          ] else ...[
            const SizedBox(height: 12),
            FinanceMethodSelector(value: _method,
                onChanged: (v) => setState(() => _method = v)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Payment reference (optional)')),
            const SizedBox(height: 8),
            const Text('A direct expense creates an immutable Debit '
                'entry with receipt ID, date, time and operator.',
              style: TextStyle(fontSize: 11)),
          ],
        ],
      ),
    )),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel')),
      FilledButton(
        key: const Key('finance_submit_expense'),
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Saving…'
            : widget.monthly ? 'Save monthly plan' : 'Record debit')),
    ],
  );
}
