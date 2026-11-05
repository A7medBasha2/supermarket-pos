import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// متابعة الطلبات الجديدة (أونلاين فقط):
///  - Realtime: أول ما عميل يعمل طلب يوصل لصاحب المحل فوراً.
///  - فحص كل 30 ثانية كاحتياط لو الاتصال الفوري انقطع.
/// لما عدد الطلبات الجديدة يزيد: بيشتغل تنبيه (صوت + اهتزاز) و arrivalTick بيزيد.
class OrdersService extends ChangeNotifier {
  OrdersService._();
  static final OrdersService instance = OrdersService._();

  SupabaseClient get _c => Supabase.instance.client;

  RealtimeChannel? _channel;
  Timer? _timer;
  String? _storeId;

  int newCount = 0;
  int arrivalTick = 0;
  bool _baselineSet = false;

  Future<void> start(String storeId) async {
    if (_storeId == storeId && _channel != null) return;
    await stop();
    _storeId = storeId;
    _baselineSet = false;
    try {
      _channel = _c
          .channel('orders-$storeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (_) => refreshCount(),
          )
          .subscribe();
    } catch (_) {
      // لو الاتصال الفوري فشل، الفحص الدوري هيغطي
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refreshCount());
    refreshCount();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _c.removeChannel(ch);
      } catch (_) {}
    }
    _storeId = null;
    newCount = 0;
    _baselineSet = false;
  }

  Future<void> refreshCount() async {
    try {
      final rows = await _c.from('orders').select('id').eq('status', 'new');
      final count = rows.length;
      final increased = _baselineSet && count > newCount;
      newCount = count;
      _baselineSet = true;
      if (increased) {
        arrivalTick++;
        _alert();
      }
      notifyListeners();
    } catch (_) {
      // أوفلاين: مفيش طلبات أونلاين أصلاً
    }
  }

  Future<void> _alert() async {
    for (var i = 0; i < 3; i++) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}
