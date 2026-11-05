import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models.dart';
import '../services/sync_service.dart';
import '../util.dart';
import 'barcode_scanner_page.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  final _discount = TextEditingController(text: '0');
  List<Product> _results = [];
  final List<CartLine> _cart = [];
  String _payment = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _discount.dispose();
    super.dispose();
  }

  double get _subtotal => _cart.fold<double>(0, (s, l) => s + l.total);
  double get _discountValue => double.tryParse(_discount.text.trim()) ?? 0;
  double get _total {
    final t = _subtotal - _discountValue;
    return t < 0 ? 0 : t;
  }

  Future<void> _onQueryChanged(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final r = await LocalDb.instance.searchProducts(q, activeOnly: true);
    if (!mounted) return;
    setState(() => _results = r.take(8).toList());
  }

  Future<void> _submit(String q) async {
    final code = q.trim();
    if (code.isEmpty) return;
    final byCode = await LocalDb.instance.byBarcode(code);
    if (byCode != null && byCode.active) {
      _add(byCode);
      return;
    }
    if (_results.length == 1) {
      _add(_results.first);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final pr = await LocalDb.instance.byBarcode(code);
    if (!mounted) return;
    if (pr == null || !pr.active) {
      showSnack(context, 'منتج غير موجود: $code', error: true);
      return;
    }
    _add(pr);
  }

  void _add(Product pr) {
    setState(() {
      final i = _cart.indexWhere((l) => l.product.id == pr.id);
      if (i >= 0) {
        _cart[i].qty += 1;
      } else {
        _cart.add(CartLine(pr, 1));
      }
      _search.clear();
      _results = [];
    });
  }

  Future<void> _editQty(CartLine line) async {
    final c = TextEditingController(text: fmtQty(line.qty));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.product.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الكمية'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())),
            child: const Text('تم'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    setState(() {
      if (v <= 0) {
        _cart.remove(line);
      } else {
        line.qty = v;
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _saving) return;
    if (!SyncService.instance.subscriptionActive) {
      showSnack(context, 'انتهى الاشتراك. جدّد الاشتراك لاستكمال البيع.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await LocalDb.instance.completeSale(
        lines: List<CartLine>.from(_cart),
        discount: _discountValue,
        paymentMethod: _payment,
      );
      final total = _total;
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _discount.text = '0';
      });
      showSnack(context, 'تم البيع: ${money(total)}');
      SyncService.instance.refreshPending();
      SyncService.instance.sync();
    } catch (e) {
      if (mounted) showSnack(context, 'فشل حفظ البيع: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onQueryChanged,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(
                    labelText: 'ابحث بالاسم أو الباركود',
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
                tooltip: 'مسح باركود',
              ),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pr in _results)
                  ListTile(
                    dense: true,
                    title: Text(pr.name),
                    subtitle: Text('المخزون: ${fmtQty(pr.stockQty)}'),
                    trailing: Text(money(pr.price)),
                    onTap: () => _add(pr),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('السلة فاضية'))
              : ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = _cart[i];
                    final over = l.qty > l.product.stockQty;
                    return ListTile(
                      title: Text(l.product.name),
                      subtitle: Text(
                        '${money(l.product.price)} × ${fmtQty(l.qty)}'
                        '${over ? '  (أكبر من المخزون)' : ''}',
                        style: TextStyle(
                            color: over ? Colors.red.shade700 : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => setState(() {
                              if (l.qty <= 1) {
                                _cart.removeAt(i);
                              } else {
                                l.qty -= 1;
                              }
                            }),
                          ),
                          InkWell(
                            onTap: () => _editQty(l),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(fmtQty(l.qty),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setState(() => l.qty += 1),
                          ),
                          SizedBox(
                            width: 72,
                            child: Text(money(l.total),
                                textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discount,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'خصم',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'cash', label: Text('نقدي')),
                      ButtonSegment(value: 'card', label: Text('فيزا')),
                      ButtonSegment(value: 'wallet', label: Text('محفظة')),
                    ],
                    selected: {_payment},
                    onSelectionChanged: (s) =>
                        setState(() => _payment = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('الإجمالي: ${money(_total)}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: (_cart.isEmpty || _saving) ? null : _checkout,
                    icon: const Icon(Icons.check),
                    label: const Text('إتمام البيع'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
