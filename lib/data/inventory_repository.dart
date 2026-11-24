import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Prices are stored as integer paisa to prevent rounding errors.
/// Sellers only submit an item ID, quantity and payment method. The current
/// price and stock are re-read inside an atomic Firestore transaction.
int inventoryMoneyMinor(String input) {
  final clean = input.trim();
  if (!RegExp(r'^[0-9]{1,9}(\.[0-9]{1,2})?$').hasMatch(clean)) {
    throw FormatException('Enter an amount in rupees, e.g. 125 or 125.50.');
  }
  final parts = clean.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

String inventoryRupees(int minor) =>
    'Rs ${(minor / 100).toStringAsFixed(2)}';

const inventoryDepartments = <String, String>{
  'canteen': 'Canteen',
  'stationery': 'Stationery',
};
const inventoryPaymentMethods = <String>[
  'Cash', 'Easypaisa', 'JazzCash', 'Bank Transfer', 'Other',
];

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.department,
    required this.unit,
    required this.priceMinor,
    required this.stockQty,
    required this.reorderPoint,
    required this.active,
    required this.description,
    this.category = 'other',
    this.subcategory = 'other',
    this.customType = '',
    this.classLevel = '',
    this.bookSeries = '',
    this.subject = '',
    this.publisher = '',
    this.brand = '',
    this.variant = '',
    this.expiryDate = '',
    this.archived = false,
  });

  final String id;
  final String name;
  final String department;
  final String unit;
  final int priceMinor;
  final int stockQty;
  final int reorderPoint;
  final bool active;
  final String description;
  final String category;
  final String subcategory;
  final String customType;
  final String classLevel;
  final String bookSeries;
  final String subject;
  final String publisher;
  final String brand;
  final String variant;
  final String expiryDate;
  final bool archived;

  bool get isLowStock => stockQty <= reorderPoint;
  bool get canSell => active && !archived && stockQty > 0;

  factory InventoryItem.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? {};
    return InventoryItem(
      id: snapshot.id,
      name: (data['name'] as String?) ?? '',
      department: (data['department'] as String?) ?? 'canteen',
      unit: (data['unit'] as String?) ?? 'piece',
      priceMinor: (data['priceMinor'] as num?)?.toInt() ?? 0,
      stockQty: (data['stockQty'] as num?)?.toInt() ?? 0,
      reorderPoint: (data['reorderPoint'] as num?)?.toInt() ?? 0,
      active: data['active'] == true,
      description: (data['description'] as String?) ?? '',
      category: (data['category'] as String?) ?? 'other',
      subcategory: (data['subcategory'] as String?) ?? 'other',
      customType: (data['customType'] as String?) ?? '',
      classLevel: (data['classLevel'] as String?) ?? '',
      bookSeries: (data['bookSeries'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      publisher: (data['publisher'] as String?) ?? '',
      brand: (data['brand'] as String?) ?? '',
      variant: (data['variant'] as String?) ?? '',
      expiryDate: (data['expiryDate'] as String?) ?? '',
      archived: data['archived'] == true,
    );
  }
}

class InventoryRepository {
  InventoryRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to manage canteen stock.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('inventory_items');

  CollectionReference<Map<String, dynamic>> get _costs =>
      _db.collection('inventory_costs');

  /// Confidential cost documents are readable only by owner/manager.
  Stream<Map<String, int>> watchCosts() => _costs.limit(500).snapshots().map(
    (snap) => {
      for (final doc in snap.docs)
        if (doc.data()['unitCostMinor'] is num)
          doc.id: (doc.data()['unitCostMinor'] as num).toInt(),
    },
  );

  Future<int?> loadCost(String sku) async {
    final snapshot = await _costs.doc(sku).get();
    return (snapshot.data()?['unitCostMinor'] as num?)?.toInt();
  }

  Stream<List<InventoryItem>> watchItems() => _items
      .orderBy('name')
      .limit(300)
      .snapshots()
      .map((snap) => snap.docs.map(InventoryItem.fromSnapshot).toList());

  /// One-shot server reload for the Sell and Stock retry buttons. Keeping
  /// the independent live stream ensures edits and stock movements continue
  /// appearing automatically after a manual refresh.
  Future<List<InventoryItem>> loadItems() async {
    final snapshot = await _items
        .orderBy('name')
        .limit(300)
        .get(const GetOptions(source: Source.server));
    return snapshot.docs.map(InventoryItem.fromSnapshot).toList();
  }

