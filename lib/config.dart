/// بيانات الاتصال بـ Supabase بتتحقن وقت البناء من GitHub Secrets
/// (--dart-define) ومش بتتكتب في الكود.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// كود المحل لنسخة العملاء. لو فاضي، التطبيق بيطلب من العميل يكتب الكود.
  static const storeCode = String.fromEnvironment('STORE_CODE');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
