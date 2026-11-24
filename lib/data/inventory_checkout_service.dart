import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'inventory_repository.dart';

/// The canteen customer directory contains no admission, guardian, health,
/// document or contact fields. Sellers must never be granted students reads.
class InventoryStudent {
  const InventoryStudent({
    required this.id,
    required this.fullName,
    required this.rollNo,
    required this.classId,
  });

  final String id;
  final String fullName;
  final String rollNo;
  final String classId;

  factory InventoryStudent.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    return InventoryStudent(
      id: snap.id,
      fullName: (data['fullName'] as String?) ?? '',
      rollNo: (data['rollNo'] as String?) ?? '',
      classId: (data['classId'] as String?) ?? '',
    );
  }
}

/// Projection of admission information that inventory sellers are allowed to
/// see. This deliberately omits guardian, health, contact and document fields.
///
/// Historical students sometimes omit status/active (the main Students screen
/// treats those as admitted/active), and must not disappear at checkout.
Map<String, dynamic>? inventoryStudentDirectoryProjection(
  String studentId, Map<String, dynamic> record,
) {
  final name = record['fullName'];
  if (name is! String || name.trim().isEmpty) return null;
  final status = record['status'] is String
      ? record['status'] as String : 'admitted';
  if (status == 'draft') return null;
  final rollNo = record['rollNo'];
  final classId = record['classId'];
  // Preserve the exact source values: Firestore rules independently verify
  // that no private or altered student details enter the public projection.
  return {
    'studentId': studentId,
    'fullName': name,
    'rollNo': rollNo is String ? rollNo : '',
    'classId': classId is String ? classId : '',
    'active': status == 'admitted' && record['active'] != false,
  };
}

class InventoryStudentSyncResult {
  const InventoryStudentSyncResult({
    required this.scanned,
    required this.synced,
    required this.active,
    required this.skipped,
  });
  final int scanned;
  final int synced;
  final int active;
  final int skipped;

  String get summary => '$synced students synchronized '
      '($active active, $skipped skipped).';
}

class InventoryCustomer {
  const InventoryCustomer.student(this.student)
      : type = 'student', name = '', phone = '';
  const InventoryCustomer.other({required this.name, this.phone = ''})
      : type = 'other', student = null;

  final String type;
  final InventoryStudent? student;
  final String name;
  final String phone;

  String get displayName => student?.fullName ?? name.trim();
  String get customerId => student?.id ?? '';
  String get rollNo => student?.rollNo ?? '';
  String get classId => student?.classId ?? '';
}

class InventoryCartLine {
  const InventoryCartLine({required this.sku, required this.quantity});
  final String sku;
  final int quantity;
}

class InventorySaleLine {
  const InventorySaleLine({
    required this.id,
    required this.orderId,
    required this.itemName,
    required this.department,
    required this.customerName,
    required this.customerType,
    required this.customerId,
    required this.customerPhone,
    required this.customerClass,
    required this.quantity,
    required this.totalMinor,
    required this.paidMinor,
    required this.sellerUid,
    this.soldAt,
  });

  final String id;
  final String orderId;
  final String itemName;
  final String department;
  final String customerName;
  final String customerType;
  final String customerId;
  final String customerPhone;
  final String customerClass;
  final int quantity;
  final int totalMinor;
  final int paidMinor;
  final String sellerUid;
  final Timestamp? soldAt;

  int get dueMinor => totalMinor - paidMinor;
  bool get isPaid => dueMinor == 0;

