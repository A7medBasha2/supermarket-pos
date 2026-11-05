import 'package:flutter/material.dart';

const orderStatuses = [
  'new',
  'preparing',
  'out_for_delivery',
  'delivered',
  'cancelled',
];

String statusLabel(String s) {
  switch (s) {
    case 'new':
      return 'جديد';
    case 'preparing':
      return 'قيد التجهيز';
    case 'out_for_delivery':
      return 'في الطريق';
    case 'delivered':
      return 'تم التسليم';
    case 'cancelled':
      return 'ملغي';
    default:
      return s;
  }
}

Color statusColor(String s) {
  switch (s) {
    case 'new':
      return Colors.blue.shade700;
    case 'preparing':
      return Colors.orange.shade800;
    case 'out_for_delivery':
      return Colors.purple.shade600;
    case 'delivered':
      return Colors.green.shade700;
    case 'cancelled':
      return Colors.red.shade700;
    default:
      return Colors.grey;
  }
}

/// وصف دقة الموقع (accuracy_m = null يعني العميل حدد الدبوس يدوياً)
String accuracyText(num? meters) {
  if (meters == null) return 'حدّده العميل يدوياً على الخريطة';
  final m = meters.round();
  if (m <= 20) return 'دقة GPS ممتازة (±$m متر)';
  if (m <= 50) return 'دقة GPS متوسطة (±$m متر)';
  return 'دقة GPS ضعيفة (±$m متر) - يُفضّل الاتصال بالعميل للتأكد';
}
