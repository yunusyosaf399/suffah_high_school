import 'package:flutter/material.dart';
import '../data/class_subject_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';

class ClassSubjectsPage extends StatefulWidget {
  const ClassSubjectsPage({
    super.key, required this.schoolClass, this.subjectsStream,
    this.onSave, this.onSetActive,
  });

  final SchoolClass schoolClass;
  final Stream<List<ClassSubject>>? subjectsStream;
  final Future<void> Function(ClassSubject? existing, String name, String code,
      String description, int weeklyPeriods)? onSave;
  final Future<void> Function(ClassSubject subject, bool active)? onSetActive;

  @override
  State<ClassSubjectsPage> createState() => _ClassSubjectsPageState();
}

class _ClassSubjectsPageState extends State<ClassSubjectsPage> {
  late final ClassSubjectRepository _repo = ClassSubjectRepository();
  late final Stream<List<ClassSubject>> _stream =
      widget.subjectsStream ?? _repo.watchSubjects(widget.schoolClass.id);

  Future<void> _edit({ClassSubject? initial}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SubjectDialog(
        initial: initial,
        onSave: (name, code, description, periods) => widget.onSave != null
          ? widget.onSave!(initial, name, code, description, periods)
          : _repo.saveSubject(
              classId: widget.schoolClass.id, name: name, code: code,
              description: description, weeklyPeriods: periods,
              existingId: initial?.id),
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject saved.')));
    }
  }

  Future<void> _toggle(ClassSubject subject) async {
    try {
      if (widget.onSetActive != null) {
        await widget.onSetActive!(subject, !subject.active);
      } else {
        await _repo.setSubjectActive(subject, !subject.active);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(subject.active ? 'Subject archived.' : 'Subject restored.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.schoolClass.label} · Subjects')),
    bottomNavigationBar: widget.schoolClass.active ? SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          key: const Key('add_class_subject'),
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Add subject')),
      ),
    ) : null,
    body: StreamBuilder<List<ClassSubject>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(schoolErrorMessage(snap.error!))));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final subjects = snap.data!;
        if (subjects.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No subjects yet. Add subjects here before assigning teachers.')));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: subjects.length,
          itemBuilder: (_, index) {
            final subject = subjects[index];
            return Card(child: ListTile(
              key: Key('class_subject_${subject.id}'),
              leading: Icon(subject.active ? Icons.menu_book_outlined
                  : Icons.archive_outlined),
              title: Text(subject.name),
              subtitle: Text([
                if (subject.code.isNotEmpty) 'Code: ${subject.code}',
                if (subject.weeklyPeriods > 0)
                  '${subject.weeklyPeriods} periods/week',
                if (subject.description.isNotEmpty) subject.description,
                if (!subject.active) 'Archived',
              ].join(' · ')),
              trailing: widget.schoolClass.active ? PopupMenuButton<String>(
                tooltip: 'Subject options',
                onSelected: (value) => value == 'edit'
                  ? _edit(initial: subject) : _toggle(subject),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit',
                    child: Text('Edit details')),
                  PopupMenuItem(value: 'toggle', child: Text(subject.active
                      ? 'Archive subject' : 'Restore subject')),
                ],
              ) : null,
            ));
          },
        );
      },
    ),
  );
}

class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({required this.onSave, this.initial});
  final ClassSubject? initial;
  final Future<void> Function(String name, String code,
      String description, int weeklyPeriods) onSave;
  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _description = TextEditingController(
      text: widget.initial?.description ?? '');
  late final _periods = TextEditingController(
      text: widget.initial?.weeklyPeriods.toString() ?? '0');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    _periods.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(_name.text.trim(), _code.text.trim(),
        _description.text.trim(), int.parse(_periods.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.initial == null ? 'Add subject' : 'Edit subject details'),
    content: SizedBox(width: 400, child: Form(
      key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(
          key: const Key('subject_name_field'), controller: _name,
          readOnly: widget.initial != null,
          maxLength: 60, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Subject name *',
            hintText: 'e.g. Mathematics'),
          validator: (v) => (v?.trim().length ?? 0) < 2
            ? 'Enter a subject name' : null),
        TextFormField(
          controller: _code, maxLength: 16,
          decoration: const InputDecoration(
            labelText: 'Subject code', hintText: 'e.g. MATH-05')),
        TextFormField(
          controller: _periods, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Periods per week (0–30)'),
          validator: (v) {
            final n = int.tryParse(v?.trim() ?? '');
            return n == null || n < 0 || n > 30
              ? 'Enter a number from 0 to 30' : null;
          }),
        TextFormField(
          controller: _description, maxLength: 500, maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description / syllabus details')),
        if (_error != null) Text(_error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    )),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
      FilledButton(
        key: const Key('save_class_subject'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save subject')),
    ],
  );
}
