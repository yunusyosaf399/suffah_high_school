import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_checkout_service.dart';

void main() {
  test('existing admissions with no active/status stay available to checkout',
      () {
    final projected = inventoryStudentDirectoryProjection('ST-2024-0003', {
      'fullName': 'Sadia Khan',
      'rollNo': '10030',
      'classId': 'class-3',
      'guardianPhone': 'private',
      'health': {'condition': 'private'},
    });
    expect(projected, isNotNull);
    expect(projected!['active'], true);
    expect(projected['fullName'], 'Sadia Khan');
    expect(projected['rollNo'], '10030');
    expect(projected.keys,
        unorderedEquals(['studentId', 'fullName', 'rollNo',
          'classId', 'active']));
    expect(projected.containsKey('guardianPhone'), isFalse);
    expect(projected.containsKey('health'), isFalse);
  });

  test('drafts and records with missing names are never exposed', () {
    expect(inventoryStudentDirectoryProjection('ST-DRAFT', {
      'fullName': 'Draft – ST-DRAFT',
      'status': 'draft',
      'active': false,
    }), isNull);
    expect(inventoryStudentDirectoryProjection('ST-BLANK', {
      'status': 'admitted',
      'active': true,
    }), isNull);
  });

  test('archived admitted student is synchronized as inactive', () {
    final entry = inventoryStudentDirectoryProjection('ST-2022-0001', {
      'fullName': 'Faisal Ahmed',
      'status': 'admitted', 'active': false,
    });
    expect(entry, isNotNull);
    expect(entry!['active'], false);
    expect(entry['rollNo'], '');
    expect(entry['classId'], '');
  });

  test('sync summary reports copied and skipped student counts', () {
    const report = InventoryStudentSyncResult(
      scanned: 12, synced: 10, active: 9, skipped: 2);
    expect(report.summary, '10 students synchronized (9 active, 2 skipped).');
  });
}
