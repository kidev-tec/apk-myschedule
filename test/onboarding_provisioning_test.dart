import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:minha_agenda/features/onboarding/onboarding_provisioning.dart';

void main() {
  // Payload de erro 404 que a API devolve quando user+business não existem.
  const notFoundBody = {'message': 'User or business not found'};

  group('ensureProvisioned', () {
    test('não faz sync quando /me responde 200 (já provisionado)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      final mocker = DioAdapter(dio: dio);

      mocker.onPatch(
        '/me',
        data: Matchers.any,
        (server) => server.reply(200, {'ok': true}),
      );

      await ensureProvisioned(dio, segmentId: 'beauty');

      // Apenas o PATCH inicial aconteceu — sem /auth/sync, sem re-PATCH.
      expect(mocker.history.length, 1);
      mocker.close();
    });

    test('fluxo de recuperação: /me 404 → /auth/sync → re-PATCH /me', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      final mocker = DioAdapter(dio: dio);

      var meCallCount = 0;
      mocker
        ..onPatch(
          '/me',
          data: Matchers.any,
          // handler com status 200, mas a 1ª chamada lança DioException 404
          // (simula API que não tem o user ainda; na 2ª, pós-sync, responde OK).
          (server) => server.replyCallbackAsync(200, (request) async {
            meCallCount++;
            if (meCallCount == 1) {
              throw DioException(
                requestOptions: request,
                response: Response(
                  requestOptions: request,
                  statusCode: 404,
                  data: notFoundBody,
                ),
              );
            }
            return {'ok': true};
          }),
        )
        ..onPost(
          '/auth/sync',
          data: Matchers.any,
          (server) => server.reply(200, {'ok': true}),
        );

      await ensureProvisioned(dio, segmentId: 'beauty');

      // O re-PATCH aconteceu (meCallCount == 2) e o fluxo completou sem
      // exceção — PATCH falhou com 404, /auth/sync resolveu, re-PATCH OK.
      expect(meCallCount, 2);
      mocker.close();
    });

    test('propaga erro não-404 de /me (ex: 500) sem tentar sync', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      final mocker = DioAdapter(dio: dio);

      mocker.onPatch(
        '/me',
        data: Matchers.any,
        (server) => server.reply(500, {'message': 'boom'}),
      );

      await expectLater(
        ensureProvisioned(dio, segmentId: 'beauty'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)),
      );

      // Só o PATCH — sync NÃO foi chamado.
      expect(mocker.history.length, 1);
      mocker.close();
    });

    test('propaga falha do /auth/sync quando ele não resolve o 404', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      final mocker = DioAdapter(dio: dio);

      mocker
        ..onPatch(
          '/me',
          data: Matchers.any,
          (server) => server.reply(404, notFoundBody),
        )
        ..onPost(
          '/auth/sync',
          data: Matchers.any,
          (server) => server.reply(500, {'message': 'sync boom'}),
        );

      await expectLater(
        ensureProvisioned(dio, segmentId: 'beauty'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)
            .having(
                (e) => e.requestOptions.path, 'rota que falhou', '/auth/sync')),
      );
      mocker.close();
    });

    test('payload do /auth/sync leva o segmento correto', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      final mocker = DioAdapter(dio: dio);

      Object? syncPayload;
      var meCallCount = 0;
      mocker
        ..onPatch(
          '/me',
          data: Matchers.any,
          (server) => server.replyCallbackAsync(200, (request) async {
            meCallCount++;
            if (meCallCount == 1) {
              throw DioException(
                requestOptions: request,
                response: Response(
                  requestOptions: request,
                  statusCode: 404,
                  data: notFoundBody,
                ),
              );
            }
            return {'ok': true};
          }),
        )
        ..onPost(
          '/auth/sync',
          data: Matchers.any,
          (server) => server.replyCallbackAsync(200, (request) async {
            syncPayload = request.data;
            return {'ok': true};
          }),
        );

      await ensureProvisioned(dio, segmentId: 'barber');

      expect(
        syncPayload,
        isA<Map>().having((m) => m['segment'], 'segment', 'barber'),
      );
      mocker.close();
    });
  });
}
