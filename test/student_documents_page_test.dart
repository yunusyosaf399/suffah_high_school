import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/student_documents_repository.dart';
import 'package:suffah_high_school/screens/student_documents_page.dart';

void main() {
  const folder = StudentDocumentFolder(
    id: 'test-1', name: 'Example Student', registrationNo: 'ST-TEST-1',
    classLabel: 'Class 4 – A', rollNo: '12',
    attachments: {'birth_certificate': {'name': 'certificate.pdf',
      'kind': 'birth_certificate', 'path': 'student-documents/test-1/example.pdf',
      'contentType': 'application/pdf', 'bytes': 2048}},
  );
  test('directory maps existing document metadata and searches file names', () {
    final record = StudentDocumentFolder.fromData('old', {
      'fullName': 'Legacy', 'classId': 'c1',
      'attachments': {'other_1': {'name': 'result.png', 'kind': 'other'}},
      'photoPath': 'student-photos/old/photo.webp',
    }, {'c1': 'Class 1'});
    expect(record.fileCount, 2);
    expect(record.registrationNo, 'old');
    expect(record.matches('result.png'), isTrue);
    expect(record.matches('class 1'), isTrue);
    expect(record.matches('unrelated'), isFalse);
  });

  testWidgets('student folder expands and search finds documents', (tester) async {
    await tester.pumpWidget(MaterialApp(home: StudentDocumentsPage(
      role: 'owner', folderLoader: () async => [folder],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Example Student'), findsOneWidget);
    await tester.tap(find.text('Example Student'));
    await tester.pumpAndSettle();
    expect(find.text('certificate.pdf'), findsOneWidget);
    expect(find.text('Upload document'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('documents_search')), 'not found');
    await tester.pumpAndSettle();
    expect(find.text('No matching folders.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('documents_search')), 'certificate.pdf');
    await tester.pumpAndSettle();
    expect(find.text('Example Student'), findsOneWidget);
  });

  testWidgets('seller cannot load private student folders', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(home: StudentDocumentsPage(
      role: 'canteen_seller', folderLoader: () async { called = true; return [folder]; },
    )));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.text('Only the owner or principal can manage student documents.'), findsOneWidget);
  });
}
