import 'package:flutter/material.dart';

import '../data/attendance_class_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import '../data/staff_repository.dart';

class AttendanceTeacherAssignmentsPage extends StatefulWidget {
  const AttendanceTeacherAssignmentsPage({
    super.key, this.role = 'owner', this.initialStaffId,
    this.staffStream, this.classesStream, this.assignmentsStream,
    this.onAssign, this.onRemove,
  });
  final String role;
  final String? initialStaffId;
  final Stream<List<StaffMember>>? staffStream;
  final Stream<List<SchoolClass>>? classesStream;
  final Stream<List<AttendanceClassAssignment>>? assignmentsStream;
  final Future<void> Function(String staffId, String classId)? onAssign;
  final Future<void> Function(String classId)? onRemove;

  @override
  State<AttendanceTeacherAssignmentsPage> createState() =>
      _AttendanceTeacherAssignmentsPageState();
}

class _AttendanceTeacherAssignmentsPageState
    extends State<AttendanceTeacherAssignmentsPage> {
  late final _repo = AttendanceClassRepository();
  late final _school = SchoolRepository();
  late final Stream<List<StaffMember>> _staff =
      widget.staffStream ?? StaffRepository().watchStaff();
  late final Stream<List<SchoolClass>> _classes =
      widget.classesStream ?? _school.watchClasses();
  late final Stream<List<AttendanceClassAssignment>> _assignments =
      widget.assignmentsStream ?? _repo.watchAssignments();
  bool _saving = false;
  bool get _allowed => widget.role == 'owner' || widget.role == 'principal';

  Future<void> _assign(List<StaffMember> staff, List<SchoolClass> classes,
      {String? initialClassId}) async {
    if (!_allowed || _saving) return;
    final teachers = staff.where((s) => s.isTeacher && s.active).toList();
    final activeClasses = classes.where((c) => c.active).toList();
    if (teachers.isEmpty || activeClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Create an active teacher and class first.')));
      return;
    }
    final chosen = await showDialog<({String staffId, String classId})>(
      context: context,
      builder: (_) => _PickAttendanceClass(
        teachers: teachers, classes: activeClasses,
        initialStaffId: widget.initialStaffId,
        initialClassId: initialClassId));
    if (chosen == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (widget.onAssign != null) {
        await widget.onAssign!(chosen.staffId, chosen.classId);
      } else {
        // Ensure existing students have privacy-safe roster projections.
        await _school.syncClassRosters();
        await _repo.assignClass(
          staffId: chosen.staffId, classId: chosen.classId);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance teacher assigned.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(AttendanceClassAssignment assignment) async {
    if (!_allowed || _saving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove attendance teacher?'),
        content: Text('Remove ${assignment.staffName} from '
            '${assignment.className}? Saved attendance will be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm_remove_attendance_teacher'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove assignment')),
        ],
      ));
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      if (widget.onRemove != null) {
        await widget.onRemove!(assignment.classId);
      } else {
        await _repo.removeClass(assignment.classId);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance teacher removed.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const Scaffold(body: Center(child:
      Text('Only the owner or principal can assign attendance teachers.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Class attendance teachers')),
      body: StreamBuilder<List<StaffMember>>(
        stream: _staff,
        builder: (context, staffSnap) {
          if (staffSnap.hasError) return Center(
            child: Text(schoolErrorMessage(staffSnap.error!)));
          if (!staffSnap.hasData) return const Center(
            child: CircularProgressIndicator());
          return StreamBuilder<List<SchoolClass>>(
            stream: _classes,
            builder: (context, classSnap) {
              if (classSnap.hasError) return Center(
                child: Text(schoolErrorMessage(classSnap.error!)));
              if (!classSnap.hasData) return const Center(
                child: CircularProgressIndicator());
              return StreamBuilder<List<AttendanceClassAssignment>>(
                stream: _assignments,
                builder: (context, assignSnap) {
                  if (assignSnap.hasError) return Center(
                    child: Text(schoolErrorMessage(assignSnap.error!)));
                  if (!assignSnap.hasData) return const Center(
                    child: CircularProgressIndicator());
                  final classes = classSnap.data!.where((c) => c.active).toList()
                    ..sort((a, b) => a.label.compareTo(b.label));
                  final byClass = {
                    for (final item in assignSnap.data!) item.classId: item
                  };
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Each teacher manages attendance for '
                            'one class only. Subject teaching is independent.',
                            style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('assign_attendance_teacher'),
                            onPressed: _saving ? null : () =>
                              _assign(staffSnap.data!, classes),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Assign attendance class')),
                        ]),
                    ),
                    Expanded(child: classes.isEmpty
                      ? const Center(child: Text('Add an active class first.'))
                      : ListView.builder(
                          itemCount: classes.length,
                          itemBuilder: (context, index) {
                            final schoolClass = classes[index];
                            final current = byClass[schoolClass.id];
                            return Card(child: ListTile(
                              key: Key('attendance_class_${schoolClass.id}'),
                              title: Text(schoolClass.label),
                              subtitle: Text(current == null
                                ? 'No attendance teacher assigned'
                                : 'Attendance teacher: ${current.staffName}'),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Attendance class options',
                                enabled: !_saving,
                                onSelected: (option) {
                                  if (option == 'assign') {
                                    _assign(staffSnap.data!, classes,
                                      initialClassId: schoolClass.id);
                                  } else if (current != null) {
                                    _remove(current);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'assign',
                                    child: Text(current == null
                                      ? 'Assign teacher' : 'Change teacher')),
                                  if (current != null) const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove teacher')),
                                ],
                              ),
                            ));
                          },
                        )),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PickAttendanceClass extends StatefulWidget {
  const _PickAttendanceClass({required this.teachers, required this.classes,
    this.initialStaffId, this.initialClassId});
  final List<StaffMember> teachers;
  final List<SchoolClass> classes;
  final String? initialStaffId;
  final String? initialClassId;

  @override
  State<_PickAttendanceClass> createState() => _PickAttendanceClassState();
}

class _PickAttendanceClassState extends State<_PickAttendanceClass> {
  late String _staffId = widget.initialStaffId ?? widget.teachers.first.id;
  late String _classId = widget.initialClassId ?? widget.classes.first.id;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Assign attendance class'),
    content: SizedBox(width: 400, child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('attendance_teacher_picker'),
          initialValue: _staffId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Teacher *'),
          items: widget.teachers.map((teacher) => DropdownMenuItem(
            value: teacher.id, child: Text(teacher.fullName))).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _staffId = value);
          }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('attendance_class_picker'),
          initialValue: _classId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class *'),
          items: widget.classes.map((schoolClass) => DropdownMenuItem(
            value: schoolClass.id, child: Text(schoolClass.label))).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _classId = value);
          }),
        const SizedBox(height: 10),
        const Text('Reassigning automatically replaces previous attendance '
          'responsibilities. Existing attendance records stay saved.',
          style: TextStyle(fontSize: 12)),
      ],
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Cancel')),
      FilledButton(
        key: const Key('save_attendance_teacher'),
        onPressed: () => Navigator.pop(context,
          (staffId: _staffId, classId: _classId)),
        child: const Text('Save assignment')),
    ],
  );
}
