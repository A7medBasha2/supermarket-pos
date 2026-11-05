import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util.dart';
import 'customer_shell.dart';
import 'store_data.dart';

SupabaseClient get _client => Supabase.instance.client;

/// تسجيل دخول العميل بالإيميل وكلمة المرور (أو حساب جديد)
class CustomerAuthGate extends StatelessWidget {
  final StoreData store;
  final Future<void> Function() onRefresh;
  const CustomerAuthGate({super.key, required this.store, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = _client.auth.currentSession;
        if (session == null) return CustomerAuthScreen(store: store);
        return CustomerGate(
          key: ValueKey('${session.user.id}-${store.id}'),
          store: store,
          onRefresh: onRefresh,
        );
      },
    );
  }
}

class CustomerAuthScreen extends StatefulWidget {
  final StoreData store;
  const CustomerAuthScreen({super.key, required this.store});

  @override
  State<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends State<CustomerAuthScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _err(String m) => showSnack(context, m, error: true);

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _err('اكتب البريد الإلكتروني وكلمة المرور');
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      if (mounted) _err(e.message);
    } catch (_) {
      if (mounted) _err('تعذّر الاتصال بالإنترنت');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _email.text.trim().isEmpty) {
      _err('اكمل كل البيانات: الاسم، الموبايل، البريد');
      return;
    }
    if (_password.text.length < 6) {
      _err('كلمة المرور لازم تكون 6 حروف أو أرقام على الأقل');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()},
      );
      if (mounted && res.session == null) {
        showSnack(context,
            'تم إنشاء الحساب. أكّد بريدك الإلكتروني من الرسالة ثم سجّل الدخول.');
        setState(() => _signup = false);
      }
    } on AuthException catch (e) {
      if (mounted) _err(e.message);
    } catch (_) {
      if (mounted) _err('تعذّر الاتصال بالإنترنت');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false, TextInputType? type, bool ltr = false, IconData? icon}) {
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
                  Text(widget.store.name,
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
                    onSelectionChanged: (s) => setState(() => _signup = s.first),
                  ),
                  const SizedBox(height: 20),
                  if (_signup) ...[
                    _field(_name, 'الاسم', icon: Icons.person_outline),
                    _field(_phone, 'رقم الموبايل',
                        type: TextInputType.phone, ltr: true, icon: Icons.phone_outlined),
                  ],
                  _field(_email, 'البريد الإلكتروني',
                      type: TextInputType.emailAddress,
                      ltr: true,
                      icon: Icons.email_outlined),
                  _field(_password, 'كلمة المرور',
                      obscure: true, ltr: true, icon: Icons.lock_outline),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : (_signup ? _createAccount : _login),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signup ? 'إنشاء الحساب' : 'تسجيل الدخول'),
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

/// بعد تسجيل الدخول: نتأكد إن العميل مسجّل في المحل ده (وإلا نسجّله من بياناته)
class CustomerGate extends StatefulWidget {
  final StoreData store;
  final Future<void> Function() onRefresh;
  const CustomerGate({super.key, required this.store, required this.onRefresh});

  @override
  State<CustomerGate> createState() => _CustomerGateState();
}

class _CustomerGateState extends State<CustomerGate> {
  late Future<Map<String, dynamic>?> _future = _ensure();

  Future<Map<String, dynamic>?> _fetch() {
    return _client
        .from('customers')
        .select()
        .eq('user_id', _client.auth.currentUser!.id)
        .eq('store_id', widget.store.id)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> _ensure() async {
    final row = await _fetch();
    if (row != null) return row;
    final meta = _client.auth.currentUser?.userMetadata ?? {};
    final name = ((meta['full_name'] as String?) ?? '').trim();
    final phone = ((meta['phone'] as String?) ?? '').trim();
    if (name.isNotEmpty && phone.isNotEmpty) {
      await _client.rpc('register_customer', params: {
        'p_store_code': widget.store.code,
        'p_full_name': name,
        'p_phone': phone,
      });
      return _fetch();
    }
    return null; // محتاج يكمل بياناته
  }

  void _reload() => setState(() => _future = _ensure());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
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
                    const Text('تعذّر الاتصال بالإنترنت', textAlign: TextAlign.center),
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
        final customer = snap.data;
        if (customer == null) {
          return _CompleteProfile(store: widget.store, onDone: _reload);
        }
        return CustomerShell(
          store: widget.store,
          customer: customer,
          onRefresh: widget.onRefresh,
        );
      },
    );
  }
}

class _CompleteProfile extends StatefulWidget {
  final StoreData store;
  final VoidCallback onDone;
  const _CompleteProfile({required this.store, required this.onDone});

  @override
  State<_CompleteProfile> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends State<_CompleteProfile> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      showSnack(context, 'اكتب الاسم ورقم الموبايل', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.rpc('register_customer', params: {
        'p_store_code': widget.store.code,
        'p_full_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
      });
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
        title: Text(widget.store.name),
        actions: [
          TextButton(
              onPressed: () => _client.auth.signOut(), child: const Text('خروج')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أكمل بياناتك عشان نقدر نوصّلك الطلب.'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'الاسم', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'رقم الموبايل', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}
