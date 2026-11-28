import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'school_user_service.dart';

const backupCollections = <String>[
  'users','classes','counters','students','student_photo_directory','staff','staff_contracts',
  'exam_teacher_directory','attendance_class_assignments','attendance_teacher_links',
  'attendance_days','teacher_assignments','system_migrations','teacher_class_links',
  'class_rosters','classwork','exam_term_control','exam_term_cycles','examinations',
  'payroll_records','finance_tuition_rates','finance_transport_rates','finance_salary_rates',
  'finance_recurring_plans','finance_generation_settings','finance_scheduler_runtime',
  'finance_scheduler_runs','finance_fee_bills','finance_salary_bills','finance_recurring_bills',
  'finance_ledger','finance_dashboard_preferences','inventory_student_directory',
  'inventory_items','inventory_sales','inventory_payments','inventory_costs',
  'inventory_purchases','inventory_adjustments','portal_threads','parent_children',
  'parent_profiles','parent_documents','parent_attendance','parent_class_grants',
  'parent_classwork_history','parent_class_schedules','parent_term_summaries',
];
const backupGroups=['subjects','marks','students','messages','days','items','papers','classes'];

class BackupDocument {
  const BackupDocument(this.path,this.data);
  final String path;
  final Map<String,dynamic> data;
}

class BackupReference {
  const BackupReference(this.path);
  final String path;
}
dynamic _portable(dynamic value){
  if(value is DocumentReference)return BackupReference(value.path);
  if(value is Map)return value.map((k,v)=>MapEntry(k.toString(),_portable(v)));
  if(value is List)return value.map(_portable).toList();
  return value;
}

/// Firestore types are explicit, including nested maps, to avoid collisions
/// between real document fields and the backup type markers.
Object encodeBackupValue(dynamic value){
  if(value==null)return {'nullValue':null};
  if(value is bool)return {'booleanValue':value};
  if(value is int)return {'integerValue':value.toString()};
  if(value is double)return {'doubleValue':value.isFinite?value:value.toString()};
  if(value is String)return {'stringValue':value};
  if(value is Timestamp)return {'timestampValue':{'seconds':value.seconds,'nanoseconds':value.nanoseconds}};
  if(value is GeoPoint)return {'geoPointValue':{'latitude':value.latitude,'longitude':value.longitude}};
  if(value is DocumentReference)return {'referenceValue':value.path};
  if(value is BackupReference)return {'referenceValue':value.path};
  if(value is Blob)return {'bytesValue':base64Encode(value.bytes)};
  if(value is List)return {'arrayValue':value.map(encodeBackupValue).toList()};
  if(value is Map)return {'mapValue':value.map((k,v)=>MapEntry(k.toString(),encodeBackupValue(v)))};
  throw FormatException('Unsupported Firestore value: ${value.runtimeType}');
}

class SchoolBackupRepository {
  SchoolBackupRepository({FirebaseFirestore? db,FirebaseAuth? auth})
    :db=db??FirebaseFirestore.instance,auth=auth??FirebaseAuth.instance;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  void requireOwner(){
    if(auth.currentUser?.uid!=schoolOwnerUid)throw StateError('Only the school owner can export data.');
  }
  Future<List<BackupDocument>> readAll(void Function(String,int) progress)async{
    requireOwner();
    final records=<String,BackupDocument>{};
    Future<void> read(Query<Map<String,dynamic>> query,String label)async{
      QueryDocumentSnapshot<Map<String,dynamic>>? cursor;
      final ordered=query.orderBy(FieldPath.documentId);
      while(true){
        requireOwner();
        progress(label,records.length);
        final QuerySnapshot<Map<String,dynamic>> page;
        try {
          page=await (cursor==null?ordered:ordered.startAfterDocument(cursor)).limit(250)
            .get(const GetOptions(source:Source.server));
        } on FirebaseException catch(e) {
          throw StateError('Cannot export $label (${e.code}). Deploy the latest Firestore rules and retry. No partial export was saved.');
        }
        for(final d in page.docs){records[d.reference.path]=BackupDocument(d.reference.path,Map<String,dynamic>.from(_portable(d.data()) as Map));}
        progress(label,records.length);
        if(page.docs.length<250)break;
        cursor=page.docs.last;
      }
    }
    for(final name in backupCollections){await read(db.collection(name),name);}
    for(final name in backupGroups){await read(db.collectionGroup(name),'Nested $name');}
    requireOwner();
    return records.values.toList()..sort((a,b)=>a.path.compareTo(b.path));
  }
}

