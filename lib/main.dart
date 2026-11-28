import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'screens/incoming_call_notifications.dart';
import 'screens/owner_dashboard.dart';
import 'screens/examinations_page.dart';
import 'data/school_user_service.dart';
import 'screens/sign_in_page.dart';
import 'screens/teacher_dashboard.dart';
import 'screens/inventory_sections_page.dart';
import 'firebase_options.dart';
import 'screens/school_settings_page.dart';
import 'screens/role_portal_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('Firebase initialized successfully');

    if(!kIsWeb&&defaultTargetPlatform==TargetPlatform.android){
      FirebaseMessaging.onBackgroundMessage(schoolCallBackgroundMessage);
    }
    await loadSchoolTheme();
    runApp(const SchoolApp());

  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Firebase initialization failed:\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  // Shared with layout regression tests: tests must use the actual school
  // theme, rather than MaterialApp's unconstrained default button style.
  static ThemeData buildTheme({Brightness brightness=Brightness.light}) {
    const seed = Color(0xFF176B56);
    final color = ColorScheme.fromSeed(seedColor: seed,brightness:brightness);
    final dark=brightness==Brightness.dark;
    return ThemeData(
        useMaterial3: true,
        colorScheme: color,
        scaffoldBackgroundColor: dark?color.surface:const Color(0xFFF7F9F8),
        appBarTheme: AppBarTheme(backgroundColor: dark?color.surface:const Color(0xFFF7F9F8), elevation: 0),
        cardTheme: CardThemeData(
          color: dark?color.surfaceContainer:Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: dark?color.outlineVariant:const Color(0xFFE7EDEA))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          // Size.fromHeight(46) has INFINITE width. It crashes constraints
          // whenever a FilledButton appears in an unconstrained Row, as in
          // the Sell and Stock toolbar. Always use a finite minimum width.
          style: FilledButton.styleFrom(minimumSize: const Size(88, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13),
          bodySmall: TextStyle(fontSize: 11),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(valueListenable:schoolThemeMode,builder:(context,mode,_)=>MaterialApp(
      debugShowCheckedModeBanner:false,title:'Suffah High School',theme:buildTheme(),
      darkTheme:buildTheme(brightness:Brightness.dark),themeMode:mode,home:const AuthGate(),
    ));
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState()=>_AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  String? _lastAccess;
  Stream<User?>? _auth;
  Stream<DocumentSnapshot<Map<String,dynamic>>>? _profile;
  String? _profileUid;
  void _accessChanged(String access){
    if(_lastAccess!=null && _lastAccess!=access){
      WidgetsBinding.instance.addPostFrameCallback((_)async{await IncomingCallNotifications.lockScreen(false);if(mounted)Navigator.of(context).popUntil((route)=>route.isFirst);});
    }
    _lastAccess=access;
  }
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth??=FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) {
          return const _StatusPage(message: 'Checking your session…');
        }
        if (auth.hasError) return const _StatusPage(message: 'Unable to check your session.');
        final user = auth.data;
        if (user == null) {_accessChanged('signed-out');return const SignInPage();}
        if(_profileUid!=user.uid){_profileUid=user.uid;_profile=FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();}

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(user.uid),
          stream: _profile,
          builder: (context, profile) {
            if (profile.connectionState == ConnectionState.waiting && !profile.hasData) {
              return const _StatusPage(message: 'Loading your school profile…');
            }
            if (profile.hasError) {
              _accessChanged('unverified');
              return const _AccessPage(message: 'Could not verify your school access. Check your connection and Firestore rules.');
            }
            final record = profile.data?.data();
            if (record == null || record['active'] != true || record['removed']==true) {
              _accessChanged('inactive');
              return const _AccessPage(message: 'This school account is inactive or has no approved role.');
            }
            final role = (record['role'] as String?) ?? '';
            final permissions=accountPermissions(record['permissions']);
            final keys=permissions.keys.toList()..sort();
            _accessChanged('${user.uid}|$role|${keys.map((k)=>'$k:${permissions[k]}').join(',')}|${record['linkedStudentIds']}');
            if (role == 'owner' && user.uid != schoolOwnerUid) {
              return const _AccessPage(message: 'This user is not the registered school owner.');
            }
            final name = record['displayName'] is String && (record['displayName'] as String).trim().isNotEmpty
                ? (record['displayName'] as String).trim() : 'School User';
            if (role == 'owner' || role == 'principal') {
              return OwnerDashboard(displayName: name, role: role,permissions:accountPermissions(record['permissions']));
            }
            if (role == 'examiner') {
              return const ExaminationsPage(role: 'examiner');
            }
            if (role == 'teacher') {
              final staffId = (record['staffId'] as String?) ?? '';
              if (staffId.isEmpty) {
                return const _AccessPage(
                  message: 'This teacher account is not linked to an active staff profile. Ask the school owner to link it from Users.',
                );
              }
              return TeacherDashboard(displayName: name, staffId: staffId,permissions:accountPermissions(record['permissions']));
            }
            if(role=='parent') return ParentPortalPage(key:ValueKey('${user.uid}|${record['linkedStudentIds']}|${keys.map((k)=>'$k:${permissions[k]}').join(',')}'),displayName:name,permissions:permissions);
            if (role == 'canteen_seller' || role == 'inventory_manager') {
              return InventorySectionsPage(role: role);
            }
            if (schoolRoles.containsKey(role)) {
              return _RoleHome(displayName: name, role: role);
            }
            return const _AccessPage(message: 'This account has an unsupported school role.');
          },
        );
      },
    );
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 18),
      Text(message, style: const TextStyle(fontSize: 12)),
    ])),
  );
}

class _AccessPage extends StatelessWidget {
  const _AccessPage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Access unavailable')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 42),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
        ]),
      ),
    )),
  );
}

class _RoleHome extends StatelessWidget {
  const _RoleHome({required this.displayName, required this.role});
  final String displayName;
  final String role;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Suffah High School'),
      actions: [
        const SchoolSettingsButton(),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle_outlined, size: 57,
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 15),
              Text('Welcome, $displayName',
                style: const TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Signed in as ${schoolRoles[role] ?? role}.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              const Text(
                'Your school account has been created. Your role-specific modules are being developed and are not yet available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
