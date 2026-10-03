import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/api/api_config.dart';

/// Cobertura de ApiConfig: constantes expostas e header de auth.
///
/// baseUrl é compile-time (--dart-define API_BASE_URL, default
/// 10.0.2.2:3000/v1 pro emulador); em teste roda o default.
void main() {
  test('baseUrl default aponta pro emulador (10.0.2.2:3000/v1)', () {
    expect(ApiConfig.baseUrl, 'http://10.0.2.2:3000/v1');
  });

  test('timeout de rede é 15s', () {
    expect(ApiConfig.timeout, const Duration(seconds: 15));
  });

  test('authHeader é o header padrão Authorization', () {
    expect(ApiConfig.authHeader, 'Authorization');
  });
}
