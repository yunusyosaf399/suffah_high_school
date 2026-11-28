import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/school_user_service.dart';
import '../data/school_backup_repository.dart';

class BackupExportPage extends StatefulWidget {
  const BackupExportPage({super.key});
  @override
  State<BackupExportPage> createState()=>_BackupExportPageState();
}
class _BackupExportPageState extends State<BackupExportPage>{
  String format='json',status='';
  bool busy=false;
  int count=0;
  Future<void> run()async{
    if(busy||FirebaseAuth.instance.currentUser?.uid!=schoolOwnerUid)return;
    final confirm=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Export confidential school records?'),
      content:const Text('This file contains private student, guardian, staff and financial information. Keep it in secure storage. Firestore reads may incur usage charges.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Export'))],
    ));
    if(confirm!=true||!mounted)return;
    setState((){busy=true;count=0;status='Reading Firestore…';});
    try{
      final repository=SchoolBackupRepository();
      final documents=await repository.readAll((label,n){if(mounted)setState((){status=label;count=n;});});
      if(!mounted)return;
      setState(()=>status='Preparing file…');
      final chosen=format;
      // Encode on a separate isolate where the platform supports it.
      final bytes=await compute(encodeSchoolBackupJob,(documents,chosen));
      repository.requireOwner();
      if(!mounted)return;
      final stamp=DateTime.now().toUtc().toIso8601String().replaceAll(':','-');
      final saved=await FilePicker.platform.saveFile(dialogTitle:'Save school export',
        fileName:'suffah-school-$stamp.${chosen=='csv'?'zip':chosen}',bytes:bytes);
      if(mounted)setState(()=>status=saved==null?'Save cancelled.':'Export saved: $count documents.');
    }catch(e){if(mounted)setState(()=>status='Export failed: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context){
    if(FirebaseAuth.instance.currentUser?.uid!=schoolOwnerUid)return Scaffold(appBar:AppBar(title:const Text('Backup & Export')),body:const Center(child:Text('Owner access only.')));
    return Scaffold(appBar:AppBar(title:const Text('Backup & Export')),body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(Icons.security_outlined,size:36,color:Theme.of(context).colorScheme.primary),
        const SizedBox(height:12),Text('School database export',style:Theme.of(context).textTheme.titleLarge),
        const Text('Owner only • Server data • Includes known nested collections'),
        const SizedBox(height:8),const Text('Export students, staff, fees, payroll, attendance, exams, inventory, messages and school account records.'),
      ]))),
      const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:format,decoration:const InputDecoration(labelText:'File format',border:OutlineInputBorder()),
        items:const [DropdownMenuItem(value:'json',child:Text('JSON — typed database records')),DropdownMenuItem(value:'xlsx',child:Text('Excel (.xlsx) — worksheets')),DropdownMenuItem(value:'csv',child:Text('CSV — ZIP of individual tables'))],
        onChanged:busy?null:(v){if(v!=null)setState(()=>format=v);}),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:busy?null:run,icon:const Icon(Icons.download),label:const Text('Download school data')),
      if(busy)const LinearProgressIndicator(),
      if(status.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text('$status\n$count documents read')),
      const SizedBox(height:12),
      const Text('Exports are not atomic snapshots. Authentication passwords, Cloudflare file contents, unknown collections and restore operations are not included. Files are not encrypted; store them securely.'),
    ]));
  }
}
