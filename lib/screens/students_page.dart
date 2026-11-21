import 'package:flutter/material.dart';

import '../data/school_repository.dart';
import 'classes_page.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key, this.classesStream, this.studentsStream});

  final Stream<List<SchoolClass>>? classesStream;
  final Stream<List<StudentRecord>>? studentsStream;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  late final SchoolRepository _repo = SchoolRepository();
  late final Stream<List<StudentRecord>> _students =
      widget.studentsStream ?? _repo.watchStudents();
  late final Stream<List<SchoolClass>> _classes =
      widget.classesStream ?? _repo.watchClasses();

  List<SchoolClass> _loadedClasses = const [];
  bool _classesLoaded = false;

  Future<void> _beginAdmission() async {
    if (!_classesLoaded || !_loadedClasses.any((c) => c.active)) {
      await _manageClasses();
      return;
    }
    await _openEditor(_loadedClasses);
  }

  Future<void> _manageClasses() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ClassesPage()),
    );
  }

  String _query = '';
  String _classFilter = '';
  bool _activeOnly = true;

  Future<void> _openEditor(List<SchoolClass> classes, [StudentRecord? student]) async {
    final available = classes.where((c) => c.active).toList();
    final selected = student != null && !available.any((c) => c.id == student.classId)
        ? [...available, ...classes.where((c) => c.id == student.classId)]
        : available;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an active class before adding students.')),
      );
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StudentEditorPage(classes: selected, student: student),
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(student == null ? 'Student admitted successfully.' : 'Student updated successfully.')),
      );
    }
  }

  Future<void> _setActive(StudentRecord student, bool active) async {
    try {
      await _repo.setStudentActive(student.id, active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active ? 'Student reactivated.' : 'Student archived.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update student. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Admissions & student records',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _beginAdmission,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Add student'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _manageClasses,
                      icon: const Icon(Icons.school_outlined, size: 18),
                      label: const Text('Manage classes & sections'),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search name, admission no. or guardian',
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.toLowerCase().trim()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<List<SchoolClass>>(
              stream: _classes,
              builder: (context, classSnapshot) {
                if (classSnapshot.hasError) {
                  return _StudentsEmpty(
                    icon: Icons.wifi_off_outlined,
                    title: 'Could not load classes',
                    subtitle: 'Check your connection. You can still open class setup.',
                    action: TextButton.icon(
                      onPressed: _manageClasses,
                      icon: const Icon(Icons.school_outlined),
                      label: const Text('Open classes'),
                    ),
                  );
                }
                if (!classSnapshot.hasData) {
                  return _StudentsEmpty(
                    icon: Icons.hourglass_top_outlined,
                    title: 'Loading classes',
                    subtitle: 'You can still use Add student or Manage classes above.',
                    action: TextButton.icon(
                      onPressed: _manageClasses,
                      icon: const Icon(Icons.school_outlined),
                      label: const Text('Manage classes'),
                    ),
                  );
                }
                final classes = classSnapshot.data!;
                _loadedClasses = classes;
                _classesLoaded = true;
                final classNames = {for (final item in classes) item.id: item.label};
                if (!classes.any((c) => c.active)) {
                  return _StudentsEmpty(
                    icon: Icons.school_outlined,
                    title: 'Create your first class',
                    subtitle: 'Add a class and section before admitting students.',
                    action: FilledButton.icon(
                      onPressed: _manageClasses,
                      icon: const Icon(Icons.add),
                      label: const Text('Create a class'),
                    ),
                  );
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: classNames.containsKey(_classFilter) ? _classFilter : '',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Class',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('All classes')),
                                ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                              ],
                              onChanged: (value) => setState(() => _classFilter = value ?? ''),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('Active only', style: TextStyle(fontSize: 11)),
                            selected: _activeOnly,
                            onSelected: (value) => setState(() => _activeOnly = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<List<StudentRecord>>(
                          stream: _students,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const _StudentsEmpty(
                                icon: Icons.wifi_off_outlined,
                                title: 'Could not load students',
                                subtitle: 'Check your internet connection and retry.',
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final all = snapshot.data!;
                            final visible = all.where((student) {
                              if (_activeOnly && !student.active) return false;
                              if (_classFilter.isNotEmpty && student.classId != _classFilter) return false;
                              if (_query.isEmpty) return true;
                              return student.fullName.toLowerCase().contains(_query) ||
                                  student.admissionNo.toLowerCase().contains(_query) ||
                                  student.guardianName.toLowerCase().contains(_query);
                            }).toList();
                            if (all.isEmpty) {
                              return _StudentsEmpty(
                                icon: Icons.groups_outlined,
                                title: 'No students yet',
                                subtitle: 'Add your first admission to this class.',
                                action: FilledButton.icon(
                                  onPressed: _beginAdmission,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Admit first student'),
                                ),
                              );
                            }
                            if (visible.isEmpty) {
                              return const _StudentsEmpty(
                                icon: Icons.search_off_outlined,
                                title: 'No matching students',
                                subtitle: 'Try another name or change the filters.',
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '${visible.length} shown • ${all.length} total',
                                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: visible.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                                    itemBuilder: (context, index) {
                                      final student = visible[index];
                                      final initials = student.fullName.trim().isEmpty
                                          ? '?' : student.fullName.trim().substring(0, 1).toUpperCase();
                                      return Card(
                                        margin: EdgeInsets.zero,
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
                                          leading: CircleAvatar(
                                            backgroundColor: colors.primaryContainer,
                                            foregroundColor: colors.onPrimaryContainer,
                                            child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ),
                                          title: Text(student.fullName,
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          subtitle: Text(
                                            '${student.admissionNo} • ${classNames[student.classId] ?? "Unassigned"}\n${student.guardianName.isEmpty ? "Guardian not provided" : student.guardianName}${student.active ? "" : " • Archived"}',
                                            maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                          ),
                                          isThreeLine: true,
                                          onTap: () => _openEditor(classes, student),
                                          trailing: PopupMenuButton<String>(
                                            tooltip: 'Student options',
                                            icon: const Icon(Icons.more_vert, size: 20),
                                            onSelected: (action) {
                                              if (action == 'edit') {
                                                _openEditor(classes, student);
                                              } else {
                                                _setActive(student, action == 'activate');
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('Edit student')),
                                              PopupMenuItem(
                                                value: student.active ? 'archive' : 'activate',
                                                child: Text(student.active ? 'Archive student' : 'Reactivate student'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                );
              },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentsEmpty extends StatelessWidget {
  const _StudentsEmpty({required this.icon, required this.title, required this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: color),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(subtitle, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color)),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class StudentEditorPage extends StatefulWidget {
  const StudentEditorPage({super.key, required this.classes, this.student});
  final List<SchoolClass> classes;
  final StudentRecord? student;

  @override
  State<StudentEditorPage> createState() => _StudentEditorPageState();
}

class _StudentEditorPageState extends State<StudentEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = SchoolRepository();
  late final _admission = TextEditingController(text: widget.student?.admissionNo ?? '');
  late final _name = TextEditingController(text: widget.student?.fullName ?? '');
  late final _guardian = TextEditingController(text: widget.student?.guardianName ?? '');
  late final _phone = TextEditingController(text: widget.student?.guardianPhone ?? '');
  late final _roll = TextEditingController(text: widget.student?.rollNo ?? '');
  late String _classId = widget.student?.classId ?? widget.classes.first.id;
  late String _gender = widget.student?.gender ?? 'Not specified';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _admission.dispose();
    _name.dispose();
    _guardian.dispose();
    _phone.dispose();
    _roll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await _repo.saveStudent(
        existingId: widget.student?.id,
        admissionNo: _admission.text,
        fullName: _name.text,
        classId: _classId,
        guardianName: _guardian.text,
        guardianPhone: _phone.text,
        gender: _gender,
        rollNo: _roll.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError || error is ArgumentError
              ? error.toString().replaceFirst(RegExp(r'^(Bad state|Invalid argument):\s*'), '')
              : 'Unable to save student. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.student != null;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(existing ? 'Edit student' : 'New admission',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 690),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text('Student details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Fields marked * are required.', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _admission,
                            enabled: !existing && !_saving,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 24,
                            decoration: const InputDecoration(
                              labelText: 'Admission number *',
                              hintText: 'e.g. SHS-001',
                              helperText: 'Unique ID; cannot be changed later',
                            ),
                            validator: (value) => validAdmissionNo(value ?? '')
                                ? null : 'Use letters, numbers or hyphens (max 24)',
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _name,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 80,
                            decoration: const InputDecoration(labelText: 'Student full name *'),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter student name' : null,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _classId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Class / section *'),
                            items: widget.classes.map((item) =>
                                DropdownMenuItem(value: item.id, child: Text(item.label))).toList(),
                            onChanged: _saving ? null : (value) => setState(() => _classId = value ?? _classId),
                            validator: (value) => value == null || value.isEmpty ? 'Choose a class' : null,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _gender,
                                  decoration: const InputDecoration(labelText: 'Gender'),
                                  items: const [
                                    DropdownMenuItem(value: 'Not specified', child: Text('Not specified')),
                                    DropdownMenuItem(value: 'Boy', child: Text('Boy')),
                                    DropdownMenuItem(value: 'Girl', child: Text('Girl')),
                                  ],
                                  onChanged: _saving ? null : (value) => setState(() => _gender = value ?? _gender),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _roll,
                                  enabled: !_saving,
                                  maxLength: 12,
                                  decoration: const InputDecoration(labelText: 'Roll no.'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Guardian information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _guardian,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 80,
                            decoration: const InputDecoration(labelText: 'Parent / guardian name'),
                          ),
                          const SizedBox(height: 9),
                          TextFormField(
                            controller: _phone,
                            enabled: !_saving,
                            keyboardType: TextInputType.phone,
                            maxLength: 20,
                            decoration: const InputDecoration(labelText: 'Guardian phone', hintText: 'e.g. 03XXXXXXXXX'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Parent login and linking multiple children to one account will be added in the parent module.',
                            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(fontSize: 12, color: colors.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: Icon(_saving ? Icons.hourglass_top : Icons.check_rounded, size: 18),
                    label: Text(_saving ? 'Saving…' : existing ? 'Save changes' : 'Admit student'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
