import 'package:flutter/material.dart';

import '../data/class_subject_repository.dart';
import '../data/examination_repository.dart';
import '../data/school_errors.dart';
import '../data/staff_repository.dart';

class ExamCreationWizard extends StatefulWidget {
  const ExamCreationWizard({super.key, required this.role, required this.assignments,
    this.teacherNames = const {}, this.classSubjects = const {}, this.classNames = const {}, this.initialKind = 'term', this.initialDateRange, this.activeCycle});
  final String role;
  final List<TeacherAssignment> assignments;
  final Map<String, String> teacherNames;
  final Map<String, List<ClassSubject>> classSubjects;
  final Map<String,String> classNames;
  final String initialKind;
  final DateTimeRange? initialDateRange;
  final Map<String,dynamic>? activeCycle;

  @override
  State<ExamCreationWizard> createState() => _ExamCreationWizardState();
}

class _ExamCreationWizardState extends State<ExamCreationWizard> {
  late final _title = TextEditingController(text: widget.activeCycle?['title']?.toString() ?? '');
  final _instructions = TextEditingController();
  final _marksDefault = TextEditingController(text:'100');
  int _startMinute = 540;
  int _endMinute = 600;
  late int _academicYear = (widget.activeCycle?['academicYear'] as int?) ?? _start.year;
  late final Map<String,String> _excluded = examStringMap(widget.activeCycle?['excludedDates']);
  final _notesDefault = TextEditingController();
  String _typeDefault = 'Theory';
  late bool _skipSunday = widget.activeCycle?['skipSunday'] == true;
  String? _generationError;
  late String _kind = widget.initialKind;
  late String _term = (widget.activeCycle?['category'] as String?) ?? 'First Term';
  String _testType = 'Monthly Test';
  String? _classId;
  final _selectedClasses=<String>{};
  final _publishedClasses=<String>{};
  String? _publishingCycleId;
  bool get _partial => _publishedClasses.isNotEmpty;
  late DateTime _start = DateUtils.dateOnly(widget.initialDateRange?.start ?? DateTime.tryParse(widget.activeCycle?['startDate']?.toString() ?? '') ?? schoolExamNow());
  late DateTime _end = DateUtils.dateOnly(widget.initialDateRange?.end ?? DateTime.tryParse(widget.activeCycle?['endDate']?.toString() ?? '') ?? _start);
  final _papers = <ExamPaperDraft>[];
  int _step = 0;
  bool _saving = false;
  String? _error;
  bool get _assignment => _kind == 'assignment';
  bool get _formal => _kind == 'term';

  @override
  void dispose() {
    _title.dispose(); _instructions.dispose(); _marksDefault.dispose();
    _notesDefault.dispose(); super.dispose();
  }

  String _classLabel(String id) {
    if (widget.classNames.containsKey(id)) return widget.classNames[id]!;
    for (final a in widget.assignments) {
      if (a.classId == id && a.className.isNotEmpty) return a.className;
    }
    return id;
  }

  Future<DateTime?> _pick(DateTime initial, {DateTime? first, DateTime? last}) =>
      showDatePicker(context: context, initialDate: initial,
        firstDate: first ?? DateTime(2000), lastDate: last ?? DateTime(2100));

  List<DateTime> get _days => examCalendarDays(_start,_end,skipSunday:_skipSunday,excludedDates:_excluded.keys.toSet());
  List<ClassSubject> _catalogFor(String? id) => (widget.classSubjects[id] ?? const <ClassSubject>[]).where((s)=>s.active).toList();
  List<String> get _formalClasses {
    final ids=(widget.classNames.isNotEmpty?widget.classNames.keys:widget.classSubjects.keys).toList();
    if(widget.activeCycle!=null) ids.removeWhere((id)=>!examStrings(widget.activeCycle!['plannedClassIds']).contains(id) || examStrings(widget.activeCycle!['classIds']).contains(id));
    return ids..sort((a,b)=>_classLabel(a).compareTo(_classLabel(b)));
  }
  String _teacherLabel(ExamPaperDraft paper)=>paper.assignment.active?widget.teacherNames[paper.assignment.staffId]??paper.assignment.staffId:'No assigned teacher';

  String? _defaultError() {
    final marks=double.tryParse(_marksDefault.text);
    final minutes=_endMinute-_startMinute;
    if(marks==null || !marks.isFinite || marks<1 || marks>1000 ||
       minutes<1 || minutes>600) return 'Check default marks (1–1000) and duration (1–600 minutes).';
    return null;
  }

