import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_sales_analytics.dart';
import 'package:suffah_high_school/screens/inventory_sales_analytics_section.dart';

void main() {
  testWidgets('sales analytics shows collected cash separate from borrowed amounts',
      (tester) async {
    const data = InventorySalesAnalytics(
      salesMinor: 30000,
      collectedMinor: 15000,
      outstandingMinor: 15000,
      orders: 2,
      units: 3,
      canteenMinor: 10000,
      stationeryMinor: 20000,
      outstandingOrders: 1,
      months: [
        InventorySalesMonth(
          month: '2026-10',
          salesMinor: 0, collectedMinor: 0),
        InventorySalesMonth(
          month: '2026-11',
          salesMinor: 30000, collectedMinor: 15000),
      ],
      topItems: [MapEntry('Maths textbook', 20000)],
      limited: false,
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: InventorySalesAnalyticsSection(initialData: data),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Canteen & Stationery sales analytics'), findsOneWidget);
    expect(find.text('Sales value (6 mo)'), findsOneWidget);
    expect(find.text('Cash collected (6 mo)'), findsOneWidget);
    expect(find.text('Outstanding (available history)'), findsOneWidget);
    expect(find.text('Rs 300.00'), findsWidgets);
    expect(find.text('Rs 150.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
