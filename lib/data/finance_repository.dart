import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'finance_models.dart';
import 'finance_scheduler_models.dart';
import 'school_repository.dart';
import 'staff_repository.dart';

String financeFeeId(String month, String kind, String studentId) =>
    'FEE-${month.replaceAll('-', '')}-$kind-$studentId';
String financeSalaryId(String month, String staffId) =>
    'SAL-${month.replaceAll('-', '')}-$staffId';
String financeExpenseId(String month, String planId) =>
    'EXP-${month.replaceAll('-', '')}-$planId';

class FinanceGenerationResult {
  const FinanceGenerationResult({
    this.created = 0,
    this.existing = 0,
    this.missingSetup = 0,
  });
  final int created;
  final int existing;
  final int missingSetup;
}

class FinanceRepository {
  FinanceRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _givenDb = firestore, _givenAuth = auth;

  final FirebaseFirestore? _givenDb;
  final FirebaseAuth? _givenAuth;
  // Lazy initialization allows UI/widget tests to inject fake repository methods.
  late final FirebaseFirestore _db =
      _givenDb ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = _givenAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get tuitionRates =>
      _db.collection('finance_tuition_rates');
  CollectionReference<Map<String, dynamic>> get transportRates =>
      _db.collection('finance_transport_rates');
  CollectionReference<Map<String, dynamic>> get salaryRates =>
      _db.collection('finance_salary_rates');
  CollectionReference<Map<String, dynamic>> get recurringPlans =>
      _db.collection('finance_recurring_plans');

