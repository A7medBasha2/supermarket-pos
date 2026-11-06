import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../maps_util.dart';
import '../order_status.dart';
import '../util.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late String _status = widget.order['status'] as String;
  bool _busy = false;
  bool _changed = false;

  Map<String, dynamic> get o => widget.order;

  /// الطلبات القديمة (من غير fulfillment_type) كلها توصيل
  bool get _isPickup => (o['fulfillment_type'] as String?) == 'pickup';

  List<({String label, String next, bool danger})> get _actions {
    switch (_status) {
      case 'new':
        return [
          (label: 'قبول وبدء التجهيز', next: 'preparing', danger: false),
          (label: 'رفض الطلب', next: 'cancelled', danger: true),
        ];
      case 'preparing':
        return [
          if (_isPickup)
            (label: 'جاهز للاستلام', next: 'ready_for_pickup', danger: false)
          else
            (label: 'خرج للتوصيل', next: 'out_for_delivery', danger: false),
          (label: 'إلغاء الطلب', next: 'cancelled', danger: true),
        ];
      case 'out_for_delivery':
        return [
          (label: 'تم التسليم', next: 'delivered', danger: false),
          (label: 'إلغاء الطلب', next: 'cancelled', danger: true),
        ];
      case 'ready_for_pickup':
        return [
          (label: 'العميل استلم الطلب', next: 'delivered', danger: false),
          (label: 'إلغاء الطلب', next: 'cancelled', danger: true),
        ];
      default:
        return [];
    }
  }

  Future<void> _setStatus(String next, {required bool danger}) async {
    if (danger) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد'),
          content: const Text('متأكد إنك عايز تلغي الطلب ده؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('نعم، إلغاء')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .update({'status': next})
          .eq('id', o['id'] as String)
          .select('status');
      if (res.isEmpty) {
        throw 'لم يتم التحديث (ممكن الاشتراك منتهي أو الطلب اتغيّر من جهاز تاني)';
      }
      if (!mounted) return;
      setState(() {
        _status = next;
        _changed = true;
      });
      showSnack(context, 'تم تحديث الحالة: ${statusLabel(next)}');
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ((o['order_items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final type = o['fulfillment_type'] as String?;
    final lat = (o['lat'] as num?)?.toDouble();
    final lng = (o['lng'] as num?)?.toDouble();
    final accuracy = o['accuracy_m'] as num?;
    final weak = accuracy != null && accuracy > 50;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الطلب')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Chip(
                  label: Text(statusLabel(_status),
                      style: const TextStyle(color: Colors.white)),
                  backgroundColor: statusColor(_status),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: Icon(fulfillmentIcon(type), size: 18),
                  label: Text(fulfillmentLabel(type)),
                ),
                const Spacer(),
                Text(money(o['total'] as num),
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${o['customer_name']}'),
                subtitle: Text('${o['customer_phone']}'),
                trailing: IconButton.filledTonal(
                  icon: const Icon(Icons.call),
                  onPressed: () async {
                    final ok = await callPhone('${o['customer_phone']}');
                    if (!ok && context.mounted) {
                      showSnack(context, 'تعذّر فتح الاتصال', error: true);
                    }
                  },
                ),
              ),
            ),
            if (_isPickup)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.storefront_outlined),
                  title: Text('استلام من المحل'),
                  subtitle: Text('العميل هيستلم الطلب بنفسه (مفيش توصيل ولا عنوان).'),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('العنوان',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${o['address_text']}'),
                      if ((o['address_details'] as String?) != null)
                        Text('${o['address_details']}'),
                      const SizedBox(height: 8),
                      Text(
                        accuracyText(accuracy),
                        style: TextStyle(
                            color: weak ? Colors.red.shade700 : Colors.green.shade800),
                      ),
                      if (lat != null && lng != null) ...[
                        Text(
                          '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.navigation),
                          label: const Text('افتح الموقع في خرائط جوجل'),
                          onPressed: () async {
                            final ok = await openInGoogleMaps(lat, lng);
                            if (!ok && context.mounted) {
                              showSnack(context, 'تعذّر فتح الخرائط', error: true);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الأصناف',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    for (final it in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(
                                    '${it['name']}  ×${fmtQty(it['qty'] as num)}')),
                            Text(money((it['price'] as num) * (it['qty'] as num))),
                          ],
                        ),
                      ),
                    const Divider(),
                    _row('المجموع', money(o['subtotal'] as num)),
                    if (!_isPickup)
                      _row('رسوم التوصيل', money(o['delivery_fee'] as num)),
                    _row('الإجمالي', money(o['total'] as num), bold: true),
                    const SizedBox(height: 4),
                    const Text('الدفع: عند الاستلام (كاش)'),
                    if ((o['note'] as String?) != null) ...[
                      const SizedBox(height: 8),
                      Text('ملاحظة العميل: ${o['note']}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final a in _actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: a.danger
                    ? OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _setStatus(a.next, danger: true),
                        child: Text(a.label),
                      )
                    : FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _setStatus(a.next, danger: false),
                        child: Text(a.label),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
