import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// بيفتح الكاميرا ويرجّع أول باركود يتقرا (Navigator.pop(context, code)).
/// لو الكاميرا فشلت بيعرض السبب بوضوح، وفيه زر لكتابة الباركود يدوياً.
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _done = false;

  void _finish(String code) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _typeManually() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اكتب الباركود'),
        content: TextField(
          controller: c,
          autofocus: true,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('تم')),
        ],
      ),
    );
    c.dispose();
    if (code != null && code.isNotEmpty) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('امسح الباركود'),
        actions: [
          IconButton(
            tooltip: 'كتابة الباركود يدوياً',
            icon: const Icon(Icons.keyboard),
            onPressed: _typeManually,
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final code = b.rawValue;
            if (code != null && code.isNotEmpty) {
              _finish(code);
              return;
            }
          }
        },
        errorBuilder: (context, error, child) {
          final denied =
              error.errorCode == MobileScannerErrorCode.permissionDenied;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    denied
                        ? 'التطبيق محتاج صلاحية الكاميرا.\n'
                            'فعّلها من إعدادات الموبايل ← التطبيقات ← الصلاحيات ← الكاميرا.'
                        : 'تعذّر تشغيل الكاميرا (${error.errorCode.name}).',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _typeManually,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('اكتب الباركود يدوياً'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
