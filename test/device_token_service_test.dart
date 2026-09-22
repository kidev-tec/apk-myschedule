import 'package:minha_agenda/features/settings/device_token_service.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
