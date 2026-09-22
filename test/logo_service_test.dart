import 'dart:io';

import 'package:minha_agenda/features/settings/logo_service.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adapter fake: responde programaticamente sem rede.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('logo_test');
  });
  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  File makeFile(int bytes) {
    final f = File('${tmp.path}/logo.png')
      ..writeAsBytesSync(List.filled(bytes, 1));
    return f;
  }

  group('LogoService.validate', () {
    test('rejeita >2MB antes de chamar a API', () {
      final svc = LogoService(dio: Dio());
      final err = svc.validate(makeFile(3 * 1024 * 1024), 'image/png');
      expect(err, contains('2MB'));
    });

    test('rejeita tipo inválido', () {
      final svc = LogoService(dio: Dio());
      final err = svc.validate(makeFile(100), 'image/gif');
      expect(err, contains('PNG ou JPG'));
    });

    test('rejeita mime null', () {
      final svc = LogoService(dio: Dio());
      final err = svc.validate(makeFile(100), null);
      expect(err, contains('PNG ou JPG'));
    });

    test('aceita PNG pequeno', () {
      final svc = LogoService(dio: Dio());
      expect(svc.validate(makeFile(100), 'image/png'), isNull);
    });
  });

  group('LogoService.upload', () {
    test('sucesso devolve logoUrl', () async {
      final dio = Dio(BaseOptions())
        ..httpClientAdapter = FakeAdapter((o) => ResponseBody.fromString(
                '{"logoUrl":"/v1/businesses/x/logo"}', 200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                }));
      final svc = LogoService(dio: dio);
      final r = await svc.upload(makeFile(100), 'image/png');
      expect(r.logoUrl, '/v1/businesses/x/logo');
      expect(r.errorMessage, isNull);
    });

    test('arquivo grande não chama a API', () async {
      var called = false;
      final dio = Dio(BaseOptions())
        ..httpClientAdapter = FakeAdapter((o) {
          called = true;
          return ResponseBody.fromString('{}', 200);
        });
      final svc = LogoService(dio: dio);
      final r = await svc.upload(makeFile(3 * 1024 * 1024), 'image/png');
      expect(called, isFalse);
      expect(r.errorMessage, contains('2MB'));
    });

    test('erro 4xx extrai mensagem humana do body', () async {
      final dio = Dio(BaseOptions())
        ..httpClientAdapter = FakeAdapter((o) => ResponseBody.fromString(
                '{"error":"Imagem inválida"}', 400,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                }));
      final svc = LogoService(dio: dio);
      final r = await svc.upload(makeFile(100), 'image/png');
      expect(r.errorMessage, 'Imagem inválida');
    });

    test('erro de rede cai em mensagem genérica', () async {
      final dio = Dio(BaseOptions())
        ..httpClientAdapter = FakeAdapter((o) => throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError));
      final svc = LogoService(dio: dio);
      final r = await svc.upload(makeFile(100), 'image/png');
      expect(r.errorMessage, contains('internet'));
    });

    test('200 sem logoUrl no body = falha', () async {
      final dio = Dio(BaseOptions())
        ..httpClientAdapter =
            FakeAdapter((o) => ResponseBody.fromString('{}', 200, headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                }));
      final svc = LogoService(dio: dio);
      final r = await svc.upload(makeFile(100), 'image/png');
      expect(r.errorMessage, isNotNull);
    });
  });

  group('LogoService.absoluteUrl', () {
    test('path relativo vira absoluto com base da API', () {
      final url = LogoService.absoluteUrl('/v1/businesses/x/logo');
      expect(url, startsWith('http'));
      expect(url, endsWith('/v1/businesses/x/logo'));
    });

    test('URL absoluta passa intocada', () {
      expect(LogoService.absoluteUrl('https://a.b/c.png'), 'https://a.b/c.png');
    });
  });
}
