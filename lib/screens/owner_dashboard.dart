import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/school_repository.dart';
import 'classes_page.dart';
import 'students_page.dart';
import 'global_search_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key, required this.displayName});

  final String displayName;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final _repository = SchoolRepository();
  late Future<SchoolSummary> _summary = _repository.loadSummary();

  static const _modules = [
    _DashboardModule('Students', Icons.groups_outlined, 'Admissions & profiles', true),
    _DashboardModule('Classes', Icons.school_outlined, 'Classes & sections', true),
    _DashboardModule('Attendance', Icons.fact_check_outlined, 'Daily registers', false),
    _DashboardModule('Fees & accounts', Icons.receipt_long_outlined, 'Fees & payments', false),
    _DashboardModule('Examinations', Icons.assignment_outlined, 'Marks & results', false),
    _DashboardModule('Staff', Icons.badge_outlined, 'Team & assignments', false),
    _DashboardModule('Parents', Icons.family_restroom_outlined, 'Families & children', false),
    _DashboardModule('Messages', Icons.forum_outlined, 'School communications', false),
  ];

  void _refresh() {
    if (mounted) setState(() => _summary = _repository.loadSummary());
  }

  Future<void> _openModule(int index) async {
    if (index == 0 || index == 1) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => index == 0 ? const StudentsPage() : const ClassesPage(),
        ),
      );
      _refresh();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_modules[index].title} is planned for the next app versions.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, size: 23),
            SizedBox(width: 9),
            Flexible(
              child: Text('Suffah High School',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh school overview',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
          const SizedBox(width: 7),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, limits) {
          final width = limits.maxWidth;
          final gridColumns = width >= 1060 ? 4 : width >= 640 ? 3 : 2;
          final maxWidth = width >= 1150 ? 1100.0 : width;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: RefreshIndicator(
                onRefresh: () async {
                  final next = _repository.loadSummary();
                  setState(() => _summary = next);
                  try { await next; } catch (_) { /* Retry through refresh. */ }
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(17, 18, 17, 32),
                  children: [
                    Text('School overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Welcome back, ${widget.displayName}.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 17),
                    GlobalSearchEntry(
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const GlobalSearchPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(19),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Manage your school',
                                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                                const SizedBox(height: 8),
                                Text('Admissions and classes are now ready to use.',
                                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.88))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Icon(Icons.auto_stories_rounded, color: Colors.white.withValues(alpha: 0.85), size: 46),
                        ],
                      ),
                    ),
                    const SizedBox(height: 23),
                    Text('At a glance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    FutureBuilder<SchoolSummary>(
                      future: _summary,
                      builder: (context, snapshot) {
                        final message = snapshot.hasError ? 'Tap refresh to retry' : 'Loading…';
                        final items = [
                          _Stat('Student records', snapshot.hasData ? '${snapshot.data!.students}' : '—',
                            Icons.groups_2_outlined),
                          _Stat('Class sections', snapshot.hasData ? '${snapshot.data!.classes}' : '—',
                            Icons.school_outlined),
                        ];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                for (var i = 0; i < items.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 10),
                                  Expanded(
                                    child: _StatisticCard(item: items[i]),
                                  ),
                                ],
                              ],
                            ),
                            if (!snapshot.hasData) ...[
                              const SizedBox(height: 7),
                              Text(message, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 27),
                    Row(
                      children: [
                        Expanded(
                          child: Text('School management',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Text('8 modules', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _modules.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 142,
                      ),
                      itemBuilder: (context, index) {
                        final item = _modules[index];
                        return Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openModule(index),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(item.icon, color: scheme.primary, size: 27),
                                      const Spacer(),
                                      if (item.available)
                                        Icon(Icons.arrow_outward_rounded, size: 15, color: scheme.primary)
                                      else
                                        Text('Soon', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Text('Suffah High School • Preview v0.2',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DashboardModule {
  const _DashboardModule(this.title, this.icon, this.subtitle, this.available);
  final String title;
  final IconData icon;
  final String subtitle;
  final bool available;
}

class _Stat {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({required this.item});
  final _Stat item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, color: scheme.primary, size: 23),
            const SizedBox(height: 10),
            Text(item.value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(item.label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
