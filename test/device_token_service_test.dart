import 'package:minha_agenda/features/settings/device_token_service.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/push/push_events.dart';
import 'package:minha_agenda/features/settings/push_init_service.dart';

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
  test('register faz POST /devices com payload correto e 201 = true', () async {
    RequestOptions? captured;
    final dio = Dio(BaseOptions())
      ..httpClientAdapter = FakeAdapter((o) {
        captured = o;
        return ResponseBody.fromString('{}', 201);
      });
    final svc = DeviceTokenService(dio: dio);
    final ok = await svc.register('TOKEN123');
    expect(ok, isTrue);
    expect(captured!.path, contains('/devices'));
    expect(captured!.data['fcmToken'], 'TOKEN123');
    expect(captured!.data['platform'], 'android');
  });

  test('plataforma: iPhone envia ios', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    RequestOptions? captured;
    final dio = Dio(BaseOptions())
      ..httpClientAdapter = FakeAdapter((o) {
        captured = o;
        return ResponseBody.fromString('{}', 201);
      });
    await DeviceTokenService(dio: dio).register('TOKEN123');
    expect(captured!.data['platform'], 'ios');
  });

  test('unregister faz DELETE /devices; erro devolve false', () async {
    RequestOptions? captured;
    final ok = await DeviceTokenService(
            dio: Dio(BaseOptions())
              ..httpClientAdapter = FakeAdapter((o) {
                captured = o;
                return ResponseBody.fromString('', 204);
              }))
        .unregister('TOKEN123');
    expect(ok, isTrue);
    expect(captured!.method, 'DELETE');
    expect(captured!.data['fcmToken'], 'TOKEN123');
    final bad = await DeviceTokenService(
            dio: Dio(BaseOptions())
              ..httpClientAdapter =
                  FakeAdapter((o) => ResponseBody.fromString('{}', 500)))
        .unregister('T');
    expect(bad, isFalse);
  });

  group('PushInitService: vínculo do aparelho', () {
    Dio dioFor(List<String> calls) => Dio(BaseOptions())
      ..httpClientAdapter = FakeAdapter((o) {
        calls.add('${o.method} ${o.data?['fcmToken']}');
        return ResponseBody.fromString('{}', o.method == 'POST' ? 201 : 204);
      });

    test('registra e desvincula o token atual', () async {
      final calls = <String>[];
      final push = PushInitService(
          tokens: DeviceTokenService(dio: dioFor(calls)),
          readToken: () async => 'TOK');
      await push.registerCurrentToken();
      await push.unregisterCurrentToken();
      expect(calls, ['POST TOK', 'DELETE TOK']);
    });

    test('sem token ou erro ao ler: não chama a API nem lança', () async {
      final calls = <String>[];
      final tokens = DeviceTokenService(dio: dioFor(calls));
      final none = PushInitService(tokens: tokens, readToken: () async => null);
      await none.registerCurrentToken();
      await none.unregisterCurrentToken();
      final fail = PushInitService(
          tokens: tokens, readToken: () async => throw Exception('apns'));
      await fail.registerCurrentToken();
      await fail.unregisterCurrentToken();
      expect(calls, isEmpty);
    });
  });

  group('PushTarget: toque na notificação', () {
    test('vaga abriu vai para a lista de espera do dia', () {
      final t = PushTarget.from({'type': 'waitlist', 'date': '2030-11-03'});
      expect(t?.waitlistDate, '2030-11-03');
      expect(t?.day, isNull);
    });
    test('agendamento vai para o dia, no horário local', () {
      final at = DateTime(2030, 11, 3, 9);
      final t = PushTarget.from({
        'type': 'new_booking',
        'starts_at': at.toUtc().toIso8601String(),
        'appointment_id': 'a1',
      });
      expect(t?.day, at);
      expect(t?.appointmentId, 'a1');
    });
    test('sem destino ou dados inválidos: só abre o app', () {
      expect(PushTarget.from({'type': 'x'}), isNull);
      expect(PushTarget.from({'starts_at': 'quebrado'}), isNull);
      expect(PushTarget.from({'type': 'waitlist'}), isNull);
    });
  });

  test('takeOpened entrega a notificação tocada uma vez só', () {
    final events = PushEvents();
    events.handleOpened({'type': 'new_booking', 'notification_id': 'n1'});
    expect(events.agendaChanged.value, 1);
    expect(events.notificationsChanged.value, 1);
    expect(events.takeOpened()?['notification_id'], 'n1');
    expect(events.takeOpened(), isNull);
  });

  test('register com 500 devolve false sem crashar', () async {
    final dio = Dio(BaseOptions())
      ..httpClientAdapter =
          FakeAdapter((o) => ResponseBody.fromString('{"e":"x"}', 500));
    final svc = DeviceTokenService(dio: dio);
    expect(await svc.register('T'), isFalse);
  });

  test('register com exceção de rede devolve false sem crashar', () async {
    final dio = Dio(BaseOptions())
      ..httpClientAdapter = FakeAdapter((o) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError);
      });
    final svc = DeviceTokenService(dio: dio);
    expect(await svc.register('T'), isFalse);
  });
}