  factory InventorySaleLine.fromMap(Map<String, dynamic> map) {
    final total = (map['totalMinor'] as num?)?.toInt() ?? 0;
    // Previous one-item sales predate credit tracking; those were always paid.
    final paid = (map['paidMinor'] as num?)?.toInt() ?? total;
    final id = (map['id'] as String?) ?? (map['saleId'] as String?) ?? '';
    final order = (map['orderId'] as String?) ?? id;
    return InventorySaleLine(
      id: id,
      orderId: order,
      itemName: (map['itemName'] as String?) ?? 'Item',
      department: (map['department'] as String?) ?? '',
      customerName: (map['customerName'] as String?) ?? 'Walk-in customer',
      customerType: (map['customerType'] as String?) ?? 'other',
      customerId: (map['customerId'] as String?) ?? '',
      customerPhone: (map['customerPhone'] as String?) ?? '',
      customerClass: (map['customerClass'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      totalMinor: total,
      paidMinor: paid,
      sellerUid: (map['sellerUid'] as String?) ?? '',
      soldAt: map['soldAt'] is Timestamp ? map['soldAt'] as Timestamp : null,
    );
  }
}

class InventoryOrderSummary {
  InventoryOrderSummary(this.orderId, this.lines);

  final String orderId;
  final List<InventorySaleLine> lines;

  int get totalMinor => lines.fold(0, (sum, l) => sum + l.totalMinor);
  int get paidMinor => lines.fold(0, (sum, l) => sum + l.paidMinor);
  int get dueMinor => totalMinor - paidMinor;
  int get quantity => lines.fold(0, (sum, l) => sum + l.quantity);
  String get customerName => lines.first.customerName;
  String get customerType => lines.first.customerType;
  String get customerId => lines.first.customerId;
  String get customerPhone => lines.first.customerPhone;
  String get customerClass => lines.first.customerClass;
  Timestamp? get soldAt => lines.first.soldAt;
}

List<InventoryOrderSummary> inventoryGroupSales(
    List<Map<String, dynamic>> records) {
  final map = <String, List<InventorySaleLine>>{};
  for (final record in records) {
    final line = InventorySaleLine.fromMap(record);
    if (line.id.isEmpty) continue;
    map.putIfAbsent(line.orderId, () => []).add(line);
  }
  final orders = [
    for (final entry in map.entries)
      InventoryOrderSummary(entry.key, entry.value),
  ];
  orders.sort((a, b) {
    final timeA = a.soldAt?.millisecondsSinceEpoch ?? 0;
    final timeB = b.soldAt?.millisecondsSinceEpoch ?? 0;
    return timeB.compareTo(timeA);
  });
  return orders;
}

/// Server-side Firestore transactions lock the owner-set price and stock and
/// create one immutable sale line per cart item in the same atomic checkout.
class InventoryCheckoutService {
  InventoryCheckoutService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before recording a sale.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection('inventory_student_directory');
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('inventory_items');
  CollectionReference<Map<String, dynamic>> get _sales =>
      _db.collection('inventory_sales');
  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection('inventory_payments');

  Future<List<InventoryStudent>> loadStudents() async {
    final snap = await _students
        .where('active', isEqualTo: true)
        .limit(1000)
        .get(const GetOptions(source: Source.server));
    final students = snap.docs.map(InventoryStudent.fromSnapshot).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return students;
  }

  /// Owner/principal backfill of active/archived admissions into the
  /// seller-safe directory. Page by document ID (rather than fullName):
  /// old school records may not have indexed fullName at all.
  ///
  /// Use small commits because Firestore rules verify each projected record
  /// against its corresponding private source student document.
  Future<InventoryStudentSyncResult> syncStudentDirectory() async {
    _uid;
    const pageSize = 100;
    const batchSize = 5;
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    var scanned = 0;
    var synced = 0;
    var active = 0;
    var skipped = 0;

    while (true) {
      Query<Map<String, dynamic>> query = _db.collection('students')
          .orderBy(FieldPath.documentId).limit(pageSize);
      if (last != null) query = query.startAfterDocument(last);
      final page = await query.get(const GetOptions(source: Source.server));
      if (page.docs.isEmpty) break;
      scanned += page.docs.length;

      final projections = <MapEntry<String, Map<String, dynamic>>>[];
      for (final doc in page.docs) {
        final value = inventoryStudentDirectoryProjection(doc.id, doc.data());
        if (value == null) {
          skipped++;
          continue;
        }
        if (value['active'] == true) active++;
        projections.add(MapEntry(doc.id, value));
      }

      for (var offset = 0; offset < projections.length; offset += batchSize) {
        final batch = _db.batch();
        final group = projections.skip(offset).take(batchSize).toList();
        for (final item in group) {
          batch.set(_students.doc(item.key), {
            ...item.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        synced += group.length;
      }

      last = page.docs.last;
      if (page.docs.length < pageSize) break;
    }

    return InventoryStudentSyncResult(
      scanned: scanned, synced: synced, active: active, skipped: skipped);
  }

  /// Up to six distinct products per atomic checkout. Multiple units of the
  /// same product are one cart line. No price sent by the seller is trusted.
  Future<String> checkout({
    required List<InventoryCartLine> lines,
    required InventoryCustomer customer,
    required bool paid,
    required String paymentMethod,
  }) async {
    if (lines.isEmpty || lines.length > 6 ||
        lines.map((line) => line.sku).toSet().length != lines.length ||
        lines.any((line) => line.quantity < 1 || line.quantity > 100)) {
      throw ArgumentError('Choose 1–6 distinct products, up to 100 units each.');
    }
    if (paid && !inventoryPaymentMethods.contains(paymentMethod)) {
      throw ArgumentError('Select a valid payment method.');
    }
    if (customer.type == 'other' &&
        (customer.name.trim().length < 2 || customer.name.trim().length > 100 ||
         customer.phone.trim().length > 30 ||
         (!paid && customer.phone.trim().isEmpty))) {
      throw ArgumentError('Enter the customer name and a contact number for credit.');
    }
    if (customer.type == 'student' && customer.student == null) {
      throw ArgumentError('Select a school student.');
    }

    final seller = _uid;
    final orderId = _sales.doc().id;
    final saleRefs = [for (final _ in lines) _sales.doc()];
    final itemRefs = [for (final line in lines) _items.doc(line.sku)];
    final studentRef = customer.student == null
        ? null : _students.doc(customer.customerId);

    await _db.runTransaction((tx) async {
      // All transaction reads MUST finish before the first write.
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in itemRefs) {
        snapshots.add(await tx.get(ref));
      }
      Map<String, dynamic>? verifiedStudent;
      if (studentRef != null) {
        final snap = await tx.get(studentRef);
        if (!snap.exists || snap.data()?['active'] != true) {
          throw StateError('Student is no longer active. Choose again.');
        }
        verifiedStudent = snap.data();
      }

      final customerName = verifiedStudent == null
          ? customer.name.trim() : (verifiedStudent['fullName'] as String?) ?? '';
      final customerClass = verifiedStudent == null ? '' :
          (verifiedStudent['classId'] as String?) ?? '';
      final customerRoll = verifiedStudent == null ? '' :
          (verifiedStudent['rollNo'] as String?) ?? '';
      if (customerName.length < 2) {
        throw StateError('Select a customer with a valid name.');
      }

      for (var index = 0; index < lines.length; index++) {
        final snapshot = snapshots[index];
        if (!snapshot.exists) {
          throw StateError('A cart product is no longer available.');
        }
        final item = InventoryItem.fromSnapshot(snapshot);
        final count = lines[index].quantity;
        if (!item.canSell || item.stockQty < count || item.priceMinor <= 0) {
          throw StateError('${item.name}: not enough active stock. Refresh your cart.');
        }
        final amount = item.priceMinor * count;
        final saleRef = saleRefs[index];
        tx.update(itemRefs[index], {
          'stockQty': item.stockQty - count,
          'lastMovementId': saleRef.id,
          'lastMovementType': 'sale',
          'updatedBy': seller,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(saleRef, {
          'saleId': saleRef.id,
          'orderId': orderId,
          'lineNumber': index + 1,
          'itemId': item.id, 'itemName': item.name,
          'department': item.department,
          'quantity': count, 'stockBefore': item.stockQty,
          'unitPriceMinor': item.priceMinor, 'totalMinor': amount,
          'currency': 'PKR', 'sellerUid': seller,
          'customerType': customer.type,
          'customerId': customer.customerId,
          'customerName': customerName,
          'customerPhone': customer.type == 'other' ? customer.phone.trim() : '',
          'customerClass': customerClass,
          'customerRollNo': customerRoll,
          'paidMinor': paid ? amount : 0,
          'paymentStatus': paid ? 'paid' : 'borrowed',
          'paymentMethod': paid ? paymentMethod : 'Unpaid',
          'lastPaymentId': '',
          'soldAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return orderId;
  }

  /// Applies one collection across the oldest unpaid lines of a cart.
  /// Every allocation is an immutable payment document and a matching
  /// sale-line update. A transaction rechecks the server due balances.
  Future<void> collectPayment({
    required InventoryOrderSummary order,
    required int amountMinor,
    required String method,
  }) async {
    if (amountMinor <= 0 || amountMinor > order.dueMinor ||
        !inventoryPaymentMethods.contains(method)) {
      throw ArgumentError('Enter a payment no greater than the outstanding amount.');
    }
    final collector = _uid;
    final unpaidLines = order.lines.where((line) => line.dueMinor > 0).toList();
    final saleRefs = [for (final line in unpaidLines) _sales.doc(line.id)];
    final payments = [for (final _ in unpaidLines) _payments.doc()];
    await _db.runTransaction((tx) async {
      final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in saleRefs) {
        snaps.add(await tx.get(ref));
      }
      final serverLines = [
        for (var index = 0; index < snaps.length; index++)
          InventorySaleLine.fromMap({...?snaps[index].data(), 'id': saleRefs[index].id}),
      ];
      if (snaps.any((s) => !s.exists) ||
          serverLines.any((line) => line.orderId != order.orderId) ||
          serverLines.any((line) =>
              line.sellerUid != order.lines.first.sellerUid)) {
        throw StateError('This order changed. Reload before collecting payment.');
      }
      final due = serverLines.fold<int>(0, (sum, line) => sum + line.dueMinor);
      if (amountMinor > due) {
        throw StateError('Outstanding balance changed. Reload this order.');
      }
      var remaining = amountMinor;
      for (var index = 0; index < serverLines.length && remaining > 0; index++) {
        final line = serverLines[index];
        if (line.dueMinor == 0) continue;
        final applied = remaining < line.dueMinor ? remaining : line.dueMinor;
        remaining -= applied;
        final paidAfter = line.paidMinor + applied;
        final paymentRef = payments[index];
        tx.update(saleRefs[index], {
          'paidMinor': paidAfter,
          'paymentStatus': paidAfter == line.totalMinor ? 'paid' : 'partially_paid',
          'lastPaymentId': paymentRef.id,
          'lastPaymentAt': FieldValue.serverTimestamp(),
        });
        tx.set(paymentRef, {
          'paymentId': paymentRef.id,
          'saleId': line.id,
          'orderId': line.orderId,
          'sellerUid': line.sellerUid,
          'customerId': line.customerId,
          'customerName': line.customerName,
          'amountMinor': applied,
          'paidBeforeMinor': line.paidMinor,
          'balanceAfterMinor': line.totalMinor - paidAfter,
          'method': method,
          'collectedBy': collector,
          'collectedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
