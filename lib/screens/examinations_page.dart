import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/class_subject_repository.dart';
import '../data/examination_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import '../data/staff_repository.dart';
import 'exam_creation_wizard.dart';
import 'teacher_examinations_page.dart';

class ExaminationsPage extends StatefulWidget {
  const ExaminationsPage({super.key, required this.role});
  final String role;
  @override
  State<ExaminationsPage> createState() => _ExaminationsPageState();
}

class _ExaminationsPageState extends State<ExaminationsPage> {
  late final _repo = ExaminationRepository();
  late final _db = _repo.db;
  late final _exams = _db.collection('examinations').snapshots();
  late final _work = _db.collection('classwork').snapshots();
  bool _busy = false;
  String _filter = 'term';
  bool get _admissionsAdmin => widget.role == 'owner' || widget.role == 'principal';

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sync() async {
    if (!_admissionsAdmin || _busy) return;
    setState(() => _busy = true);
    try {
      final links = await StaffRepository().syncTeacherClassLinks();
      final count = await SchoolRepository().syncClassRosters();
      final names = await _repo.syncTeacherNames();
      _message('Synced $count students, $links class links and $names teacher names.');
    } catch (error) { _message(schoolErrorMessage(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final assignments = await StaffRepository().watchAssignments().first.timeout(const Duration(seconds: 20));
      final nameDocs = await _db.collection('exam_teacher_directory').get();
      final names = <String,String>{for (final doc in nameDocs.docs)
        doc.id: (doc.data()['name'] ?? doc.id).toString()};
      if (_admissionsAdmin) {
        final staff = await StaffRepository().watchStaff().first.timeout(const Duration(seconds: 20));
        for (final person in staff) { if (person.isTeacher && person.active) names[person.id] = person.fullName; }
      }
      final classDocs = await _db.collection('classes').get(const GetOptions(source: Source.server));
      final classes = classDocs.docs.map(SchoolClass.fromSnapshot).where((c)=>c.active).toList();
      final classNames = {for(final c in classes) c.id:c.label};
      final inactiveTeachers = nameDocs.docs.where((d)=>d.data()['active']==false).map((d)=>d.id).toSet();
      final active = assignments.where((a)=>a.active && classNames.containsKey(a.classId)
        && !inactiveTeachers.contains(a.staffId)).toList();
      if(classes.isEmpty) { _message('Create an active class first.'); return; }
      final catalog = <String,List<ClassSubject>>{};
      await Future.wait(classes.map((c) async {
        final docs = await _db.collection('classes').doc(c.id).collection('subjects')
          .get(const GetOptions(source: Source.server));
        catalog[c.id] = docs.docs.map(ClassSubject.fromSnapshot).where((s)=>s.active).toList();
      }));
      if (!mounted) return;
      setState(() => _busy = false);
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ExamCreationWizard(role: widget.role, assignments: active,
          teacherNames: names, classSubjects: catalog, classNames: classNames,
          initialKind: _filter == 'assignment' ? 'assignment' : _filter == 'test' ? 'test' : 'term')));
      if (saved == true) _message('Assessment published.');
    } catch (error) { _message(schoolErrorMessage(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _setPaper(QueryDocumentSnapshot<Map<String,dynamic>> doc, String action) async {
    try {
      if (action == 'results') {
        await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
          TeacherExamMarksPage(examId: doc.id, exam: doc.data(), readOnly: true)));
        return;
      }
      final confirmed = await showDialog<bool>(context: context, builder: (context) =>
        AlertDialog(title: Text(action == 'release' ? 'Release subject results?' : 'Confirm change'),
          content: Text(action == 'release' ? 'Review the marks first. This releases this subject result internally.' :
            'Update the status of this paper?'),
          actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context,true), child: const Text('Confirm'))]));
      if (confirmed != true) return;
      await doc.reference.update({
        if (action == 'archive' || action == 'restore') 'active': action == 'restore',
        if (action == 'release' || action == 'reopen') 'resultStatus': action == 'release' ? 'released' : 'draft',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _message('Paper updated.');
    } catch (error) { _message(schoolErrorMessage(error)); }
  }

  Widget _paper(QueryDocumentSnapshot<Map<String,dynamic>> doc) {
    final d = doc.data();
    final status = d['resultStatus'] ?? 'draft';
    final active = d['active'] == true;
    return ListTile(
      title: Text('${d['subject'] ?? 'Subject'} • ${d['paperType'] ?? 'Theory'}'),
      subtitle: Text('${d['examDate'] ?? 'No date'} • ${d['maxMarks']} marks\n'
        'Results: $status${active ? '' : ' • Archived'}'),
      trailing: PopupMenuButton<String>(onSelected: (v) => _setPaper(doc,v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'results', child: Text('Review marks')),
          if (active && status == 'submitted') const PopupMenuItem(value: 'release', child: Text('Release results')),
          if (active && status != 'draft') const PopupMenuItem(value: 'reopen', child: Text('Reopen marks')),
          PopupMenuItem(value: active ? 'archive' : 'restore', child: Text(active ? 'Archive paper' : 'Restore paper')),
        ]),
    );
  }

