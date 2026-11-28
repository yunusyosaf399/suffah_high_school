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
    final roleDropdown = find.byKey(const Key('account_role_dropdown'));
    await tester.ensureVisible(roleDropdown);
    await tester.tap(roleDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teacher').last);
    await tester.pumpAndSettle();

    expect(find.text('Select active teacher *'), findsOneWidget);
    final teacherDropdown = find.byKey(const Key('teacher_profile_dropdown'));
    await tester.ensureVisible(teacherDropdown);
    await tester.tap(teacherDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aisha Khan • EMP-2026-0001'));
    await tester.pumpAndSettle();

    final emailDropdown = find.byKey(const Key('teacher_email_dropdown'));
    await tester.ensureVisible(emailDropdown);
    await tester.tap(emailDropdown);
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

  testWidgets('owner can open a parent permission editor', (tester) async {
    await tester.pumpWidget(MaterialApp(home:UsersPage(role:'owner',usersStream:Stream.value(const [
      SchoolUserAccount(uid:'parent-test',name:'Test Parent',email:'parent@example.com',role:'parent',active:true,linkedStudentIds:['S1'])
    ]))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Parent'));
    await tester.pumpAndSettle();
    expect(find.text('Account & permissions'),findsOneWidget);
    expect(find.text('Fees and dues'),findsOneWidget);
    await tester.tap(find.text('Fees and dues'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile,'Fees and dues')).value,isFalse);
    expect(tester.takeException(),isNull);
  });

  testWidgets('parent form autofills guardian and sends confirmed child links with corrected email',(tester)async{
    await tester.binding.setSurfaceSize(const Size(1000,1100));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final children=const [
      ParentChildOption(id:'S1',name:'Student One',guardianName:'Example Guardian',relationship:'Father',phone:'03000000000',email:'old@example.com'),
      ParentChildOption(id:'S2',name:'Student Two',guardianName:'Example Guardian',relationship:'Father'),
    ];
    var called=false;
    await tester.pumpWidget(MaterialApp(home:UsersPage(role:'owner',usersStream:Stream.value(const []),
      childrenStream:Stream.value(children),
      parentCreateOverride:({required name,required email,required password,required children,required guardianConfirmed})async{
        expect(name,'Example Guardian');expect(email,'new@example.com');
        expect(children.map((c)=>c.id),['S1','S2']);expect(guardianConfirmed,isTrue);
        called=true;
        return const CreatedSchoolUser(uid:'parent',email:'new@example.com',resetEmailSent:false);
      })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create user account'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_role_dropdown')));await tester.pumpAndSettle();
    await tester.tap(find.text('Parent / guardian').last);await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('parent_child_picker')));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('parent_child_S1')));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('parent_child_S2')));await tester.pumpAndSettle();
    await tester.tap(find.text('Select 2 children'));await tester.pumpAndSettle();
    final field=find.byKey(const Key('parent_guardian_email'));
    expect(tester.widget<TextField>(field).controller!.text,'old@example.com');
    await tester.ensureVisible(field);await tester.enterText(field,'new@example.com');await tester.pumpAndSettle();
    final confirm=find.byKey(const Key('parent_guardian_confirm'));
    await tester.ensureVisible(confirm);await tester.tap(confirm);await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));await tester.pumpAndSettle();
    expect(called,isTrue);expect(find.text('Account created'),findsOneWidget);
  });

  test('guardian email update retains nested student and guardian details and legacy email',(){
    final data=<String,dynamic>{'fullName':'Child','guardianName':'Guardian','guardianPhone':'123',
      'guardianEmail':'old@example.com','details':{'student':{'firstName':'Child','dateOfBirth':'2020-01-01'},
        'guardian':{'firstName':'Guardian','phone':'123','email':'old@example.com'},'health':{'note':'retain'}}};
    final option=ParentChildOption.fromData('S1',data);
    expect(option.email,'old@example.com');expect(option.guardianName,'Guardian');
    final patch=guardianEmailUpdate(data,'new@example.com');
    expect(patch['details']['guardian']['email'],'new@example.com');
    expect(patch['details']['guardian']['phone'],'123');
    expect(patch['details']['health']['note'],'retain');
    expect(patch['guardianEmail'],'new@example.com');
    expect(data['details']['guardian']['email'],'old@example.com');
    final legacy=guardianEmailUpdate({'fullName':'Legacy Child','guardianName':'Old Guardian','guardianPhone':'456'},'parent@example.com');
    expect(legacy['details']['guardian']['firstName'],'Old Guardian');
    expect(legacy['details']['guardian']['email'],'parent@example.com');
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
