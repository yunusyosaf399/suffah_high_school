import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_backup_repository.dart';

void main(){
  const docs=[BackupDocument('students/a',{'name':'=unsafe','amount':1200}),BackupDocument('attendance_days/d/marks/a',{'status':'present'})];
  test('JSON retains paths and integer type',(){
    final decoded=jsonDecode(utf8.decode(buildSchoolBackup(docs,'json'))) as Map;
    expect(decoded['documentCount'],2);
    expect(decoded['documents'][0]['fields']['amount']['integerValue'],'1200');
    expect(decoded['documents'][1]['path'],'attendance_days/d/marks/a');
  });
  test('CSV protects spreadsheet formulas and separates tables',(){
    final zip=ZipDecoder().decodeBytes(buildSchoolBackup(docs,'csv'));
    expect(zip.files.map((f)=>f.name),containsAll(['students.csv','marks.csv']));
    final csv=utf8.decode(zip.files.firstWhere((f)=>f.name=='students.csv').content);
    expect(csv,contains("'=unsafe"));
  });
  test('XLSX contains workbook and inline text, never formula elements',(){
    final zip=ZipDecoder().decodeBytes(buildSchoolBackup(docs,'xlsx'));
    expect(zip.files.map((f)=>f.name),containsAll(['[Content_Types].xml','xl/workbook.xml','xl/worksheets/sheet1.xml']));
    final sheet=utf8.decode(zip.files.firstWhere((f)=>f.name=='xl/worksheets/sheet1.xml').content);
    expect(sheet,contains('t="inlineStr"'));
    expect(sheet,isNot(contains('<f>')));
  });
}
