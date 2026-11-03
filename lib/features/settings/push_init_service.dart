import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'device_token_service.dart';

/// Inicializa o Firebase Messaging e registra o token do dispositivo na API.
/// Tudo best-effort: push é melhoria — falha (permissão negada, sem rede,
/// Firebase não configurado em teste) nunca pode travar o boot do app.
class PushInitService {
  final DeviceTokenService _tokens;
  final Future<String?> Function() _readToken;

  /// [readToken]: token do aparelho (injetável nos testes).
  PushInitService(
      {DeviceTokenService? tokens, Future<String?> Function()? readToken})
      : _tokens = tokens ?? DeviceTokenService(),
        _readToken = readToken ?? _deviceToken;

  /// Token do FCM. No iOS ele depende do token da Apple (APNs), que pode
  /// demorar alguns segundos depois da permissão: sem ele, getToken() lança.
  static Future<String?> _deviceToken() async {
    final messaging = FirebaseMessaging.instance;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      var apns = await messaging.getAPNSToken();
      for (var i = 0; apns == null && i < 5; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        apns = await messaging.getAPNSToken();
      }
      if (apns == null) return null;
    }
    return messaging.getToken();
  }

  /// Vincula este aparelho à conta logada. A API exige sessão, então isso
  /// precisa rodar depois do login, não só na abertura do app.
  Future<void> registerCurrentToken() async {
    try {
      final token = await _readToken();
      if (token == null) {
        debugPrint('[push] aparelho sem token');
        return;
      }
      final ok = await _tokens.register(token);
      debugPrint('[push] registro ${ok ? 'ok' : 'falhou (silencioso)'}');
    } catch (e) {
      debugPrint('[push] registro indisponível: $e');
    }
  }

  /// Sair da conta: desvincula o aparelho. Sem rede não trava a saída; o
  /// próximo login no aparelho refaz o vínculo com a conta certa.
  Future<void> unregisterCurrentToken() async {
    try {
      final token = await _readToken().timeout(const Duration(seconds: 5));
      if (token == null) return;
      await _tokens.unregister(token).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[push] não desvinculou o aparelho: $e');
    }
  }

  /// Handler de background precisa ser top-level (@pragma no main.dart).
  static Future<void> firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    debugPrint('[push:bg] ${message.notification?.title ?? '(sem título)'}');
  }

  /// [onForegroundMessage]: push com o app aberto (título, texto, dados).
  /// [onData]: dados de push recebido com o app aberto (agenda recarrega).
  /// [onOpened]: tocou na notificação do sistema (abre a tela dela).
  Future<void> init({
    required void Function(String title, String body) onForegroundMessage,
    void Function(Map<String, dynamic> data)? onData,
    void Function(Map<String, dynamic> data)? onOpened,
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
          .listen((message) => onOpened?.call(message.data));
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpened?.call(initial.data);

      await registerCurrentToken();

      // Renovação do token (reinstall, restore, expiração).
      messaging.onTokenRefresh.listen((newToken) {
        _tokens.register(newToken);
      });
    } catch (e) {
      debugPrint('[push] init indisponível: $e');
    }
  }
}
