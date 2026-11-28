import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdfrx/pdfrx.dart';
import '../data/admission_storage.dart';
import '../data/school_user_service.dart';
import '../data/school_portal_client.dart';
import '../data/teacher_portal_repository.dart';
import '../data/parent_portal_repository.dart';
import '../data/school_errors.dart';
import 'school_settings_page.dart';

String _value(dynamic value)=>value==null||value.toString().trim().isEmpty?'—':value.toString();
String _money(dynamic minor)=>minor is num?'PKR ${(minor/100).toStringAsFixed(2)}':'—';
String _clock(dynamic value)=>value is int?'${(value~/60).toString().padLeft(2,'0')}:${(value%60).toString().padLeft(2,'0')}':'—';
num _amount(dynamic value)=>value is num?value:0;
Widget _entry(String name,dynamic value)=>ListTile(dense:true,title:Text(name),subtitle:Text(_value(value)));
Widget _notice(String text)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Text(text)));
Widget _heading(BuildContext context,String title)=>Padding(padding:const EdgeInsets.fromLTRB(4,14,4,6),
  child:Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)));

class _PortalLoad extends StatefulWidget{
  const _PortalLoad({super.key,required this.load,required this.content});
  final Future<Map<String,dynamic>> Function() load;
  final List<Widget> Function(BuildContext,Map<String,dynamic>) content;
  @override
  State<_PortalLoad> createState()=>_PortalLoadState();
}
class _PortalLoadState extends State<_PortalLoad>{
  late Future<Map<String,dynamic>> _future=widget.load();
  @override
  Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,snapshot){
    if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
    final data=snapshot.data;
    return RefreshIndicator(onRefresh:()async{setState(()=>_future=widget.load());try{await _future;}catch(_){}},
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
        if(snapshot.hasError)...[
          _notice(schoolErrorMessage(snapshot.error!)),
          TextButton(onPressed:()=>setState(()=>_future=widget.load()),child:const Text('Retry')),
        ]else if(data!=null)...[
          if(data['truncated']==true)_notice('Showing a limited set of records. Totals may not cover the complete history.'),
          ...widget.content(context,data),
        ],
      ]));
  });
}
class ParentPortalPage extends StatelessWidget {
  const ParentPortalPage({super.key,required this.displayName,required this.permissions});
  final String displayName;
  final Map<String,bool> permissions;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Parent portal'),actions:[
      const SchoolSettingsButton(),
      IconButton(tooltip:'Sign out',icon:const Icon(Icons.logout),onPressed:()=>FirebaseAuth.instance.signOut()),
    ]),
    body:_PortalLoad(load:()=>ParentPortalRepository().children(),content:(context,data){
      final children=portalRows(data['rows']);
      return [
        _heading(context,'Welcome, $displayName'),
        const Text('Your linked children'),
        if(children.isEmpty)_notice('No child is linked to this account. Ask the school owner to verify and link your child.'),
        for(final child in children)Card(child:ListTile(
          leading:const CircleAvatar(child:Icon(Icons.school_outlined)),title:Text(_value(child['name'])),subtitle:Text(child['needsSync']==true?'${child['id']} • Ask owner to sync parent records':_value(child['id'])),
          trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>
            _ChildPortalPage(child:child,permissions:permissions))))),
        if(schoolPermission(permissions,'messages'))Card(child:ListTile(leading:const Icon(Icons.forum_outlined),
          title:const Text('Messages'),subtitle:const Text('Contact school administration'),
          onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const SchoolMessagesPage())))),
      ];
    }));
}
class _ChildPortalPage extends StatelessWidget {
  const _ChildPortalPage({required this.child,required this.permissions});
  final Map<String,dynamic> child;
  final Map<String,bool> permissions;
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(_value(child['name']))),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[
        const CircleAvatar(radius:28,child:Icon(Icons.school_outlined,size:28)),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_value(child['name']),style:Theme.of(context).textTheme.titleLarge),
          const Text('Student dashboard'),
          if(child['className']!=null)Text(_value(child['className'])),
        ])),
      ]))),
      _heading(context,'Student records'),
      LayoutBuilder(builder:(context,constraints){
        final columns=constraints.maxWidth>=720?4:2;
        return GridView.count(crossAxisCount:columns,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
          crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:1.35,children:[
      for(final item in const [
        ('profile','Profile','parent_profile',Icons.person_outline),
        ('fees','Fees and dues','parent_fees',Icons.receipt_long_outlined),
        ('attendance','Attendance','parent_attendance',Icons.fact_check_outlined),
        ('exams','Examinations and results','parent_exams',Icons.school_outlined),
        ('tests','Class and monthly tests','parent_exams',Icons.quiz_outlined),
        ('assignments','Assignments','parent_exams',Icons.assignment_outlined),
        ('homework','Homework','parent_exams',Icons.menu_book_outlined),
        ('documents','Documents','parent_documents',Icons.folder_outlined),
      ]) if(schoolPermission(permissions,item.$3))Card(clipBehavior:Clip.antiAlias,child:InkWell(
        onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>
          _ParentSection(childId:child['id'].toString(),section:item.$1,title:item.$2))),
        child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(item.$4,color:Theme.of(context).colorScheme.primary,size:28),
          const Spacer(),
          Text(item.$2,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700)),
        ])))),
        ]);
      }),
      if(schoolPermission(permissions,'parent_exams'))...[
        _heading(context,'Current school activities'),
        for(final item in const [('exams','Upcoming examinations'),('tests','Upcoming tests'),('assignments','Active assignments'),('homework','Active homework')])
          Card(child:ListTile(leading:const Icon(Icons.event_note_outlined),title:Text(item.$2),trailing:const Icon(Icons.chevron_right),
            onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>
              _ParentSection(childId:child['id'].toString(),section:item.$1,title:item.$2,currentOnly:true))))),
      ],
    ]));
}
class _ParentSection extends StatelessWidget {
  const _ParentSection({required this.childId,required this.section,required this.title,this.currentOnly=false});
  final bool currentOnly;
  final String childId,section,title;
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(title)),
    body:_PortalLoad(load:()=>ParentPortalRepository().section(childId,section),
      content:(context,data){
        final rows=portalRows(data['rows']);
        if(section=='profile'){
          final p=portalMap(data['profile']);
          return [for(final field in const [('fullName','Name'),('admissionNo','Admission number'),('rollNo','Roll number'),
            ('className','Class'),('dateOfBirth','Date of birth'),('gender','Gender'),('nationality','Nationality'),('admissionDate','Admission date'),('status','Status')])
            _entry(field.$2,p[field.$1])];
        }
        if(section=='fees')return [ _ParentHistory(rows:rows,section:section) ];
        if(['attendance','exams','tests','assignments','homework'].contains(section))return [_ParentHistory(rows:rows,section:section,currentOnly:currentOnly)];
        return [
          if(rows.isEmpty)_notice('No documents available.'),
          for(final file in rows)Card(child:ListTile(leading:const Icon(Icons.insert_drive_file_outlined),
            title:Text(_value(file['name'])),subtitle:Text(_value(file['kind']??file['contentType'])),trailing:const Icon(Icons.visibility_outlined),
            onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>_ParentDocument(file:file))))),
        ];
      }));
}
class _ParentHistory extends StatefulWidget {
  const _ParentHistory({required this.rows,required this.section,this.currentOnly=false});
  final bool currentOnly;
  final List<Map<String,dynamic>> rows;
  final String section;
  @override
  State<_ParentHistory> createState()=>_ParentHistoryState();
}
class _ParentHistoryState extends State<_ParentHistory>{
  String period='All';
  String year='All';
  String group='Daily';
  late String activity=widget.currentOnly?'Current':'All';
  String category='All';
  String date(Map<String,dynamic> r)=>(r['month']??r['date']??r['examDate']??r['dueDate']??'').toString();
  String month(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}';
  bool isCurrent(Map<String,dynamic> r,String today){
    if(widget.section=='exams'||widget.section=='tests')return r['active']==true&&r['cycleStatus']!='closed'&&date(r).compareTo(today)>=0;
    return r['active']==true&&date(r).compareTo(today)>=0;
  }
  Widget select(String label,String value,List<String> options,ValueChanged<String> update)=>Padding(
    padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(
      initialValue:options.contains(value)?value:options.first,isExpanded:true,
      decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),
      items:options.map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),
      onChanged:(s){if(s!=null)setState(()=>update(s));}));
  @override
  Widget build(BuildContext context){
    final now=DateTime.now().toUtc().add(const Duration(hours:5));
    final today='${month(now)}-${now.day.toString().padLeft(2,'0')}';
    final fees=widget.section=='fees',attendance=widget.section=='attendance';
    final exams=widget.section=='exams'||widget.section=='tests';
    final years=widget.rows.map(date).where((d)=>d.length>=4).map((d)=>d.substring(0,4)).toSet().toList()..sort((a,b)=>b.compareTo(a));
    final cats=widget.rows.map((r)=>(r['category']??'Other').toString()).toSet().toList()..sort();
    final months=period=='This month'?1:period=='Last 6 months'?6:12;
    final first=month(DateTime(now.year,now.month-months+1));
    final rows=widget.rows.where((r){
      final d=date(r);
      if(year!='All'&&!d.startsWith(year))return false;
      if((fees||attendance)&&period!='All'&&(d.length<7||d.substring(0,7).compareTo(first)<0||d.substring(0,7).compareTo(month(now))>0))return false;
      if(fees&&category!='All'&&r['category']!=category)return false;
      if(!fees&&!attendance&&activity!='All'&&(isCurrent(r,today)!=(activity=='Current')))return false;
      return true;
    }).toList();
    final grouped=<String,List<Map<String,dynamic>>>{};
    if(attendance)for(final r in rows){
      final d=date(r),length=group=='Yearly'?4:group=='Monthly'?7:10;
      final key=d.length>=length?d.substring(0,length):d;
      grouped.putIfAbsent(key,()=>[]).add(r);
    }
    Widget attendanceCard(String title,List<Map<String,dynamic>> records){
      final present=records.where((r)=>['present','late'].contains(r['status'])).length;
      final absent=records.where((r)=>r['status']=='absent').length;
      final leave=records.where((r)=>r['status']=='leave').length;
      final rate=records.isEmpty?0.0:present/records.length;
      return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:Theme.of(context).textTheme.titleMedium),
        Text('Present / late: $present • Absent: $absent • Leave: $leave'),
        const SizedBox(height:8),LinearProgressIndicator(value:rate),
        Text('${(rate*100).toStringAsFixed(1)}% of recorded days present or late'),
      ])));
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(fees||attendance)select('Period',period,['All','This month','Last 6 months','Last 12 months'],(s)=>period=s),
      select('Year',year,['All',...years],(s)=>year=s),
      if(fees)select('Fee or purchase type',category,['All',...cats],(s)=>category=s),
      if(attendance)select('Attendance view',group,['Daily','Monthly','Yearly'],(s)=>group=s),
      if(!fees&&!attendance)select('Activity',activity,['All','Current','History'],(s)=>activity=s),
      if(fees)..._bills(rows),
      if(attendance)...[
        attendanceCard('Selected period',rows),
        if(group=='Daily')for(final r in rows)Card(child:ListTile(title:Text(date(r)),trailing:Text(_value(r['status'])))),
        if(group!='Daily')for(final e in grouped.entries)attendanceCard(e.key,e.value),
      ],
      if(!fees&&!attendance)for(final r in rows)Card(child:ListTile(
        title:Text(_value(exams?r['subject']:r['title'])),
        subtitle:Text(exams?'${_value(r['sessionTitle']??r['title'])}\n${date(r)} • ${_clock(r['startMinute'])}–${_clock(r['endMinute'])} PKT\n${r['resultStatus']=='released'?'Result declared':r['cycleStatus']=='closed'?'Completed':'Result pending'}':'${_value(r['subject'])} • Due ${date(r)}\n${_value(r['instructions'])}'),
        trailing:exams&&r['score'] is num?Text('${r['score']} / ${_value(r['maxMarks'])}'):null,
      )),
      if(rows.isEmpty&&!fees)_notice('No records for the selected filters.'),
    ]);
  }
}
List<Widget> _bills(List<Map<String,dynamic>> rows){
  final total=rows.fold<num>(0,(sum,r)=>sum+_amount(r['amountMinor']));
  final paid=rows.fold<num>(0,(sum,r)=>sum+_amount(r['paidMinor']));
  return [
    _notice('Total: ${_money(total)}\nPaid: ${_money(paid)}\nOutstanding: ${_money(total-paid)}'),
    if(rows.isEmpty)_notice('No bills recorded.'),
    for(final r in rows)Card(child:ListTile(title:Text('${_value(r['title'])} • ${_value(r['month'])}'),
      subtitle:Text('${_value(r['category'])} • ${_value(r['status'])} • Paid: ${_money(r['paidMinor'])}\nOutstanding: ${_money(_amount(r['amountMinor'])-_amount(r['paidMinor']))}'),
      trailing:Text(_money(r['amountMinor'])))),
  ];
}
class _ParentDocument extends StatefulWidget{
  const _ParentDocument({required this.file});
  final Map<String,dynamic> file;
  @override
  State<_ParentDocument> createState()=>_ParentDocumentState();
}
class _ParentDocumentState extends State<_ParentDocument>{
  late final _storage=AdmissionStorage();
  late Future<Uint8List> _bytes=_storage.downloadFile(widget.file['path'].toString(),parentReadOnly:true);
  bool _saving=false;
  Future<void> _save()async{
    setState(()=>_saving=true);
    try{await _storage.saveDocumentToDevice(widget.file,parentReadOnly:true);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(schoolErrorMessage(e))));}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(_value(widget.file['name'])),
    actions:[IconButton(tooltip:'Download',onPressed:_saving?null:_save,icon:const Icon(Icons.download_outlined))]),
    body:FutureBuilder<Uint8List>(future:_bytes,builder:(context,s){
      if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(s.hasError||!s.hasData)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(schoolErrorMessage(s.error??StateError('File unavailable.'))),
        TextButton(onPressed:()=>setState(()=>_bytes=_storage.downloadFile(widget.file['path'].toString(),parentReadOnly:true)),child:const Text('Retry')),
      ]));
      final name=_value(widget.file['name']).toLowerCase();
      final type=_value(widget.file['contentType']);
      if(type=='application/pdf'||name.endsWith('.pdf'))return PdfViewer.data(s.data!,sourceName:'parent-document');
      if(type.startsWith('image/')||RegExp(r'\.(jpg|jpeg|png|webp)$').hasMatch(name))return InteractiveViewer(child:Center(child:Image.memory(s.data!,fit:BoxFit.contain)));
      return const Center(child:Text('Use Download to open this file.'));
    }));
}
int? completedServiceMonths(String date,{DateTime? now}){
  final start=DateTime.tryParse(date);
  final end=now??DateTime.now();
  if(start==null||start.isAfter(end))return null;
  return (end.year-start.year)*12+end.month-start.month-(end.day<start.day?1:0);
}
class TeacherPersonalPage extends StatelessWidget{
  const TeacherPersonalPage({super.key,required this.section});
  final String section;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(section=='profile'?'My profile & contract':section=='salary'?'My salary':'Performance analytics')),
    body:_PortalLoad(load:()=>TeacherPortalRepository().load(section),content:(context,data){
      if(section=='profile'){
        final p=portalMap(data['profile']),c=portalMap(data['contract']);
        final months=completedServiceMonths(p['joinDate']?.toString()??'');
        return [
          for(final field in const [('fullName','Name'),('staffNo','Staff number'),('designation','Designation'),('email','Email'),('phone','Phone'),('qualification','Qualification'),('subjectSpecialization','Specialization'),('joinDate','Joining date')])
            _entry(field.$2,p[field.$1]),
          _entry('Completed months since joining',months),
          _heading(context,'Contract'),
          if(c.isEmpty)_notice('No contract details recorded. Ask the school owner to add them.'),
          for(final field in const [('type','Contract type'),('startDate','Start date'),('endDate','End date'),('details','Terms')])if(c.isNotEmpty)_entry(field.$2,c[field.$1]),
        ];
      }
      final rows=portalRows(data['rows']);
      if(section=='salary'){
        final rate=portalMap(data['rate']);
        return [_heading(context,'Current salary rate'),_notice(rate.isEmpty?'No salary rate set.':'Basic: ${_money(rate['basicMinor'])}\nAllowances: ${_money(rate['allowanceMinor'])}\nBonus: ${_money(rate['bonusMinor'])}\nTotal: ${_money(rate['amountMinor'])}'),
          _heading(context,'Salary history'),..._bills(rows)];
      }
      String percent(dynamic v)=>v is num?'${v.toStringAsFixed(1)}%':'Not available';
      return [
        _notice('Released papers: ${_value(data['released'])}\nAwaiting review: ${_value(data['submitted'])}\nAverage released score: ${percent(data['average'])}'),
        const Text('These statistics describe recorded student outcomes for your papers, not a formal evaluation of teaching quality.'),
        if((data['skipped'] as int? ?? 0)>0)_notice('Some historical papers have no current assignment access and were excluded from score averages.'),
        for(final r in rows)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_value(r['name']),style:const TextStyle(fontWeight:FontWeight.w700)),
          Text('${_value(r['papers'])} papers • ${_value(r['marks'])} marks • ${percent(r['average'])}'),
          if(r['average'] is num)LinearProgressIndicator(value:((r['average'] as num)/100).clamp(0.0,1.0).toDouble()),
        ]))),
      ];
    }));
}
class SchoolMessagesPage extends StatelessWidget {
  const SchoolMessagesPage({super.key,this.admin=false});
  final bool admin;
  @override
  Widget build(BuildContext context){
    if(!admin)return const _ConversationPage();
    return Scaffold(appBar:AppBar(title:const Text('School messages')),
      body:_PortalLoad(load:()=>SchoolMessageRepository().threads(),content:(context,data){
        final rows=portalRows(data['rows']);
        return [
          if(rows.isEmpty)_notice('No active parent or teacher messaging accounts.'),
          for(final row in rows)Card(child:ListTile(title:Text(_value(row['name'])),subtitle:Text(_value(row['role'])),
            leading:const Icon(Icons.forum_outlined),onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>
              _ConversationPage(uid:row['uid'].toString(),name:row['name'].toString()))))),
        ];
      }));
  }
}
class _ConversationPage extends StatefulWidget {
  const _ConversationPage({this.uid,this.name});
  final String? uid,name;
  @override
  State<_ConversationPage> createState()=>_ConversationPageState();
}
class _ConversationPageState extends State<_ConversationPage>{
  final _text=TextEditingController();
  final _client=SchoolMessageRepository();
  bool _sending=false;
  int _revision=0;
  @override
  void dispose(){_text.dispose();super.dispose();}
  Future<void> _send()async{
    final text=_text.text.trim();
    if(text.isEmpty||_sending)return;
    setState(()=>_sending=true);
    try{
      await _client.send(widget.uid,text);
      if(mounted){_text.clear();setState(()=>_revision++);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(schoolErrorMessage(e))));}
    finally{if(mounted)setState(()=>_sending=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.name??'School messages'),
    actions:[IconButton(tooltip:'Refresh messages',onPressed:()=>setState(()=>_revision++),icon:const Icon(Icons.refresh))]),
    body:SafeArea(child:Column(children:[
      Expanded(child:_PortalLoad(key:ValueKey(_revision),load:()=>_client.messages(widget.uid),content:(context,data){
        final rows=portalRows(data['rows']);
        return [
          if(rows.isEmpty)_notice('No messages yet.'),
          for(final row in rows)Align(alignment:(row['fromSchool']==true)==(widget.uid!=null)?Alignment.centerRight:Alignment.centerLeft,
            child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
              Text(row['fromSchool']==true?'School administration':widget.name??'You',style:const TextStyle(fontWeight:FontWeight.w700)),
              Text(_value(row['text'])),Text(_value(row['date']),style:Theme.of(context).textTheme.bodySmall),
            ])))),
        ];
      })),
      Padding(padding:const EdgeInsets.all(12),child:Row(children:[
        Expanded(child:TextField(controller:_text,maxLength:2000,maxLines:3,minLines:1,
          decoration:const InputDecoration(hintText:'Write a message'))),
        IconButton(tooltip:'Send',onPressed:_sending?null:_send,icon:const Icon(Icons.send)),
      ])),
    ])));
}
