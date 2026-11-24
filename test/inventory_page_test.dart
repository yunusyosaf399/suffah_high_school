import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_repository.dart';
import 'package:suffah_high_school/main.dart';
import 'package:suffah_high_school/screens/inventory_page.dart';

const chips = InventoryItem(
  id: 'CHIPS001', name: 'Potato chips', department: 'canteen',
  unit: 'packet', priceMinor: 8500, stockQty: 24, reorderPoint: 5,
  active: true, description: 'Crispy snack',
);

Widget inventoryHost(String role) => MaterialApp(
  theme: SchoolApp.buildTheme(),
  home: InventoryPage(
    role: role,
    itemsStream: Stream.value(const [chips]),
    salesStream: Stream.value(const <Map<String, dynamic>>[]),
    purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
  ),
);

void main() {
  test('production FilledButton has a FINITE minimum width', () {
    // Original Size.fromHeight(46) made width infinite. Our prior tests
    // used the default MaterialApp theme and missed the production crash.
    expect(const Size.fromHeight(46).width.isInfinite, isTrue);
    final minimum = SchoolApp.buildTheme()
        .filledButtonTheme.style!.minimumSize!
        .resolve(<WidgetState>{})!;
    expect(minimum.width.isFinite, isTrue);
    expect(minimum.width, greaterThan(0));
    expect(minimum.height, 46);
  });

  testWidgets('production theme lays out the actual Sell and Stock headers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(inventoryHost('inventory_manager'));
    await tester.pumpAndSettle();
    expect(find.text('Record a sale'), findsOneWidget);
    expect(find.text('Cart (0)'), findsOneWidget);
    expect(find.text('Potato chips'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock catalogue'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(find.text('Potato chips'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller sees sale and read-only stock without manager controls',
      (tester) async {
    await tester.pumpWidget(inventoryHost('canteen_seller'));
    await tester.pumpAndSettle();
    expect(find.text('Canteen & Stationery'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('My sales'), findsOneWidget);
    expect(find.text('Purchases'), findsNothing);
    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.text('Borrowed'), findsOneWidget);
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

  testWidgets('seller adds product to cart and opens customer checkout',
      (tester) async {
    await tester.pumpWidget(inventoryHost('canteen_seller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory_open_cart_action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory_open_cart_action')));
    await tester.pumpAndSettle();
    expect(find.text('Canteen checkout'), findsOneWidget);
    expect(find.text('Shopping cart'), findsOneWidget);
    expect(find.text('Customer details'), findsOneWidget);
    expect(find.text('Rs 85.00'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Selling price (PKR) *'), findsNothing);
    await tester.pageBack();
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
  theme: SchoolApp.buildTheme(),
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
  theme: SchoolApp.buildTheme(),
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

  testWidgets('Sell and Stock remain visible with a long product catalogue '
      'after repeatedly changing tabs', (tester) async {
    final items = List.generate(120, (index) => InventoryItem(
      id: 'SKU${index.toString().padLeft(5, '0')}',
      name: 'English Book Iqbal Series Part $index',
      department: 'stationery', category: 'books',
      subcategory: 'textbook', classLevel: 'Class 5',
      bookSeries: 'Iqbal Series', unit: 'piece',
      priceMinor: 15000, stockQty: 14, reorderPoint: 4,
      active: true, description: 'School course textbook',
    ));
    await tester.pumpWidget(MaterialApp(
  theme: SchoolApp.buildTheme(),
      home: InventoryPage(
        role: 'owner',
        itemsStream: Stream.value(items),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
        purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Record a sale'), findsOneWidget);
    expect(find.text('120 products'), findsOneWidget);
    expect(find.byKey(const PageStorageKey<String>('inventory_sell_list')),
      findsOneWidget);
    expect(find.text('English Book Iqbal Series Part 0'), findsOneWidget);

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock catalogue'), findsOneWidget);
    expect(find.byKey(const PageStorageKey<String>('inventory_stock_list')),
      findsOneWidget);
    expect(find.text('English Book Iqbal Series Part 0'), findsOneWidget);

    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    expect(find.text('Record a sale'), findsOneWidget);
    expect(find.text('120 products'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue error always shows header and Retry in both tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
  theme: SchoolApp.buildTheme(),
      home: InventoryPage(
        role: 'owner',
        itemsStream: Stream<List<InventoryItem>>.error(
          StateError('Inventory stream is temporarily unavailable')),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
        purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Record a sale'), findsOneWidget);
    expect(find.byKey(const Key('inventory_retry_products')), findsOneWidget);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock catalogue'), findsOneWidget);
    expect(find.byKey(const Key('inventory_retry_products')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Canteen has its own quick sale and filters stationery products',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const book = InventoryItem(
      id: 'BOOK001', name: 'English Workbook', department: 'stationery',
      unit: 'piece', priceMinor: 50000, stockQty: 16,
      reorderPoint: 5, active: true);
    await tester.pumpWidget(MaterialApp(
      theme: SchoolApp.buildTheme(),
      home: InventoryPage(
        role: 'owner', department: 'canteen',
        itemsStream: Stream.value(const [chips, book]),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
        purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Canteen Sales'), findsOneWidget);
    expect(find.text('Potato chips'), findsOneWidget);
    expect(find.text('English Workbook'), findsNothing);
    expect(find.text('Borrowed'), findsNothing);
    expect(find.byKey(const Key('inventory_sync_student_directory')),
        findsNothing);
    expect(find.byKey(const Key('canteen_sell_now_CHIPS001')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('canteen_sell_now_CHIPS001')));
    await tester.pumpAndSettle();
    expect(find.text('Canteen quick sale'), findsOneWidget);
    expect(find.text('Who is buying?'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Select school student'), findsNothing);
    expect(find.text('Customer details'), findsNothing);
    expect(find.text('Borrowed'), findsNothing);
    expect(find.byKey(const Key('canteen_complete_quick_sale')),
      findsOneWidget);
    await tester.tap(find.text('Teacher'));
    await tester.pumpAndSettle();
    final teacherChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Teacher'));
    expect(teacherChip.selected, true);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory_open_cart_action')));
    await tester.pumpAndSettle();
    expect(find.text('Canteen quick sale'), findsOneWidget);
    expect(find.text('Cart • 1 units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stationery retains named student checkout and borrowed tab',
      (tester) async {
    const book = InventoryItem(
      id: 'BOOK001', name: 'English Workbook', department: 'stationery',
      unit: 'piece', priceMinor: 50000, stockQty: 16,
      reorderPoint: 5, active: true);
    await tester.pumpWidget(MaterialApp(
      theme: SchoolApp.buildTheme(),
      home: InventoryPage(
        role: 'owner', department: 'stationery',
        itemsStream: Stream.value(const [chips, book]),
        salesStream: Stream.value(const <Map<String, dynamic>>[]),
        purchasesStream: Stream.value(const <Map<String, dynamic>>[]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Stationery & Books'), findsOneWidget);
    expect(find.text('English Workbook'), findsOneWidget);
    expect(find.text('Potato chips'), findsNothing);
    expect(find.text('Borrowed'), findsOneWidget);
    expect(find.byKey(const Key('canteen_sell_now_BOOK001')), findsNothing);

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory_open_cart_action')));
    await tester.pumpAndSettle();
    expect(find.text('Canteen checkout'), findsOneWidget);
    expect(find.text('Customer details'), findsOneWidget);
    expect(find.byKey(const Key('inventory_select_student')), findsOneWidget);
    expect(find.text('Borrowed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unauthorized roles never see inventory content',
      (tester) async {
    await tester.pumpWidget(inventoryHost('teacher'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot access the canteen inventory'),
      findsOneWidget);
    expect(find.text('Add to cart'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
