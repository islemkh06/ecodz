class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xcklutpwyvpbrotrobuc.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhja2x1dHB3eXZwYnJvdHJvYnVjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5ODY1MjQsImV4cCI6MjA5MDU2MjUyNH0.cwGWK3rK8JBppHd2-c13AmOc2nsyUK3Moi0HsmyE_Ps',
  );

  static void validate() {
    final uri = Uri.tryParse(url);

    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError('Supabase URL or anon key is empty.');
    }

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Supabase URL is invalid: $url');
    }
  }
}
