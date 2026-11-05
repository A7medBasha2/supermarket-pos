import 'package:flutter/material.dart';

import '../util.dart';
import 'checkout_screen.dart';
import 'store_data.dart';

class CartItem {
  final CatalogProduct product;
  int qty;
  CartItem(this.product, this.qty);

  double get total => product.price * qty;
}

class CartController extends ChangeNotifier {
  CartController._();
  static final CartController instance = CartController._();

  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();
  bool get isEmpty => _items.isEmpty;
  int get count => _items.values.fold(0, (s, i) => s + i.qty);
  double get subtotal => _items.values.fold(0.0, (s, i) => s + i.total);
  int qtyOf(String productId) => _items[productId]?.qty ?? 0;

  void add(CatalogProduct p) {
    final existing = _items[p.id];
    if (existing != null) {
      existing.qty += 1;
    } else {
      _items[p.id] = CartItem(p, 1);
    }
    notifyListeners();
  }

  void decrement(String productId) {
    final it = _items[productId];
    if (it == null) return;
    if (it.qty <= 1) {
      _items.remove(productId);
    } else {
      it.qty -= 1;
    }
    notifyListeners();
  }

  void remove(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

class CartScreen extends StatelessWidget {
  final StoreData store;
  const CartScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final cart = CartController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.isEmpty) {
            return const Center(child: Text('السلة فاضية'));
          }
          final subtotal = cart.subtotal;
          final belowMin = subtotal < store.minOrder;
          final total = subtotal + store.deliveryFee;
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final it = cart.items[i];
                    return ListTile(
                      title: Text(it.product.name),
                      subtitle: Text(
                          '${money(it.product.price)} × ${it.qty} = ${money(it.total)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => cart.decrement(it.product.id),
                          ),
                          Text('${it.qty}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => cart.add(it.product),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => cart.remove(it.product.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Column(
                  children: [
                    _row('المجموع', money(subtotal)),
                    _row('رسوم التوصيل', money(store.deliveryFee)),
                    _row('الإجمالي', money(total), bold: true),
                    if (belowMin)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'الحد الأدنى للطلب ${money(store.minOrder)}',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: belowMin
                            ? null
                            : () async {
                                final ok = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => CheckoutScreen(store: store)),
                                );
                                if (ok == true && context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                        child: const Text('متابعة لإتمام الطلب'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
