import 'package:cloud_firestore/cloud_firestore.dart';

/// Owner/manager-only inventory profitability report. Profit is a gross
/// margin estimate based on the CURRENT confidential purchase cost; changing
/// acquisition prices later can change historical estimates. Never persist
/// purchase cost on customer-visible item or sale documents.
enum InventoryReportPeriod { month, year, all }

class InventoryTrendPoint {
  const InventoryTrendPoint({
    required this.key,
    required this.label,
    required this.salesMinor,
    required this.purchasesMinor,
    required this.estimatedProfitMinor,
  });
  final String key;
  final String label;
  final int salesMinor;
  final int purchasesMinor;
  final int estimatedProfitMinor;
}

class InventoryDepartmentAnalytics {
  const InventoryDepartmentAnalytics({
    required this.stockUnits,
    required this.soldUnits,
    required this.salesMinor,
    required this.purchaseMinor,
    required this.estimatedProfitMinor,
    required this.uncostedUnits,
    required this.trend,
    required this.limited,
  });
  final int stockUnits;
  final int soldUnits;
  final int salesMinor;
  final int purchaseMinor;
  final int estimatedProfitMinor;
  final int uncostedUnits;
  final List<InventoryTrendPoint> trend;
  final bool limited;
  bool get completeCostCoverage => uncostedUnits == 0;
}

DateTime? _reportDate(dynamic value) =>
    value is Timestamp ? value.toDate() : value is DateTime ? value : null;

String _dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

bool _within(DateTime date, InventoryReportPeriod period,
    int year, int month) {
  if (period == InventoryReportPeriod.all) return true;
  if (date.year != year) return false;
  return period == InventoryReportPeriod.year || date.month == month;
}

InventoryDepartmentAnalytics calculateDepartmentInventoryAnalytics({
  required String department,
  required InventoryReportPeriod period,
  required int year,
  required int month,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> sales,
  required List<Map<String, dynamic>> purchases,
  required Map<String, int> currentCostsMinor,
  bool limited = false,
}) {
  final stock = items.where((item) =>
      item['department'] == department &&
      item['active'] == true && item['archived'] != true)
    .fold<int>(0, (total, item) =>
        total + ((item['stockQty'] as num?)?.toInt() ?? 0));

  final filteredSales = sales.where((row) {
    final date = _reportDate(row['soldAt']);
    return row['department'] == department && date != null &&
        _within(date, period, year, month);
  }).toList();
  final itemIds = {
    for (final item in items)
      (item['id'] ?? item['sku'] ?? '').toString(): item['department'],
  };
  final filteredPurchases = purchases.where((row) {
    final date = _reportDate(row['purchasedAt'] ?? row['recordedAt']);
    return itemIds[(row['itemId'] ?? '').toString()] == department &&
        date != null && _within(date, period, year, month);
  }).toList();

  final salesByKey = <String, int>{};
  final purchasesByKey = <String, int>{};
  final profitByKey = <String, int>{};
  String keyFor(DateTime date) => period == InventoryReportPeriod.month
      ? _dayKey(date) : _monthKey(date);
  var soldUnits = 0;
  var salesTotal = 0;
  var purchaseTotal = 0;
  var estimatedProfit = 0;
  var uncostedUnits = 0;
  for (final row in filteredSales) {
    final date = _reportDate(row['soldAt'])!;
    final key = keyFor(date);
    final amount = (row['totalMinor'] as num?)?.toInt() ?? 0;
    final qty = (row['quantity'] as num?)?.toInt() ?? 0;
    final itemId = (row['itemId'] ?? '').toString();
    final unitCost = currentCostsMinor[itemId];
    soldUnits += qty;
    salesTotal += amount;
    salesByKey[key] = (salesByKey[key] ?? 0) + amount;
    if (unitCost == null || unitCost <= 0) {
      uncostedUnits += qty;
    } else {
      final margin = amount - unitCost * qty;
      estimatedProfit += margin;
      profitByKey[key] = (profitByKey[key] ?? 0) + margin;
    }
  }
  for (final row in filteredPurchases) {
    final date = _reportDate(row['purchasedAt'] ?? row['recordedAt'])!;
    final key = keyFor(date);
    final amount = (row['totalCostMinor'] as num?)?.toInt() ?? 0;
    purchaseTotal += amount;
    purchasesByKey[key] = (purchasesByKey[key] ?? 0) + amount;
  }

  final dates = <DateTime>[];
  if (period == InventoryReportPeriod.month) {
    final days = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= days; day++) {
      dates.add(DateTime(year, month, day));
    }
  } else if (period == InventoryReportPeriod.year) {
    for (var m = 1; m <= 12; m++) {
      dates.add(DateTime(year, m));
    }
  } else {
    final allDates = [
      for (final row in filteredSales)
        if (_reportDate(row['soldAt']) != null) _reportDate(row['soldAt'])!,
      for (final row in filteredPurchases)
        if (_reportDate(row['purchasedAt'] ?? row['recordedAt']) != null)
          _reportDate(row['purchasedAt'] ?? row['recordedAt'])!,
    ];
    if (allDates.isEmpty) {
      dates.add(DateTime(year, month, 1));
    } else {
      allDates.sort();
      final first = allDates.first;
      final last = allDates.last;
      for (var date = DateTime(first.year, first.month);
          !date.isAfter(DateTime(last.year, last.month));
          date = DateTime(date.year, date.month + 1)) {
        dates.add(date);
      }
    }
  }
  final trends = [
    for (final date in dates)
      InventoryTrendPoint(
        key: keyFor(date),
        label: period == InventoryReportPeriod.month
            ? date.day.toString()
            : '${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}',
        salesMinor: salesByKey[keyFor(date)] ?? 0,
        purchasesMinor: purchasesByKey[keyFor(date)] ?? 0,
        estimatedProfitMinor: profitByKey[keyFor(date)] ?? 0,
      ),
  ];

  return InventoryDepartmentAnalytics(
    stockUnits: stock,
    soldUnits: soldUnits,
    salesMinor: salesTotal,
    purchaseMinor: purchaseTotal,
    estimatedProfitMinor: estimatedProfit,
    uncostedUnits: uncostedUnits,
    trend: trends,
    limited: limited,
  );
}

