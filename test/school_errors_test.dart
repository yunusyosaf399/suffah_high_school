import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_errors.dart';

void main() {
  test('generic permission errors do not incorrectly mention staff registration', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    final message = schoolErrorMessage(error);
    expect(message, contains('firestore.rules'));
    expect(message, isNot(contains('staff registration')));
    expect(message, contains('permission-denied'));
  });

  test('attendance permission errors explain owner, principal and teacher access', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    final message = schoolErrorMessage(error, operation: 'attendance-save');
    expect(message, contains('Attendance save'));
    expect(message, contains('firestore.rules'));
    expect(message, contains('principals'));
    expect(message, contains('Teachers'));
    expect(message, isNot(contains('staff registration')));
  });

  test('timeouts recommend checking for a completed save first', () {
    expect(
      schoolErrorMessage(TimeoutException('no reply')),
      contains('check the list before repeating'),
    );
  });
}
