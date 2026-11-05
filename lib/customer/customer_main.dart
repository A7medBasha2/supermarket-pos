import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'customer_auth.dart';
import 'store_code_screen.dart';
import 'store_data.dart';

/// نقطة دخول تطبيق العملاء:  flutter build apk --target lib/customer/customer_main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const CustomerApp());
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  String? _code;
  bool _booting = true;
  bool _loading = false;
  String? _error;
  String? _status; // active / suspended / not_found
  String? _suspendedName;
  StoreData? _store;
  Color _brand = const Color(0xFF2E7D32);

  /// لو الكود متحقن وقت البناء (نسخة المحل الخاصة) العميل مش بيكتبه
  bool get _codeIsBakedIn => AppConfig.storeCode.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    String? code = _codeIsBakedIn ? AppConfig.storeCode : null;
    if (code == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        code = prefs.getString('store_code');
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _code = code;
      _booting = false;
    });
    if (code != null) await _loadStore();
  }

  Future<void> _setCode(String raw) async {
    final code = raw.trim().toLowerCase();
    if (code.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('store_code', code);
    } catch (_) {}
    setState(() {
      _code = code;
      _status = null;
      _store = null;
      _error = null;
    });
    await _loadStore();
  }

  Future<void> _changeStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('store_code');
    } catch (_) {}
    setState(() {
      _code = null;
      _status = null;
      _store = null;
      _error = null;
    });
  }

  Future<void> _loadStore() async {
    final code = _code;
    if (code == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('public_catalog', params: {'p_code': code}).timeout(
              const Duration(seconds: 20));
      final map = Map<String, dynamic>.from(res as Map);
      final status = map['status'] as String;
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status == 'active') {
          _store = StoreData.fromCatalog(code, map);
          _brand = _store!.brandColor;
        } else {
          _store = null;
          _suspendedName = map['name'] as String?;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر الاتصال بالإنترنت');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _body() {
    if (_booting) return const _Loader();
    if (_code == null) return StoreCodeScreen(onSubmit: _setCode);
    if (_store == null && _loading) return const _Loader();
    if (_store == null && _error != null) {
      return _Message(
        icon: Icons.wifi_off,
        text: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _loadStore,
        secondLabel: _codeIsBakedIn ? null : 'تغيير المحل',
        onSecond: _codeIsBakedIn ? null : _changeStore,
      );
    }
    if (_status == 'not_found') {
      return _codeIsBakedIn
          ? const _Message(
              icon: Icons.error_outline,
              text: 'المتجر غير موجود. تأكد من نسخة التطبيق.')
          : StoreCodeScreen(
              onSubmit: _setCode, message: 'كود المحل غير صحيح، جرّب تاني');
    }
    if (_status == 'suspended') {
      return _Message(
        icon: Icons.storefront_outlined,
        text: '${_suspendedName ?? 'المتجر'} غير متاح حالياً.\nحاول مرة تانية لاحقاً.',
        actionLabel: 'تحديث',
        onAction: _loadStore,
        secondLabel: _codeIsBakedIn ? null : 'تغيير المحل',
        onSecond: _codeIsBakedIn ? null : _changeStore,
      );
    }
    final store = _store;
    if (store == null) return const _Loader();
    return CustomerAuthGate(store: store, onRefresh: _loadStore);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _store?.name ?? 'متجر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _brand, useMaterial3: true),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: _body(),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondLabel;
  final VoidCallback? onSecond;

  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.secondLabel,
    this.onSecond,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondLabel != null)
                TextButton(onPressed: onSecond, child: Text(secondLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}
