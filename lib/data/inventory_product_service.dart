import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'inventory_catalog.dart';
import 'inventory_repository.dart';

/// The only entry point for direct product-quantity edits.
/// Both an opening balance and later corrections have an immutable ledger
/// entry in the SAME transaction as their corresponding inventory change.
class InventoryProductInput {
  const InventoryProductInput({
    required this.name,
    required this.department,
    required this.category,
    required this.subcategory,
    required this.quantity,
    required this.priceMinor,
    required this.reorderPoint,
    this.unit = 'piece',
    this.customType = '',
    this.classLevel = '',
    this.bookSeries = '',
    this.subject = '',
    this.publisher = '',
    this.brand = '',
    this.variant = '',
    this.expiryDate = '',
    this.description = '',
    this.active = true,
  });

  final String name;
  final String department;
  final String category;
  final String subcategory;
  final int quantity;
  final int priceMinor;
  final int reorderPoint;
  final String unit;
  final String customType;
  final String classLevel;
  final String bookSeries;
  final String subject;
  final String publisher;
  final String brand;
  final String variant;
  final String expiryDate;
  final String description;
  final bool active;

  void validate() {
    final categories = inventoryCategoriesFor(department);
    final subcategories = inventorySubcategoriesFor(department, category);
    if (!inventoryDepartments.containsKey(department) ||
        !categories.containsKey(category) ||
        !subcategories.containsKey(subcategory) ||
        name.trim().length < 2 || name.trim().length > 100 ||
        quantity < 0 || quantity > 100000000 ||
        priceMinor <= 0 || priceMinor > 100000000000 ||
        reorderPoint < 0 || reorderPoint > 100000000 ||
        unit.trim().isEmpty || unit.length > 24 ||
        description.length > 250 || customType.length > 80 ||
        classLevel.length > 32 || bookSeries.length > 100 ||
        subject.length > 80 || publisher.length > 100 ||
        brand.length > 100 || variant.length > 80 ||
        expiryDate.length > 10) {
      throw ArgumentError('Check item name, category, quantity and price.');
    }
    if ((category == 'other' || subcategory == 'other') &&
        customType.trim().isEmpty) {
      throw ArgumentError('Please describe the Other category or product type.');
    }
    if (department == 'stationery' && category == 'books' &&
        !inventorySchoolClasses.contains(classLevel)) {
      throw ArgumentError('Choose the class for this book.');
    }
    if (expiryDate.isNotEmpty &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiryDate)) {
      throw ArgumentError('Enter an expiry date as YYYY-MM-DD.');
    }
  }

  Map<String, dynamic> get metadata => {
    'name': name.trim(), 'department': department,
    'category': category, 'subcategory': subcategory,
    'customType': customType.trim(), 'classLevel': classLevel,
    'bookSeries': bookSeries.trim(), 'subject': subject.trim(),
    'publisher': publisher.trim(), 'brand': brand.trim(),
    'variant': variant.trim(), 'expiryDate': expiryDate,
    'description': description.trim(), 'unit': unit.trim(),
    'priceMinor': priceMinor, 'reorderPoint': reorderPoint,
    'active': active,
  };
}

class InventoryProductService {
  InventoryProductService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to manage inventory.');
    return uid;
  }

  /// Returns an auto-generated immutable item code, e.g. ST-3V... or CN-8K....
  Future<String> create(InventoryProductInput input) async {
    input.validate();
    final editor = _uid;
    final randomId = _db.collection('inventory_items').doc().id.toUpperCase();
    final sku = '${input.department == 'stationery' ? 'ST' : 'CN'}-${randomId.substring(0, 15)}';
    final ref = _db.collection('inventory_items').doc(sku);
    final opening = _db.collection('inventory_adjustments').doc();

    await _db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) {
        throw StateError('Code conflict. Please save the product again.');
      }
      tx.set(ref, {
        'sku': sku, ...input.metadata,
        'stockQty': input.quantity,
        'active': true, 'archived': false, 'currency': 'PKR',
        'lastMovementType': input.quantity > 0 ? 'opening' : '',
        'lastMovementId': input.quantity > 0 ? opening.id : '',
        'createdBy': editor, 'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': editor, 'updatedAt': FieldValue.serverTimestamp(),
      });
      if (input.quantity > 0) {
        tx.set(opening, {
          'adjustmentId': opening.id, 'itemId': sku,
          'itemName': input.name.trim(), 'delta': input.quantity,
          'stockBefore': 0, 'reason': 'opening',
          'notes': 'Opening quantity entered on new product',
          'recordedBy': editor, 'recordedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return sku;
  }

  /// Re-reads current stock to prevent lost updates if sales occur while an
  /// owner is editing. Saving with a new quantity writes a correction ledger
  /// event atomically with all other product edits.
  Future<void> save(InventoryItem item, InventoryProductInput input) async {
    input.validate();
    final editor = _uid;
    final ref = _db.collection('inventory_items').doc(item.id);
    final adjustment = _db.collection('inventory_adjustments').doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Product not found.');
      final current = InventoryItem.fromSnapshot(snap);
      if (current.archived) {
        throw StateError('Restore this item before editing.');
      }
      final difference = input.quantity - current.stockQty;
      if (difference.abs() > 100000) {
        throw ArgumentError('Stock correction cannot exceed 100,000 per change.');
      }
      tx.update(ref, {
        ...input.metadata,
        'stockQty': input.quantity,
        if (difference != 0) ...{
          'lastMovementType': 'adjustment',
          'lastMovementId': adjustment.id,
        },
        'updatedBy': editor, 'updatedAt': FieldValue.serverTimestamp(),
      });
      if (difference != 0) {
        tx.set(adjustment, {
          'adjustmentId': adjustment.id, 'itemId': current.id,
          'itemName': current.name, 'delta': difference,
          'stockBefore': current.stockQty, 'reason': 'correction',
          'notes': 'Authorized user entered a new stock quantity',
          'recordedBy': editor, 'recordedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Reversible delete for daily operations. Receipts and purchase records
  /// remain immutable, and the SKU is never reused.
  Future<void> archive(InventoryItem item) async {
    final editor = _uid;
    final ref = _db.collection('inventory_items').doc(item.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Product not found.');
      if (InventoryItem.fromSnapshot(snap).archived) {
        throw StateError('Product is already archived.');
      }
      tx.update(ref, {
        'active': false, 'archived': true,
        'archivedBy': editor, 'archivedAt': FieldValue.serverTimestamp(),
        'updatedBy': editor, 'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> restore(InventoryItem item) async {
    final editor = _uid;
    final ref = _db.collection('inventory_items').doc(item.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Product not found.');
      if (!InventoryItem.fromSnapshot(snap).archived) return;
      tx.update(ref, {
        'archived': false, 'active': false,
        'archivedBy': '', 'archivedAt': null,
        'updatedBy': editor, 'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
