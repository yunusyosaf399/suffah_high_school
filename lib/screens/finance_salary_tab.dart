import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import '../data/school_user_service.dart' show schoolOwnerUid;
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

/// Every stage of the server read is held in explicit State, not inside a
/// nested FutureBuilder or ListView. The status row is always rendered,
/// even when Firestore hangs, denies access, or returns an empty result.
class _FinancePaySalaryTabState extends State<FinancePaySalaryTab> {
  List<FinanceBill> _bills = const [];
  Object? _readError;
  bool _loading = true;
  int _requestNumber = 0;
  double _horizontalSwipeDistance = 0;
  String _query = '';
  bool _includePaid = false;

  @override
  void initState() {
    super.initState();
    _loadBills(initial: true);
  }

  @override
  void didUpdateWidget(covariant FinancePaySalaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _loadBills();
    }
  }

  @override
  void dispose() {
    _requestNumber++;
    super.dispose();
  }

  Future<void> _loadBills({bool initial = false}) async {
    final request = ++_requestNumber;
    if (!initial && mounted) {
      setState(() {
        _loading = true;
        _readError = null;
      });
    }
    try {
      final fetched = await widget.repository.loadSalaryBills()
          .timeout(const Duration(seconds: 24));
      if (!mounted || request != _requestNumber) return;
      setState(() {
        _bills = fetched;
        _readError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _requestNumber) return;
      setState(() {
        _readError = error;
        _loading = false;
      });
    }
  }

  String _connectionDetails() {
    try {
      final projectId = Firebase.app().options.projectId;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final account = uid == null
          ? 'signed out'
          : uid == schoolOwnerUid
              ? 'registered owner account'
              : 'UID …${uid.substring(uid.length > 5 ? uid.length - 5 : 0)}';
      return 'Project: $projectId · account: $account';
    } catch (_) {
      return 'Project/account details unavailable in this environment';
    }
  }

  String _failureDetails(Object error) {
    if (error is FirebaseException) {
      return 'Firestore code: ${error.code}\n${schoolErrorMessage(error)}';
    }
    if (error is TimeoutException) {
      return 'Request timeout\n${schoolErrorMessage(error)}';
    }
    return '${error.runtimeType}\n${schoolErrorMessage(error)}';
  }

  Future<void> _probeSalaryDocument() async {
    var billId = 'SAL-202611-EMP-2026-0001';
    String? result;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          scrollable: true,
          title: const Text('Check a saved salary document'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'This performs a read-only Firestore GET on one bill. '
                'It does not generate, edit, or pay any salary.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('salary_probe_document_id'),
                initialValue: billId,
                decoration: const InputDecoration(
                  labelText: 'Exact salary bill document ID',
                ),
                onChanged: (value) => billId = value,
              ),
              if (result != null) ...[
                const SizedBox(height: 14),
                SelectableText(
                  result!,
                  key: const Key('salary_probe_result'),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const Key('salary_probe_read'),
              onPressed: busy ? null : () async {
                updateDialog(() {
                  busy = true;
                  result = 'Checking document on Firestore server…';
                });
                try {
                  final bill = await widget.repository.probeSalaryBill(billId);
                  if (!dialogContext.mounted) return;
                  updateDialog(() {
                    result = bill == null
                        ? 'Document GET succeeded, but this ID does not exist. '
                          'Verify the document ID and Firebase project.'
                        : 'Document GET succeeded.\n'
                          'Teacher: ${bill.staffName}\n'
                          'Month: ${bill.month}\n'
                          'Outstanding: ${financeMoney(bill.remainingMinor)}\n'
                          'If the main list is empty, the collection LIST '
                          'and the direct GET are behaving differently.';
                    busy = false;
                  });
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  updateDialog(() {
                    result = 'Document GET failed: '
                        '${schoolErrorMessage(error)} '
                        '(type: ${error.runtimeType})';
                    busy = false;
                  });
                }
              },
              icon: const Icon(Icons.manage_search),
              label: const Text('Check document'),
            ),
          ],
        ),
      ),
    );
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
      await _loadBills();
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _bills.where((bill) =>
      (_includePaid || !bill.isPaid) &&
      (bill.staffName.toLowerCase().contains(_query) ||
       bill.month.toLowerCase().contains(_query) ||
       bill.id.toLowerCase().contains(_query))
    ).toList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart:
          (widget.onSwipePrevious != null || widget.onSwipeNext != null)
              ? (_) => _horizontalSwipeDistance = 0
              : null,
      onHorizontalDragUpdate:
          (widget.onSwipePrevious != null || widget.onSwipeNext != null)
              ? (details) {
                  _horizontalSwipeDistance += details.primaryDelta ?? 0;
                }
              : null,
      onHorizontalDragEnd:
          (widget.onSwipePrevious != null || widget.onSwipeNext != null)
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
      child: RefreshIndicator(
        onRefresh: _loadBills,
        child: ListView(
          key: const Key('salary_pay_scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            Row(children: [
              Expanded(child: Text(
                'Pay monthly salaries',
                style: Theme.of(context).textTheme.titleMedium,
              )),
              IconButton(
                key: const Key('finance_refresh_salaries'),
                tooltip: 'Read salary bills from Firestore again',
                onPressed: _loadBills,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Only confirmed payments go into the Debit ledger. '
              'Partial salary payment and remaining balances are tracked.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('salary_bill_search'),
              decoration: const InputDecoration(
                labelText: 'Search teacher, month or salary ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                setState(() => _query = v.trim().toLowerCase());
              },
            ),
            CheckboxListTile(
              dense: true,
              value: _includePaid,
              title: const Text('Show fully paid salaries'),
              onChanged: (v) {
                setState(() => _includePaid = v ?? false);
              },
            ),
            const Divider(),
            const Text(
              'Salary records · finance_salary_bills · Diagnostic v4',
              key: Key('salary_server_view_version'),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              _connectionDetails(),
              key: const Key('salary_connection_details'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('finance_salary_probe'),
                onPressed: _probeSalaryDocument,
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('Check a specific saved salary bill'),
              ),
            ),
            const SizedBox(height: 8),
            // Never put this status inside a conditional async widget.
            Text(
              _loading
                  ? 'Read status: Loading saved salaries…'
                  : _readError != null
                      ? 'Read status: Failed to load salaries'
                      : 'Read status: ${_bills.length} saved salaries loaded · '
                        '${records.length} shown',
              key: const Key('salary_read_status'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _readError == null
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const LinearProgressIndicator(key: Key('salary_server_loading'))
            else if (_readError != null) ...[
              Text(
                _failureDetails(_readError!),
                key: const Key('salary_server_error'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('finance_salary_retry'),
                onPressed: _loadBills,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading salaries'),
              ),
            ] else if (records.isEmpty) ...[
              Text(
                _query.isNotEmpty
                    ? 'No salaries match the search. Clear the search.'
                    : _bills.isEmpty
                        ? 'The server returned no salary bills. Check the '
                          'Firebase project, published rules and signed-in account.'
                        : 'All salary bills are paid or filtered. '
                          'Enable Show fully paid salaries.',
                key: const Key('salary_server_empty'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadBills,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Firestore again'),
              ),
            ] else
              for (final bill in records)
                Card(
                  key: Key('salary_bill_${bill.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
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
                        const SizedBox(height: 8),
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
                ),
          ],
        ),
      ),
    );
  }
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
