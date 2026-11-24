import 'package:flutter/material.dart';

import '../data/inventory_checkout_service.dart';
import '../data/inventory_repository.dart';
import '../data/school_errors.dart';

/// Break-time point of sale. No student directory lookup or personal details.
/// Items must be canteen products; checkout is paid-only.
class InventoryQuickCanteenCheckoutPage extends StatefulWidget {
  const InventoryQuickCanteenCheckoutPage({
    super.key,
    required this.items,
    required this.cart,
    this.service,
  });

  final List<InventoryItem> items;
  final Map<String, int> cart;
  final InventoryCheckoutService? service;

  @override
  State<InventoryQuickCanteenCheckoutPage> createState() =>
      _InventoryQuickCanteenCheckoutPageState();
}

class _InventoryQuickCanteenCheckoutPageState
    extends State<InventoryQuickCanteenCheckoutPage> {
  late final InventoryCheckoutService _service =
      widget.service ?? InventoryCheckoutService();
  late final Map<String, int> _quantities = Map.of(widget.cart);
  String _customerType = 'student';
  String _method = 'Cash';
  bool _saving = false;
  String? _error;

  List<InventoryItem> get _items => widget.items.where((item) =>
      item.department == 'canteen' && (_quantities[item.id] ?? 0) > 0).toList();
  int get _total => _items.fold(0, (sum, item) =>
      sum + item.priceMinor * (_quantities[item.id] ?? 0));
  int get _units => _quantities.values.fold(0, (sum, qty) => sum + qty);

  void _changeQuantity(InventoryItem item, int delta) {
    final quantity = (_quantities[item.id] ?? 0) + delta;
    if (quantity > item.stockQty || quantity > 100) return;
    setState(() {
      if (quantity <= 0) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = quantity;
      }
    });
  }

  Future<void> _completeSale() async {
    if (_saving || _items.isEmpty) return;
    // Guard against a stale or mixed-department cart before any write.
    if (_quantities.keys.any((id) => !widget.items.any(
        (item) => item.id == id && item.department == 'canteen'))) {
      setState(() => _error = 'Only canteen products can be sold here.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final receipt = await _service.checkout(
        lines: [
          for (final item in _items)
            InventoryCartLine(sku: item.id, quantity: _quantities[item.id]!),
        ],
        customer: InventoryCustomer.quick(_customerType),
        paid: true,
        paymentMethod: _method,
        quickCanteen: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(receipt);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canteen quick sale')),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(
          key: const Key('canteen_quick_checkout_list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Text('Cart • $_units units',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final item in _items)
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text('${inventoryRupees(item.priceMinor)} each'),
                    Row(children: [
                      IconButton(
                        tooltip: 'Remove one',
                        onPressed: _saving ? null : () => _changeQuantity(item, -1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${_quantities[item.id]}'),
                      IconButton(
                        tooltip: 'Add one',
                        onPressed: _saving || (_quantities[item.id] ?? 0) >= item.stockQty
                            ? null : () => _changeQuantity(item, 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      Text(inventoryRupees(item.priceMinor *
                              (_quantities[item.id] ?? 0)),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ],
                ),
              )),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Cart is empty. Go back to add canteen products.')),
            const SizedBox(height: 20),
            Text('Who is buying?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              key: const Key('canteen_quick_customer_type'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in const [
                  ('student', 'Student', Icons.school_outlined),
                  ('teacher', 'Teacher', Icons.badge_outlined),
                  ('other', 'Other', Icons.person_outline),
                ])
                  ChoiceChip(
                    label: Text(choice.$2),
                    avatar: Icon(choice.$3, size: 17),
                    selected: _customerType == choice.$1,
                    onSelected: _saving ? null : (_) =>
                        setState(() => _customerType = choice.$1),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            const Text('No name, roll number or student lookup is needed.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('canteen_quick_payment_method'),
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment received by'),
              items: [
                for (final method in inventoryPaymentMethods)
                  DropdownMenuItem(value: method, child: Text(method)),
              ],
              onChanged: _saving ? null : (method) {
                if (method != null) setState(() => _method = method);
              },
            ),
            const SizedBox(height: 10),
            const Text('Paid sales only. Stock is deducted automatically '
                'and the sale is recorded in Canteen Sales.',
                style: TextStyle(fontSize: 12)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        )),
        Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('Total',
                  style: TextStyle(fontWeight: FontWeight.w700))),
                Text(inventoryRupees(_total),
                  style: const TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('canteen_complete_quick_sale'),
                  onPressed: _saving || _items.isEmpty ? null : _completeSale,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Recording sale…' : 'Complete paid sale'),
                )),
            ]),
          ),
        ),
      ])),
    );
  }
}
