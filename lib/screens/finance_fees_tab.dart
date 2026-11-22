import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import 'finance_common.dart';

class FinanceFeeSetupTab extends StatefulWidget {
  const FinanceFeeSetupTab({
    super.key,
    required this.scope,
    required this.role,
    required this.repository,
  });
  final FinanceScope scope;
  final String role;
  final FinanceRepository repository;
  @override
  State<FinanceFeeSetupTab> createState() => _FinanceFeeSetupTabState();
}

class _FinanceFeeSetupTabState extends State<FinanceFeeSetupTab> {
  late Future<List<Map<String, Map<String, dynamic>>>> _rates = _load();

  Future<List<Map<String, Map<String, dynamic>>>> _load() => Future.wait([
    widget.repository.loadTuitionRates(),
    widget.repository.loadTransportRates(),
  ]);

  Future<void> _tuitionDialog() async {
    if (widget.scope.classes.isEmpty) {
      financeSnack(context, 'Create a class first.');
      return;
    }
    Map<String, Map<String, dynamic>> currentRates;
    try {
      currentRates = (await _rates)[0];
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FinanceTuitionDialog(
        scope: widget.scope,
        repository: widget.repository,
        rates: currentRates,
      ),
    );
    if (saved == true && mounted) {
      setState(() { _rates = _load(); });
      financeSnack(context, 'Monthly tuition rate saved for the class.');
    }
  }

  Future<void> _transportDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FinanceTransportDialog(
        scope: widget.scope,
        repository: widget.repository,
      ),
    );
    if (saved == true && mounted) {
      setState(() { _rates = _load(); });
      financeSnack(context, 'Individual transport rates saved.');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Monthly fee setup', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Setting a fee does not create a bill, credit or debit. '
          'Monthly bills are created separately in Generate Finance.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
        title: const Text('Tuition fee setup'),
        subtitle: Text(widget.role == 'owner'
            ? 'Fixed monthly rate per class. Only owner can edit.'
            : 'View fixed tuition rates. Only the owner can change them.'),
        trailing: widget.role == 'owner'
            ? const Icon(Icons.edit_outlined) : const Icon(Icons.lock_outline),
        onTap: widget.role == 'owner' ? _tuitionDialog : null,
      )),
      Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.directions_bus_outlined)),
        title: const Text('Transport fee setup'),
        subtitle: const Text('Personal amount for single or multiple students'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: _transportDialog,
      )),
      const SizedBox(height: 15),
      FutureBuilder<List<Map<String, Map<String, dynamic>>>>(
        future: _rates,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(
              schoolErrorMessage(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final tuition = snapshot.data![0];
          final transport = snapshot.data![1];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Class tuition rates', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final item in widget.scope.classes)
              Card(child: ListTile(
                dense: true,
                title: Text(item.label),
                trailing: Text(
                  tuition[item.id]?['amountMinor'] is num
                      ? financeMoney((tuition[item.id]!['amountMinor'] as num).toInt())
                      : 'Not set',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            const SizedBox(height: 14),
            Text('Transport rates configured: ${transport.values.where((d) => d['active'] == true).length} students',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          ]);
        },
      ),
    ],
  );
}

class FinanceGenerateTab extends StatefulWidget {
  const FinanceGenerateTab({
    super.key, required this.repository,
  });
  final FinanceRepository repository;
  @override
  State<FinanceGenerateTab> createState() => _FinanceGenerateTabState();
}

class _FinanceGenerateTabState extends State<FinanceGenerateTab> {
  String _month = financeMonth(DateTime.now());
  bool _tuition = true;
  bool _transport = false;
  bool _salary = false;
  bool _recurringExpenses = false;
  bool _busy = false;
  String? _result;

