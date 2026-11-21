import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({super.key, required this.displayName});

  final String displayName;

  static const _modules = [
    _Module('Students', Icons.groups_outlined, 'Admissions & profiles'),
    _Module('Academics', Icons.menu_book_outlined, 'Classes & subjects'),
    _Module('Attendance', Icons.fact_check_outlined, 'Daily registers'),
    _Module('Fees', Icons.receipt_long_outlined, 'Payments & balances'),
    _Module('Examinations', Icons.assignment_outlined, 'Marks & results'),
    _Module('Staff', Icons.badge_outlined, 'Team & assignments'),
    _Module('Parents', Icons.family_restroom_outlined, 'Families & children'),
    _Module('Messages', Icons.forum_outlined, 'School communications'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suffah High School', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, limits) {
          final width = limits.maxWidth;
          final columns = width >= 1000 ? 4 : width >= 650 ? 3 : 2;
          final contentWidth = width >= 1100 ? 1050.0 : width;
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
                children: [
                  Text('Good to see you, $displayName', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Owner dashboard', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: scheme.onPrimaryContainer, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Owner access enabled', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                              const SizedBox(height: 4),
                              Text('Firebase sign-in and your school profile are connected.',
                                  style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 27),
                  Row(
                    children: [
                      Text('School management', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('Preview', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _modules.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 11,
                      mainAxisSpacing: 11,
                      mainAxisExtent: 132,
                    ),
                    itemBuilder: (context, index) {
                      final module = _modules[index];
                      return Card(
                        elevation: 0,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(module.title + ' module is coming next.')),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(module.icon, color: scheme.primary, size: 25),
                                const Spacer(),
                                Text(module.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 3),
                                Text(module.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text('Version 0.1 • Android preview', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Module {
  const _Module(this.title, this.icon, this.subtitle);
  final String title;
  final IconData icon;
  final String subtitle;
}
