import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/school_errors.dart';

class TeacherExaminationsPage extends StatelessWidget {
  const TeacherExaminationsPage({super.key, required this.staffId});
  final String staffId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('examinations')
        .where('staffId', isEqualTo: staffId)
        .where('active', isEqualTo: true)
        .limit(100).snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Examinations & marks',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ExamMessage(
            message: schoolErrorMessage(snapshot.error!),
            icon: Icons.cloud_off_outlined);
          if (!snapshot.hasData) return const _ExamMessage(
            message: 'Loading examinations…',
            icon: Icons.hourglass_top_rounded);
          final exams = snapshot.data!.docs;
          if (exams.isEmpty) return const _ExamMessage(
            message: 'No examinations have been published for your assigned subjects yet.',
            icon: Icons.fact_check_outlined);
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: exams.length,
            itemBuilder: (context, index) {
              final doc = exams[index];
              final data = doc.data();
              return Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.fact_check_outlined)),
                  title: Text((data['title'] as String?) ?? 'Examination',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${data['className'] ?? data['classId']} • ${data['subject']}\n'
                    'Date: ${data['examDate'] ?? 'Not set'} • Max: ${data['maxMarks']}',
                    style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TeacherExamMarksPage(
                      examId: doc.id, exam: data)),
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

class TeacherExamMarksPage extends StatefulWidget {
  const TeacherExamMarksPage({
    super.key, required this.examId, required this.exam,
  });
  final String examId;
  final Map<String, dynamic> exam;

  @override
  State<TeacherExamMarksPage> createState() => _TeacherExamMarksPageState();
}

class _TeacherExamMarksPageState extends State<TeacherExamMarksPage> {
  final _db = FirebaseFirestore.instance;
  final _controllers = <String, TextEditingController>{};
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _rosterFuture;
  bool _saving = false;
  String? _error;

  String get _classId => (widget.exam['classId'] as String?) ?? '';
  double get _maxMarks => (widget.exam['maxMarks'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _rosterFuture = _loadRoster();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadRoster() async {
    final roster = await _db.collection('class_rosters').doc(_classId)
        .collection('students').where('active', isEqualTo: true)
        .limit(1000).get(const GetOptions(source: Source.server));
    final marks = await _db.collection('examinations').doc(widget.examId)
        .collection('marks').get(const GetOptions(source: Source.server));
    for (final mark in marks.docs) {
      final score = mark.data()['score'];
      _controllers[mark.id] = TextEditingController(
        text: score is num ? score.toString() : '');
    }
    for (final student in roster.docs) {
      _controllers.putIfAbsent(student.id, () => TextEditingController());
    }
    return roster.docs;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> roster,
  ) async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Sign in again to save examination marks.');
      return;
    }
    final batch = _db.batch();
    var count = 0;
    for (final student in roster) {
      final text = _controllers[student.id]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final score = double.tryParse(text);
      if (score == null || score < 0 || score > _maxMarks) {
        setState(() => _error = 'Marks must be a number from 0 to ${_maxMarks}.');
        return;
      }
      batch.set(
        _db.collection('examinations').doc(widget.examId)
            .collection('marks').doc(student.id),
        {
          'examId': widget.examId,
          'studentId': student.id,
          'classId': _classId,
          'score': score,
          'teacherUid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      count++;
    }
    if (count == 0) {
      setState(() => _error = 'Enter at least one student mark before saving.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Examination marks saved.')));
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(
      (widget.exam['title'] as String?) ?? 'Examination marks',
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
    body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _rosterFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ExamMessage(
          message: schoolErrorMessage(snapshot.error!),
          icon: Icons.cloud_off_outlined);
        if (!snapshot.hasData) return const _ExamMessage(
          message: 'Loading student roll…',
          icon: Icons.hourglass_top_rounded);
        final roster = snapshot.data!;
        if (roster.isEmpty) return const _ExamMessage(
          message: 'No active students are available in this class roster. Ask the owner to open Examinations and sync the student list.',
          icon: Icons.groups_outlined);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Enter marks out of ${_maxMarks}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: roster.length,
            itemBuilder: (context, index) {
              final data = roster[index].data();
              return Card(
                margin: const EdgeInsets.only(bottom: 7),
                child: ListTile(
                  title: Text((data['fullName'] as String?) ?? 'Student',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: Text('Roll no: ${data['rollNo'] ?? '—'}',
                    style: const TextStyle(fontSize: 10)),
                  trailing: SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _controllers[roster[index].id],
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(labelText: 'Marks', isDense: true),
                    ),
                  ),
                ),
              );
            },
          )),
          if (_error != null) Padding(
            padding: const EdgeInsets.all(10),
            child: Text(_error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error, fontSize: 12))),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 14, 12),
              child: SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(roster),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save marks'),
                ),
              ),
            ),
          ),
        ]);
      },
    ),
  );
}

class _ExamMessage extends StatelessWidget {
  const _ExamMessage({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12)),
      ]),
    ),
  );
}
