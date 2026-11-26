import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/inventory_department_analytics.dart';
import '../data/inventory_repository.dart';
import '../data/school_errors.dart';

/// Private financial analytics for the selected inventory department.
class InventoryDepartmentAnalyticsTab extends StatefulWidget {
  const InventoryDepartmentAnalyticsTab({
    super.key,
    required this.department,
    this.repository,
  });
  final String department;
  final InventoryDepartmentAnalyticsRepository? repository;

  @override
  State<InventoryDepartmentAnalyticsTab> createState() =>
      _InventoryDepartmentAnalyticsTabState();
}

class _InventoryDepartmentAnalyticsTabState
    extends State<InventoryDepartmentAnalyticsTab> {
  late final InventoryDepartmentAnalyticsRepository _repo =
      widget.repository ?? InventoryDepartmentAnalyticsRepository();
  InventoryReportPeriod _period = InventoryReportPeriod.month;
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  late Future<InventoryDepartmentAnalytics> _future = _load();

  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Future<InventoryDepartmentAnalytics> _load() => _repo.load(
    department: widget.department,
    period: _period, year: _year, month: _month,
  );

  void _refresh() => setState(() => _future = _load());

  Widget _metric(String title, String value, IconData icon, double width) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 21, color: colors.primary),
              const SizedBox(height: 10),
              Text(value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Text(title, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: Key('inventory_analytics_${widget.department}'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        Row(children: [
          Expanded(child: Text('Analytics • ${widget.department == 'canteen' ? 'Canteen' : 'Stationery'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(
            key: const Key('inventory_analytics_refresh'),
            tooltip: 'Refresh analytics',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Purchase costs and gross profit are visible only to authorized '
            'stock managers.', style: TextStyle(fontSize: 12,
              color: colors.onSurfaceVariant)),
        const SizedBox(height: 14),
        Wrap(
          key: const Key('inventory_analytics_period'),
          spacing: 8, runSpacing: 8,
          children: [
            for (final option in const [
              (InventoryReportPeriod.month, 'Monthly'),
              (InventoryReportPeriod.year, 'Yearly'),
              (InventoryReportPeriod.all, 'All'),
            ])
              ChoiceChip(
                key: Key('inventory_analytics_${option.$2.toLowerCase()}'),
                label: Text(option.$2),
                selected: _period == option.$1,
                onSelected: (_) => setState(() {
                  _period = option.$1;
                  _future = _load();
                }),
              ),
          ],
        ),
        if (_period != InventoryReportPeriod.all) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 142, child: DropdownButtonFormField<int>(
              key: ValueKey('inventory_analytics_year_$_year'),
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [
                for (var year = DateTime.now().year; year >= 2019; year--)
                  DropdownMenuItem(value: year, child: Text('$year')),
              ],
              onChanged: (year) {
                if (year == null) return;
                setState(() { _year = year; _future = _load(); });
              },
            )),
            if (_period == InventoryReportPeriod.month)
              SizedBox(width: 166, child: DropdownButtonFormField<int>(
                key: ValueKey('inventory_analytics_month_$_month'),
                initialValue: _month,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Month'),
                items: [
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem(value: i + 1, child: Text(monthNames[i])),
                ],
                onChanged: (month) {
                  if (month == null) return;
                  setState(() { _month = month; _future = _load(); });
                },
              )),
          ]),
        ],
        const SizedBox(height: 16),
        FutureBuilder<InventoryDepartmentAnalytics>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(schoolErrorMessage(snapshot.error!),
                    style: TextStyle(color: colors.error)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry report'),
                  ),
                ],
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.only(top: 30),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snapshot.data!;
            return LayoutBuilder(builder: (context, constraints) {
              final cardWidth = math.max(120.0, (constraints.maxWidth - 10) / 2);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    _metric('Items available now', '${data.stockUnits}',
                      Icons.inventory_2_outlined, cardWidth),
                    _metric('Total items sold', '${data.soldUnits}',
                      Icons.shopping_basket_outlined, cardWidth),
                    _metric('Total profit (estimated)',
                      data.completeCostCoverage
                          ? inventoryRupees(data.estimatedProfitMinor)
                          : '—',
                      Icons.trending_up, cardWidth),
                    _metric('Total purchases', inventoryRupees(data.purchaseMinor),
                      Icons.local_shipping_outlined, cardWidth),
                    _metric('Sales value', inventoryRupees(data.salesMinor),
                      Icons.receipt_long_outlined, cardWidth),
                  ]),
                  const SizedBox(height: 22),
                  _salesBreakdown(data),
                  const SizedBox(height: 22),
                  Text('Sales, purchases & gross profit trend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 7, children: [
                    _legend('Sales', colors.primary),
                    _legend('Purchases', colors.secondary),
                    _legend('Estimated profit', colors.tertiary),
                  ]),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(constraints.maxWidth - 24, data.trend.length * 20.0 + 66),
                          height: 248,
                          child: CustomPaint(
                            painter: _InventoryTrendPainter(
                              data.trend,
                              salesColor: colors.primary,
                              purchasesColor: colors.secondary,
                              profitColor: colors.tertiary,
                              gridColor: colors.outlineVariant,
                              textColor: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Profit = sales value minus the current confidential '
                      'purchase cost × units sold. It is an estimated gross '
                      'profit, not net profit or cash collected. Earlier sales '
                      'may be valued at today’s purchase cost.',
                    style: TextStyle(fontSize: 11,
                      color: colors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  const Text('Total purchases includes the valued opening stock '
                      'of new products and recorded purchase receipts. '
                      'Existing products created before cost tracking may lack '
                      'historical opening purchases.',
                    style: TextStyle(fontSize: 11)),
                  if (!data.completeCostCoverage)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Purchase price missing for ${data.uncostedUnits} sold '
                        'units. Enter their cost before using profit totals.',
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    ),
                  if (data.limited)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('History limit reached. Totals and the All '
                          'filter can be incomplete; consult exported records '
                          'for a complete audit.',
                        style: TextStyle(fontSize: 12)),
                    ),
                ],
              );
            });
          },
        ),
      ],
    );
  }

  void _movePeriod(int delta) {
    final next = _period == InventoryReportPeriod.month
        ? DateTime(_year, _month + delta)
        : DateTime(_year + delta, _month);
    final now = DateTime.now();
    if (next.year < 2019 || next.year > now.year) return;
    setState(() {
      _year = next.year;
      _month = next.month;
      _future = _load();
    });
  }

  Widget _salesBreakdown(InventoryDepartmentAnalytics data) {
    final colors = Theme.of(context).colorScheme;
    const costColor = Color(0xFF5364E8);
    const profitColor = Color(0xFF16A7A0);
    final valid = data.completeCostCoverage && data.salesMinor > 0 &&
        data.estimatedProfitMinor >= 0 &&
        data.estimatedProfitMinor <= data.salesMinor;
    final cost = data.salesMinor - data.estimatedProfitMinor;
    final periodLabel = switch (_period) {
      InventoryReportPeriod.month => '${monthNames[_month - 1]} $_year',
      InventoryReportPeriod.year => '$_year',
      InventoryReportPeriod.all => 'All time',
    };
    Widget entry(String label, String value, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(Icons.circle, size: 11, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        )),
      ]),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sales breakdown', style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(periodLabel, style: TextStyle(color: colors.onSurfaceVariant)),
                ],
              )),
              if (_period != InventoryReportPeriod.all) ...[
                IconButton(tooltip: 'Previous period', onPressed: () => _movePeriod(-1),
                  icon: const Icon(Icons.chevron_left)),
                IconButton(tooltip: 'Next period', onPressed: () => _movePeriod(1),
                  icon: const Icon(Icons.chevron_right)),
              ],
            ]),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              final ring = SizedBox(
                width: 174, height: 174,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(child: CustomPaint(painter: _SalesRingPainter(
                    fraction: valid ? cost / data.salesMinor : 0,
                    valid: valid, costColor: costColor, profitColor: profitColor,
                    trackColor: colors.surfaceContainerHighest,
                  ))),
                  SizedBox(width: 110, child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Sales value', style: TextStyle(
                        fontSize: 11, color: colors.onSurfaceVariant)),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(
                        inventoryRupees(data.salesMinor),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                    ],
                  )),
                ]),
              );
              final legend = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  entry('Cost of items sold', data.completeCostCoverage
                      ? inventoryRupees(cost) : 'Not available', costColor),
                  entry('Estimated gross profit', data.completeCostCoverage
                      ? inventoryRupees(data.estimatedProfitMinor) : 'Not available', profitColor),
                  entry('Stock purchases', inventoryRupees(data.purchaseMinor),
                    colors.onSurfaceVariant),
                ],
              );
              return constraints.maxWidth >= 340
                  ? Row(children: [Expanded(child: legend), const SizedBox(width: 12), ring])
                  : Column(children: [ring, const SizedBox(height: 12), legend]);
            }),
            if (!valid)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(!data.completeCostCoverage
                    ? 'Purchase costs are missing; breakdown unavailable.'
                    : data.salesMinor <= 0 ? 'No sales recorded for this period.'
                    : 'A loss is recorded; see the amounts above.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            Text('Stock purchases are shown separately, not included in the ring.',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _InventoryTrendPainter extends CustomPainter {
  _InventoryTrendPainter(
    this.points, {
    required this.salesColor,
    required this.purchasesColor,
    required this.profitColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<InventoryTrendPoint> points;
  final Color salesColor;
  final Color purchasesColor;
  final Color profitColor;
  final Color gridColor;
  final Color textColor;

  void _text(Canvas canvas, String text, Offset at, {double size = 10}) {
    final p = TextPainter(
      text: TextSpan(text: text,
        style: TextStyle(fontSize: size, color: textColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 55.0;
    const top = 14.0;
    const bottom = 42.0;
    const right = 12.0;
    final plotWidth = size.width - left - right;
    final plotHeight = size.height - top - bottom;
    final values = [
      for (final point in points)
        ...[point.salesMinor, point.purchasesMinor, point.estimatedProfitMinor],
    ];
    final maxValue = math.max(1, values.reduce(math.max));
    final minValue = math.min(0, values.reduce(math.min));
    final range = math.max(1, maxValue - minValue);
    double y(int value) =>
        top + plotHeight * (maxValue - value) / range;
    double x(int index) =>
        left + index * plotWidth / math.max(1, points.length - 1);

    for (var step = 0; step <= 4; step++) {
      final yPos = top + plotHeight * step / 4;
      final number = (maxValue - range * step / 4) / 100;
      canvas.drawLine(Offset(left, yPos),
        Offset(size.width - right, yPos),
        Paint()..color = gridColor..strokeWidth = 0.8);
      final formatted = number.abs() >= 1000
          ? '${(number / 1000).toStringAsFixed(1)}k'
          : number.toStringAsFixed(0);
      _text(canvas, formatted, Offset(2, yPos - 7), size: 10);
    }

    void drawSeries(int Function(InventoryTrendPoint) value, Color color) {
      final paint = Paint()
        ..color = color..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final offset = Offset(x(index), y(value(points[index])));
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(path, paint);
      for (var index = 0; index < points.length; index++) {
        if (points.length > 25 && index % 3 != 0) continue;
        canvas.drawCircle(Offset(x(index), y(value(points[index]))),
          3, Paint()..color = color);
      }
    }
    drawSeries((point) => point.salesMinor, salesColor);
    drawSeries((point) => point.purchasesMinor, purchasesColor);
    drawSeries((point) => point.estimatedProfitMinor, profitColor);

    final skip = points.length > 22 ? 3 : points.length > 12 ? 2 : 1;
    for (var index = 0; index < points.length; index += skip) {
      _text(canvas, points[index].label,
        Offset(x(index) - 11, size.height - 27));
    }
  }

  @override
  bool shouldRepaint(covariant _InventoryTrendPainter old) =>
      old.points != points ||
      old.salesColor != salesColor ||
      old.purchasesColor != purchasesColor ||
      old.profitColor != profitColor;
}

class _SalesRingPainter extends CustomPainter {
  const _SalesRingPainter({required this.fraction, required this.valid,
    required this.costColor, required this.profitColor, required this.trackColor});
  final double fraction;
  final bool valid;
  final Color costColor, profitColor, trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 24.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero),
      radius: (size.shortestSide - thickness - 8) / 2);
    final brush = Paint()..style = PaintingStyle.stroke..strokeWidth = thickness;
    canvas.drawArc(rect, 0, 2 * math.pi, false, brush..color = trackColor);
    if (!valid) return;
    final angle = 2 * math.pi * fraction;
    if (angle > 0) {
      canvas.drawArc(rect, -math.pi / 2, angle, false, brush..color = costColor);
    }
    if (angle < 2 * math.pi) {
      canvas.drawArc(rect, -math.pi / 2 + angle, 2 * math.pi - angle,
        false, brush..color = profitColor);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.valid != valid ||
      oldDelegate.costColor != costColor || oldDelegate.profitColor != profitColor ||
      oldDelegate.trackColor != trackColor;
}
