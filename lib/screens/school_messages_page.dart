import 'dart:async';
import 'dart:typed_data';
import 'package:visibility_detector/visibility_detector.dart';
import 'school_voice_message.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../data/teacher_portal_repository.dart';
import '../data/school_errors.dart';
import 'account_picture.dart';
import 'office_calls.dart';

typedef _Docs = QuerySnapshot<Map<String,dynamic>>;

class SchoolMessagesPage extends StatelessWidget {
  const SchoolMessagesPage({super.key,this.admin=false,this.threadUid});
  final bool admin;
  final String? threadUid;
  @override
  Widget build(BuildContext context)=>admin?(threadUid==null?const _ThreadList():_Conversation(uid:threadUid,name:'School conversation')):const _Conversation();
}
class _MessageProfileButton extends StatelessWidget {
  const _MessageProfileButton({required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(right:8),
    child:IconButton(
      tooltip:'My profile and message settings',
      onPressed:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AccountPicturePage(fromMessages:true))),
      icon:AccountPicture(uid:uid,name:'Me',radius:17),
    ),
  );
}
Future<bool> _confirmConversationDeletion(BuildContext context,SchoolMessageRepository repo,{String? uid,String? name})async{
  final all=uid==null;
  final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(all?'Delete ALL conversations?':'Delete conversation?'),
    content:Text(all?'Permanently remove every school conversation for both sides, including messages, attachments, voice recordings and scheduled messages. Accounts and other school records will remain. This cannot be undone.':'Permanently remove the conversation with ${name??'this account'} for both sides, including its voice recordings and scheduled messages. This cannot be undone.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(ctx).colorScheme.error,foregroundColor:Theme.of(ctx).colorScheme.onError),onPressed:()=>Navigator.pop(ctx,true),child:Text(all?'Delete all':'Delete conversation'))],
  ));
  if(yes!=true||!context.mounted)return false;
  try{
    await repo.deleteConversations(uid);
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Deletion queued. The server will remove the conversation records and audio.')));
    return true;
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(schoolErrorMessage(e))));return false;}
}
class _OwnerCleanupStatus extends StatefulWidget{
  const _OwnerCleanupStatus({required this.repo,required this.onCompleted});
  final SchoolMessageRepository repo;
  final VoidCallback onCompleted;
  @override
  State<_OwnerCleanupStatus> createState()=>_OwnerCleanupStatusState();
}
class _OwnerCleanupStatusState extends State<_OwnerCleanupStatus>{
  late final stream=widget.repo.cleanupRequest.snapshots();
  Object? lastCompletion;
  Timer? retryTimer;
  bool requesting=false;
  String? retryError;
  bool pending=false;
  Future<void> advance()async{
    if(!mounted||!pending||requesting)return;
    setState(()=>requesting=true);
    try{await widget.repo.resumeConversationCleanup();if(mounted)setState(()=>retryError=null);}
    catch(e){if(mounted)setState(()=>retryError=schoolErrorMessage(e));}
    finally{if(mounted)setState(()=>requesting=false);}
  }
  @override
  void initState(){super.initState();retryTimer=Timer.periodic(const Duration(seconds:5),(_)=>unawaited(advance()));}
  @override
  void dispose(){retryTimer?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:stream,builder:(context,s){
    final data=s.data?.data();
    if(data==null||s.hasError){pending=false;return const SizedBox.shrink();}
    final done=data['status']=='done';
    final wasPending=pending;pending=!done;
    if(pending&&!wasPending)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(advance());});
    if(done&&data['completedAt']!=null&&lastCompletion!=data['completedAt']){
      lastCompletion=data['completedAt'];
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)widget.onCompleted();});
    }
    return Material(color:Theme.of(context).colorScheme.surfaceContainerHighest,child:ListTile(
      leading:done?const Icon(Icons.check_circle_outline):const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)),
      title:Text(done?'Conversation deletion completed':'Deleting conversations…'),
      subtitle:Text(done?'Deleted messages are no longer available.':'${data['deletedRecords']??0} records removed. Sending is temporarily disabled in affected chats.\n${retryError??data['lastError']??'Continuing cleanup automatically.'}'),
      trailing:done?null:TextButton(onPressed:requesting?null:advance,child:const Text('Retry now')),
    ));
  });
}
class _ThreadList extends StatefulWidget{
  const _ThreadList();
  @override
  State<_ThreadList> createState()=>_ThreadListState();
}
class _ThreadListState extends State<_ThreadList>{
  final repo=SchoolMessageRepository();
  late Future<Map<String,dynamic>> rows=repo.threads();
  String query='';
  late final owner=repo.isOwner();
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('School messages'),actions:[
    IconButton(tooltip:'Refresh conversations',onPressed:()=>setState(()=>rows=repo.threads()),icon:const Icon(Icons.refresh)),
    FutureBuilder<bool>(future:owner,builder:(context,s)=>s.data==true?IconButton(tooltip:'Delete all conversations',icon:const Icon(Icons.delete_sweep_outlined),onPressed:()=>_confirmConversationDeletion(context,repo)):const SizedBox.shrink()),
    _MessageProfileButton(uid:repo.currentUid)
  ]),body:Column(children:[
    FutureBuilder<bool>(future:owner,builder:(context,s)=>s.data==true?_OwnerCleanupStatus(repo:repo,onCompleted:()=>setState(()=>rows=repo.threads())):const SizedBox.shrink()),
    Padding(padding:const EdgeInsets.all(12),child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search conversations'),onChanged:(v)=>setState(()=>query=v.toLowerCase()))),
    Expanded(child:FutureBuilder<Map<String,dynamic>>(future:rows,builder:(context,s){
      if(s.hasError)return Center(child:Text(schoolErrorMessage(s.error!)));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final items=(s.data!['rows'] as List).whereType<Map>().where((x)=>'${x['name']} ${x['role']}'.toLowerCase().contains(query)).toList();
      if(items.isEmpty)return const Center(child:Text('No matching conversations.'));
      return ListView.builder(itemCount:items.length,itemBuilder:(context,i){
        final x=items[i],uid=x['uid'].toString(),name=x['name'].toString();
        return ListTile(leading:AccountPicture(uid:uid,name:name),title:Text(name),subtitle:Text(x['role'].toString()),trailing:FutureBuilder<bool>(future:owner,builder:(context,s)=>s.data==true?PopupMenuButton<String>(tooltip:'Conversation options',onSelected:(v){if(v=='delete')_confirmConversationDeletion(context,repo,uid:uid,name:name);},itemBuilder:(_)=>const [PopupMenuItem(value:'delete',child:Text('Delete conversation for everyone'))]):const Icon(Icons.chevron_right)),
          onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>_Conversation(uid:uid,name:name))));
      });
    }))
  ]));
}
class _Conversation extends StatefulWidget{
  const _Conversation({this.uid,this.name});
  final String? uid,name;
  @override
  State<_Conversation> createState()=>_ConversationState();
}
class _ConversationState extends State<_Conversation>{
  final repo=SchoolMessageRepository();
  final text=TextEditingController();
  final scroll=ScrollController();
  late final String me=repo.currentUid;
  late final owner=repo.isOwner();
  int limit=60;
  late Stream<_Docs> messages=repo.watch(widget.uid,limit);
  late final Stream<_Docs> hidden=repo.hidden(widget.uid);
  late final Stream<_Docs> scheduled=repo.scheduled(widget.uid);
  late final preferences=FirebaseFirestore.instance.collection('chat_preferences').doc(me);
  late final preferenceStream=preferences.snapshots();
  bool busy=false;
  VoiceClip? pendingVoice;
  String? pendingVoiceId;
  bool voiceSending=false;
  String? voiceFailure;
  final Set<String> acknowledging={};
  Future<void> ack(String id,{bool played=false})async{
    if(!acknowledging.add(id)){
      if(played){await Future<void>.delayed(const Duration(milliseconds:300));if(mounted)await ack(id,played:true);}
      return;
    }
    try{await repo.receipt(widget.uid,id,read:true,played:played);}catch(e){if(played)error(e);}
    finally{acknowledging.remove(id);}
  }
  Future<void> recordVoice(VoiceClip clip)async{
    if(!mounted||pendingVoice!=null)return;
    setState((){pendingVoice=clip;pendingVoiceId=repo.reserveMessageId(widget.uid);voiceFailure=null;});
    await uploadVoice();
  }
  Future<void> uploadVoice()async{
    final clip=pendingVoice,id=pendingVoiceId;
    if(clip==null||id==null||voiceSending)return;
    setState((){voiceSending=true;voiceFailure=null;});
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&scroll.hasClients)scroll.jumpTo(0);});
    try{
      await repo.send(widget.uid,'',kind:'voice',attachment:{'durationMs':clip.durationMs,'contentType':'audio/mp4'},voice:clip.bytes,messageId:id);
      if(mounted)setState((){pendingVoice=null;pendingVoiceId=null;});
    }catch(e){
      if(mounted)setState(()=>voiceFailure=schoolErrorMessage(e));
    }finally{if(mounted)setState(()=>voiceSending=false);}
  }
  Widget pendingVoiceBubble(Map<String,dynamic> p,ColorScheme scheme){
    final clip=pendingVoice!;
    final bg=color(p,'outgoing',scheme.primaryContainer),fg=readable(bg);
    return Padding(padding:const EdgeInsets.symmetric(vertical:4,horizontal:8),child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[
      Flexible(child:Container(constraints:const BoxConstraints(maxWidth:300),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
        Row(mainAxisSize:MainAxisSize.min,children:[
          if(voiceSending)SizedBox(width:28,height:28,child:CircularProgressIndicator(strokeWidth:2.5,color:fg))
          else IconButton(tooltip:'Retry voice upload',onPressed:uploadVoice,icon:Icon(Icons.refresh,color:fg)),
          const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Container(height:4,margin:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:fg.withValues(alpha:.3),borderRadius:BorderRadius.circular(4))),
            Text('${clip.durationMs~/60000}:${(clip.durationMs~/1000%60).toString().padLeft(2,'0')}',style:TextStyle(color:fg,fontSize:11)),
          ])),
          if(!voiceSending)IconButton(tooltip:'Discard unsent voice',onPressed:()=>setState((){pendingVoice=null;pendingVoiceId=null;voiceFailure=null;}),icon:Icon(Icons.close,color:fg)),
        ]),
        Text(voiceSending?'Sending voice…':voiceFailure??'Upload failed · Retry',style:TextStyle(color:fg,fontSize:11)),
      ]))),
      const SizedBox(width:6),AccountPicture(uid:me,name:'You',radius:15),
    ]));
  }
  static const emojis=['😀','😂','😊','❤️','👍','🙏','🎉','✅','📚','✏️','⭐','🤝','😢','👏','🌷','👋'];
  void error(Object e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(schoolErrorMessage(e))));}
  @override
  void dispose(){text.dispose();scroll.dispose();super.dispose();}
  Future<void> send({String? value,String kind='text',Map<String,dynamic>? attachment,DateTime? at,Uint8List? voice})async{
    final content=value??text.text.trim();
    if(busy||(content.isEmpty&&attachment==null))return;
    setState(()=>busy=true);
    try{
      await repo.send(widget.uid,content,kind:kind,attachment:attachment,sendAt:at,voice:voice);
      if(mounted){
        if(value==null&&text.text.trim()==content)text.clear();
        if(at!=null)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Message scheduled. Requires the school delivery service.')));
        if(scroll.hasClients)scroll.animateTo(0,duration:const Duration(milliseconds:200),curve:Curves.easeOut);
      }
    }catch(e){error(e);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> attach()async{
    try{
      final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf','png','jpg','jpeg','webp','txt'],withData:true);
      final f=picked?.files.single;
      if(f==null||!mounted)return;
      final bytes=f.bytes;
      if(bytes==null||bytes.isEmpty||bytes.length>524288)throw StateError('Choose a document no larger than 512 KB.');
      const mime={'pdf':'application/pdf','png':'image/png','jpg':'image/jpeg','jpeg':'image/jpeg','webp':'image/webp','txt':'text/plain'};
      final type=mime[f.extension?.toLowerCase()];
      if(type==null)throw StateError('Unsupported document format.');
      final name=f.name.replaceAll(RegExp(r'[\r\n]'),' ');
      await send(kind:'file',attachment:{'name':name.length>120?name.substring(0,120):name,'bytes':Blob(bytes),'contentType':type});
    }catch(e){error(e);}
  }
  Future<void> download(Map a)async{
    try{
      final blob=a['bytes'];
      if(blob is! Blob)return;
      final name=(a['name']??'document').toString().replaceAll(RegExp(r'[/\\\r\n]'),'_');
      await FilePicker.platform.saveFile(dialogTitle:'Save attachment',fileName:name,bytes:blob.bytes);
    }catch(e){error(e);}
  }
  Future<void> schedule()async{
    if(text.text.trim().isEmpty){error(StateError('Write a message first.'));return;}
    final now=DateTime.now();
    final day=await showDatePicker(context:context,initialDate:now,firstDate:DateUtils.dateOnly(now),lastDate:now.add(const Duration(days:365)));
    if(day==null||!mounted)return;
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(now.add(const Duration(minutes:5))));
    if(time==null||!mounted)return;
    final at=DateTime(day.year,day.month,day.day,time.hour,time.minute);
    if(!at.isAfter(DateTime.now())){error(StateError('Choose a future time.'));return;}
    await send(at:at);
  }
  Future<void> queue()async{
    await showModalBottomSheet<void>(context:context,builder:(context)=>SafeArea(child:StreamBuilder<_Docs>(stream:scheduled,builder:(context,s){
      if(s.hasError)return Padding(padding:const EdgeInsets.all(20),child:Text(schoolErrorMessage(s.error!)));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final docs=s.data!.docs.toList()..sort((a,b)=>(a.data()['sendAt'] as Timestamp).compareTo(b.data()['sendAt'] as Timestamp));
      return ListView(shrinkWrap:true,children:[
        const ListTile(title:Text('Scheduled messages'),subtitle:Text('Delivery runs approximately every five minutes when deployed.')),
        if(docs.isEmpty)const ListTile(title:Text('No pending messages')),
        for(final d in docs)ListTile(title:Text(d.data()['text'].toString()),subtitle:Text(stamp(d.data()['sendAt'])),
          trailing:IconButton(tooltip:'Cancel scheduled message',icon:const Icon(Icons.cancel_outlined),onPressed:()async{try{await repo.cancel(widget.uid,d.id);}catch(e){error(e);}}))
      ]);
    })));
  }
  String stamp(dynamic v){
    if(v is! Timestamp)return 'Sending…';
    final d=v.toDate().toLocal();
    final l=MaterialLocalizations.of(context);
    return '${l.formatShortDate(d)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }
  Future<void> picker(bool stickers)async{
    await showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:Wrap(spacing:8,runSpacing:8,children:[
      for(final e in emojis)InkWell(onTap:(){
        Navigator.pop(ctx);
        if(stickers){send(value:e,kind:'sticker');}else{
          final sel=text.selection;
          final start=sel.isValid?sel.start:text.text.length;
          final end=sel.isValid?sel.end:start;
          final newText=text.text.replaceRange(start,end,e);
          text.value=TextEditingValue(text:newText,selection:TextSelection.collapsed(offset:start+e.length));
        }
      },child:Padding(padding:const EdgeInsets.all(9),child:Text(e,style:TextStyle(fontSize:stickers?44:28))))
    ]))));
  }
  Future<void> options(String id,Map<String,dynamic> m)async{
    final action=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.visibility_off_outlined),title:const Text('Delete for me'),onTap:()=>Navigator.pop(ctx,'hide')),
      if(m['senderUid']==me&&m['deleted']!=true)ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Delete for everyone'),onTap:()=>Navigator.pop(ctx,'retract'))
    ])));
    try{
      if(action=='hide'){await repo.hide(widget.uid,id);await repo.discardVoiceCache(widget.uid,id);}
      if(action=='retract'){await repo.retract(widget.uid,id);await repo.discardVoiceCache(widget.uid,id);}
    }catch(e){error(e);}
  }
  Color readable(Color c)=>c.computeLuminance()>.42?Colors.black:Colors.white;
  Color color(Map<String,dynamic> p,String key,Color fallback)=>p[key] is int?Color(p[key] as int):fallback;
  Future<void> colors(Map<String,dynamic> p,ColorScheme scheme)async{
    final result=await showDialog<Map<String,int>>(context:context,builder:(_)=>_ChatColors(initial:{
      'background':color(p,'background',scheme.surface).toARGB32(),
      'outgoing':color(p,'outgoing',scheme.primaryContainer).toARGB32(),
      'incoming':color(p,'incoming',scheme.surfaceContainerHighest).toARGB32(),
    }));
    if(result!=null){try{await preferences.set(result);}catch(e){error(e);}}
  }
  Widget bubble(QueryDocumentSnapshot<Map<String,dynamic>> d,Map<String,dynamic> p,ColorScheme scheme){
    final m=d.data(),mine=m['senderUid']==me,deleted=m['deleted']==true;
    final sender=m['senderUid']?.toString()??'',name=mine?'You':m['fromSchool']==true?'School administration':widget.name??'Participant';
    final bg=color(p,mine?'outgoing':'incoming',mine?scheme.primaryContainer:scheme.surfaceContainerHighest),fg=readable(bg);
    final a=m['attachment'];
    final callRecord=m['kind']=='call'&&!deleted;
    return VisibilityDetector(key:ValueKey('visible-${d.id}'),onVisibilityChanged:(v){
      if(mounted&&!mine&&!deleted&&v.visibleFraction>=0.5&&ModalRoute.of(context)?.isCurrent==true&&WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed&&(m['deliveredAt']==null||(m['kind']!='voice'&&m['readAt']==null)))unawaited(ack(d.id));
    },child:Padding(padding:const EdgeInsets.symmetric(vertical:4,horizontal:8),child:Row(mainAxisAlignment:mine?MainAxisAlignment.end:MainAxisAlignment.start,crossAxisAlignment:CrossAxisAlignment.end,children:[
      if(!mine)...[AccountPicture(uid:sender,name:name,radius:15),const SizedBox(width:6)],
      Flexible(child:ConstrainedBox(constraints:BoxConstraints(maxWidth:callRecord?220:480),child:Material(color:bg,borderRadius:BorderRadius.circular(14),child:InkWell(borderRadius:BorderRadius.circular(14),onLongPress:()=>options(d.id,m),child:Padding(padding:callRecord?const EdgeInsets.fromLTRB(10,5,10,6):const EdgeInsets.fromLTRB(12,8,8,6),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(name,style:TextStyle(color:fg,fontSize:11,fontWeight:FontWeight.w600))),
          IconButton(visualDensity:VisualDensity.compact,constraints:callRecord?const BoxConstraints(minWidth:32,minHeight:28):null,padding:callRecord?EdgeInsets.zero:null,tooltip:'Message options',iconSize:16,color:fg,onPressed:()=>options(d.id,m),icon:const Icon(Icons.more_vert))]),
        if(deleted)Text('This message was deleted',style:TextStyle(color:fg,fontStyle:FontStyle.italic))
        else...[
          if(m['kind']=='call')InkWell(
            borderRadius:BorderRadius.circular(10),
            onTap:()=>OfficeCalls.dial(context,targetUid:widget.uid,name:widget.name),
            child:Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(mainAxisSize:MainAxisSize.min,children:[
              Container(width:34,height:34,decoration:BoxDecoration(shape:BoxShape.circle,color:fg.withValues(alpha:.08)),
                child:Icon(m['callStatus']=='completed'?(mine?Icons.call_made:Icons.call_received):Icons.call_missed,
                  size:19,color:m['callStatus']=='completed'?fg:Colors.redAccent)),
              const SizedBox(width:9),
              Flexible(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(m['callStatus']=='completed'?'Voice call':m['callStatus']=='declined'?'Declined call':'Missed call',
                  style:TextStyle(color:fg,fontSize:13,fontWeight:FontWeight.w600)),
                const SizedBox(height:2),
                Text(m['callStatus']=='completed'?'${(m['durationSeconds'] as num? ?? 0).toInt()~/60} min ${(m['durationSeconds'] as num? ?? 0).toInt()%60} sec':mine?'Outgoing call':'Incoming call',
                  style:TextStyle(color:fg.withValues(alpha:.8),fontSize:11)),
              ])),
            ]))),
          if((m['text']??'').toString().isNotEmpty)Text(m['text'].toString(),style:TextStyle(color:fg,fontSize:m['kind']=='sticker'?48:15)),
          if(m['kind']=='voice'&&a is Map)SchoolVoicePlayer(key:ValueKey(d.id),durationMs:(a['durationMs'] as num?)?.toInt()??0,load:()=>repo.voiceFile(widget.uid,d.id),onPlayed:mine?null:()=>ack(d.id,played:true),foreground:fg)
          else if(a is Map)TextButton.icon(style:TextButton.styleFrom(foregroundColor:fg),onPressed:()=>download(a),icon:const Icon(Icons.file_download_outlined),label:Flexible(child:Text((a['name']??'Attachment').toString(),overflow:TextOverflow.ellipsis))),
        ],
        Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(stamp(m['createdAt']),style:TextStyle(color:fg,fontSize:10))),if(mine&&!deleted&&m['kind']!='call')...[const SizedBox(width:4),Tooltip(message:d.metadata.hasPendingWrites?'Sending':m['readAt']!=null?'Read / played':m['deliveredAt']!=null?'Delivered · unread':'Sent',child:Icon(d.metadata.hasPendingWrites?Icons.schedule:m['deliveredAt']!=null?Icons.done_all:Icons.done,size:16,color:m['readAt']!=null?Colors.lightBlueAccent:fg.withValues(alpha:.65)))]]),
      ])))))),
      if(mine)...[const SizedBox(width:6),AccountPicture(uid:sender,name:name,radius:15)]
    ])));
  }
  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:preferenceStream,builder:(context,pref){
      final p=pref.data?.data()??{};
      return Scaffold(appBar:AppBar(title:Text(widget.name??'School messages'),actions:[
        IconButton(tooltip:widget.uid==null?'Call school office':'Call participant',onPressed:()=>OfficeCalls.dial(context,targetUid:widget.uid,name:widget.name),icon:const Icon(Icons.call_outlined)),
        IconButton(tooltip:'Scheduled messages',onPressed:queue,icon:const Icon(Icons.schedule)),
        IconButton(tooltip:'Chat colors',onPressed:()=>colors(p,scheme),icon:const Icon(Icons.palette_outlined)),
        FutureBuilder<bool>(future:owner,builder:(context,s)=>s.data==true&&widget.uid!=null?IconButton(tooltip:'Delete conversation for everyone',icon:const Icon(Icons.delete_outline),onPressed:()async{if(await _confirmConversationDeletion(context,repo,uid:widget.uid,name:widget.name)&&context.mounted)Navigator.pop(context);}):const SizedBox.shrink()),
        _MessageProfileButton(uid:me),
      ]),body:SafeArea(child:Column(children:[
        Expanded(child:ColoredBox(color:color(p,'background',scheme.surface),child:StreamBuilder<_Docs>(stream:hidden,builder:(context,h){
          final hiddenIds=h.data?.docs.map((x)=>x.id).toSet()??<String>{};
          return StreamBuilder<_Docs>(stream:messages,builder:(context,s){
            if(s.hasError)return Center(child:Text(schoolErrorMessage(s.error!)));
            if(h.hasError)return Center(child:Text(schoolErrorMessage(h.error!)));
            if((!s.hasData||!h.hasData)&&pendingVoice==null)return const Center(child:CircularProgressIndicator());
            final docs=(s.data?.docs??[]).where((d)=>!hiddenIds.contains(d.id)).toList();
            final showPending=pendingVoice!=null&&!docs.any((d)=>d.id==pendingVoiceId&&!d.metadata.hasPendingWrites);
            final visibleDocs=docs.where((d)=>!showPending||d.id!=pendingVoiceId).toList();
            final offset=showPending?1:0;
            final more=(s.data?.docs.length??0)>=limit;
            if(visibleDocs.isEmpty&&!more&&!showPending)return const Center(child:Text('No messages yet.'));
            return ListView.builder(controller:scroll,reverse:true,padding:const EdgeInsets.symmetric(vertical:8),itemCount:visibleDocs.length+offset+(more?1:0),itemBuilder:(context,i){
              if(showPending&&i==0)return pendingVoiceBubble(p,scheme);
              final index=i-offset;
              if(index==visibleDocs.length)return Center(child:TextButton(onPressed:()=>setState((){limit+=60;messages=repo.watch(widget.uid,limit);}),child:const Text('Load older messages')));
              return bubble(visibleDocs[index],p,scheme);
            });
          });
        }))),
        if(busy)const LinearProgressIndicator(),
        InlineVoiceComposer(controller:text,enabled:!busy&&pendingVoice==null,onSendText:()=>send(),onVoice:recordVoice,onError:error,leading:[
          PopupMenuButton<String>(tooltip:'More message options',icon:const Icon(Icons.add_circle_outline),onSelected:(v){if(v=='file')attach();if(v=='sticker')picker(true);if(v=='schedule')schedule();},itemBuilder:(_)=>const [
            PopupMenuItem(value:'file',child:Text('Attach document')),
            PopupMenuItem(value:'sticker',child:Text('Send sticker')),
            PopupMenuItem(value:'schedule',child:Text('Schedule message'))]),
          IconButton(tooltip:'Emoji',onPressed:()=>picker(false),icon:const Icon(Icons.emoji_emotions_outlined)),
        ])

      ])));
    });
  }
}
class _ChatColors extends StatefulWidget{
  const _ChatColors({required this.initial});
  final Map<String,int> initial;
  @override
  State<_ChatColors> createState()=>_ChatColorsState();
}
class _ChatColorsState extends State<_ChatColors>{
  late final values=Map<String,int>.from(widget.initial);
  String selected='background';
  @override
  Widget build(BuildContext context){
    final c=Color(values[selected]!);
    return AlertDialog(title:const Text('Chat colors'),content:SizedBox(width:350,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButton<String>(value:selected,items:const [DropdownMenuItem(value:'background',child:Text('Chat background')),DropdownMenuItem(value:'outgoing',child:Text('Sent message')),DropdownMenuItem(value:'incoming',child:Text('Received message'))],onChanged:(v)=>setState(()=>selected=v!)),
      Container(height:44,decoration:BoxDecoration(color:c,borderRadius:BorderRadius.circular(8))),
      for(final i in [0,1,2])...[
        Align(alignment:Alignment.centerLeft,child:Text(['Red','Green','Blue'][i])),
        Slider(min:0,max:255,divisions:255,value:((values[selected]!>>(16-i*8))&255).toDouble(),onChanged:(v)=>setState((){
          final shift=16-i*8;values[selected]=(values[selected]!&~(255<<shift))|(v.round()<<shift)|0xff000000;
        })),
      ],
      Wrap(spacing:8,runSpacing:8,children:[for(final v in [0xffeff3f1,0xffd9fdd3,0xffe7e5ff,0xffd8edff,0xffffe6d2,0xff263238,0xff005c4b,0xff455a64])
        InkWell(onTap:()=>setState(()=>values[selected]=v),child:CircleAvatar(radius:16,backgroundColor:Color(v)))]),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,values),child:const Text('Save colors'))]);
  }
}
