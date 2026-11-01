import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';

/// Estado da checagem de atualização.
class UpdateInfo {
  final String currentVersion;
  final String remoteVersion;
  final String changelog;
  final String apkUrl;

  const UpdateInfo({
    required this.currentVersion,
    required this.remoteVersion,
    required this.changelog,
    required this.apkUrl,
  });

  bool get hasUpdate =>
      _versionToInt(remoteVersion) > _versionToInt(currentVersion);

  static int _versionToInt(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
  }
}

/// Falha da atualização com mensagem pronta pro usuário (PT-BR).
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checa nova versão na API e, se houver, baixa o APK e dispara a instalação.
///
/// Só no Android: no iOS a atualização vem pela App Store/TestFlight, então
/// o app nem consulta (e a faixa nunca aparece).
///
/// Fluxo de release:
/// 1. builda o APK release e sobe pra <api>/apks/minha-agenda.apk
/// 2. edita <api>/public/version.json com a versão nova
/// 3. apps abertos mostram banner "Atualizar" → baixa → pede instalação
class UpdateService {
  UpdateService._();

  static const _currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  static UpdateInfo? lastCheck;

  /// Atualização pelo próprio app (baixar APK) só existe no Android.
  /// Sobrescrito nos testes.
  static bool Function() supportsInAppUpdate =
      () => !kIsWeb && Platform.isAndroid;

  /// Faixa fechada no X: fica escondida até o app ser aberto de novo
  /// (estático = vale pelo processo inteiro).
  static bool dismissed = false;

  /// Consulta a API. Retorna info se houver update, null se igual/erro ou
  /// se a plataforma não atualiza pelo app.
  static Future<UpdateInfo?> check() async {
    if (!supportsInAppUpdate()) return null;
    try {
      final resp = await Dio(BaseOptions(
              connectTimeout: ApiConfig.timeout,
              receiveTimeout: ApiConfig.timeout))
          .get('${ApiConfig.baseUrl}/version');
      final info = UpdateInfo(
        currentVersion: _currentVersion,
        remoteVersion: resp.data['version'] as String? ?? '0.0.0',
        changelog: resp.data['changelog'] as String? ?? '',
        apkUrl: resp.data['apk_url'] as String? ?? '/apks/minha-agenda.apk',
      );
      lastCheck = info.hasUpdate ? info : null;
      return lastCheck;
    } catch (e) {
      debugPrint('[update] checagem falhou (ok em offline): $e');
      return null;
    }
  }

  /// Baixa o APK (com progresso 0..1) e abre o instalador do Android.
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (!supportsInAppUpdate()) {
      throw const UpdateException(
          'Neste aparelho a atualização é feita pela loja de aplicativos.');
    }
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/minha-agenda-${info.remoteVersion}.apk';

    try {
      await Dio().download(
        '${ApiConfig.baseUrl}${info.apkUrl}',
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      debugPrint('[update] download falhou: $e');
      throw const UpdateException('Não foi possível baixar a atualização. '
          'Verifique a internet e tente de novo.');
    }

    final result = await OpenFilex.open(savePath);
    if (result.type != ResultType.done) {
      debugPrint('[update] instalador não abriu: ${result.message}');
      throw const UpdateException('Não foi possível abrir o instalador. '
          'Tente de novo em instantes.');
    }
  }
}
