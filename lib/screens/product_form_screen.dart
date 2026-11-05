import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models.dart';
import '../util.dart';
import 'barcode_scanner_page.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _barcode =
      TextEditingController(text: widget.product?.barcode ?? '');
  late final _price = TextEditingController(
      text: widget.product == null ? '' : fmtQty(widget.product!.price));
  late final _cost = TextEditingController(
      text: widget.product == null ? '' : fmtQty(widget.product!.cost));
  late final _stock = TextEditingController(
      text: widget.product == null ? '0' : fmtQty(widget.product!.stockQty));
  late final _minStock = TextEditingController(
      text: widget.product == null ? '0' : fmtQty(widget.product!.minStock));
  late bool _active = widget.product?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code != null) setState(() => _barcode.text = code);
  }

  double _num(TextEditingController c) => parseNum(c.text) ?? 0;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'اكتب اسم المنتج', error: true);
      return;
    }
    if (parseNum(_price.text) == null) {
      showSnack(context, 'اكتب سعر البيع', error: true);
      return;
    }
    final barcode = _barcode.text.trim().isEmpty ? null : _barcode.text.trim();
    final existing = widget.product;

    setState(() => _saving = true);
    try {
      if (barcode != null) {
        final dup = await LocalDb.instance.byBarcode(barcode);
        if (dup != null && dup.id != existing?.id) {
          if (mounted) {
            showSnack(context, 'الباركود ده مستخدم في منتج تاني: ${dup.name}',
                error: true);
          }
          return;
        }
      }

      final stock = _num(_stock);
      final delta = stock - (existing?.stockQty ?? 0);
      final pr = Product(
        id: existing?.id ?? LocalDb.instance.newId(),
        name: name,
        barcode: barcode,
        price: _num(_price),
        cost: _num(_cost),
        stockQty: stock,
        minStock: _num(_minStock),
        active: _active,
      );
      await LocalDb.instance.saveProduct(
        pr,
        stockDelta: delta,
        reason: existing == null ? 'opening' : 'adjustment',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, 'فشل الحفظ: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'منتج جديد' : 'تعديل منتج')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'اسم المنتج', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcode,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'الباركود (اختياري)',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'سعر البيع', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'سعر التكلفة', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stock,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: InputDecoration(
                      labelText: isNew ? 'الكمية الافتتاحية' : 'الكمية الحالية',
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minStock,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'حد التنبيه', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('المنتج متاح للبيع'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