  Future<void> _editGenerationDay() async {
    Map<String, int> prior;
    try {
      prior = await widget.repository.loadGenerationDays();
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
      return;
    }
    if (!mounted) return;
    var category = 'tuition';
    var day = prior[category] ?? 1;
    var busy = false;
    final success = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('Monthly generation day preference'),
          content: SizedBox(width: 390, child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Save the preferred day (1–27). This does not '
                  'automatically generate fees or salaries yet. '
                  'Firebase scheduled Functions require Blaze billing.',
                style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Finance type'),
                items: const [
                  DropdownMenuItem(value: 'tuition', child: Text('Tuition fees')),
                  DropdownMenuItem(value: 'transport', child: Text('Transport fees')),
                  DropdownMenuItem(value: 'salary', child: Text('Teacher salaries')),
                ],
                onChanged: busy ? null : (v) {
                  if (v != null) update(() {
                    category = v;
                    day = prior[v] ?? 1;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(category),
                initialValue: day,
                decoration: const InputDecoration(
                  labelText: 'Preferred generation date'),
                items: [
                  for (var n = 1; n <= 27; n++)
                    DropdownMenuItem(value: n, child: Text('Day $n')),
                ],
                onChanged: busy ? null : (v) {
                  if (v != null) update(() => day = v);
                },
              ),
            ],
          )),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: busy ? null : () async {
                update(() => busy = true);
                try {
                  await widget.repository.saveGenerationDay(
                    category: category, scheduleDay: day);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (error) {
                  if (context.mounted) {
                    financeSnack(context, schoolErrorMessage(error));
                    update(() => busy = false);
                  }
                }
              },
              child: Text(busy ? 'Saving…' : 'Save preference')),
          ],
        ),
      ),
    );
    if (success == true && mounted) {
      financeSnack(context, 'Preferred generation day saved. '
          'Automatic execution is still disabled.');
    }
  }

  Future<void> _generate() async {
    if (!_tuition && !_transport && !_salary && !_recurringExpenses) {
      financeSnack(context, 'Select at least one finance type.');
      return;
    }
    setState(() { _busy = true; _result = null; });
    try {
      final output = <String>[];
      if (_tuition || _transport) {
        final r = await widget.repository.generateFees(
          month: _month, tuition: _tuition, transport: _transport);
        output.add('Student fees: ${r.created} new, ${r.existing} existing, '
            '${r.missingSetup} with no applicable rate.');
      }
      if (_salary) {
        final r = await widget.repository.generateSalaries(_month);
        output.add('Teacher salaries: ${r.created} new, '
            '${r.existing} existing, ${r.missingSetup} missing salary setup.');
      }
      if (_recurringExpenses) {
        final r = await widget.repository.generateRecurringExpenses(_month);
        output.add('Recurring expenses: ${r.created} new, '
            '${r.existing} existing.');
      }
      if (mounted) setState(() => _result = output.join('\n'));
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Generate monthly finance', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('Choose the current or previous month. Generating fees, '
          'salaries and recurring expenses creates outstanding records only. '
          'It never adds money to credit or debit.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      FinanceMonthSelector(value: _month, onChanged: (s) =>
          setState(() => _month = s)),
      const SizedBox(height: 12),
      CheckboxListTile(
        key: const Key('generate_tuition'),
        value: _tuition,
        title: const Text('Monthly tuition fees'),
        subtitle: const Text('All active, admitted students with a class rate'),
        onChanged: _busy ? null : (v) => setState(() => _tuition = v ?? false)),
      CheckboxListTile(
        key: const Key('generate_transport'),
        value: _transport,
        title: const Text('Monthly transport fees'),
        subtitle: const Text('Only students with an individual transport rate'),
        onChanged: _busy ? null : (v) => setState(() => _transport = v ?? false)),
      CheckboxListTile(
        key: const Key('generate_salaries'),
        value: _salary,
        title: const Text('Monthly teacher salaries'),
        subtitle: const Text('All active teachers with salary setup'),
        onChanged: _busy ? null : (v) => setState(() => _salary = v ?? false)),
      CheckboxListTile(
        key: const Key('generate_recurring_expenses'),
        value: _recurringExpenses,
        title: const Text('Monthly recurring expenses'),
        subtitle: const Text('Active rent, WiFi and other monthly plans'),
        onChanged: _busy ? null : (v) => setState(() =>
            _recurringExpenses = v ?? false)),
      const SizedBox(height: 18),
      FilledButton.icon(
        key: const Key('generate_finance_button'),
        onPressed: _busy ? null : _generate,
        icon: const Icon(Icons.event_repeat_outlined),
        label: Text(_busy ? 'Generating finance…' : 'Generate Finance'),
      ),
      if (_result != null) Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_result!))),
      const SizedBox(height: 16),
      Card(child: ListTile(
        leading: const Icon(Icons.edit_calendar_outlined),
        title: const Text('Monthly schedule preferences'),
        subtitle: const Text('Set a day from 1 to 27 for fees and salaries '
            '(automatic execution not yet active)'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _editGenerationDay,
      )),
      const SizedBox(height: 8),
      const Text('Automatic backend scheduling is not enabled. '
          'The saved monthly expense schedule dates are for a future '
          'Firebase Functions integration after billing is configured.',
        style: TextStyle(fontSize: 11)),
    ],
  );
}

class FinanceOneTimeTab extends StatefulWidget {
  const FinanceOneTimeTab({
    super.key, required this.scope, required this.repository,
  });
  final FinanceScope scope;
  final FinanceRepository repository;
  @override
  State<FinanceOneTimeTab> createState() => _FinanceOneTimeTabState();
}

