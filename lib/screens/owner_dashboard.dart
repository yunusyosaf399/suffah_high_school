import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'owner_analytics.dart';
import 'owner_overview.dart';
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

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({
    super.key,
    required this.displayName,
    this.role = 'owner',
    this.summaryLoader,
    this.financePreview,
    this.moduleBuilder,
  });

  final String displayName;
  final String role;
  // Optional sources make navigation and scrolling testable without Firebase.
  final Future<SchoolSummary> Function()? summaryLoader;
  final Widget? financePreview;
  final Widget Function(int index)? moduleBuilder;

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
  final _navigator = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  int _selected = -1;
  int _navigationRevision = 0;
  final _dashboardChanges = ChangeNotifier();
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _dashboardChanges.notifyListeners();
  }
  @override
  void dispose(){_dashboardChanges.dispose();super.dispose();}
  bool _pinned = true;
  bool _slideshow = false;
  bool _savingPreferences = false;
  bool _preferencesTouched = false;

  bool get _realOwner => widget.role == 'owner' && widget.summaryLoader == null;

  @override
  void initState() {
    super.initState();
    if (_realOwner) _loadDashboardPreferences();
  }

  DocumentReference<Map<String, dynamic>>? _preferences() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null :
      FirebaseFirestore.instance.collection('finance_dashboard_preferences').doc(uid);
  }

  Future<void> _loadDashboardPreferences() async {
    try {
      final ref = _preferences();
      if (ref == null) return;
      final data = (await ref.get()).data();
      if (!mounted || _preferencesTouched || data == null) return;
      setState(() {
        _pinned = data['navigationPinned'] != false;
        _slideshow = data['schoolSlideshow'] == true;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dashboard preferences could not be loaded.')));
    }
  }

  Future<void> _setPreferences({bool? pinned, bool? slideshow}) async {
    if (_savingPreferences) return;
    setState(() {
      _preferencesTouched = true;
      _pinned = pinned ?? _pinned;
      _slideshow = slideshow ?? _slideshow;
      _savingPreferences = _realOwner;
    });
    if (!_realOwner) return;
    try {
      final ref = _preferences();
      if (ref == null) throw StateError('Sign in again.');
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final previous = (await tx.get(ref)).data();
        tx.set(ref, {
          if (previous == null) ...{
            'uid': ref.id,
            'visibleCards': ['credit', 'debit', 'net', 'fees'],
            'rotate': false,
          },
          'navigationPinned': _pinned,
          'schoolSlideshow': _slideshow,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changed for this session; preferences could not be saved.')));
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  void _home() {
    _navigationRevision++;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    if (_selected != -1) {
      setState(() => _selected = -1);
      _refresh();
    }
  }

  void _search() {
    _showPage(-2, const GlobalSearchPage());
  }

  void _settings() {
    _showPage(-3, _DashboardSettings(
      pinned: _pinned, slideshow: _slideshow,
      owner: widget.role == 'owner',
      onPinned: (v) => _setPreferences(pinned: v),
      onSlideshow: (v) => _setPreferences(slideshow: v),
    ));
  }

  Widget _navigation(List<_DashboardModule> modules, {required bool expanded, bool drawer = false}) {
    Widget tile(int index, String title, IconData icon, VoidCallback action) {
      final selected = _selected == index;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
        child: Tooltip(message: title, child: Material(
          color: selected ? dashboardPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              if (drawer) _scaffold.currentState?.closeDrawer();
              action();
            },
            child: SizedBox(height: 43, child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                if (expanded) const SizedBox(width: 12),
                Icon(icon, size: 21, color: selected ? Colors.white : const Color(0xFF545363)),
                if (expanded) ...[
                  const SizedBox(width: 13),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : const Color(0xFF292537)))),
                ],
              ],
            )),
          ),
        )),
      );
    }
    return Material(
      color: const Color(0xFFFCFBFE),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          child: expanded ? Row(children: [
            Image.asset('assets/icon/app_icon.png',width:38,height:38,fit:BoxFit.contain),
            const SizedBox(width:8),
            const Expanded(child: Text('Suffah\nHigh School', style:TextStyle(fontSize:16,fontWeight:FontWeight.w800))),
            if(!drawer) IconButton(tooltip:'Collapse navigation',onPressed:_savingPreferences?null:()=>_setPreferences(pinned:false),
              icon:const Icon(Icons.keyboard_double_arrow_left,color:dashboardPurple)),
          ]) : Column(children:[
            Image.asset('assets/icon/app_icon.png',width:35,height:35,fit:BoxFit.contain),
            IconButton(tooltip:'Pin expanded navigation',onPressed:_savingPreferences?null:()=>_setPreferences(pinned:true),
              icon:const Icon(Icons.keyboard_double_arrow_right,color:dashboardPurple)),
          ])),
        Expanded(child: ListView(padding: const EdgeInsets.only(bottom:8),children:[
          tile(-2,'Search...',Icons.search,_search),
          const SizedBox(height:10),
          tile(-1,'Dashboard',Icons.dashboard_outlined,_home),
          for(final module in modules)
            tile(_modules.indexOf(module),module.title,module.icon,()=>_openModule(_modules.indexOf(module))),
          tile(-3,'Settings',Icons.settings_outlined,_settings),
        ])),
        const Divider(indent:12,endIndent:12),
        Padding(padding:const EdgeInsets.only(bottom:12),child:tile(-4,'Logout',Icons.logout_rounded,()=>FirebaseAuth.instance.signOut())),
      ]),
    );
  }

  static const _modules = [
    _DashboardModule('Students', Icons.groups_outlined, 'Admissions & profiles', true),
    _DashboardModule('Classes', Icons.school_outlined, 'Classes & sections', true),
    _DashboardModule('Attendance', Icons.fact_check_outlined, 'Daily class registers', true),
    _DashboardModule('Fees & Finance', Icons.receipt_long_outlined, 'Billing, salary, expenses & ledger', true),
    _DashboardModule('Examinations', Icons.assignment_outlined, 'Marks & results', true),
    _DashboardModule('Staff', Icons.badge_outlined, 'Team & assignments', true),
    _DashboardModule('Parents', Icons.family_restroom_outlined, 'Families & children', false),
    _DashboardModule('Messages', Icons.forum_outlined, 'School communications', false),
    _DashboardModule('Users', Icons.manage_accounts_outlined, 'Staff and parent sign-ins', true),
    _DashboardModule('Canteen Sales', Icons.fastfood_outlined, 'Quick selling, stock & receipts', true),
    _DashboardModule('Stationery & Books', Icons.menu_book_outlined, 'Products, customer sales & credit', true),
    _DashboardModule('Documents', Icons.folder_copy_outlined, 'Student folders & certificates', true),
  ];

  void _refresh() {
    if (mounted) setState(() {
      _summary = _loadSummary();
      _financeRevision++;
    });
  }

  Future<void> _showPage(int index, Widget page) async {
    final nav = _navigator.currentState;
    if(nav == null)return;
    final revision = ++_navigationRevision;
    nav.popUntil((route)=>route.isFirst);
    setState(()=>_selected=index);
    await nav.push<void>(MaterialPageRoute(builder:(_)=>page));
    if(!mounted || revision!=_navigationRevision)return;
    setState(()=>_selected=-1);
    _refresh();
  }

  Future<void> _openModule(int index) async {
    final module = _modules[index];
    if(!module.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${module.title} is planned for a future version.')));
      return;
    }
    final page = widget.moduleBuilder?.call(index) ?? (switch(index) {
      0 => StudentsPage(role:widget.role),
      1 => const ClassesPage(),
      2 => AttendancePage(role:widget.role),
      3 => FinancePage(role:widget.role),
      4 => ExaminationsPage(role:widget.role),
      5 => StaffPage(role:widget.role),
      8 when widget.role=='owner' => UsersPage(role:widget.role),
      9 when widget.role=='owner' => InventoryPage(role:widget.role,department:'canteen'),
      10 when widget.role=='owner' => InventoryPage(role:widget.role,department:'stationery'),
      11 => StudentDocumentsPage(role:widget.role),
      _ => const SizedBox.shrink(),
    });
    await _showPage(index,page);
  }

  List<_DashboardModule> get _shownModules => [for(final i in [0,1,2,3,4,5,9,10,11,8,6,7])
    if(widget.role=='owner'||![8,9,10].contains(i)) _modules[i]];

  Widget _dashboard() {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FB),
      body: LayoutBuilder(builder:(context,limits){
        final width=limits.maxWidth;
        final maxWidth=width;
        final gridColumns=width>=1060?4:width>=640?3:2;
        final scheme=Theme.of(context).colorScheme;
        final shownModules=_shownModules;
        return RefreshIndicator(onRefresh:()async{
          _refresh();
          try{await _summary;}catch(_){}
        },child:ListView(
          key:const Key('owner_dashboard_scroll'),
          physics:const AlwaysScrollableScrollPhysics(),
          padding:const EdgeInsets.fromLTRB(17,18,17,32),
          children:[
            Row(children:[
              const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('Dashboard',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),
                Text('School overview and analytics',style:TextStyle(color:Color(0xFF68647D))),
              ])),
              if(widget.role=='owner') ...[
                if(width>620)const Text('Slideshow'),
                Tooltip(message:_slideshow?'Stop dashboard slideshow':'Start 10-second dashboard slideshow',
                  child:Switch(value:_slideshow,onChanged:_savingPreferences?null:(v)=>_setPreferences(slideshow:v))),
              ],
              IconButton(tooltip:'Refresh school overview',onPressed:_refresh,icon:const Icon(Icons.refresh_rounded)),
              if(width>620) ...[
                const CircleAvatar(backgroundColor:Color(0xFFEDE5F8),foregroundColor:dashboardPurple,child:Icon(Icons.person)),
                const SizedBox(width:7),
                ConstrainedBox(constraints:const BoxConstraints(maxWidth:110),child:Text(widget.displayName,maxLines:1,overflow:TextOverflow.ellipsis)),
              ],
            ]),
            const SizedBox(height:18),
            if(_realOwner && widget.financePreview==null)
              OwnerOverview(key:ValueKey(_financeRevision),summary:_summary,slideshow:_slideshow,
                onOpenExams:()=>_openModule(4),examCard:ExamTermOverview(onOpen:()=>_openModule(4),dashboard:true))
            else ...[
              const Text('School overview',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
              const SizedBox(height:12),
              FutureBuilder<SchoolSummary>(future:_summary,builder:(context,snapshot){
                if(snapshot.connectionState==ConnectionState.waiting)return const DashboardSkeleton(full:true);
                if(snapshot.hasError)return const Text('Tap refresh to retry');
                return Row(children:[
                  Expanded(child:_StatisticCard(item:_Stat('Student records','${snapshot.data?.students??"—"}',Icons.groups_outlined))),
                  const SizedBox(width:10),
                  Expanded(child:_StatisticCard(item:_Stat('Class sections','${snapshot.data?.classes??"—"}',Icons.school_outlined))),
                ]);
              }),
              const SizedBox(height:18),
              widget.financePreview??FinanceDashboardPreview(key:ValueKey(_financeRevision)),
              if(widget.summaryLoader==null)ExamTermOverview(onOpen:()=>_openModule(4),dashboard:true),
            ],
            if(widget.summaryLoader!=null || widget.role!='owner') ...[
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

            ],
          ],
        ));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop=MediaQuery.sizeOf(context).width>=900;
    return Scaffold(
      key:_scaffold,
      appBar:desktop?null:AppBar(title:const Text('Suffah High School')),
      drawer:desktop?null:Drawer(child:SafeArea(child:_navigation(_shownModules,expanded:true,drawer:true))),
      body:SafeArea(child:Row(children:[
        if(desktop) ...[
          AnimatedContainer(key:const Key('persistent_school_sidebar'),
            duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:180),
            width:_pinned?235:72,
            child:LayoutBuilder(builder:(context,c)=>_navigation(_shownModules,expanded:c.maxWidth>=205))),
          const VerticalDivider(width:1,thickness:1,color:Color(0xFFE4DFF0)),
        ],
        Expanded(child:NavigatorPopHandler<void>(
          onPopWithResult:(_){_navigator.currentState?.maybePop();},
          child:Navigator(key:_navigator,onGenerateRoute:(_)=>MaterialPageRoute<void>(
            settings:const RouteSettings(name:'/dashboard'),
            builder:(_)=>_DashboardBody(builder:_dashboard),
          )),
        )),
      ])),
    );
  }
}

