import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_user_service.dart';
import 'package:suffah_high_school/data/staff_repository.dart';
import 'package:suffah_high_school/screens/users_page.dart';

void main() {
  testWidgets('owner can reach the Users creation form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UsersPage(
          role: 'owner',
          usersStream: Stream.value(const [
            SchoolUserAccount(
              uid: schoolOwnerUid,
              name: 'School Owner',
              email: '',
              role: 'owner',
              active: true,
            ),
          ]),
          createOverride: ({
            required name,
            required email,
            required password,
            required role,
            staffId,
          }) async {
            expect(name, 'Test Principal');
            expect(email, 'principal@example.com');
            expect(password.length, greaterThanOrEqualTo(12));
            expect(role, 'principal');
            return const CreatedSchoolUser(
              uid: 'test-principal',
              email: 'principal@example.com',
              resetEmailSent: false,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Users & accounts'), findsOneWidget);
    expect(find.text('School Owner'), findsOneWidget);
    await tester.tap(find.text('Create user account'));
    await tester.pumpAndSettle();
    // The primary footer action and the dialog title share this wording.
    expect(find.text('Create user account'), findsNWidgets(2));
    await tester.enterText(
      find.widgetWithText(TextField, 'Full name *'), 'Test Principal');
    await tester.enterText(
      find.widgetWithText(TextField, 'Email address *'),
      'principal@example.com');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Account created'), findsOneWidget);
    expect(find.text('Copy password'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner links a teacher account to an active teacher and saved email',
      (tester) async {
    String? selectedStaffId;
    String? selectedEmail;
    await tester.pumpWidget(MaterialApp(
      home: UsersPage(
        role: 'owner',
        usersStream: Stream.value(const <SchoolUserAccount>[]),
        teachersStream: Stream.value(const [
          StaffMember(
            id: 'EMP-2026-0001',
            staffNo: 'EMP-2026-0001',
            fullName: 'Aisha Khan',
            firstName: 'Aisha',
            lastName: 'Khan',
            roleType: 'teacher',
            designation: 'Mathematics Teacher',
            phone: '03001234567',
            email: 'aisha@example.com',
            alternateEmail: 'a.khan@example.com',
            active: true,
          ),
        ]),
        createOverride: ({
          required name,
          required email,
          required password,
          required role,
          staffId,
        }) async {
          selectedStaffId = staffId;
          selectedEmail = email;
          expect(name, 'Aisha Khan');
          expect(role, 'teacher');
          return const CreatedSchoolUser(
            uid: 'teacher-account',
            email: 'a.khan@example.com',
            resetEmailSent: false,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create user account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teacher').last);
    await tester.pumpAndSettle();

    expect(find.text('Select active teacher *'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aisha Khan • EMP-2026-0001'));
    await tester.pumpAndSettle();

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.khan@example.com').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(selectedStaffId, 'EMP-2026-0001');
    expect(selectedEmail, 'a.khan@example.com');
    expect(find.text('Account created'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-owner cannot manage or create users', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UsersPage(
          role: 'principal',
          usersStream: Stream.value(const <SchoolUserAccount>[]),
        ),
      ),
    );
    expect(find.textContaining('Only the school owner'), findsOneWidget);
    expect(find.text('Create user account'), findsNothing);
  });
}
