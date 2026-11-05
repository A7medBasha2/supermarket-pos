import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sync_service.dart';
import '../util.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _subText(SyncService s) {
    if (s.subStatus == null && s.subUntil == null) return 'غير معروف (يحتاج مزامنة)';
    final until = s.subUntil == null
        ? '-'
        : DateFormat('yyyy-MM-dd').format(s.subUntil!);
    final label = switch (s.subStatus) {
      'trial' => 'تجربة مجانية',
      'active' => 'نشط',
      'suspended' => 'موقوف',
      _ => '-',
    };
    return '$label - ينتهي: $until';
  }

  Future<void> _logout(BuildContext context) async {
    final sync = SyncService.instance;
    await sync.refreshPending();
    if (!context.mounted) return;
    if (sync.pending > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('فيه بيانات لسه ماتزامنتش'),
          content: Text(
              'فيه ${sync.pending} عملية لسه ماترفعتش للسيرفر. '
              'لو خرجت دلوقتي وسجّل دخول محل تاني على الجهاز ده هتضيع. '
              'الأفضل تعمل مزامنة الأول.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('خروج رغم كده')),
          ],
        ),
      );
      if (ok != true) return;
    }
    sync.stop();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(sync.storeName ?? '-'),
              subtitle: const Text('اسم السوبر ماركت'),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: SelectableText(sync.storeCode ?? '-'),
              subtitle: const Text('كود المحل (لنسخة العملاء)'),
            ),
            ListTile(
              leading: Icon(
                sync.subscriptionActive ? Icons.verified_outlined : Icons.block,
                color: sync.subscriptionActive ? null : Colors.red.shade700,
              ),
              title: Text(_subText(sync)),
              subtitle: const Text('الاشتراك'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(sync.syncing
                  ? 'جاري المزامنة...'
                  : 'آخر مزامنة: ${sync.lastSync == null ? '-' : DateFormat('yyyy-MM-dd HH:mm').format(sync.lastSync!)}'),
              subtitle: Text(
                  'لم تُرفع بعد: ${sync.pending}${sync.lastError != null ? '\n${sync.lastError}' : ''}'),
              trailing: FilledButton(
                onPressed: sync.syncing
                    ? null
                    : () async {
                        await sync.sync();
                        if (context.mounted && sync.lastError == null) {
                          showSnack(context, 'تمت المزامنة');
                        }
                      },
                child: const Text('مزامنة الآن'),
              ),
              isThreeLine: sync.lastError != null,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('تسجيل خروج'),
              onTap: () => _logout(context),
            ),
          ],
        );
      },
    );
  }
}
