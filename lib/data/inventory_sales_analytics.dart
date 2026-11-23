import 'package:cloud_firestore/cloud_firestore.dart';

/// Sales statistics use independent inventory cashflows, not school fee or
/// salary ledger entries. Cash collected later is counted on collection date.
class InventorySalesMonth {
  const InventorySalesMonth({
    required this.month,
    required this.salesMinor,
    required this.collectedMinor,
  });
  final String month;
  final int salesMinor;
  final int collectedMinor;
}

class InventorySalesAnalytics {
  const InventorySalesAnalytics({
    required this.salesMinor,
    required this.collectedMinor,
    required this.outstandingMinor,
    required this.orders,
    required this.units,
    required this.canteenMinor,
    required this.stationeryMinor,
    required this.outstandingOrders,
    required this.months,
    required this.topItems,
    required this.limited,
  });

  final int salesMinor;
  final int collectedMinor;
  final int outstandingMinor;
  final int orders;
  final int units;
  final int canteenMinor;
  final int stationeryMinor;
  final int outstandingOrders;
  final List<InventorySalesMonth> months;
  final List<MapEntry<String, int>> topItems;
  final bool limited;

  int get averageOrderMinor => orders == 0 ? 0 : salesMinor ~/ orders;
}

DateTime? _inventoryTime(dynamic value) =>
    value is Timestamp ? value.toDate() : null;

String _inventoryMonth(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}';

InventorySalesAnalytics calculateInventoryAnalytics({
  required List<Map<String, dynamic>> sales,
  required List<Map<String, dynamic>> repayments,
  DateTime? now,
  bool limited = false,
}) {
  final time = now ?? DateTime.now();
  final monthKeys = <String>[];
  for (var ago = 5; ago >= 0; ago--) {
    monthKeys.add(_inventoryMonth(DateTime(time.year, time.month - ago, 1)));
  }
  final monthlySales = {for (final key in monthKeys) key: 0};
  final monthlyCollections = {for (final key in monthKeys) key: 0};
  final ordersSet = <String>{};
  final outstandingOrders = <String>{};
  final top = <String, int>{};
  var salesMinor = 0;
  var collectedMinor = 0;
  var outstandingMinor = 0;
  var canteenMinor = 0;
  var stationeryMinor = 0;
  var units = 0;

  for (final sale in sales) {
    final gross = (sale['totalMinor'] as num?)?.toInt() ?? 0;
    final paid = (sale['paidMinor'] as num?)?.toInt() ?? gross;
    final due = gross - paid;
    final id = (sale['orderId'] as String?) ??
        (sale['saleId'] as String?) ?? (sale['id'] as String?) ?? '';
    outstandingMinor += due > 0 ? due : 0;
    if (due > 0 && id.isNotEmpty) outstandingOrders.add(id);

    final date = _inventoryTime(sale['soldAt']);
    final key = date == null ? '' : _inventoryMonth(date);
    if (!monthlySales.containsKey(key)) continue;
    ordersSet.add(id);
    salesMinor += gross;
    units += (sale['quantity'] as num?)?.toInt() ?? 0;
    monthlySales[key] = monthlySales[key]! + gross;
    final department = sale['department'];
    if (department == 'canteen') canteenMinor += gross;
    if (department == 'stationery') stationeryMinor += gross;
    final itemName = (sale['itemName'] as String?) ?? 'Other';
    top[itemName] = (top[itemName] ?? 0) + gross;

    // Initial paid receipts count when sold. Borrowed receipts are counted
    // only through their later immutable collection events below.
    if (sale['paymentMethod'] != 'Unpaid') {
      collectedMinor += gross;
      monthlyCollections[key] = monthlyCollections[key]! + gross;
    }
  }
  for (final payment in repayments) {
    final date = _inventoryTime(payment['collectedAt']);
    final key = date == null ? '' : _inventoryMonth(date);
    if (!monthlyCollections.containsKey(key)) continue;
    final amount = (payment['amountMinor'] as num?)?.toInt() ?? 0;
    collectedMinor += amount;
    monthlyCollections[key] = monthlyCollections[key]! + amount;
  }

  final sortedTop = top.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return InventorySalesAnalytics(
    salesMinor: salesMinor,
    collectedMinor: collectedMinor,
    outstandingMinor: outstandingMinor,
    outstandingOrders: outstandingOrders.length,
    orders: ordersSet.length,
    units: units,
    canteenMinor: canteenMinor,
    stationeryMinor: stationeryMinor,
    topItems: sortedTop.take(5).toList(),
    months: [
      for (final key in monthKeys)
        InventorySalesMonth(
          month: key,
          salesMinor: monthlySales[key]!,
          collectedMinor: monthlyCollections[key]!,
        ),
    ],
    limited: limited,
  );
}

class InventoryAnalyticsRepository {
  InventoryAnalyticsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<InventorySalesAnalytics> load() async {
    final results = await Future.wait([
      _db.collection('inventory_sales')
          .orderBy('soldAt', descending: true).limit(1500)
          .get(const GetOptions(source: Source.server)),
      _db.collection('inventory_payments')
          .orderBy('collectedAt', descending: true).limit(1500)
          .get(const GetOptions(source: Source.server)),
    ]);
    return calculateInventoryAnalytics(
      sales: results[0].docs.map((d) => {...d.data(), 'id': d.id}).toList(),
      repayments: results[1].docs.map((d) => {...d.data(), 'id': d.id}).toList(),
      limited: results[0].docs.length >= 1500 || results[1].docs.length >= 1500,
    );
  }
}
