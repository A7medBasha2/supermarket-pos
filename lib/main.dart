import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'إدارة السوبر ماركت',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      // الواجهة عربي (من اليمين لليسار)
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: AppConfig.isConfigured ? const AuthGate() : const _ConfigMissing(),
    );
  }
}

class _ConfigMissing extends StatelessWidget {
  const _ConfigMissing();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'التطبيق غير مربوط بقاعدة البيانات.\n'
            'أضف SUPABASE_URL و SUPABASE_ANON_KEY في GitHub Secrets ثم أعد البناء.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
