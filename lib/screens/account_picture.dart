import 'dart:typed_data';
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
  const AccountPicturePage({super.key});
  @override
  State<AccountPicturePage> createState()=>_AccountPicturePageState();
}
class _AccountPicturePageState extends State<AccountPicturePage>{
  bool busy=false;
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
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Account picture')),
    body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      AccountPicture(uid:FirebaseAuth.instance.currentUser?.uid??'',name:'Me',radius:60),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:busy?null:()=>change(false),icon:const Icon(Icons.photo_library_outlined),label:const Text('Upload or replace picture')),
      TextButton(onPressed:busy?null:()=>change(true),child:const Text('Remove picture')),
      if(busy)const CircularProgressIndicator(),
    ])));
}