  void _generate({bool preserve = false}) {
    if (!_formal || _partial) return;
    setState(() {
      _generationError=null; _error=null;
      try {
        final invalid=_defaultError();
        if(invalid!=null) throw ArgumentError(invalid);
        final old=groupExamPapersByClass(_papers);
        final generated=<ExamPaperDraft>[];
        for(final id in _formalClasses.where(_selectedClasses.contains)) {
          try {
            final previous=old[id];
            generated.addAll(preserve && previous!=null && previous.isNotEmpty
              ? redistributeExamPapers(previous,_days)
              : generateClassExamSchedule(classId:id,className:_classLabel(id),
                  subjects:_catalogFor(id),assignments:widget.assignments,days:_days,teacherNames:widget.teacherNames,
                  type:_typeDefault,maxMarks:double.parse(_marksDefault.text),
                  durationMinutes:_endMinute-_startMinute,startMinute:_startMinute,instructions:_notesDefault.text));
          } on ArgumentError catch(error) {
            throw ArgumentError('${_classLabel(id)}: ${error.message}');
          }
        }
        _papers..clear()..addAll(generated);
      } on ArgumentError catch(error) {
        _generationError=error.message.toString();
      }
    });
  }

  void _toggleClass(String id,bool selected) {
    setState(() {
      if(selected) {_selectedClasses.add(id);}else{_selectedClasses.remove(id);}
      _papers.removeWhere((p)=>!_selectedClasses.contains(p.assignment.classId));
    });
    _generate(preserve:true);
  }

  void _shuffle() {
    if(_saving || _partial || _generationError!=null || _papers.length<2) return;
    setState(() {
      final result=shuffleClassSchedules(_papers);
      _papers..clear()..addAll(result);
      _error=null;
    });
  }

  String? _scheduleError() {
    if(_formal && _generationError!=null) return _generationError;
    if(_papers.isEmpty) return 'Choose at least one class and schedule its subjects.';
    if(!_formal && _papers.length!=1) return 'Choose one subject.';
    if(_assignment) return _title.text.trim().isEmpty ? 'Enter an assignment title.' : null;
    if(_formal) {
      final groups=groupExamPapersByClass(_papers);
      if(_selectedClasses.isEmpty || !groups.keys.toSet().containsAll(_selectedClasses) ||
        !_selectedClasses.containsAll(groups.keys)) return 'Generate papers for every selected class.';
      final days=_days.map(examDateKey).toSet();
      for(final id in _selectedClasses) {
        final group=groups[id]!;
        final scheduled=group.map((p)=>p.assignment.subject).toSet();
        final missing=_catalogFor(id).where((s)=>!scheduled.contains(s.name)).toList();
        if(missing.isNotEmpty) return '${_classLabel(id)}: Missing subjects: ${missing.map((s)=>s.name).join(', ')}';
        if(group.any((p)=>!days.contains(examDateKey(p.date)))) return '${_classLabel(id)}: Every paper must use an available examination day.';
        final error=validateExamSchedule(kind:_kind,category:_term,title:_title.text,start:_start,end:_end,papers:group);
        if(error!=null) return '${_classLabel(id)}: $error';
      }
      return null;
    }
    return validateExamSchedule(kind:_kind,category:_testType,title:_title.text,start:_start,end:_end,papers:_papers);
  }

  void _next() {
    String? error;
    if (_step == 0) {
      if (_end.isBefore(_start)) error = 'Check the date range.';
      if (_formal) error ??= _defaultError();
      if (_title.text.trim().isEmpty) {
        _title.text = _formal ? _term : _assignment ? 'Class assignment' : _testType;
      }
    } else if (_step == 1) {
      error = _scheduleError();
    }
    setState(() { _error = error; if (error == null) _step++; });
  }

