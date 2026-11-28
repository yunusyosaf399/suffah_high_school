import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/screens/office_calls.dart';

void main(){
  test('Windows can present an incoming call even when unfocused',(){
    expect(OfficeCalls.canPresent(AppLifecycleState.inactive,desktop:true),isTrue);
    expect(OfficeCalls.canPresent(null,desktop:true),isTrue);
    expect(OfficeCalls.canPresent(AppLifecycleState.detached,desktop:true),isFalse);
    expect(OfficeCalls.canPresent(AppLifecycleState.paused,desktop:false),isFalse);
    expect(OfficeCalls.canPresent(AppLifecycleState.resumed,desktop:false),isTrue);
  });
  test('only unexpired ringing sessions may be presented',(){
    final future=Timestamp.fromDate(DateTime.now().add(const Duration(minutes:1)));
    final past=Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes:1)));
    expect(OfficeCalls.fresh({'status':'ringing','expiresAt':future}),isTrue);
    expect(OfficeCalls.fresh({'status':'ringing','expiresAt':past}),isFalse);
    expect(OfficeCalls.fresh({'status':'connected','expiresAt':future}),isFalse);
  });
}
