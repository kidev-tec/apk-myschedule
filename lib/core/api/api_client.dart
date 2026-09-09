import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';

class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.timeout,
          receiveTimeout: ApiConfig.timeout,
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers[ApiConfig.authHeader] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // 401 → tentar refresh uma vez
        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.contains('/auth/refresh')) {
          await _tryRefreshToken();
          // Retry original request
          final newToken = await _storage.read(key: 'access_token');
          if (newToken != null) {
            error.requestOptions.headers[ApiConfig.authHeader] =
                'Bearer $newToken';
            final retry = await _dio.fetch(error.requestOptions);
            return handler.resolve(retry);
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  Future<void> _tryRefreshToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return;

    try {
      final resp = await Dio().post(
        '${ApiConfig.baseUrl}/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      if (resp.data['access_token'] != null) {
        await _storage.write(
            key: 'access_token', value: resp.data['access_token']);
        if (resp.data['refresh_token'] != null) {
          await _storage.write(
              key: 'refresh_token', value: resp.data['refresh_token']);
        }
      }
    } catch (_) {
      // Refresh falhou → logout será tratado pelo auth controller
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
