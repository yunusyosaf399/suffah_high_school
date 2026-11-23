import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import '../data/staff_repository.dart';
import 'finance_common.dart';

// Keep the established import path for the rest of the school app.
export 'finance_pay_salary_tab.dart' show FinancePaySalaryTab;

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
