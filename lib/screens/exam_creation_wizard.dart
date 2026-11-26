import 'package:flutter/material.dart';

import '../data/class_subject_repository.dart';
import '../data/examination_repository.dart';
import '../data/school_errors.dart';
import '../data/staff_repository.dart';

class ExamCreationWizard extends StatefulWidget {
  const ExamCreationWizard({super.key, required this.role, required this.assignments,
    this.teacherNames = const {}, this.classSubjects = const {}, this.initialKind = 'term'});
  final String role;
  final List<TeacherAssignment> assignments;
  final Map<String, String> teacherNames;
  final Map<String, List<ClassSubject>> classSubjects;
  final String initialKind;

  @override
  State<ExamCreationWizard> createState() => _ExamCreationWizardState();
}

class _ExamCreationWizardState extends State<ExamCreationWizard> {
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  late String _kind = widget.initialKind;
  String _term = 'First Term';
  String _testType = 'Monthly Test';
  String? _classId;
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  DateTime _end = DateUtils.dateOnly(DateTime.now());
  final _papers = <ExamPaperDraft>[];
  int _step = 0;
  bool _saving = false;
  String? _error;
  bool get _assignment => _kind == 'assignment';
  bool get _formal => _kind == 'term';

  @override
  void dispose() {
    _title.dispose(); _instructions.dispose(); super.dispose();
  }

  String _classLabel(String id) {
    for (final a in widget.assignments) {
      if (a.classId == id && a.className.isNotEmpty) return a.className;
    }
    return id;
  }

  Future<DateTime?> _pick(DateTime initial, {DateTime? first, DateTime? last}) =>
      showDatePicker(context: context, initialDate: initial,
        firstDate: first ?? DateTime(2000), lastDate: last ?? DateTime(2100));

  void _next() {
    String? error;
    if (_step == 0) {
      if (_end.isBefore(_start)) error = 'Check the date range.';
      if (_title.text.trim().isEmpty) {
        _title.text = _formal ? _term : _assignment ? 'Class assignment' : _testType;
      }
    } else if (_step == 1) {
      if (_papers.isEmpty) error = 'Add at least one subject and responsible teacher.';
      if (!_formal && _papers.length != 1) error = 'Choose one subject for this activity.';
      if (!_assignment && error == null) {
        error = validateExamSchedule(kind: _kind, category: _formal ? _term : _testType,
          title: _title.text, start: _start, end: _end, papers: _papers);
      }
    }
    setState(() { _error = error; if (error == null) _step++; });
  }

  Future<void> _addPaper() async {
    if (_classId == null) return;
    final options = widget.assignments.where((a) => a.active && a.classId == _classId).toList();
    if (options.isEmpty) {
      setState(() => _error = 'Assign a subject teacher to this class first.');
      return;
    }
    final paper = await showDialog<ExamPaperDraft>(
      context: context,
      builder: (_) => _PaperEditor(assignments: options, teacherNames: widget.teacherNames,
        start: _start, end: _end, assignmentOnly: _assignment),
    );
    if (!mounted || paper == null) return;
    setState(() {
      _error = null;
      if (!_formal) _papers.clear();
      _papers.add(paper);
    });
  }

