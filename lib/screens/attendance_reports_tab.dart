import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';

/// Aggregated from real saved marks. An unmarked student is never counted
/// as absent, and days with no marks are excluded from attendance averages.
class AttendanceDayStats {
  const AttendanceDayStats({
    required this.date,
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
    required this.leave,
  });

  final DateTime date;
  final int total;
  final int present;
  final int absent;
  final int late;
  final int leave;

  int get marked => present + absent + late + leave;
  int get unmarked => math.max(0, total - marked);
  int get attended => present + late;
  double? get attendanceRate => marked == 0 ? null : attended / marked;
  double get completionRate =>
      total == 0 ? 0 : math.min(1, marked / total);

  factory AttendanceDayStats.fromMarks(
    DateTime date,
    List<StudentRecord> roster,
    Map<String, String> marks,
  ) {
    final summary = AttendanceSummary.fromMarks(roster, marks);
    return AttendanceDayStats(
      date: date,
      total: summary.total,
      present: summary.present,
      absent: summary.absent,
      late: summary.late,
      leave: summary.leave,
    );
  }
}

class AttendanceReportsTab extends StatefulWidget {
  const AttendanceReportsTab({
    super.key,
    required this.classId,
    required this.classLabel,
    required this.roster,
    required this.referenceDate,
    this.forTeacher = false,
    this.marksLoader,
  });

  final String classId;
  final String classLabel;
  final List<StudentRecord> roster;
  final DateTime referenceDate;
  final bool forTeacher;
  final Future<Map<String, String>> Function(String classId, DateTime date)?
      marksLoader;

  @override
  State<AttendanceReportsTab> createState() => _AttendanceReportsTabState();
}

