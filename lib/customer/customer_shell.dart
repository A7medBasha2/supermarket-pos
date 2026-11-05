import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../maps_util.dart';
import '../util.dart';
import 'cart.dart';
import 'my_orders_screen.dart';
import 'store_data.dart';

class CustomerShell extends StatefulWidget {
  final StoreData store;
  final Map<String, dynamic> customer;
  final Future<void> Function() onRefresh;
  const CustomerShell({
    super.key,
    required this.store,
    required this.customer,
    required this.onRefresh,
  });

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;
  int _ordersTick = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _CatalogTab(
            store: widget.store,
            onRefresh: widget.onRefresh,
            onOrdered: () => setState(() {
              _index = 1;
              _ordersTick++;
            }),
          ),
          MyOrdersScreen(key: ValueKey(_ordersTick), store: widget.store),
          _AccountTab(store: widget.store, customer: widget.customer),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'المتجر'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'طلباتي'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Catalog
class _CatalogTab extends StatefulWidget {
  final StoreData store;
  final Future<void> Function() onRefresh;
  final VoidCallback onOrdered;
  const _CatalogTab({
    required this.store,
    required this.onRefresh,
    required this.onOrdered,
  });

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final cart = CartController.instance;
    final q = _search.text.trim().toLowerCase();
    final products = store.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(store.name)),
      floatingActionButton: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () async {
              final ordered = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => CartScreen(store: store)),
              );
              if (ordered == true) widget.onOrdered();
            },
            icon: Badge(label: Text('${cart.count}'), child: const Icon(Icons.shopping_cart)),
            label: Text('السلة • ${money(cart.subtotal)}'),
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListenableBuilder(
          listenable: cart,
          builder: (context, _) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (!store.acceptingOrders)
                  Container(
                    color: Colors.red.shade700,
                    padding: const EdgeInsets.all(10),
                    child: const Text(
                      'المتجر لا يستقبل طلبات حالياً',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'رسوم التوصيل ${money(store.deliveryFee)}'
                    '${store.minOrder > 0 ? ' • الحد الأدنى ${money(store.minOrder)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'ابحث عن منتج',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لا توجد منتجات')),
                  ),
                for (final p in products)
                  ListTile(
                    title: Text(p.name),
                    subtitle: p.inStock
                        ? null
                        : Text('غير متوفر حالياً',
                            style: TextStyle(color: Colors.red.shade700)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(money(p.price),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        if (cart.qtyOf(p.id) > 0) ...[
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => cart.decrement(p.id),
                          ),
                          Text('${cart.qtyOf(p.id)}'),
                        ],
                        IconButton.filled(
                          icon: const Icon(Icons.add),
                          onPressed: (p.inStock && store.acceptingOrders)
                              ? () => cart.add(p)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Account
class _AccountTab extends StatelessWidget {
  final StoreData store;
  final Map<String, dynamic> customer;
  const _AccountTab({required this.store, required this.customer});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text('${customer['full_name']}'),
            subtitle: Text('${customer['phone']}\n$email'),
            isThreeLine: true,
          ),
          if (store.phone != null && store.phone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.call),
              title: Text('اتصل بـ ${store.name}'),
              subtitle: Text(store.phone!, textDirection: TextDirection.ltr),
              onTap: () async {
                final ok = await callPhone(store.phone!);
                if (!ok && context.mounted) {
                  showSnack(context, 'تعذّر فتح الاتصال', error: true);
                }
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('تسجيل خروج'),
            onTap: () async {
              CartController.instance.clear();
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
