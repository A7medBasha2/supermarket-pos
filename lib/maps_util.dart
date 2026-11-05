import 'package:url_launcher/url_launcher.dart';

/// يفتح خرائط جوجل (التطبيق أو المتصفح) على نفس الإحداثيات بالظبط للملاحة.
Future<bool> openInGoogleMaps(double lat, double lng) async {
  try {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<bool> callPhone(String phone) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (_) {
    return false;
  }
}
