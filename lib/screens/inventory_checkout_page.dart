import 'package:flutter/material.dart';

import '../data/inventory_checkout_service.dart';
import '../data/inventory_repository.dart';
import '../data/school_errors.dart';

class InventoryCheckoutPage extends StatefulWidget {
  const InventoryCheckoutPage({
    super.key,
    required this.items,
    required this.cart,
    this.service,
    this.canSyncStudents = false,
  });

  final List<InventoryItem> items;
  final Map<String, int> cart;
  final InventoryCheckoutService? service;
  /// Only pass true for the school owner, never for seller accounts.
  final bool canSyncStudents;

  @override
  State<InventoryCheckoutPage> createState() => _InventoryCheckoutPageState();
}

class _InventoryCheckoutPageState extends State<InventoryCheckoutPage> {
  late final InventoryCheckoutService _service =
      widget.service ?? InventoryCheckoutService();
  late final Map<String, int> _quantities = Map.of(widget.cart);
  final _customerName = TextEditingController();
  final _phone = TextEditingController();
  Future<List<InventoryStudent>>? _studentsFuture;
  InventoryStudent? _selectedStudent;
  String _customerType = 'student';
  String _paymentStatus = 'paid';
  String _method = 'Cash';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _customerName.dispose();
    _phone.dispose();
    super.dispose();
  }

  List<InventoryItem> get _items => widget.items
      .where((item) => (_quantities[item.id] ?? 0) > 0)
      .toList();

  int get _totalMinor => _items.fold(0, (sum, item) =>
      sum + item.priceMinor * (_quantities[item.id] ?? 0));

  int get _units => _quantities.values.fold(0, (sum, q) => sum + q);

  void _changeQuantity(InventoryItem item, int delta) {
    final next = (_quantities[item.id] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _quantities.remove(item.id);
      } else if (next <= item.stockQty && next <= 100) {
        _quantities[item.id] = next;
      }
    });
  }

  Future<void> _chooseStudent() async {
    // Always query again when reopening: the owner may have just synced
    // records from another session/device.
    _studentsFuture = _service.loadStudents();
    String search = '';
    String? syncMessage;
    bool syncing = false;
    final chosen = await showModalBottomSheet<InventoryStudent>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16, 14, 16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (sheetContext, update) => SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.65,
              child: Column(children: [
                Text('Choose school student',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('inventory_student_search'),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Search name, registration or roll number',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const Key('inventory_student_refresh'),
                      tooltip: 'Reload school students',
                      icon: const Icon(Icons.refresh),
                      onPressed: syncing ? null : () => update(() {
                        _studentsFuture = _service.loadStudents();
                        syncMessage = null;
                      }),
                    ),
                  ),
                  onChanged: (value) => update(() => search = value.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Expanded(child: FutureBuilder<List<InventoryStudent>>(
                  future: _studentsFuture,
                  builder: (_, snap) {
                    if (snap.hasError) {
                      return Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(schoolErrorMessage(snap.error!)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => update(() {
                              _studentsFuture = _service.loadStudents();
                            }),
                            child: const Text('Retry student list'),
                          ),
                        ],
                      ));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final matching = snap.data!.where((s) {
                      final keyword = search.trim();
                      return keyword.isEmpty ||
                          s.fullName.toLowerCase().contains(keyword) ||
                          s.id.toLowerCase().contains(keyword) ||
                          s.rollNo.toLowerCase().contains(keyword) ||
                          s.classId.toLowerCase().contains(keyword);
                    }).toList();
                    if (matching.isEmpty) {
                      final emptyDirectory = snap.data!.isEmpty;
                      return Center(child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emptyDirectory
                                ? 'No students have been synchronized for canteen checkout.'
                                : 'No student matches your search. Try a different name, registration or roll number.',
                              textAlign: TextAlign.center),
                            if (syncMessage != null) ...[
                              const SizedBox(height: 8),
                              Text(syncMessage!, textAlign: TextAlign.center),
                            ],
                            const SizedBox(height: 12),
                            if (widget.canSyncStudents)
                              FilledButton.icon(
                                key: const Key('inventory_sync_students_in_checkout'),
                                onPressed: syncing ? null : () async {
                                  update(() { syncing = true; syncMessage = null; });
                                  try {
                                    final result = await _service.syncStudentDirectory();
                                    if (!sheetContext.mounted) return;
                                    update(() {
                                      syncMessage = result.summary;
                                      _studentsFuture = _service.loadStudents();
                                      syncing = false;
                                    });
                                  } catch (error) {
                                    if (!sheetContext.mounted) return;
                                    update(() {
                                      syncMessage = schoolErrorMessage(error);
                                      syncing = false;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.sync),
                                label: Text(syncing ? 'Synchronizing…' : 'Sync students now'),
                              )
                            else if (emptyDirectory)
                              const Text('Ask the school owner to open Canteen '
                                '& Stationery → Sell → Sync students for checkout.',
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ));
                    }
                    return ListView.builder(
                      itemCount: matching.length,
                      itemBuilder: (_, index) {
                        final student = matching[index];
                        return ListTile(
                          title: Text(student.fullName),
                          subtitle: Text('${student.id} • Roll ${student.rollNo} • '
                              '${student.classId}'),
                          onTap: () => Navigator.pop(sheetContext, student),
                        );
                      },
                    );
                  },
                )),
              ]),
            ),
          ),
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => _selectedStudent = chosen);
    }
  }

  Future<void> _checkout() async {
    if (_busy) return;
    if (_items.isEmpty) {
      setState(() => _error = 'Add a product to the cart first.');
      return;
    }
    if (_customerType == 'student' && _selectedStudent == null) {
      setState(() => _error = 'Select the student who is buying or borrowing.');
      return;
    }
    final customer = _customerType == 'student'
        ? InventoryCustomer.student(_selectedStudent!)
        : InventoryCustomer.other(
            name: _customerName.text, phone: _phone.text);
    setState(() { _busy = true; _error = null; });
    try {
      final orderId = await _service.checkout(
        lines: [for (final item in _items)
          InventoryCartLine(sku: item.id, quantity: _quantities[item.id]!)],
        customer: customer,
        paid: _paymentStatus == 'paid',
        paymentMethod: _method,
      );
      if (!mounted) return;
      Navigator.of(context).pop(orderId);
    } catch (e) {
      if (mounted) setState(() => _error = schoolErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owed = _paymentStatus == 'borrowed';
    final mobile = MediaQuery.sizeOf(context).width < 420;
    return Scaffold(
      appBar: AppBar(title: const Text('Canteen checkout')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              key: const Key('inventory_checkout_scroll'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('Shopping cart',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text('${_items.length} products • $_units units',
                    style: Theme.of(context).textTheme.bodySmall),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Text('Your cart is empty. Return to Sell to add items.'),
                  ),
                for (final item in _items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${inventoryRupees(item.priceMinor)} each • '
                              '${item.stockQty} available'),
                          const SizedBox(height: 8),
                          Row(children: [
                            IconButton(
                              tooltip: 'Remove one',
                              onPressed: _busy ? null : () => _changeQuantity(item, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${_quantities[item.id]}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            IconButton(
                              tooltip: 'Add one',
                              onPressed: _busy ? null : () => _changeQuantity(item, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            const Spacer(),
                            Flexible(child: Text(
                              inventoryRupees(item.priceMinor *
                                  (_quantities[item.id] ?? 0)),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            )),
                          ]),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Customer details',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'student', label: Text('Student'),
                        icon: Icon(Icons.school_outlined)),
                    ButtonSegment(value: 'other', label: Text('Other'),
                        icon: Icon(Icons.person_outline)),
                  ],
                  selected: {_customerType},
                  onSelectionChanged: _busy ? null : (selection) =>
                      setState(() => _customerType = selection.first),
                ),
                const SizedBox(height: 14),
                if (_customerType == 'student') ...[
                  OutlinedButton.icon(
                    key: const Key('inventory_select_student'),
                    onPressed: _busy ? null : _chooseStudent,
                    icon: const Icon(Icons.person_search),
                    label: Text(_selectedStudent == null
                        ? 'Select school student' : 'Change student'),
                  ),
                  if (_selectedStudent != null)
                    ListTile(
                      title: Text(_selectedStudent!.fullName),
                      subtitle: Text('Reg: ${_selectedStudent!.id} • '
                        'Roll: ${_selectedStudent!.rollNo} • '
                        '${_selectedStudent!.classId}'),
                    ),
                ] else ...[
                  TextField(
                    key: const Key('inventory_customer_name'),
                    controller: _customerName,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Customer name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('inventory_customer_phone'),
                    controller: _phone,
                    maxLength: 30,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: owed
                          ? 'Contact number (required for borrowed items) *'
                          : 'Contact number (optional)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text('Payment', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  key: const Key('inventory_payment_status'),
                  segments: const [
                    ButtonSegment(value: 'paid', label: Text('Paid'),
                        icon: Icon(Icons.check_circle_outline)),
                    ButtonSegment(value: 'borrowed', label: Text('Borrowed'),
                        icon: Icon(Icons.schedule_outlined)),
                  ],
                  selected: {_paymentStatus},
                  onSelectionChanged: _busy ? null : (selection) =>
                      setState(() => _paymentStatus = selection.first),
                ),
                const SizedBox(height: 12),
                if (!owed)
                  DropdownButtonFormField<String>(
                    key: const Key('inventory_checkout_method'),
                    initialValue: _method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final method in inventoryPaymentMethods)
                        DropdownMenuItem(value: method, child: Text(method)),
                    ],
                    onChanged: _busy ? null : (value) {
                      if (value != null) setState(() => _method = value);
                    },
                  )
                else
                  const Text('Stock will be deducted immediately. The total '
                      'will remain outstanding under this customer until '
                      'payment is collected.'),
                const SizedBox(height: 12),
                const Text('Final prices and available stock are verified '
                    'again when checkout is saved. The seller cannot '
                    'change the owner-set unit prices.',
                  style: TextStyle(fontSize: 12)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('Grand total',
                      style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(inventoryRupees(_totalMinor),
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                if (mobile)
                  SizedBox(width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('inventory_confirm_checkout'),
                      onPressed: _busy || _items.isEmpty ? null : _checkout,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(_busy ? 'Recording…' : owed
                          ? 'Save borrowed sale' : 'Complete paid sale'),
                    ))
                else
                  FilledButton.icon(
                    key: const Key('inventory_confirm_checkout'),
                    onPressed: _busy || _items.isEmpty ? null : _checkout,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(_busy ? 'Recording…' : owed
                        ? 'Save borrowed sale' : 'Complete paid sale'),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
