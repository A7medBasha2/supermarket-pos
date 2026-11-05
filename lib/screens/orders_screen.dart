import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../order_status.dart';
import '../services/orders_service.dart';
import '../util.dart';
import 'order_detail_screen.dart';

/// طلبات العملاء (أونلاين فقط)
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filter = 'new';
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _lastTick = OrdersService.instance.arrivalTick;
    OrdersService.instance.addListener(_onService);
    _load();
  }

  @override
  void dispose() {
    OrdersService.instance.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    final tick = OrdersService.instance.arrivalTick;
    if (tick != _lastTick) {
      _lastTick = tick;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('orders')
          .select('*, order_items(*)')
          .eq('status', _filter)
          .order('created_at', ascending: _filter == 'new')
          .limit(100);
      if (!mounted) return;
      setState(() => _orders = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'تعذّر تحميل الطلبات. الطلبات تحتاج اتصال بالإنترنت.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
    );
    if (changed == true) {
      _load();
      OrdersService.instance.refreshCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in orderStatuses)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(statusLabel(s)),
                    selected: _filter == s,
                    onSelected: (_) {
                      setState(() => _filter = s);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _orders.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: CircularProgressIndicator()),
                  ])
                : _error != null
                    ? ListView(children: [
                        const SizedBox(height: 100),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      ])
                    : _orders.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 100),
                            Center(child: Text('لا توجد طلبات')),
                          ])
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final o = _orders[i];
                              final items = (o['order_items'] as List?) ?? [];
                              final created = DateTime.tryParse(
                                      o['created_at'] as String? ?? '')
                                  ?.toLocal();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      statusColor(o['status'] as String),
                                  child: const Icon(Icons.shopping_bag_outlined,
                                      color: Colors.white),
                                ),
                                title: Text(
                                    '${o['customer_name']} • ${money(o['total'] as num)}'),
                                subtitle: Text(
                                  '${o['address_text']}\n'
                                  '${items.length} صنف'
                                  '${created == null ? '' : ' • ${DateFormat('MM-dd HH:mm').format(created)}'}',
                                ),
                                isThreeLine: true,
                                onTap: () => _open(o),
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }
}
