import 'student_avatar.dart';
import '../data/parent_portal_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/examination_repository.dart';
import '../data/staff_repository.dart';
import 'exam_creation_wizard.dart';

class TeacherExaminationsPage extends StatelessWidget {
  const TeacherExaminationsPage({super.key, required this.staffId, this.testsOnly = false});
  final bool testsOnly;
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
      floatingActionButton: testsOnly ? FloatingActionButton.extended(
        onPressed: () async {
          try {
            final assignments = await StaffRepository().watchAssignmentsForStaff(staffId).first.timeout(const Duration(seconds: 20));
            if (!context.mounted) return;
            if (assignments.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No assigned subjects.')));
              return;
            }
            await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
              ExamCreationWizard(role: 'teacher', assignments: assignments, initialKind: 'test')));
          } catch (error) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(schoolErrorMessage(error))));
          }
        }, icon: const Icon(Icons.add), label: const Text('New class test')) : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ExamMessage(
            message: schoolErrorMessage(snapshot.error!),
            icon: Icons.cloud_off_outlined);
          if (!snapshot.hasData) return const _ExamMessage(
            message: 'Loading examinations…',
            icon: Icons.hourglass_top_rounded);
          final exams = snapshot.data!.docs.where((doc) => testsOnly ? doc.data()['kind'] == 'test' : doc.data()['kind'] != 'test').toList();
          exams.sort((a,b) => (b.data()['examDate'] ?? '').toString().compareTo((a.data()['examDate'] ?? '').toString()));
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
                    'Date: ${data['examDate'] ?? 'Not set'} • ${examTiming(data)}\nMax: ${data['maxMarks']} • ${data['resultStatus'] ?? 'draft'}',
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
    super.key, required this.examId, required this.exam, this.readOnly = false,
  });
  final String examId;
  final Map<String, dynamic> exam;
  final bool readOnly;

  @override
  State<TeacherExamMarksPage> createState() => _TeacherExamMarksPageState();
}

class _TeacherExamMarksPageState extends State<TeacherExamMarksPage> {
  final _db = FirebaseFirestore.instance;
  final _controllers = <String, TextEditingController>{};
  late Future<List<_ExamStudent>> _rosterFuture;
  bool get _managed => widget.exam['cycleId'] is String;
  bool _saving = false;
  String? _error;
  late bool _locked = widget.readOnly || (widget.exam['resultStatus'] ?? 'draft') != 'draft';