  Future<void> _publish() async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ExaminationRepository();
      if (_assignment) {
        await repo.createAssignment(assignment: _papers.single.assignment,
          title: _title.text, instructions: _instructions.text, dueDate: _start);
      } else {
        await repo.publishSchedule(role: widget.role, kind: _kind,
          category: _formal ? _term : _testType, title: _title.text,
          start: _start, end: _end, papers: _papers);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateTile(String title, DateTime date, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero, title: Text(title),
    subtitle: Text(examDateKey(date)), trailing: const Icon(Icons.calendar_month),
    onTap: onTap,
  );

  Widget _details() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DropdownButtonFormField<String>(
      initialValue: _kind, isExpanded: true,
      decoration: const InputDecoration(labelText: 'Assessment type'),
      items: [
        if (canScheduleFormalExams(widget.role))
          const DropdownMenuItem(value: 'term', child: Text('Term Examination')),
        const DropdownMenuItem(value: 'test', child: Text('Classwise Test')),
        if (canScheduleFormalExams(widget.role))
          const DropdownMenuItem(value: 'assignment', child: Text('Class Assignment')),
      ],
      onChanged: (v) {
        if (v != null) setState(() {
          _kind = v; _papers.clear();
          if (!_formal) _end = _start;
        });
      },
    ),
    const SizedBox(height: 14),
    if (!_assignment)
      DropdownButtonFormField<String>(
        key: ValueKey(_kind), initialValue: _formal ? _term : _testType,
        isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final item in _formal ? examTerms : classTestTypes)
          DropdownMenuItem(value: item, child: Text(item))],
        onChanged: (v) { if (v != null) setState(() { if (_formal) { _term = v; } else { _testType = v; } }); },
      ),
    const SizedBox(height: 14),
    TextField(controller: _title, maxLength: 100,
      decoration: const InputDecoration(labelText: 'Title (optional automatic name)')),
    _dateTile(_assignment ? 'Due date' : 'Start date', _start, () async {
      final picked = await _pick(_start);
      if (picked != null && mounted) setState(() {
        _start = picked;
        if (!_formal || _end.isBefore(_start)) _end = _start;
        _papers.clear();
      });
    }),
    if (_formal) _dateTile('End date', _end, () async {
      final picked = await _pick(_end, first: _start);
      if (picked != null && mounted) setState(() { _end = picked; _papers.clear(); });
    }),
    if (_assignment) TextField(controller: _instructions, maxLines: 4, maxLength: 1000,
      decoration: const InputDecoration(labelText: 'Assignment instructions')),
  ]);

  Widget _schedule() {
    final classes = widget.assignments.where((a) => a.active).map((a) => a.classId).toSet().toList()
      ..sort((a,b) => _classLabel(a).compareTo(_classLabel(b)));
    final catalog = widget.classSubjects[_classId] ?? const <ClassSubject>[];
    final scheduled = _papers.map((p) => p.assignment.subject).toSet();
    final missing = catalog.where((s) => s.active && !scheduled.contains(s.name)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: _classId, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Class & section'),
        items: [for (final id in classes) DropdownMenuItem(value: id,
          child: Text(_classLabel(id), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() { _classId = v; _papers.clear(); }),
      ),
      const SizedBox(height: 10),
      if (_formal && missing.isNotEmpty)
        Text('Not yet scheduled: ${missing.map((s) => s.name).join(', ')}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      for (var i = 0; i < _papers.length; i++)
        Card(child: ListTile(
          title: Text(_papers[i].assignment.subject),
          subtitle: Text('${widget.teacherNames[_papers[i].assignment.staffId] ?? _papers[i].assignment.staffId}'
            '${_assignment ? '' : '\n${examDateKey(_papers[i].date)} • ${_papers[i].type} • ${_papers[i].maxMarks} marks'}'),
          trailing: IconButton(tooltip: 'Remove paper', onPressed: () => setState(() => _papers.removeAt(i)),
            icon: const Icon(Icons.delete_outline)),
        )),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _classId == null || _papers.length >= 15 ? null : _addPaper,
        icon: const Icon(Icons.add), label: Text(_formal ? 'Add subject paper' : 'Choose subject & teacher')),
      if (_formal) const Text('Add theory and practical papers separately if required. A schedule supports up to 15 papers.'),
    ]);
  }

  Widget _review() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(_title.text, style: Theme.of(context).textTheme.titleLarge),
    Text('${examDateKey(_start)}${_formal ? ' – ${examDateKey(_end)}' : ''}'),
    Text(_classLabel(_classId!)),
    const SizedBox(height: 12),
    for (final p in _papers) Card(child: ListTile(
      title: Text(p.assignment.subject),
      subtitle: Text('${widget.teacherNames[p.assignment.staffId] ?? p.assignment.staffId}'
        '${_assignment ? '' : '\n${examDateKey(p.date)} • ${p.type} • ${p.maxMarks} marks • ${p.durationMinutes} min'}'),
    )),
    if (_assignment) Text(_instructions.text),
    const SizedBox(height: 12),
    const Text('Publishing makes the activity available to its assigned subject teacher.'),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create assessment')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Step ${_step + 1} of 3 • ${['Details', 'Class & papers', 'Review'][_step]}',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_step + 1) / 3),
          ])),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_step == 0) _details() else if (_step == 1) _schedule() else _review(),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          if (_step > 0) Expanded(child: OutlinedButton(onPressed: _saving ? null : () => setState(() { _step--; _error = null; }),
            child: const Text('Back'))),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _saving ? null : _step == 2 ? _publish : _next,
            child: Text(_saving ? 'Publishing…' : _step == 2 ? 'Publish' : 'Next'))),
        ])),
      ]),
    ))),
  );
}

