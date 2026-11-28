import 'message_notifications.dart';
import 'package:flutter/material.dart';

import '../data/school_repository.dart';
import 'classes_page.dart';
import 'students_page.dart';
import 'attendance_page.dart';
import 'staff_page.dart';
import 'examinations_page.dart';
import 'exam_term_overview.dart';
import 'global_search_page.dart';
import 'users_page.dart';
import 'finance_page.dart';
import 'finance_analytics_tab.dart';
import 'inventory_page.dart';
import 'student_documents_page.dart';
import '../data/school_user_service.dart';
import 'role_portal_pages.dart';
import 'school_settings_page.dart';
import 'backup_export_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({
    super.key,
    required this.displayName,
    this.role = 'owner',
    this.summaryLoader,
    this.financePreview,
    this.permissions=const {},
  });

  final String displayName;
  final String role;
  final Map<String,bool> permissions;
  bool get examAccess=>role=='owner'||schoolPermission(permissions,'principal_exams');
  bool get messageAccess=>role=='owner'||schoolPermission(permissions,'messages');
  // Optional sources make navigation and scrolling testable without Firebase.
  final Future<SchoolSummary> Function()? summaryLoader;
  final Widget? financePreview;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  SchoolRepository? _repository;
  Future<SchoolSummary> _loadSummary() =>
      widget.summaryLoader?.call() ??
      (_repository ??= SchoolRepository()).loadSummary();
  late Future<SchoolSummary> _summary = _loadSummary();
  int _financeRevision = 0;

  static const _modules = [
    _DashboardModule('Students', Icons.groups_outlined, 'Admissions & profiles', true),
    _DashboardModule('Classes', Icons.school_outlined, 'Classes & sections', true),
    _DashboardModule('Attendance', Icons.fact_check_outlined, 'Daily class registers', true),
    _DashboardModule('Fees & Finance', Icons.receipt_long_outlined, 'Billing, salary, expenses & ledger', true),
    _DashboardModule('Examinations', Icons.assignment_outlined, 'Marks & results', true),
    _DashboardModule('Staff', Icons.badge_outlined, 'Team & assignments', true),
    _DashboardModule('Parents', Icons.family_restroom_outlined, 'Families & children', false),
    _DashboardModule('Messages', Icons.forum_outlined, 'School communications', true),
    _DashboardModule('Users', Icons.manage_accounts_outlined, 'Staff and parent sign-ins', true),
    _DashboardModule('Canteen Sales', Icons.fastfood_outlined, 'Quick selling, stock & receipts', true),
    _DashboardModule('Stationery & Books', Icons.menu_book_outlined, 'Products, customer sales & credit', true),
    _DashboardModule('Documents', Icons.folder_copy_outlined, 'Student folders & certificates', true),
    _DashboardModule('Backup & Export', Icons.download_for_offline_outlined, 'JSON, Excel and CSV', true),
  ];

  void _refresh() {
    if (mounted) setState(() {
      _summary = _loadSummary();
      _financeRevision++;
    });
  }

  Future<void> _openModule(int index) async {
    if(index==12 && widget.role=='owner'){
      await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const BackupExportPage()));
      return;
    }
    if(index==4 && !widget.examAccess)return;
    if(index==7 && widget.messageAccess){await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const SchoolMessagesPage(admin:true)));return;}
    if (index == 0 || index == 1) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => index == 0
              ? StudentsPage(role: widget.role)
              : const ClassesPage(),
        ),
      );
      _refresh();
      return;
    }
    if (index == 2) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AttendancePage(role: widget.role),
        ),
      );
      return;
    }
    if (index == 3) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => FinancePage(role: widget.role)),
      );
      _refresh();
      return;
    }
    if (index == 4) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ExaminationsPage(role: widget.role),
        ),
      );
      return;
    }
    if (index == 5) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => StaffPage(role: widget.role),
        ),
      );
      return;
    }
    if (index == 8 && widget.role == 'owner') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => UsersPage(role: widget.role),
        ),
      );
      return;
    }
    if ((index == 9 || index == 10) && widget.role == 'owner') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => InventoryPage(
          role: widget.role,
          department: index == 9 ? 'canteen' : 'stationery',
        )),
      );
      return;
    }
    if (index == 11 && (widget.role == 'owner' || widget.role == 'principal')) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => StudentDocumentsPage(role: widget.role),
      ));
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
    final shownModules = widget.role == 'owner'
        ? _modules
        : _modules.where((module) => module.title != 'Users' && module.title != 'Backup & Export' &&
            module.title != 'Canteen Sales' &&
            module.title != 'Stationery & Books' &&
            (module.title!='Examinations'||widget.examAccess) && (module.title!='Messages'||widget.messageAccess)).toList();

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
          if(widget.messageAccess && widget.summaryLoader==null) const MessageNotificationBell(admin:true),
          const SchoolSettingsButton(),
          IconButton(
            tooltip: 'Refresh school overview',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => signOutSchool(),
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
                  final next = _loadSummary();
                  setState(() => _summary = next);
                  try { await next; } catch (_) { /* Retry through refresh. */ }
                },
                child: ListView(
                  key: const Key('owner_dashboard_scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
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
                                Text('Manage admissions, attendance, finance, staff and examinations.',
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
                    const SizedBox(height: 18),
                    widget.financePreview ??
                        FinanceDashboardPreview(
                          key: ValueKey(_financeRevision),
                        ),
                    if (widget.summaryLoader == null && widget.examAccess) ...[
                      const SizedBox(height: 16),
                      ExamTermOverview(onOpen:()=>_openModule(4)),
                    ],
                    const SizedBox(height: 27),
                    Row(
                      children: [
                        Expanded(
                          child: Text('School management',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Text('${shownModules.length} modules', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // A single vertical Scrollable owns the entire dashboard.
                    // Avoid a nested GridView: it can swallow swipe gestures
                    // on the module cards on some Android devices.
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in shownModules)
                          SizedBox(
                            width: (maxWidth - 34 - (gridColumns - 1) * 10) /
                                gridColumns,
                            height: 142,
                            child: Card(
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openModule(_modules.indexOf(item)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(item.icon, color: scheme.primary,
                                              size: 27),
                                          const Spacer(),
                                          if (item.available)
                                            Icon(Icons.arrow_outward_rounded,
                                                size: 15, color: scheme.primary)
                                          else
                                            Text('Soon',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: scheme.onSurfaceVariant)),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(item.title, maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(item.subtitle, maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 10,
                                              color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('Suffah High School • Preview v0.7',
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