  String get _classId => (widget.exam['classId'] as String?) ?? '';
  double get _maxMarks => (widget.exam['maxMarks'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _rosterFuture = _loadRoster();
  }

  Future<List<_ExamStudent>> _loadRoster() async {
    final students=<_ExamStudent>[];
    if(_managed) {
      final snapshot=widget.exam['rosterSnapshot'] as Map;
      for(final id in examStrings(widget.exam['expectedStudentIds'])) {
        final data=snapshot[id] as Map;
        students.add(_ExamStudent(id,(data['fullName']??'Student').toString(),(data['rollNo']??'').toString()));
      }
    } else {
      final roster=await _db.collection('class_rosters').doc(_classId)
        .collection('students').where('active',isEqualTo:true)
        .limit(1000).get(const GetOptions(source:Source.server));
      for(final doc in roster.docs) {
        final data=doc.data();
        students.add(_ExamStudent(doc.id,(data['fullName']??'Student').toString(),(data['rollNo']??'').toString()));
      }
    }
    final marks=await _db.collection('examinations').doc(widget.examId)
      .collection('marks').get(const GetOptions(source:Source.server));
    if(!mounted)return students;
    for(final mark in marks.docs) {
      final score=mark.data()['score'];
      _controllers[mark.id]=TextEditingController(text:score is num?score.toString():'');
    }
    for(final student in students) {
      _controllers.putIfAbsent(student.id,()=>TextEditingController());
    }
    return students;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(
    List<_ExamStudent> roster, {bool submit = false}
  ) async {
    if (_saving || _locked) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Sign in again to save examination marks.');
      return;
    }
    if(submit && _managed && (widget.exam['endAt'] as Timestamp).toDate().isAfter(DateTime.now())) {
      setState(()=>_error='The paper has not ended yet. Save draft marks only.'); return;
    }
    final scores = <String,double>{};
    for (final student in roster) {
      final text = _controllers[student.id]?.text.trim() ?? '';
      if (text.isEmpty && !submit) continue;
      final score = double.tryParse(text);
      if (score == null || !score.isFinite || score < 0 || score > _maxMarks) {
        setState(() => _error = submit ? 'Enter valid marks for every student before submitting.' :
          'Marks must be a number from 0 to $_maxMarks.');
        return;
      }
      scores[student.id] = score;
    }
    if (scores.isEmpty) {
      setState(() => _error = 'Enter at least one student mark before saving.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final ref = _db.collection('examinations').doc(widget.examId);
      if(_managed) {
        // Each mark and its completion ledger entry must commit together.
        for(final entry in scores.entries) {
          final batch=_db.batch();
          batch.set(ref.collection('marks').doc(entry.key),{
            'examId':widget.examId,'studentId':entry.key,'classId':_classId,
            'score':entry.value,'teacherUid':user.uid,'updatedAt':FieldValue.serverTimestamp(),
          },SetOptions(merge:true));
          batch.update(ref,{'markedStudentIds':FieldValue.arrayUnion([entry.key]),
            'lastMarkedStudentId':entry.key,'updatedAt':FieldValue.serverTimestamp()});
          await batch.commit();
        }
      } else {
      // Keep rule-dependent document lookups below Firestore batch limits.
      var batch = _db.batch();
      var count = 0;
      for (final entry in scores.entries) {
        batch.set(ref.collection('marks').doc(entry.key), {
          'examId': widget.examId, 'studentId': entry.key, 'classId': _classId,
          'score': entry.value, 'teacherUid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (++count == 2) { await batch.commit(); batch = _db.batch(); count = 0; }
      }
      if (count > 0) await batch.commit();
      }
      var parentSyncPending=false;
      if (submit) {
        await ref.update({'resultStatus': 'submitted', 'submittedBy': user.uid,
          'submittedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
        try{await ParentPortalRepository.syncPaper(_db,widget.examId);}catch(_){parentSyncPending=true;}
      }
      if (mounted) {
        if (submit) setState(() => _locked = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          submit ? (parentSyncPending?'Results submitted. Owner: sync parent records.':'Results submitted for review. Marks are locked.') : 'Examination marks saved.')));
      }
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
    body: FutureBuilder<List<_ExamStudent>>(
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
              child: Text(_locked ? 'Recorded marks out of $_maxMarks' : 'Enter marks out of $_maxMarks',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: roster.length,
            itemBuilder: (context, index) {
              final student = roster[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 7),
                child: ListTile(
                  leading: StudentAvatar(studentId:student.id,name:student.name),
                  title: Text(student.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: Text('Roll no: ${student.rollNo.isEmpty ? '—' : student.rollNo}',
                    style: const TextStyle(fontSize: 10)),
                  trailing: SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _controllers[roster[index].id],
                      enabled: !_saving && !_locked,
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
          if (!_locked) SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OutlinedButton.icon(onPressed: _saving ? null : () => _save(roster),
                  icon: const Icon(Icons.save_outlined), label: const Text('Save draft marks')),
                const SizedBox(height: 8),
                FilledButton(onPressed: _saving ? null : () => _save(roster, submit: true),
                  child: Text(_saving ? 'Saving…' : 'Submit subject results')),
              ]),
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

class _ExamStudent {
  const _ExamStudent(this.id,this.name,this.rollNo);
  final String id,name,rollNo;
}
