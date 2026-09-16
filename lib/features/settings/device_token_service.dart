import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';

/// Registra o token FCM do dispositivo na API (POST /devices).
/// Falha de rede nunca crasha: push é melhoria, não fluxo crítico.
class DeviceTokenService {
  final Dio _dio;

  /// [dio] permite injetar mock nos testes (padrão do ApiClient).
  DeviceTokenService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  Future<bool> register(String fcmToken, {String platform = 'android'}) async {
    try {
      final resp = await _dio.post('/devices',
          data: <String, dynamic>{'fcmToken': fcmToken, 'platform': platform});
      return resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
