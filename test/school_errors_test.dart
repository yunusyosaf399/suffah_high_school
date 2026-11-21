import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_errors.dart';

void main() {
  test('permission errors point to the Firebase owner and rules', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    expect(schoolErrorMessage(error), contains('Firestore Rules'));
  });

  test('timeouts recommend checking for a completed save first', () {
    expect(
      schoolErrorMessage(TimeoutException('no reply')),
      contains('check the list before repeating'),
    );
  });
}
