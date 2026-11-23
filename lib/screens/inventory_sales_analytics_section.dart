import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/inventory_repository.dart';
import '../data/inventory_sales_analytics.dart';
import '../data/school_errors.dart';

/// Visible inside Finance -> Analytics, independently loaded from finance.
class InventorySalesAnalyticsSection extends StatefulWidget {
  const InventorySalesAnalyticsSection({
    super.key,
    this.repository,
    this.initialData,
  });

  final InventoryAnalyticsRepository? repository;
  final InventorySalesAnalytics? initialData;

  @override
  State<InventorySalesAnalyticsSection> createState() =>
      _InventorySalesAnalyticsSectionState();
}

class _InventorySalesAnalyticsSectionState
    extends State<InventorySalesAnalyticsSection> {
  late final InventoryAnalyticsRepository _repo =
      widget.repository ?? InventoryAnalyticsRepository();
  late Future<InventorySalesAnalytics> _data =
      widget.initialData == null ? _repo.load() : Future.value(widget.initialData);

  void _refresh() => setState(() => _data = _repo.load());

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<InventorySalesAnalytics>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Canteen & Stationery sales analytics',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(schoolErrorMessage(snapshot.error!)),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Retry inventory analytics'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Column(children: [
                ListTile(title: Text('Canteen & Stationery sales analytics')),
                LinearProgressIndicator(),
              ]);
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('Canteen & Stationery sales analytics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800))),
                  IconButton(
                    tooltip: 'Refresh inventory analytics',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text('Last six calendar months: sales value, actual '
                    'cash collected, credit and departmental performance.',
                  style: TextStyle(fontSize: 12)),
                const SizedBox(height: 14),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  _metric('Sales value (6 mo)', data.salesMinor,
                      Icons.trending_up),
                  _metric('Cash collected (6 mo)', data.collectedMinor,
                      Icons.account_balance_wallet_outlined),
                  _metric('Outstanding (available history)', data.outstandingMinor,
                      Icons.pending_actions),
                  _metric('Average basket', data.averageOrderMinor,
                      Icons.shopping_cart_outlined),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 5, children: [
                  Text('${data.orders} receipts (6 mo)'),
                  Text('${data.units} units sold (6 mo)'),
                  Text('${data.outstandingOrders} unpaid receipts (available history)'),
                ]),
                const SizedBox(height: 16),
                Text('Sales vs cash received by month',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.circle, color: Colors.teal.shade700, size: 12),
                  const Text(' Sales', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 18),
                  Icon(Icons.circle, color: Colors.blue.shade700, size: 12),
                  const Text(' Cash received', style: TextStyle(fontSize: 11)),
                ]),
                const SizedBox(height: 12),
                _monthlyChart(data.months),
                const SizedBox(height: 16),
                Text('Department sales (6 mo)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _categoryBar('Canteen', data.canteenMinor, data.salesMinor),
                _categoryBar('Stationery', data.stationeryMinor, data.salesMinor),
                const SizedBox(height: 16),
                Text('Best-selling products by value (6 mo)',
                    style: Theme.of(context).textTheme.titleSmall),
                if (data.topItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No canteen or stationery sales in this period.'),
                  ),
                for (var index = 0; index < data.topItems.length; index++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(radius: 14,
                        child: Text('${index + 1}')),
                    title: Text(data.topItems[index].key),
                    trailing: Text(
                      inventoryRupees(data.topItems[index].value),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Cash received excludes borrowed sales until actually paid. '
                  'Borrowed balances shown here cover available receipts, '
                  'not necessarily all historical records.'
                  '${data.limited ? ' Data limit reached (1,500 sale lines or payments): totals may be incomplete.' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _metric(String label, int minor, IconData icon) => SizedBox(
    width: 170,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(inventoryRupees(minor), style: const TextStyle(
          fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]),
    ),
  );

  Widget _monthlyChart(List<InventorySalesMonth> months) {
    final maxAmount = math.max(1, months.fold(0, (maxValue, month) =>
        math.max(maxValue, math.max(month.salesMinor, month.collectedMinor))));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final month in months)
            SizedBox(width: 66, child: Column(children: [
              SizedBox(height: 118,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 23,
                      height: math.max(3, 108 * month.salesMinor / maxAmount),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 23,
                      height: math.max(3, 108 * month.collectedMinor / maxAmount),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(month.month.substring(5),
                  style: const TextStyle(fontSize: 11)),
            ])),
        ],
      ),
    );
  }

  Widget _categoryBar(String label, int amount, int total) {
    final fraction = total > 0 ? amount / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(inventoryRupees(amount),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 7,
          borderRadius: BorderRadius.circular(6),
        ),
      ]),
    );
  }
}
