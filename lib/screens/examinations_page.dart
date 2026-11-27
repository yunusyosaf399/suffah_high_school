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
import 'exam_term_overview.dart';

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

  Future<void> _create({bool addClass = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if(_filter=='term' && !canScheduleFormalExams(widget.role)) {_message('Only the owner or principal can create formal examinations.');return;}
      final cycle = _filter == 'term' ? await _repo.loadActiveTerm() : null;
      if (_filter == 'term' && cycle != null && !addClass) {
        _message('An examination is active. Close it before creating another, or add a class to its date sheet.'); return;
      }
      if (addClass && cycle == null) { _message('No active examination.'); return; }
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
          teacherNames: names, classSubjects: catalog, classNames: classNames, activeCycle:cycle,
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
      if (action == 'reschedule') { await _reschedule(doc); return; }
      final confirmed = await showDialog<bool>(context: context, builder: (context) =>
        AlertDialog(title: Text(action == 'release' ? 'Release subject results?' : 'Confirm change'),
          content: Text(action == 'release' ? 'Review the marks first. This releases this subject result internally.' :
            'Update the status of this paper?'),
          actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context,true), child: const Text('Confirm'))]));
      if (confirmed != true) return;
      if (action == 'release' || action == 'reopen') {
        await _repo.setTermResult(doc.id,release:action=='release');
        _message('Paper updated.'); return;
      }
      await doc.reference.update({
        if (action == 'archive' || action == 'restore') 'active': action == 'restore',
        if (action == 'release' || action == 'reopen') 'resultStatus': action == 'release' ? 'released' : 'draft',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _message('Paper updated.');
    } catch (error) { _message(schoolErrorMessage(error)); }
  }

  Future<void> _closeTerm(String id) async {
    final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Declare and close examination?'),
      content:const Text('Every planned class and paper must be complete. Closing permanently locks this annual term and permits a new examination.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Declare & close'))]));
    if(confirmed!=true)return;
    try {await _repo.closeTerm(id);_message('Examination declared and closed.');}
    catch(error){_message(schoolErrorMessage(error));}
  }

  Future<void> _holiday(String id) async {
    try {
      final cycle=await _repo.loadActiveTerm();
      if(!mounted || cycle==null || cycle['id']!=id)return;
      final off=examStringMap(cycle['excludedDates']);
      final entries=off.entries.toList()..sort((a,b)=>a.key.compareTo(b.key));
      final choice=await showDialog<String>(context:context,builder:(context)=>AlertDialog(
        title:const Text('School holidays & closures'),
        content:SizedBox(width:480,child:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,children:[
            if(entries.isEmpty) const Text('No excluded dates.'),
            for(final entry in entries) ListTile(
              title:Text(entry.key),subtitle:Text(entry.value),
              trailing:IconButton(tooltip:'Remove closure',icon:const Icon(Icons.delete_outline),
                onPressed:()=>Navigator.pop(context,entry.key))),
          ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,'add'),child:const Text('Add closure'))]));
      if(choice==null || !mounted)return;
      if(choice!='add') {
        final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
          title:const Text('Remove excluded date?'),
          content:Text('$choice will become available again. Previously rescheduled papers stay on their new dates.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
            FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Remove'))]));
        if(confirmed==true) {
          await _repo.removeSchoolClosure(id,choice);
          _message('Closure removed.');
        }
        return;
      }
      final now=schoolExamNow();
      final today=DateTime(now.year,now.month,now.day);
      final day=await showDatePicker(context:context,initialDate:today,firstDate:today,lastDate:DateTime(2100));
      if(day==null || !mounted)return;
      final reason=await showDialog<String>(context:context,builder:(_)=>const _ReasonDialog(title:'School holiday / closure',label:'Reason (Eid, disaster, public holiday, etc.)'));
      if(reason==null)return;
      await _repo.markSchoolClosure(id,examDateKey(day),reason);
      _message('Closure saved. Reschedule any affected papers using their menu.');
    } catch(error){_message(schoolErrorMessage(error));}
  }

  Future<void> _reschedule(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    final cycle=await _repo.loadActiveTerm();
    if(!mounted || cycle==null || cycle['id']!=doc.data()['cycleId']) {
      _message('This examination is not active.');return;
    }
    final now=schoolExamNow();
    final today=DateTime(now.year,now.month,now.day);
    final d=doc.data();
    final old=DateTime.tryParse(d['examDate'].toString()) ?? today;
    final first=old.isAfter(today)?old:today;
    final off=examStringMap(cycle['excludedDates']);
    final slots=examStringMap(cycle['slots']);
    bool available(DateTime date) {
      final key=examDateKey(date);
      final occupied=slots[examSlot(d['classId'].toString(),key)];
      return !off.containsKey(key) && (cycle['skipSunday']!=true || date.weekday!=DateTime.sunday)
        && (occupied==null || occupied==doc.id);
    }
    var initial=first;
    while(!available(initial) && initial.isBefore(DateTime(2100))) {initial=DateTime(initial.year,initial.month,initial.day+1);}
    if(!available(initial)) {_message('No available dates.');return;}
    final date=await showDatePicker(context:context,initialDate:initial,firstDate:first,
      lastDate:DateTime(2100),selectableDayPredicate:available);
    if(date==null || !mounted)return;
    final start=d['startMinute'] as int? ?? 540;
    final end=d['endMinute'] as int? ?? 600;
    final timing=await showDialog<_RescheduleDetails>(context:context,builder:(_)=>_RescheduleDialog(start:start,end:end));
    if(timing==null)return;
    try {
      await _repo.reschedulePaper(doc.id,date,timing.start,timing.end,timing.reason);
      _message('Paper rescheduled to ${examDateKey(date)}.');
    } catch(error){_message(schoolErrorMessage(error));}
  }

  Widget _paper(QueryDocumentSnapshot<Map<String,dynamic>> doc) {
    final d = doc.data();
    final status = d['resultStatus'] ?? 'draft';
    final active = d['active'] == true;
    final managed = d['cycleId'] is String;
    return ListTile(
      title: Text('${d['className'] ?? d['classId']} • ${d['subject'] ?? 'Subject'} • ${d['paperType'] ?? 'Theory'}'),
      subtitle: Text('${d['examDate'] ?? 'No date'} • ${examTiming(d)} • ${d['maxMarks']} marks\n'
        'Results: $status${active ? '' : ' • Archived'}${d['rescheduleReason'] == null ? '' : '\nRescheduled: ${d['rescheduleReason']}'}'),
      trailing: PopupMenuButton<String>(onSelected: (v) => _setPaper(doc,v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'results', child: Text('Review marks')),
          if (active && status == 'submitted') const PopupMenuItem(value: 'release', child: Text('Release results')),
          if (active && status != 'draft') const PopupMenuItem(value: 'reopen', child: Text('Reopen marks')),
          if (managed && active && status=='draft' && examStrings(d['markedStudentIds']).isEmpty)
            const PopupMenuItem(value:'reschedule',child:Text('Reschedule paper')),
          if (!managed) PopupMenuItem(value: active ? 'archive' : 'restore', child: Text(active ? 'Archive paper' : 'Restore paper')),
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
        groups.putIfAbsent((d['cycleId'] ?? d['sessionId'] ?? doc.id).toString(), () => []).add(doc);
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
            key: PageStorageKey(group.first.data()['cycleId'] ?? group.first.data()['sessionId'] ?? group.first.id),
            leading: const Icon(Icons.event_note_outlined),
            title: Text((d['sessionTitle'] ?? d['title'] ?? 'Examination').toString()),
            subtitle: Text('${d['cycleId'] == null ? d['className'] ?? d['classId'] : 'School-wide term'} • ${group.length} papers\n'
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
    if (!canManageExamCentre(widget.role)) return const Scaffold(body: Center(child: Text('Access denied.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Examinations'),
        actions: [
          if (_admissionsAdmin) IconButton(tooltip: 'Sync student rosters & teachers', onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync)),
          if (widget.role == 'examiner') IconButton(tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
        ]),
      floatingActionButton: _filter == 'homework' || (_filter=='term' && !canScheduleFormalExams(widget.role)) ? null : FloatingActionButton.extended(
        onPressed: _busy ? null : () => _create(), icon: const Icon(Icons.add), label: const Text('Create assessment')),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final item in const [('term','Term Exams'),('test','Class Tests'),('assignment','Assignments'),('homework','Homework')])
            ChoiceChip(label: Text(item.$2), selected: _filter == item.$1,
              onSelected: (_) => setState(() => _filter = item.$1)),
        ])),
        if (_admissionsAdmin) const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Sync rosters and teacher names before scheduling if school records changed.', style: TextStyle(fontSize: 12))),
        if (_filter=='term') ExamTermOverview(onAddClass:_busy || !canScheduleFormalExams(widget.role)?null:()=>_create(addClass:true),
          onClose:_closeTerm,onHoliday:_holiday,compact:true),
        Expanded(child: _filter == 'assignment' || _filter == 'homework' ? _workList() : _paperList()),
      ])),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title,required this.label});
  final String title,label;
  @override
  State<_ReasonDialog> createState()=>_ReasonDialogState();
}
class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason=TextEditingController();
  @override
  void dispose(){_reason.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),
    content:TextField(controller:_reason,maxLength:200,autofocus:true,onChanged:(_)=>setState((){}),
      decoration:InputDecoration(labelText:widget.label)),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:_reason.text.trim().isEmpty?null:()=>Navigator.pop(context,_reason.text.trim()),child:const Text('Save'))]);
}
class _RescheduleDetails {
  const _RescheduleDetails(this.start,this.end,this.reason);
  final int start,end;
  final String reason;
}
class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({required this.start,required this.end});
  final int start,end;
  @override
  State<_RescheduleDialog> createState()=>_RescheduleDialogState();
}
class _RescheduleDialogState extends State<_RescheduleDialog> {
  late int _start=widget.start,_end=widget.end;
  final _reason=TextEditingController();
  @override
  void dispose(){_reason.dispose();super.dispose();}
  Future<void> _pick(bool start) async {
    final minute=start?_start:_end;
    final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:minute~/60,minute:minute%60));
    if(t!=null && mounted)setState((){if(start){_start=t.hour*60+t.minute;}else{_end=t.hour*60+t.minute;}});
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(scrollable:true,title:const Text('Reschedule paper'),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(title:const Text('Start time (PKT)'),subtitle:Text(examClock(_start)),onTap:()=>_pick(true)),
      ListTile(title:const Text('End time (PKT)'),subtitle:Text(examClock(_end)),onTap:()=>_pick(false)),
      TextField(controller:_reason,maxLength:200,onChanged:(_)=>setState((){}),
        decoration:const InputDecoration(labelText:'Reason for rescheduling')),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:_reason.text.trim().isEmpty || _end<=_start || _end-_start>600?null:
        ()=>Navigator.pop(context,_RescheduleDetails(_start,_end,_reason.text.trim())),child:const Text('Confirm reschedule'))]);
}
