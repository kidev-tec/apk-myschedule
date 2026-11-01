import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';
import 'paywall_flag.dart';

/// Fonte do ID token do Firebase. `forceRefresh` pede um token novo na rede.
typedef IdTokenProvider = Future<String?> Function({bool forceRefresh});

class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final IdTokenProvider _idToken;

  /// [adapter] permite injetar um mock (http_mock_adapter) nos testes.
  /// Em prod, não passar nada — usa o network real.
  /// [idToken]: injetável em teste; padrão = usuário atual do Firebase.
  ApiClient({HttpClientAdapter? adapter, IdTokenProvider? idToken})
      : _idToken = idToken ?? _firebaseIdToken,
        _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.timeout,
          receiveTimeout: ApiConfig.timeout,
          headers: {'Content-Type': 'application/json'},
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // retry do 401 já vem com o token renovado: não sobrescrever
        if (options.extra[_retried] == true) return handler.next(options);
        final token = await _currentToken();
        if (token != null) {
          options.headers[ApiConfig.authHeader] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // 401 → o ID token do Firebase venceu (dura 1h): força um token novo
        // e repete UMA vez. Marcado em `extra` pra nunca entrar em loop.
        final opts = error.requestOptions;
        if (error.response?.statusCode == 401 && opts.extra[_retried] != true) {
          final fresh = await _currentToken(forceRefresh: true);
          if (fresh != null) {
            opts.extra[_retried] = true;
            opts.headers[ApiConfig.authHeader] = 'Bearer $fresh';
            try {
              return handler.resolve(await _dio.fetch(opts));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
        }
        // 402 → paywall: trial vencido/assinatura cancelada (RF-14)
        if (error.response?.statusCode == 402) {
          PaywallFlag.hit('Período de teste encerrado. Renove a assinatura '
              'para continuar agendando.');
        }
        handler.next(error);
      },
    ));
  }

  static const _retried = 'auth_retried';

  Dio get dio => _dio;

  /// Token do Firebase (renovado automaticamente quando perto de vencer);
  /// sem usuário/Firebase, cai no último token salvo.
  Future<String?> _currentToken({bool forceRefresh = false}) async {
    final fresh = await _idToken(forceRefresh: forceRefresh);
    if (fresh != null && fresh.isNotEmpty) {
      await _storage.write(key: 'access_token', value: fresh);
      return fresh;
    }
    return _storage.read(key: 'access_token');
  }

  static Future<String?> _firebaseIdToken({bool forceRefresh = false}) async {
    try {
      return await FirebaseAuth.instance.currentUser
          ?.getIdToken(forceRefresh)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // sem Firebase (testes) ou rede oscilando: usa o token salvo
      return null;
    }
  }

  Future<void> storeTokens(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
