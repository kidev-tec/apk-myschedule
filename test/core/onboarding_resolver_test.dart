import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/storage/onboarding_resolver.dart';
import 'package:minha_agenda/core/storage/onboarding_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(adapter: adapter);
  });

  group('resolveOnboardingComplete — servidor é a fonte da verdade', () {
    test('server true → completo (e sincroniza a flag local)', () async {
      adapter.onGet('/me', (s) => s.reply(200, {'onboarding_complete': true}));

      final done = await resolveOnboardingComplete(api);
      expect(done, isTrue);
      // flag local sincronizada: próxima sessão offline também pula
      expect(await OnboardingStore.isComplete(), isTrue);
    });

    test('server false → assistente (mesmo com flag local antiga true)',
        () async {
      await OnboardingStore.markComplete(); // flag suja de sessão anterior
      adapter.onGet('/me', (s) => s.reply(200, {'onboarding_complete': false}));

      final done = await resolveOnboardingComplete(api);
      expect(done, isFalse);
    });

    test('rede falha (sem response) → fallback na flag local', () async {
      // sem handler pra /me → DioException sem response
      await OnboardingStore.markComplete();
      final done = await resolveOnboardingComplete(api);
      expect(done, isTrue); // flag local diz completo
    });

    test('rede falha + flag local nunca marcada → assistente', () async {
      final done = await resolveOnboardingComplete(api);
      expect(done, isFalse);
    });

    test('server sem o campo (API velha) → cai na flag local', () async {
      await OnboardingStore.markComplete();
      adapter.onGet('/me', (s) => s.reply(200, {'name': 'X'}));
      final done = await resolveOnboardingComplete(api);
      expect(done, isTrue);
    });
  });
}