class _PaperEditor extends StatefulWidget {
  const _PaperEditor({required this.assignments, required this.teacherNames,
    required this.start, required this.end, required this.assignmentOnly});
  final List<TeacherAssignment> assignments;
  final Map<String, String> teacherNames;
  final DateTime start, end;
  final bool assignmentOnly;

  @override
  State<_PaperEditor> createState() => _PaperEditorState();
}

class _PaperEditorState extends State<_PaperEditor> {
  late String _subject = widget.assignments.first.subject;
  String? _assignmentId;
  late DateTime _date = widget.start;
  String _type = 'Theory';
  final _marks = TextEditingController(text: '100');
  final _duration = TextEditingController(text: '60');
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() { _marks.dispose(); _duration.dispose(); _notes.dispose(); super.dispose(); }

  void _save() {
    final options = widget.assignments.where((a) => a.subject == _subject && a.id == _assignmentId);
    final marks = double.tryParse(_marks.text);
    final minutes = int.tryParse(_duration.text);
    if (options.isEmpty || marks == null || !marks.isFinite || marks <= 0 || marks > 1000 ||
        minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _error = 'Select a teacher and enter valid marks and duration.');
      return;
    }
    Navigator.pop(context, ExamPaperDraft(assignment: options.first, date: _date,
      type: _type, maxMarks: marks, durationMinutes: minutes, instructions: _notes.text));
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.assignments.map((a) => a.subject).toSet().toList()..sort();
    final teachers = widget.assignments.where((a) => a.subject == _subject);
    return AlertDialog(scrollable: true, title: Text(widget.assignmentOnly ? 'Choose subject' : 'Schedule paper'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: _subject, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: [for (final subject in subjects) DropdownMenuItem(value: subject, child: Text(subject))],
          onChanged: (v) { if (v != null) setState(() { _subject = v; _assignmentId = null; }); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(key: ValueKey(_subject), initialValue: _assignmentId, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Responsible subject teacher'),
          items: [for (final a in teachers) DropdownMenuItem(value: a.id,
            child: Text(widget.teacherNames[a.staffId] ?? a.staffId, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _assignmentId = v)),
        if (!widget.assignmentOnly) ...[
          const SizedBox(height: 12),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Paper date'),
            subtitle: Text(examDateKey(_date)), trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: widget.start, lastDate: widget.end);
              if (d != null && mounted) setState(() => _date = d);
            }),
          DropdownButtonFormField<String>(initialValue: _type, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paper type'),
            items: [for (final type in paperTypes) DropdownMenuItem(value: type, child: Text(type))],
            onChanged: (v) { if (v != null) setState(() => _type = v); }),
          const SizedBox(height: 12),
          TextField(controller: _marks, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Maximum marks')),
          const SizedBox(height: 12),
          TextField(controller: _duration, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duration (minutes)')),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 3, maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Room, syllabus or instructions')),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Add'))]);
  }
}
