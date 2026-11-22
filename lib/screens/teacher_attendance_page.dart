import 'package:flutter/material.dart';

import '../data/attendance_class_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import 'attendance_page.dart';

/// A linked teacher can open only their designated attendance class.
class TeacherAttendancePage extends StatefulWidget {
  const TeacherAttendancePage({
    super.key,
    required this.staffId,
    this.assignmentStream,
    this.rosterLoader,
    this.marksLoader,
    this.saveOverride,
  });

  final String staffId;
  final Stream<AttendanceClassAssignment?>? assignmentStream;
  final Future<List<StudentRecord>> Function(String classId)? rosterLoader;
  final Future<Map<String, String>> Function(String classId, DateTime date)?
      marksLoader;
  final AttendanceSaveCallback? saveOverride;

  @override
  State<TeacherAttendancePage> createState() => _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends State<TeacherAttendancePage> {
  late final Stream<AttendanceClassAssignment?> _assignment =
      widget.assignmentStream ??
          AttendanceClassRepository().watchForTeacher(widget.staffId);

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<AttendanceClassAssignment?>(
        stream: _assignment,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Scaffold(
            appBar: AppBar(title: const Text('My class attendance')),
            body: Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(schoolErrorMessage(snapshot.error!)))));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(
              child: CircularProgressIndicator()));
          }
          final assigned = snapshot.data;
          if (assigned == null || !assigned.active ||
              assigned.staffId != widget.staffId) {
            return Scaffold(
              appBar: AppBar(title: const Text('My class attendance')),
              body: const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No attendance class has been assigned to you. '
                  'Ask the owner or principal to assign one class.'))),
            );
          }
          // This class list is constructed solely from the teacher's own
          // permission-checked link, never from a global classes query.
          return AttendancePage(
            key: ValueKey('assigned_attendance_${assigned.classId}'),
            role: 'teacher',
            assignedClass: SchoolClass(
              id: assigned.classId,
              name: assigned.className.isEmpty
                  ? assigned.classId : assigned.className,
              section: '',
              active: true,
            ),
            rosterLoader: widget.rosterLoader,
            marksLoader: widget.marksLoader,
            saveOverride: widget.saveOverride,
          );
        },
      );
}
