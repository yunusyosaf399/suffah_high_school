import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/staff_repository.dart';
import 'teacher_examinations_page.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key, required this.displayName, required this.staffId});
  final String displayName;
  final String staffId;
  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  late final Stream<List<TeacherAssignment>> _assignments =
      StaffRepository().watchAssignmentsForStaff(widget.staffId);

  void _open(Widget page) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => page),
  );

  Widget _module(String title, String subtitle, IconData icon,
      VoidCallback onTap) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 27, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher portal',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Text('Welcome, ${widget.displayName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('Your assigned classes and academic work.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                Text('My teaching assignments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                StreamBuilder<List<TeacherAssignment>>(
                  stream: _assignments,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _TeacherMessage(
                      message: schoolErrorMessage(snapshot.error!),
                      icon: Icons.cloud_off_outlined);
                    if (!snapshot.hasData) return const _TeacherMessage(
                      message: 'Loading your assigned classes…',
                      icon: Icons.hourglass_top_rounded);
                    final assignments = snapshot.data!;
                    if (assignments.isEmpty) return const _TeacherMessage(
                      message: 'No active class or subject assignments have been added yet.',
                      icon: Icons.menu_book_outlined);
                    return Column(children: assignments.map((assignment) => Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
                        title: Text(assignment.className.isEmpty
                            ? assignment.classId : assignment.className,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(assignment.subject,
                          style: const TextStyle(fontSize: 11)),
                      ),
                    )).toList());
                  },
                ),
                const SizedBox(height: 18),
                Text('Teacher workspace',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 620 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.12,
                  children: [
                    _module('Examinations & marks', 'View exams and enter marks',
                      Icons.fact_check_outlined,
                      () => _open(TeacherExaminationsPage(staffId: widget.staffId))),
                    _module('Assignments', 'Create class assignments',
                      Icons.assignment_outlined,
                      () => _open(TeacherClassworkPage(
                        staffId: widget.staffId, kind: 'assignment'))),
                    _module('Homework', 'Set and review homework',
                      Icons.menu_book_outlined,
                      () => _open(TeacherClassworkPage(
                        staffId: widget.staffId, kind: 'homework'))),

                  ],
                ),
                const SizedBox(height: 18),
                Text('This portal is limited to your linked teacher profile and assigned teaching work.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherMessage extends StatelessWidget {
  const _TeacherMessage({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
      ]),
    ),
  );
}

class TeacherClassworkPage extends StatefulWidget {
  const TeacherClassworkPage({super.key, required this.staffId, required this.kind});
  final String staffId;
  final String kind;
  @override
  State<TeacherClassworkPage> createState() => _TeacherClassworkPageState();
}

class _TeacherClassworkPageState extends State<TeacherClassworkPage> {
  final _db = FirebaseFirestore.instance;
  late final Stream<List<TeacherAssignment>> _assignments =
      StaffRepository().watchAssignmentsForStaff(widget.staffId);
  String get _title => widget.kind == 'homework' ? 'Homework' : 'Assignments';

  Future<void> _create(List<TeacherAssignment> assignments) async {
    if (assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ask the school owner to assign you to a class and subject first.')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ClassworkEditor(
        kind: widget.kind,
        assignments: assignments,
        onSave: (assignment, title, instructions, dueDate) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('Sign in again to continue.');
          await _db.collection('classwork').add({
            'kind': widget.kind,
            'title': title,
            'instructions': instructions,
            'dueDate': dueDate,
            'assignmentId': assignment.id,
            'staffId': widget.staffId,
            'teacherUid': user.uid,
            'classId': assignment.classId,
            'className': assignment.className,
            'subject': assignment.subject,
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_title created.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Sign in again.')));
    final query = _db.collection('classwork')
        .where('staffId', isEqualTo: widget.staffId)
        .where('teacherUid', isEqualTo: user.uid)
        .limit(100);
    return Scaffold(
      appBar: AppBar(title: Text(_title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      floatingActionButton: StreamBuilder<List<TeacherAssignment>>(
        stream: _assignments,
        builder: (context, snapshot) => FloatingActionButton.extended(
          onPressed: snapshot.hasData ? () => _create(snapshot.data!) : null,
          icon: const Icon(Icons.add),
          label: Text('New ${widget.kind}'),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _TeacherMessage(
            message: schoolErrorMessage(snapshot.error!), icon: Icons.cloud_off_outlined);
          if (!snapshot.hasData) return const _TeacherMessage(
            message: 'Loading your classwork…', icon: Icons.hourglass_top_rounded);
          final docs = snapshot.data!.docs
              .where((doc) => doc.data()['kind'] == widget.kind &&
                  doc.data()['active'] != false)
              .toList()
            ..sort((a, b) {
              final at = a.data()['createdAt'];
              final bt = b.data()['createdAt'];
              if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
              return 0;
            });
          if (docs.isEmpty) return _TeacherMessage(
            message: 'No ${widget.kind} created yet. Use the button to add one for an assigned class.',
            icon: Icons.assignment_outlined);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              return Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  leading: CircleAvatar(child: Icon(widget.kind == 'homework'
                      ? Icons.menu_book_outlined : Icons.assignment_outlined)),
                  title: Text((data['title'] as String?) ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${data['className'] ?? data['classId']} • ${data['subject']}\nDue: ${data['dueDate'] ?? 'Not set'}',
                    style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((data['title'] as String?) ?? '',
                            style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          Text((data['instructions'] as String?) ?? 'No instructions.'),
                          const SizedBox(height: 10),
                          Text('Due: ${data['dueDate'] ?? 'Not set'}',
                            style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ClassworkEditor extends StatefulWidget {
  const _ClassworkEditor({required this.kind, required this.assignments, required this.onSave});
  final String kind;
  final List<TeacherAssignment> assignments;
  final Future<void> Function(
    TeacherAssignment assignment, String title, String instructions, String dueDate,
  ) onSave;
  @override
  State<_ClassworkEditor> createState() => _ClassworkEditorState();
}

class _ClassworkEditorState extends State<_ClassworkEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  late String _assignmentId = widget.assignments.first.id;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _title.dispose(); _instructions.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    TeacherAssignment? assignment;
    for (final item in widget.assignments) {
      if (item.id == _assignmentId) assignment = item;
    }
    if (assignment == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(
        assignment, _title.text.trim(), _instructions.text.trim(),
        '${_dueDate.year.toString().padLeft(4, '0')}-'
        '${_dueDate.month.toString().padLeft(2, '0')}-'
        '${_dueDate.day.toString().padLeft(2, '0')}',
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
    title: Text('New ${widget.kind}', style: const TextStyle(fontSize: 16)),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _assignmentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Assigned class & subject'),
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
            controller: _title, maxLength: 100,
            decoration: const InputDecoration(labelText: 'Title *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a title' : null,
          ),
          TextFormField(
            controller: _instructions, maxLength: 1000, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Instructions'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Due date', style: TextStyle(fontSize: 12)),
            subtitle: Text('${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _saving ? null : () async {
              final picked = await showDatePicker(
                context: context, initialDate: _dueDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null && mounted) setState(() => _dueDate = picked);
            },
          ),
          if (_error != null) Text(_error!, style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Create')),
    ],
  );
}

