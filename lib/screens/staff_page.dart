import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/school_repository.dart';
import '../data/staff_repository.dart';

typedef StaffSaveAction = Future<void> Function(StaffInput input, String? id);
typedef TeacherAssignAction = Future<void> Function(
  String staffId, String classId, String subject,
);

class StaffPage extends StatefulWidget {
  const StaffPage({
    super.key,
    this.role = 'owner',
    this.staffStream,
    this.assignmentsStream,
    this.classesStream,
    this.onSaveStaff,
    this.onAssignTeacher,
  });

  final String role;
  final Stream<List<StaffMember>>? staffStream;
  final Stream<List<TeacherAssignment>>? assignmentsStream;
  final Stream<List<SchoolClass>>? classesStream;
  final StaffSaveAction? onSaveStaff;
  final TeacherAssignAction? onAssignTeacher;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with SingleTickerProviderStateMixin {
  late final StaffRepository _repo = StaffRepository();
  late final SchoolRepository _schoolRepo = SchoolRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Stream<List<StaffMember>> _staff;
  late Stream<List<TeacherAssignment>> _assignments;
  late Stream<List<SchoolClass>> _classes;
  List<StaffMember> _staffCache = const [];
  List<SchoolClass> _classesCache = const [];
  String _staffQuery = '';
  String _assignmentQuery = '';
  bool _showArchivedStaff = false;
  bool _showArchivedAssignments = false;

  bool get _canEdit =>
      widget.role == 'owner' || widget.role == 'principal';

  @override
  void initState() {
    super.initState();
    _resetStreams();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _resetStreams() {
    _staff = (widget.staffStream ?? _repo.watchStaff()).asBroadcastStream();
    _assignments = widget.assignmentsStream ?? _repo.watchAssignments();
    _classes = widget.classesStream ?? _schoolRepo.watchClasses();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(_resetStreams);
  }

  Future<void> _saveStaff(StaffInput input, String? id) =>
      widget.onSaveStaff != null
          ? widget.onSaveStaff!(input, id)
          : id == null
              ? _repo.createStaff(input)
              : _repo.updateStaff(id, input);

  Future<void> _addStaff({StaffMember? existing}) async {
    if (!_canEdit) return;
    final success = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffEditorDialog(
        initial: existing,
        onSave: (input) => _saveStaff(input, existing?.id),
      ),
    );
    if (!mounted || success != true) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(existing == null
          ? 'Staff member created.'
          : 'Staff information updated.'),
    ));
  }

  Future<void> _assignTeacher() async {
    if (!_canEdit) return;
    final teachers = _staffCache
        .where((staff) => staff.isTeacher && staff.active)
        .toList();
    final classes = _classesCache.where((c) => c.active).toList();
    if (teachers.isEmpty || classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Add an active teacher and class before making assignments.',
        )),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignTeacherDialog(
        teachers: teachers,
        classes: classes,
        onSave: (staffId, classId, subject) =>
            widget.onAssignTeacher != null
                ? widget.onAssignTeacher!(staffId, classId, subject)
                : _repo.assignTeacher(
                    staffId: staffId,
                    classId: classId,
                    subject: subject,
                  ),
      ),
    );
    if (!mounted || saved != true) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Teacher assignment saved.'),
    ));
  }

  Future<void> _toggleStaff(StaffMember staff, bool active) async {
    if (!_canEdit) return;
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Archive staff member?'),
          content: const Text(
            'This removes the staff member from active lists. Existing '
            'teacher assignments and historical references are preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await _repo.setStaffActive(staff.id, active);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(active ? 'Staff member restored.' : 'Staff archived.'),
      ));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleAssignment(TeacherAssignment assignment) async {
    if (!_canEdit) return;
    try {
      await _repo.setAssignmentActive(assignment.id, !assignment.active);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(assignment.active
            ? 'Assignment archived.'
            : 'Assignment restored.'),
      ));
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(schoolErrorMessage(error))),
    );
  }

  Future<void> _showProfile(StaffMember staff) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 5, 20, 26),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(staff.fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('${staff.staffNo} · ${staffTypes[staff.roleType] ?? staff.roleType}',
                    style: const TextStyle(fontSize: 12)),
                  const Divider(height: 26),
                  _detail('Designation', staff.designation),
                  _detail('Phone', staff.phone),
                  _detail('WhatsApp', staff.whatsapp),
                  _detail('Email', staff.email),
                  _detail('Date joined', staff.joinDate),
                  _detail('Qualifications', staff.qualification),
                  _detail('Address', staff.address),
                  _detail('Status', staff.active ? 'Active' : 'Archived'),
                  if (_canEdit) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _addStaff(existing: staff);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit staff details'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(
          fontSize: 10, letterSpacing: 0.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(value.trim().isEmpty ? '—' : value,
          style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  Widget _empty(String title, String detail, {IconData icon = Icons.people_outline}) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 39, color: color),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _staffTab(List<StaffMember> members) {
    final filtered = members.where((staff) {
      if (!_showArchivedStaff && !staff.active) return false;
      if (_staffQuery.isEmpty) return true;
      final query = _staffQuery.toLowerCase();
      return staff.fullName.toLowerCase().contains(query) ||
          staff.staffNo.toLowerCase().contains(query) ||
          staff.designation.toLowerCase().contains(query) ||
          staff.phone.contains(query);
    }).toList();

    return CustomScrollView(
      key: const Key('staff_scroll_view'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Staff directory',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Staff records are separate from Firebase sign-in accounts.',
                  style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('staff_search'),
                  onChanged: (value) =>
                      setState(() => _staffQuery = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search staff, designation or phone',
                    prefixIcon: Icon(Icons.search_rounded, size: 19)),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Show archived',
                        style: TextStyle(fontSize: 11)),
                      selected: _showArchivedStaff,
                      onSelected: (value) =>
                          setState(() => _showArchivedStaff = value),
                    ),
                    const Spacer(),
                    Text('${filtered.length} staff',
                      style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _empty(
              members.isEmpty ? 'No staff members yet' : 'No matching staff',
              members.isEmpty
                  ? 'Tap Add staff to create your first staff profile.'
                  : 'Adjust the search or archived filter.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final staff = filtered[index];
                final color = Theme.of(context).colorScheme;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    key: Key('staff_item_${staff.id}'),
                    onTap: () => _showProfile(staff),
                    leading: CircleAvatar(
                      backgroundColor: color.primaryContainer,
                      child: const Icon(Icons.badge_outlined, size: 22),
                    ),
                    title: Text(staff.fullName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${staff.staffNo} · ${staff.designation}\n'
                      '${staffTypes[staff.roleType] ?? staff.roleType}'
                      ' · ${staff.active ? "Active" : "Archived"}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                    trailing: !_canEdit
                        ? const Icon(Icons.chevron_right)
                        : PopupMenuButton<String>(
                            tooltip: 'Staff actions',
                            onSelected: (action) {
                              if (action == 'view') {
                                _showProfile(staff);
                              } else {
                                _toggleStaff(staff, action == 'restore');
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'view', child: Text('View staff profile')),
                              PopupMenuItem(
                                value: staff.active ? 'archive' : 'restore',
                                child: Text(staff.active
                                    ? 'Archive staff' : 'Restore staff')),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _assignmentsTab(
    List<StaffMember> staff,
    List<TeacherAssignment> assignments,
    List<SchoolClass> classes,
  ) {
    final byStaff = {for (final member in staff) member.id: member};
    final byClass = {for (final item in classes) item.id: item};
    final filtered = assignments.where((assignment) {
      if (!_showArchivedAssignments && !assignment.active) return false;
      final teacher = byStaff[assignment.staffId];
      final schoolClass = byClass[assignment.classId];
      final words = [
        teacher?.fullName ?? '',
        schoolClass?.label ?? '',
        assignment.subject,
      ].join(' ').toLowerCase();
      return words.contains(_assignmentQuery.toLowerCase());
    }).toList()
      ..sort((a, b) {
        final aName = byStaff[a.staffId]?.fullName ?? '';
        final bName = byStaff[b.staffId]?.fullName ?? '';
        return aName.compareTo(bName);
      });

    return CustomScrollView(
      key: const Key('assignments_scroll_view'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teaching assignments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Assign a teacher to one or more classes and subjects.',
                  style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('assignment_search'),
                  onChanged: (value) =>
                      setState(() => _assignmentQuery = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search teacher, class or subject',
                    prefixIcon: Icon(Icons.search_rounded, size: 19)),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Show archived',
                        style: TextStyle(fontSize: 11)),
                      selected: _showArchivedAssignments,
                      onSelected: (value) =>
                          setState(() => _showArchivedAssignments = value),
                    ),
                    const Spacer(),
                    Text('${filtered.length} assignments',
                      style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _empty(
              assignments.isEmpty ? 'No teacher assignments yet'
                  : 'No matching assignments',
              assignments.isEmpty
                  ? 'Add a teacher and class, then tap Assign teacher.'
                  : 'Adjust your search or archived filter.',
              icon: Icons.menu_book_outlined,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final assignment = filtered[index];
                final teacher = byStaff[assignment.staffId];
                final schoolClass = byClass[assignment.classId];
                final valid = teacher?.active == true &&
                    schoolClass?.active == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    key: Key('assignment_item_${assignment.id}'),
                    leading: const CircleAvatar(
                      child: Icon(Icons.co_present_outlined, size: 20)),
                    title: Text(teacher?.fullName ?? 'Unknown teacher',
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${schoolClass?.label ?? assignment.classId}'
                      ' · ${assignment.subject}\n'
                      '${assignment.active && valid ? "Active" : valid ? "Archived" : "Staff/class inactive"}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                    trailing: !_canEdit
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: 'Assignment options',
                            onSelected: (_) => _toggleAssignment(assignment),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'toggle',
                                enabled: assignment.active || valid,
                                child: Text(assignment.active
                                    ? 'Archive assignment'
                                    : 'Restore assignment'),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & teachers',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Reload staff',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Staff'),
            Tab(text: 'Assignments'),
          ],
        ),
      ),
      bottomNavigationBar: _canEdit ? SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key(_tabs.index == 0 ? 'add_staff' : 'assign_teacher'),
                  onPressed: _tabs.index == 0 ? _addStaff : _assignTeacher,
                  icon: Icon(_tabs.index == 0
                      ? Icons.person_add_alt_1_rounded
                      : Icons.playlist_add_check_rounded),
                  label: Text(_tabs.index == 0 ? 'Add staff' : 'Assign teacher'),
                ),
              ),
            ),
          ),
        ),
      ) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: StreamBuilder<List<StaffMember>>(
              stream: _staff,
              builder: (context, staffSnapshot) {
                if (staffSnapshot.hasError) {
                  return _empty('Staff could not load',
                    schoolErrorMessage(staffSnapshot.error!),
                    icon: Icons.cloud_off_outlined);
                }
                if (!staffSnapshot.hasData) {
                  return _empty('Loading staff',
                    'Reading staff profiles from Firestore.',
                    icon: Icons.hourglass_top_rounded);
                }
                _staffCache = staffSnapshot.data!;
                return TabBarView(
                  controller: _tabs,
                  children: [
                    _staffTab(_staffCache),
                    StreamBuilder<List<SchoolClass>>(
                      stream: _classes,
                      builder: (context, classSnap) {
                        if (classSnap.hasError) {
                          return _empty('Classes unavailable',
                            schoolErrorMessage(classSnap.error!),
                            icon: Icons.cloud_off_outlined);
                        }
                        if (!classSnap.hasData) {
                          return _empty('Loading classes',
                            'Reading available sections.',
                            icon: Icons.hourglass_top_rounded);
                        }
                        _classesCache = classSnap.data!;
                        return StreamBuilder<List<TeacherAssignment>>(
                          stream: _assignments,
                          builder: (context, assignmentSnap) {
                            if (assignmentSnap.hasError) {
                              return _empty('Assignments unavailable',
                                schoolErrorMessage(assignmentSnap.error!),
                                icon: Icons.cloud_off_outlined);
                            }
                            if (!assignmentSnap.hasData) {
                              return _empty('Loading assignments',
                                'Reading teaching assignments.',
                                icon: Icons.hourglass_top_rounded);
                            }
                            return _assignmentsTab(
                              _staffCache,
                              assignmentSnap.data!,
                              _classesCache,
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog({required this.onSave, this.initial});
  final StaffMember? initial;
  final Future<void> Function(StaffInput input) onSave;

  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.initial?.firstName);
  late final _middle = TextEditingController(text: widget.initial?.middleName);
  late final _last = TextEditingController(text: widget.initial?.lastName);
  late final _title = TextEditingController(
    text: widget.initial?.designation ?? 'Teacher');
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _whatsapp = TextEditingController(
    text: widget.initial?.whatsapp);
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _qualification = TextEditingController(
    text: widget.initial?.qualification);
  late final _address = TextEditingController(text: widget.initial?.address);
  late String _type = widget.initial?.roleType ?? 'teacher';
  late DateTime _joined = DateTime.tryParse(
      widget.initial?.joinDate ?? '') ?? DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _first, _middle, _last, _title, _phone,
      _whatsapp, _email, _qualification, _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _date() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _joined,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'Date of joining',
    );
    if (result != null && mounted) setState(() => _joined = result);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final input = StaffInput(
      firstName: _first.text,
      middleName: _middle.text,
      lastName: _last.text,
      roleType: _type,
      designation: _title.text,
      phone: _phone.text,
      whatsapp: _whatsapp.text,
      email: _email.text,
      qualification: _qualification.text,
      address: _address.text,
      joinDate: '${_joined.year.toString().padLeft(4, '0')}-'
          '${_joined.month.toString().padLeft(2, '0')}-'
          '${_joined.day.toString().padLeft(2, '0')}',
    );
    final validation = input.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(input);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller,
      {bool required = false, TextInputType? inputType, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          keyboardType: inputType,
          textCapitalization: inputType == TextInputType.emailAddress
              ? TextCapitalization.none : TextCapitalization.words,
          maxLength: lines > 1 ? 200 : 100,
          decoration: InputDecoration(labelText: label,
            counterText: ''),
          validator: required
              ? (value) => value == null || value.trim().isEmpty
                  ? 'Required field' : null
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.initial == null ? 'Add staff member' : 'Edit staff',
      style: const TextStyle(fontSize: 17)),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.initial != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('ID: ${widget.initial!.staffNo}',
                  style: const TextStyle(fontSize: 11)),
              ),
            _field('First name *', _first, required: true),
            _field('Middle name (optional)', _middle),
            _field('Last name *', _last, required: true),
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Staff category *'),
                items: staffTypes.entries.map((item) =>
                    DropdownMenuItem(
                      value: item.key, child: Text(item.value))).toList(),
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
            ),
            _field('Designation *', _title, required: true),
            _field('Phone number *', _phone,
              required: true, inputType: TextInputType.phone),
            _field('WhatsApp number', _whatsapp,
              inputType: TextInputType.phone),
            _field('Email', _email,
              inputType: TextInputType.emailAddress),
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: InkWell(
                onTap: _saving ? null : _date,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of joining',
                    suffixIcon: Icon(Icons.calendar_month_outlined, size: 21)),
                  child: Text(
                    '${_joined.year.toString().padLeft(4, '0')}-'
                    '${_joined.month.toString().padLeft(2, '0')}-'
                    '${_joined.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
            _field('Qualification', _qualification),
            _field('Address', _address, lines: 2),
            if (_error != null) ...[
              const SizedBox(height: 5),
              Text(_error!,
                style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…'
            : widget.initial == null ? 'Save staff' : 'Save changes')),
    ],
  );
}

class _AssignTeacherDialog extends StatefulWidget {
  const _AssignTeacherDialog({
    required this.teachers,
    required this.classes,
    required this.onSave,
  });
  final List<StaffMember> teachers;
  final List<SchoolClass> classes;
  final TeacherAssignAction onSave;

  @override
  State<_AssignTeacherDialog> createState() => _AssignTeacherDialogState();
}

class _AssignTeacherDialogState extends State<_AssignTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  late String _staffId = widget.teachers.first.id;
  late String _classId = widget.classes.first.id;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(_staffId, _classId, _subject.text.trim());
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
    title: const Text('Assign teacher', style: TextStyle(fontSize: 17)),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _staffId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Teacher *'),
              items: widget.teachers.map((staff) =>
                  DropdownMenuItem(
                    value: staff.id, child: Text(staff.fullName))).toList(),
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() => _staffId = value);
              },
            ),
            const SizedBox(height: 13),
            DropdownButtonFormField<String>(
              initialValue: _classId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Class & section *'),
              items: widget.classes.map((item) =>
                  DropdownMenuItem(
                    value: item.id, child: Text(item.label))).toList(),
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() => _classId = value);
              },
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _subject,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Subject *', hintText: 'e.g. Mathematics'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter the teaching subject' : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'The same teacher may teach multiple subjects or classes. '
              'An existing assignment cannot be duplicated.',
              style: TextStyle(fontSize: 11),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 12,
                color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save assignment')),
    ],
  );
}
