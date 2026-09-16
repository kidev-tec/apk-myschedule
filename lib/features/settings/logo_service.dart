import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';

/// Resultado do upload da logo do estabelecimento.
class LogoUploadResult {
  final String? logoUrl;
  final String? errorMessage;

  const LogoUploadResult._(this.logoUrl, this.errorMessage);

  const LogoUploadResult.success(String url) : this._(url, null);
  const LogoUploadResult.failure(String message) : this._(null, message);
}

/// Valida e envia a logo do negócio (POST /me/logo, multipart).
/// Validação local ANTES do upload: leigo não espera rede pra saber
/// que escolheu arquivo grande demais.
class LogoService {
  static const int maxBytes = 2 * 1024 * 1024; // 2MB
  static const List<String> allowedMimes = ['image/png', 'image/jpeg'];

  final Dio _dio;

  LogoService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  /// Valida tamanho e tipo. Retorna mensagem de erro humana ou null.
  String? validate(File file, String? mime) {
    final size = file.lengthSync();
    if (size > maxBytes) {
      return 'A imagem passou de 2MB. Escolhe uma menor.';
    }
    if (mime == null || !allowedMimes.contains(mime)) {
      return 'Formato não suportado. Usa PNG ou JPG.';
    }
    return null;
  }

  Future<LogoUploadResult> upload(File file, String mime) async {
    final invalid = validate(file, mime);
    if (invalid != null) {
      return LogoUploadResult.failure(invalid);
    }
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'logo': await MultipartFile.fromFile(file.path,
            filename: 'logo', contentType: DioMediaType.parse(mime)),
      });
      final resp = await _dio.post('/me/logo', data: form);
      final url = resp.data['logoUrl'] as String?;
      if (url == null || url.isEmpty) {
        return const LogoUploadResult.failure(
            'Servidor não devolveu o endereço da logo. Tenta de novo.');
      }
      return LogoUploadResult.success(url);
    } on DioException catch (e) {
      final msg = e.response?.data;
      final human = msg is Map && msg['error'] is String
          ? msg['error'] as String
          : 'Não consegui enviar a logo. Verifica a internet e tenta de novo.';
      return LogoUploadResult.failure(human);
    } catch (_) {
      return const LogoUploadResult.failure(
          'Não consegui enviar a logo. Verifica a internet e tenta de novo.');
    }
  }

  /// URL absoluta da logo a partir do path relativo devolvido pela API.
  static String absoluteUrl(String logoUrl) {
    if (logoUrl.startsWith('http')) return logoUrl;
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/v1/?$'), '');
    return '$base$logoUrl';
  }
}
