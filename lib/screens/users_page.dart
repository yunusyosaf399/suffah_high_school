import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/school_errors.dart';
import '../data/school_user_service.dart';
import '../data/staff_repository.dart';
import '../data/parent_portal_repository.dart';
import 'user_access_page.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.role,
    this.usersStream,
    this.createOverride,
    this.teachersStream,
    this.childrenStream,
    this.parentCreateOverride,
  });

  final String role;
  final Stream<List<SchoolUserAccount>>? usersStream;
  final Future<CreatedSchoolUser> Function({
    required String name,
    required String email,
    required String password,
    required String role,
    String? staffId,
  })? createOverride;
  final Stream<List<StaffMember>>? teachersStream;
  final Stream<List<ParentChildOption>>? childrenStream;
  final Future<CreatedSchoolUser> Function({required String name,required String email,required String password,required List<ParentChildOption> children,required bool guardianConfirmed})? parentCreateOverride;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final SchoolUserService _service = SchoolUserService();
  late Stream<List<SchoolUserAccount>> _users =
      widget.usersStream ?? _service.watchUsers();

  void _reload() =>
      setState(() => _users = widget.usersStream ?? _service.watchUsers());

  bool _syncing=false;
  Future<void> _syncParents()async{
    if(_syncing)return;
    setState(()=>_syncing=true);
    try{
      final count=await ParentPortalRepository().syncExisting();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Parent records synchronized for $count linked children.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(schoolErrorMessage(e))));}
    finally{if(mounted)setState(()=>_syncing=false);}
  }

  Future<void> _create() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateUserDialog(
        teacherStreamProvider: () => widget.teachersStream ?? StaffRepository().watchStaff(),
        childStreamProvider:()=>widget.childrenStream??_service.watchParentChildren(),
        onCreateParent:({required name,required email,required password,required children,required guardianConfirmed})=>
          widget.parentCreateOverride?.call(name:name,email:email,password:password,children:children,guardianConfirmed:guardianConfirmed)??
          _service.createAccount(name:name,email:email,password:password,role:'parent',children:children,guardianConfirmed:guardianConfirmed),
        onCreate: ({
          required String name,
          required String email,
          required String password,
          required String role,
          String? staffId,
        }) => widget.createOverride != null
            ? widget.createOverride!(
                name: name, email: email, password: password,
                role: role, staffId: staffId)
            : _service.createAccount(
                name: name, email: email, password: password,
                role: role, staffId: staffId),
      ),
    );
  }

  Future<void> _toggle(SchoolUserAccount user, bool active) async {
    try {
      await _service.setActive(user, active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(active ? 'Account activated.' : 'Account suspended.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(schoolErrorMessage(error)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner') {
      return Scaffold(
        appBar: AppBar(title: const Text('Users')),
        body: const Center(child: Text(
          'Only the school owner can manage user accounts.',
        )),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & accounts',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip:'Sync parent records',onPressed:_syncing?null:_syncParents,icon:_syncing?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.sync)),
          IconButton(
            tooltip: 'Reload accounts',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.person_add_alt_1, size: 19),
                  label: const Text('Create user account'),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('School users', style: Theme.of(context)
                          .textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800)),
                        const SizedBox(height: 7),
                        Text(
                          'Create accounts for principals, staff, canteen sellers or inventory managers. Only the owner assigns account roles.',
                          style: TextStyle(fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                  color: scheme.primary),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Teachers need an active staff link. Canteen sellers can only view stock and record sales; inventory managers may manage items, prices and stock.',
                                    style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                StreamBuilder<List<SchoolUserAccount>>(
                  stream: _users,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(child: _EmptyUsers(
                        message: schoolErrorMessage(snapshot.error!),
                      ));
                    }
                    if (!snapshot.hasData) {
                      return const SliverToBoxAdapter(
                        child: _EmptyUsers(message: 'Loading accounts…'),
                      );
                    }
                    final users = snapshot.data!;
                    if (users.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: _EmptyUsers(message: 'No user profiles yet.'),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final roleName = user.isOwner
                              ? 'Owner' : schoolRoles[user.role] ?? user.role;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap:user.isOwner?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>UserAccessPage(account:user))),
                              leading: CircleAvatar(
                                child: Icon(user.isOwner
                                    ? Icons.admin_panel_settings_outlined
                                    : Icons.person_outline_rounded),
                              ),
                              title: Text(user.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                '$roleName • ${user.email.isEmpty ? "Email not listed" : user.email} • ${user.removed?'Removed':user.active?'Active':'Suspended'}',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11)),
                              trailing: user.isOwner || user.removed
                                  ? const Icon(Icons.lock_outline)
                                  : Switch.adaptive(
                                      value: user.active,
                                      onChanged: (active) => _toggle(user, active),
                                    ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Text(message, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12)),
    ),
  );
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.onCreate, required this.teacherStreamProvider,required this.childStreamProvider,required this.onCreateParent});
  final Stream<List<ParentChildOption>> Function() childStreamProvider;
  final Future<CreatedSchoolUser> Function({required String name,required String email,required String password,required List<ParentChildOption> children,required bool guardianConfirmed}) onCreateParent;
  final Stream<List<StaffMember>> Function() teacherStreamProvider;
  final Future<CreatedSchoolUser> Function({
    required String name,
    required String email,
    required String password,
    required String role,
    String? staffId,
  }) onCreate;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  late final _password = TextEditingController(text: _newPassword());
  String _role = 'principal';
  String? _teacherId;
  String? _teacherEmail;
  final _children=<ParentChildOption>[];
  bool _guardianConfirmed=false;
  Stream<List<ParentChildOption>>? _childStreamCache;
  bool _busy = false;
  bool _revealPassword = false;
  Stream<List<StaffMember>>? _teacherStreamCache;

  Stream<List<StaffMember>> get _teacherStream =>
      _teacherStreamCache ??= widget.teacherStreamProvider();
  CreatedSchoolUser? _created;
  String? _error;

  static String _newPassword() {
    const symbols = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    return List.generate(16, (_) => symbols[random.nextInt(symbols.length)])
      .join();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_role == 'teacher' &&
          (_teacherId == null || _teacherEmail == null ||
           _teacherEmail!.isEmpty)) {
        throw ArgumentError('Select an active teacher and an email from the profile.');
      }
      if(_role=='parent' && (_children.isEmpty || !_guardianConfirmed))throw ArgumentError('Select children and confirm the guardian identity and email.');
      final created = _role=='parent'?await widget.onCreateParent(name:_name.text,email:_email.text,password:_password.text,children:List.of(_children),guardianConfirmed:_guardianConfirmed):await widget.onCreate(
        name: _name.text,
        email: _role == 'teacher' ? _teacherEmail! : _email.text,
        password: _password.text,
        role: _role,
        staffId: _role == 'teacher' ? _teacherId : null,
      );
      if (mounted) setState(() => _created = created);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _parentForm()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    StreamBuilder<List<ParentChildOption>>(
      stream:_childStreamCache??=widget.childStreamProvider(),
      builder:(context,snapshot){
        if(snapshot.hasError)return Text(schoolErrorMessage(snapshot.error!));
        if(!snapshot.hasData)return const LinearProgressIndicator();
        final options=snapshot.data!;
        return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          OutlinedButton.icon(key:const Key('parent_child_picker'),onPressed:_busy||options.isEmpty?null:()async{
            final selected=await showDialog<List<ParentChildOption>>(context:context,builder:(_)=>
              _ParentChildPicker(options:options,initial:_children));
            if(selected==null||!mounted)return;
            setState((){
              final previous=_children.firstOrNull?.id;
              _children..clear()..addAll(selected);
              if(_children.firstOrNull?.id!=previous){
                _name.text=_children.firstOrNull?.guardianName??'';
                _email.text=_children.firstOrNull?.email??'';
              }
              _guardianConfirmed=false;
            });
          },icon:const Icon(Icons.family_restroom),label:Text(_children.isEmpty?'Select student(s) *':'Change selected children (${_children.length})')),
          if(options.isEmpty)const Text('No active admitted students are available.'),
          for(final child in _children)
            ListTile(contentPadding:EdgeInsets.zero,title:Text(child.name),
              subtitle:Text('${child.id} • ${child.classId}\n${child.guardianName} • ${child.relationship}\nPhone: ${child.phone.isEmpty?'Not recorded':child.phone}\nSaved email: ${child.email.isEmpty?'Not recorded':child.email}')),
        ]);
      }),
    if(_children.isNotEmpty)...[
      const SizedBox(height:8),
      TextField(controller:_name,readOnly:_busy,decoration:const InputDecoration(labelText:'Parent / guardian name *'),
        onChanged:(_)=>setState(()=>_guardianConfirmed=false)),
      const SizedBox(height:12),
      if(_children.map((c)=>c.email).where((e)=>e.isNotEmpty).toSet().isNotEmpty)
        Wrap(spacing:6,children:[
          for(final email in _children.map((c)=>c.email).where((e)=>e.isNotEmpty).toSet())
            ActionChip(label:Text(email),onPressed:_busy?null:()=>setState((){_email.text=email;_guardianConfirmed=false;})),
        ]),
      TextField(key:const Key('parent_guardian_email'),controller:_email,readOnly:_busy,
        keyboardType:TextInputType.emailAddress,autocorrect:false,
        decoration:InputDecoration(labelText:'Guardian email / account email *',
          helperText:_children.first.email.isEmpty?'No email recorded. Enter a valid guardian email.':'Use the saved email or enter a correction.'),
        onChanged:(_)=>setState(()=>_guardianConfirmed=false)),
      const SizedBox(height:8),
      Text('The account email will be saved as the guardian email for every selected child.'),
      if(_children.any((c)=>c.email.isNotEmpty&&c.email.trim().toLowerCase()!=_email.text.trim().toLowerCase()))
        Text('Warning: an existing guardian email will be replaced.',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      CheckboxListTile(key:const Key('parent_guardian_confirm'),contentPadding:EdgeInsets.zero,
        value:_guardianConfirmed,onChanged:_busy?null:(v)=>setState(()=>_guardianConfirmed=v==true),
        title:const Text('I verified this guardian may access every selected child and approve the email update.')),
    ],
  ]);

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(_created == null ? 'Create user account' : 'Account created'),
    content: SizedBox(
      width: 400,
      child: _created == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('account_role_dropdown'),
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account role'),
                  items: schoolRoles.entries.map((entry) =>
                      DropdownMenuItem(
                        value: entry.key, child: Text(entry.value))).toList(),
                  onChanged: _busy ? null : (role) {
                    if (role != null) setState(() {
                      _role = role;
                      _children.clear();
                      _guardianConfirmed=false;
                      _name.clear();
                      _email.clear();
                      _teacherId = null;
                      _teacherEmail = null;
                      if (role == 'teacher') {
                        _name.clear();
                        _email.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_role == 'teacher') ...[
                  StreamBuilder<List<StaffMember>>(
                    stream: _teacherStream,
                    builder: (context, snapshot) {
                      final teachers = (snapshot.data ?? const <StaffMember>[])
                          .where((staff) => staff.isTeacher && staff.active)
                          .toList()
                        ..sort((a, b) => a.fullName.compareTo(b.fullName));
                      if (snapshot.hasError) {
                        return Text('Could not load teacher profiles.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error,
                            fontSize: 12));
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        );
                      }
                      StaffMember? selected;
                      for (final item in teachers) {
                        if (item.id == _teacherId) selected = item;
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            key: const Key('teacher_profile_dropdown'),
                            initialValue: selected?.id,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Select active teacher *'),
                            items: teachers.map((staff) => DropdownMenuItem(
                              value: staff.id,
                              child: Text('${staff.fullName} • ${staff.staffNo}',
                                overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: _busy ? null : (id) {
                              StaffMember? next;
                              for (final item in teachers) {
                                if (item.id == id) next = item;
                              }
                              setState(() {
                                _teacherId = id;
                                _teacherEmail = next?.accountEmails.firstOrNull;
                                _name.text = next?.fullName ?? '';
                                _email.text = _teacherEmail ?? '';
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          if (selected == null)
                            const Text('Choose a teacher profile to continue.',
                              style: TextStyle(fontSize: 11))
                          else if (selected.accountEmails.isEmpty)
                            const Text('This teacher has no valid email saved. Edit the staff profile first.',
                              style: TextStyle(fontSize: 11))
                          else
                            DropdownButtonFormField<String>(
                              key: const Key('teacher_email_dropdown'),
                              initialValue: selected.accountEmails.contains(_teacherEmail)
                                  ? _teacherEmail : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Account email *'),
                              items: selected.accountEmails.map((email) =>
                                DropdownMenuItem(value: email, child: Text(email))).toList(),
                              onChanged: _busy ? null : (email) {
                                if (email == null) return;
                                setState(() {
                                  _teacherEmail = email;
                                  _email.text = email;
                                });
                              },
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _name,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Teacher name',
                              helperText: 'Taken from the selected staff profile'),
                          ),
                        ],
                      );
                    },
                  ),
                ] else if(_role=='parent') ...[
                  _parentForm(),
                ] else ...[
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email address *'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  readOnly: true,
                  obscureText: !_revealPassword,
                  decoration: InputDecoration(
                    labelText: 'Generated temporary password',
                    suffixIcon: IconButton(
                      tooltip: 'Show or hide password',
                      onPressed: () => setState(
                        () => _revealPassword = !_revealPassword),
                      icon: Icon(_revealPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A separate Firebase sign-in session keeps the owner logged in. Share credentials privately.',
                  style: TextStyle(fontSize: 11),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
                ],
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('User created successfully',
                  style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SelectableText(_created!.email),
                const SizedBox(height: 12),
                const Text('Temporary password — copy it now',
                  style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                SelectableText(_password.text,
                  style: const TextStyle(fontSize: 14)),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _password.text)),
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Copy password'),
                ),
                const SizedBox(height: 10),
                Text(_created!.resetEmailSent
                    ? 'A password reset/setup email was requested. Share the temporary password only if needed.'
                    : 'Reset email was not sent. Share the temporary password securely and ask the user to change it.',
                  style: const TextStyle(fontSize: 11)),
              ],
            ),
    ),
    actions: [
      if (_created == null) ...[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Creating…' : 'Create account'),
        ),
      ] else
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
    ],
  );
}

class _ParentChildPicker extends StatefulWidget{
  const _ParentChildPicker({required this.options,required this.initial});
  final List<ParentChildOption> options,initial;
  @override
  State<_ParentChildPicker> createState()=>_ParentChildPickerState();
}
class _ParentChildPickerState extends State<_ParentChildPicker>{
  late final _selected=widget.initial.map((c)=>c.id).toList();
  String _query='';
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Select children for guardian'),
    content:SizedBox(width:500,height:400,child:Column(children:[
      TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search student, admission no., guardian or email'),
        onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase())),
      const SizedBox(height:8),
      Expanded(child:ListView.builder(
        itemCount:widget.options.where((c)=>'${c.name} ${c.id} ${c.guardianName} ${c.email}'.toLowerCase().contains(_query)).length,
        itemBuilder:(context,i){
          final c=widget.options.where((c)=>'${c.name} ${c.id} ${c.guardianName} ${c.email}'.toLowerCase().contains(_query)).elementAt(i);
          return CheckboxListTile(key:ValueKey('parent_child_${c.id}'),value:_selected.contains(c.id),
            title:Text('${c.name} • ${c.id}'),subtitle:Text('${c.classId} • ${c.guardianName}\n${c.email.isEmpty?'No guardian email':c.email}'),
            onChanged:(v)=>setState((){if(v==true&&_selected.length<50){_selected.add(c.id);}else if(v==false){_selected.remove(c.id);}}));
        })),
    ])),actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:_selected.isEmpty?null:()=>Navigator.pop(context,[for(final id in _selected)
        if(widget.options.any((c)=>c.id==id))widget.options.firstWhere((c)=>c.id==id)]),
        child:Text('Select ${_selected.length} children')),
    ]);
}