  CollectionReference<Map<String, dynamic>> get feeBills =>
      _db.collection('finance_fee_bills');
  CollectionReference<Map<String, dynamic>> get salaryBills =>
      _db.collection('finance_salary_bills');
  CollectionReference<Map<String, dynamic>> get recurringBills =>
      _db.collection('finance_recurring_bills');
  CollectionReference<Map<String, dynamic>> get ledger =>
      _db.collection('finance_ledger');

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before recording finances.');
    return uid;
  }

  Future<List<StudentRecord>> loadStudents() async {
    final snapshot = await _db.collection('students')
        .orderBy('fullName')
        .limit(1000)
        .get(const GetOptions(source: Source.server));
    return snapshot.docs.map(StudentRecord.fromSnapshot)
        .where((s) => s.active && !s.isDraft)
        .toList();
  }

  Future<List<SchoolClass>> loadClasses() async {
    final snap = await _db.collection('classes')
        .get(const GetOptions(source: Source.server));
    final classes = snap.docs.map(SchoolClass.fromSnapshot)
        .where((item) => item.active).toList();
    classes.sort((a, b) => a.label.compareTo(b.label));
    return classes;
  }

  Future<List<StaffMember>> loadTeachers() async {
    final snap = await _db.collection('staff')
        .where('roleType', isEqualTo: 'teacher')
        .limit(500)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map(StaffMember.fromSnapshot)
        .where((s) => s.active).toList();
  }

  Future<Map<String, Map<String, dynamic>>> _rates(
      CollectionReference<Map<String, dynamic>> source) async {
    final snap = await source.limit(1000)
        .get(const GetOptions(source: Source.server));
    return {for (final d in snap.docs) d.id: d.data()};
  }

  Future<Map<String, Map<String, dynamic>>> loadTuitionRates() =>
      _rates(tuitionRates);
  Future<Map<String, Map<String, dynamic>>> loadTransportRates() =>
      _rates(transportRates);
  Future<Map<String, Map<String, dynamic>>> loadSalaryRates() =>
      _rates(salaryRates);

  Future<void> setTuition({
    required SchoolClass schoolClass,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) throw ArgumentError('Tuition must be positive.');
    final ref = tuitionRates.doc(schoolClass.id);
    final uid = _uid;
    await _db.runTransaction((tx) async {
      final previous = await tx.get(ref);
      tx.set(ref, {
        'classId': schoolClass.id,
        'className': schoolClass.label,
        'amountMinor': amountMinor,
        'currency': 'PKR',
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!previous.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<int> setTransport({
    required List<StudentRecord> students,
    required Map<String, SchoolClass> classes,
    required int amountMinor,
  }) async {
    if (amountMinor < 0) throw ArgumentError('Amount cannot be negative.');
    if (students.isEmpty) throw ArgumentError('Choose students first.');
    final uid = _uid;
    var saved = 0;
    for (var start = 0; start < students.length; start += 300) {
      final batch = _db.batch();
      for (final student in students.skip(start).take(300)) {
        batch.set(transportRates.doc(student.id), {
          'studentId': student.id,
          'studentName': student.fullName,
          'classId': student.classId,
          'className': classes[student.classId]?.label ?? student.classId,
          'amountMinor': amountMinor,
          'active': amountMinor > 0,
          'currency': 'PKR',
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        saved++;
      }
      await batch.commit();
    }
    return saved;
  }

  /// No ledger entry is created while fees are generated.
  /// Deterministic IDs make repeating the operation safe.
  Future<FinanceGenerationResult> generateFees({
    required String month,
    required bool tuition,
    required bool transport,
  }) async {
    _requireGenerationMonth(month);
    if (!tuition && !transport) {
      throw ArgumentError('Select tuition, transport, or both.');
    }
    // Start independent setup reads together instead of waiting for four
    // separate network round trips.
    final studentsRequest = loadStudents();
    final classesRequest = loadClasses();
    final tuitionRequest = tuition
        ? loadTuitionRates()
        : Future.value(<String, Map<String, dynamic>>{});
    final transportRequest = transport
        ? loadTransportRates()
        : Future.value(<String, Map<String, dynamic>>{});
    final students = await studentsRequest;
    final classes = {for (final c in await classesRequest) c.id: c};
    final tuitionSetup = await tuitionRequest;
    final transportSetup = await transportRequest;
    final prepared = <({String id, Map<String, dynamic> data})>[];
    var missing = 0;
    final uid = _uid;
    for (final student in students) {
      if (!classes.containsKey(student.classId)) continue;
      for (final kind in ['tuition', 'transport']) {
        if (kind == 'tuition' && !tuition ||
            kind == 'transport' && !transport) continue;
        final source = kind == 'tuition'
            ? tuitionSetup[student.classId]
            : transportSetup[student.id];
        final amount = (source?['amountMinor'] as num?)?.toInt() ?? 0;
        if (amount <= 0 || (kind == 'transport' && source?['active'] == false)) {
          missing++;
          continue;
        }
        final id = financeFeeId(month, kind, student.id);
        prepared.add((id: id, data: {
          'billId': id,
          'month': month,
          'category': kind,
          'subcategory': '',
          'title': kind == 'tuition' ? 'Monthly tuition' : 'Monthly transport',
          'description': '',
          'studentId': student.id,
          'studentName': student.fullName,
          'rollNo': student.rollNo,
          'classId': student.classId,
          'className': classes[student.classId]!.label,
          'amountMinor': amount,
          'paidMinor': 0,
          'status': 'unpaid',
          'currency': 'PKR',
          'sourceRateId': kind == 'tuition' ? student.classId : student.id,
          'generatedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
    }
    var created = 0;
    var existing = 0;
    // Read-before-write for every transaction; no paid amounts are overwritten.
    for (var start = 0; start < prepared.length; start += 30) {
      final part = prepared.skip(start).take(30).toList();
      final counts = await _db.runTransaction((tx) async {
        final existingDocs = await Future.wait(
          part.map((item) => tx.get(feeBills.doc(item.id))),
        );
        var newCount = 0;
        for (var i = 0; i < part.length; i++) {
          if (existingDocs[i].exists) continue;
          tx.set(feeBills.doc(part[i].id), part[i].data);
          newCount++;
        }
        return newCount;
      });
      created += counts;
      existing += part.length - counts;
    }
    return FinanceGenerationResult(
      created: created, existing: existing, missingSetup: missing);
  }

  Future<int> createOneTimeFees({
    required String category,
    required String description,
    required int amountMinor,
    required List<StudentRecord> students,
    required Map<String, SchoolClass> classes,
  }) async {
    if (!financeOneTimeCategories.contains(category)) {
      throw ArgumentError('Select an approved one-time fee category.');
    }
    if (category == 'Other' && description.trim().isEmpty) {
      throw ArgumentError('A description is required for Other fees.');
    }
    if (students.isEmpty || amountMinor <= 0) {
      throw ArgumentError('Choose students and a positive fee.');
    }
    final groupId = feeBills.doc().id;
    final uid = _uid;
    final month = financeMonth(DateTime.now());
    for (var start = 0; start < students.length; start += 300) {
      final batch = _db.batch();
      for (final student in students.skip(start).take(300)) {
        final ref = feeBills.doc('ONE-$groupId-${student.id}');
        batch.set(ref, {
          'billId': ref.id,
          'batchId': groupId,
          'month': month,
          'category': 'one_time',
          'subcategory': category,
          'title': category,
          'description': description.trim(),
          'studentId': student.id,
          'studentName': student.fullName,
          'rollNo': student.rollNo,
          'classId': student.classId,
          'className': classes[student.classId]?.label ?? student.classId,
          'amountMinor': amountMinor,
          'paidMinor': 0,
          'status': 'unpaid',
          'currency': 'PKR',
          'generatedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    return students.length;
  }

  Future<void> setSalary({
    required StaffMember teacher,
    required int basicMinor,
    required int allowanceMinor,
    required int bonusMinor,
    required String notes,
  }) async {
    if (!teacher.isTeacher || !teacher.active ||
        basicMinor <= 0 || allowanceMinor < 0 || bonusMinor < 0) {
      throw ArgumentError('Enter a valid active teacher and salary amounts.');
    }
    await salaryRates.doc(teacher.id).set({
      'staffId': teacher.id,
      'staffName': teacher.fullName,
      'basicMinor': basicMinor,
      'allowanceMinor': allowanceMinor,
      'bonusMinor': bonusMinor,
      'amountMinor': basicMinor + allowanceMinor + bonusMinor,
      'notes': notes.trim(),
      'currency': 'PKR',
      'updatedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<FinanceGenerationResult> generateSalaries(String month) async {
    _requireGenerationMonth(month);
    final teachersRequest = loadTeachers();
    final ratesRequest = loadSalaryRates();
    final teachers = await teachersRequest;
    final rates = await ratesRequest;
    final uid = _uid;
    final prepared = <({String id, Map<String, dynamic> data})>[];
    var missing = 0;
    for (final teacher in teachers) {
      final rate = rates[teacher.id];
      final amount = (rate?['amountMinor'] as num?)?.toInt() ?? 0;
      if (amount <= 0) { missing++; continue; }
      final id = financeSalaryId(month, teacher.id);
      prepared.add((id: id, data: {
        'billId': id,
        'month': month,
        'category': 'salary',
        'title': 'Monthly salary',
        'staffId': teacher.id,
        'staffName': teacher.fullName,
        'basicMinor': (rate?['basicMinor'] as num?)?.toInt() ?? 0,
        'allowanceMinor': (rate?['allowanceMinor'] as num?)?.toInt() ?? 0,
        'bonusMinor': (rate?['bonusMinor'] as num?)?.toInt() ?? 0,
        'description': (rate?['notes'] as String?) ?? '',
        'amountMinor': amount,
        'paidMinor': 0,
        'status': 'unpaid',
        'currency': 'PKR',
        'generatedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    }
    var created = 0;
    for (var start = 0; start < prepared.length; start += 30) {
      final chunk = prepared.skip(start).take(30).toList();
      created += await _db.runTransaction((tx) async {
        final existing = await Future.wait(
          chunk.map((item) => tx.get(salaryBills.doc(item.id))),
        );
        var added = 0;
        for (var i = 0; i < chunk.length; i++) {
          if (existing[i].exists) continue;
          tx.set(salaryBills.doc(chunk[i].id), chunk[i].data);
          added++;
        }
        return added;
      });
    }
    return FinanceGenerationResult(
      created: created, existing: prepared.length - created,
      missingSetup: missing);
  }

  Future<String> setRecurringExpense({
    String? existingId,
    required String name,
    required String category,
    required String subcategory,
    required String description,
    required int amountMinor,
    required int scheduleDay,
  }) async {
    if (name.trim().isEmpty || amountMinor <= 0 || scheduleDay < 1 ||
        scheduleDay > 27 || !financeExpenseCategories.containsKey(category)) {
      throw ArgumentError('Enter expense details and a day from 1 to 27.');
    }
    final ref = existingId == null ? recurringPlans.doc()
        : recurringPlans.doc(existingId);
    await ref.set({
      'planId': ref.id,
      'name': name.trim(),
      'category': category,
      'subcategory': subcategory,
      'description': description.trim(),
      'amountMinor': amountMinor,
      'scheduleDay': scheduleDay,
      'active': true,
      // No background worker is deployed. This is a future scheduling setting.
      'automaticEnabled': false,
      'currency': 'PKR',
      'updatedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> disableRecurringExpense(String planId) =>
      recurringPlans.doc(planId).update({
        'active': false,
        'automaticEnabled': false,
        'updatedBy': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<FinanceGenerationResult> generateRecurringExpenses(String month) async {
    _requireGenerationMonth(month);
    final snapshots = await recurringPlans.where('active', isEqualTo: true)
        .limit(500).get(const GetOptions(source: Source.server));
    final uid = _uid;
    final plans = snapshots.docs;
    var created = 0;
    for (var start = 0; start < plans.length; start += 30) {
      final chunk = plans.skip(start).take(30).toList();
      created += await _db.runTransaction((tx) async {
        final newDocs = <({String id, Map<String, dynamic> data})>[];
        for (final item in chunk) {
          final id = financeExpenseId(month, item.id);
          if ((await tx.get(recurringBills.doc(id))).exists) continue;
          final data = item.data();
          newDocs.add((id: id, data: {
            'billId': id, 'planId': item.id, 'month': month,
            'category': 'expense', 'subcategory': data['subcategory'] ?? '',
            'expenseCategory': data['category'] ?? 'Other',
            'title': data['name'] ?? '',
            'description': data['description'] ?? '',
            'amountMinor': data['amountMinor'] ?? 0,
            'paidMinor': 0, 'status': 'unpaid', 'currency': 'PKR',
            'generatedBy': uid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }));
        }
        for (final item in newDocs) {
          tx.set(recurringBills.doc(item.id), item.data);
        }
        return newDocs.length;
      });
    }
    return FinanceGenerationResult(
      created: created, existing: plans.length - created);
  }

  void _requireGenerationMonth(String month) {
    if (!financeSalaryMonthAllowed(month, DateTime.now())) {
      throw ArgumentError('Generate for the current or previous month only.');
    }
  }

  Stream<List<FinanceBill>> watchFeeBills() => feeBills
      .orderBy('createdAt', descending: true)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs.map(FinanceBill.fromSnapshot).toList());

  /// Reads the same collection written by generateSalaries(). A direct
  /// server read provides a clear success/error result for salary payments
  /// and never silently substitutes possibly stale cached balances.
  Future<List<FinanceBill>> loadSalaryBills() async {
    final snapshot = await salaryBills.limit(600)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return _sortedSalaryBills(
      snapshot.docs.map(FinanceBill.fromSnapshot).toList(),
    );
  }

  /// Read-only diagnostic: compare a single document GET against the salary
  /// collection LIST query. Firestore rules can authorize them separately.
  /// Never writes, regenerates, or updates existing salary records.
  Future<FinanceBill?> probeSalaryBill(String billId) async {
    final normalized = billId.trim();
    if (normalized.isEmpty || normalized.contains('/')) {
      throw ArgumentError('Enter a valid salary bill ID.');
    }
    final snapshot = await salaryBills.doc(normalized)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return snapshot.exists ? FinanceBill.fromSnapshot(snapshot) : null;
  }

  /// Do not order the query by createdAt: legacy or partially migrated
  /// salary bills can lack that field and Firestore would silently omit them.
  /// Sort the small salary result set locally by month, then teacher.
  Stream<List<FinanceBill>> watchSalaryBills() => salaryBills
      .limit(600)
      .snapshots()
      .map((snapshot) => _sortedSalaryBills(
        snapshot.docs.map(FinanceBill.fromSnapshot).toList(),
      ));

  static List<FinanceBill> _sortedSalaryBills(List<FinanceBill> bills) {
    bills.sort((a, b) {
      final byMonth = b.month.compareTo(a.month);
      return byMonth != 0
          ? byMonth
          : a.staffName.toLowerCase().compareTo(b.staffName.toLowerCase());
    });
    return bills;
  }

  Stream<List<FinanceBill>> watchRecurringBills() => recurringBills
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(FinanceBill.fromSnapshot).toList());

  Stream<List<FinanceEntry>> watchLedger() => ledger
      .orderBy('createdAt', descending: true)
      .limit(120)
      .snapshots()
      .map((s) => s.docs.map(FinanceEntry.fromSnapshot).toList());

  /// A receipt and the paid balance are committed atomically. No amount may
  /// exceed what is still owed; transaction retry rechecks the fresh balance.
  Future<String> collectFee({
    required String billId,
    required int amountMinor,
    required String method,
    String reference = '',
    String notes = '',
    String payerName = '',
  }) => _payBill(
    collection: feeBills, billId: billId, amountMinor: amountMinor,
    method: method, reference: reference, notes: notes,
    direction: 'credit', sourceType: 'fee',
    payerName: payerName,
  );

  Future<String> paySalary({
    required String billId,
    required int amountMinor,
    required String method,
    String reference = '',
    String notes = '',
  }) => _payBill(
    collection: salaryBills, billId: billId, amountMinor: amountMinor,
    method: method, reference: reference, notes: notes,
    direction: 'debit', sourceType: 'salary',
  );

  Future<String> payRecurringExpense({
    required String billId,
    required int amountMinor,
    required String method,
    String reference = '',
    String notes = '',
  }) => _payBill(
    collection: recurringBills, billId: billId, amountMinor: amountMinor,
    method: method, reference: reference, notes: notes,
    direction: 'debit', sourceType: 'recurring_expense',
  );

  Future<String> _payBill({
    required CollectionReference<Map<String, dynamic>> collection,
    required String billId,
    required int amountMinor,
    required String method,
    required String reference,
    required String notes,
    required String direction,
    required String sourceType,
    String payerName = '',
  }) async {
    if (amountMinor <= 0 || !financePaymentMethods.contains(method)) {
      throw ArgumentError('Enter a positive payment and valid method.');
    }
    final uid = _uid;
    final billRef = collection.doc(billId);
    final txRef = ledger.doc();
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(billRef);
      if (!snapshot.exists) throw StateError('This bill was not found.');
      final data = snapshot.data()!;
      final total = (data['amountMinor'] as num?)?.toInt() ?? 0;
      final paid = (data['paidMinor'] as num?)?.toInt() ?? 0;
      if (amountMinor > total - paid) {
        throw StateError('Payment exceeds remaining balance '
            '(${financeMoney(total - paid)}). Reload and try again.');
      }
      final updatedPaid = paid + amountMinor;
      tx.update(billRef, {
        'paidMinor': updatedPaid,
        'lastPaymentId': txRef.id,
        'status': updatedPaid == total ? 'paid' : 'partial',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
      tx.set(txRef, {
        'entryId': txRef.id,
        'direction': direction,
        'category': sourceType == 'fee' ? (data['category'] ?? 'one_time')
            : sourceType == 'salary' ? 'salary' : 'expense',
        'subcategory': data['subcategory'] ?? '',
        'sourceType': sourceType,
        'sourceId': billId,
        'amountMinor': amountMinor,
        'currency': 'PKR',
        'displayName': data['studentName'] ?? data['staffName'] ??
            data['title'] ?? '',
        'payerName': sourceType == 'fee'
            ? (payerName.trim().isEmpty
                ? (data['studentName'] ?? '')
                : payerName.trim())
            : '',
        'recipientName': sourceType == 'salary'
            ? (data['staffName'] ?? '')
            : sourceType == 'recurring_expense'
                ? (data['title'] ?? '') : '',
        'studentId': data['studentId'] ?? '',
        'staffId': data['staffId'] ?? '',
        'classId': data['classId'] ?? '',
        'className': data['className'] ?? '',
        'billMonth': data['month'] ?? '',
        'postedMonth': financeMonth(DateTime.now()),
        'method': method,
        'reference': reference.trim(),
        'description': notes.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
      });
    });
    return txRef.id;
  }

  /// Direct expenses are real cash outflows, not generated payables.
  Future<String> recordExpense({
    required String category,
    required String subcategory,
    required String description,
    required int amountMinor,
    required String method,
    String reference = '',
  }) async {
    if (!financeExpenseCategories.containsKey(category) ||
        !financeExpenseCategories[category]!.contains(subcategory) ||
        amountMinor <= 0 || !financePaymentMethods.contains(method) ||
        (subcategory == 'Other' && description.trim().isEmpty)) {
      throw ArgumentError('Enter a category, subcategory and positive expense.');
    }
    final uid = _uid;
    final ref = ledger.doc();
    await ref.set({
      'entryId': ref.id,
      'direction': 'debit',
      'category': 'expense',
      'subcategory': subcategory,
      'expenseCategory': category,
      'sourceType': 'direct_expense',
      'sourceId': ref.id,
      'amountMinor': amountMinor,
      'currency': 'PKR',
      'displayName': subcategory,
      'payerName': '',
      'recipientName': '',
      'studentId': '',
      'staffId': '',
      'classId': '',
      'className': '',
      'billMonth': '',
      'postedMonth': financeMonth(DateTime.now()),
      'method': method,
      'reference': reference.trim(),
      'description': description.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
    });
    return ref.id;
  }

  Future<FinanceOverview> loadOverview({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--)
        financeMonth(DateTime(now.year, now.month - i)),
    ];
    final from = months.first;
    final results = await Future.wait([
      ledger.where('postedMonth', isGreaterThanOrEqualTo: from)
          .limit(3000).get(const GetOptions(source: Source.server)),
      feeBills.where('month', isGreaterThanOrEqualTo: from)
          .limit(4000).get(const GetOptions(source: Source.server)),
      salaryBills.where('month', isGreaterThanOrEqualTo: from)
          .limit(1200).get(const GetOptions(source: Source.server)),
      recurringBills.where('month', isGreaterThanOrEqualTo: from)
          .limit(1200).get(const GetOptions(source: Source.server)),
    ]);
    final entries = results[0].docs.map(FinanceEntry.fromSnapshot).toList();
    final credits = <String, int>{};
    final debits = <String, int>{};
    for (final entry in entries) {
      final target = entry.direction == 'credit' ? credits : debits;
      target.update(entry.postedMonth,
          (old) => old + entry.amountMinor, ifAbsent: () => entry.amountMinor);
    }
    int outstanding(int index) => results[index].docs.fold<int>(0, (sum, doc) {
      final bill = FinanceBill.fromSnapshot(doc);
      return sum + (bill.remainingMinor > 0 ? bill.remainingMinor : 0);
    });
    entries.sort((a, b) {
      final left = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final right = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    return FinanceOverview(
      months: [
        for (final month in months)
          FinanceMonthSummary(
            month: month,
            creditsMinor: credits[month] ?? 0,
            debitsMinor: debits[month] ?? 0,
          ),
      ],
      unpaidFeesMinor: outstanding(1),
      unpaidSalariesMinor: outstanding(2),
      unpaidExpensesMinor: outstanding(3),
      recentEntries: entries.take(20).toList(),
    );
  }

  /// Finance automatic generation configuration and trusted worker status.
  /// On projects without the backend runtime rules, only the heartbeat
  /// read may be denied; keep configuration editable and show 'not deployed'.
  Future<FinanceAutomationSnapshot> loadFinanceAutomation() async {
    final settingsFuture = _db.collection('finance_generation_settings')
        .get(const GetOptions(source: Source.server));
    final plansFuture = recurringPlans.limit(500)
        .get(const GetOptions(source: Source.server));
    final runtimeFuture = _loadFinanceWorkerStatus();

    final settings = await settingsFuture;
    final plans = await plansFuture;
    final runtime = await runtimeFuture;
    return FinanceAutomationSnapshot(
      preferences: {
        for (final name in financeSchedulerCategories.keys)
          name: FinanceAutomationPreference(
            category: name,
            scheduleDay: (settings.docs
                    .where((doc) => doc.id == name)
                    .firstOrNull?.data()['scheduleDay'] as num?)?.toInt() ?? 1,
            automaticEnabled: settings.docs
                    .where((doc) => doc.id == name)
                    .firstOrNull?.data()['automaticEnabled'] == true,
          ),
      },
      plans: [
        for (final doc in plans.docs)
          FinanceAutomationPlan(
            id: doc.id,
            name: (doc.data()['name'] as String?) ?? 'Monthly expense',
            amountMinor: (doc.data()['amountMinor'] as num?)?.toInt() ?? 0,
            scheduleDay: (doc.data()['scheduleDay'] as num?)?.toInt() ?? 1,
            active: doc.data()['active'] == true,
            automaticEnabled: doc.data()['automaticEnabled'] == true,
          ),
      ],
      lastHeartbeat: (runtime?['lastHeartbeatAt'] as Timestamp?)?.toDate(),
      lastCompleted: (runtime?['lastCompletedAt'] as Timestamp?)?.toDate(),
    );
  }

  Future<Map<String, dynamic>?> _loadFinanceWorkerStatus() async {
    try {
      final doc = await _db.collection('finance_scheduler_runtime')
          .doc('status').get(const GetOptions(source: Source.server));
      return doc.data();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        // Rules have not been published or Functions have not run.
        return null;
      }
      rethrow;
    }
  }

  /// Saving a preference is not proof of live background execution.
  Future<void> saveGenerationSchedules(
      Map<String, FinanceAutomationPreference> preferences) async {
    if (preferences.isEmpty) return;
    for (final item in preferences.entries) {
      if (!financeSchedulerCategories.containsKey(item.key) ||
          item.value.category != item.key ||
          item.value.scheduleDay < 1 || item.value.scheduleDay > 27) {
        throw ArgumentError('Choose a finance type and day from 1 to 27.');
      }
    }
    final uid = _uid;
    final batch = _db.batch();
    for (final item in preferences.entries) {
      batch.set(_db.collection('finance_generation_settings').doc(item.key), {
        'category': item.key,
        'scheduleDay': item.value.scheduleDay,
        'automaticEnabled': item.value.automaticEnabled,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> saveRecurringAutomation({
    required String planId,
    required int scheduleDay,
    required bool automaticEnabled,
  }) async {
    if (planId.isEmpty || planId.contains('/') ||
        scheduleDay < 1 || scheduleDay > 27) {
      throw ArgumentError('Choose a valid expense plan and day from 1 to 27.');
    }
    await recurringPlans.doc(planId).update({
      'scheduleDay': scheduleDay,
      'automaticEnabled': automaticEnabled,
      'updatedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stored as scheduling preferences only. Actual automation requires
  /// a deployed trusted Cloud Scheduler / Firebase Functions worker.
  Future<Map<String, int>> loadGenerationDays() async {
    final snap = await _db.collection('finance_generation_settings')
        .get(const GetOptions(source: Source.server));
    return {
      for (final doc in snap.docs)
        doc.id: (doc.data()['scheduleDay'] as num?)?.toInt() ?? 1,
    };
  }

  Future<void> saveGenerationDay({
    required String category,
    required int scheduleDay,
  }) => saveGenerationSchedules({
        category: FinanceAutomationPreference(
          category: category,
          scheduleDay: scheduleDay,
          automaticEnabled: false,
        ),
      });

  Future<Map<String, dynamic>?> loadDashboardPreferences() async {
    final doc = await _db.collection('finance_dashboard_preferences')
        .doc(_uid).get(const GetOptions(source: Source.server));
    return doc.data();
  }

  Future<void> saveDashboardPreferences({
    required List<String> visibleCards,
    required bool rotate,
  }) async {
    const allowed = ['credit', 'debit', 'net', 'fees', 'salaries', 'expenses'];
    if (visibleCards.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Invalid dashboard metric.');
    }
    await _db.collection('finance_dashboard_preferences').doc(_uid).set({
      'uid': _uid,
      'visibleCards': visibleCards,
      'rotate': rotate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
