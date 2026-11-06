import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util.dart';

/// إعدادات الطلبات أونلاين: قبول الطلبات، التوصيل/الاستلام، رسوم التوصيل، الحد الأدنى، رقم المحل
class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _phone = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _min = TextEditingController(text: '0');
  bool _accepting = true;
  bool _delivery = true;
  bool _pickup = true;

  /// false لو قاعدة البيانات لسه ماتشغّلش عليها migration 003 (مفيش توصيل/استلام)
  bool _hasFulfillmentCols = false;
  bool _loading = true;
  bool _saving = false;
  String? _storeId;
  String? _error;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _fee.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      Map<String, dynamic>? row;
      try {
        row = await _c
            .from('stores')
            .select(
                'id, phone, delivery_fee, min_order, accepting_orders, delivery_enabled, pickup_enabled')
            .maybeSingle();
        _hasFulfillmentCols = true;
      } on PostgrestException {
        // أعمدة التوصيل/الاستلام مش موجودة لسه (قبل migration 003)
        row = await _c
            .from('stores')
            .select('id, phone, delivery_fee, min_order, accepting_orders')
            .maybeSingle();
        _hasFulfillmentCols = false;
      }
      if (row != null && mounted) {
        final r = row;
        setState(() {
          _storeId = r['id'] as String;
          _phone.text = (r['phone'] as String?) ?? '';
          _fee.text = fmtQty(r['delivery_fee'] as num);
          _min.text = fmtQty(r['min_order'] as num);
          _accepting = r['accepting_orders'] as bool;
          if (_hasFulfillmentCols) {
            _delivery = r['delivery_enabled'] as bool;
            _pickup = r['pickup_enabled'] as bool;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تحتاج اتصال بالإنترنت لتعديل الإعدادات.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final id = _storeId;
    if (id == null) return;
    if (_hasFulfillmentCols && !_delivery && !_pickup) {
      showSnack(context, 'فعّل التوصيل أو الاستلام (واحد على الأقل)', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _c
          .from('stores')
          .update(<String, dynamic>{
            'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            'delivery_fee': parseNum(_fee.text) ?? 0,
            'min_order': parseNum(_min.text) ?? 0,
            'accepting_orders': _accepting,
            if (_hasFulfillmentCols) 'delivery_enabled': _delivery,
            if (_hasFulfillmentCols) 'pickup_enabled': _pickup,
          })
          .eq('id', id)
          .select('id');
      if (res.isEmpty) throw 'لم يتم الحفظ (الاشتراك منتهي؟)';
      if (mounted) {
        showSnack(context, 'تم حفظ الإعدادات');
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطلبات أونلاين')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      title: const Text('استقبال طلبات من العملاء'),
                      subtitle: const Text('لو اتقفل، العملاء مش هيقدروا يطلبوا'),
                      value: _accepting,
                      onChanged: (v) => setState(() => _accepting = v),
                    ),
                    if (_hasFulfillmentCols) ...[
                      SwitchListTile(
                        title: const Text('التوصيل (دليفري)'),
                        subtitle: const Text('العميل بيحدد موقعه على الخريطة'),
                        value: _delivery,
                        onChanged: (v) => setState(() => _delivery = v),
                      ),
                      SwitchListTile(
                        title: const Text('الاستلام من المحل'),
                        subtitle: const Text('العميل بيجي ياخد طلبه (من غير عنوان)'),
                        value: _pickup,
                        onChanged: (v) => setState(() => _pickup = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'رقم تليفون المحل (يظهر للعملاء)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fee,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'رسوم التوصيل (للتوصيل فقط)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _min,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'الحد الأدنى للطلب',
                          border: OutlineInputBorder()),
                    ),
                    if (!_hasFulfillmentCols)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'خيارات التوصيل/الاستلام هتظهر بعد تشغيل التحديث الجديد لقاعدة البيانات.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('حفظ'),
                    ),
                  ],
                ),
    );
  }
}
