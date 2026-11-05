import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models.dart';
import '../services/sync_service.dart';
import '../util.dart';
import 'barcode_scanner_page.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Product> _items = [];

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_onSync);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSync);
    _search.dispose();
    super.dispose();
  }

  void _onSync() {
    if (!SyncService.instance.syncing) _load();
  }

  Future<void> _load() async {
    final r = await LocalDb.instance.searchProducts(_search.text);
    if (!mounted) return;
    setState(() => _items = r);
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null) return;
    _search.text = code;
    _load();
  }

  Future<void> _open([Product? p]) async {
    if (!SyncService.instance.subscriptionActive) {
      showSnack(context, 'انتهى الاشتراك: لا يمكن تعديل المنتجات.', error: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)),
    );
    _load();
    SyncService.instance.refreshPending();
    SyncService.instance.sync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('منتج جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => _load(),
                    decoration: const InputDecoration(
                      labelText: 'بحث',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('لا توجد منتجات'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = _items[i];
                      return ListTile(
                        enabled: true,
                        title: Text(
                          p.name,
                          style: TextStyle(
                            color: p.active ? null : Theme.of(context).disabledColor,
                          ),
                        ),
                        subtitle: Text(
                          '${p.barcode ?? 'بدون باركود'}  •  '
                          'المخزون: ${fmtQty(p.stockQty)}'
                          '${p.active ? '' : '  •  متوقف'}',
                          style: TextStyle(
                              color: (p.active && p.lowStock)
                                  ? Colors.red.shade700
                                  : null),
                        ),
                        trailing: Text(money(p.price),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => _open(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