class _AttendanceReportsTabState extends State<AttendanceReportsTab> {
  Future<List<AttendanceDayStats>>? _report;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AttendanceReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId ||
        attendanceDateKey(oldWidget.referenceDate) !=
            attendanceDateKey(widget.referenceDate) ||
        oldWidget.roster.length != widget.roster.length) {
      _refresh();
    }
  }

  void _refresh() {
    setState(() {
      _report = _fetchWeek();
    });
  }

  Future<List<AttendanceDayStats>> _fetchWeek() async {
    final reference = widget.referenceDate;
    final roster = widget.roster;
    final loader = widget.marksLoader ??
        (String classId, DateTime date) => AttendanceRepository().loadMarks(
            classId, date, forAttendanceTeacher: widget.forTeacher);
    final dates = [
      for (var i = 6; i >= 0; i--)
        DateTime(reference.year, reference.month, reference.day)
            .subtract(Duration(days: i)),
    ];
    // Seven independent class/day reads, never a cross-class query.
    return Future.wait(dates.map((date) async {
      final marks = await loader(widget.classId, date);
      return AttendanceDayStats.fromMarks(date, roster, marks);
    }));
  }

  String _pct(double? rate) =>
      rate == null ? '—' : '${(rate * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    if (widget.roster.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No active students in this class. Add students to begin attendance reports.'),
      ));
    }
    return FutureBuilder<List<AttendanceDayStats>>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(schoolErrorMessage(snapshot.error!)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry reports'),
              ),
            ]),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Calculating saved attendance…'),
            ],
          ));
        }
        final days = snapshot.data!;
        final selected = days.last;
        final marked = days.fold<int>(0, (sum, day) => sum + day.marked);
        final attended = days.fold<int>(0, (sum, day) => sum + day.attended);
        final average = marked == 0 ? null : attended / marked;
        final recordedDays = days.where((day) => day.marked > 0).length;

        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _report;
          },
          child: ListView(
            key: const Key('attendance_reports_scroll'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attendance reports & analytics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${widget.classLabel} · 7 days ending '
                        '${attendanceDateKey(widget.referenceDate)}',
                      style: TextStyle(fontSize: 12,
                        color: color.onSurfaceVariant)),
                  ],
                )),
                IconButton(
                  tooltip: 'Refresh attendance analytics',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _SummaryTile(label: 'Students', value: '${selected.total}',
                  icon: Icons.groups_outlined, color: color.primary),
                _SummaryTile(label: 'Marked on date', value: '${selected.marked}',
                  icon: Icons.task_alt_outlined, color: color.secondary),
                _SummaryTile(label: 'Present + late', value: '${selected.attended}',
                  icon: Icons.check_circle_outline, color: color.tertiary),
                _SummaryTile(label: 'Absent on date', value: '${selected.absent}',
                  icon: Icons.person_off_outlined, color: color.error),
                _SummaryTile(label: '7-day attendance', value: _pct(average),
                  icon: Icons.trending_up_rounded, color: color.primary),
                _SummaryTile(label: 'Days recorded', value: '$recordedDays / 7',
                  icon: Icons.calendar_today_outlined, color: color.secondary),
              ]),
              const SizedBox(height: 15),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected day: attendance breakdown',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${attendanceDateKey(selected.date)} · '
                        '${_pct(selected.completionRate)} of class marked',
                      style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    Row(children: [
                      SizedBox(
                        width: 145, height: 145,
                        child: CustomPaint(
                          key: const Key('attendance_breakdown_chart'),
                          painter: _AttendanceRingPainter(
                            amounts: [
                              selected.present, selected.absent,
                              selected.late, selected.leave, selected.unmarked,
                            ],
                            colors: [
                              color.primary, color.error, color.tertiary,
                              color.secondary, color.outlineVariant,
                            ],
                            background: color.surfaceContainerHighest,
                          ),
                          child: Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${selected.marked}/${selected.total}',
                                style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                              Text('marked', style: TextStyle(
                                fontSize: 11, color: color.onSurfaceVariant)),
                            ],
                          )),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Legend('Present', selected.present, color.primary),
                          _Legend('Absent', selected.absent, color.error),
                          _Legend('Late', selected.late, color.tertiary),
                          _Legend('Leave', selected.leave, color.secondary),
                          _Legend('Unmarked', selected.unmarked,
                            color.outlineVariant),
                        ],
                      )),
                    ]),
                  ],
                ),
              )),
              const SizedBox(height: 10),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attendance trend · last 7 days',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Present + late as a share of marked students',
                      style: TextStyle(fontSize: 11,
                        color: color.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    SizedBox(height: 192, child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: days.map((day) {
                        final rate = day.attendanceRate;
                        return Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(_pct(rate), style: const TextStyle(fontSize: 10)),
                            const SizedBox(height: 6),
                            Container(
                              key: Key('attendance_trend_${attendanceDateKey(day.date)}'),
                              width: 24,
                              height: rate == null
                                ? 4
                                : math.max(4.0, 125.0 * rate),
                              decoration: BoxDecoration(
                                color: rate == null
                                  ? color.outlineVariant : color.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text('${day.date.day}/${day.date.month}',
                              style: const TextStyle(fontSize: 10)),
                          ],
                        ));
                      }).toList(),
                    )),
                    const SizedBox(height: 8),
                    Text('— means no students were marked that day. '
                        'Unmarked students are not treated as absent.',
                      style: TextStyle(fontSize: 11,
                        color: color.onSurfaceVariant)),
                  ],
                ),
              )),
              const SizedBox(height: 10),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Daily report',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final day in days)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(width: 83,
                            child: Text(attendanceDateKey(day.date),
                              style: const TextStyle(fontSize: 11))),
                          Expanded(child: Text(
                            'P ${day.present} · A ${day.absent} · '
                            'L ${day.late} · Leave ${day.leave}',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis)),
                          Text('${day.marked}/${day.total}',
                            style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              Text('Rates use only students with saved attendance marks. '
                  'The roster reflects current active enrollment, not historical transfers.',
                style: TextStyle(fontSize: 11, color: color.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 148,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 7),
            Text(value, style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
      Text('$count', style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _AttendanceRingPainter extends CustomPainter {
  const _AttendanceRingPainter({
    required this.amounts,
    required this.colors,
    required this.background,
  });
  final List<int> amounts;
  final List<Color> colors;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = amounts.fold<int>(0, (a, b) => a + b);
    final base = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (total == 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      if (amounts[i] <= 0) continue;
      final sweep = math.pi * 2 * amounts[i] / total;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceRingPainter old) =>
      old.amounts.toString() != amounts.toString() ||
      old.colors.toString() != colors.toString() ||
      old.background != background;
}