class _FinanceOneTimeTabState extends State<FinanceOneTimeTab> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _category = financeOneTimeCategories.first;
  List<StudentRecord> _selected = [];
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_selected.isEmpty) {
      financeSnack(context, 'Select one or more students.');
      return;
    }
    setState(() => _busy = true);
    try {
      final count = await widget.repository.createOneTimeFees(
        category: _category, description: _description.text,
        amountMinor: financeMinorUnits(_amount.text),
        students: _selected, classes: widget.scope.classesById);
      if (!mounted) return;
      financeSnack(context, '$count one-time fee bills added. '
          'No credit has been recorded; collect payment in Collections.');
      setState(() => _selected = []);
      _amount.clear();
      _description.clear();
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('One-time student fees', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Assign a fee to one student, a class, selected students '
          'or all students. It becomes an outstanding fee until collected.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 15),
      Form(key: _form, child: Column(children: [
        DropdownButtonFormField<String>(
          key: const Key('one_time_category'),
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fee category'),
          items: [
            for (final item in financeOneTimeCategories)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: _busy ? null : (v) {
            if (v != null) setState(() => _category = v);
          }),
        const SizedBox(height: 12),
        FinanceAmountField(controller: _amount, label: 'Amount per student'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: _category == 'Other'
                ? 'Description (required)' : 'Description / notes'),
          validator: (v) => _category == 'Other' && (v?.trim().isEmpty ?? true)
              ? 'Enter a description for Other.' : null,
        ),
      ])),
      const SizedBox(height: 15),
      OutlinedButton.icon(
        key: const Key('one_time_pick_students'),
        onPressed: _busy ? null : () async {
          final picked = await pickFinanceStudents(context, widget.scope);
          if (picked != null) setState(() => _selected = picked);
        },
        icon: const Icon(Icons.people_outline),
        label: Text(_selected.isEmpty
            ? 'Select student(s)' : '${_selected.length} students selected'),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('one_time_create'),
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.post_add_outlined),
        label: Text(_busy ? 'Creating bills…' : 'Apply one-time fee'),
      ),
    ],
  );
}

class FinanceCollectionsTab extends StatefulWidget {
  const FinanceCollectionsTab({super.key, required this.repository});
  final FinanceRepository repository;
  @override
  State<FinanceCollectionsTab> createState() => _FinanceCollectionsTabState();
}

class _FinanceCollectionsTabState extends State<FinanceCollectionsTab> {
  late Stream<List<FinanceBill>> _feeStream;
  String _type = 'all';
  String _subcategory = 'all';
  String _search = '';
  bool _showPaid = false;

  @override
  void initState() {
    super.initState();
    _feeStream = widget.repository.watchFeeBills();
  }

