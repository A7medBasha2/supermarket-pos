import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';

/// مزامنة SQLite المحلية مع Supabase:
///  1) رفع المنتجات المعدّلة  2) رفع المبيعات (+ بنودها + حركات المخزون)
///  3) رفع حركات المخزون المنفصلة  4) سحب المنتجات والاشتراك من السيرفر.
/// كل عملية رفع idempotent (نفس الـ id مايتكررش) فالإعادة آمنة.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  SupabaseClient get _client => Supabase.instance.client;

  Timer? _timer;
  bool syncing = false;
  String? lastError;
  DateTime? lastSync;
  int pending = 0;
  int lowStockCount = 0;

  String? storeName;
  String? storeCode;
  String? subStatus;
  DateTime? subUntil;

  /// الاشتراك فعّال لو لسه ماخلصش (+3 أيام سماح). لو مش معروف نسمح.
  bool get subscriptionActive {
    if (subStatus == 'suspended') return false;
    final until = subUntil;
    if (until == null) return true;
    return DateTime.now().isBefore(until.add(const Duration(days: 3)));
  }

  /// تحذير قبل انتهاء الاشتراك بـ 5 أيام أو أثناء فترة السماح (null لو مفيش داعي).
  /// نفس قاعدة السيرفر: بعد الانتهاء فيه 3 أيام سماح قبل ما التطبيق يتحول للقراءة فقط.
  String? get subscriptionWarning {
    final until = subUntil;
    if (until == null || !subscriptionActive) return null;
    final now = DateTime.now();
    if (now.isBefore(until)) {
      final days = (until.difference(now).inHours / 24).ceil();
      if (days <= 5) {
        return 'الاشتراك ينتهي بعد $days يوم. جدّد لتفادي إيقاف التطبيق.';
      }
      return null;
    }
    final left =
        (until.add(const Duration(days: 3)).difference(now).inHours / 24).ceil();
    return 'انتهى الاشتراك. فاضل $left يوم سماح قبل ما التطبيق يتحول للقراءة فقط.';
  }

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 45), (_) => sync());
    loadMeta().then((_) => sync());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> loadMeta() async {
    final db = LocalDb.instance;
    storeName = await db.getMeta('store_name');
    storeCode = await db.getMeta('store_code');
    subStatus = await db.getMeta('sub_status');
    final until = await db.getMeta('sub_until');
    subUntil = until == null ? null : DateTime.tryParse(until)?.toLocal();
    pending = await db.pendingCount();
    lowStockCount = await db.lowStockCount();
    notifyListeners();
  }

  Future<void> refreshPending() async {
    pending = await LocalDb.instance.pendingCount();
    lowStockCount = await LocalDb.instance.lowStockCount();
    notifyListeners();
  }

  Future<void> sync() async {
    if (syncing) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      // بيانات المحل والاشتراك الأول ومستقلة عن باقي المزامنة: لو رفع البيانات فشل
      // لأي سبب (اشتراك منتهي، تعارض باركود...) لازم التطبيق يعرف التجديد فوراً.
      try {
        await _pullStoreInfo().timeout(const Duration(seconds: 20));
      } catch (_) {}
      await _pushProducts().timeout(const Duration(seconds: 40));
      await _pushSales().timeout(const Duration(seconds: 60));
      await _pushMovements().timeout(const Duration(seconds: 40));
      await _pullProducts().timeout(const Duration(seconds: 60));
      lastSync = DateTime.now();
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        lastError = 'الاشتراك منتهي: لا يمكن رفع البيانات. جدّد الاشتراك.';
      } else {
        lastError = 'خطأ مزامنة: ${e.message}';
      }
    } catch (e) {
      lastError = 'لا يوجد اتصال بالإنترنت (البيانات محفوظة على الجهاز).';
    } finally {
      syncing = false;
      await loadMeta();
    }
  }

  // ------------------------------------------------------------------ push
  Future<void> _pushProducts() async {
    final d = await LocalDb.instance.db;
    while (true) {
      final rows = await d.query('products', where: 'dirty = 1', limit: 200);
      if (rows.isEmpty) return;
      final payload = rows
          .map((r) => {
                'id': r['id'],
                'name': r['name'],
                'barcode': r['barcode'],
                'price': r['price'],
                'cost': r['cost'],
                'min_stock': r['min_stock'],
                'active': (r['active'] as int) == 1,
                'updated_at': r['updated_at'],
              })
          .toList();
      await _client.from('products').upsert(payload, onConflict: 'id');
      final ids = rows.map((r) => r['id'] as String).toList();
      final ph = List.filled(ids.length, '?').join(',');
      await d.update('products', {'dirty': 0},
          where: 'id IN ($ph)', whereArgs: ids);
    }
  }

  Future<void> _pushSales() async {
    final d = await LocalDb.instance.db;
    while (true) {
      final sales = await d.query('sales',
          where: 'synced = 0', orderBy: 'created_at', limit: 50);
      if (sales.isEmpty) return;
      final ids = sales.map((s) => s['id'] as String).toList();
      final ph = List.filled(ids.length, '?').join(',');

      final items =
          await d.query('sale_items', where: 'sale_id IN ($ph)', whereArgs: ids);
      final moves = await d.query('stock_movements',
          where: "ref_id IN ($ph) AND reason = 'sale'", whereArgs: ids);

      await _client.from('sales').upsert(
            sales
                .map((s) => {
                      'id': s['id'],
                      'total': s['total'],
                      'discount': s['discount'],
                      'payment_method': s['payment_method'],
                      'created_at': s['created_at'],
                    })
                .toList(),
            onConflict: 'id',
            ignoreDuplicates: true,
          );
      if (items.isNotEmpty) {
        await _client.from('sale_items').upsert(
              items
                  .map((i) => {
                        'id': i['id'],
                        'sale_id': i['sale_id'],
                        'product_id': i['product_id'],
                        'name': i['name'],
                        'qty': i['qty'],
                        'price': i['price'],
                        'cost': i['cost'],
                      })
                  .toList(),
              onConflict: 'id',
              ignoreDuplicates: true,
            );
      }
      if (moves.isNotEmpty) {
        await _client.from('stock_movements').upsert(
              moves
                  .map((m) => {
                        'id': m['id'],
                        'product_id': m['product_id'],
                        'qty_delta': m['qty_delta'],
                        'reason': m['reason'],
                        'ref_id': m['ref_id'],
                        'created_at': m['created_at'],
                      })
                  .toList(),
              onConflict: 'id',
              ignoreDuplicates: true,
            );
      }

      await d.update('sales', {'synced': 1},
          where: 'id IN ($ph)', whereArgs: ids);
      await d.update('stock_movements', {'synced': 1},
          where: "ref_id IN ($ph) AND reason = 'sale'", whereArgs: ids);
    }
  }

  Future<void> _pushMovements() async {
    final d = await LocalDb.instance.db;
    while (true) {
      final rows =
          await d.query('stock_movements', where: 'synced = 0', limit: 200);
      if (rows.isEmpty) return;
      await _client.from('stock_movements').upsert(
            rows
                .map((m) => {
                      'id': m['id'],
                      'product_id': m['product_id'],
                      'qty_delta': m['qty_delta'],
                      'reason': m['reason'],
                      'ref_id': m['ref_id'],
                      'created_at': m['created_at'],
                    })
                .toList(),
            onConflict: 'id',
            ignoreDuplicates: true,
          );
      final ids = rows.map((r) => r['id'] as String).toList();
      final ph = List.filled(ids.length, '?').join(',');
      await d.update('stock_movements', {'synced': 1},
          where: 'id IN ($ph)', whereArgs: ids);
    }
  }

  // ------------------------------------------------------------------ pull
  Future<void> _pullProducts() async {
    final d = await LocalDb.instance.db;

    // حركات لسه ماترفعتش (لو رفعها فشل) نضيفها فوق كمية السيرفر
    final pendingDelta = <String, double>{};
    final pendingRows = await d.rawQuery(
        'SELECT product_id, SUM(qty_delta) AS s FROM stock_movements WHERE synced = 0 GROUP BY product_id');
    for (final r in pendingRows) {
      pendingDelta[r['product_id'] as String] = (r['s'] as num).toDouble();
    }
    // منتجات معدّلة على الجهاز ولسه ماترفعتش: نحتفظ بنسختنا
    final dirtyIds = (await d.query('products',
            columns: ['id'], where: 'dirty = 1'))
        .map((r) => r['id'] as String)
        .toSet();

    const page = 1000;
    var from = 0;
    while (true) {
      final data = await _client
          .from('products')
          .select()
          .order('id')
          .range(from, from + page - 1);

      final batch = d.batch();
      for (final r in data) {
        final id = r['id'] as String;
        if (dirtyIds.contains(id)) continue;
        batch.insert(
          'products',
          {
            'id': id,
            'name': r['name'],
            'barcode': r['barcode'],
            'price': (r['price'] as num).toDouble(),
            'cost': (r['cost'] as num).toDouble(),
            'stock_qty': (r['stock_qty'] as num).toDouble() +
                (pendingDelta[id] ?? 0),
            'min_stock': (r['min_stock'] as num).toDouble(),
            'active': (r['active'] as bool) ? 1 : 0,
            'dirty': 0,
            'updated_at': r['updated_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      if (data.length < page) break;
      from += page;
    }
  }

  Future<void> _pullStoreInfo() async {
    final db = LocalDb.instance;
    final store =
        await _client.from('stores').select('name, code').maybeSingle();
    if (store != null) {
      await db.setMeta('store_name', store['name'] as String?);
      await db.setMeta('store_code', store['code'] as String?);
    }
    final sub = await _client
        .from('subscriptions')
        .select('status, active_until')
        .maybeSingle();
    if (sub != null) {
      await db.setMeta('sub_status', sub['status'] as String?);
      await db.setMeta('sub_until', sub['active_until'] as String?);
    }
  }
}
