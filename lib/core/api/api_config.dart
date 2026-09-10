/// Configuração da API via --dart-define (padrão pianolouvorja-flutter).
/// Build: flutter build apk --dart-define=API_BASE_URL=https://api.exemplo.com/v1
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/v1',
  );
  static const Duration timeout = Duration(seconds: 15);
  static String get authHeader => 'Authorization';
}
