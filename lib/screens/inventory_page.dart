import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/inventory_repository.dart';
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
        ? const ['Sell', 'Stock', 'Purchases', 'Sales']
        : const ['Sell', 'Stock', 'My sales'];
    return DefaultTabController(
      length: sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Canteen & Stationery',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
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
              if (!selling && _canManage)
                FilledButton.icon(
                  onPressed: () => _editItem(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add product'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(selling
                ? 'The selling price is fixed by the owner. Recording a sale automatically reduces stock.'
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
                              onPressed: item.canSell
                                  ? () => _sell(item) : null,
                              icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                              label: const Text('Sell item'),
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

  Future<void> _sell(InventoryItem item) async {
    final quantity = TextEditingController(text: '1');
    String method = 'Cash';
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          scrollable: true,
          title: const Text('Confirm sale'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Unit price: ${inventoryRupees(item.priceMinor)}'),
              Text('Available: ${item.stockQty} ${item.unit}'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('inventory_sale_quantity'),
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity sold *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [for (final m in inventoryPaymentMethods)
                  DropdownMenuItem(value: m, child: Text(m))],
                onChanged: busy ? null : (value) {
                  if (value != null) update(() => method = value);
                },
              ),
              const SizedBox(height: 8),
              Text('Seller cannot change the unit price. Final amount is calculated from current stock data.',
                style: TextStyle(fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color:
                  Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: busy ? null : () async {
                final count = int.tryParse(quantity.text.trim());
                if (count == null || count <= 0 || count > 100) {
                  update(() => error = 'Enter a quantity between 1 and 100.');
                  return;
                }
                update(() { busy = true; error = null; });
                try {
                  await _repo.recordSale(
                    sku: item.id, quantity: count, paymentMethod: method);
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _notice('Sale recorded. Stock updated automatically.');
                } catch (e) {
                  if (dialogContext.mounted) {
                    update(() { busy = false; error = _error(e); });
                  }
                }
              },
              child: Text(busy ? 'Recording…' : 'Record sale'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
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

  Widget _salesHistory() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: widget.salesStream ?? _repo.watchSales(manager: _canManage),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text(_error(snap.error!)));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final sales = snap.data!;
      if (sales.isEmpty) return const Center(child: Text('No recorded sales yet.'));
      return ListView.builder(
        padding: const EdgeInsets.all(14), itemCount: sales.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Recent sales • last 60 records',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));
          final sale = sales[index - 1];
          final price = (sale['totalMinor'] as num?)?.toInt() ?? 0;
          return Card(child: ListTile(
            title: Text((sale['itemName'] ?? 'Item').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${sale['quantity'] ?? 0} units • ${sale['paymentMethod'] ?? 'Cash'}\n'
              '${_date(sale['soldAt'])}'
              '${_canManage ? ' • Seller: ${sale['sellerUid'] ?? ''}' : ''}'),
            isThreeLine: true,
            trailing: Text(inventoryRupees(price),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          ));
        },
      );
    },
  );

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
