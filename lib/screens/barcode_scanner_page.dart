import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// بيفتح الكاميرا ويرجّع أول باركود يتقرا (Navigator.pop(context, code)).
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('امسح الباركود')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          for (final b in capture.barcodes) {
            final code = b.rawValue;
            if (code != null && code.isNotEmpty) {
              _done = true;
              Navigator.of(context).pop(code);
              return;
            }
          }
        },
      ),
    );
  }
}
