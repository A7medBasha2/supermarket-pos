import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import 'pos_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    SyncService.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _StatusBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [
                  PosScreen(),
                  ProductsScreen(),
                  ReportsScreen(),
                  SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.point_of_sale), label: 'البيع'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'التقارير'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

/// شريط الحالة: اشتراك منتهي / بيانات لسه مارُفعتش
class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (!sync.subscriptionActive) {
          return _bar(Colors.red.shade700,
              'انتهى الاشتراك: التطبيق للقراءة فقط. جدّد الاشتراك لاستكمال البيع.');
        }
        if (sync.pending > 0) {
          return _bar(
            Colors.amber.shade800,
            'فيه ${sync.pending} عملية لسه ماتزامنتش'
            '${sync.lastError != null ? ' - ${sync.lastError}' : ''}',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _bar(Color color, String text) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      );
}