class InventoryDepartmentAnalyticsRepository {
  InventoryDepartmentAnalyticsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  static const maxRecords = 2500;

  Future<InventoryDepartmentAnalytics> load({
    required String department,
    required InventoryReportPeriod period,
    required int year,
    required int month,
  }) async {
    if (department != 'canteen' && department != 'stationery') {
      throw ArgumentError('Choose a valid inventory department.');
    }
    final start = period == InventoryReportPeriod.all
        ? null : Timestamp.fromDate(DateTime(
            year, period == InventoryReportPeriod.month ? month : 1));

    // Firestore permissions are the security boundary: inventory_costs
    // and inventory_purchases reject seller reads at the server.
    final itemsFuture = _db.collection('inventory_items').limit(500)
        .get(const GetOptions(source: Source.server));
    final costsFuture = _db.collection('inventory_costs').limit(500)
        .get(const GetOptions(source: Source.server));
    final salesBase = _db.collection('inventory_sales');
    final purchasesBase = _db.collection('inventory_purchases');
    final salesFuture = (start == null ? salesBase
        : salesBase.where('soldAt', isGreaterThanOrEqualTo: start))
        .orderBy('soldAt', descending: true).limit(maxRecords)
        .get(const GetOptions(source: Source.server));
    final purchasesFuture = (start == null ? purchasesBase
        : purchasesBase.where('purchasedAt', isGreaterThanOrEqualTo: start))
        .orderBy('purchasedAt', descending: true).limit(maxRecords)
        .get(const GetOptions(source: Source.server));
    final itemsResult = await itemsFuture;
    final costsResult = await costsFuture;
    final salesResult = await salesFuture;
    final purchasesResult = await purchasesFuture;
    return calculateDepartmentInventoryAnalytics(
      department: department,
      period: period, year: year, month: month,
      items: [
        for (final doc in itemsResult.docs) {...doc.data(), 'id': doc.id},
      ],
      sales: [for (final doc in salesResult.docs) doc.data()],
      purchases: [for (final doc in purchasesResult.docs) doc.data()],
      currentCostsMinor: {
        for (final doc in costsResult.docs)
          if (doc.data()['unitCostMinor'] is num)
            doc.id: (doc.data()['unitCostMinor'] as num).toInt(),
      },
      limited: itemsResult.docs.length >= 500 ||
          costsResult.docs.length >= 500 ||
          salesResult.docs.length >= maxRecords ||
          purchasesResult.docs.length >= maxRecords,
    );
  }
}
