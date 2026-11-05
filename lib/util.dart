import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _moneyFmt = NumberFormat('#,##0.00');

String money(num v) => _moneyFmt.format(v);

/// كمية: بدون كسور لو رقم صحيح (مثلاً 3) وإلا بالكسر (مثلاً 1.5)
String fmtQty(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : null,
  ));
}

String isoNow() => DateTime.now().toUtc().toIso8601String();
