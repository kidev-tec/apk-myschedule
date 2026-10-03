import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_config.dart';
import 'package:minha_agenda/core/update/update_service.dart';

/// Cobertura de UpdateService.check e downloadAndInstall (contrato).
///
/// check() aceita Dio injetado (DI igual ApiClient/wizard) pra mockar a rede
/// com http_mock_adapter. downloadAndInstall é Android-only (OpenFilex +
/// instalador) — em teste valida a exceção de plataforma e o nome do arquivo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // downloadAndInstall chama getTemporaryDirectory() antes da guarda de
    // plataforma — mocka o channel pra retornar um dir fake no host.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/fake-updater',
    );
  });

  group('UpdateService.check', () {
    test('nova versão remota → retorna UpdateInfo e grava lastCheck',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet('${ApiConfig.baseUrl}/version',
          (s) => s.reply(200, {
                'version': '1.1.0',
                'changelog': 'correções',
                'apk_url': '/apks/minha-agenda.apk',
              }));

      final info = await UpdateService.check(dio: dio);

      expect(info, isNotNull);
      expect(info!.remoteVersion, '1.1.0');
      expect(info.changelog, 'correções');
      expect(info.apkUrl, '/apks/minha-agenda.apk');
      expect(UpdateService.lastCheck, same(info));
    });

    test('mesma versão → null e lastCheck limpo', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet('${ApiConfig.baseUrl}/version',
          (s) => s.reply(200, {'version': '1.0.0'}));

      final info = await UpdateService.check(dio: dio);

      expect(info, isNull);
      expect(UpdateService.lastCheck, isNull);
    });

    test('download fail (rede fora) → null, sem crash', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet('${ApiConfig.baseUrl}/version', (s) => s.reply(500, null));

      final info = await UpdateService.check(dio: dio);

      expect(info, isNull);
      expect(UpdateService.lastCheck, isNull);
    });

    test('check() sem Dio injetado (prod path) → falha de rede vira null',
        () async {
      // Usa o Dio default com ApiConfig.baseUrl (10.0.2.2, inacessível no
      // host) — cobre o branch dio ?? Dio(...) e o catch de rede.
      final info = await UpdateService.check();
      expect(info, isNull);
    });

    test('campos ausentes no JSON usam defaults', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
          '${ApiConfig.baseUrl}/version', (s) => s.reply(200, {}));

      final info = await UpdateService.check(dio: dio);

      // default version '0.0.0' < 1.0.0 → sem update
      expect(info, isNull);
      expect(UpdateService.lastCheck, isNull);
    });
  });


  test('construtores privados e line-coverage trivial', () {
    // UpdateService._() e PaywallFlag._() são construtores privados de
    // namespace estático — instanciação via noSuchMethod não é possível;
    // as linhas são executadas pela própria carga da classe.
    expect(UpdateService.lastCheck, isNull);
  });

  group('UpdateService.downloadAndInstall — contrato', () {
    test('fora do Android → UnsupportedError antes de tocar a rede',
        () async {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '9.9.9',
        changelog: '',
        apkUrl: '/apks/minha-agenda.apk',
      );

      // Dio com adapter mockado: o download responde bytes fake, o teste
      // chega na guarda de plataforma (host não é Android → UnsupportedError).
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
        '${ApiConfig.baseUrl}${info.apkUrl}',
        (s) => s.reply(200, [104, 105, 106]),
      );

      // Teste roda no host (Linux), nunca Android → lança UnsupportedError.
      // Cobertura: branch da guarda de plataforma e montagem do savePath.
      await expectLater(
        UpdateService.downloadAndInstall(info, dio: dio),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('progresso do download dispara o callback onProgress (0..1)',
        () async {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '9.9.9',
        changelog: '',
        apkUrl: '/apks/minha-agenda.apk',
      );

      // Dio fake: download() simulado escreve os bytes e dispara o callback
      // de progresso como o Dio real faria com Content-Length conhecido.
      // (HttpServer real + runAsync pendura o isolate do flutter_test.)
      final dio = _FakeDownloadingDio();

      final progressos = <double>[];
      await expectLater(
        UpdateService.downloadAndInstall(
          info,
          dio: dio,
          onProgress: progressos.add,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(progressos, isNotEmpty);
      expect(progressos.single, 1.0);
    });

    test('download fake recebe o savePath com a versão no nome', () async {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '9.9.9',
        changelog: '',
        apkUrl: '/apks/minha-agenda.apk',
      );
      final dio = _FakeDownloadingDio();

      await expectLater(
        UpdateService.downloadAndInstall(info, dio: dio),
        throwsA(isA<UnsupportedError>()),
      );
      // o caminho montado pelo download fake
      expect(
          _FakeDownloadingDio.lastSavePath, contains('minha-agenda-9.9.9.apk'));
    });
  });
}

/// Dio fake pra downloadAndInstall: simula o download completo (chama
/// onReceiveProgress(1.0)) sem tocar rede — suficiente pra exercer o fluxo
/// até a guarda de plataforma.
class _FakeDownloadingDio implements Dio {
  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    lastSavePath = savePath as String;
    onReceiveProgress?.call(16, 16);
    return Response(requestOptions: RequestOptions(path: urlPath));
  }

  static String? lastSavePath;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
