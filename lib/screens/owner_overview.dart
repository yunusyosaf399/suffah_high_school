import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/examination_repository.dart';
import '../data/finance_models.dart';
import '../data/inventory_catalog.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import 'owner_analytics.dart';

const _muted = Color(0xFF68647D);
const _pale = Color(0xFFF1EBFC);
const _palette = [dashboardPurple, Color(0xFF9870E1), Color(0xFFC4ABF5),
  Color(0xFFE0D3FA), Color(0xFF8065A8), Color(0xFFA99AC8)];

class OwnerOverview extends StatefulWidget {
  const OwnerOverview({super.key, required this.summary, required this.slideshow,
    required this.examCard});
  final Future<SchoolSummary> summary;
  final bool slideshow;
  final Widget examCard;

  @override
  State<OwnerOverview> createState() => _OwnerOverviewState();
}

class _OwnerOverviewState extends State<OwnerOverview> {
  final _db = FirebaseFirestore.instance;
  final _now = schoolExamNow();
  late final _fees = _loadFees();
  late final _sales = _loadSales();
  late final _attendance = _loadAttendance();
  int _feeMonths = 6;
  int _attendanceDays = 14;
  final _yearSales = <String,bool>{};
  final _detailsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    for (final f in [_fees, _sales, _attendance]) {
      f.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    }
  }

  Future<List<FinanceBill>> _loadFees() async {
    final from = financeMonth(DateTime(_now.year, _now.month - 5));
    final result = await _db.collection('finance_fee_bills')
      .where('month', isGreaterThanOrEqualTo: from)
      .where('month', isLessThanOrEqualTo: financeMonth(_now))
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 30));
    return result.docs.map(FinanceBill.fromSnapshot).toList();
  }

  Future<({Map<String,Map<String,int>> month, Map<String,Map<String,int>> year})> _loadSales() async {
    // Sales do not store a category snapshot in older receipts. Use the current
    // catalog, and preserve uncategorized historical receipts as Other.
    final start = Timestamp.fromDate(DateTime.utc(_now.year, 1, 1).subtract(const Duration(hours: 5)));
    final results = await Future.wait([
      _db.collection('inventory_items').get(const GetOptions(source: Source.server)),
      _db.collection('inventory_sales').where('soldAt', isGreaterThanOrEqualTo: start)
        .where('soldAt', isLessThanOrEqualTo: Timestamp.now())
        .get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 30));
    final catalog = {for (final d in results[0].docs) d.id: d.data()};
    final month = <String,Map<String,int>>{}, year = <String,Map<String,int>>{};
    for (final d in results[1].docs) {
      final data = d.data();
      final dept = data['department'];
      final stamp = data['soldAt'];
      if (dept is! String || stamp is! Timestamp) continue;
      final item = catalog[data['itemId']];
      final category = inventoryCategoryLabel(dept,
        (data['category'] ?? item?['category'] ?? 'other').toString());
      final amount = (data['totalMinor'] as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;
      void add(Map<String,Map<String,int>> target) {
        final group = target.putIfAbsent(dept, () => {});
        group.update(category, (v) => v + amount, ifAbsent: () => amount);
      }
      add(year);
      final day = stamp.toDate().toUtc().add(const Duration(hours:5));
      if (day.year == _now.year && day.month == _now.month) add(month);
    }
    return (month: month, year: year);
  }

  Future<Map<String, double?>> _loadAttendance() async {
    final from = attendanceDateKey(DateTime(_now.year, _now.month, _now.day - 13));
    final today = attendanceDateKey(_now);
    final days = await _db.collection('attendance_days')
      .where('date', isGreaterThanOrEqualTo: from).where('date', isLessThanOrEqualTo: today)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 25));
    final counts = <String,List<int>>{};
    for (var i = 0; i < days.docs.length; i += 12) {
      final group = days.docs.skip(i).take(12);
      await Future.wait(group.map((day) async {
        final key = day.data()['date'].toString();
        final marks = await day.reference.collection('marks')
          .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
        final count = counts.putIfAbsent(key, () => [0,0]);
        for (final mark in marks.docs) {
          final status = mark.data()['status'];
          if (['present','late','absent','leave'].contains(status)) {
            count[1]++;
            if (status == 'present' || status == 'late') count[0]++;
          }
        }
      }));
    }
    return {for (var i = 13; i >= 0; i--)
      attendanceDateKey(DateTime(_now.year, _now.month, _now.day-i)): null,
      for (final e in counts.entries) e.key: e.value[1] == 0 ? null : e.value[0]*100/e.value[1]};
  }

  Widget _loaded<T>(Future<T> future, Widget Function(T) builder, {String title = 'Analytics'}) =>
    FutureBuilder<T>(future: future, builder: (context, snapshot) {
      if (snapshot.hasError) return Card(child: ListTile(title: Text(title),
        subtitle: Text(schoolErrorMessage(snapshot.error!))));
      if (!snapshot.hasData) return const DashboardSkeleton();
      return builder(snapshot.data as T);
    });

  Widget _kpi(String title, String value, IconData icon, String note) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: _pale,
        borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: dashboardPurple)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800))),
        const SizedBox(height: 3),
        Text(note, style: const TextStyle(fontSize: 10, color: _muted)),
      ])),
    ])),
  );

  Widget _kpis() => LayoutBuilder(builder: (context, c) {
    final columns = c.maxWidth >= 900 ? 4 : c.maxWidth >= 450 ? 2 : 1;
    final w = (c.maxWidth - (columns-1)*12)/columns;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      SizedBox(width:w, child: _loaded(widget.summary, (s) =>
        _kpi('Student records', '${s.students}', Icons.groups_outlined, 'School records'))),
      SizedBox(width:w, child: _loaded(widget.summary, (s) =>
        _kpi('Class sections', '${s.classes}', Icons.school_outlined, 'School sections'))),
      SizedBox(width:w, child: _loaded(_attendance, (data) {
        final rate = data[attendanceDateKey(_now)];
        return _kpi("Today's attendance", rate == null ? '—' : '${rate.toStringAsFixed(1)}%',
          Icons.event_available_outlined, 'Recorded marks only');
      })),
      SizedBox(width:w, child: _loaded(_fees, (data) {
        final due = data.where((b) => b.month == financeMonth(_now))
          .fold<int>(0,(s,b)=>s+math.max(0,b.remainingMinor));
        return _kpi('Outstanding fees', financeMoney(due), Icons.account_balance_wallet_outlined, 'Current month bills');
      })),
    ]);
  });

  Widget _panel(String title, String subtitle, IconData icon, Widget body, {Widget? filter}) =>
    Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color:_pale,
            borderRadius: BorderRadius.circular(10)), child: Icon(icon,color:dashboardPurple,size:23)),
          const SizedBox(width:9),
          Expanded(child: Text(title, style: const TextStyle(fontSize:16,fontWeight:FontWeight.w800))),
        ]),
        const SizedBox(height:5),
        Text(subtitle,style:const TextStyle(fontSize:11,color:_muted)),
        if(filter != null) Align(alignment:Alignment.centerRight,child:filter),
        const SizedBox(height:8),
        body,
      ])));

  Widget _feeChart() => _loaded(_fees, (data) {
    final labels = [for(var i=_feeMonths-1;i>=0;i--) financeMonth(DateTime(_now.year,_now.month-i))];
    final paid = <double>[], due = <double>[];
    for(final label in labels) {
      final bills=data.where((b)=>b.month==label);
      paid.add(bills.fold<double>(0,(s,b)=>s+b.paidMinor/100));
      due.add(bills.fold<double>(0,(s,b)=>s+math.max(0,b.remainingMinor)/100));
    }
    return _panel('Fees analytics','Paid vs outstanding by bill month',Icons.payments_outlined,
      Column(children:[
        _AnimatedPlot(painter:(t)=>_TrendPainter(labels.map((m)=>m.substring(5)).toList(),
          paid,due,progress:t)),
        const SizedBox(height:8),
        const Wrap(spacing:12,runSpacing:4,children:[
          _Legend('Paid',dashboardPurple),_Legend('Outstanding',Color(0xFFC4ABF5)),
        ]),
      ]),filter:DropdownButton<int>(value:_feeMonths,underline:const SizedBox.shrink(),
        items:const [DropdownMenuItem(value:6,child:Text('Last 6 months')),DropdownMenuItem(value:3,child:Text('Last 3 months'))],
        onChanged:(v){if(v!=null)setState(()=>_feeMonths=v);}));
  }, title:'Fees analytics');

  Widget _salesChart(String dept) => _loaded(_sales, (data) {
    final groups=((_yearSales[dept]??false)?data.year:data.month)[dept]??{};
    final sorted=groups.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    final entries=sorted.take(5).toList();
    if(sorted.length>5) entries.add(MapEntry('Remaining categories',sorted.skip(5).fold<int>(0,(s,e)=>s+e.value)));
    final total=entries.fold<int>(0,(s,e)=>s+e.value);
    return _panel(dept=='canteen'?'Canteen sales':'Stationery analytics',
      'Sales value by current product category',dept=='canteen'?Icons.restaurant:Icons.edit_outlined,
      Column(children:[
        SizedBox(height:154,child:Stack(alignment:Alignment.center,children:[
          _AnimatedPlot(height:154,painter:(t)=>_RingPainter(entries.map((e)=>e.value.toDouble()).toList(),t)),
          SizedBox(width:112,child:Column(mainAxisSize:MainAxisSize.min,children:[
            FittedBox(fit:BoxFit.scaleDown,child:Text(financeMoney(total),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16))),
            const Text('Total sales',style:TextStyle(fontSize:11,color:_muted)),
          ])),
        ])),
        if(entries.isEmpty)const Text('No sales in this period',style:TextStyle(color:_muted)),
        for(var i=0;i<entries.length;i++) Padding(padding:const EdgeInsets.only(top:5),
          child:Row(children:[Expanded(child:_Legend(entries[i].key,_palette[i])),
            Text('${(entries[i].value*100/total).toStringAsFixed(0)}%',style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700))])),
      ]),filter:DropdownButton<bool>(value:_yearSales[dept]??false,underline:const SizedBox.shrink(),
        items:const [DropdownMenuItem(value:false,child:Text('This month')),DropdownMenuItem(value:true,child:Text('This year'))],
        onChanged:(v){if(v!=null)setState(()=>_yearSales[dept]=v);}));
  },title:dept=='canteen'?'Canteen sales':'Stationery analytics');

  Widget _attendanceChart() => _loaded(_attendance,(data){
    final values=data.entries.toList()..sort((a,b)=>a.key.compareTo(b.key));
    final selected=values.skip(values.length-_attendanceDays).toList();
    return _panel('Attendance trend','Present + late / recorded marks',Icons.event_available_outlined,
      Column(children:[
        _AnimatedPlot(painter:(t)=>_TrendPainter(selected.map((e)=>e.key.substring(5)).toList(),
          selected.map((e)=>e.value).toList(),const [],progress:t,line:true)),
        if(selected.every((e)=>e.value==null))const Text('No attendance recorded in this period.'),
        const Text('Missing registers are gaps, not zero attendance.',style:TextStyle(fontSize:10,color:_muted)),
      ]),filter:DropdownButton<int>(value:_attendanceDays,underline:const SizedBox.shrink(),
        items:const [DropdownMenuItem(value:14,child:Text('Last 14 days')),DropdownMenuItem(value:7,child:Text('Last 7 days'))],
        onChanged:(v){if(v!=null)setState(()=>_attendanceDays=v);}));
  },title:'Attendance trend');

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    _kpis(),
    const SizedBox(height:16),
    if(!widget.slideshow)
      LayoutBuilder(builder:(context,c){
        final n=c.maxWidth>=1000?3:c.maxWidth>=640?2:1;
        final width=(c.maxWidth-(n-1)*12)/n;
        return Wrap(spacing:12,runSpacing:12,children:[
          for(final chart in [_feeChart(),_salesChart('canteen'),_salesChart('stationery')])
            SizedBox(width:width,child:chart),
        ]);
      }),
    if(widget.slideshow) OwnerAnalytics(key:_detailsKey,slideshow:true),
    const SizedBox(height:16),
    LayoutBuilder(builder:(context,c){
      final n=c.maxWidth>=850?2:1;
      final width=(c.maxWidth-(n-1)*12)/n;
      return Wrap(spacing:12,runSpacing:12,children:[
        SizedBox(width:width,child:_attendanceChart()),
        SizedBox(width:width,child:widget.examCard),
      ]);
    }),
    if(!widget.slideshow) ...[
      const SizedBox(height:18),
      const Text('Detailed reports',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),
      OwnerAnalytics(key:_detailsKey,slideshow:false),
    ],
  ]);
}

