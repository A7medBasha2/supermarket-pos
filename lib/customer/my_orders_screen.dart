import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../order_status.dart';
import '../util.dart';
import 'store_data.dart';

/// طلبات العميل وحالتها (بتتحدّث تلقائياً كل 20 ثانية)
class MyOrdersScreen extends StatefulWidget {
  final StoreData store;
  const MyOrdersScreen({super.key, required this.store});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await _c
          .from('orders')
          .select('*, order_items(*)')
          .eq('store_id', widget.store.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _orders = rows;
        _error = null;
      });
    } catch (_) {
      if (mounted && !silent) setState(() => _error = 'تعذّر تحميل الطلبات');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('متأكد إنك عايز تلغي الطلب؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، إلغاء')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _c.rpc('cancel_my_order', params: {'p_order_id': id});
      if (mounted) showSnack(context, 'تم إلغاء الطلب');
    } on PostgrestException {
      if (mounted) {
        showSnack(context, 'لا يمكن إلغاء الطلب بعد بدء تجهيزه. اتصل بالمتجر.',
            error: true);
      }
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر الاتصال بالإنترنت', error: true);
    }
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _orders.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator()),
              ])
            : _error != null && _orders.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 100),
                    Center(child: Text(_error!)),
                  ])
                : _orders.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 100),
                        Center(child: Text('لسه معملتش أي طلب')),
                      ])
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _orders.length,
                        itemBuilder: (context, i) => _orderCard(_orders[i]),
                      ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final status = o['status'] as String;
    final items = ((o['order_items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final created = DateTime.tryParse(o['created_at'] as String? ?? '')?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(statusLabel(status),
                      style: const TextStyle(color: Colors.white)),
                  backgroundColor: statusColor(status),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (created != null)
                  Text(DateFormat('yyyy-MM-dd HH:mm').format(created),
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            for (final it in items)
              Text('• ${it['name']} ×${fmtQty(it['qty'] as num)}'),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('الإجمالي (شامل التوصيل)')),
                Text(money(o['total'] as num),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Text('${o['address_text']}',
                style: Theme.of(context).textTheme.bodySmall),
            if (status == 'new')
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => _cancel(o['id'] as String),
                  child: const Text('إلغاء الطلب'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
