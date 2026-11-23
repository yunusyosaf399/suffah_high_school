import 'package:cloud_firestore/cloud_firestore.dart';

/// All money is stored in integer minor units (paisa), never floating point.
int financeMinorUnits(String input) {
  final value = input.trim().replaceAll(',', '');
  if (!RegExp(r'^[0-9]+(\.[0-9]{1,2})?$').hasMatch(value)) {
    throw ArgumentError('Enter a positive amount with at most two decimal places.');
  }
  final parts = value.split('.');
  final rupees = int.parse(parts.first);
  final paisa = parts.length == 1
      ? 0
      : int.parse(parts.last.padRight(2, '0'));
  final amount = rupees * 100 + paisa;
  if (amount <= 0 || amount > 100000000000) {
    throw ArgumentError('Enter an amount between Rs 0.01 and Rs 1,000,000,000.');
  }
  return amount;
}

String financeMoney(int minor) {
  final negative = minor < 0;
  final positive = minor.abs();
  final figures = (positive ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < figures.length; i++) {
    if (i > 0 && (figures.length - i) % 3 == 0) buffer.write(',');
    buffer.write(figures[i]);
  }
  return '${negative ? '-' : ''}Rs ${buffer.toString()}.${(positive % 100).toString().padLeft(2, '0')}';
}

