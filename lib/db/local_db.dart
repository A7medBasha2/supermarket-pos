import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../util.dart';

/// قاعدة البيانات المحلية (SQLite) - مصدر الحقيقة للواجهة.
/// كل العمليات بتتسجل هنا الأول (حتى من غير نت) وبعدين بتتزامن مع Supabase.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const _uuid = Uuid();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'pos.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            barcode TEXT,
            price REAL NOT NULL DEFAULT 0,
            cost REAL NOT NULL DEFAULT 0,
            stock_qty REAL NOT NULL DEFAULT 0,
            min_stock REAL NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1,
            dirty INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT
          )''');
        await d.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
        await d.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            total REAL NOT NULL,
            discount REAL NOT NULL DEFAULT 0,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            created_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT,
            name TEXT NOT NULL,
            qty REAL NOT NULL,
            price REAL NOT NULL,
            cost REAL NOT NULL DEFAULT 0
          )''');
        await d.execute('CREATE INDEX idx_items_sale ON sale_items(sale_id)');
        await d.execute('''
          CREATE TABLE stock_movements (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            qty_delta REAL NOT NULL,
            reason TEXT NOT NULL,
            ref_id TEXT,
            created_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )''');
      },
    );
    return _db!;
  }

  // ------------------------------------------------------------------ meta
  Future<String?> getMeta(String key) async {
    final d = await db;
    final rows = await d.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    final d = await db;
    await d.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// لو مستخدم من سوبر ماركت تاني سجّل دخول على نفس الجهاز، نمسح البيانات القديمة.
  Future<void> resetForStore(String storeId, String userId) async {
    final d = await db;
    final current = await getMeta('store_id');
    if (current != null && current != storeId) {
      await d.transaction((txn) async {
        await txn.delete('products');
        await txn.delete('sales');
        await txn.delete('sale_items');
        await txn.delete('stock_movements');
        await txn.delete('meta');
      });
    }
    await setMeta('store_id', storeId);
    await setMeta('user_id', userId);
  }

  // -------------------------------------------------------------- products
  Future<List<Product>> searchProducts(String q, {bool activeOnly = false}) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (activeOnly) where.add('active = 1');
    final term = q.trim();
    if (term.isNotEmpty) {
      where.add('(name LIKE ? OR barcode LIKE ?)');
      args
        ..add('%$term%')
        ..add('%$term%');
    }
    final rows = await d.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE',
      limit: 300,
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> byBarcode(String code) async {
    final d = await db;
    final rows = await d.query('products',
        where: 'barcode = ?', whereArgs: [code.trim()], limit: 1);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  String newId() => _uuid.v4();

  /// حفظ منتج (جديد أو تعديل). أي تغيير في الكمية بيتسجل كحركة مخزون.
  Future<void> saveProduct(
    Product pr, {
    required double stockDelta,
    required String reason,
  }) async {
    final d = await db;
    final now = isoNow();
    await d.transaction((txn) async {
      await txn.insert(
        'products',
        {
          'id': pr.id,
          'name': pr.name,
          'barcode': pr.barcode,
          'price': pr.price,
          'cost': pr.cost,
          'stock_qty': pr.stockQty,
          'min_stock': pr.minStock,
          'active': pr.active ? 1 : 0,
          'dirty': 1,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (stockDelta != 0) {
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': pr.id,
          'qty_delta': stockDelta,
          'reason': reason,
          'ref_id': null,
          'created_at': now,
          'synced': 0,
        });
      }
    });
  }

  // ----------------------------------------------------------------- sales
  Future<String> completeSale({
    required List<CartLine> lines,
    required double discount,
    required String paymentMethod,
  }) async {
    final d = await db;
    final saleId = _uuid.v4();
    final subtotal = lines.fold<double>(0, (s, l) => s + l.total);
    final total = math.max(0.0, subtotal - discount);
    final now = isoNow();

    await d.transaction((txn) async {
      await txn.insert('sales', {
        'id': saleId,
        'total': total,
        'discount': discount,
        'payment_method': paymentMethod,
        'created_at': now,
        'synced': 0,
      });
      for (final l in lines) {
        await txn.insert('sale_items', {
          'id': _uuid.v4(),
          'sale_id': saleId,
          'product_id': l.product.id,
          'name': l.product.name,
          'qty': l.qty,
          'price': l.product.price,
          'cost': l.product.cost,
        });
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': l.product.id,
          'qty_delta': -l.qty,
          'reason': 'sale',
          'ref_id': saleId,
          'created_at': now,
          'synced': 0,
        });
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
          [l.qty, l.product.id],
        );
      }
    });
    return saleId;
  }

  // --------------------------------------------------------------- reports
  Future<Map<String, num>> summarySince(String sinceIso) async {
    final d = await db;
    final s = await d.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total),0) AS t, COALESCE(SUM(discount),0) AS disc '
      'FROM sales WHERE created_at >= ?',
      [sinceIso],
    );
    final g = await d.rawQuery(
      'SELECT COALESCE(SUM((si.price - si.cost) * si.qty),0) AS gp '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE s.created_at >= ?',
      [sinceIso],
    );
    final disc = (s.first['disc'] as num);
    return {
      'count': s.first['c'] as num,
      'revenue': s.first['t'] as num,
      'profit': (g.first['gp'] as num) - disc,
    };
  }

  Future<List<Map<String, Object?>>> topProductsSince(String sinceIso) async {
    final d = await db;
    return d.rawQuery(
      'SELECT si.name AS name, SUM(si.qty) AS q, SUM(si.qty * si.price) AS r '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      'WHERE s.created_at >= ? GROUP BY si.name ORDER BY q DESC LIMIT 5',
      [sinceIso],
    );
  }

  Future<List<Product>> lowStock() async {
    final d = await db;
    final rows = await d.query('products',
        where: 'active = 1 AND stock_qty <= min_stock',
        orderBy: 'stock_qty ASC',
        limit: 30);
    return rows.map(Product.fromMap).toList();
  }

  // ----------------------------------------------------------------- sync
  Future<int> pendingCount() async {
    final d = await db;
    final a = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM sales WHERE synced = 0')) ??
        0;
    final b = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM products WHERE dirty = 1')) ??
        0;
    final c = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM stock_movements WHERE synced = 0 AND ref_id IS NULL')) ??
        0;
    return a + b + c;
  }
}
