import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_repository.dart';
import 'package:suffah_high_school/screens/inventory_page.dart';

const chips = InventoryItem(
  id: 'CHIPS001', name: 'Potato chips', department: 'canteen',
  unit: 'packet', priceMinor: 8500, stockQty: 24, reorderPoint: 5,
  active: true, description: 'Crispy snack',
);

Widget inventoryHost(String role) => MaterialApp(
  home: InventoryPage(
    role: role,
    itemsStream: Stream.value(const [chips]),
    salesStream: Stream.value(const <Map<String, dynamic>>[]),
    purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
  ),
);

void main() {
  testWidgets('seller sees sale and read-only stock without manager controls',
      (tester) async {
    await tester.pumpWidget(inventoryHost('canteen_seller'));
    await tester.pumpAndSettle();
    expect(find.text('Canteen & Stationery'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('My sales'), findsOneWidget);
    expect(find.text('Purchases'), findsNothing);
    expect(find.text('Sell item'), findsOneWidget);
    expect(find.text('Rs 85.00'), findsOneWidget);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Add product'), findsNothing);
    expect(find.byKey(const Key('inventory_add_product_action')), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Receive stock'), findsNothing);
    expect(find.text('Adjust'), findsNothing);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sale dialog displays locked price and quantity-only entry',
      (tester) async {
    await tester.pumpWidget(inventoryHost('canteen_seller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell item'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm sale'), findsOneWidget);
    expect(find.text('Unit price: Rs 85.00'), findsOneWidget);
    expect(find.byKey(const Key('inventory_sale_quantity')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Selling price (PKR) *'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager can access stock purchase and adjustment controls',
      (tester) async {
    await tester.pumpWidget(inventoryHost('inventory_manager'));
    await tester.pumpAndSettle();
    expect(find.text('Purchases'), findsOneWidget);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Add product'), findsOneWidget);
    expect(find.byKey(const Key('inventory_add_product_action')), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Receive stock'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner always has Add product with zero stock and working tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InventoryPage(
        role: 'owner',
        itemsStream: Stream.value(const <InventoryItem>[]),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
        purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No products available to sell yet.'), findsOneWidget);
    expect(find.byKey(const Key('inventory_add_product_action')), findsOneWidget);

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock catalogue'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(find.text('No stock items have been added yet.'), findsOneWidget);
    expect(find.text('Create first product'), findsOneWidget);

    await tester.tap(find.text('Create first product'));
    await tester.pumpAndSettle();
    expect(find.text('Add product'), findsOneWidget);
    expect(find.byKey(const Key('inventory_product_name')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory_stock_quantity')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('inventory_stock_quantity')), findsOneWidget);
    expect(find.textContaining('generated automatically'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Create first product'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller never receives product-creation actions with empty stock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InventoryPage(
        role: 'canteen_seller',
        itemsStream: Stream.value(const <InventoryItem>[]),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('No stock items have been added yet.'), findsOneWidget);
    expect(find.text('Create first product'), findsNothing);
    expect(find.text('Add product'), findsNothing);
    expect(find.byKey(const Key('inventory_add_product_action')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unauthorized roles never see inventory content',
      (tester) async {
    await tester.pumpWidget(inventoryHost('teacher'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot access the canteen inventory'),
      findsOneWidget);
    expect(find.text('Sell item'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
