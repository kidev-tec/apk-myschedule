import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'device_token_service.dart';

/// Inicializa o Firebase Messaging e registra o token do dispositivo na API.
/// Tudo best-effort: push é melhoria — falha (permissão negada, sem rede,
/// Firebase não configurado em teste) nunca pode travar o boot do app.
class PushInitService {
  final DeviceTokenService _tokens;

  PushInitService({DeviceTokenService? tokens})
      : _tokens = tokens ?? DeviceTokenService();

  /// Handler de background precisa ser top-level (@pragma no main.dart).
  static Future<void> firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    debugPrint('[push:bg] ${message.notification?.title ?? '(sem título)'}');
  }

  Future<void> init({
    required void Function(String title, String body) onForegroundMessage,
  }) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('[push] permissão negada — sem notificações');
        return;
      }

      // Handlers ANTES do getToken (nenhum token/notificação no meio).
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n != null) onForegroundMessage(n.title ?? '', n.body ?? '');
      });

      final token = await messaging.getToken();
      if (token != null) {
        final ok = await _tokens.register(token);
        debugPrint('[push] registro ${ok ? 'ok' : 'falhou (silencioso)'}');
      }

      // Renovação do token (reinstall, restore, expiração).
      messaging.onTokenRefresh.listen((newToken) {
        _tokens.register(newToken);
      });
    } catch (e) {
      debugPrint('[push] init indisponível: $e');
    }
  }
}
