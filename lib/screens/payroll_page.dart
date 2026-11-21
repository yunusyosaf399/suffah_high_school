import 'package:flutter/material.dart';

import '../data/payroll_repository.dart';
import '../data/school_errors.dart';
import '../data/staff_repository.dart';

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key, required this.role});
  final String role;
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late final PayrollRepository _repository = PayrollRepository();
  late final Stream<List<PayrollRecord>> _records = _repository.watchPayroll();
  late final Stream<List<StaffMember>> _staff = StaffRepository().watchStaff();

  Future<void> _create(List<StaffMember> staff) async {
    final active = staff.where((item) => item.active).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Register an active staff member before adding payroll.')));
      return;
    }
    final receipt = await showDialog<String>(
      context: context,
      builder: (_) => _PayrollEditor(
        staff: active, onSave: _repository.createRecord),
    );
    if (!mounted || receipt == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Salary receipt $receipt created.')));
  }

  Future<void> _markPaid(PayrollRecord record) async {
    final date = await showDatePicker(
      context: context, initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Payment date',
    );
    if (date == null || !mounted) return;
    final paidAt = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    try {
      await _repository.updatePaymentStatus(
        recordId: record.id, status: 'paid',
        paidAt: paidAt, paymentMethod: 'Bank transfer',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))));
    }
  }

  void _showReceipt(PayrollRecord record) {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (_) => _PayrollReceipt(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner' && widget.role != 'principal') {
      return const Scaffold(
        body: Center(child: Text('Only school administrators can manage payroll.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll & salary receipts',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      floatingActionButton: StreamBuilder<List<StaffMember>>(
        stream: _staff,
        builder: (context, snapshot) => FloatingActionButton.extended(
          onPressed: snapshot.hasData ? () => _create(snapshot.data!) : null,
          icon: const Icon(Icons.add),
          label: const Text('Add salary record'),
        ),
      ),
      body: StreamBuilder<List<PayrollRecord>>(
        stream: _records,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(schoolErrorMessage(snapshot.error!))));
          if (!snapshot.hasData) return const Center(
            child: CircularProgressIndicator());
          final records = snapshot.data!.toList()
            ..sort((a, b) => b.period.compareTo(a.period));
          if (records.isEmpty) return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No salary records yet. Add the first staff payroll record.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            ),
          );
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(record.status == 'paid'
                        ? Icons.check_circle_outline : Icons.pending_outlined)),
                  title: Text(record.staffName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${record.period} • ${record.receiptNo}\nNet: PKR ${record.netSalary.toStringAsFixed(2)} • ${record.status.toUpperCase()}',
                    style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') _showReceipt(record);
                      if (value == 'paid') _markPaid(record);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view',
                        child: Text('View salary receipt')),
                      if (record.status != 'paid')
                        const PopupMenuItem(value: 'paid',
                          child: Text('Mark as paid')),
                    ],
                  ),
                  onTap: () => _showReceipt(record),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PayrollEditor extends StatefulWidget {
  const _PayrollEditor({required this.staff, required this.onSave});
  final List<StaffMember> staff;
  final Future<String> Function(PayrollInput input) onSave;
  @override
  State<_PayrollEditor> createState() => _PayrollEditorState();
}

class _PayrollEditorState extends State<_PayrollEditor> {
  final _form = GlobalKey<FormState>();
  late final _period = TextEditingController(
    text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}');
  final _basic = TextEditingController();
  final _allowances = TextEditingController(text: '0');
  final _deductions = TextEditingController(text: '0');
  final _notes = TextEditingController();
  late String _staffId = widget.staff.first.id;
  String _status = 'unpaid';
  String _paymentMethod = 'Bank transfer';
  DateTime _paidDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _period.dispose(); _basic.dispose(); _allowances.dispose();
    _deductions.dispose(); _notes.dispose(); super.dispose();
  }

  double _amount(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;
  double get _net => _amount(_basic) + _amount(_allowances) - _amount(_deductions);

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final input = PayrollInput(
      staffId: _staffId,
      period: _period.text.trim(),
      basicSalary: _amount(_basic),
      allowances: _amount(_allowances),
      deductions: _amount(_deductions),
      status: _status,
      paymentMethod: _paymentMethod,
      paidAt: _status == 'paid'
          ? '${_paidDate.year.toString().padLeft(4, '0')}-'
            '${_paidDate.month.toString().padLeft(2, '0')}-'
            '${_paidDate.day.toString().padLeft(2, '0')}'
          : '',
      notes: _notes.text,
    );
    final validation = input.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final receipt = await widget.onSave(input);
      if (mounted) Navigator.pop(context, receipt);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moneyField(String label, TextEditingController controller,
      {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, prefixText: 'PKR '),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Enter $label';
        }
        final number = double.tryParse(value ?? '');
        if (number == null || number < 0) return 'Enter a valid amount';
        return null;
      },
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Add salary record', style: TextStyle(fontSize: 16)),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _staffId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Staff member *'),
            items: widget.staff.map((staff) => DropdownMenuItem(
              value: staff.id,
              child: Text('${staff.fullName} • ${staff.staffNo}',
                overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _saving ? null : (value) {
              if (value != null) setState(() => _staffId = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _period,
            decoration: const InputDecoration(labelText: 'Pay period (YYYY-MM) *'),
            validator: (value) => value == null ||
                !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value.trim())
                ? 'Use YYYY-MM' : null,
          ),
          const SizedBox(height: 12),
          _moneyField('Basic salary', _basic, required: true),
          _moneyField('Allowances', _allowances),
          _moneyField('Deductions', _deductions),
          Align(alignment: Alignment.centerRight,
            child: Text('Net salary: PKR ${_net.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Payment status'),
            items: const [
              DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
            ],
            onChanged: _saving ? null : (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          if (_status == 'paid') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const ['Bank transfer', 'Cash', 'Cheque']
                  .map((value) => DropdownMenuItem(
                    value: value, child: Text(value))).toList(),
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Paid on', style: TextStyle(fontSize: 12)),
              subtitle: Text('${_paidDate.year}-${_paidDate.month.toString().padLeft(2, '0')}-${_paidDate.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _saving ? null : () async {
                final picked = await showDatePicker(
                  context: context, initialDate: _paidDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null && mounted) setState(() => _paidDate = picked);
              },
            ),
          ],
          TextFormField(
            controller: _notes, maxLength: 300, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Create receipt')),
    ],
  );
}

class _PayrollReceipt extends StatelessWidget {
  const _PayrollReceipt({required this.record});
  final PayrollRecord record;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Salary receipt', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(record.staffName, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700)),
        _row('Employee ID', record.staffNo),
        _row('Receipt number', record.receiptNo),
        _row('Pay period', record.period),
        const Divider(),
        _row('Basic salary', 'PKR ${record.basicSalary.toStringAsFixed(2)}'),
        _row('Allowances', 'PKR ${record.allowances.toStringAsFixed(2)}'),
        _row('Deductions', 'PKR ${record.deductions.toStringAsFixed(2)}'),
        const Divider(),
        _row('Net salary', 'PKR ${record.netSalary.toStringAsFixed(2)}'),
        _row('Payment status', record.status.toUpperCase()),
        _row('Paid on', record.paidAt.isEmpty ? '—' : record.paidAt),
        _row('Payment method', record.paymentMethod.isEmpty ? '—' : record.paymentMethod),
        if (record.notes.isNotEmpty) _row('Notes', record.notes),
      ]),
    ),
  );
}
