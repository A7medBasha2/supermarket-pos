import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';
import '../util.dart';
import 'home_screen.dart';

SupabaseClient get _client => Supabase.instance.client;

/// اسم المحل اللي اتكتب في شاشة "حساب جديد" - بنسجّله تلقائياً بعد إنشاء الحساب
class _PendingSignup {
  static String? storeName;
}

/// يحدد الشاشة: تسجيل دخول / حساب جديد / الشاشة الرئيسية
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
  final _ownerName = TextEditingController();
  final _storeName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _signup = false;
  bool _busy = false;

  @override
  void dispose() {
    _ownerName.dispose();
    _storeName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  void _err(String msg) => showSnack(context, msg, error: true);

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _err('اكتب البريد الإلكتروني وكلمة المرور');
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      if (mounted) _err(e.message);
    } catch (_) {
      if (mounted) _err('تعذّر الاتصال بالإنترنت');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    final owner = _ownerName.text.trim();
    final store = _storeName.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    if (owner.isEmpty || store.isEmpty || phone.isEmpty || email.isEmpty) {
      _err('اكمل كل البيانات: الاسم، اسم السوبر ماركت، الموبايل، البريد');
      return;
    }
    if (_password.text.length < 6) {
      _err('كلمة المرور لازم تكون 6 حروف أو أرقام على الأقل');
      return;
    }
    if (_password.text != _password2.text) {
      _err('كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() => _busy = true);
    try {
      _PendingSignup.storeName = store;
      final res = await _client.auth.signUp(
        email: email,
        password: _password.text,
        data: {'full_name': owner, 'phone': phone},
      );
      if (mounted && res.session == null) {
        _PendingSignup.storeName = null;
        showSnack(context,
            'تم إنشاء الحساب. أكّد بريدك الإلكتروني من الرسالة ثم سجّل الدخول.');
        setState(() => _signup = false);
      }
      // لو فيه session: AuthGate هيفتح الشاشة الرئيسية وينشئ المحل تلقائياً
    } on AuthException catch (e) {
      _PendingSignup.storeName = null;
      if (mounted) _err(e.message);
    } catch (_) {
      _PendingSignup.storeName = null;
      if (mounted) _err('تعذّر الاتصال بالإنترنت');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false,
      TextInputType? type,
      bool ltr = false,
      IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
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
                  const Icon(Icons.storefront, size: 64),
                  const SizedBox(height: 8),
                  Text('إدارة السوبر ماركت',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('تسجيل الدخول')),
                      ButtonSegment(value: true, label: Text('حساب جديد')),
                    ],
                    selected: {_signup},
                    onSelectionChanged: (s) =>
                        setState(() => _signup = s.first),
                  ),
                  const SizedBox(height: 20),
                  if (_signup) ...[
                    _field(_ownerName, 'اسمك', icon: Icons.person_outline),
                    _field(_storeName, 'اسم السوبر ماركت',
                        icon: Icons.storefront_outlined),
                    _field(_phone, 'رقم الموبايل',
                        type: TextInputType.phone,
                        ltr: true,
                        icon: Icons.phone_outlined),
                  ],
                  _field(_email, 'البريد الإلكتروني',
                      type: TextInputType.emailAddress,
                      ltr: true,
                      icon: Icons.email_outlined),
                  _field(_password, 'كلمة المرور',
                      obscure: true, ltr: true, icon: Icons.lock_outline),
                  if (_signup)
                    _field(_password2, 'تأكيد كلمة المرور',
                        obscure: true, ltr: true, icon: Icons.lock_outline),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : (_signup ? _createAccount : _login),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signup ? 'إنشاء الحساب والمحل' : 'تسجيل الدخول'),
                  ),
                  if (_signup)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('تجربة مجانية 14 يوم بعد التسجيل.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12)),
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

  Future<String?> _fetchStoreId() async {
    final row = await _client
        .from('profiles')
        .select('store_id')
        .eq('id', widget.userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    return row?['store_id'] as String?;
  }

  /// بيرجع store_id للمستخدم، أو null لو لسه ماعملش محل.
  Future<String?> _resolve() async {
    final db = LocalDb.instance;
    try {
      var sid = await _fetchStoreId();
      // حساب جديد لسه ماله محل: ننشئه تلقائياً من الاسم اللي اتكتب في التسجيل
      final pendingName = _PendingSignup.storeName;
      if (sid == null && pendingName != null) {
        _PendingSignup.storeName = null;
        await _client.rpc('register_store', params: {'p_store_name': pendingName});
        sid = await _fetchStoreId();
      }
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
                    const SizedBox(height: 8),
                    Text('${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11)),
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
/// بتظهر بس لو حساب موجود وملوش محل (مثلاً أكّد الإيميل وسجّل دخول بعدين)
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
