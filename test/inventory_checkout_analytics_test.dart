import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_checkout_service.dart';
import 'package:suffah_high_school/data/inventory_sales_analytics.dart';

void main() {
  test('multiple sale lines group into one customer checkout receipt', () {
    final date = Timestamp.fromDate(DateTime(2026, 11, 23, 9));
    final orders = inventoryGroupSales([
      {
        'id': 'line-a', 'orderId': 'cart-001',
        'itemName': 'Pen', 'customerName': 'Aisha Khan',
        'customerType': 'student', 'customerId': 'ST-2026-0005',
        'quantity': 3, 'totalMinor': 9000, 'paidMinor': 0,
        'sellerUid': 'seller', 'soldAt': date,
      },
      {
        'id': 'line-b', 'orderId': 'cart-001',
        'itemName': 'Notebook', 'customerName': 'Aisha Khan',
        'customerType': 'student', 'customerId': 'ST-2026-0005',
        'quantity': 2, 'totalMinor': 14000, 'paidMinor': 4000,
        'sellerUid': 'seller', 'soldAt': date,
      },
    ]);
    expect(orders, hasLength(1));
    expect(orders.single.lines, hasLength(2));
    expect(orders.single.totalMinor, 23000);
    expect(orders.single.paidMinor, 4000);
    expect(orders.single.dueMinor, 19000);
    expect(orders.single.quantity, 5);
    expect(orders.single.customerId, 'ST-2026-0005');
  });

  test('analytics recognize borrowed sales but only count received cash', () {
    final date = Timestamp.fromDate(DateTime(2026, 11, 5));
    final sales = [
      {
        'id': 'cash-one', 'orderId': 'order-cash',
        'itemName': 'Chips', 'department': 'canteen',
        'totalMinor': 10000, 'paidMinor': 10000,
        'paymentMethod': 'Cash', 'quantity': 2,
        'soldAt': date,
      },
      {
        'id': 'credit-one', 'orderId': 'order-credit',
        'itemName': 'Maths book', 'department': 'stationery',
        'totalMinor': 20000, 'paidMinor': 5000,
        'paymentMethod': 'Unpaid', 'quantity': 1,
        'soldAt': date,
      },
    ];
    final repayments = [
      {
        'amountMinor': 5000,
        'collectedAt': Timestamp.fromDate(DateTime(2026, 11, 15)),
      },
    ];
    final result = calculateInventoryAnalytics(
      sales: sales,
      repayments: repayments,
      now: DateTime(2026, 11, 23),
    );
    expect(result.salesMinor, 30000);
    expect(result.collectedMinor, 15000);
    expect(result.outstandingMinor, 15000);
    expect(result.orders, 2);
    expect(result.outstandingOrders, 1);
    expect(result.units, 3);
    expect(result.canteenMinor, 10000);
    expect(result.stationeryMinor, 20000);
    expect(result.averageOrderMinor, 15000);
    expect(result.topItems.first.key, 'Maths book');
    expect(result.months.last.month, '2026-11');
    expect(result.months.last.collectedMinor, 15000);
  });

  test('legacy sales count as already paid without double-counting credit', () {
    final result = calculateInventoryAnalytics(
      sales: [{
        'id': 'legacy-sale',
        'itemName': 'Notebook', 'department': 'stationery',
        'totalMinor': 25000, 'paymentMethod': 'Cash',
        'quantity': 5,
        'soldAt': Timestamp.fromDate(DateTime(2026, 11, 8)),
      }],
      repayments: const [],
      now: DateTime(2026, 11, 23),
    );
    expect(result.outstandingMinor, 0);
    expect(result.collectedMinor, 25000);
    expect(result.orders, 1);
  });

  test('order summaries sort newest first and track partial payments', () {
    final orders = inventoryGroupSales([
      {
        'id': 'old', 'orderId': 'old-order',
        'totalMinor': 1000, 'paidMinor': 1000,
        'soldAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      },
      {
        'id': 'new', 'orderId': 'new-order',
        'totalMinor': 12000, 'paidMinor': 3000,
        'soldAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
      },
    ]);
    expect(orders.first.orderId, 'new-order');
    expect(orders.first.dueMinor, 9000);
    expect(orders.last.isPaid, isNot(isNull)); // Receipt remains available.
  });
}
