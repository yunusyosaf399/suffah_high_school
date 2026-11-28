import 'account_picture.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final schoolThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadSchoolTheme() async {
  try {
    final stored=(await SharedPreferences.getInstance()).getString('school_theme');
    schoolThemeMode.value=ThemeMode.values.firstWhere((m)=>m.name==stored,orElse:()=>ThemeMode.system);
  } catch (_) {
    // The system setting remains available if local storage is unavailable.
  }
}

class SchoolSettingsButton extends StatelessWidget {
  const SchoolSettingsButton({super.key});
  @override
  Widget build(BuildContext context)=>IconButton(tooltip:'Settings',
    icon:const Icon(Icons.settings_outlined),
    onPressed:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const SchoolSettingsPage())));
}

class SchoolSettingsPage extends StatelessWidget {
  const SchoolSettingsPage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Settings')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:640),
      child:ValueListenableBuilder<ThemeMode>(valueListenable:schoolThemeMode,builder:(context,mode,_)=>ListView(
        padding:const EdgeInsets.all(16),children:[
          Card(child:ListTile(leading:AccountPicture(uid:FirebaseAuth.instance.currentUser?.uid??'',name:'Me'),
            title:const Text('Account picture'),subtitle:const Text('Upload, replace or remove your profile picture'),
            onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const AccountPicturePage())))),
          Text('Appearance',style:Theme.of(context).textTheme.titleLarge),
          const Text('Choose how the school app looks on this device.'),
          const SizedBox(height:12),
          for(final choice in ThemeMode.values) Card(child:ListTile(
            leading:Icon(choice==ThemeMode.system?Icons.brightness_auto_outlined:choice==ThemeMode.dark?Icons.dark_mode_outlined:Icons.light_mode_outlined),
            title:Text(choice==ThemeMode.system?'Follow system':choice==ThemeMode.dark?'Dark theme':'Light theme'),
            trailing:Icon(choice==mode?Icons.check_circle:Icons.radio_button_unchecked),
            onTap:() async {
              schoolThemeMode.value=choice;
              try {await (await SharedPreferences.getInstance()).setString('school_theme',choice.name);}
              catch(_) {if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Theme applied for this session; preference could not be saved.')));}
            })),
        ]))),
    ));
}
