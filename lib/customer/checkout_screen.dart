import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../order_status.dart';
import '../util.dart';
import 'cart.dart';
import 'location_picker_screen.dart';
import 'store_data.dart';

class SavedAddress {
  final String id;
  final String label;
  final String addressText;
  final String? details;
  final double lat;
  final double lng;
  final double? accuracyM;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.addressText,
    required this.details,
    required this.lat,
    required this.lng,
    required this.accuracyM,
  });

  factory SavedAddress.fromMap(Map<String, dynamic> m) => SavedAddress(
        id: m['id'] as String,
        label: m['label'] as String,
        addressText: m['address_text'] as String,
        details: m['details'] as String?,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        accuracyM: (m['accuracy_m'] as num?)?.toDouble(),
      );
}

String orderErrorText(String msg) {
  final m = msg.toLowerCase();
  if (m.contains('insufficient stock')) {
    final parts = msg.split(':');
    final name = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
    return 'الكمية المطلوبة من "$name" غير متوفرة حالياً';
  }
  if (m.contains('store suspended')) return 'المتجر غير متاح حالياً';
  if (m.contains('not accepting')) return 'المتجر لا يستقبل طلبات حالياً';
  if (m.contains('below minimum')) return 'الطلب أقل من الحد الأدنى';
  if (m.contains('product unavailable')) return 'أحد المنتجات لم يعد متاحاً';
  if (m.contains('not a customer')) return 'سجّل خروج ثم ادخل من جديد';
  return msg;
}

class CheckoutScreen extends StatefulWidget {
  final StoreData store;
  const CheckoutScreen({super.key, required this.store});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _note = TextEditingController();
  List<SavedAddress> _addresses = [];
  String? _selectedId;
  bool _loading = true;
  bool _placing = false;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    try {
      final rows = await _c
          .from('customer_addresses')
          .select()
          .eq('store_id', widget.store.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _addresses = rows.map(SavedAddress.fromMap).toList();
        _selectedId ??= _addresses.isEmpty ? null : _addresses.first.id;
      });
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر تحميل العناوين', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAddress() async {
    final p = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (p == null) return;
    try {
      final row = await _c
          .from('customer_addresses')
          .insert({
            'store_id': widget.store.id,
            'label': p.label,
            'address_text': p.addressText,
            'details': p.details,
            'lat': p.lat,
            'lng': p.lng,
            'accuracy_m': p.accuracyM,
          })
          .select()
          .single();
      final saved = SavedAddress.fromMap(row);
      if (!mounted) return;
      setState(() {
        _addresses = [saved, ..._addresses];
        _selectedId = saved.id;
      });
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر حفظ العنوان', error: true);
    }
  }

  Future<void> _deleteAddress(SavedAddress a) async {
    try {
      await _c.from('customer_addresses').delete().eq('id', a.id);
      if (!mounted) return;
      setState(() {
        _addresses.removeWhere((x) => x.id == a.id);
        if (_selectedId == a.id) {
          _selectedId = _addresses.isEmpty ? null : _addresses.first.id;
        }
      });
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر حذف العنوان', error: true);
    }
  }

  Future<void> _place() async {
    SavedAddress? addr;
    for (final a in _addresses) {
      if (a.id == _selectedId) addr = a;
    }
    if (addr == null) {
      showSnack(context, 'اختار عنوان التوصيل أو أضف عنوان جديد', error: true);
      return;
    }
    final cart = CartController.instance;
    setState(() => _placing = true);
    try {
      await _c.rpc('place_order', params: {
        'p_store_code': widget.store.code,
        'p_items': cart.items
            .map((i) => {'product_id': i.product.id, 'qty': i.qty})
            .toList(),
        'p_address_text': addr.addressText,
        'p_address_details': addr.details,
        'p_lat': addr.lat,
        'p_lng': addr.lng,
        'p_accuracy': addr.accuracyM,
        'p_note': _note.text.trim(),
      });
      cart.clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('تم إرسال طلبك'),
          content: const Text(
              'المتجر هيتواصل معاك ويجهّز الطلب. تقدر تتابع الحالة من "طلباتي".'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, orderErrorText(e.message), error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر الاتصال بالإنترنت', error: true);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartController.instance;
    final subtotal = cart.subtotal;
    final total = subtotal + widget.store.deliveryFee;
    return Scaffold(
      appBar: AppBar(title: const Text('إتمام الطلب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('عنوان التوصيل',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final a in _addresses)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _selectedId == a.id
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: _selectedId == a.id
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(a.label),
                      subtitle: Text(
                        '${a.addressText}\n${a.details ?? ''}\n'
                        '${accuracyText(a.accuracyM)}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteAddress(a),
                      ),
                      onTap: () => setState(() => _selectedId = a.id),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _addAddress,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('إضافة عنوان جديد (على الخريطة)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظات للمتجر (اختياري)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _row('المجموع', money(subtotal)),
                        _row('رسوم التوصيل', money(widget.store.deliveryFee)),
                        _row('الإجمالي', money(total), bold: true),
                        const SizedBox(height: 6),
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('الدفع عند الاستلام (كاش)'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _placing ? null : _place,
                  child: _placing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('تأكيد الطلب'),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null;
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
