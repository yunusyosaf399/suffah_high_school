import 'package:cloud_firestore/cloud_firestore.dart';

class PayrollInput {
  const PayrollInput({
    required this.staffId,
    required this.period,
    required this.basicSalary,
    required this.allowances,
    required this.deductions,
    required this.status,
    required this.paymentMethod,
    this.paidAt = '',
    this.notes = '',
  });

  final String staffId;
  final String period;
  final double basicSalary;
  final double allowances;
  final double deductions;
  final String status;
  final String paymentMethod;
  final String paidAt;
  final String notes;

  double get netSalary => basicSalary + allowances - deductions;

  String? validate() {
    if (staffId.isEmpty || staffId.contains('/')) {
      return 'Select a valid staff member.';
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      return 'Enter the pay period as YYYY-MM.';
    }
    if (basicSalary < 0 || allowances < 0 || deductions < 0) {
      return 'Salary amounts cannot be negative.';
    }
    if (deductions > basicSalary + allowances) {
      return 'Deductions cannot exceed gross salary.';
    }
    if (status != 'paid' && status != 'unpaid') {
      return 'Choose a valid payment status.';
    }
    if (status == 'paid' && paidAt.isEmpty) {
      return 'Enter the payment date for a paid salary.';
    }
    return null;
  }
}

class PayrollRecord {
  const PayrollRecord({
    required this.id,
    required this.receiptNo,
    required this.staffId,
    required this.staffNo,
    required this.staffName,
    required this.period,
    required this.basicSalary,
    required this.allowances,
    required this.deductions,
    required this.netSalary,
    required this.status,
    required this.paidAt,
    required this.paymentMethod,
    required this.notes,
  });

  final String id;
  final String receiptNo;
  final String staffId;
  final String staffNo;
  final String staffName;
  final String period;
  final double basicSalary;
  final double allowances;
  final double deductions;
  final double netSalary;
  final String status;
  final String paidAt;
  final String paymentMethod;
  final String notes;

  factory PayrollRecord.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    String text(String key) => (data[key] as String?) ?? '';
    double amount(String key) => (data[key] as num?)?.toDouble() ?? 0;
    return PayrollRecord(
      id: snapshot.id,
      receiptNo: text('receiptNo'),
      staffId: text('staffId'),
      staffNo: text('staffNo'),
      staffName: text('staffName'),
      period: text('period'),
      basicSalary: amount('basicSalary'),
      allowances: amount('allowances'),
      deductions: amount('deductions'),
      netSalary: amount('netSalary'),
      status: text('status'),
      paidAt: text('paidAt'),
      paymentMethod: text('paymentMethod'),
      notes: text('notes'),
    );
  }
}

String payrollReceiptNumber(int year, int sequence) {
  if (year < 2000 || year > 2200 || sequence < 1 || sequence > 9999) {
    throw ArgumentError('Invalid payroll receipt sequence.');
  }
  return 'SAL-${year}-${sequence.toString().padLeft(4, '0')}';
}

class PayrollRepository {
  PayrollRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<PayrollRecord>> watchPayroll() => _db
      .collection('payroll_records')
      .limit(500)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(PayrollRecord.fromSnapshot).toList());

  Future<String> createRecord(PayrollInput input) async {
    final error = input.validate();
    if (error != null) throw ArgumentError(error);
    final year = DateTime.now().year;
    final counter = _db.collection('counters')
        .doc('payroll_receipt_${year}');
    final receiptRef = _db.collection('payroll_records').doc();
    final staffRef = _db.collection('staff').doc(input.staffId);
    try {
      return await _db.runTransaction((transaction) async {
        final counterSnapshot = await transaction.get(counter);
        final staffSnapshot = await transaction.get(staffRef);
        if (!staffSnapshot.exists || staffSnapshot.data()?['active'] != true) {
          throw StateError('Choose an active staff member.');
        }
        final sequence =
            ((counterSnapshot.data()?['last'] as num?)?.toInt() ?? 0) + 1;
        final receiptNo = payrollReceiptNumber(year, sequence);
        final staff = staffSnapshot.data() ?? <String, dynamic>{};
        transaction.set(counter, {
          'last': sequence,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(receiptRef, {
          'receiptNo': receiptNo,
          'staffId': input.staffId,
          'staffNo': (staff['staffNo'] as String?) ?? input.staffId,
          'staffName': (staff['fullName'] as String?) ?? '',
          'period': input.period,
          'basicSalary': input.basicSalary,
          'allowances': input.allowances,
          'deductions': input.deductions,
          'netSalary': input.netSalary,
          'status': input.status,
          'paidAt': input.paidAt,
          'paymentMethod': input.paymentMethod,
          'notes': input.notes.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return receiptNo;
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'Payroll save was denied. Publish the latest Firestore Rules and sign in as the owner or principal.',
        );
      }
      rethrow;
    }
  }

  Future<void> updatePaymentStatus({
    required String recordId,
    required String status,
    required String paidAt,
    required String paymentMethod,
  }) async {
    if (recordId.isEmpty || recordId.contains('/')) {
      throw ArgumentError('Invalid payroll record.');
    }
    if (status != 'paid' && status != 'unpaid') {
      throw ArgumentError('Invalid payment status.');
    }
    await _db.collection('payroll_records').doc(recordId).update({
      'status': status,
      'paidAt': status == 'paid' ? paidAt : '',
      'paymentMethod': status == 'paid' ? paymentMethod : '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
