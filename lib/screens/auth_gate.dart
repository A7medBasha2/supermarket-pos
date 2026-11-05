import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';
import '../util.dart';
import 'home_screen.dart';

SupabaseClient get _client => Supabase.instance.client;

/// يحدد الشاشة: تسجيل دخول / تسجيل محل جديد / الشاشة الرئيسية
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = _client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return StoreGate(key: ValueKey(session.user.id), userId: session.user.id);
      },
    );
  }
}

// ---------------------------------------------------------------- Login
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await _client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر الاتصال بالإنترنت', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    setState(() => _busy = true);
    try {
      final res = await _client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted && res.session == null) {
        showSnack(context, 'تم إنشاء الحساب. أكّد بريدك الإلكتروني ثم سجّل الدخول.');
      }
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر الاتصال بالإنترنت', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.storefront, size: 72),
                  const SizedBox(height: 12),
                  Text('إدارة السوبر ماركت',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'كلمة المرور', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('تسجيل الدخول'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _signUp,
                    child: const Text('إنشاء حساب جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Store gate
class StoreGate extends StatefulWidget {
  final String userId;
  const StoreGate({super.key, required this.userId});

  @override
  State<StoreGate> createState() => _StoreGateState();
}

class _StoreGateState extends State<StoreGate> {
  late Future<String?> _future = _resolve();

  /// بيرجع store_id للمستخدم، أو null لو لسه ماعملش محل.
  Future<String?> _resolve() async {
    final db = LocalDb.instance;
    try {
      final row = await _client
          .from('profiles')
          .select('store_id')
          .eq('id', widget.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      final sid = row?['store_id'] as String?;
      if (sid != null) await db.resetForStore(sid, widget.userId);
      return sid;
    } catch (e) {
      // أوفلاين: نستخدم المحل المخزّن لو هو نفس المستخدم
      final cachedUser = await db.getMeta('user_id');
      final cachedStore = await db.getMeta('store_id');
      if (cachedUser == widget.userId && cachedStore != null) return cachedStore;
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _resolve());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذّر الاتصال. أول تسجيل دخول يحتاج إنترنت.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _reload, child: const Text('إعادة المحاولة')),
                    TextButton(
                        onPressed: () => _client.auth.signOut(),
                        child: const Text('تسجيل خروج')),
                  ],
                ),
              ),
            ),
          );
        }
        if (snap.data == null) return RegisterStoreScreen(onDone: _reload);
        return const HomeScreen();
      },
    );
  }
}

// -------------------------------------------------------- Register store
class RegisterStoreScreen extends StatefulWidget {
  final VoidCallback onDone;
  const RegisterStoreScreen({super.key, required this.onDone});

  @override
  State<RegisterStoreScreen> createState() => _RegisterStoreScreenState();
}

class _RegisterStoreScreenState extends State<RegisterStoreScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'اكتب اسم السوبر ماركت', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.rpc('register_store', params: {'p_store_name': name});
      widget.onDone();
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذّر الاتصال بالإنترنت', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء السوبر ماركت'),
        actions: [
          TextButton(
              onPressed: () => _client.auth.signOut(),
              child: const Text('خروج')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('اكتب اسم السوبر ماركت. هتاخد تجربة مجانية 14 يوم.'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'اسم السوبر ماركت', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _register,
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}
