import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/examination_repository.dart';
import '../data/school_errors.dart';

class ExamTermOverview extends StatefulWidget {
  const ExamTermOverview({super.key,this.onOpen,this.onAddClass,this.onClose,this.onHoliday,this.compact=false});
  final VoidCallback? onOpen,onAddClass;
  final ValueChanged<String>? onClose,onHoliday;
  final bool compact;
  @override
  State<ExamTermOverview> createState()=>_ExamTermOverviewState();
}
class _ExamTermOverviewState extends State<ExamTermOverview> {
  late final _db=FirebaseFirestore.instance;
  late final _control=_db.collection('exam_term_control').doc('current').snapshots();
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:_control,builder:(context,snapshot) {
      if(snapshot.hasError)return Padding(padding:const EdgeInsets.all(8),
        child:Text(schoolErrorMessage(snapshot.error!),style:const TextStyle(fontSize:12)));
      if(!snapshot.hasData)return const SizedBox.shrink();
      final id=snapshot.data?.data()?['cycleId'];
      if(id is! String || id.isEmpty)return const SizedBox.shrink();
      return _CycleCard(key:ValueKey(id),id:id,config:widget);
    });
}
class _CycleCard extends StatefulWidget {
  const _CycleCard({super.key,required this.id,required this.config});
  final String id;
  final ExamTermOverview config;
  @override
  State<_CycleCard> createState()=>_CycleCardState();
}
class _CycleCardState extends State<_CycleCard> {
  late final _db=FirebaseFirestore.instance;
  late final _cycle=_db.collection('exam_term_cycles').doc(widget.id).snapshots();
  late final _papers=_db.collection('examinations').where('cycleId',isEqualTo:widget.id).snapshots();
  Timer? _clock;
  @override
  void initState(){
    super.initState();
    _clock=Timer.periodic(const Duration(minutes:1),(_){if(mounted)setState((){});});
  }
  @override
  void dispose(){_clock?.cancel();super.dispose();}

  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:_cycle,builder:(context,snapshot) {
      if(snapshot.hasError)return Text(schoolErrorMessage(snapshot.error!));
      final cycle=snapshot.data?.data();
      if(cycle==null)return const SizedBox.shrink();
      if(cycle['status']=='closed') {
        return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:ListTile(
          leading:const Icon(Icons.check_circle_outline),
          title:Text('${cycle['category']} • Fully closed'),
          subtitle:Text('Academic year ${cycle['academicYear']}–${(cycle['academicYear'] as int)+1} • All results declared\nNo active examination. A new term may be created.'),
          trailing:widget.config.onOpen==null?null:IconButton(tooltip:'Open examinations',
            icon:const Icon(Icons.chevron_right),onPressed:widget.config.onOpen)));
      }
      if(cycle['status']!='active')return const SizedBox.shrink();
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:_papers,builder:(context,paperSnapshot) {
          if(paperSnapshot.hasError)return Text(schoolErrorMessage(paperSnapshot.error!));
          final papers=paperSnapshot.data?.docs.map((d)=>d.data()).toList()??[];
          final off=examStringMap(cycle['excludedDates']);
          final now=schoolExamNow();
          final tomorrow=examDateKey(DateTime(now.year,now.month,now.day+1));
          final today=examDateKey(now);
          final future=papers.where((p)=>(p['examDate']??'').toString().compareTo(today)>=0 &&
            p['resultStatus']=='draft' && !off.containsKey(p['examDate'])).toList()
            ..sort((a,b)=>('${a['examDate']} ${examTiming(a)}').compareTo('${b['examDate']} ${examTiming(b)}'));
          final next=future.where((p)=>p['examDate']==tomorrow).toList();
          final affected=papers.where((p)=>off.containsKey(p['examDate']) && p['resultStatus']!='released').length;
          final total=examStrings(cycle['paperIds']).length;
          final released=examStrings(cycle['releasedPaperIds']).length;
          final classCount=examStrings(cycle['classIds']).length;
          final planned=examStrings(cycle['plannedClassIds']).length;
          final submitted=papers.where((p)=>p['resultStatus']=='submitted').length;
          final ready=termReadyToClose(cycle);
          final dateLabels=papers.map((p)=>(p['examDate']??'').toString()).where((d)=>d.isNotEmpty).toList()..sort();
          final actualEnd=dateLabels.isEmpty?cycle['endDate']:dateLabels.last;
          final config=widget.config;
          final content=Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
            Row(children:[
              Icon(Icons.event_available_outlined,color:Theme.of(context).colorScheme.primary),
              const SizedBox(width:8),
              Expanded(child:Text('${cycle['category']} • ${cycle['academicYear']}–${(cycle['academicYear'] as int)+1}',
                style:const TextStyle(fontWeight:FontWeight.w800))),
              Text(ready?'Ready to close':'Active',style:const TextStyle(fontSize:12)),
            ]),
            const SizedBox(height:6),
            Text('Planned end: ${cycle['endDate']} • Last paper: $actualEnd'),
            const SizedBox(height:6),
            Text('$classCount/$planned classes scheduled • $released/$total results released • $submitted awaiting review'),
            const SizedBox(height:6),
            LinearProgressIndicator(value:total==0?0:released/total),
            const SizedBox(height:8),
            if(!paperSnapshot.hasData) const Text('Loading upcoming papers…')
            else if(next.isNotEmpty) ...[
              Text('Tomorrow: ${next.length} paper(s)',style:const TextStyle(fontWeight:FontWeight.w700)),
              for(final p in next.take(config.compact?2:4))
                Text('${p['className']??p['classId']} • ${p['subject']} • ${examTiming(p)}',style:const TextStyle(fontSize:12)),
              if(next.length>(config.compact?2:4)) Text('And ${next.length-(config.compact?2:4)} more in date sheet'),
            ] else ...[
              const Text('No paper scheduled tomorrow.'),
              if(future.isNotEmpty) Text('Next: ${future.first['examDate']} • ${future.first['subject']} • ${examTiming(future.first)}',style:const TextStyle(fontSize:12)),
            ],
            if(affected>0) Text('$affected paper(s) on excluded dates need rescheduling.',
              style:TextStyle(color:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w700)),
            if(off.isNotEmpty) Text('School closures: ${off.length} date(s)',style:const TextStyle(fontSize:12)),
            Wrap(spacing:6,runSpacing:4,children:[
              if(config.onOpen!=null) TextButton(onPressed:config.onOpen,child:const Text('Open examinations')),
              if(config.onAddClass!=null && classCount<planned) TextButton(onPressed:config.onAddClass,child:const Text('Add class date sheet')),
              if(config.onHoliday!=null) TextButton(onPressed:()=>config.onHoliday!(widget.id),child:const Text('Mark holiday / closure')),
              if(config.onClose!=null) TextButton(onPressed:ready?()=>config.onClose!(widget.id):null,child:const Text('Declare & close')),
            ]),
          ]);
          return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Padding(
            padding:const EdgeInsets.all(12),
            child:config.compact?ConstrainedBox(constraints:const BoxConstraints(maxHeight:235),
              child:SingleChildScrollView(child:content)):content));
        });
    });
}
