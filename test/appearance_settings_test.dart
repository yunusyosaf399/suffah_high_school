import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suffah_high_school/main.dart';
import 'package:suffah_high_school/screens/school_settings_page.dart';
import 'package:suffah_high_school/screens/role_portal_pages.dart';

void main(){
  testWidgets('appearance preference is applied and persisted', (tester) async {
    SharedPreferences.setMockInitialValues({});
    schoolThemeMode.value=ThemeMode.system;
    addTearDown(()=>schoolThemeMode.value=ThemeMode.system);
    await tester.pumpWidget(const MaterialApp(home:SchoolSettingsPage()));
    await tester.tap(find.text('Dark theme'));
    await tester.pumpAndSettle();
    expect(schoolThemeMode.value,ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getString('school_theme'),'dark');
    await tester.tap(find.text('Light theme'));
    await tester.pumpAndSettle();
    expect(schoolThemeMode.value,ThemeMode.light);
    await tester.tap(find.text('Follow system'));
    await tester.pumpAndSettle();
    expect(schoolThemeMode.value,ThemeMode.system);
    expect(SchoolApp.buildTheme(brightness:Brightness.dark).colorScheme.brightness,Brightness.dark);
  });
  test('service months count complete months, not rounded elapsed days',(){
    expect(completedServiceMonths('2026-01-20',now:DateTime(2026,11,19)),9);
    expect(completedServiceMonths('2026-01-20',now:DateTime(2026,11,20)),10);
    expect(completedServiceMonths('',now:DateTime(2026,11,20)),isNull);
  });
}