class _Legend extends StatelessWidget {
  const _Legend(this.text,this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context)=>Row(mainAxisSize:MainAxisSize.min,children:[
    Icon(Icons.circle,size:10,color:color),const SizedBox(width:5),
    Flexible(child:Text(text,style:const TextStyle(fontSize:11),maxLines:2,overflow:TextOverflow.ellipsis)),
  ]);
}

class _AnimatedPlot extends StatelessWidget {
  const _AnimatedPlot({required this.painter,this.height=166});
  final CustomPainter Function(double) painter;
  final double height;
  @override
  Widget build(BuildContext context)=>TweenAnimationBuilder<double>(
    tween:Tween(begin:0,end:1),duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:850),
    curve:Curves.easeOutCubic,builder:(context,t,_)=>SizedBox(height:height,width:double.infinity,
      child:CustomPaint(painter:painter(t))));
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.values,this.progress);
  final List<double> values;
  final double progress;
  @override
  void paint(Canvas canvas,Size size){
    final radius=math.max(0.0,math.min(size.width,size.height)/2-15);
    final rect=Rect.fromCircle(center:size.center(Offset.zero),radius:radius);
    final brush=Paint()..style=PaintingStyle.stroke..strokeWidth=24;
    canvas.drawArc(rect,0,2*math.pi,false,brush..color=_pale);
    final total=values.fold<double>(0,(s,v)=>s+v);
    if(total<=0)return;
    var angle=-math.pi/2;
    for(var i=0;i<values.length;i++){
      final sweep=2*math.pi*values[i]/total;
      canvas.drawArc(rect,angle,sweep*progress,false,brush..color=_palette[i%_palette.length]);
      angle+=sweep;
    }
  }
  @override bool shouldRepaint(covariant _RingPainter old)=>true;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.labels,this.first,this.second,{required this.progress,this.line=false});
  final List<String> labels;
  final List<double?> first,second;
  final double progress;
  final bool line;
  void _text(Canvas c,String s,Offset o){
    final p=TextPainter(text:TextSpan(text:s,style:const TextStyle(fontSize:9,color:_muted)),
      textDirection:TextDirection.ltr)..layout();p.paint(c,o);
  }
  @override
  void paint(Canvas canvas,Size size){
    final left=42.0, top=8.0, bottom=size.height-22, width=math.max(1.0,size.width-left-8);
    final height=math.max(1.0,bottom-top);
    final max=line?100.0:[...first,...second].whereType<double>().fold<double>(1,(v,x)=>math.max(v,x));
    for(var i=0;i<=4;i++){
      final y=top+height*i/4;
      canvas.drawLine(Offset(left,y),Offset(size.width-4,y),Paint()..color=const Color(0xFFE8E4F0));
      final value=max*(1-i/4);
      _text(canvas,line?'${value.round()}%':value>=1000?'${(value/1000).toStringAsFixed(1)}k':value.round().toString(),Offset(0,y-5));
    }
    final step=width/math.max(1,labels.length);
    double x(int i)=>left+step*(i+.5);
    double y(double v)=>bottom-height*(v/max)*progress;
    final brush=Paint()..color=dashboardPurple..strokeWidth=2.4;
    if(line){
      Offset? previous;
      for(var i=0;i<first.length;i++){
        final value=first[i];
        if(value==null){previous=null;continue;}
        final point=Offset(x(i),y(value));
        if(previous!=null)canvas.drawLine(previous,point,brush);
        canvas.drawCircle(point,3,brush);
        previous=point;
      }
    }else{
      for(var i=0;i<first.length;i++){
        final a=first[i]??0,b=second[i]??0,bar=step*.28;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(i)-bar,y(a),x(i),bottom),const Radius.circular(2)),brush..color=dashboardPurple);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(i)+2,y(b),x(i)+bar+2,bottom),const Radius.circular(2)),brush..color=const Color(0xFFC4ABF5));
      }
    }
    for(var i=0;i<labels.length;i++){
      if(labels.length>7&&i%2!=0)continue;
      _text(canvas,labels[i],Offset(x(i)-10,bottom+5));
    }
  }
  @override bool shouldRepaint(covariant _TrendPainter old)=>true;
}
