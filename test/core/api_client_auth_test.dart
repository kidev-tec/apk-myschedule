import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/api/api_client.dart';

/// Adapter falso: registra cada requisição (path + Authorization) e
/// responde 200 só quando o token bate com [validToken].
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.validToken);
  String validToken;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final auth = options.headers['Authorization'] as String?;
    calls.add('${options.path} $auth');
    final ok = auth == 'Bearer $validToken';
    return ResponseBody.fromString(
      jsonEncode(ok ? {'ok': true} : {'error': 'token inválido ou expirado'}),
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('usa o token atual do Firebase em cada requisição', () async {
    final adapter = _FakeAdapter('t1');
    final api = ApiClient(
        adapter: adapter, idToken: ({bool forceRefresh = false}) async => 't1');
    final r = await api.dio.get('/me');
    expect(r.statusCode, 200);
    expect(adapter.calls, ['/me Bearer t1']);
  });

  test('401: força renovação do token UMA vez e repete a requisição', () async {
    final adapter = _FakeAdapter('novo');
    var forced = 0;
    final api = ApiClient(
      adapter: adapter,
      idToken: ({bool forceRefresh = false}) async {
        if (forceRefresh) forced++;
        return forceRefresh ? 'novo' : 'vencido';
      },
    );
    final r = await api.dio.get('/me');
    expect(r.statusCode, 200);
    expect(forced, 1);
    expect(adapter.calls, ['/me Bearer vencido', '/me Bearer novo']);
  });

  test('401 persistente: devolve o erro sem loop e sem /auth/refresh',
      () async {
    final adapter = _FakeAdapter('nunca');
    final api = ApiClient(
        adapter: adapter, idToken: ({bool forceRefresh = false}) async => 'x');
    await expectLater(
      api.dio.get('/me'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(adapter.calls, hasLength(2), reason: 'original + 1 retry, só');
    expect(adapter.calls.any((c) => c.contains('/auth/refresh')), isFalse);
  });

  test('sem usuário no Firebase: cai no token salvo (compat)', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'salvo'});
    final adapter = _FakeAdapter('salvo');
    final api = ApiClient(
        adapter: adapter, idToken: ({bool forceRefresh = false}) async => null);
    final r = await api.dio.get('/me');
    expect(r.statusCode, 200);
    expect(adapter.calls, ['/me Bearer salvo']);
  });
}
