import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../services/orders_service.dart';
import '../services/sync_service.dart';
import 'orders_screen.dart';
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
  int _seenTick = 0;

  @override
  void initState() {
    super.initState();
    SyncService.instance.start();
    _seenTick = OrdersService.instance.arrivalTick;
    OrdersService.instance.addListener(_onOrders);
    LocalDb.instance.getMeta('store_id').then((id) {
      if (id != null) OrdersService.instance.start(id);
    });
  }

  @override
  void dispose() {
    OrdersService.instance.removeListener(_onOrders);
    super.dispose();
  }

  /// تنبيه طلب جديد (شغّال وإنت جوه التطبيق)
  void _onOrders() {
    final tick = OrdersService.instance.arrivalTick;
    if (tick != _seenTick && mounted) {
      _seenTick = tick;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: const Text('وصلك طلب جديد من عميل!'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'عرض',
          onPressed: () => setState(() => _index = 1),
        ),
      ));
    }
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
                  OrdersScreen(),
                  ProductsScreen(),
                  ReportsScreen(),
                  SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: OrdersService.instance,
        builder: (context, _) {
          final n = OrdersService.instance.newCount;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.point_of_sale), label: 'البيع'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: n > 0,
                  label: Text('$n'),
                  child: const Icon(Icons.delivery_dining),
                ),
                label: 'الطلبات',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart), label: 'التقارير'),
              const NavigationDestination(
                  icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
            ],
          );
        },
      ),
    );
  }
}

/// شريط الحالة: اشتراك منتهي / بيانات لسه مارُفعتش / منتجات قاربت على النفاد (بيشتغل أوفلاين)
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
        final warn = sync.subscriptionWarning;
        if (warn != null) {
          return _bar(Colors.orange.shade800, warn);
        }
        if (sync.pending > 0) {
          return _bar(
            Colors.amber.shade800,
            'فيه ${sync.pending} عملية لسه ماتزامنتش'
            '${sync.lastError != null ? ' - ${sync.lastError}' : ''}',
          );
        }
        if (sync.lowStockCount > 0) {
          return _bar(Colors.deepOrange.shade700,
              'تنبيه: ${sync.lowStockCount} منتج قارب على النفاد (شوف تبويب التقارير)');
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
