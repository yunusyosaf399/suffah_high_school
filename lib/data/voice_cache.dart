import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Private, disposable cache, isolated by signed-in account and conversation.
/// Last-modified time stores the server expiry, not the last playback time.
class VoiceCache {
  static final _valid=RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static Future<Directory> _root(String uid)async{
    if(!_valid.hasMatch(uid))throw ArgumentError('Invalid account');
    final dir=await getTemporaryDirectory();
    return Directory('${dir.path}/school-voice-cache-v1/$uid');
  }
  static Future<File> _file(String uid,String thread,String id)async{
    if(!_valid.hasMatch(thread)||!_valid.hasMatch(id))throw ArgumentError('Invalid voice reference');
    final root=await _root(uid);
    return File('${root.path}/$thread/$id.m4a');
  }
  static Future<File?> read(String uid,String thread,String id)async{
    final f=await _file(uid,thread,id);
    if(!await f.exists())return null;
    if(!(await f.lastModified()).isAfter(DateTime.now())||await f.length()==0){
      await remove(uid,thread,id);return null;
    }
    return f;
  }
  static Future<File> store(String uid,String thread,String id,Uint8List bytes,DateTime expiry)async{
    if(!expiry.isAfter(DateTime.now()))throw StateError('Voice message expired.');
    final f=await _file(uid,thread,id);
    await f.parent.create(recursive:true);
    final tmp=File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    try{
      await tmp.writeAsBytes(bytes,flush:true);
      await tmp.setLastModified(expiry);
      // Replacing a cache entry never changes the remote audio.
      if(await f.exists())await f.delete();
      return await tmp.rename(f.path);
    }finally{if(await tmp.exists())await tmp.delete();}
  }
  static Future<void> remove(String uid,String thread,String id)async{
    try{final f=await _file(uid,thread,id);if(await f.exists())await f.delete();}catch(_){}
  }
  static Future<void> clear(String uid)async{
    try{final root=await _root(uid);if(await root.exists())await root.delete(recursive:true);}catch(_){}
  }
  static Future<void> prune(String uid)async{
    try{
      final root=await _root(uid);if(!await root.exists())return;
      await for(final e in root.list(recursive:true,followLinks:false)){
        if(e is File){
          try{
            final modified=await e.lastModified();
            if(e.path.endsWith('.m4a')&&!modified.isAfter(DateTime.now())||
              e.path.endsWith('.part')&&modified.isBefore(DateTime.now().subtract(const Duration(minutes:10))))await e.delete();
          }catch(_){}
        }
      }
    }catch(_){}
  }
}
