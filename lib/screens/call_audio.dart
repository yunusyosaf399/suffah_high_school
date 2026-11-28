import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchoolCallAudio {
  static const native=MethodChannel('suffah/call_audio');
  static bool get android=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  static String get uid=>FirebaseAuth.instance.currentUser?.uid??'';
  static Future<String> channelId()async{
    if(!android)return 'school_calls';
    try{return await native.invokeMethod<String>('channelId',{'uid':uid})??'school_calls';}catch(_){return 'school_calls';}
  }
  static Future<bool> startService()async{
    if(!android)return false;
    try{return await native.invokeMethod<bool>('startService')??false;}catch(_){return false;}
  }
  static Future<void> stopService()async{if(android){try{await native.invokeMethod<void>('stopService');}catch(_){}}}
  static Future<void> choose(BuildContext context)async{
    final account=uid;
    if(account.isEmpty)return;
    try{
      if(android){
        if(await native.invokeMethod<bool>('chooseRingtone',{'uid':account})!=true)return;
        final token=await FirebaseMessaging.instance.getToken();
        if(token!=null&&uid==account)await FirebaseFirestore.instance.collection('push_devices').doc(token).set({
          'uid':account,'updatedAt':FieldValue.serverTimestamp(),'callChannel':await channelId(),
        },SetOptions(merge:true));
      }else{
        final reset=await showDialog<bool>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Call ringtone'),children:[
          SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Choose audio file')),
          SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Restore default ringing sound')),
        ]));
        if(reset==null)return;
        final prefs=await SharedPreferences.getInstance();
        final key='school_ringtone_$account';
        if(reset){final old=prefs.getString(key);await prefs.remove(key);if(old!=null){try{await File(old).delete();}catch(_){}}}
        else{
          final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['wav','mp3','m4a','ogg'],withData:false);
          final path=picked?.files.single.path;
          if(path==null)return;
          final dir=await getApplicationSupportDirectory();
          await dir.create(recursive:true);
          final ext=picked!.files.single.extension??'wav';
          final file=File('${dir.path}/ringtone-$account.$ext');
          if(await File(path).length()>20*1024*1024)throw StateError('Choose an audio file smaller than 20 MB.');
          if(path!=file.path)await File(path).copy(file.path);
          final old=prefs.getString(key);await prefs.setString(key,file.path);
          if(old!=null&&old!=file.path){try{await File(old).delete();}catch(_){}}
        }
      }
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Call ringtone saved on this device.')));
    }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not set ringtone: $e')));}
  }
  static bool get windows=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.windows;
  AudioPlayer? player;
  Timer? windowsRepeat;
  bool disposed=false;
  int generation=0;
  Future<void> audioTail=Future<void>.value();
  Future<void> ordered(Future<void> Function() work){
    final next=audioTail.then((_)=>work());
    audioTail=next.then<void>((_){},onError:(Object _,StackTrace __){});
    return next;
  }
  Future<void> ring({bool outgoing=false}){
    final run=++generation;
    return ordered(()async{
    if(disposed||run!=generation)return;
    try{
      if(android&&!outgoing){await native.invokeMethod<void>('ring',{'uid':uid});if(disposed||run!=generation)await native.invokeMethod<void>('stopRing');return;}
      final prefs=await SharedPreferences.getInstance();
      final custom=outgoing?null:prefs.getString('school_ringtone_$uid');
      final path=custom!=null&&await File(custom).exists()?custom:await _toneFile(outgoing);
      if(disposed||run!=generation)return;
      if(windows){
        // Native WinMM ringtone avoids creating a second Flutter audio plugin
        // player alongside the Windows WebRTC capture device.
        debugPrint('Office call: starting Windows ringtone');
        final ok=await native.invokeMethod<bool>('ringFile',{'path':path});
        if(ok!=true){await native.invokeMethod<bool>('ringFile',{'path':await _toneFile(outgoing)});}
        if(disposed||run!=generation){await native.invokeMethod<void>('stopRing');return;}
        windowsRepeat?.cancel();
        windowsRepeat=Timer.periodic(const Duration(seconds:1),(_){
          if(!disposed&&run==generation)unawaited(ordered(()async{
            if(!disposed&&run==generation){try{await native.invokeMethod<void>('repeatRing');}catch(_){}}
          }));
        });
        return;
      }
      final p=player??=AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      if(disposed||run!=generation)return;
      await p.play(DeviceFileSource(path),volume:outgoing ? 0.32 : 0.8);
      if(disposed||run!=generation)await p.stop();
    }catch(_){if(!disposed&&run==generation){try{await SystemSound.play(SystemSoundType.alert);}catch(_){}}}
    });
  }
  Future<void> stop(){
    generation++;
    windowsRepeat?.cancel();windowsRepeat=null;
    return ordered(()async{
      try{await player?.stop();}catch(_){}
      if(android||windows){try{await native.invokeMethod<void>('stopRing');}catch(_){}}
      if(windows)debugPrint('Office call: Windows ringtone stopped');
    });
  }
  Future<void> dispose()async{
    if(disposed)return;
    disposed=true;await stop();
    await ordered(()async{final p=player;player=null;try{await p?.dispose();}catch(_){}});
  }
  static Future<String> _toneFile(bool outgoing)async{
    final dir=await getTemporaryDirectory();
    final f=File('${dir.path}/school-ring-${outgoing?'out':'in'}-v1.wav');
    if(await f.exists())return f.path;
    const rate=16000,samples=rate*3;
    final data=ByteData(44+samples*2);
    void tag(int offset,String s){for(var i=0;i<s.length;i++){data.setUint8(offset+i,s.codeUnitAt(i));}}
    tag(0,'RIFF');data.setUint32(4,36+samples*2,Endian.little);tag(8,'WAVE');tag(12,'fmt ');
    data.setUint32(16,16,Endian.little);data.setUint16(20,1,Endian.little);data.setUint16(22,1,Endian.little);
    data.setUint32(24,rate,Endian.little);data.setUint32(28,rate*2,Endian.little);
    data.setUint16(32,2,Endian.little);data.setUint16(34,16,Endian.little);tag(36,'data');data.setUint32(40,samples*2,Endian.little);
    for(var i=0;i<samples;i++){
      final t=i/rate;
      final pulse=t<0.45||(t>0.65&&t<1.10);
      final value=pulse?((math.sin(2*math.pi*440*t)+math.sin(2*math.pi*(outgoing?480:660)*t))*4500).round():0;
      data.setInt16(44+i*2,value,Endian.little);
    }
    await f.writeAsBytes(data.buffer.asUint8List(),flush:true);return f.path;
  }
}
