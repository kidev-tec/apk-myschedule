import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';

/// Registra o token FCM do dispositivo na API (POST /devices).
/// Falha de rede nunca crasha: push é melhoria, não fluxo crítico.
class DeviceTokenService {
  final Dio _dio;

  /// [dio] permite injetar mock nos testes (padrão do ApiClient).
  DeviceTokenService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  /// `ios` no iPhone/iPad; `android` nos demais.
  static String get currentPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<bool> register(String fcmToken, {String? platform}) async {
    try {
      final resp = await _dio.post('/devices', data: <String, dynamic>{
        'fcmToken': fcmToken,
        'platform': platform ?? currentPlatform,
      });
      return resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Desvincula o aparelho da conta (sair): para de receber os avisos dela.
  Future<bool> unregister(String fcmToken) async {
    try {
      final resp = await _dio
          .delete('/devices', data: <String, dynamic>{'fcmToken': fcmToken});
      return resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
