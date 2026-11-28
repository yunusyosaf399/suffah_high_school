import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class SchoolPortalClient {
  static const _url=String.fromEnvironment('SCHOOL_PORTAL_URL',
    defaultValue:'https://asia-south1-suffah-high-school.cloudfunctions.net/schoolPortal');
  Future<Map<String,dynamic>> request(String action,[Map<String,dynamic> fields=const {}]) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)throw StateError('Sign in again.');
    final token=await user.getIdToken();
    if(token==null || token.isEmpty)throw StateError('Sign in again.');
    final uri=Uri.parse(_url);
    if(uri.scheme!='https')throw StateError('The school portal requires HTTPS.');
    final req=http.Request('POST',uri)..followRedirects=false
      ..headers.addAll({'Authorization':'Bearer $token','Content-Type':'application/json'})
      ..body=jsonEncode({...fields,'action':action});
    final response=await http.Response.fromStream(await req.send().timeout(const Duration(seconds:120)));
    Map<String,dynamic> data;
    try {data=Map<String,dynamic>.from(jsonDecode(response.body) as Map);}
    catch(_) {throw StateError('School portal is not available. Ask the administrator to deploy the portal backend.');}
    if(response.statusCode!=200)throw StateError(data['error']?.toString()??'School portal request failed.');
    return data;
  }
}
List<Map<String,dynamic>> portalRows(dynamic value)=>value is List
  ?value.whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList():[];
Map<String,dynamic> portalMap(dynamic value)=>value is Map?Map<String,dynamic>.from(value):{};