  Stream<List<Map<String, dynamic>>> watchBorrowed({required bool manager}) {
    // Separate query means old borrowed items remain collectible after
    // they are no longer in the recent-sales window.
    final source = _db.collection('inventory_sales');
    final query = manager
        ? source.where('paymentStatus',
            whereIn: ['borrowed', 'partially_paid']).limit(1000)
        : source.where('sellerUid', isEqualTo: _uid)
            .where('paymentStatus',
                whereIn: ['borrowed', 'partially_paid']).limit(1000);
    return query.snapshots().map((snap) {
      final data = snap.docs.map((doc) =>
        {...doc.data(), 'id': doc.id}).toList();
      data.sort((a, b) {
        final first = a['soldAt'];
        final second = b['soldAt'];
        if (first is! Timestamp || second is! Timestamp) return 0;
        return second.compareTo(first);
      });
      return data;
    });
  }

  Stream<List<Map<String, dynamic>>> watchSales({required bool manager}) {
    final query = manager
        ? _db.collection('inventory_sales')
            .orderBy('soldAt', descending: true).limit(300)
        : _db.collection('inventory_sales')
            .where('sellerUid', isEqualTo: _uid).limit(300);
    return query.snapshots().map((snap) {
      final records = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      records.sort((a, b) {
        final left = a['soldAt'];
        final right = b['soldAt'];
        if (left is! Timestamp || right is! Timestamp) return 0;
        return right.compareTo(left);
      });
      return records;
    });
  }

