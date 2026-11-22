import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/school_repository.dart';
import '../data/staff_repository.dart';

class FinanceScope {
  const FinanceScope({
    required this.classes,
    required this.students,
    required this.teachers,
  });
  final List<SchoolClass> classes;
  final List<StudentRecord> students;
  final List<StaffMember> teachers;

  Map<String, SchoolClass> get classesById =>
      {for (final item in classes) item.id: item};
}

class FinanceStudentPicker extends StatefulWidget {
  const FinanceStudentPicker({
    super.key,
    required this.students,
    required this.classes,
    this.initialIds = const {},
  });
  final List<StudentRecord> students;
  final List<SchoolClass> classes;
  final Set<String> initialIds;

  @override
  State<FinanceStudentPicker> createState() => _FinanceStudentPickerState();
}

class _FinanceStudentPickerState extends State<FinanceStudentPicker> {
  late Set<String> _selected = {...widget.initialIds};
  String _classId = 'all';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final students = widget.students.where((student) =>
        (_classId == 'all' || student.classId == _classId) &&
        (student.fullName.toLowerCase().contains(_query.toLowerCase()) ||
            student.rollNo.contains(_query) ||
            student.admissionNo.toLowerCase().contains(_query.toLowerCase())))
        .toList();
    students.sort((a, b) => a.fullName.compareTo(b.fullName));

    return AlertDialog(
      title: const Text('Select students'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 500,
        height: math.min(420.0, MediaQuery.sizeOf(context).height * 0.56),
        child: Column(children: [
          DropdownButtonFormField<String>(
            key: const Key('finance_picker_class'),
            initialValue: 'all',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Class / all students'),
            items: [
              const DropdownMenuItem(value: 'all',
                child: Text('All classes')),
              ...widget.classes.map((c) => DropdownMenuItem(
                value: c.id, child: Text(c.label))),
            ],
            onChanged: (value) => setState(() => _classId = value ?? 'all'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('finance_student_search'),
            decoration: const InputDecoration(
              hintText: 'Search student, admission or roll',
              prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(
              '${_selected.length} selected · ${students.length} shown',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            TextButton(
              onPressed: () => setState(() =>
                  _selected.addAll(students.map((s) => s.id))),
              child: const Text('Select shown')),
            TextButton(
              onPressed: () => setState(() =>
                  _selected.removeAll(students.map((s) => s.id))),
              child: const Text('Clear shown')),
          ]),
          const Divider(height: 4),
          Expanded(child: students.isEmpty
              ? const Center(child: Text('No students match the filter.'))
              : ListView.builder(
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return CheckboxListTile(
                      key: Key('finance_select_${student.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(student.id),
                      title: Text(student.fullName,
                        style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${widget.classes.where((c) => c.id == student.classId).map((c) => c.label).firstOrNull ?? student.classId} · Roll ${student.rollNo}',
                        style: const TextStyle(fontSize: 11)),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(student.id);
                        } else {
                          _selected.remove(student.id);
                        }
                      }),
                    );
                  })),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
        FilledButton(
          key: const Key('finance_apply_student_selection'),
          onPressed: _selected.isEmpty ? null : () => Navigator.pop(
            context,
            widget.students.where((s) => _selected.contains(s.id)).toList(),
          ),
          child: Text('Apply (${_selected.length})')),
      ],
    );
  }
}

Future<List<StudentRecord>?> pickFinanceStudents(
    BuildContext context, FinanceScope scope) =>
    showDialog<List<StudentRecord>>(
      context: context,
      builder: (_) => FinanceStudentPicker(
        students: scope.students, classes: scope.classes),
    );

String? financeValidateAmount(String? input, {bool allowZero = false}) {
  try {
    if (allowZero && (input == null || input.trim().isEmpty ||
        RegExp(r'^0+(\.0{1,2})?
    return null;
  } catch (_) {
    return allowZero
        ? 'Enter 0 or a positive amount with up to two decimals.'
        : 'Enter an amount greater than zero (e.g. 2000.00).';
  }
}

int financeOptionalAmount(String input) =>
    input.trim().isEmpty ||
    RegExp(r'^0+(\.0{1,2})?

class FinanceAmountField extends StatelessWidget {
  const FinanceAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.optional = false,
  });
  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: 'Rs ',
    ),
    validator: (value) =>
        financeValidateAmount(value, allowZero: optional),
  );
}

