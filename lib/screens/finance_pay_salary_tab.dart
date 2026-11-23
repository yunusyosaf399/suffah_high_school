import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/school_errors.dart';
import '../data/school_user_service.dart' show schoolOwnerUid;
import 'finance_fees_tab.dart';

/// A dedicated payroll payments page: one scroll owner, indexed salary rows,
/// no nested scrolling widgets and no conditional collection-for children.
/// Generation remains completely separate from confirmed debit payments.
class FinancePaySalaryTab extends StatefulWidget {
  const FinancePaySalaryTab({
    super.key,
    required this.repository,
    this.onSwipePrevious,
    this.onSwipeNext,
  });

  final FinanceRepository repository;
  final VoidCallback? onSwipePrevious;
  final VoidCallback? onSwipeNext;

  @override
  State<FinancePaySalaryTab> createState() => _FinancePaySalaryTabState();
}

class _FinancePaySalaryTabState extends State<FinancePaySalaryTab> {
  List<FinanceBill> _bills = const [];
  Object? _readError;
  bool _loading = true;
  bool _includePaid = false;
  String _query = '';
  String _month = 'all';
  int _requestNumber = 0;
  double _horizontalSwipeDistance = 0;

  @override
  void initState() {
    super.initState();
    _loadBills(initial: true);
  }

  @override
  void didUpdateWidget(covariant FinancePaySalaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _loadBills();
  }

  @override
  void dispose() {
    _requestNumber++;
    super.dispose();
  }

  Future<void> _loadBills({bool initial = false}) async {
    final request = ++_requestNumber;
    if (!initial && mounted) {
      setState(() {
        _loading = true;
        _readError = null;
      });
    }
    try {
      final fetched = await widget.repository.loadSalaryBills()
          .timeout(const Duration(seconds: 24));
      if (!mounted || request != _requestNumber) return;
      setState(() {
        _bills = fetched;
        _readError = null;
        _loading = false;
        if (_month != 'all' &&
            !_bills.any((bill) => bill.month == _month)) {
          _month = 'all';
        }
      });
    } catch (error) {
      if (!mounted || request != _requestNumber) return;
      setState(() {
        _readError = error;
        _loading = false;
      });
    }
  }