  @override
  void didUpdateWidget(covariant FinanceCollectionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _feeStream = widget.repository.watchFeeBills();
    }
  }

  Future<void> _collect(FinanceBill bill) async {
    final receipt = await showDialog<String>(
      context: context,
      builder: (_) => FinancePaymentDialog(
        bill: bill,
        title: 'Collect student fee',
        submitLabel: 'Collect & record credit',
        onPay: (amount, method, reference, notes, payerName) =>
            widget.repository.collectFee(
              billId: bill.id,
              amountMinor: amount,
              method: method,
              reference: reference,
              notes: notes,
              payerName: payerName,
            ),
      ),
    );
    if (receipt != null && mounted) {
      financeSnack(context,
          'Fee received. Credit receipt: $receipt');
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(14), child: Column(children: [
      Text('Student fee collections',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 5),
      const Text('Only an actual payment creates a credit transaction. '
          'Partial collections are supported.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _type, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Collection type'),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('All fee categories')),
          DropdownMenuItem(value: 'tuition', child: Text('Tuition')),
          DropdownMenuItem(value: 'transport', child: Text('Transport')),
          DropdownMenuItem(value: 'one_time', child: Text('One-time fees')),
        ],
        onChanged: (v) => setState(() {
          _type = v ?? 'all';
          _subcategory = 'all';
        }),
      ),
      if (_type == 'one_time') ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _subcategory,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'One-time category'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All one-time categories')),
            for (final category in financeOneTimeCategories)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
          onChanged: (v) => setState(() => _subcategory = v ?? 'all'),
        ),
      ],
      const SizedBox(height: 8),
      TextField(
        key: const Key('finance_collections_search'),
        decoration: const InputDecoration(
          labelText: 'Search student, admission, class or fee',
          prefixIcon: Icon(Icons.search_outlined)),
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
      ),
      CheckboxListTile(
        dense: true, value: _showPaid,
        title: const Text('Include fully paid fees'),
        onChanged: (v) => setState(() => _showPaid = v ?? false),
      ),
    ])),
    Expanded(child: StreamBuilder<List<FinanceBill>>(
      stream: _feeStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return FinanceEmpty(schoolErrorMessage(snapshot.error!));
        if (!snapshot.hasData) {
          return const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Loading generated student fee bills…'),
            ],
          ));
        }
        final bills = snapshot.data!.where((bill) =>
          (_type == 'all' || bill.category == _type) &&
          (_subcategory == 'all' || bill.subcategory == _subcategory) &&
          (_showPaid || !bill.isPaid) &&
          (bill.studentName.toLowerCase().contains(_search) ||
            bill.studentId.toLowerCase().contains(_search) ||
            bill.className.toLowerCase().contains(_search) ||
            bill.title.toLowerCase().contains(_search)))
          .toList();
        if (bills.isEmpty) {
          return const FinanceEmpty('No matching fee bills. '
              'Generate monthly fees or apply a one-time fee first.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          itemCount: bills.length,
          itemBuilder: (context, i) {
            final bill = bills[i];
            return Card(
              key: Key('finance_bill_${bill.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(
                          '${bill.studentName} · ${bill.title}',
                          style: Theme.of(context).textTheme.titleSmall,
                        )),
                        const SizedBox(width: 8),
                        Text(
                          financeMoney(bill.remainingMinor),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${bill.className} · ${financeMonthLabel(bill.month)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Due ${financeMoney(bill.amountMinor)} · '
                            'Paid ${financeMoney(bill.paidMinor)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (bill.isPaid)
                          const Icon(Icons.check_circle_outline, size: 22)
                        else
                          TextButton(
                            key: Key('finance_collect_${bill.id}'),
                            onPressed: () => _collect(bill),
                            child: const Text('Collect'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    )),
  ]);
}

typedef FinancePayAction = Future<String> Function(
  int amountMinor, String method, String reference,
  String notes, String payerName);

class FinancePaymentDialog extends StatefulWidget {
  const FinancePaymentDialog({
    super.key,
    required this.bill,
    required this.title,
    required this.submitLabel,
    required this.onPay,
  });
  final FinanceBill bill;
  final String title;
  final String submitLabel;
  final FinancePayAction onPay;

  @override
  State<FinancePaymentDialog> createState() => _FinancePaymentDialogState();
}

class _FinancePaymentDialogState extends State<FinancePaymentDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: '${widget.bill.remainingMinor ~/ 100}.${(widget.bill.remainingMinor % 100).toString().padLeft(2, '0')}');
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late final _payerName =
      TextEditingController(text: widget.bill.studentName);
  String _method = 'Cash';
  bool _busy = false;
  int? _entered;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    _payerName.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (!_form.currentState!.validate()) return;
    final amount = financeMinorUnits(_amount.text);
    if (amount > widget.bill.remainingMinor) {
      financeSnack(context, 'Amount exceeds outstanding balance.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await widget.onPay(
        amount, _method, _reference.text, _notes.text, _payerName.text);
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) financeSnack(context, schoolErrorMessage(error));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remains = _entered == null
        ? widget.bill.remainingMinor
        : widget.bill.remainingMinor - _entered!;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(width: 430, child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.bill.studentName.isNotEmpty
              ? widget.bill.studentName
              : widget.bill.staffName.isNotEmpty
                  ? widget.bill.staffName : widget.bill.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text('Bill: ${widget.bill.id}', style: const TextStyle(fontSize: 11)),
          Text('Total: ${financeMoney(widget.bill.amountMinor)}'),
          Text('Already paid: ${financeMoney(widget.bill.paidMinor)}'),
          Text('Outstanding: ${financeMoney(widget.bill.remainingMinor)}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('finance_payment_amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount being paid', prefixText: 'Rs '),
            validator: (v) {
              final error = financeValidateAmount(v);
              if (error != null) return error;
              if (financeMinorUnits(v!) > widget.bill.remainingMinor) {
                return 'Payment exceeds remaining balance.';
              }
              return null;
            },
            onChanged: (v) => setState(() {
              try { _entered = financeMinorUnits(v); }
              catch (_) { _entered = null; }
            }),
          ),
          const SizedBox(height: 8),
          Text('Remains after payment: ${financeMoney(remains > 0 ? remains : 0)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          if (widget.bill.studentId.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('finance_payer_name'),
              controller: _payerName,
              decoration: const InputDecoration(
                labelText: 'Payer / guardian name'),
              validator: (v) => v?.trim().isEmpty == true
                  ? 'Enter who paid the fee.' : null,
            ),
          ],
          const SizedBox(height: 12),
          FinanceMethodSelector(value: _method,
              onChanged: (v) => setState(() => _method = v)),
          const SizedBox(height: 12),
          TextFormField(controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Bank/reference number (optional)')),
          const SizedBox(height: 10),
          TextFormField(controller: _notes, maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Payment notes (optional)')),
          const SizedBox(height: 10),
          const Text('Payment date, time, receipt ID, operator and ledger '
              'entry are generated automatically.',
            style: TextStyle(fontSize: 11)),
        ]),
      )),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel')),
        FilledButton(
          key: const Key('finance_confirm_payment'),
          onPressed: _busy ? null : _pay,
          child: Text(_busy ? 'Recording…' : widget.submitLabel)),
      ],
    );
  }
}