  Stream<List<Map<String, dynamic>>> watchPurchases() => _db
      .collection('inventory_purchases')
      .orderBy('recordedAt', descending: true)
      .limit(60)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());

  /// Owner/authorized manager only. Stock starts at zero; it is increased by
  /// recording a dated receipt, never by modifying an item directly.
  Future<void> createItem({
    required String sku,
    required String name,
    required String department,
    required String unit,
    required int priceMinor,
    required int reorderPoint,
    String description = '',
  }) async {
    final key = sku.trim().toUpperCase();
    final cleanName = name.trim();
    if (!RegExp(r'^[A-Z0-9_-]{3,32}$').hasMatch(key) ||
        cleanName.length < 2 || cleanName.length > 100 ||
        !inventoryDepartments.containsKey(department) ||
        unit.trim().isEmpty || unit.trim().length > 24 ||
        priceMinor <= 0 || reorderPoint < 0 || description.length > 250) {
      throw ArgumentError('Check the SKU, name, category, price and stock alert.');
    }
    final userId = _uid;
    await _db.runTransaction((tx) async {
      final ref = _items.doc(key);
      final existing = await tx.get(ref);
      if (existing.exists) throw StateError('This SKU is already registered.');
      tx.set(ref, {
        'sku': key, 'name': cleanName, 'department': department,
        'unit': unit.trim(), 'description': description.trim(),
        'priceMinor': priceMinor, 'stockQty': 0, 'reorderPoint': reorderPoint,
        'active': true, 'currency': 'PKR',
        'lastMovementId': '', 'lastMovementType': '',
        'createdBy': userId, 'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': userId, 'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateItem({
    required InventoryItem item,
    required String name,
    required String department,
    required String unit,
    required int priceMinor,
    required int reorderPoint,
    required bool active,
    String description = '',
  }) async {
    if (name.trim().length < 2 || name.trim().length > 100 ||
        !inventoryDepartments.containsKey(department) ||
        unit.trim().isEmpty || unit.trim().length > 24 ||
        priceMinor <= 0 || reorderPoint < 0 || description.length > 250) {
      throw ArgumentError('Check the item name, category, price and details.');
    }
    await _items.doc(item.id).update({
      'name': name.trim(), 'department': department, 'unit': unit.trim(),
      'description': description.trim(), 'priceMinor': priceMinor,
      'reorderPoint': reorderPoint, 'active': active,
      'updatedBy': _uid, 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordSale({
    required String sku,
    required int quantity,
    required String paymentMethod,
  }) async {
    if (quantity < 1 || quantity > 100 ||
        !inventoryPaymentMethods.contains(paymentMethod)) {
      throw ArgumentError('Choose a valid quantity and payment method.');
    }
    final seller = _uid;
    final saleRef = _db.collection('inventory_sales').doc();
    final itemRef = _items.doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) throw StateError('The item is no longer available.');
      final item = InventoryItem.fromSnapshot(snap);
      if (!item.active || item.archived) {
        throw StateError('This item is no longer available for sale.');
      }
      if (item.priceMinor <= 0 || item.stockQty < quantity) {
        throw StateError('Insufficient stock. Refresh and try again.');
      }
      tx.update(itemRef, {
        'stockQty': item.stockQty - quantity,
        'lastMovementId': saleRef.id, 'lastMovementType': 'sale',
        'updatedBy': seller, 'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(saleRef, {
        'saleId': saleRef.id, 'itemId': item.id,
        'itemName': item.name, 'department': item.department,
        'quantity': quantity, 'stockBefore': item.stockQty,
        'unitPriceMinor': item.priceMinor,
        'totalMinor': item.priceMinor * quantity,
        'currency': 'PKR', 'sellerUid': seller,
        'paymentMethod': paymentMethod,
        'soldAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> receiveStock({
    required String sku,
    required int quantity,
    required int unitCostMinor,
    required String supplier,
    required String invoice,
  }) async {
    if (quantity < 1 || quantity > 100000 || unitCostMinor <= 0 ||
        supplier.trim().isEmpty || supplier.trim().length > 100 ||
        invoice.trim().length > 80) {
      throw ArgumentError('Check stock quantity, supplier and purchase cost.');
    }
    final userId = _uid;
    final event = _db.collection('inventory_purchases').doc();
    final ref = _items.doc(sku);
    final costRef = _costs.doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final currentCost = await tx.get(costRef);
      if (!snap.exists) throw StateError('Item is missing.');
      final item = InventoryItem.fromSnapshot(snap);
      if (item.stockQty + quantity > 100000000) {
        throw StateError('This stock quantity is too high.');
      }
      if (currentCost.exists) {
        tx.update(costRef, {
          'unitCostMinor': unitCostMinor,
          'updatedBy': userId, 'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (unitCostMinor > 0) {
        tx.set(costRef, {
          'sku': sku, 'department': item.department,
          'unitCostMinor': unitCostMinor, 'currency': 'PKR',
          'createdBy': userId, 'createdAt': FieldValue.serverTimestamp(),
          'updatedBy': userId, 'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      tx.update(ref, {
        'stockQty': item.stockQty + quantity,
        'lastMovementId': event.id, 'lastMovementType': 'purchase',
        'updatedBy': userId, 'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(event, {
        'purchaseId': event.id, 'itemId': item.id, 'itemName': item.name,
        'quantity': quantity, 'stockBefore': item.stockQty,
        'unitCostMinor': unitCostMinor,
        'totalCostMinor': unitCostMinor * quantity,
        'supplier': supplier.trim(), 'invoice': invoice.trim(),
        'source': 'receipt',
        'currency': 'PKR', 'recordedBy': userId,
        'purchasedAt': FieldValue.serverTimestamp(),
        'recordedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> adjustStock({
    required String sku,
    required int delta,
    required String reason,
    required String notes,
  }) async {
    const reasons = {'damage', 'expired', 'wastage', 'return', 'correction'};
    if (delta == 0 || delta.abs() > 100000 ||
        !reasons.contains(reason) || notes.trim().length > 250) {
      throw ArgumentError('Choose a valid adjustment and reason.');
    }
    final userId = _uid;
    final event = _db.collection('inventory_adjustments').doc();
    final ref = _items.doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Item is missing.');
      final item = InventoryItem.fromSnapshot(snap);
      final next = item.stockQty + delta;
      if (next < 0 || next > 100000000) {
        throw StateError('Stock cannot become negative or exceed the limit.');
      }
      tx.update(ref, {
        'stockQty': next, 'lastMovementId': event.id,
        'lastMovementType': 'adjustment', 'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(event, {
        'adjustmentId': event.id, 'itemId': item.id, 'itemName': item.name,
        'delta': delta, 'stockBefore': item.stockQty,
        'reason': reason, 'notes': notes.trim(), 'recordedBy': userId,
        'recordedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
