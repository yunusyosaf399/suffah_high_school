import 'dart:typed_data';
import '../data/teacher_portal_repository.dart';
import 'school_voice_message.dart';
import 'call_audio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class AccountPicture extends StatelessWidget {
  const AccountPicture({super.key,required this.uid,required this.name,this.radius=18});
  final String uid,name;
  final double radius;
  @override
  Widget build(BuildContext context){
    final fallback=CircleAvatar(radius:radius,child:Text(name.trim().isEmpty?'?':name.trim().characters.first.toUpperCase()));
    if(uid.isEmpty)return fallback;
    // Keep the picture stream alive across ordinary rebuilds.
    return _PictureStream(key:ValueKey(uid),uid:uid,radius:radius,fallback:fallback);
  }
}
class _PictureStream extends StatefulWidget {
  const _PictureStream({super.key,required this.uid,required this.radius,required this.fallback});
  final String uid;
  final double radius;
  final Widget fallback;
  @override
  State<_PictureStream> createState()=>_PictureStreamState();
}
class _PictureStreamState extends State<_PictureStream>{
  Stream<DocumentSnapshot<Map<String,dynamic>>>? _stream;
  @override
  void initState(){
    super.initState();
    try{_stream=FirebaseFirestore.instance.collection('account_pictures').doc(widget.uid).snapshots();}
    catch(_){}
  }
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:_stream,builder:(context,snapshot){
      final v=snapshot.data?.data()?['image'];
      if(snapshot.hasError||v is! Blob)return widget.fallback;
      return ClipOval(child:Image.memory(v.bytes,width:widget.radius*2,height:widget.radius*2,
        fit:BoxFit.cover,cacheWidth:256,errorBuilder:(_,__,___)=>widget.fallback));
    });
}
class AccountPicturePage extends StatefulWidget{
  const AccountPicturePage({super.key,this.fromMessages=false});
  final bool fromMessages;
  @override
  State<AccountPicturePage> createState()=>_AccountPicturePageState();
}
class _AccountPicturePageState extends State<AccountPicturePage>{
  bool busy=false;
  SchoolMessageRepository? messageRepo;
  Future<bool>? ownerAccess;
  @override
  void initState(){
    super.initState();
    if(widget.fromMessages){
      try{
        messageRepo=SchoolMessageRepository();
        ownerAccess=messageRepo!.isOwner();
      }catch(_){}
    }
  }
  Future<void> change(bool remove)async{
    if(busy)return;
    setState(()=>busy=true);
    try{
      final uid=FirebaseAuth.instance.currentUser?.uid;
      if(uid==null)throw StateError('Sign in first.');
      final ref=FirebaseFirestore.instance.collection('account_pictures').doc(uid);
      if(remove){await ref.delete();return;}
      final picked=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);
      final bytes=picked?.files.single.bytes;
      if(bytes==null)return;
      Uint8List? compressed;
      for(final quality in [75,50,30,15]){
        try{
          final b=await FlutterImageCompress.compressWithList(bytes,minWidth:256,minHeight:256,quality:quality,format:CompressFormat.jpeg);
          if(b.isNotEmpty&&b.length<=102400){compressed=b;break;}
        }catch(_){break;}
      }
      // Windows plugin availability varies. Small original images also work.
      if(compressed==null&&bytes.length<=102400)compressed=bytes;
      if(compressed==null)throw StateError('Choose a smaller image (100 KB or less), or compress it first.');
      await ref.set({'image':Blob(compressed),'updatedAt':FieldValue.serverTimestamp()});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.fromMessages?'Message profile':'Account picture')),
    body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Column(mainAxisSize:MainAxisSize.min,children:[
      AccountPicture(uid:FirebaseAuth.instance.currentUser?.uid??'',name:'Me',radius:60),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:busy?null:()=>change(false),icon:const Icon(Icons.photo_library_outlined),label:const Text('Upload or replace picture')),
      TextButton(onPressed:busy?null:()=>change(true),child:const Text('Remove picture')),
      if(busy)const CircularProgressIndicator(),
      if(widget.fromMessages)Card(child:ListTile(leading:const Icon(Icons.music_note),title:const Text('Call ringtone'),subtitle:const Text('Choose your own ringing sound'),trailing:const Icon(Icons.chevron_right),onTap:()=>SchoolCallAudio.choose(context))),
      if(widget.fromMessages&&messageRepo!=null)FutureBuilder<bool>(future:ownerAccess,builder:(context,access){
        if(access.data!=true)return const SizedBox.shrink();
        final repo=messageRepo!;
        return Padding(padding:const EdgeInsets.only(top:24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Divider(),
          Text('Message settings',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:8),
          Card(child:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:repo.voiceSettings.snapshots(),builder:(context,s){
            final mode=s.data?.data()?['mode'];
            final description=s.hasError?'Settings unavailable':!s.hasData?'Loading…':mode=='7days'?'Delete after 7 days':mode=='14days'?'Delete after 14 days':'Delete after recipient finishes playback';
            return ListTile(leading:const Icon(Icons.auto_delete_outlined),title:const Text('Automatic voice message deletion'),subtitle:Text(description),trailing:const Icon(Icons.chevron_right),onTap:()=>showVoiceRetention(context,repo));
          })),
          const Text('School-wide setting for new voice messages. Only the owner can change it.'),
        ]));
      }),
    ])))));
}