/// Dialog widgets own their controllers for the entire Navigator route lifetime.
/// Disposing a controller immediately after showDialog completes is too early:
/// Flutter still animates and unmounts the departing dialog after pop().
class _FinanceTuitionDialog extends StatefulWidget {
  const _FinanceTuitionDialog({
    required this.scope,
    required this.repository,
    required this.rates,
  });

  final FinanceScope scope;
  final FinanceRepository repository;
  final Map<String, Map<String, dynamic>> rates;

  @override
  State<_FinanceTuitionDialog> createState() => _FinanceTuitionDialogState();
}

class _FinanceTuitionDialogState extends State<_FinanceTuitionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String _classId = widget.scope.classes.first.id;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fillClassRate();
  }

  void _fillClassRate() {
    final minor = (widget.rates[_classId]?['amountMinor'] as num?)?.toInt();
    _amount.text = minor == null ? '' :
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setTuition(
        schoolClass: widget.scope.classes.firstWhere((c) => c.id == _classId),
        amountMinor: financeMinorUnits(_amount.text),
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
    title: const Text('Monthly tuition fee setup'),
    content: SizedBox(
      width: 450,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tuition is fixed per class. Only the owner may change the '
              'class rate. New rates apply to future generation; '
              'previously generated bills are not altered.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              key: const Key('finance_tuition_class'),
              initialValue: _classId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Class / section'),
              items: [
                for (final c in widget.scope.classes)
                  DropdownMenuItem(value: c.id, child: Text(c.label)),
              ],
              onChanged: _saving ? null : (value) {
                if (value == null) return;
                setState(() {
                  _classId = value;
                  _fillClassRate();
                });
              },
            ),
            const SizedBox(height: 14),
            FinanceAmountField(
              controller: _amount, label: 'Fixed tuition per month'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save_tuition_rate'),
        onPressed: _saving ? null : _apply,
        child: Text(_saving ? 'Saving…' : 'Apply tuition'),
      ),
    ],
  );
}

class _FinanceTransportDialog extends StatefulWidget {
  const _FinanceTransportDialog({
    required this.scope,
    required this.repository,
  });
  final FinanceScope scope;
  final FinanceRepository repository;

  @override
  State<_FinanceTransportDialog> createState() => _FinanceTransportDialogState();
}

class _FinanceTransportDialogState extends State<_FinanceTransportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  List<StudentRecord> _selected = [];
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickStudents() async {
    final selection = await pickFinanceStudents(context, widget.scope);
    if (mounted && selection != null) {
      setState(() => _selected = selection);
    }
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (_selected.isEmpty) {
      financeSnack(context, 'Select at least one student.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.setTransport(
        students: _selected,
        classes: widget.scope.classesById,
        amountMinor: financeOptionalAmount(_amount.text),
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
    title: const Text('Monthly transport fee setup'),
    content: SizedBox(
      width: 450,
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Each student may have a different transport fee. Select one, '
            'several, a class or every student. The amount applies only to '
            'the chosen students.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            key: const Key('select_transport_students'),
            onPressed: _saving ? null : _pickStudents,
            icon: const Icon(Icons.groups_outlined),
            label: Text(_selected.isEmpty
              ? 'Choose students'
              : '${_selected.length} students selected'),
          ),
          const SizedBox(height: 14),
          FinanceAmountField(
            controller: _amount,
            label: 'Individual monthly transport fee',
            optional: true,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter 0 to stop future monthly transport charges for the '
            'selected students. Existing generated bills remain unchanged.',
            style: TextStyle(fontSize: 11),
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
        key: const Key('save_transport_rates'),
        onPressed: _saving ? null : _apply,
        child: Text(_saving ? 'Applying…' : 'Apply transport fee'),
      ),
    ],
  );
}
