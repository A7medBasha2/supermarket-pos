/// بيانات الاتصال بـ Supabase بتتحقن وقت البناء من GitHub Secrets
/// (--dart-define) ومش بتتكتب في الكود.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
