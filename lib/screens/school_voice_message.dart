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

/// Inline recorder keeps the microphone pointer target mounted during gestures.
class InlineVoiceComposer extends StatefulWidget {
  const InlineVoiceComposer({super.key,required this.controller,required this.enabled,required this.onSendText,required this.onVoice,required this.onError,required this.leading});
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSendText;
  final Future<void> Function(VoiceClip) onVoice;
  final void Function(Object) onError;
  final List<Widget> leading;
  @override
  State<InlineVoiceComposer> createState()=>_InlineVoiceComposerState();
}
class _InlineVoiceComposerState extends State<InlineVoiceComposer> with WidgetsBindingObserver {
  final recorder=AudioRecorder();
  final clock=Stopwatch();
  Timer? timer,deadline;
  String? path;
  bool starting=false,recording=false,locked=false,finishing=false,disposed=false;
  int? pointer;
  Offset origin=Offset.zero;
  bool held=false;
  bool cancelRequested=false;
  bool releaseRequested=false;
  bool get active=>starting||recording||finishing;
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);widget.controller.addListener(changed);}
  @override
  void didUpdateWidget(covariant InlineVoiceComposer old){super.didUpdateWidget(old);if(old.controller!=widget.controller){old.controller.removeListener(changed);widget.controller.addListener(changed);}}
  void changed(){if(mounted)setState((){});}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused||state==AppLifecycleState.detached){if(starting)cancelRequested=true;else if(recording)unawaited(finish(cancel:true));}
  }
  Future<void> clearFile(String? p)async{if(p!=null){try{await File(p).delete();}catch(_){}}}
  Future<void> start()async{
    if(active||!widget.enabled)return;
    FocusScope.of(context).unfocus();
    clock.reset();
    setState((){starting=true;locked=false;cancelRequested=false;releaseRequested=false;held=false;});
    try{
      if(!await recorder.hasPermission())throw StateError('Microphone permission is required.');
      if(disposed)return;
      if(!await recorder.isEncoderSupported(AudioEncoder.aacLc))throw StateError('AAC recording is unavailable.');
      if(disposed)return;
      final dir=await getTemporaryDirectory();
      if(disposed)return;
      path='${dir.path}/school-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      if(cancelRequested){await clearFile(path);return;}
      await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc,bitRate:32000,sampleRate:24000,numChannels:1),path:path!);
      if(disposed){try{await recorder.stop();}catch(_){}await clearFile(path);return;}
      clock.reset();clock.start();
      setState((){starting=false;recording=true;});
      if(cancelRequested){await finish(cancel:true);return;}
      if(releaseRequested&&!locked){await finish();return;}
      timer=Timer.periodic(const Duration(milliseconds:200),(_){if(mounted)setState((){});});
      deadline=Timer(const Duration(minutes:4),(){if(mounted)unawaited(finish());});
    }catch(e){if(mounted)widget.onError(e);await clearFile(path);}
    finally{if(disposed){try{await recorder.dispose();}catch(_){}await clearFile(path);}else if(mounted)setState(()=>starting=false);}
  }
  Future<void> finish({bool cancel=false})async{
    if(starting){if(cancel)cancelRequested=true;else releaseRequested=true;return;}
    if(!recording||finishing)return;
    setState(()=>finishing=true);timer?.cancel();deadline?.cancel();clock.stop();
    VoiceClip? clip;
    try{
      final p=await recorder.stop();
      if(!cancel&&p!=null&&clock.elapsedMilliseconds>=200){
        final bytes=await File(p).readAsBytes();
        if(bytes.isEmpty||bytes.length>3000000)throw StateError('Recording is empty or too large.');
        clip=VoiceClip(bytes,clock.elapsedMilliseconds.clamp(1,240000).toInt());
      }
    }catch(e){if(mounted)widget.onError(e);}
    finally{
      await clearFile(path);path=null;
      if(mounted)setState((){recording=false;finishing=false;locked=false;pointer=null;});
      if(disposed){try{await recorder.dispose();}catch(_){}}
    }
    if(clip!=null&&mounted)await widget.onVoice(clip);
  }
  void down(PointerDownEvent e){
    if(active||!widget.enabled)return;
    pointer=e.pointer;origin=e.position;unawaited(start());
  }
  void move(PointerMoveEvent e){
    if(pointer!=e.pointer||locked||!active)return;
    final delta=e.position-origin;
    if(delta.dx < -75&&delta.dx.abs()>delta.dy.abs()){
      pointer=null;unawaited(finish(cancel:true));
    }else if(delta.dy < -65){
      setState(()=>locked=true);pointer=null;
    }else if(delta.distance>12){held=true;}
  }
  void up(PointerUpEvent e){
    if(pointer!=e.pointer)return;
    pointer=null;
    if(!active||locked)return;
    // A quick tap starts hands-free recording; a held press sends on release.
    if((e.position-origin).distance<12&&!held&&clock.elapsedMilliseconds<350){if(mounted)setState(()=>locked=true);}
    else{unawaited(finish());}
  }
  @override
  void dispose(){
    disposed=true;WidgetsBinding.instance.removeObserver(this);widget.controller.removeListener(changed);timer?.cancel();deadline?.cancel();
    if(starting){cancelRequested=true;}else if(!finishing){unawaited(()async{try{if(recording)await recorder.stop();await recorder.dispose();}catch(_){}await clearFile(path);}());}
    super.dispose();
  }
  @override
  Widget build(BuildContext context){
    final hasText=widget.controller.text.isNotEmpty;
    final scheme=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.fromLTRB(6,4,6,8),child:Row(children:[
      Expanded(child:Row(children:[
      if(!active)...[
        ...widget.leading,
        Expanded(child:TextField(controller:widget.controller,maxLength:2000,minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'Message',counterText:'',isDense:true,border:OutlineInputBorder()))),
      ]else...[
        if(locked)IconButton(tooltip:'Delete recording',onPressed:finishing?null:()=>finish(cancel:true),icon:const Icon(Icons.delete_outline,color:Colors.red))
        else const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.mic,color:Colors.red)),
        Text(_time(clock.elapsedMilliseconds.clamp(0,240000).toInt()),style:const TextStyle(fontWeight:FontWeight.w600)),
        const SizedBox(width:8),
        Expanded(child:Text(finishing?'Finishing…':starting?'Starting…':locked?'Recording locked · 4 min max':'← Slide to cancel   ↑ Lock',overflow:TextOverflow.ellipsis,textAlign:TextAlign.center)),
      ],
      ])),
      // Same element position and key across recording transitions preserves pointer delivery.
      if(hasText&&!active)IconButton.filled(tooltip:'Send',onPressed:widget.enabled?widget.onSendText:null,icon:const Icon(Icons.send))
      else Listener(key:const ValueKey('voice-mic-target'),onPointerDown:down,onPointerMove:move,onPointerUp:up,onPointerCancel:(e){if(pointer==e.pointer){pointer=null;if(!locked)unawaited(finish(cancel:true));}},child:
        active&&locked?IconButton.filled(tooltip:'Send voice',onPressed:finishing?null:()=>finish(),icon:const Icon(Icons.send)):
        Semantics(button:true,label:active?'Recording voice':'Record voice message',child:Container(width:48,height:48,margin:const EdgeInsets.only(left:4),decoration:BoxDecoration(color:widget.enabled||active?scheme.primary:scheme.surfaceContainerHighest,shape:BoxShape.circle),child:Icon(active?Icons.mic:Icons.mic_none,color:scheme.onPrimary)))),
    ]));
  }
}
class SchoolVoicePlayer extends StatefulWidget{
  const SchoolVoicePlayer({super.key,required this.durationMs,required this.load,required this.foreground,this.onPlayed});
  final int durationMs;
  final Future<File> Function() load;
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
    subs.add(player.onPlayerComplete.listen((_){if(mounted){setState((){position=0;loaded=false;playing=false;});final cb=widget.onPlayed;if(cb!=null)unawaited(cb());}}));
  }
  Future<void> toggle()async{
    if(loading)return;
    setState((){loading=true;problem=null;});
    try{
      if(playing){await player.pause();}
      else{
        final file=await widget.load();
        if(!mounted)return;
        if(loaded&&local?.path==file.path){await player.resume();}
        else{local=file;await player.play(DeviceFileSource(file.path));loaded=true;}
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
    await player.dispose();
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
    if(!await repo.isOwner())throw StateError('Only the owner can change message retention.');
    final current=(await repo.voiceSettings.get()).data()?['mode']??'played';
    if(!context.mounted)return;
    final choice=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Voice message retention'),children:[
      const Padding(padding:EdgeInsets.all(16),child:Text('Applies to new recordings. Audio and its message are permanently removed by the cleanup service. Unplayed recordings in the first mode expire after 14 days.')),
      for(final item in const {'played':'After recipient finishes playback','7days':'After 7 days','14days':'After 14 days'}.entries)
        SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,item.key),child:Row(children:[Icon(current==item.key?Icons.check_circle:Icons.radio_button_unchecked),const SizedBox(width:8),Expanded(child:Text(item.value))])),
    ]));
    if(choice!=null){
      await repo.voiceSettings.set({'mode':choice,'updatedAt':FieldValue.serverTimestamp()});
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Voice deletion setting saved.')));
    }
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not change voice retention: $e')));}
}
