import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/admission_storage.dart';

/// Private, lazy thumbnail. No public URL or persistent cross-account cache.
class StudentAvatar extends StatefulWidget {
  const StudentAvatar({super.key,required this.studentId,required this.name,
    this.photoPath,this.radius=20});
  final String studentId,name;
  final String? photoPath;
  final double radius;
  @override
  State<StudentAvatar> createState()=>_StudentAvatarState();
}
class _StudentAvatarState extends State<StudentAvatar> {
  Future<Uint8List?>? _photo;
  @override
  void initState(){super.initState();_load();}
  @override
  void didUpdateWidget(covariant StudentAvatar old){
    super.didUpdateWidget(old);
    if(old.studentId!=widget.studentId||old.photoPath!=widget.photoPath)_load();
  }
  void _load(){
    _photo=null;
    if(!AdmissionStorage.isConfigured||widget.studentId.isEmpty||widget.photoPath=='')return;
    _photo=_fetch();
  }
  Future<Uint8List?> _fetch()async{
    AdmissionStorage? storage;
    try{
      final uid=FirebaseAuth.instance.currentUser?.uid;
      if(uid==null)return null;
      storage=AdmissionStorage();
      final bytes=await storage.downloadStudentPhoto(widget.studentId);
      if(FirebaseAuth.instance.currentUser?.uid!=uid)return null;
      return bytes;
    }catch(_){return null;}finally{storage?.close();}
  }
  @override
  Widget build(BuildContext context){
    final name=widget.name.trim();
    final initial=name.isEmpty?'?':name.characters.first.toUpperCase();
    final fallback=CircleAvatar(radius:widget.radius,child:Text(initial,
      style:const TextStyle(fontWeight:FontWeight.w700)));
    return FutureBuilder<Uint8List?>(key:ValueKey(widget.studentId+'|'+(widget.photoPath??'')),
      future:_photo,builder:(context,snapshot){
        final bytes=snapshot.data;
        if(bytes==null||bytes.isEmpty)return fallback;
        return ClipOval(child:Image.memory(bytes,width:widget.radius*2,height:widget.radius*2,
          fit:BoxFit.cover,cacheWidth:128,errorBuilder:(_,__,___)=>fallback));
      });
  }
}

/// Explicit repair for existing photo references. No image bytes are copied.
Future<int> syncStudentPhotoDirectory()async{
  final db=FirebaseFirestore.instance;
  QueryDocumentSnapshot<Map<String,dynamic>>? last;
  var count=0;
  while(true){
    final q=db.collection('students').orderBy(FieldPath.documentId).limit(100);
    final page=await (last==null?q:q.startAfterDocument(last)).get(const GetOptions(source:Source.server));
    if(page.docs.isEmpty)break;
    final batch=db.batch();
    for(final d in page.docs){
      batch.set(db.collection('student_photo_directory').doc(d.id),
        {'photoPath':d.data()['photoPath'] as String? ?? ''});
      count++;
    }
    await batch.commit();
    last=page.docs.last;
    if(page.docs.length<100)break;
  }
  return count;
}
