import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/school_user_service.dart';
import '../data/school_errors.dart';

class UserAccessPage extends StatefulWidget {
  const UserAccessPage({super.key,required this.account});
  final SchoolUserAccount account;
  @override
  State<UserAccessPage> createState()=>_UserAccessPageState();
}
class _UserAccessPageState extends State<UserAccessPage> {
  late final _account=widget.account;
  late final _permissions={..._account.permissions};
  late final _children=_account.linkedStudentIds.toSet();
  late final _service=SchoolUserService();
  bool _busy=false;
  String? _error;
  Future<void> _run(Future<void> Function() work,{bool close=true}) async {
    if(_busy)return;
    setState((){_busy=true;_error=null;});
    try {
      await work();
      if(mounted && close){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Account updated.')));
        Navigator.pop(context);
      }
    }catch(error){if(mounted)setState(()=>_error=schoolErrorMessage(error));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _selectChildren() async {
    await _run(()async{
      final docs=await FirebaseFirestore.instance.collection('students').get(const GetOptions(source:Source.server));
      if(!mounted)return;
      final options=docs.docs.where((d)=>d.data()['status']!='draft').map((d)=>
        (id:d.id,name:(d.data()['fullName']??d.id).toString(),classId:(d.data()['classId']??'').toString())).toList()
        ..sort((a,b)=>a.name.compareTo(b.name));
      final selected=await showDialog<Set<String>>(context:context,builder:(_)=>_ChildPicker(
        options:options,initial:_children));
      if(selected!=null && mounted)setState(()=>_children..clear()..addAll(selected));
    },close:false);
  }
  Future<void> _remove(bool deleteAuth)async{
    final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:Text(deleteAuth?'Delete sign-in account permanently?':'Remove school access?'),
      content:Text(deleteAuth?'School access is removed first. Firebase Authentication deletion requires the deployed backend. Student, staff, financial and historical records are preserved.':'This account can no longer access the school portal. Its historical records are retained. Use Suspend for a temporary restriction.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(deleteAuth?'Delete sign-in':'Remove access'))]));
    if(ok==true && mounted)await _run(()=>_service.removeAccount(_account,deleteAuthentication:deleteAuth));
  }
  Future<void> _contract() async {
    await _run(()async{
      final ref=FirebaseFirestore.instance.collection('staff_contracts').doc(_account.staffId);
      final data=(await ref.get(const GetOptions(source:Source.server))).data()??{};
      if(!mounted)return;
      final result=await showDialog<Map<String,String>>(context:context,builder:(_)=>_ContractEditor(data:data));
      if(result!=null)await ref.set({...result,'updatedAt':FieldValue.serverTimestamp()});
    },close:false);
  }
  @override
  Widget build(BuildContext context) {
    final labels=schoolPermissionLabels[_account.role]??{};
    return Scaffold(appBar:AppBar(title:const Text('Account & permissions')),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(
        padding:const EdgeInsets.all(16),children:[
          ListTile(leading:const CircleAvatar(child:Icon(Icons.person_outline)),
            title:Text(_account.name),subtitle:Text('${schoolRoles[_account.role]??_account.role} • ${_account.email}')),
          Text(_account.removed?'Removed':_account.active?'Active':'Suspended',
            style:Theme.of(context).textTheme.titleMedium),
          if(_busy)const LinearProgressIndicator(),
          if(!_account.removed)...[
            SwitchListTile(title:const Text('Account active'),subtitle:const Text('Turn off to suspend access temporarily.'),
              value:_account.active,onChanged:_busy?null:(v)=>_run(()=>_service.setActive(_account,v))),
            const Divider(),
            Text('Feature permissions',style:Theme.of(context).textTheme.titleLarge),
            const Text('Permissions can restrict this role; they cannot grant owner or unrelated account access.'),
            if(labels.isEmpty)const Text('This role has a fixed permission set.'),
            for(final entry in labels.entries) SwitchListTile(
              title:Text(entry.value),value:schoolPermission(_permissions,entry.key),
              onChanged:_busy?null:(v)=>setState(()=>_permissions[entry.key]=v)),
            if(_account.role=='parent')...[
              const Divider(),
              Text('Linked children (${_children.length})',style:Theme.of(context).textTheme.titleMedium),
              const Text('Only link children whose guardian identity has been verified by the school.'),
              for(final id in _children)ListTile(title:Text(id),trailing:IconButton(tooltip:'Unlink child',
                onPressed:_busy?null:()=>setState(()=>_children.remove(id)),icon:const Icon(Icons.link_off))),
              OutlinedButton.icon(onPressed:_busy?null:_selectChildren,icon:const Icon(Icons.family_restroom),label:const Text('Select linked children')),
            ],
            if(_account.role=='teacher' && _account.staffId.isNotEmpty)
              OutlinedButton.icon(onPressed:_busy?null:_contract,icon:const Icon(Icons.description_outlined),label:const Text('Edit employment contract')),
            FilledButton(onPressed:_busy?null:()=>_run(()=>_service.saveAccess(_account,_permissions,_children.toList())),
              child:const Text('Save permissions & links')),
            const Divider(),
            OutlinedButton(onPressed:_busy?null:()=>_remove(false),child:const Text('Remove school access')),
          ],
          OutlinedButton(onPressed:_busy?null:()=>_remove(true),child:const Text('Delete Firebase sign-in account')),
          if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        ]))));
  }
}
typedef _ChildOption=({String id,String name,String classId});
class _ChildPicker extends StatefulWidget {
  const _ChildPicker({required this.options,required this.initial});
  final List<_ChildOption> options;
  final Set<String> initial;
  @override
  State<_ChildPicker> createState()=>_ChildPickerState();
}
class _ChildPickerState extends State<_ChildPicker>{
  late final _selected={...widget.initial};
  String _query='';
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Select children'),
    content:SizedBox(width:560,height:400,child:Column(children:[
      TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search name or admission number'),
        onChanged:(v)=>setState(()=>_query=v.toLowerCase())),
      Expanded(child:ListView(children:[
        for(final c in widget.options.where((c)=>'${c.name} ${c.id}'.toLowerCase().contains(_query)))
          CheckboxListTile(value:_selected.contains(c.id),title:Text(c.name),subtitle:Text('${c.id} • ${c.classId}'),
            onChanged:(v)=>setState((){if(v==true){_selected.add(c.id);}else{_selected.remove(c.id);}})),
      ])),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:_selected.length>50?null:()=>Navigator.pop(context,_selected),child:Text('Link ${_selected.length} children'))]);
}
class _ContractEditor extends StatefulWidget {
  const _ContractEditor({required this.data});
  final Map<String,dynamic> data;
  @override
  State<_ContractEditor> createState()=>_ContractEditorState();
}
class _ContractEditorState extends State<_ContractEditor>{
  final _form=GlobalKey<FormState>();
  late final _fields={for(final k in ['type','startDate','endDate','details'])
    k:TextEditingController(text:widget.data[k]?.toString()??'')};
  @override
  void dispose(){for(final c in _fields.values){c.dispose();}super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(scrollable:true,title:const Text('Employment contract'),
    content:SizedBox(width:500,child:Form(key:_form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(controller:_fields['type'],maxLength:80,decoration:const InputDecoration(labelText:'Contract type')),
      for(final field in ['startDate','endDate']) Padding(padding:const EdgeInsets.only(top:10),child:TextFormField(
        controller:_fields[field],decoration:InputDecoration(labelText:field=='startDate'?'Start date (YYYY-MM-DD)':'End date (YYYY-MM-DD, optional)'),
        validator:(v)=>v!=null&&v.trim().isNotEmpty&&DateTime.tryParse(v.trim())==null?'Enter a valid date':null)),
      TextFormField(controller:_fields['details'],maxLength:2000,maxLines:5,decoration:const InputDecoration(labelText:'Contract terms / details')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){if(_form.currentState!.validate())Navigator.pop(context,{for(final e in _fields.entries)e.key:e.value.text.trim()});},
        child:const Text('Save contract'))]);
}