  Future<void> _addPaper({int? index,String? classId}) async {
    if (_saving || _partial) return;
    final previous=index==null?null:_papers[index];
    final target=previous?.assignment.classId ?? classId ?? _classId;
    if(target==null)return;
    final options=widget.assignments.where((a)=>a.active && a.classId==target &&
      (previous==null || a.subject==previous.assignment.subject) &&
      (!_formal || _catalogFor(target).any((c)=>c.name==a.subject && (a.subjectId.isEmpty || a.subjectId==c.id)))).toList();
    if(options.isEmpty) {
      setState(()=>_error='Assign an active subject teacher in Staff first.');
      return;
    }
    final days=_formal?_days:[_start];
    final used=_papers.where((p)=>p.assignment.classId==target).map((p)=>examDateKey(p.date)).toSet();
    final free=days.where((d)=>!used.contains(examDateKey(d))).toList();
    if(days.isEmpty || (_formal && previous==null && free.isEmpty)) {
      setState(()=>_error='Extend the date range to make room for another paper.');
      return;
    }
    final paper=await showDialog<ExamPaperDraft>(context:context,builder:(_)=>_PaperEditor(
      assignments:options,teacherNames:widget.teacherNames,start:_start,end:_end,
      assignmentOnly:_assignment,availableDays:days,initial:previous,
      initialDate:previous?.date ?? (free.isNotEmpty?free.first:days.first),
      defaultType:_typeDefault,defaultMarks:double.tryParse(_marksDefault.text)??100,
      defaultMinutes:_endMinute-_startMinute,defaultStartMinute:_startMinute,defaultNotes:_notesDefault.text));
    if(!mounted || paper==null) return;
    if(_formal) {
      if(_papers.asMap().entries.any((e)=>e.key!=index && e.value.assignment.classId==target && e.value.assignment.subject==paper.assignment.subject && e.value.type==paper.type)) {
        setState(()=>_error='This subject already has a ${paper.type} paper.'); return;
      }
      final occupied=_papers.indexWhere((p)=>p.assignment.classId==target && examDateKey(p.date)==examDateKey(paper.date));
      if(index==null && occupied>=0) {
        setState(()=>_error='That day already has a paper. Choose a free date.'); return;
      }
      setState(() {
        if(index!=null && occupied>=0 && occupied!=index) {
          _papers[occupied]=_papers[occupied].copyWith(date:previous!.date);
        }
        if(index==null) { _papers.add(paper); } else { _papers[index]=paper; }
        _papers.sort((a,b)=>a.date.compareTo(b.date)); _error=null;
      });
    } else {
      setState(() { _papers..clear()..add(paper); _error=null; });
    }
  }

