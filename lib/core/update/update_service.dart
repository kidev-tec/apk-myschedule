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

  bool get hasUpdate => _versionToInt(remoteVersion) > _versionToInt(currentVersion);

  static int _versionToInt(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
  }
}

/// Checa nova versão na API e, se houver, baixa o APK e dispara a instalação.
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

  /// Consulta a API. Retorna info se houver update, null se igual/erro.
  static Future<UpdateInfo?> check() async {
    try {
      final resp = await Dio(BaseOptions(connectTimeout: ApiConfig.timeout, receiveTimeout: ApiConfig.timeout))
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
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/minha-agenda-${info.remoteVersion}.apk';

    await Dio().download(
      '${ApiConfig.baseUrl}${info.apkUrl}',
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
      options: Options(responseType: ResponseType.bytes),
    );

    if (!Platform.isAndroid) throw UnsupportedError('updater: só Android');
    final result = await OpenFilex.open(savePath);
    if (result.type != ResultType.done) {
      throw Exception('instalação não iniciada: ${result.message}');
    }
  }
}