  Future<void> _pay(FinanceBill bill) async {
    final receipt = await showDialog<String>(
      context: context,
      builder: (_) => FinancePaymentDialog(
        bill: bill,
        title: 'Pay teacher salary',
        submitLabel: 'Pay salary & record debit',
        onPay: (amount, method, reference, notes, payerName) =>
            widget.repository.paySalary(
              billId: bill.id,
              amountMinor: amount,
              method: method,
              reference: reference,
              notes: notes,
            ),
      ),
    );
    if (receipt != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salary debit recorded. Receipt: $receipt')),
      );
      await _loadBills();
    }
  }

  String _connectionDetails() {
    try {
      final projectId = Firebase.app().options.projectId;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final account = uid == null
          ? 'signed out'
          : uid == schoolOwnerUid
              ? 'registered owner'
              : 'account …${uid.substring(uid.length > 5 ? uid.length - 5 : 0)}';
      return 'Project: $projectId · $account';
    } catch (_) {
      return 'Firebase connection details unavailable in test mode';
    }
  }

  Future<void> _probeSalaryDocument() async {
    var billId = 'SAL-202611-EMP-2026-0001';
    String? result;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          scrollable: true,
          title: const Text('Check a saved salary document'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Read-only Firestore check. No salary balances or receipts '
                'will be changed.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                _connectionDetails(),
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('salary_probe_document_id'),
                initialValue: billId,
                decoration: const InputDecoration(
                    labelText: 'Exact salary bill document ID'),
                onChanged: (value) => billId = value,
              ),
              if (result != null) ...[
                const SizedBox(height: 12),
                SelectableText(result!, key: const Key('salary_probe_result')),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const Key('salary_probe_read'),
              onPressed: busy ? null : () async {
                updateDialog(() {
                  busy = true;
                  result = 'Checking saved salary document…';
                });
                try {
                  final bill = await widget.repository.probeSalaryBill(billId);
                  if (!dialogContext.mounted) return;
                  updateDialog(() {
                    result = bill == null
                        ? 'Document GET succeeded but no document has that ID.'
                        : 'Document GET succeeded.\n'
                          'Teacher: ${bill.staffName}\n'
                          'Month: ${bill.month}\n'
                          'Remaining: ${financeMoney(bill.remainingMinor)}';
                    busy = false;
                  });
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  updateDialog(() {
                    result = 'Document GET failed: ${schoolErrorMessage(error)}';
                    busy = false;
                  });
                }
              },
              icon: const Icon(Icons.search),
              label: const Text('Check document'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSwipe(DragEndDetails details) {
    final speed = details.primaryVelocity ?? 0;
    if (_horizontalSwipeDistance > 75 || speed > 400) {
      widget.onSwipePrevious?.call();
    } else if (_horizontalSwipeDistance < -75 || speed < -400) {
      widget.onSwipeNext?.call();
    }
    _horizontalSwipeDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final months = _bills
        .map((bill) => bill.month)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final records = _bills.where((bill) {
      if (!_includePaid && bill.isPaid) return false;
      if (_month != 'all' && bill.month != _month) return false;
      final q = _query;
      return q.isEmpty ||
          bill.staffName.toLowerCase().contains(q) ||
          bill.staffId.toLowerCase().contains(q) ||
          bill.month.toLowerCase().contains(q) ||
          bill.id.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final month = b.month.compareTo(a.month);
        return month == 0
            ? a.staffName.toLowerCase().compareTo(b.staffName.toLowerCase())
            : month;
      });
    final unpaid = _bills.where((bill) => !bill.isPaid).toList();
    final outstanding = unpaid.fold<int>(
      0, (sum, bill) => sum + bill.remainingMinor);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (widget.onSwipePrevious != null ||
              widget.onSwipeNext != null)
          ? (_) => _horizontalSwipeDistance = 0 : null,
      onHorizontalDragUpdate: (widget.onSwipePrevious != null ||
              widget.onSwipeNext != null)
          ? (detail) => _horizontalSwipeDistance += detail.primaryDelta ?? 0
          : null,
      onHorizontalDragEnd: (widget.onSwipePrevious != null ||
              widget.onSwipeNext != null)
          ? _handleSwipe : null,
      child: RefreshIndicator(
        onRefresh: _loadBills,
        child: CustomScrollView(
          key: const Key('salary_pay_scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  key: const Key('salary_pay_header'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pay monthly salaries',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                'Review salary balances and record payments.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const Key('finance_salary_probe'),
                          tooltip: 'Check a saved salary bill',
                          onPressed: _probeSalaryDocument,
                          icon: const Icon(Icons.manage_search_outlined),
                        ),
                        IconButton(
                          key: const Key('finance_refresh_salaries'),
                          tooltip: 'Refresh salary bills',
                          onPressed: _loadBills,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: _PayrollSummaryTile(
                          label: 'Outstanding salary',
                          value: financeMoney(outstanding),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PayrollSummaryTile(
                          label: 'Unpaid bills',
                          value: '${unpaid.length}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('salary_bill_search'),
                      decoration: InputDecoration(
                        hintText: 'Teacher, month or salary ID',
                        labelText: 'Search salaries',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('salary_month_$_month'),
                          initialValue: _month,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Salary month',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all', child: Text('All months')),
                            for (final month in months)
                              DropdownMenuItem(
                                value: month,
                                child: Text(financeMonthLabel(month),
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _month = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Checkbox(
                            key: const Key('salary_show_paid_checkbox'),
                            value: _includePaid,
                            onChanged: (value) =>
                                setState(() => _includePaid = value ?? false),
                          ),
                          Flexible(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _includePaid = !_includePaid),
                              child: const Text('Show fully paid salaries',
                                maxLines: 2,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: Text(
                          _loading
                              ? 'Read status: Loading saved salaries…'
                              : _readError != null
                                  ? 'Read status: Failed to load salaries'
                                  : 'Read status: ${_bills.length} saved salaries loaded · '
                                    '${records.length} shown',
                          key: const Key('salary_read_status'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _readError == null
                                ? scheme.onSurfaceVariant : scheme.error,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    // Stable source/version marker, deliberately below the
                    // filters rather than interspersed among payment cards.
                    Text(
                      'Payroll · Finance salary bills · Redesign v5',
                      key: const Key('salary_server_view_version'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                    key: Key('salary_server_loading')),
                ),
              )
            else if (_readError != null)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    key: const Key('salary_server_error'),
                    children: [
                      Icon(Icons.cloud_off_outlined, color: scheme.error,
                        size: 36),
                      const SizedBox(height: 12),
                      const Text('Unable to load saved salary bills'),
                      const SizedBox(height: 8),
                      Text(schoolErrorMessage(_readError!),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('finance_salary_retry'),
                        onPressed: _loadBills,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry loading salaries'),
                      ),
                    ],
                  ),
                ),
              )
            else if (records.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    key: const Key('salary_server_empty'),
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 10),
                      Text(
                        _query.isNotEmpty ? 'No matching salaries'
                            : _bills.isEmpty
                                ? 'No generated salary bills found'
                                : 'No unpaid salaries in this view',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _bills.isEmpty
                            ? 'Generate Finance creates salary bills. '
                              'Payments are recorded separately.'
                            : 'Change the month, search or paid filter.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Salary bills',
                    key: const Key('salary_results_heading'),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final bill = records[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SalaryPaymentCard(
                          key: Key('salary_bill_${bill.id}'),
                          bill: bill,
                          onPay: () => _pay(bill),
                        ),
                      );
                    },
                    childCount: records.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayrollSummaryTile extends StatelessWidget {
  const _PayrollSummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SalaryPaymentCard extends StatelessWidget {
  const _SalaryPaymentCard({
    super.key,
    required this.bill,
    required this.onPay,
  });

  final FinanceBill bill;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final double paidPercent = bill.amountMinor > 0
        ? (bill.paidMinor / bill.amountMinor).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final isPartial = bill.paidMinor > 0 && !bill.isPaid;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.person_outline, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.staffName.isEmpty ? 'Teacher ${bill.staffId}' : bill.staffName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(financeMonthLabel(bill.month),
                    style: theme.textTheme.bodySmall),
              ],
            )),
            const SizedBox(width: 8),
            Text(
              bill.isPaid ? 'Paid' : isPartial ? 'Partial' : 'Unpaid',
              style: theme.textTheme.labelSmall?.copyWith(
                color: bill.isPaid ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 5, children: [
            Text('Basic ${financeMoney(bill.basicMinor)}',
                style: theme.textTheme.bodySmall),
            Text('Allowance ${financeMoney(bill.allowanceMinor)}',
                style: theme.textTheme.bodySmall),
            Text('Bonus ${financeMoney(bill.bonusMinor)}',
                style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: paidPercent,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 6),
          Text(
            'Total ${financeMoney(bill.amountMinor)} · '
            'Paid ${financeMoney(bill.paidMinor)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remaining balance',
                    style: theme.textTheme.labelSmall),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    financeMoney(bill.remainingMinor > 0
                        ? bill.remainingMinor : 0),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: bill.isPaid ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            )),
            const SizedBox(width: 12),
            if (bill.isPaid)
              Icon(Icons.check_circle_outline, color: scheme.primary)
            else
              FilledButton.icon(
                key: Key('finance_pay_salary_${bill.id}'),
                onPressed: onPay,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Pay salary'),
              ),
          ]),
        ]),
      ),
    );
  }
}