  Future<void> _publish() async {
    if (_saving) return;
    final validation=_scheduleError();
    if(validation!=null) { setState(()=>_error=validation); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ExaminationRepository();
      if (_assignment) {
        await repo.createAssignment(assignment: _papers.single.assignment,
          title: _title.text, instructions: _instructions.text, dueDate: _start);
      } else if (_formal) {
        final plan=widget.activeCycle==null?_selectedClasses.toList():examStrings(widget.activeCycle!['plannedClassIds']);
        await repo.publishClassSchedules(role:widget.role,category:_term,title:_title.text,
          start:_start,end:_end,academicYear:_academicYear,
          papers:_papers.where((p)=>!_publishedClasses.contains(p.assignment.classId)).toList(),
          plannedClassIds:plan,excludedDates:_excluded,skipSunday:_skipSunday,
          activeCycleId:_publishingCycleId??widget.activeCycle?['id']?.toString(),
          onClassPublished:(id){if(mounted)setState((){_publishedClasses.add(id);_publishingCycleId=termCycleId(_academicYear,_term);});});
      } else {
        await repo.publishSchedule(role: widget.role, kind: _kind,
          category: _formal ? _term : _testType, title: _title.text,
          start: _start, end: _end, papers: _papers, academicYear:_academicYear,
          activeCycleId:widget.activeCycle?['id']?.toString(), plannedClassIds:widget.classNames.keys.toList(),
          excludedDates:_excluded,skipSunday:_skipSunday);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _partial ? '${_publishedClasses.length} of ${_selectedClasses.length} selected classes published. ${schoolErrorMessage(error)} Retry remaining classes, or reopen the active examination to resume.' : schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateTile(String title, DateTime date, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero, title: Text(title),
    subtitle: Text(examDateKey(date)), trailing: const Icon(Icons.calendar_month),
    onTap: widget.activeCycle != null && _formal ? null : onTap,
  );

  Widget _details() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DropdownButtonFormField<String>(
      initialValue: _kind, isExpanded: true,
      decoration: const InputDecoration(labelText: 'Assessment type'),
      items: [
        if (canScheduleFormalExams(widget.role))
          const DropdownMenuItem(value: 'term', child: Text('Term Examination')),
        const DropdownMenuItem(value: 'test', child: Text('Classwise Test')),
        if (canScheduleFormalExams(widget.role))
          const DropdownMenuItem(value: 'assignment', child: Text('Class Assignment')),
      ],
      onChanged: widget.activeCycle!=null ? null : (v) {
        if (v != null) setState(() {
          _kind = v; _papers.clear(); _selectedClasses.clear(); _classId=null; _generationError=null;
          if (!_formal) _end = _start;
        });
      },
    ),
    const SizedBox(height: 14),
    if (!_assignment)
      DropdownButtonFormField<String>(
        key: ValueKey(_kind), initialValue: _formal ? _term : _testType,
        isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final item in _formal ? examTerms : classTestTypes)
          DropdownMenuItem(value: item, child: Text(item))],
        onChanged: widget.activeCycle!=null?null:(v) { if (v != null) setState(() { if (_formal) { _term = v; } else { _testType = v; } }); },
      ),
    const SizedBox(height: 14),
    TextField(controller: _title, readOnly:widget.activeCycle!=null, maxLength: 100,
      decoration: const InputDecoration(labelText: 'Title (optional automatic name)')),
    _dateTile(_assignment ? 'Due date' : 'Start date', _start, () async {
      final picked = await _pick(_start);
      if (picked != null && mounted) {
        setState(() {
          _start=picked;
          if(!_formal || _end.isBefore(_start)) _end=_start;
          if(!_formal) _papers.clear();
        });
        _generate(preserve:true);
      }
    }),
    if (_formal) _dateTile('End date', _end, () async {
      final picked = await _pick(_end, first: _start);
      if (picked != null && mounted) { setState(()=>_end=picked); _generate(preserve:true); }
    }),
    if(_formal) ...[
      DropdownButtonFormField<int>(initialValue:_academicYear,isExpanded:true,
        decoration:const InputDecoration(labelText:'Academic year (starting year)'),
        items:[for(var y=2000;y<=2100;y++) DropdownMenuItem(value:y,child:Text('$y–${y+1}'))],
        onChanged:widget.activeCycle!=null?null:(v) {if(v!=null)setState(()=>_academicYear=v);}),
      const SizedBox(height:12),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Exclude Sundays'),
        subtitle:Text('${_days.length} available examination days'),value:_skipSunday,
        onChanged:widget.activeCycle!=null?null:(v) { setState(()=>_skipSunday=v); _generate(preserve:true); }),
      _holidayControls(),
      const SizedBox(height:12),
      Text('Default details for all subjects',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      DropdownButtonFormField<String>(initialValue:_typeDefault,isExpanded:true,
        decoration:const InputDecoration(labelText:'Default paper type'),
        items:[for(final type in paperTypes) DropdownMenuItem(value:type,child:Text(type))],
        onChanged:(v) { if(v!=null) setState(()=>_typeDefault=v); }),
      const SizedBox(height:12),
      TextField(controller:_marksDefault,keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'Default maximum marks')),
      const SizedBox(height:12),
      _timingControls(),
      const SizedBox(height:12),
      TextField(controller:_notesDefault,maxLines:2,maxLength:1000,
        decoration:const InputDecoration(labelText:'Common paper instructions')),
      if(_papers.isNotEmpty) OutlinedButton(
        onPressed:() {
          final error=_defaultError();
          if(error!=null) { setState(()=>_error=error); return; }
          setState(() {
            for(var i=0;i<_papers.length;i++) {
              _papers[i]=_papers[i].copyWith(maxMarks:double.parse(_marksDefault.text),
                durationMinutes:_endMinute-_startMinute,startMinute:_startMinute,instructions:_notesDefault.text);
            }
            _error=null;
          });
        },child:const Text('Apply marks, timing and instructions to all')),
    ],
    if (_assignment) TextField(controller: _instructions, maxLines: 4, maxLength: 1000,
      decoration: const InputDecoration(labelText: 'Assignment instructions')),
  ]);

  Future<void> _chooseTime(bool start) async {
    final current=start?_startMinute:_endMinute;
    final picked=await showTimePicker(context:context,initialTime:TimeOfDay(hour:current~/60,minute:current%60));
    if(picked==null || !mounted)return;
    final minute=picked.hour*60+picked.minute;
    setState(() {
      if(start) {
        final length=_endMinute-_startMinute;
        _startMinute=minute;
        _endMinute=(minute+length).clamp(0,1439);
      } else {_endMinute=minute;}
    });
  }

  Widget _timingControls()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    ListTile(contentPadding:EdgeInsets.zero,title:const Text('Paper start time (PKT)'),
      subtitle:Text(examClock(_startMinute)),trailing:const Icon(Icons.schedule),onTap:()=>_chooseTime(true)),
    ListTile(contentPadding:EdgeInsets.zero,title:const Text('Paper end time (PKT)'),
      subtitle:Text('${examClock(_endMinute)} • ${_endMinute-_startMinute} minutes'),
      trailing:const Icon(Icons.schedule),onTap:()=>_chooseTime(false)),
    if(_papers.isNotEmpty) OutlinedButton.icon(
      onPressed:() {
        final error=_defaultError();
        if(error!=null){setState(()=>_error=error);return;}
        setState(() {
          for(var i=0;i<_papers.length;i++) {
            _papers[i]=_papers[i].copyWith(startMinute:_startMinute,durationMinutes:_endMinute-_startMinute);
          }
          _error=null;
        });
      },icon:const Icon(Icons.schedule),label:const Text('Apply timing to all subjects')),
  ]);

  Widget _holidayControls()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    for(final entry in _excluded.entries)
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event_busy),
        title:Text(entry.key),subtitle:Text(entry.value),
        trailing:widget.activeCycle!=null?null:IconButton(tooltip:'Remove holiday',
          onPressed:(){setState(()=>_excluded.remove(entry.key));_generate(preserve:true);},icon:const Icon(Icons.close))),
    if(widget.activeCycle==null) OutlinedButton.icon(onPressed:() async {
      final date=await _pick(_start,first:_start,last:_end);
      if(date==null || !mounted)return;
      final controller=TextEditingController();
      final reason=await showDialog<String>(context:context,builder:(context)=>AlertDialog(
        title:const Text('School holiday / closure'),
        content:TextField(controller:controller,maxLength:200,
          decoration:const InputDecoration(labelText:'Reason (Eid, Iqbal Day, etc.)')),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,controller.text.trim()),child:const Text('Add'))]));
      controller.dispose();
      if(reason==null || reason.isEmpty || !mounted)return;
      setState(()=>_excluded[examDateKey(date)]=reason);
      _generate(preserve:true);
    },icon:const Icon(Icons.event_busy),label:const Text('Exclude holiday / school closure')),
  ]);

  Widget _paperCards()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    for(var i=0;i<_papers.length;i++) Card(child:ListTile(
      leading:_formal?CircleAvatar(child:Text('${i+1}')):null,
      title:Text(_papers[i].assignment.subject),
      subtitle:Text('${_papers[i].assignment.active ? widget.teacherNames[_papers[i].assignment.staffId] ?? _papers[i].assignment.staffId : 'No assigned teacher'}'
        '${_assignment?'':'\n${examDateKey(_papers[i].date)} • ${_papers[i].type} • ${_papers[i].maxMarks} marks • ${_papers[i].durationMinutes} min • ${examClock(_papers[i].startMinute)}–${examClock(_papers[i].endMinute)} PKT'}'),
      onTap:_saving || (_formal && _generationError!=null)?null:()=>_addPaper(index:i),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(tooltip:'Edit paper',onPressed:_saving || (_formal && _generationError!=null)?null:()=>_addPaper(index:i),
          icon:const Icon(Icons.edit_outlined)),
        if(_formal && _papers.where((p)=>p.assignment.classId==_papers[i].assignment.classId && p.assignment.subject==_papers[i].assignment.subject).length>1)
          IconButton(tooltip:'Remove additional paper',onPressed:_saving?null:()=>setState(()=>_papers.removeAt(i)),
            icon:const Icon(Icons.delete_outline)),
      ]),
    )),
  ]);

  Future<void> _bulkTiming() async {
    var start=_startMinute,end=_endMinute;
    final result=await showDialog<(int,int)>(context:context,builder:(context)=>StatefulBuilder(
      builder:(context,update)=>AlertDialog(
        title:const Text('Apply timing to all subjects'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          ListTile(title:const Text('Start time (PKT)'),subtitle:Text(examClock(start)),
            trailing:const Icon(Icons.schedule),onTap:() async {
              final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:start~/60,minute:start%60));
              if(t!=null && context.mounted)update(()=>start=t.hour*60+t.minute);
            }),
          ListTile(title:const Text('End time (PKT)'),subtitle:Text(examClock(end)),
            trailing:const Icon(Icons.schedule),onTap:() async {
              final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:end~/60,minute:end%60));
              if(t!=null && context.mounted)update(()=>end=t.hour*60+t.minute);
            }),
          const Text('This replaces all individual paper timings. Dates, marks and teachers stay unchanged.'),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
          FilledButton(onPressed:end<=start || end-start>600?null:()=>Navigator.pop(context,(start,end)),
            child:const Text('Apply to all'))])));
    if(result==null || !mounted)return;
    setState((){
      _startMinute=result.$1;_endMinute=result.$2;
      for(var i=0;i<_papers.length;i++) {
        _papers[i]=_papers[i].copyWith(startMinute:_startMinute,durationMinutes:_endMinute-_startMinute);
      }
      _error=null;
    });
  }

  Widget _scheduleActions()=>Wrap(spacing:8,runSpacing:8,children:[
    OutlinedButton.icon(onPressed:_saving || _partial || _papers.isEmpty || _generationError!=null?null:_bulkTiming,
      icon:const Icon(Icons.schedule),label:const Text('Apply timing to all subjects')),
    OutlinedButton.icon(onPressed:_saving || _partial || !groupExamPapersByClass(_papers).values.any((p)=>p.length>1) || _generationError!=null?null:_shuffle,
      icon:const Icon(Icons.shuffle),label:const Text('Shuffle subjects')),
    OutlinedButton.icon(onPressed:_saving || _partial || _selectedClasses.isEmpty?null:() async {
      final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:const Text('Regenerate date sheet?'),
        content:const Text('This replaces manual edits and extra papers with the default subject schedule.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Regenerate'))]));
      if(confirmed==true && mounted) _generate();
    },icon:const Icon(Icons.auto_awesome),label:const Text('Regenerate')),
  ]);

  Widget _schedule() {
    if(!_formal) {
      final classes=widget.assignments.where((a)=>a.active).map((a)=>a.classId).toSet().toList()
        ..sort((a,b)=>_classLabel(a).compareTo(_classLabel(b)));
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:_classId,isExpanded:true,
          decoration:const InputDecoration(labelText:'Class & section'),
          items:[for(final id in classes) DropdownMenuItem(value:id,child:Text(_classLabel(id)))],
          onChanged:(v)=>setState((){_classId=v;_papers.clear();_error=null;})),
        _paperCards(),
        OutlinedButton.icon(onPressed:_classId==null?null:()=>_addPaper(),
          icon:const Icon(Icons.add),label:const Text('Choose subject & teacher')),
      ]);
    }
    final classes=_formalClasses;
    final selected=_selectedClasses.length;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Select participating classes',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:6),
      const Text('Select any classes for this examination. Each selected class gets its own subjects and date sheet under the same term.'),
      Row(children:[
        Expanded(child:Text('$selected of ${classes.length} classes selected')),
        TextButton(onPressed:classes.isEmpty?null:(){
          setState((){
            if(_selectedClasses.length==classes.length){_selectedClasses.clear();_papers.clear();}
            else{_selectedClasses.addAll(classes);}
          });
          _generate(preserve:true);
        },child:Text(selected==classes.length?'Clear selection':'Select all')),
      ]),
      for(final id in classes)
        Card(child:CheckboxListTile(
          key:ValueKey('exam_class_$id'),
          value:_selectedClasses.contains(id),
          title:Text(_classLabel(id),style:const TextStyle(fontWeight:FontWeight.w600)),
          subtitle:Text(_catalogFor(id).isEmpty?'No active subjects — configure this class first':
            '${_catalogFor(id).length} subjects: ${_catalogFor(id).map((s)=>s.name).join(', ')}'),
          controlAffinity:ListTileControlAffinity.leading,
          onChanged:(v)=>_toggleClass(id,v==true),
        )),
      if(classes.isEmpty) const Text('No eligible classes are available.'),
      const SizedBox(height:10),
      Text('${_papers.length} generated papers • ${_days.length} available examination days',
        style:Theme.of(context).textTheme.titleMedium),
      if(_generationError!=null) Text(_generationError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      for(final p in _papers.where((p)=>!p.assignment.active))
        Text('${_classLabel(p.assignment.classId)}: ${p.assignment.subject} has no assigned teacher.',
          style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(_papers.any((p)=>!p.assignment.active))
        const Text('Assign missing subject teachers in Staff, then reopen the wizard.'),
      if(_selectedClasses.isNotEmpty) _scheduleActions(),
    ]);
  }

  Widget _reviewTable() {
    final groups=groupExamPapersByClass(_papers);
    final ordered=[..._papers]..sort((a,b){
      final date=a.date.compareTo(b.date);
      if(date!=0)return date;
      final time=a.startMinute.compareTo(b.startMinute);
      return time!=0?time:_classLabel(a.assignment.classId).compareTo(_classLabel(b.assignment.classId));
    });
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('All dates and times are in PKT. Scroll horizontally to see every column.'),
      const SizedBox(height:8),
      Card(child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
        columnSpacing:20,
        columns:const [
          DataColumn(label:Text('Date')),DataColumn(label:Text('Class')),
          DataColumn(label:Text('Subject')),DataColumn(label:Text('Type')),
          DataColumn(label:Text('Start')),DataColumn(label:Text('End')),
          DataColumn(label:Text('Marks'),numeric:true),DataColumn(label:Text('Teacher')),
          DataColumn(label:Text('Actions')),
        ],
        rows:[for(final paper in ordered) DataRow(
          cells:[
            DataCell(Text(examDateKey(paper.date))),
            DataCell(Text(_classLabel(paper.assignment.classId))),
            DataCell(Text(paper.assignment.subject),onTap:_saving||_partial?null:()=>_addPaper(index:_papers.indexOf(paper))),
            DataCell(Text(paper.type)),
            DataCell(Text(examClock(paper.startMinute))),
            DataCell(Text(examClock(paper.endMinute))),
            DataCell(Text(paper.maxMarks.toString())),
            DataCell(Text(_teacherLabel(paper))),
            DataCell(Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(tooltip:'Edit paper',onPressed:_saving||_partial?null:()=>_addPaper(index:_papers.indexOf(paper)),
                icon:const Icon(Icons.edit_outlined)),
              if(groups[paper.assignment.classId]!.where((p)=>p.assignment.subject==paper.assignment.subject).length>1)
                IconButton(tooltip:'Remove additional paper',onPressed:_saving||_partial?null:()=>setState(()=>_papers.remove(paper)),
                  icon:const Icon(Icons.delete_outline)),
              if(_publishedClasses.contains(paper.assignment.classId)) const Icon(Icons.check_circle_outline),
            ])),
          ],
        )],
      ))),
      if(!_partial) Wrap(spacing:8,runSpacing:8,children:[
        for(final entry in groups.entries) OutlinedButton.icon(
          onPressed:_saving||entry.value.length>=15?null:()=>_addPaper(classId:entry.key),
          icon:const Icon(Icons.add),label:Text('Extra paper: ${_classLabel(entry.key)}')),
      ]),
    ]);
  }

  Widget _review()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text(_title.text,style:Theme.of(context).textTheme.titleLarge),
    Text('${examDateKey(_start)}${_formal?' – ${examDateKey(_end)}':''}'),
    if(!_formal) Text(_classLabel(_classId!)),
    const SizedBox(height:12),
    if(_formal) ...[
      Text('${_selectedClasses.length} classes • ${_papers.length} papers'),
      const Text('Review and edit the combined timetable before publishing. Shuffle rearranges papers within each class.'),
      if(_partial) Text('${_publishedClasses.length}/${_selectedClasses.length} classes published. Retry remaining classes without recreating the term.'),
      const SizedBox(height:8),
      _scheduleActions(),
      _reviewTable(),
    ] else _paperCards(),
    if(_assignment) Text(_instructions.text),
    const SizedBox(height:12),
    const Text('Publishing makes the activities available to their assigned subject teachers.'),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create assessment')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _step==2 && _formal?1400:760),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Step ${_step + 1} of 3 • ${['Details', 'Class & papers', 'Review'][_step]}',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_step + 1) / 3),
          ])),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_step == 0) _details() else if (_step == 1) _schedule() else _review(),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          if (_step > 0) Expanded(child: OutlinedButton(onPressed: _saving || _partial ? null : () => setState(() { _step--; _error = null; }),
            child: const Text('Back'))),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _saving ? null : _step == 2 ? _publish : _next,
            child: Text(_saving ? 'Publishing…' : _step == 2 ? (_partial?'Retry remaining classes':'Publish') : 'Next'))),
        ])),
      ]),
    ))),
  );
}

