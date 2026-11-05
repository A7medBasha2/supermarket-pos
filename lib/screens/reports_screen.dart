import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models.dart';
import '../services/sync_service.dart';
import '../util.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 1; // 1 = النهارده
  Map<String, num> _summary = {'count': 0, 'revenue': 0, 'profit': 0};
  List<Map<String, Object?>> _top = [];
  List<Product> _low = [];

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_onSync);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (!SyncService.instance.syncing) _load();
  }

  String _since() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final from = startOfToday.subtract(Duration(days: _days - 1));
    return from.toUtc().toIso8601String();
  }

  Future<void> _load() async {
    final since = _since();
    final s = await LocalDb.instance.summarySince(since);
    final t = await LocalDb.instance.topProductsSince(since);
    final l = await LocalDb.instance.lowStock();
    if (!mounted) return;
    setState(() {
      _summary = s;
      _top = t;
      _low = l;
    });
  }

  Widget _tile(String label, String value, IconData icon) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Icon(icon),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('التقارير بتعرض مبيعات الجهاز ده.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final e in const {1: 'النهارده', 7: '7 أيام', 30: '30 يوم'}.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _days == e.key,
                onSelected: (_) {
                  setState(() => _days = e.key);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _tile('المبيعات', money(_summary['revenue'] ?? 0), Icons.payments),
            _tile('الربح', money(_summary['profit'] ?? 0), Icons.trending_up),
            _tile('الفواتير', '${(_summary['count'] ?? 0).toInt()}',
                Icons.receipt_long),
          ],
        ),
        const SizedBox(height: 16),
        Text('الأكثر مبيعاً', style: Theme.of(context).textTheme.titleMedium),
        if (_top.isEmpty)
          const Padding(
              padding: EdgeInsets.all(12), child: Text('لا توجد مبيعات بعد'))
        else
          for (final r in _top)
            ListTile(
              dense: true,
              title: Text(r['name'] as String),
              subtitle: Text('الكمية: ${fmtQty(r['q'] as num)}'),
              trailing: Text(money(r['r'] as num)),
            ),
        const SizedBox(height: 16),
        Text('منتجات قاربت على النفاد',
            style: Theme.of(context).textTheme.titleMedium),
        if (_low.isEmpty)
          const Padding(
              padding: EdgeInsets.all(12), child: Text('كل المنتجات كافية'))
        else
          for (final p in _low)
            ListTile(
              dense: true,
              title: Text(p.name),
              trailing: Text(fmtQty(p.stockQty),
                  style: TextStyle(color: Colors.red.shade700)),
            ),
      ],
    );
  }
}
