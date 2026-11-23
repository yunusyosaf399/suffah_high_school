import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/owner_dashboard.dart';
import 'data/school_user_service.dart';
import 'screens/sign_in_page.dart';
import 'screens/teacher_dashboard.dart';
import 'screens/inventory_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // The registered Android app reads its configuration from google-services.json.
    await Firebase.initializeApp();
    runApp(const SchoolApp());
  } catch (_) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not initialize Firebase. Check your connection and app configuration.'),
        )),
      ),
    ));
  }
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF176B56);
    final color = ColorScheme.fromSeed(seedColor: seed);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Suffah High School',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: color,
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F9F8), elevation: 0),
        cardTheme: CardThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE7EDEA))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13),
          bodySmall: TextStyle(fontSize: 11),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) {
          return const _StatusPage(message: 'Checking your session…');
        }
        if (auth.hasError) return const _StatusPage(message: 'Unable to check your session.');
        final user = auth.data;
        if (user == null) return const SignInPage();

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(user.uid),
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, profile) {
            if (profile.connectionState != ConnectionState.done) {
              return const _StatusPage(message: 'Loading your school profile…');
            }
            if (profile.hasError) {
              return const _AccessPage(message: 'Could not verify your school access. Check your connection and Firestore rules.');
            }
            final record = profile.data?.data();
            if (record == null || record['active'] != true) {
              return const _AccessPage(message: 'This school account is inactive or has no approved role.');
            }
            final role = (record['role'] as String?) ?? '';
            if (role == 'owner' && user.uid != schoolOwnerUid) {
              return const _AccessPage(message: 'This user is not the registered school owner.');
            }
            final name = record['displayName'] is String && (record['displayName'] as String).trim().isNotEmpty
                ? (record['displayName'] as String).trim() : 'School User';
            if (role == 'owner' || role == 'principal') {
              return OwnerDashboard(displayName: name, role: role);
            }
            if (role == 'teacher') {
              final staffId = (record['staffId'] as String?) ?? '';
              if (staffId.isEmpty) {
                return const _AccessPage(
                  message: 'This teacher account is not linked to an active staff profile. Ask the school owner to link it from Users.',
                );
              }
              return TeacherDashboard(displayName: name, staffId: staffId);
            }
            if (role == 'canteen_seller' || role == 'inventory_manager') {
              return InventoryPage(role: role);
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