class _PaperEditor extends StatefulWidget {
  const _PaperEditor({required this.assignments, required this.teacherNames,
    required this.start, required this.end, required this.assignmentOnly,
    required this.availableDays, required this.initialDate, this.initial,
    required this.defaultType, required this.defaultMarks, required this.defaultMinutes, required this.defaultStartMinute, required this.defaultNotes});
  final List<TeacherAssignment> assignments;
  final Map<String, String> teacherNames;
  final DateTime start, end;
  final bool assignmentOnly;
  final List<DateTime> availableDays;
  final DateTime initialDate;
  final ExamPaperDraft? initial;
  final String defaultType, defaultNotes;
  final double defaultMarks;
  final int defaultMinutes, defaultStartMinute;

  @override
  State<_PaperEditor> createState() => _PaperEditorState();
}

class _PaperEditorState extends State<_PaperEditor> {
  late String _subject=widget.initial?.assignment.subject ?? widget.assignments.first.subject;
  late String? _assignmentId=widget.assignments.any((a)=>a.id==widget.initial?.assignment.id)
    ?widget.initial!.assignment.id:widget.assignments.firstWhere((a)=>a.subject==_subject).id;
  late DateTime _date=widget.availableDays.any((d)=>examDateKey(d)==examDateKey(widget.initialDate))
    ?widget.initialDate:widget.availableDays.first;
  late String _type=widget.initial?.type??widget.defaultType;
  late final _marks=TextEditingController(text:(widget.initial?.maxMarks??widget.defaultMarks).toString());
  late int _paperStart=widget.initial?.startMinute??widget.defaultStartMinute;
  late int _paperEnd=_paperStart+(widget.initial?.durationMinutes??widget.defaultMinutes);
  late final _notes=TextEditingController(text:widget.initial?.instructions??widget.defaultNotes);
  String? _error;

