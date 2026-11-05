import 'package:flutter/material.dart';

/// شاشة كتابة كود المحل (للنسخة العامة من تطبيق العملاء)
class StoreCodeScreen extends StatefulWidget {
  final Future<void> Function(String code) onSubmit;
  final String? message;
  const StoreCodeScreen({super.key, required this.onSubmit, this.message});

  @override
  State<StoreCodeScreen> createState() => _StoreCodeScreenState();
}

class _StoreCodeScreenState extends State<StoreCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await widget.onSubmit(_code.text);
    if (mounted) setState(() => _busy = false);
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
                  Text('اكتب كود المحل',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('الكود بتاخده من السوبر ماركت بتاعك.',
                      textAlign: TextAlign.center),
                  if (widget.message != null) ...[
                    const SizedBox(height: 12),
                    Text(widget.message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700)),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    autocorrect: false,
                    onSubmitted: (_) => _go(),
                    decoration: const InputDecoration(
                        labelText: 'كود المحل', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _go,
                    child: const Text('متابعة'),
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
