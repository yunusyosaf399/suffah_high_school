import 'dart:async';

import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/school_repository.dart';
import '../data/admission_repository.dart';
import 'admission_wizard_page.dart';
import 'classes_page.dart';
import 'student_profile_page.dart';

/// The admission CTA, filters and student list render separately, so a
/// failing classes stream cannot blank the entire student-management screen.
class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key, this.role = 'viewer', this.classesStream, this.studentsStream});

  final String role;
  final Stream<List<SchoolClass>>? classesStream;
  final Stream<List<StudentRecord>>? studentsStream;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  late final SchoolRepository _repo = SchoolRepository();
  late final AdmissionRepository _admissions = AdmissionRepository();
  bool _openingAdmission = false;
  bool get _canEdit => canEditAdmittedStudent(widget.role);
  late Stream<List<SchoolClass>> _classes =
      widget.classesStream ?? _repo.watchClasses();
  late Stream<List<StudentRecord>> _students =
      widget.studentsStream ?? _repo.watchStudents();

  List<SchoolClass> _loadedClasses = const [];
  bool _classesLoaded = false;
  bool _classesLoadingTooLong = false;
  Timer? _classesTimer;
  String _query = '';
  String _classFilter = '';
  bool _activeOnly = true;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  void _armTimer() {
    _classesTimer?.cancel();
    _classesTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && !_classesLoaded) {
        setState(() => _classesLoadingTooLong = true);
      }
    });
  }

  @override
  void dispose() {
    _classesTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _classesLoaded = false;
      _classesLoadingTooLong = false;
      _loadedClasses = const [];
      _classes = widget.classesStream ?? _repo.watchClasses();
      _students = widget.studentsStream ?? _repo.watchStudents();
    });
    _armTimer();
  }

  void _refreshStudents() {
    setState(() => _students =
        widget.studentsStream ?? _repo.watchStudents());
  }

  Future<void> _manageClasses() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ClassesPage()),
    );
    if (mounted) _reload();
  }

  Future<void> _beginAdmission() async {
    if (!_canEdit) return;
    if (!_classesLoaded || !_loadedClasses.any((c) => c.active)) {
      await _manageClasses();
      return;
    }
    await _openEditor(_loadedClasses);
  }

  Future<void> _openEditor(
    List<SchoolClass> classes, [
    StudentRecord? student,
  ]) async {
    if (_openingAdmission) return;
    final available = classes.where((c) => c.active).toList();
    final chosen = student != null &&
        !available.any((c) => c.id == student.classId)
        ? [...available, ...classes.where((c) => c.id == student.classId)]
        : available;
    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an active class first.')),
      );
      return;
    }

    setState(() => _openingAdmission = true);
    try {
      final record = student == null
          ? await _admissions.startDraft()
          : await _admissions.load(student.id);
      if (!mounted) return;
      setState(() => _openingAdmission = false);
      final finished = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AdmissionWizardPage(
            record: record,
            classes: chosen,
          ),
        ),
      );
      if (!mounted) return;
      _refreshStudents();
      if (finished == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admission completed and saved.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admission draft saved.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _openingAdmission = false);
    }
  }

  Future<void> _openProfile(StudentRecord student) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StudentProfilePage(
          studentId: student.id,
          role: widget.role,
          classes: _loadedClasses,
        ),
      ),
    );
    if (mounted) _refreshStudents();
  }

  Future<void> _setActive(StudentRecord student, bool active) async {
    if (!_canEdit) return;
    try {
      await _repo.setStudentActive(student.id, active);
      if (!mounted) return;
      _refreshStudents();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active
            ? 'Student reactivated.'
            : 'Student archived.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))),
      );
    }
  }

  Widget _notice(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 39, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(detail,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Reload students',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canEdit && !_openingAdmission ? _beginAdmission : null,
                  icon: const Icon(Icons.person_add_alt_1, size: 19),
                  label: Text(_openingAdmission ? 'Preparing admission…' : 'Add student'),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: CustomScrollView(
              key: const Key('students_scroll_view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admissions & student records',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                        const SizedBox(height: 5),
                        Text('Find or add student records. Start by creating a class.',
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                        const SizedBox(height: 5),
                        TextButton.icon(
                          onPressed: _manageClasses,
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: const Text('Manage classes & sections'),
                        ),
                        const SizedBox(height: 9),
                        TextField(
                          key: const Key('student_search_input'),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search name, admission no. or guardian',
                          ),
                          onChanged: (value) => setState(
                            () => _query = value.toLowerCase().trim(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<SchoolClass>>(
                          stream: _classes,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              _classesTimer?.cancel();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(schoolErrorMessage(snapshot.error!),
                                    style: TextStyle(color: colors.error, fontSize: 12)),
                                  TextButton.icon(
                                    onPressed: _reload,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry classes'),
                                  ),
                                ],
                              );
                            }
                            if (!snapshot.hasData) {
                              return Text(
                                _classesLoadingTooLong
                                    ? 'Classes are not responding. Check internet or open Manage classes.'
                                    : 'Loading class list…',
                                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                              );
                            }
                            _classesTimer?.cancel();
                            final classes = snapshot.data!;
                            _loadedClasses = classes;
                            _classesLoaded = true;
                            if (!classes.any((c) => c.active)) {
                              return OutlinedButton.icon(
                                onPressed: _manageClasses,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Create your first class'),
                              );
                            }
                            return Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: classes.any((c) => c.id == _classFilter)
                                        ? _classFilter : '',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Class',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                    ),
                                    items: [
                                      const DropdownMenuItem(value: '', child: Text('All classes')),
                                      ...classes.map((c) => DropdownMenuItem(
                                        value: c.id,
                                        child: Text(c.label),
                                      )),
                                    ],
                                    onChanged: (value) => setState(
                                      () => _classFilter = value ?? '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilterChip(
                                  label: const Text('Active only',
                                    style: TextStyle(fontSize: 11)),
                                  selected: _activeOnly,
                                  onSelected: (value) =>
                                      setState(() => _activeOnly = value),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                StreamBuilder<List<StudentRecord>>(
                  stream: _students,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: _notice(context,
                          icon: Icons.wifi_off_outlined,
                          title: 'Could not load students',
                          detail: schoolErrorMessage(snapshot.error!),
                          actionLabel: 'Retry students',
                          onAction: _refreshStudents),
                      );
                    }
                    if (!snapshot.hasData) {
                      return SliverToBoxAdapter(
                        child: _notice(context,
                          icon: Icons.hourglass_top_outlined,
                          title: 'Loading students',
                          detail: 'Reading the admission list from Firestore…'),
                      );
                    }
                    final all = snapshot.data!;
                    final shown = all.where((student) {
                      if (_activeOnly && !student.active && !student.isDraft) return false;
                      if (_classFilter.isNotEmpty &&
                          student.classId != _classFilter) return false;
                      if (_query.isEmpty) return true;
                      return student.fullName.toLowerCase().contains(_query) ||
                          student.admissionNo.toLowerCase().contains(_query) ||
                          student.guardianName.toLowerCase().contains(_query);
                    }).toList();

                    if (all.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _notice(context,
                          icon: Icons.groups_outlined,
                          title: 'No students yet',
                          detail: 'Tap Add student below to create the first admission.',
                          actionLabel: 'Create first admission',
                          onAction: _beginAdmission),
                      );
                    }
                    if (shown.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _notice(context,
                          icon: Icons.search_off_outlined,
                          title: 'No matching students',
                          detail: 'Try a different search term or filter.'),
                      );
                    }

                    final classNames = {
                      for (final item in _loadedClasses) item.id: item.label,
                    };
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final student = shown[index];
                          final initials = student.fullName.trim().isEmpty
                              ? '?' : student.fullName.trim()[0].toUpperCase();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                                leading: CircleAvatar(
                                  backgroundColor: colors.primaryContainer,
                                  foregroundColor: colors.onPrimaryContainer,
                                  child: Text(initials,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                title: Text(student.isDraft
                                  ? 'Draft • ${student.admissionNo}'
                                  : student.fullName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${student.admissionNo} • ${classNames[student.classId] ?? "Class not loaded"}\n'
                                  '${student.guardianName.isEmpty ? "Guardian not provided" : student.guardianName}'
                                  '${student.isDraft ? " • Save draft to resume" : student.active ? "" : " • Archived"}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                ),
                                isThreeLine: true,
                                onTap: () => student.isDraft
                                    ? _openEditor(_loadedClasses, student)
                                    : _openProfile(student),
                                trailing: !_canEdit
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : PopupMenuButton<String>(
                                        tooltip: 'Student options',
                                        onSelected: (action) {
                                          if (action == 'open') {
                                            if (student.isDraft) {
                                              _openEditor(_loadedClasses, student);
                                            } else {
                                              _openProfile(student);
                                            }
                                          } else {
                                            _setActive(student, action == 'activate');
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'open',
                                            child: Text(student.isDraft
                                                ? 'Resume draft'
                                                : 'View profile')),
                                          if (!student.isDraft)
                                            PopupMenuItem(
                                              value: student.active
                                                  ? 'archive' : 'activate',
                                              child: Text(student.active
                                                  ? 'Archive student'
                                                  : 'Reactivate student')),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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
      ).timeout(const Duration(seconds: 25));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = schoolErrorMessage(error);
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