  @override
  void dispose() { _marks.dispose(); _notes.dispose(); super.dispose(); }

  void _save() {
    final options = widget.assignments.where((a) => a.subject == _subject && a.id == _assignmentId);
    final marks = double.tryParse(_marks.text);
    final minutes = _paperEnd-_paperStart;
    if (options.isEmpty || marks == null || !marks.isFinite || marks <= 0 || marks > 1000 ||
        minutes < 1 || minutes > 600) {
      setState(() => _error = 'Select a teacher and enter valid marks and duration.');
      return;
    }
    Navigator.pop(context, ExamPaperDraft(assignment: options.first, date: _date,
      type: _type, maxMarks: marks, durationMinutes: minutes, startMinute:_paperStart,instructions: _notes.text));
  }

  Future<void> _pickTime(bool start) async {
    final current=start?_paperStart:_paperEnd;
    final picked=await showTimePicker(context:context,initialTime:TimeOfDay(hour:current~/60,minute:current%60));
    if(picked==null || !mounted)return;
    final minute=picked.hour*60+picked.minute;
    setState(() {
      if(start){final length=_paperEnd-_paperStart;_paperStart=minute;_paperEnd=(minute+length).clamp(0,1439);}
      else {_paperEnd=minute;}
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.assignments.map((a) => a.subject).toSet().toList()..sort();
    final teachers = widget.assignments.where((a) => a.subject == _subject);
    return AlertDialog(scrollable: true, title: Text(widget.assignmentOnly ? 'Choose subject' : 'Schedule paper'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: _subject, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: [for (final subject in subjects) DropdownMenuItem(value: subject, child: Text(subject))],
          onChanged: widget.initial!=null?null:(v) { if(v!=null) setState(() { _subject=v; _assignmentId=widget.assignments.firstWhere((a)=>a.subject==v).id; }); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(key: ValueKey(_subject), initialValue: _assignmentId, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Responsible subject teacher'),
          items: [for (final a in teachers) DropdownMenuItem(value: a.id,
            child: Text(widget.teacherNames[a.staffId] ?? a.staffId, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _assignmentId = v)),
        if (!widget.assignmentOnly) ...[
          const SizedBox(height: 12),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Paper date'),
            subtitle: Text(examDateKey(_date)), trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: widget.start, lastDate: widget.end,
                selectableDayPredicate:(day)=>widget.availableDays.any((d)=>examDateKey(d)==examDateKey(day)));
              if (d != null && mounted) setState(() => _date = d);
            }),
          DropdownButtonFormField<String>(initialValue: _type, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paper type'),
            items: [for (final type in paperTypes) DropdownMenuItem(value: type, child: Text(type))],
            onChanged: (v) { if (v != null) setState(() => _type = v); }),
          const SizedBox(height: 12),
          TextField(controller: _marks, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Maximum marks')),
          const SizedBox(height: 12),
          ListTile(contentPadding:EdgeInsets.zero,title:const Text('Paper start time (PKT)'),
            subtitle:Text(examClock(_paperStart)),trailing:const Icon(Icons.schedule),onTap:()=>_pickTime(true)),
          ListTile(contentPadding:EdgeInsets.zero,title:const Text('Paper end time (PKT)'),
            subtitle:Text('${examClock(_paperEnd)} • ${_paperEnd-_paperStart} minutes'),
            trailing:const Icon(Icons.schedule),onTap:()=>_pickTime(false)),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 3, maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Room, syllabus or instructions')),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(widget.initial==null?'Add':'Save changes'))]);
  }
}
