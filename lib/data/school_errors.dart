import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Short, actionable errors for staff using online-only school workflows.
String schoolErrorMessage(Object error, {String? operation}) {
  if (error is TimeoutException) {
    return 'Firebase is taking too long to respond. Check your internet and try again. '
        'If you just saved a record, check the list before repeating it.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        if (operation == 'attendance-save') {
          return 'Attendance save was denied by Firestore security rules. '
              'Publish the complete latest firestore.rules from GitHub in '
              'Firebase Console → Firestore Database → Rules. '
              'Then sign out and back in. Owners must use the registered owner '
              'account; principals need an active principal role. Teachers '
              'must have an active linked account, a designated attendance '
              'class and an active student roster. If rules are already '
              'published, check those permissions. (permission-denied)';
        }
        return 'Firestore denied access. Check that the complete latest '
            'firestore.rules are published in Firebase Console → Firestore '
            'Database → Rules, and that this account has permission for '
            'the requested action. (permission-denied)';
      case 'unauthenticated':
        return 'Your school session has expired. Sign out and sign in again.';
      case 'unavailable':
      case 'network-request-failed':
        return 'Firebase is unavailable. Check mobile data or Wi-Fi and retry.';
      case 'failed-precondition':
        return 'Firebase needs a database setting or index. Check the '
            'Firestore console (failed-precondition).';
      case 'resource-exhausted':
        return 'Firebase usage or quota limit reached (resource-exhausted).';
      case 'deadline-exceeded':
        return 'The Firebase request timed out. Try again.';
      case 'already-exists':
        return 'This school record already exists.';
      default:
        return 'Firebase error: ${error.code}. Check Firestore and try again.';
    }
  }
  if (error is StateError || error is ArgumentError) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^(Bad state|Invalid argument):\s*'), '');
  }
  return 'Could not complete the request. Check your connection and retry.';
}
