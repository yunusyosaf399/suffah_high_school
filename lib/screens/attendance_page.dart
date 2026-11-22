import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import 'classes_page.dart';
import 'attendance_teacher_assignments_page.dart';
import 'attendance_reports_tab.dart';

typedef AttendanceSaveCallback = Future<void> Function(
  String classId,
  DateTime date,
  Map<String, String> changes,
);

/// Online student attendance for one class and date at a time.
///
/// A status remains "Not marked" until somebody explicitly marks it.
/// Only changes are uploaded, and the current day's register is re-loadable.
class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    this.role = 'owner',
    this.assignedClass,
    this.classesLoader,
    this.rosterLoader,
    this.marksLoader,
    this.saveOverride,
  });

  final String role;
  /// A teacher can open only this class; the server verifies the assignment.
  final SchoolClass? assignedClass;
  final Future<List<SchoolClass>> Function()? classesLoader;
  final Future<List<StudentRecord>> Function(String classId)? rosterLoader;
  final Future<Map<String, String>> Function(String classId, DateTime date)?
      marksLoader;
  final AttendanceSaveCallback? saveOverride;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final SchoolRepository _school = SchoolRepository();
  late final AttendanceRepository _attendance = AttendanceRepository();

  List<SchoolClass> _classes = const [];
  List<StudentRecord> _roster = const [];
  Map<String, String> _marks = {};
  Map<String, String> _savedMarks = {};
  DateTime _date = DateTime.now();
  String? _classId;
  String _search = '';
  bool _unmarkedOnly = false;
  bool _classesLoading = true;
  bool _loadingRegister = false;
  bool _saving = false;
  bool _registerLoaded = false;
  String? _classError;
  String? _registerError;
  int _generation = 0;
  int _reportRevision = 0;

  bool get _teacherClass => widget.role == 'teacher' && widget.assignedClass != null;
  bool get _canEdit => canManageAttendance(widget.role) || _teacherClass;

  AttendanceSummary get _summary =>
      AttendanceSummary.fromMarks(_roster, _marks);

  Map<String, String> get _pending {
    final changes = <String, String>{};
    for (final student in _roster) {
      final current = _marks[student.id] ?? 'unmarked';
      final previous = _savedMarks[student.id] ?? 'unmarked';
      if (current != previous) changes[student.id] = current;
    }
    return changes;
  }

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _loadClasses();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() {
      _classesLoading = true;
      _classError = null;
    });
    try {
      final loaded = _teacherClass
          ? [widget.assignedClass!]
          : await (widget.classesLoader?.call() ?? _school.watchClasses().first)
              .timeout(const Duration(seconds: 22));
      if (!mounted) return;
      final active = loaded.where((c) => c.active).toList();
      active.sort((a, b) => a.label.compareTo(b.label));
      final selected = active.any((c) => c.id == _classId)
          ? _classId : active.isEmpty ? null : active.first.id;
      setState(() {
        _classes = active;
        _classesLoading = false;
        _classId = selected;
      });
      if (selected != null) {
        await _loadRegister();
      } else {
        setState(() {
          _roster = const [];
          _marks = {};
          _savedMarks = {};
          _registerLoaded = true;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _classesLoading = false;
        _classError = schoolErrorMessage(error);
      });
    }
  }

  Future<bool> _discardIfNeeded() async {
    if (_pending.isEmpty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved attendance'),
        content: const Text(
          'You have unsaved marks. Discard them and open another register?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _changeClass(String? next) async {
    if (next == null || next == _classId || _saving) return;
    if (!await _discardIfNeeded()) return;
    if (!mounted) return;
    setState(() => _classId = next);
    await _loadRegister();
  }

  Future<void> _changeDate() async {
    if (_saving) return;
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Attendance date',
    );
    if (picked == null || attendanceDateKey(picked) == attendanceDateKey(_date)) {
      return;
    }
    if (!mounted || !await _discardIfNeeded()) return;
    if (!mounted) return;
    setState(() => _date = picked);
    await _loadRegister();
  }

  Future<void> _refresh() async {
    if (_saving || !await _discardIfNeeded() || !mounted) return;
    if (_classes.isEmpty) {
      await _loadClasses();
    } else {
      await _loadRegister();
    }
  }

  Future<void> _openClassSetup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ClassesPage()),
    );
    if (mounted) await _loadClasses();
  }

  Future<void> _loadRegister() async {
    final classId = _classId;
    if (classId == null) return;
    final generation = ++_generation;
    if (!mounted) return;
    setState(() {
      _loadingRegister = true;
      _registerLoaded = false;
      _registerError = null;
      _roster = const [];
      _marks = {};
      _savedMarks = {};
    });
    try {
      final rosterFuture = widget.rosterLoader?.call(classId)
          ?? (_teacherClass
              ? _attendance.loadSafeRoster(classId)
              : _attendance.loadRoster(classId));
      final marksFuture = widget.marksLoader?.call(classId, _date)
          ?? _attendance.loadMarks(classId, _date,
              forAttendanceTeacher: _teacherClass);
      final roster = await rosterFuture;
      final marks = await marksFuture;
      if (!mounted || generation != _generation) return;
      setState(() {
        _roster = roster;
        _marks = Map<String, String>.from(marks);
        _savedMarks = Map<String, String>.from(marks);
        _registerLoaded = true;
        _loadingRegister = false;
        _reportRevision++;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingRegister = false;
        _registerError = schoolErrorMessage(error);
      });
    }
  }

  void _mark(String studentId, String status) {
    if (!_canEdit || _saving || !_registerLoaded) return;
    setState(() {
      _marks[studentId] = status;
    });
  }

  void _markRemainingPresent() {
    if (!_canEdit || !_registerLoaded || _saving) return;
    setState(() {
      for (final student in _roster) {
        if (!attendanceStatuses.contains(_marks[student.id])) {
          _marks[student.id] = 'present';
        }
      }
    });
  }

  Future<void> _save() async {
    final classId = _classId;
    final changes = _pending;
    if (!_canEdit || _saving || classId == null || changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (widget.saveOverride != null) {
        await widget.saveOverride!(classId, _date, changes);
      } else {
        await _attendance.saveChanges(
          classId: classId, date: _date, changes: changes,
          forAttendanceTeacher: _teacherClass);
      }
      if (!mounted) return;
      setState(() {
        _savedMarks.addAll(changes);
        _reportRevision++;
      });
      final totalUnmarked = _summary.unmarked;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          totalUnmarked == 0
              ? 'Attendance saved. All ${_roster.length} students marked.'
              : 'Saved ${changes.length} change(s). ${totalUnmarked} students still unmarked.',
        )),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Attendance not fully saved: ${schoolErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _indicator(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${label}: ${value}',
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _studentCard(StudentRecord student) {
    final color = Theme.of(context).colorScheme;
    final selected = _marks[student.id] ?? 'unmarked';
    final name = student.fullName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Card(
      key: Key('attendance_student_${student.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: color.primaryContainer,
                  foregroundColor: color.onPrimaryContainer,
                  child: Text(initial,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        'Roll ${student.rollNo.isEmpty ? "—" : student.rollNo} · ${student.admissionNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10, color: color.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected != 'unmarked')
                  Icon(Icons.check_circle_outline_rounded, size: 18,
                    color: color.primary),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final status in attendanceStatuses)
                  ChoiceChip(
                    key: Key('mark_${student.id}_${status}'),
                    label: Text(attendanceStatusLabels[status]!,
                      style: const TextStyle(fontSize: 11)),
                    selected: selected == status,
                    onSelected: _canEdit && !_saving
                        ? (_) => _mark(student.id, status)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                if (selected != 'unmarked' && _canEdit)
                  TextButton(
                    onPressed: _saving ? null
                        : () => _mark(student.id, 'unmarked'),
                    child: const Text('Clear', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusView(String title, String detail,
      {IconData icon = Icons.info_outline_rounded, VoidCallback? retry}) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: color.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
            if (retry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final summary = _summary;
    final visible = _roster.where((student) {
      if (_unmarkedOnly &&
          attendanceStatuses.contains(_marks[student.id])) return false;
      if (_search.isEmpty) return true;
      final search = _search.toLowerCase();
      return student.fullName.toLowerCase().contains(search) ||
          student.rollNo.contains(search) ||
          student.admissionNo.toLowerCase().contains(search);
    }).toList();
    final changes = _pending.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student attendance', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Daily Register', icon: Icon(Icons.edit_calendar_outlined)),
            Tab(text: 'Reports & Analytics', icon: Icon(Icons.bar_chart_outlined)),
          ],
        ),
        actions: [
          if (canManageAttendance(widget.role))
            IconButton(
              tooltip: 'Assign class attendance teachers',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) =>
                  AttendanceTeacherAssignmentsPage(role: widget.role))),
              icon: const Icon(Icons.assignment_ind_outlined),
            ),
          IconButton(
            tooltip: 'Reload attendance',
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: _tabs.index == 0 ? SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 670),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canEdit && changes > 0 && !_saving
                      ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(_saving
                      ? 'Saving attendance…'
                      : changes > 0
                          ? 'Save attendance (${changes} changes)'
                          : 'Attendance saved'),
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 950),
                child: CustomScrollView(
              key: const Key('attendance_scroll_view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Daily class register',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          _teacherClass
                            ? 'Only your assigned class is shown. Unmarked is not absent.'
                            : 'Choose a class and date. Unmarked is not the same as absent.',
                          style: TextStyle(
                            fontSize: 11, color: color.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        if (_classError != null) ...[
                          Text(_classError!, style: TextStyle(
                            color: color.error, fontSize: 12)),
                          TextButton(
                            onPressed: _loadClasses,
                            child: const Text('Retry class list'),
                          ),
                        ],
                        if (_classesLoading)
                          const LinearProgressIndicator(minHeight: 2),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: const Key('attendance_class_selector'),
                                value: _classId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Class & section'),
                                items: _classes.map((c) =>
                                    DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.label,
                                        overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: _saving || _classesLoading || _teacherClass
                                    ? null : _changeClass,
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              key: const Key('attendance_date_picker'),
                              onPressed: _saving ? null : _changeDate,
                              icon: const Icon(Icons.calendar_month_outlined,
                                size: 18),
                              label: Text(attendanceDateKey(_date),
                                style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                        if (!_teacherClass && !_classesLoading && _classes.isEmpty) ...[
                          const SizedBox(height: 9),
                          OutlinedButton.icon(
                            onPressed: _openClassSetup,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Create your first class'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _indicator('Present', summary.present, color.primary),
                            _indicator('Absent', summary.absent, color.error),
                            _indicator('Late', summary.late, color.tertiary),
                            _indicator('Leave', summary.leave, color.secondary),
                            _indicator('Unmarked', summary.unmarked,
                              color.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _registerLoaded
                                    ? '${summary.marked} / ${summary.total} marked'
                                    : 'Select a class to begin',
                                style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_roster.isNotEmpty && _canEdit)
                              TextButton.icon(
                                onPressed: _saving ? null
                                    : _markRemainingPresent,
                                icon: const Icon(Icons.done_all, size: 17),
                                label: const Text('Mark remaining present',
                                  style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        TextField(
                          key: const Key('attendance_search_input'),
                          onChanged: (value) =>
                              setState(() => _search = value.trim()),
                          decoration: const InputDecoration(
                            hintText: 'Search student or roll number',
                            prefixIcon: Icon(Icons.search_rounded, size: 20)),
                          ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            FilterChip(
                              label: const Text('Unmarked only',
                                style: TextStyle(fontSize: 11)),
                              selected: _unmarkedOnly,
                              onSelected: (selected) =>
                                  setState(() => _unmarkedOnly = selected),
                            ),
                            const Spacer(),
                            if (_pending.isNotEmpty)
                              Text('${_pending.length} unsaved',
                                style: TextStyle(
                                  fontSize: 11, color: color.error)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loadingRegister)
                  SliverToBoxAdapter(
                    child: _statusView(
                      'Loading attendance',
                      'Reading class roster and saved marks from Firestore.',
                      icon: Icons.hourglass_top_rounded),
                  )
                else if (_registerError != null)
                  SliverToBoxAdapter(
                    child: _statusView(
                      'Could not load register',
                      _registerError!,
                      icon: Icons.cloud_off_outlined,
                      retry: _loadRegister),
                  )
                else if (!_registerLoaded || _classId == null)
                  SliverToBoxAdapter(
                    child: _statusView(
                      'Select a class',
                      'The selected class will show its active students here.',
                      icon: Icons.school_outlined),
                  )
                else if (_roster.isEmpty)
                  SliverToBoxAdapter(
                    child: _statusView(
                      'No active students in this class',
                      'Admit students to this class before taking attendance.',
                      icon: Icons.groups_outlined),
                  )
                else if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: _statusView(
                      'No matching students',
                      'Change the search or unmarked-only filter.',
                      icon: Icons.search_off_rounded),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _studentCard(visible[index]),
                    ),
                  ),
              ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _classId == null || !_registerLoaded
                ? Center(child: Text(_classesLoading
                    ? 'Loading class attendance…'
                    : _registerError ?? 'Choose a class in Daily Register first.'))
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 950),
                      child: AttendanceReportsTab(
                        key: ValueKey(
                          'attendance_report_${_classId}_${attendanceDateKey(_date)}_$_reportRevision'),
                        classId: _classId!,
                        classLabel: _classes
                            .where((schoolClass) => schoolClass.id == _classId)
                            .map((schoolClass) => schoolClass.label)
                            .firstOrNull ?? _classId!,
                        roster: _roster,
                        referenceDate: _date,
                        forTeacher: _teacherClass,
                        marksLoader: widget.marksLoader,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
