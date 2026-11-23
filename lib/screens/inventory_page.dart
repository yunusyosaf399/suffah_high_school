import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/inventory_repository.dart';
import '../data/inventory_checkout_service.dart';
import 'inventory_checkout_page.dart';
import '../data/inventory_catalog.dart';
import '../data/inventory_product_service.dart';
import 'inventory_product_form.dart';
import '../data/school_errors.dart';

/// Sales and stock are intentionally separate from the school fee/salary ledger.
class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.role,
    this.itemsStream,
    this.salesStream,
    this.purchasesStream,
    this.repository,
  });

  final String role;
  final Stream<List<InventoryItem>>? itemsStream;
  final Stream<List<Map<String, dynamic>>>? salesStream;
  final Stream<List<Map<String, dynamic>>>? purchasesStream;
  final InventoryRepository? repository;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final InventoryRepository _repo =
      widget.repository ?? InventoryRepository();
  late final Stream<List<InventoryItem>> _items =
      widget.itemsStream ?? _repo.watchItems();
  String _department = 'all';
  bool _showArchived = false;
  final Map<String, int> _cart = {};
  String _salesSearch = '';
  late final InventoryCheckoutService _checkout = InventoryCheckoutService();
  late final InventoryProductService _products = InventoryProductService();
  // A single live Firestore listener feeds both tabs. Cached values ensure
  // the off-screen Stock view is populated even when the database is empty.
  List<InventoryItem>? _currentItems;
  Object? _itemsError;
  late final StreamSubscription<List<InventoryItem>> _itemsSubscription;

  @override
  void initState() {
    super.initState();
    _itemsSubscription = _items.listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _currentItems = items;
          _itemsError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _itemsError = error);
      },
    );
  }

  @override
  void dispose() {
    _itemsSubscription.cancel();
    super.dispose();
  }

  bool get _canManage =>
      widget.role == 'owner' || widget.role == 'inventory_manager';
  bool get _canAccess => _canManage || widget.role == 'canteen_seller';

  int get _cartUnits => _cart.values.fold(0, (sum, qty) => sum + qty);

  void _addToCart(InventoryItem item) {
    if (!item.canSell) return;
    if (!_cart.containsKey(item.id) && _cart.length >= 6) {
      _notice('One checkout supports up to six different products.');
      return;
    }
    final next = (_cart[item.id] ?? 0) + 1;
    if (next > item.stockQty || next > 100) {
      _notice('Quantity cannot exceed available stock or 100 units.');
      return;
    }
    setState(() => _cart[item.id] = next);
    _notice('${item.name} added to cart. $_cartUnits units in cart.');
  }

  Future<void> _openCart() async {
    if (_cart.isEmpty) {
      _notice('Add at least one item to the cart.');
      return;
    }
    final items = _currentItems ?? const <InventoryItem>[];
    final orderId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InventoryCheckoutPage(
          items: items, cart: _cart,
        ),
      ),
    );
    if (orderId != null && mounted) {
      setState(() => _cart.clear());
      _notice('Checkout recorded. Receipt ${orderId.substring(0, 8).toUpperCase()}.');
    }
  }

  Future<void> _syncStudents() async {
    try {
      final count = await _checkout.syncStudentDirectory();
      _notice('Canteen student directory updated: $count school records.');
    } catch (error) {
      _notice(_error(error));
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _error(Object e) => schoolErrorMessage(e);
  String _date(dynamic value) {
    if (value is! Timestamp) return 'Pending timestamp';
    final date = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Scaffold(body: Center(
        child: Text('This account cannot access the canteen inventory.')));
    }
    final sections = _canManage
        ? const ['Sell', 'Stock', 'Purchases', 'Sales', 'Borrowed']
        : const ['Sell', 'Stock', 'My sales', 'Borrowed'];
    return DefaultTabController(
      length: sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Canteen & Stationery',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            IconButton(
              key: const Key('inventory_open_cart_action'),
              tooltip: 'Cart ($_cartUnits units)',
              onPressed: _openCart,
              icon: Badge(
                label: Text('$_cartUnits'),
                isLabelVisible: _cartUnits > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
            if (_canManage)
              IconButton(
                key: const Key('inventory_add_product_action'),
                tooltip: 'Add product',
                onPressed: () => _editItem(),
                icon: const Icon(Icons.add_box_outlined),
              ),
            if (widget.role == 'canteen_seller' || widget.role == 'inventory_manager')
              IconButton(
                tooltip: 'Sign out',
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_outlined),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final name in sections) Tab(text: name)],
          ),
        ),
        body: SafeArea(
          child: TabBarView(children: [
            _catalog(selling: true),
            _catalog(selling: false),
            if (_canManage) _purchaseHistory(),
            _salesHistory(),
            _salesHistory(onlyBorrowed: true),
          ]),
        ),
      ),
    );
  }

  Widget _filterChips() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final entry in const [
          ('all', 'All items'), ('canteen', 'Canteen'),
          ('stationery', 'Stationery')])
          ChoiceChip(
            label: Text(entry.$2),
            selected: _department == entry.$1,
            onSelected: (_) => setState(() => _department = entry.$1),
          ),
      ],
    ),
  );

  Widget _catalog({required bool selling}) {
        final all = _currentItems ?? const <InventoryItem>[];
        final waitingForItems = _currentItems == null && _itemsError == null;
        final visible = all.where((item) => !item.archived).toList();
        final filtered = all.where((item) =>
          (_department == 'all' || item.department == _department) &&
          (_canManage && !selling && _showArchived
              ? item.archived : !item.archived)).toList();
        final available = visible.where((item) => item.canSell).length;
        final low = visible.where((item) => item.isLowStock).length;
        return ListView(
          key: Key(selling ? 'inventory_sell_list' : 'inventory_stock_list'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            Row(children: [
              Expanded(child: Text(selling ? 'Record a sale' : 'Stock catalogue',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              if (selling)
                FilledButton.icon(
                  key: const Key('inventory_open_cart'),
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                  label: Text('Cart ($_cartUnits)'),
                )
              else if (_canManage)
                FilledButton.icon(
                  onPressed: () => _editItem(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add product'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(selling
                ? 'Add products to your cart, select a student or another customer, then record paid or borrowed items. Stock is reduced at checkout.'
                : _canManage
                  ? 'Only authorized managers can edit prices, receive stock or record adjustments.'
                  : 'View prices and quantities. Stock and prices are read-only.',
              style: TextStyle(fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(avatar: const Icon(Icons.inventory_2_outlined, size: 17),
                label: Text('${visible.length} products')),
              Chip(avatar: const Icon(Icons.check_circle_outline, size: 17),
                label: Text('$available available')),
              Chip(avatar: const Icon(Icons.warning_amber_outlined, size: 17),
                label: Text('$low low stock')),
            ]),
            const SizedBox(height: 12),
            _filterChips(),
            if (selling && widget.role == 'owner')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('inventory_sync_student_directory'),
                  onPressed: _syncStudents,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync students for checkout'),
                ),
              ),
            if (!selling && _canManage)
              SwitchListTile.adaptive(
                key: const Key('inventory_show_deleted'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show deleted products'),
                subtitle: const Text('Deleted items are hidden from sales; transaction history is kept.'),
                value: _showArchived,
                onChanged: (value) => setState(() => _showArchived = value),
              ),
            if (_itemsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(_error(_itemsError!),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              )
            else if (waitingForItems)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(selling ? 'No products available to sell yet.'
                      : _showArchived ? 'No deleted products.'
                      : 'No stock items have been added yet.',
                      textAlign: TextAlign.center),
                    if (!selling && _canManage && !_showArchived) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _editItem(),
                        icon: const Icon(Icons.add),
                        label: const Text('Create first product'),
                      ),
                    ],
                  ],
                ),
              )
            else
              for (final item in filtered)
                Card(
                  margin: const EdgeInsets.only(bottom: 9),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text('${item.id} • ${inventoryDepartments[item.department] ?? item.department}',
                                  style: const TextStyle(fontSize: 11)),
                                const SizedBox(height: 3),
                                Text(
                                  '${inventoryCategoryLabel(item.department, item.category)}'
                                  ' / ${inventorySubcategoryLabel(item.department, item.category, item.subcategory)}'
                                  '${item.customType.isNotEmpty ? ' • ${item.customType}' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                if (item.classLevel.isNotEmpty ||
                                    item.bookSeries.isNotEmpty)
                                  Text('${item.classLevel}'
                                    '${item.bookSeries.isNotEmpty ? ' • ${item.bookSeries}' : ''}',
                                    style: const TextStyle(fontSize: 11)),

                              ],
                            )),
                            const SizedBox(width: 8),
                            Text(inventoryRupees(item.priceMinor),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 15, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('In stock: ${item.stockQty} ${item.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w600,
                                fontSize: 12)),
                            if (item.isLowStock)
                              const Text('LOW STOCK', style: TextStyle(
                                fontSize: 11, color: Colors.deepOrange,
                                fontWeight: FontWeight.w800)),
                            if (!item.active)
                              const Text('INACTIVE', style: TextStyle(
                                fontSize: 11, color: Colors.redAccent)),
                          ]),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item.description,
                            style: const TextStyle(fontSize: 11)),
                        ],
                        const SizedBox(height: 10),
                        if (selling)
                          Align(alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: Key('inventory_add_to_cart_${item.id}'),
                              onPressed: item.canSell
                                  ? () => _addToCart(item) : null,
                              icon: const Icon(Icons.add_shopping_cart, size: 18),
                              label: const Text('Add to cart'),
                            ))
                        else if (_canManage)
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            if (item.archived)
                              OutlinedButton.icon(
                                key: const Key('inventory_restore_product'),
                                onPressed: () => _restoreItem(item),
                                icon: const Icon(Icons.restore, size: 16),
                                label: const Text('Restore'),
                              )
                            else ...[
                              OutlinedButton.icon(
                                onPressed: () => _editItem(item),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Edit'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _receive(item),
                                icon: const Icon(Icons.add_box_outlined, size: 16),
                                label: const Text('Receive stock'),
                              ),
                              TextButton.icon(
                                onPressed: () => _adjust(item),
                                icon: const Icon(Icons.tune, size: 16),
                                label: const Text('Adjust'),
                              ),
                              TextButton.icon(
                                key: const Key('inventory_delete_product'),
                                onPressed: () => _deleteItem(item),
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Delete'),
                              ),
                            ],
                          ]),
                      ],
                    ),
                  ),
                ),
          ],
        );
  }

  Future<void> _editItem([InventoryItem? item]) async {
    if (!_canManage) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InventoryProductForm(item: item)),
    );
    if (saved == true) {
      _notice(item == null
          ? 'Product created with its opening stock quantity.'
          : 'Product and stock details saved.');
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    if (!_canManage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${item.name}" from stock and sales? '
          'Past purchases and sales will be kept for audit. You can '
          'restore this product later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete product'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _products.archive(item);
      _notice('Product deleted from active inventory. History is preserved.');
    } catch (error) {
      _notice(_error(error));
    }
  }

  Future<void> _restoreItem(InventoryItem item) async {
    if (!_canManage) return;
    try {
      await _products.restore(item);
      _notice('Product restored as inactive. Edit it to enable selling.');
    } catch (error) {
      _notice(_error(error));
    }
  }

  Future<void> _receive(InventoryItem item) async {
    if (!_canManage) return;
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final supplier = TextEditingController();
    final invoice = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog<void>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          scrollable: true,
          title: Text('Receive stock — ${item.name}'),
          content: SizedBox(width: 390,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Current stock: ${item.stockQty} ${item.unit}'),
              const SizedBox(height: 12),
              TextField(controller: quantity, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity purchased *')),
              const SizedBox(height: 10),
              TextField(controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Unit cost (PKR) *')),
              const SizedBox(height: 10),
              TextField(controller: supplier, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Supplier name *')),
              const SizedBox(height: 10),
              TextField(controller: invoice,
                decoration: const InputDecoration(labelText: 'Invoice number (optional)')),
              const SizedBox(height: 8),
              const Text('Purchase date and time are recorded automatically. Supplier costs are not visible to sellers.',
                style: TextStyle(fontSize: 11)),
              if (error != null) Text(error!, style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            FilledButton(onPressed: busy ? null : () async {
              update(() { busy = true; error = null; });
              try {
                final q = int.tryParse(quantity.text.trim());
                if (q == null) throw const FormatException('Enter a valid quantity.');
                await _repo.receiveStock(
                  sku: item.id, quantity: q, unitCostMinor: inventoryMoneyMinor(cost.text),
                  supplier: supplier.text, invoice: invoice.text,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _notice('Purchase received and stock updated.');
              } catch (e) {
                if (dialogContext.mounted) {
                  update(() { busy = false; error = _error(e); });
                }
              }
            }, child: Text(busy ? 'Recording…' : 'Record purchase')),
          ],
        ),
      ),
    );
    for (final field in [quantity, cost, supplier, invoice]) {
      field.dispose();
    }
  }

  Future<void> _adjust(InventoryItem item) async {
    if (!_canManage) return;
    final change = TextEditingController();
    final notes = TextEditingController();
    String reason = 'correction';
    String? error;
    bool busy = false;
    await showDialog<void>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          scrollable: true, title: Text('Stock adjustment — ${item.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current quantity: ${item.stockQty} ${item.unit}'),
            const SizedBox(height: 12),
            TextField(controller: change,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Change (+ or - quantity) *',
                helperText: 'Example: -2 for damaged goods')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: reason, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: const [
                DropdownMenuItem(value: 'correction', child: Text('Stock correction')),
                DropdownMenuItem(value: 'damage', child: Text('Damaged')),
                DropdownMenuItem(value: 'expired', child: Text('Expired')),
                DropdownMenuItem(value: 'wastage', child: Text('Wastage')),
                DropdownMenuItem(value: 'return', child: Text('Returned')),
              ],
              onChanged: busy ? null : (value) {
                if (value != null) update(() => reason = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: notes, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes / explanation')),
            if (error != null) Text(error!, style:
              TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            FilledButton(onPressed: busy ? null : () async {
              update(() { busy = true; error = null; });
              try {
                final qty = int.tryParse(change.text.trim());
                if (qty == null) throw const FormatException('Enter a signed quantity.');
                await _repo.adjustStock(
                  sku: item.id, delta: qty, reason: reason, notes: notes.text);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _notice('Stock adjustment recorded.');
              } catch (e) {
                if (dialogContext.mounted) {
                  update(() { busy = false; error = _error(e); });
                }
              }
            }, child: Text(busy ? 'Saving…' : 'Save adjustment')),
          ],
        ),
      ),
    );
    change.dispose();
    notes.dispose();
  }

  Widget _salesHistory({bool onlyBorrowed = false}) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.salesStream ?? _repo.watchSales(manager: _canManage),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(_error(snap.error!)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = inventoryGroupSales(snap.data!);
          final shown = orders.where((order) {
            if (onlyBorrowed && order.dueMinor <= 0) return false;
            final keyword = _salesSearch.toLowerCase().trim();
            return keyword.isEmpty ||
                order.customerName.toLowerCase().contains(keyword) ||
                order.customerId.toLowerCase().contains(keyword) ||
                order.orderId.toLowerCase().contains(keyword);
          }).toList();
          return ListView(
            key: Key(onlyBorrowed ? 'inventory_borrowed_orders' : 'inventory_sales_orders'),
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                onlyBorrowed ? 'Outstanding customer balances'
                    : 'Recent sales and receipts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('Orders are grouped by checkout. Paid and borrowed '
                  'amounts are tracked separately; repayments do not reduce '
                  'stock a second time.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                key: Key(onlyBorrowed
                    ? 'inventory_search_borrowed' : 'inventory_search_sales'),
                decoration: const InputDecoration(
                  labelText: 'Search customer, student registration or receipt',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _salesSearch = value),
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(onlyBorrowed
                        ? 'No outstanding borrowed sales.'
                        : 'No recorded sales yet.'),
                  ),
                ),
              for (final order in shown)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(order.customerName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15))),
                          Text(order.dueMinor == 0 ? 'PAID' : 'BORROWED',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: order.dueMinor == 0
                                  ? Colors.green : Colors.deepOrange,
                            )),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Receipt ${order.orderId.substring(0, order.orderId.length < 8 ? order.orderId.length : 8).toUpperCase()}'
                          ' • ${_date(order.soldAt)}'
                          '${order.customerId.isNotEmpty ? ' • ${order.customerId}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (order.customerClass.isNotEmpty)
                          Text('Class: ${order.customerClass}',
                            style: const TextStyle(fontSize: 11)),
                        if (order.customerPhone.isNotEmpty)
                          Text('Contact: ${order.customerPhone}',
                            style: const TextStyle(fontSize: 11)),
                        const Divider(height: 20),
                        for (final line in order.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Expanded(child: Text(
                                '${line.itemName} × ${line.quantity}',
                                style: const TextStyle(fontSize: 12),
                              )),
                              Text(inventoryRupees(line.totalMinor),
                                style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 12, runSpacing: 5, children: [
                          Text('Total: ${inventoryRupees(order.totalMinor)}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('Paid: ${inventoryRupees(order.paidMinor)}'),
                          Text('Due: ${inventoryRupees(order.dueMinor)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                        if (order.dueMinor > 0) ...[
                          const SizedBox(height: 12),
                          Align(alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: Key('inventory_collect_${order.orderId}'),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Collect payment'),
                              onPressed: () => _collectPayment(order),
                            )),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Future<void> _collectPayment(InventoryOrderSummary order) async {
    final amount = TextEditingController(
      text: (order.dueMinor / 100).toStringAsFixed(2),
    );
    String method = 'Cash';
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          scrollable: true,
          title: const Text('Collect borrowed payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.customerName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Outstanding: ${inventoryRupees(order.dueMinor)}'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('inventory_collect_amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment amount (PKR)',
                  border: OutlineInputBorder(),
                  helperText: 'Full or partial payment',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
                items: [for (final m in inventoryPaymentMethods)
                  DropdownMenuItem(value: m, child: Text(m))],
                onChanged: busy ? null : (v) {
                  if (v != null) update(() => method = v);
                },
              ),
              if (error != null)
                Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(error!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('inventory_confirm_collection'),
              onPressed: busy ? null : () async {
                update(() { busy = true; error = null; });
                try {
                  final minor = inventoryMoneyMinor(amount.text);
                  await _checkout.collectPayment(
                    order: order, amountMinor: minor, method: method);
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _notice('Payment collected and balance updated.');
                } catch (e) {
                  if (dialogContext.mounted) {
                    update(() { busy = false; error = _error(e); });
                  }
                }
              },
              child: Text(busy ? 'Collecting…' : 'Confirm payment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
  }

  Widget _purchaseHistory() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: widget.purchasesStream ?? _repo.watchPurchases(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text(_error(snap.error!)));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final purchases = snap.data!;
      if (purchases.isEmpty) {
        return const Center(child: Text('No stock purchases recorded yet.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(14), itemCount: purchases.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Recent purchases • last 60 records',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));
          final purchase = purchases[index - 1];
          final cost = (purchase['totalCostMinor'] as num?)?.toInt() ?? 0;
          return Card(child: ListTile(
            title: Text((purchase['itemName'] ?? 'Item').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${purchase['quantity'] ?? 0} units • ${purchase['supplier'] ?? 'Unknown supplier'}\n'
              '${_date(purchase['purchasedAt'])} • ${purchase['invoice'] ?? ''}'),
            isThreeLine: true,
            trailing: Text(inventoryRupees(cost),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          ));
        },
      );
    },
  );
}
