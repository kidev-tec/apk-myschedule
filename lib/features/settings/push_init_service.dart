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

  /// [onForegroundMessage]: push com o app aberto (título, texto, dados).
  /// [onData]: dados de qualquer push recebido/aberto (agenda recarrega).
  Future<void> init({
    required void Function(String title, String body) onForegroundMessage,
    void Function(Map<String, dynamic> data)? onData,
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
        onData?.call(message.data);
      });
      // Tocou na notificação com o app em 2º plano / fechado.
      FirebaseMessaging.onMessageOpenedApp
          .listen((message) => onData?.call(message.data));
      final initial = await messaging.getInitialMessage();
      if (initial != null) onData?.call(initial.data);

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