  Widget _paperList() => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream: _exams,
    builder: (context,snapshot) {
      if (snapshot.hasError) return Center(child: Text(schoolErrorMessage(snapshot.error!)));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final groups = <String,List<QueryDocumentSnapshot<Map<String,dynamic>>>>{};
      for (final doc in snapshot.data!.docs) {
        final d = doc.data();
        final kind = d['kind'] ?? 'term';
        if (kind != _filter) continue;
        groups.putIfAbsent((d['sessionId'] ?? doc.id).toString(), () => []).add(doc);
      }
      final ordered = groups.values.toList()..sort((a,b) =>
        (b.first.data()['startDate'] ?? b.first.data()['examDate'] ?? '').toString().compareTo(
        (a.first.data()['startDate'] ?? a.first.data()['examDate'] ?? '').toString()));
      if (ordered.isEmpty) return const Center(child: Text('No assessments in this section yet.'));
      return ListView.builder(padding: const EdgeInsets.fromLTRB(14,8,14,90),
        itemCount: ordered.length, itemBuilder: (context,index) {
          final group = ordered[index]..sort((a,b) => (a.data()['examDate'] ?? '').toString().compareTo((b.data()['examDate'] ?? '').toString()));
          final d = group.first.data();
          return Card(child: ExpansionTile(
            key: PageStorageKey(group.first.data()['sessionId'] ?? group.first.id),
            leading: const Icon(Icons.event_note_outlined),
            title: Text((d['sessionTitle'] ?? d['title'] ?? 'Examination').toString()),
            subtitle: Text('${d['className'] ?? d['classId']} • ${group.length} papers\n'
              '${d['startDate'] ?? d['examDate']} – ${d['endDate'] ?? d['examDate']}'),
            children: [for (final doc in group) _paper(doc)],
          ));
        });
    },
  );

  Widget _workList() => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream: _work, builder: (context,snapshot) {
      if (snapshot.hasError) return Center(child: Text(schoolErrorMessage(snapshot.error!)));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs.where((doc) => doc.data()['kind'] == _filter && doc.data()['active'] != false).toList();
      docs.sort((a,b) => (b.data()['dueDate'] ?? '').toString().compareTo((a.data()['dueDate'] ?? '').toString()));
      if (docs.isEmpty) return const Center(child: Text('No classwork recorded yet.'));
      return ListView.builder(padding: const EdgeInsets.fromLTRB(14,8,14,90), itemCount: docs.length,
        itemBuilder: (context,i) {
          final d = docs[i].data();
          return Card(child: ExpansionTile(
            leading: const Icon(Icons.assignment_outlined),
            title: Text((d['title'] ?? 'Classwork').toString()),
            subtitle: Text('${d['className'] ?? d['classId']} • ${d['subject']} • Due ${d['dueDate']}'),
            children: [Padding(padding: const EdgeInsets.all(14), child: Text((d['instructions'] ?? '').toString()))],
          ));
        });
    });

  @override
  Widget build(BuildContext context) {
    if (!canScheduleFormalExams(widget.role)) return const Scaffold(body: Center(child: Text('Access denied.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Examinations'),
        actions: [
          if (_admissionsAdmin) IconButton(tooltip: 'Sync student rosters & teachers', onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync)),
          if (widget.role == 'examiner') IconButton(tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
        ]),
      floatingActionButton: _filter == 'homework' ? null : FloatingActionButton.extended(
        onPressed: _busy ? null : _create, icon: const Icon(Icons.add), label: const Text('Create assessment')),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final item in const [('term','Term Exams'),('test','Class Tests'),('assignment','Assignments'),('homework','Homework')])
            ChoiceChip(label: Text(item.$2), selected: _filter == item.$1,
              onSelected: (_) => setState(() => _filter = item.$1)),
        ])),
        if (_admissionsAdmin) const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Sync rosters and teacher names before scheduling if school records changed.', style: TextStyle(fontSize: 12))),
        Expanded(child: _filter == 'assignment' || _filter == 'homework' ? _workList() : _paperList()),
      ])),
    );
  }
}
