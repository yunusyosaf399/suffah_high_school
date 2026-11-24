import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_department_analytics.dart';

void main() {
  final sales = <Map<String, dynamic>>[
    {
      'itemId': 'CN-01', 'department': 'canteen',
      'quantity': 2, 'totalMinor': 30000,
      'soldAt': DateTime(2026, 11, 23),
    },
    {
      'itemId': 'CN-01', 'department': 'canteen',
      'quantity': 1, 'totalMinor': 15000,
      'soldAt': DateTime(2026, 10, 30),
    },
    {
      'itemId': 'ST-01', 'department': 'stationery',
      'quantity': 3, 'totalMinor': 60000,
      'soldAt': DateTime(2026, 11, 22),
    },
  ];
  final items = <Map<String, dynamic>>[
    {
      'id': 'CN-01', 'department': 'canteen', 'active': true,
      'archived': false, 'stockQty': 25,
    },
    {
      'id': 'ST-01', 'department': 'stationery', 'active': true,
      'archived': false, 'stockQty': 10,
    },
  ];
  final purchases = <Map<String, dynamic>>[
    {
      'itemId': 'CN-01', 'totalCostMinor': 100000,
      'purchasedAt': DateTime(2026, 11, 20), 'source': 'opening',
    },
    {
      'itemId': 'CN-01', 'totalCostMinor': 40000,
      'purchasedAt': DateTime(2026, 10, 15), 'source': 'receipt',
    },
    {
      'itemId': 'ST-01', 'totalCostMinor': 300000,
      'purchasedAt': DateTime(2026, 11, 5), 'source': 'opening',
    },
  ];
  test('monthly canteen total purchases, units, profit and trend are separate', () {
    final data = calculateDepartmentInventoryAnalytics(
      department: 'canteen', period: InventoryReportPeriod.month,
      year: 2026, month: 11, items: items, sales: sales,
      purchases: purchases, currentCostsMinor: {'CN-01': 10000},
    );
    expect(data.stockUnits, 25);
    expect(data.soldUnits, 2);
    expect(data.salesMinor, 30000);
    expect(data.purchaseMinor, 100000);
    expect(data.estimatedProfitMinor, 10000);
    expect(data.completeCostCoverage, isTrue);
    expect(data.trend.length, 30);
    expect(data.trend[22].salesMinor, 30000);
    expect(data.trend[19].purchasesMinor, 100000);
  });

  test('yearly and all-time range aggregate full transactions', () {
    final yearly = calculateDepartmentInventoryAnalytics(
      department: 'canteen', period: InventoryReportPeriod.year,
      year: 2026, month: 11, items: items, sales: sales,
      purchases: purchases, currentCostsMinor: {'CN-01': 10000},
    );
    expect(yearly.soldUnits, 3);
    expect(yearly.salesMinor, 45000);
    expect(yearly.purchaseMinor, 140000);
    expect(yearly.estimatedProfitMinor, 15000);
    expect(yearly.trend.length, 12);
    final all = calculateDepartmentInventoryAnalytics(
      department: 'canteen', period: InventoryReportPeriod.all,
      year: 2026, month: 11, items: items, sales: sales,
      purchases: purchases, currentCostsMinor: {'CN-01': 10000},
    );
    expect(all.trend.length, 2);
    expect(all.salesMinor, 45000);
  });

  test('stationery does not contain canteen sales, stock or expenses', () {
    final stationery = calculateDepartmentInventoryAnalytics(
      department: 'stationery', period: InventoryReportPeriod.month,
      year: 2026, month: 11, items: items, sales: sales,
      purchases: purchases, currentCostsMinor: {'ST-01': 14000},
    );
    expect(stationery.stockUnits, 10);
    expect(stationery.soldUnits, 3);
    expect(stationery.salesMinor, 60000);
    expect(stationery.purchaseMinor, 300000);
    expect(stationery.estimatedProfitMinor, 18000);
  });

  test('missing confidential cost never creates a fake profit total', () {
    final data = calculateDepartmentInventoryAnalytics(
      department: 'stationery', period: InventoryReportPeriod.month,
      year: 2026, month: 11, items: items, sales: sales,
      purchases: purchases, currentCostsMinor: {},
    );
    expect(data.completeCostCoverage, isFalse);
    expect(data.uncostedUnits, 3);
  });
}
