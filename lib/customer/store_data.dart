import 'package:flutter/material.dart';

Color parseHexColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

class CatalogProduct {
  final String id;
  final String name;
  final String? barcode;
  final double price;
  final bool inStock;

  const CatalogProduct({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.inStock,
  });

  factory CatalogProduct.fromJson(Map<String, dynamic> m) => CatalogProduct(
        id: m['id'] as String,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        price: (m['price'] as num).toDouble(),
        inStock: m['in_stock'] as bool,
      );
}

/// بيانات المحل والكتالوج من public_catalog
class StoreData {
  final String id;
  final String code;
  final String name;
  final Color brandColor;
  final String? logoUrl;
  final String? phone;
  final double deliveryFee;
  final double minOrder;
  final bool acceptingOrders;

  /// لو السيرفر لسه على النسخة القديمة (قبل migration 003) مفيش اختيار توصيل/استلام:
  /// الطلب توصيل فقط. [supportsFulfillment] بيبقى false والتطبيق بيشتغل بالطريقة القديمة.
  final bool supportsFulfillment;
  final bool deliveryEnabled;
  final bool pickupEnabled;
  final List<CatalogProduct> products;

  const StoreData({
    required this.id,
    required this.code,
    required this.name,
    required this.brandColor,
    required this.logoUrl,
    required this.phone,
    required this.deliveryFee,
    required this.minOrder,
    required this.acceptingOrders,
    required this.supportsFulfillment,
    required this.deliveryEnabled,
    required this.pickupEnabled,
    required this.products,
  });

  bool get deliveryAvailable => deliveryEnabled;
  bool get pickupAvailable => supportsFulfillment && pickupEnabled;

  factory StoreData.fromCatalog(String code, Map<String, dynamic> m) {
    final s = Map<String, dynamic>.from(m['store'] as Map);
    final products = (m['products'] as List)
        .map((e) => CatalogProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final hasFulfillment = s.containsKey('pickup_enabled');
    return StoreData(
      id: s['id'] as String,
      code: code,
      name: s['name'] as String,
      brandColor: parseHexColor(s['brand_color'] as String?, const Color(0xFF2E7D32)),
      logoUrl: s['logo_url'] as String?,
      phone: s['phone'] as String?,
      deliveryFee: (s['delivery_fee'] as num).toDouble(),
      minOrder: (s['min_order'] as num).toDouble(),
      acceptingOrders: s['accepting_orders'] as bool,
      supportsFulfillment: hasFulfillment,
      deliveryEnabled: (s['delivery_enabled'] as bool?) ?? true,
      pickupEnabled: hasFulfillment ? ((s['pickup_enabled'] as bool?) ?? false) : false,
      products: products,
    );
  }
}
