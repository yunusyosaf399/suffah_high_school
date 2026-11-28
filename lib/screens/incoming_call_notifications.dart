import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

/// Only genuine school call pushes use this path. No microphone is opened by
/// the background isolate. The call page verifies the live session on server.
@pragma('vm:entry-point')
Future<void> schoolCallBackgroundMessage(RemoteMessage message)async{
  if(message.data['type']!='office_call_v2'||message.notification!=null)return;
  try{
    await Firebase.initializeApp(options:DefaultFirebaseOptions.currentPlatform);
    await IncomingCallNotifications.show(message.data);
  }catch(_){/* FCM is best effort; the live receiver remains available. */}
}

class IncomingCallNotifications{
  static final plugin=FlutterLocalNotificationsPlugin();
  static final opened=StreamController<Map<String,dynamic>>.broadcast();
  static const _accountKey='school_incoming_call_account';
  static const _native=MethodChannel('suffah/call_audio');
  static bool get android=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  static Future<bool>? _init;
  static Map<String,dynamic>? decode(String? payload){
    if(payload==null)return null;
    try{
      final value=jsonDecode(payload);
      return value is Map<String,dynamic>&&value['type']=='office_call_v2'?value:null;
    }catch(_){return null;}
  }
  static int notificationId(String callId){
    // Stable across isolates, positive and deterministic.
    var hash=17;
    for(final c in callId.codeUnits){hash=(hash*31+c)&0x7fffffff;}
    return hash;
  }
  static Future<bool> initialize()=>_init??=_initialize();
  static Future<bool> _initialize()async{
    if(!android)return false;
    return await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse:(response){
        final data=decode(response.payload);
        if(data!=null)opened.add(data);
      })??false;
  }
  static Future<void> registerAccount(String uid)async{
    if(!android)return;
    final p=await SharedPreferences.getInstance();
    await p.setString(_accountKey,uid);
  }
  static Future<void> clearAccount()async{
    if(!android)return;
    try{final p=await SharedPreferences.getInstance();await p.remove(_accountKey);await plugin.cancelAll();}catch(_){}
  }
  static Future<Map<String,dynamic>?> launchPayload()async{
    if(!android)return null;
    try{
      final details=await plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp==true?decode(details?.notificationResponse?.payload):null;
    }catch(_){return null;}
  }
  static Future<void> show(Map<String,dynamic> data)async{
    if(!android||data['type']!='office_call_v2')return;
    final id=data['callId'],caller=data['callerUid'],channel=data['channel'];
    final expiry=DateTime.tryParse(data['expiresAt']?.toString()??'');
    if(id is! String||!RegExp(r'^[A-Za-z0-9_-]{20}$').hasMatch(id)||caller is! String
      ||expiry==null||!expiry.isAfter(DateTime.now()))return;
    final prefs=await SharedPreferences.getInstance();await prefs.reload();
    final account=prefs.getString(_accountKey);
    if(account==null||account.isEmpty||account!=data['recipientUid'])return;
    if(!await initialize())return;
    final channelId=channel is String&&RegExp(r'^school_calls[A-Za-z0-9_]{0,80}$').hasMatch(channel)?channel:'school_calls';
    final remaining=expiry.difference(DateTime.now()).inMilliseconds.clamp(1,60000).toInt();
    await plugin.show(notificationId(id),'Suffah High School','Incoming voice call — tap to answer',
      NotificationDetails(android:AndroidNotificationDetails(channelId,'School incoming calls',
        importance:Importance.max,priority:Priority.max,category:AndroidNotificationCategory.call,
        fullScreenIntent:true,timeoutAfter:remaining,visibility:NotificationVisibility.private,
        ongoing:true,autoCancel:false,additionalFlags:Int32List.fromList([4]))),
      payload:jsonEncode(data));
  }
  static Future<void> cancel(String id)async{
    if(!android)return;
    try{await initialize();await plugin.cancel(notificationId(id));}catch(_){}
  }
  static Future<void> lockScreen(bool enabled)async{
    if(!android)return;
    try{await _native.invokeMethod<void>('callLockScreen',{'enabled':enabled});}catch(_){}
  }
  static Future<void> requestFullScreen(BuildContext context)async{
    if(!android)return;
    try{
      await initialize();
      final impl=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted=await impl?.requestFullScreenIntentPermission();
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(granted==true?'Full-screen incoming calls enabled.':'Allow full-screen notifications in Android settings if available.')));
    }catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Check Android notification and full-screen alert settings.')));}
  }
}
