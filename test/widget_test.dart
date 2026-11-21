import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/screens/sign_in_page.dart';

void main() {
  testWidgets('Sign-in form presents accessible fields and actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