class FinanceMonthSelector extends StatelessWidget {
  const FinanceMonthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Financial month',
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = [financeMonth(now), previousFinanceMonth(now)];
    return DropdownButtonFormField<String>(
      key: const Key('finance_month_selector'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final month in options)
          DropdownMenuItem(
            value: month, child: Text(financeMonthLabel(month))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class FinanceMethodSelector extends StatelessWidget {
  const FinanceMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Payment method'),
    items: [
      for (final method in financePaymentMethods)
        DropdownMenuItem(value: method, child: Text(method)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

void financeSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
}

class FinanceEmpty extends StatelessWidget {
  const FinanceEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, textAlign: TextAlign.center),
  ));
}
).hasMatch(input.trim()))) {
      return null;
    }
    financeMinorUnits(input ?? '');
    return null;
  } catch (_) {
    return allowZero
        ? 'Enter 0 or a positive amount with up to two decimals.'
        : 'Enter an amount greater than zero (e.g. 2000.00).';
  }
}

int financeOptionalAmount(String input) =>
    input.trim().isEmpty || input.trim() == '0'
        ? 0 : financeMinorUnits(input);

class FinanceAmountField extends StatelessWidget {
  const FinanceAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.optional = false,
  });
  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: 'Rs ',
    ),
    validator: (value) =>
        financeValidateAmount(value, allowZero: optional),
  );
}

class FinanceMonthSelector extends StatelessWidget {
  const FinanceMonthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Financial month',
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = [financeMonth(now), previousFinanceMonth(now)];
    return DropdownButtonFormField<String>(
      key: const Key('finance_month_selector'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final month in options)
          DropdownMenuItem(
            value: month, child: Text(financeMonthLabel(month))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class FinanceMethodSelector extends StatelessWidget {
  const FinanceMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Payment method'),
    items: [
      for (final method in financePaymentMethods)
        DropdownMenuItem(value: method, child: Text(method)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

void financeSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
}

class FinanceEmpty extends StatelessWidget {
  const FinanceEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, textAlign: TextAlign.center),
  ));
}
).hasMatch(input.trim())
        ? 0 : financeMinorUnits(input);

class FinanceAmountField extends StatelessWidget {
  const FinanceAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.optional = false,
  });
  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: 'Rs ',
    ),
    validator: (value) =>
        financeValidateAmount(value, allowZero: optional),
  );
}

class FinanceMonthSelector extends StatelessWidget {
  const FinanceMonthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Financial month',
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = [financeMonth(now), previousFinanceMonth(now)];
    return DropdownButtonFormField<String>(
      key: const Key('finance_month_selector'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final month in options)
          DropdownMenuItem(
            value: month, child: Text(financeMonthLabel(month))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class FinanceMethodSelector extends StatelessWidget {
  const FinanceMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Payment method'),
    items: [
      for (final method in financePaymentMethods)
        DropdownMenuItem(value: method, child: Text(method)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

void financeSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
}

class FinanceEmpty extends StatelessWidget {
  const FinanceEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, textAlign: TextAlign.center),
  ));
}
).hasMatch(input.trim()))) {
      return null;
    }
    financeMinorUnits(input ?? '');
    return null;
  } catch (_) {
    return allowZero
        ? 'Enter 0 or a positive amount with up to two decimals.'
        : 'Enter an amount greater than zero (e.g. 2000.00).';
  }
}

int financeOptionalAmount(String input) =>
    input.trim().isEmpty || input.trim() == '0'
        ? 0 : financeMinorUnits(input);

class FinanceAmountField extends StatelessWidget {
  const FinanceAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.optional = false,
  });
  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: 'Rs ',
    ),
    validator: (value) =>
        financeValidateAmount(value, allowZero: optional),
  );
}

class FinanceMonthSelector extends StatelessWidget {
  const FinanceMonthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Financial month',
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = [financeMonth(now), previousFinanceMonth(now)];
    return DropdownButtonFormField<String>(
      key: const Key('finance_month_selector'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final month in options)
          DropdownMenuItem(
            value: month, child: Text(financeMonthLabel(month))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class FinanceMethodSelector extends StatelessWidget {
  const FinanceMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Payment method'),
    items: [
      for (final method in financePaymentMethods)
        DropdownMenuItem(value: method, child: Text(method)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

void financeSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
}

class FinanceEmpty extends StatelessWidget {
  const FinanceEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, textAlign: TextAlign.center),
  ));
}