String financeMonth(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String previousFinanceMonth(DateTime now) =>
    financeMonth(DateTime(now.year, now.month - 1));

bool financeSalaryMonthAllowed(String month, DateTime now) =>
    month == financeMonth(now) || month == previousFinanceMonth(now);

String financeMonthLabel(String month) {
  final pieces = month.split('-');
  if (pieces.length != 2) return month;
  final index = int.tryParse(pieces[1]);
  if (index == null || index < 1 || index > 12) return month;
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${names[index - 1]} ${pieces[0]}';
}

const financeOneTimeCategories = <String>[
  'Certificate Fee',
  'Uniform Fee',
  'Fines',
  'Examination Fee',
  'Promotions Fee',
  '2nd Time Tuition Fee',
  'Other',
];

const financeExpenseCategories = <String, List<String>>{
  'Utilities': ['WiFi Bill', 'Electricity', 'Water', 'Gas', 'Telephone'],
  'Hospitality': ['Hotel Expenses', 'Guest Refreshments', 'School Events'],
  'Stationery': ['Ink', 'Copy Paper', 'Printer', 'Toner', 'Office Supplies'],
  'Laboratory': ['Lab Equipment', 'Chemicals', 'Repairs'],
  'Examinations': ['Printing', 'Invigilation', 'Exam Materials'],
  'Transport': ['Vehicle Fuel', 'Vehicle Maintenance', 'Tires', 'Driver Allowance'],
  'Uniform & Tailoring': ['Tailor Expenses', 'Fabric', 'Stitching'],
  'Maintenance': ['General Maintenance', 'Building Repair', 'Cleaning'],
  'Staff Support': ['Mobile Packages for Teachers', 'Second Tuition Payment to Teacher'],
  'Building': ['Building Rent', 'Security', 'Property Charges'],
  'Other': ['Other'],
};

const financePaymentMethods = <String>[
  'Cash', 'Bank Transfer', 'Bank Deposit', 'Easypaisa', 'JazzCash', 'Other',
];

class FinanceBill {
  const FinanceBill({
    required this.id,
    required this.amountMinor,
    required this.paidMinor,
    required this.month,
    required this.category,
    required this.title,
    this.subcategory = '',
    this.description = '',
    this.studentId = '',
    this.staffId = '',
    this.studentName = '',
    this.staffName = '',
    this.classId = '',
    this.className = '',
    this.rollNo = '',
    this.basicMinor = 0,
    this.allowanceMinor = 0,
    this.bonusMinor = 0,
  });

  final String id;
  final int amountMinor;
  final int paidMinor;
  final String month;
  final String category;
  final String title;
  final String subcategory;
  final String description;
  final String studentId;
  final String staffId;
  final String studentName;
  final String staffName;
  final String classId;
  final String className;
  final String rollNo;
  final int basicMinor;
  final int allowanceMinor;
  final int bonusMinor;

  int get remainingMinor => amountMinor - paidMinor;
  bool get isPaid => remainingMinor <= 0;

  factory FinanceBill.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => FinanceBill.fromData(snapshot.id,
      snapshot.data() ?? <String, dynamic>{});

  /// Test the same int64 and field names returned by actual Firestore bills
  /// without requiring a live Firebase project in widget/unit tests.
  factory FinanceBill.fromData(String id, Map<String, dynamic> data) {
    return FinanceBill(
      id: id,
      amountMinor: (data['amountMinor'] as num?)?.toInt() ?? 0,
      paidMinor: (data['paidMinor'] as num?)?.toInt() ?? 0,
      month: (data['month'] as String?) ?? '',
      category: (data['category'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      subcategory: (data['subcategory'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      staffId: (data['staffId'] as String?) ?? '',
      studentName: (data['studentName'] as String?) ?? '',
      staffName: (data['staffName'] as String?) ?? '',
      classId: (data['classId'] as String?) ?? '',
      className: (data['className'] as String?) ?? '',
      rollNo: (data['rollNo'] as String?) ?? '',
      basicMinor: (data['basicMinor'] as num?)?.toInt() ?? 0,
      allowanceMinor: (data['allowanceMinor'] as num?)?.toInt() ?? 0,
      bonusMinor: (data['bonusMinor'] as num?)?.toInt() ?? 0,
    );
  }
}

class FinanceEntry {
  const FinanceEntry({
    required this.id,
    required this.direction,
    required this.category,
    required this.amountMinor,
    required this.postedMonth,
    required this.sourceId,
    required this.sourceType,
    required this.displayName,
    required this.createdBy,
    this.subcategory = '',
    this.description = '',
    this.method = '',
    this.reference = '',
    this.payerName = '',
    this.recipientName = '',
    this.createdAt,
  });

  final String id;
  final String direction; // credit = cash in, debit = cash out
  final String category;
  final int amountMinor;
  final String postedMonth;
  final String sourceId;
  final String sourceType;
  final String displayName;
  final String createdBy;
  final String subcategory;
  final String description;
  final String method;
  final String reference;
  final String payerName;
  final String recipientName;
  final DateTime? createdAt;

  factory FinanceEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return FinanceEntry(
      id: snapshot.id,
      direction: (data['direction'] as String?) ?? '',
      category: (data['category'] as String?) ?? '',
      amountMinor: (data['amountMinor'] as num?)?.toInt() ?? 0,
      postedMonth: (data['postedMonth'] as String?) ?? '',
      sourceId: (data['sourceId'] as String?) ?? '',
      sourceType: (data['sourceType'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      subcategory: (data['subcategory'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      method: (data['method'] as String?) ?? '',
      reference: (data['reference'] as String?) ?? '',
      payerName: (data['payerName'] as String?) ?? '',
      recipientName: (data['recipientName'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class FinanceMonthSummary {
  const FinanceMonthSummary({
    required this.month,
    this.creditsMinor = 0,
    this.debitsMinor = 0,
  });
  final String month;
  final int creditsMinor;
  final int debitsMinor;
  int get netMinor => creditsMinor - debitsMinor;
}

class FinanceOverview {
  const FinanceOverview({
    required this.months,
    required this.unpaidFeesMinor,
    required this.unpaidSalariesMinor,
    required this.unpaidExpensesMinor,
    required this.recentEntries,
  });

  final List<FinanceMonthSummary> months;
  final int unpaidFeesMinor;
  final int unpaidSalariesMinor;
  final int unpaidExpensesMinor;
  final List<FinanceEntry> recentEntries;

  int get creditsMinor =>
      months.fold(0, (sum, item) => sum + item.creditsMinor);
  int get debitsMinor =>
      months.fold(0, (sum, item) => sum + item.debitsMinor);
  int get netMinor => creditsMinor - debitsMinor;
}

