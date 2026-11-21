import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/school_repository.dart';
import '../data/staff_repository.dart';

class ExaminationsPage extends StatefulWidget {
  const ExaminationsPage({super.key, required this.role});
  final String role;
  @override
  State<ExaminationsPage> createState() => _ExaminationsPageState();
}

class _ExaminationsPageState extends State<ExaminationsPage> {
  final _db = FirebaseFirestore.instance;
  final _school = SchoolRepository();
  late final Stream<List<TeacherAssignment>> _assignments =
      StaffRepository().watchAssignments();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _exams =
      _db.collection('examinations').limit(200).snapshots();
  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _syncRoster();
  }

  Future<void> _syncRoster() async {
    if (_syncing) return;
    setState(() { _syncing = true; _syncMessage = null; });
    try {
      final links = await StaffRepository().syncTeacherClassLinks();
      final count = await _school.syncClassRosters();
      if (mounted) setState(() =>
        _syncMessage = 'Teacher class access and safe student lists are ready ($links classes, $count students).');
    } catch (error) {
      if (mounted) setState(() => _syncMessage = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _create(List<TeacherAssignment> assignments) async {
    final active = assignments.where((item) => item.active).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Assign a teacher to a class and subject first.')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ExamEditor(
        assignments: active,
        onSave: (assignment, title, date, maxMarks) async {
          await _db.collection('examinations').add({
            'assignmentId': assignment.id,
            'staffId': assignment.staffId,
            'classId': assignment.classId,
            'className': assignment.className,
            'subject': assignment.subject,
            'title': title,
            'examDate': date,
            'maxMarks': maxMarks,
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Examination published for the assigned teacher.')));
    }
  }

  Future<void> _archive(String id, bool active) async {
    try {
      await _db.collection('examinations').doc(id).update({
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(schoolErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner' && widget.role != 'principal') {
      return const Scaffold(
        body: Center(child: Text('Only school administrators can manage examinations.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Examinations',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: Column(children: [
          if (_syncing || _syncMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    if (_syncing)
                      const SizedBox(width: 17, height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.groups_outlined, size: 19),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _syncing ? 'Preparing safe student class lists…' : _syncMessage!,
                      style: const TextStyle(fontSize: 11))),
                    if (!_syncing)
                      IconButton(
                        tooltip: 'Sync student lists again',
                        onPressed: _syncRoster,
                        icon: const Icon(Icons.refresh_rounded, size: 18)),
                  ]),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Publish exams for assigned classes and subjects. Teachers can then enter marks for their own class roster.',
                style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _exams,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(schoolErrorMessage(snapshot.error!))));
                if (!snapshot.hasData) return const Center(
                  child: CircularProgressIndicator());
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final av = a.data()['examDate'] as String? ?? '';
                    final bv = b.data()['examDate'] as String? ?? '';
                    return bv.compareTo(av);
                  });
                if (docs.isEmpty) return const Center(
                  child: Text('No examinations published yet.',
                    style: TextStyle(fontSize: 12)));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final active = data['active'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(active ? Icons.fact_check_outlined
                              : Icons.archive_outlined)),
                        title: Text((data['title'] as String?) ?? 'Examination',
                          style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${data['className'] ?? data['classId']} • ${data['subject']}\n'
                          '${data['examDate'] ?? 'No date'} • Max marks: ${data['maxMarks']} • '
                          '${active ? 'Published' : 'Archived'}',
                          style: const TextStyle(fontSize: 11)),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => _archive(doc.id, value == 'restore'),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: active ? 'archive' : 'restore',
                              child: Text(active ? 'Archive exam' : 'Restore exam')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
      floatingActionButton: StreamBuilder<List<TeacherAssignment>>(
        stream: _assignments,
        builder: (context, snapshot) => FloatingActionButton.extended(
          onPressed: snapshot.hasData ? () => _create(snapshot.data!) : null,
          icon: const Icon(Icons.add),
          label: const Text('Publish examination'),
        ),
      ),
    );
  }
}

class _ExamEditor extends StatefulWidget {
  const _ExamEditor({required this.assignments, required this.onSave});
  final List<TeacherAssignment> assignments;
  final Future<void> Function(
    TeacherAssignment assignment, String title, String examDate, double maxMarks,
  ) onSave;
  @override
  State<_ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends State<_ExamEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _maxMarks = TextEditingController(text: '100');
  late String _assignmentId = widget.assignments.first.id;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _title.dispose(); _maxMarks.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    TeacherAssignment? assignment;
    for (final item in widget.assignments) {
      if (item.id == _assignmentId) assignment = item;
    }
    final maxMarks = double.tryParse(_maxMarks.text.trim());
    if (assignment == null || maxMarks == null || maxMarks <= 0) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(
        assignment,
        _title.text.trim(),
        '${_date.year.toString().padLeft(4, '0')}-'
        '${_date.month.toString().padLeft(2, '0')}-'
        '${_date.day.toString().padLeft(2, '0')}',
        maxMarks,
      );
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
    title: const Text('Publish examination', style: TextStyle(fontSize: 16)),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _assignmentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Teacher • class • subject'),
            items: widget.assignments.map((item) => DropdownMenuItem(
              value: item.id,
              child: Text('${item.className.isEmpty ? item.classId : item.className} • ${item.subject}',
                overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _saving ? null : (value) {
              if (value != null) setState(() => _assignmentId = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Examination name *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter an examination name' : null,
          ),
          TextFormField(
            controller: _maxMarks,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Maximum marks *'),
            validator: (value) {
              final number = double.tryParse(value ?? '');
              return number == null || number <= 0
                  ? 'Enter a number greater than zero' : null;
            },
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Examination date', style: TextStyle(fontSize: 12)),
            subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _saving ? null : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null && mounted) setState(() => _date = picked);
            },
          ),
          if (_error != null) Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Publish exam')),
    ],
  );
}
