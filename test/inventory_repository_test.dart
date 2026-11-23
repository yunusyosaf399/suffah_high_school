import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_repository.dart';

void main() {
  test('PKR prices use integer minor units', () {
    expect(inventoryMoneyMinor('125'), 12500);
    expect(inventoryMoneyMinor('125.5'), 12550);
    expect(inventoryMoneyMinor('0.01'), 1);
    expect(inventoryMoneyMinor(' 999.99 '), 99999);
    expect(inventoryRupees(12550), 'Rs 125.50');
  });

  test('invalid prices cannot be silently rounded', () {
    for (final input in ['-3', '12.345', 'abc', '1,000', '', '1e10']) {
      expect(() => inventoryMoneyMinor(input), throwsFormatException,
        reason: 'Rejected invalid input: $input');
    }
  });

  test('sale availability uses active flag and stock', () {
    const item = InventoryItem(
      id: 'SNACK001', name: 'Chips', department: 'canteen',
      unit: 'packet', priceMinor: 10000, stockQty: 3,
      reorderPoint: 4, active: true, description: '',
    );
    expect(item.canSell, isTrue);
    expect(item.isLowStock, isTrue);
  });
}
