import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Short, actionable errors for staff using online-only school workflows.
String schoolErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'Firebase is taking too long to respond. Check your internet and try again. '
        'If you just saved a record, check the list before repeating it.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firestore rejected this request. For staff registration, publish '
            'the latest firestore.rules from GitHub in Firebase Console → '
            'Firestore Database → Rules, then sign in with the approved school '
            'owner or principal account. (permission-denied)';
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
