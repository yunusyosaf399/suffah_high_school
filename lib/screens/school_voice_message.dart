import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../data/teacher_portal_repository.dart';

class VoiceClip {
  const VoiceClip(this.bytes,this.durationMs);
  final Uint8List bytes;
  final int durationMs;
}
String _time(int ms)=>'${ms~/60000}:${(ms~/1000%60).toString().padLeft(2,'0')}';

class VoiceRecorderDialog extends StatefulWidget{
  const VoiceRecorderDialog({super.key});
  @override
  State<VoiceRecorderDialog> createState()=>_VoiceRecorderDialogState();
}
class _VoiceRecorderDialogState extends State<VoiceRecorderDialog>{
  final recorder=AudioRecorder();
  final clock=Stopwatch();
  Timer? timer;
  String? path;
  String? problem;
  bool recording=false,working=false;
  @override
  void dispose(){
    timer?.cancel();
    unawaited(_clean());
    super.dispose();
  }
  Future<void> _clean()async{
    try{await recorder.dispose();}catch(_){}
    try{if(path!=null)await File(path!).delete();}catch(_){}
  }
  Future<void> start()async{
    setState(()=>working=true);
    try{
      if(!await recorder.hasPermission())throw StateError('Microphone permission is required.');
      if(!await recorder.isEncoderSupported(AudioEncoder.aacLc))throw StateError('AAC recording is unavailable on this device.');
      final dir=await getTemporaryDirectory();
      path='${dir.path}/school-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc,bitRate:32000,sampleRate:24000,numChannels:1),path:path!);
      clock.reset();clock.start();
      if(!mounted)return;
      setState(()=>recording=true);
      timer=Timer.periodic(const Duration(milliseconds:250),(_){
        if(!mounted)return;
        if(clock.elapsedMilliseconds>=300000){unawaited(stop());}
        else{setState((){});}
      });
    }catch(e){if(mounted)setState(()=>problem=e.toString());}
    finally{if(mounted)setState(()=>working=false);}
  }
  Future<void> stop()async{
    if(working||!recording)return;
    setState(()=>working=true);
    timer?.cancel();clock.stop();
    try{
      final p=await recorder.stop();
      if(p==null)throw StateError('No recording was captured.');
      final bytes=await File(p).readAsBytes();
      if(bytes.isEmpty||bytes.length>3000000)throw StateError('Recording is empty or too large.');
      if(mounted)Navigator.pop(context,VoiceClip(bytes,clock.elapsedMilliseconds.clamp(1,300000).toInt()));
    }catch(e){if(mounted)setState((){problem=e.toString();recording=false;working=false;});}
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Record voice message'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    Icon(recording?Icons.mic:Icons.mic_none,size:48,color:recording?Colors.red:null),
    Text(_time(clock.elapsedMilliseconds),style:Theme.of(context).textTheme.headlineMedium),
    const Text('Maximum 5 minutes · sends when you stop'),
    if(problem!=null)Text(problem!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  ]),actions:[TextButton(onPressed:working?null:()=>Navigator.pop(context),child:const Text('Cancel')),
    FilledButton.icon(onPressed:working?null:recording?stop:start,icon:Icon(recording?Icons.send:Icons.mic),label:Text(recording?'Stop and send':'Start recording'))]);
}
class SchoolVoicePlayer extends StatefulWidget{
  const SchoolVoicePlayer({super.key,required this.durationMs,required this.load,required this.foreground,this.onPlayed});
  final int durationMs;
  final Future<Uint8List> Function() load;
  final Future<void> Function()? onPlayed;
  final Color foreground;
  @override
  State<SchoolVoicePlayer> createState()=>_SchoolVoicePlayerState();
}
class _SchoolVoicePlayerState extends State<SchoolVoicePlayer>{
  final player=AudioPlayer();
  final List<StreamSubscription<dynamic>> subs=[];
  bool loading=false,playing=false,loaded=false;
  int position=0;
  double speed=1;
  String? problem;
  File? local;
  @override
  void initState(){
    super.initState();
    subs.add(player.onPositionChanged.listen((p){if(mounted)setState(()=>position=p.inMilliseconds);}));
    subs.add(player.onPlayerStateChanged.listen((s){if(mounted)setState(()=>playing=s==PlayerState.playing);}));
    subs.add(player.onPlayerComplete.listen((_){if(mounted){setState(()=>position=0);final cb=widget.onPlayed;if(cb!=null)unawaited(cb());}}));
  }
  Future<void> toggle()async{
    if(loading)return;
    setState((){loading=true;problem=null;});
    try{
      if(playing){await player.pause();}
      else if(loaded){await player.resume();}
      else{
        final bytes=await widget.load();
        if(!mounted)return;
        final dir=await getTemporaryDirectory();
        local=File('${dir.path}/school-play-${DateTime.now().microsecondsSinceEpoch}.m4a');
        await local!.writeAsBytes(bytes,flush:true);
        if(!mounted){await local!.delete();return;}
        await player.play(DeviceFileSource(local!.path));
        loaded=true;
      }
      if(playing||loaded)await player.setPlaybackRate(speed);
    }catch(e){if(mounted)setState(()=>problem='Voice unavailable or expired');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override
  void dispose(){
    for(final sub in subs){unawaited(sub.cancel());}
    unawaited(_disposePlayer());
    super.dispose();
  }
  Future<void> _disposePlayer()async{
    try{await player.dispose();}finally{try{await local?.delete();}catch(_){}}
  }
  @override
  Widget build(BuildContext context)=>SizedBox(width:245,child:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[
      IconButton(tooltip:playing?'Pause':'Play voice',onPressed:loading?null:toggle,icon:loading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Icon(playing?Icons.pause_circle_filled:Icons.play_circle_fill,color:widget.foreground)),
      Expanded(child:Slider(value:position.clamp(0,widget.durationMs>0?widget.durationMs:1).toDouble(),max:widget.durationMs>0?widget.durationMs.toDouble():1,onChanged:loaded?(v)=>unawaited(player.seek(Duration(milliseconds:v.round()))):null)),
      TextButton(onPressed:()async{setState(()=>speed=speed==1?1.5:speed==1.5?2:1);try{if(loaded)await player.setPlaybackRate(speed);}catch(_){}},child:Text('${speed}x')),
    ]),
    Text('${_time(position)} / ${_time(widget.durationMs)}',style:TextStyle(color:widget.foreground,fontSize:11)),
    if(problem!=null)Text(problem!,style:TextStyle(color:widget.foreground)),
  ]));
}
Future<void> showVoiceRetention(BuildContext context,SchoolMessageRepository repo)async{
  try{
    final current=(await repo.voiceSettings.get()).data()?['mode']??'played';
    if(!context.mounted)return;
    final choice=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Voice message retention'),children:[
      const Padding(padding:EdgeInsets.all(16),child:Text('Applies to new recordings. Audio and its message are permanently removed by the cleanup service. Unplayed recordings in the first mode expire after 14 days.')),
      for(final item in const {'played':'After recipient finishes playback','7days':'After 7 days','14days':'After 14 days'}.entries)
        SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,item.key),child:Row(children:[Icon(current==item.key?Icons.check_circle:Icons.radio_button_unchecked),const SizedBox(width:8),Expanded(child:Text(item.value))])),
    ]));
    if(choice!=null)await repo.voiceSettings.set({'mode':choice,'updatedAt':FieldValue.serverTimestamp()});
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not change voice retention: $e')));}
}
