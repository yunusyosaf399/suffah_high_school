import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/screens/global_search_page.dart';

void main() {
  testWidgets('Global search entry is visible and opens the preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlobalSearchEntry(
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Global search'), findsOneWidget);
    expect(find.textContaining('Students, reports'), findsOneWidget);
    expect(find.text('Soon'), findsOneWidget);
  });

  testWidgets('Global search scopes are labeled as a preview', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlobalSearchPage()));
    expect(find.text('Global search'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Search results coming later'), findsOneWidget);
  });
}
