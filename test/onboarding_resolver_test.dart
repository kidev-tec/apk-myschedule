import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/storage/onboarding_resolver.dart';
import 'package:minha_agenda/core/storage/onboarding_store.dart';

/// Cenário do bug mmmarckos (22/09): conta autenticada no Firebase mas
/// INEXISTENTE no Postgres (sync falhou). O GET /me responde 404 e o
/// resolver NÃO pode cair na flag local — ela é global por aparelho e
/// estava true por causa de OUTRA conta, o que pulava o onboarding e
/// deixava a conta nova sem user/business (fantasma).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notFoundBody = {'message': 'User or business not found'};

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    // garante flag local suja: simula aparelho onde outra conta completou
    await OnboardingStore.markComplete();
  });

  ApiClient clientWith(DioAdapter mocker) {
    final client = ApiClient();
    client.dio.httpClientAdapter = mocker;
    return client;
  }

  test('GET /me 404 → SEMPRE onboarding (ignora flag local true)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    final mocker = DioAdapter(dio: dio);
    mocker.onGet(
      '/me',
      (server) => server.reply(404, notFoundBody),
    );

    final result = await resolveOnboardingComplete(clientWith(mocker));

    expect(result, isFalse,
        reason: 'conta sem registro no servidor precisa passar pelo '
            'onboarding (que provisiona via ensureProvisioned)');
    // flag local suja deve ter sido limpa
    expect(await OnboardingStore.isComplete(), isFalse);
    mocker.close();
  });

  test('GET /me 200 + onboarding_complete true → agenda (e marca local)',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    final mocker = DioAdapter(dio: dio);
    mocker.onGet(
      '/me',
      (server) => server.reply(200, {'onboarding_complete': true}),
    );

    final result = await resolveOnboardingComplete(clientWith(mocker));

    expect(result, isTrue);
    expect(await OnboardingStore.isComplete(), isTrue);
    mocker.close();
  });

  test('GET /me 200 + onboarding_complete false → onboarding', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    final mocker = DioAdapter(dio: dio);
    mocker.onGet(
      '/me',
      (server) => server.reply(200, {'onboarding_complete': false}),
    );

    final result = await resolveOnboardingComplete(clientWith(mocker));

    expect(result, isFalse);
    mocker.close();
  });

  test('GET /me erro de REDE (sem response) → fallback flag local', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    final mocker = DioAdapter(dio: dio);
    // simula falha de rede sem response HTTP
    mocker.onGet(
      '/me',
      (server) => server.throws(
        0,
        DioException(
          requestOptions: RequestOptions(path: '/me'),
          type: DioExceptionType.connectionError,
        ),
      ),
    );

    final result = await resolveOnboardingComplete(clientWith(mocker));

    // rede falhou (não 404): fallback honesto usa a flag local marcada
    expect(result, isTrue);
    mocker.close();
  });
}