String _display(dynamic v){
  if(v==null)return '';
  if(v is String)return v;
  if(v is Timestamp)return v.toDate().toUtc().toIso8601String();
  if(v is num||v is bool)return v.toString();
  return jsonEncode(encodeBackupValue(v));
}
String csvBackupCell(String value){
  // Prevent spreadsheet formula injection when opening exported CSV.
  final safe=RegExp(r'^[\s\uFEFF]*[=+\-@]|^[\t\r\n]').hasMatch(value)?"'$value":value;
  return '"${safe.replaceAll('"','""')}"';
}
String _xml(String s)=>s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),'\uFFFD')
  .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
String _column(int index){
  var n=index+1,result='';
  while(n>0){n--;result=String.fromCharCode(65+n%26)+result;n~/=26;}
  return result;
}
Map<String,List<BackupDocument>> _tables(List<BackupDocument> docs){
  final tables=<String,List<BackupDocument>>{};
  for(final d in docs){
    final parts=d.path.split('/');
    tables.putIfAbsent(parts[parts.length-2],()=>[]).add(d);
  }
  if(tables.isEmpty)tables['empty']=[];
  return tables;
}
List<String> _headers(List<BackupDocument> docs)=>['_documentPath',...({for(final d in docs)...d.data.keys}.toList()..sort())];
List<String> _row(BackupDocument d,List<String> headers)=>[d.path,...headers.skip(1).map((h)=>_display(d.data[h]))];

Uint8List encodeSchoolBackupJob((List<BackupDocument>,String) job)=>buildSchoolBackup(job.$1,job.$2);

Uint8List buildSchoolBackup(List<BackupDocument> docs,String format,{DateTime? now}){
  if(format=='json'){
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'schemaVersion':1,'exportedAt':(now??DateTime.now()).toUtc().toIso8601String(),
      'scope':'known school Firestore collections','documentCount':docs.length,
      'documents':[for(final d in docs){'path':d.path,'fields':d.data.map((k,v)=>MapEntry(k,encodeBackupValue(v)))}],
    })));
  }
  final tables=_tables(docs);
  final archive=Archive();
  void add(String name,String data){final bytes=utf8.encode(data);archive.addFile(ArchiveFile(name,bytes.length,bytes));}
  if(format=='csv'){
    for(final e in tables.entries){
      final headers=_headers(e.value);
      final buffer=StringBuffer('\uFEFF');
      buffer.write(headers.map(csvBackupCell).join(',')+'\r\n');
      for(final d in e.value){buffer.write(_row(d,headers).map(csvBackupCell).join(',')+'\r\n');}
      add('${e.key}.csv',buffer.toString());
    }
  }else if(format=='xlsx'){
    const main='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const rel='http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    const pkg='http://schemas.openxmlformats.org/package/2006/relationships';
    final sheets=StringBuffer(),rels=StringBuffer(),types=StringBuffer();
    final used=<String>{};
    var index=0;
    for(final e in tables.entries){
      final headers=_headers(e.value);
      if(headers.length>16384)throw StateError('Too many columns for Excel. Choose JSON or CSV.');
      for(var start=0;start<e.value.length||start==0;start+=1048575){
        index++;
        final base=e.key.length>24?e.key.substring(0,24):e.key;
        var name=base;
        var suffix=1;
        while(!used.add(name.toLowerCase())){name='${base}_${suffix++}';}
        sheets.write('<sheet name="${_xml(name)}" sheetId="$index" r:id="rId$index"/>');
        rels.write('<Relationship Id="rId$index" Type="$rel/worksheet" Target="worksheets/sheet$index.xml"/>');
        types.write('<Override PartName="/xl/worksheets/sheet$index.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
        final body=StringBuffer('<worksheet xmlns="$main"><sheetData>');
        var rowNum=0;
        void writeRow(List<String> cells){
          rowNum++;
          body.write('<row r="$rowNum">');
          for(var i=0;i<cells.length;i++){
            final cell=cells[i];
            if(cell.length>32767)throw StateError('A field exceeds the Excel cell limit. Choose JSON or CSV.');
            body.write('<c r="${_column(i)}$rowNum" t="inlineStr"><is><t xml:space="preserve">${_xml(cell)}</t></is></c>');
          }
          body.write('</row>');
        }
        writeRow(headers);
        for(final d in e.value.skip(start).take(1048575)){writeRow(_row(d,headers));}
        body.write('</sheetData></worksheet>');
        add('xl/worksheets/sheet$index.xml',body.toString());
      }
    }
    add('[Content_Types].xml','<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>$types</Types>');
    add('_rels/.rels','<Relationships xmlns="$pkg"><Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add('xl/workbook.xml','<workbook xmlns="$main" xmlns:r="$rel"><sheets>$sheets</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels','<Relationships xmlns="$pkg">$rels</Relationships>');
  }else{throw ArgumentError('Unknown export format');}
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
