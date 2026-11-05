class Product {
  final String id;
  final String name;
  final String? barcode;
  final double price;
  final double cost;
  final double stockQty;
  final double minStock;
  final bool active;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.cost,
    required this.stockQty,
    required this.minStock,
    required this.active,
  });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        price: (m['price'] as num).toDouble(),
        cost: (m['cost'] as num).toDouble(),
        stockQty: (m['stock_qty'] as num).toDouble(),
        minStock: (m['min_stock'] as num).toDouble(),
        active: (m['active'] as int) == 1,
      );

  bool get lowStock => stockQty <= minStock;
}

class CartLine {
  final Product product;
  double qty;

  CartLine(this.product, this.qty);

  double get total => qty * product.price;
}