// The root route is retained by the nested navigator; rebuild it when
// shell preferences or refreshed data change without resetting the stack.
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.builder});
  final Widget Function() builder;
  @override
  Widget build(BuildContext context){
    final state=context.findAncestorStateOfType<_OwnerDashboardState>()!;
    return AnimatedBuilder(animation:state._dashboardChanges,builder:(_,__)=>builder());
  }
}

class _DashboardSettings extends StatefulWidget {
  const _DashboardSettings({required this.pinned,required this.slideshow,required this.owner,
    required this.onPinned,required this.onSlideshow});
  final bool pinned,slideshow,owner;
  final ValueChanged<bool> onPinned,onSlideshow;
  @override State<_DashboardSettings> createState()=>_DashboardSettingsState();
}
class _DashboardSettingsState extends State<_DashboardSettings>{
  late bool pinned=widget.pinned, slideshow=widget.slideshow;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Dashboard settings')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      SwitchListTile(title:const Text('Expanded desktop sidebar'),value:pinned,onChanged:(v){setState(()=>pinned=v);widget.onPinned(v);}),
      if(widget.owner)SwitchListTile(title:const Text('Dashboard slideshow'),subtitle:const Text('Rotate analytics every 10 seconds'),
        value:slideshow,onChanged:(v){setState(()=>slideshow=v);widget.onSlideshow(v);}),
    ]));
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
