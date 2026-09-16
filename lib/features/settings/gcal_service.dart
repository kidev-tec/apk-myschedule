import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// RF-08 — Google Calendar do prestador (espelho de agendamentos).
///
/// Fluxo: abrir auth-url no browser → consentimento Google → callback da API
/// salva o refresh_token no business → usuário volta ao app e reconfere status.
class GCalService {
  final ApiClient _api = ApiClient();

  /// Busca o status de conexão do business. Erro → desconectado (o card
  /// oferece conectar; nada quebra se a API oscilar).
  Future<bool> isConnected() async {
    try {
      final resp = await _api.dio.get('/gcal/status');
      final data = resp.data;
      final connected = data is Map ? data['connected'] == true : false;
      return connected;
    } catch (e) {
      debugPrint('[gcal] status erro: $e');
      return false;
    }
  }

  /// Abre o consentimento Google no browser externo.
  /// Retorna false se não conseguiu abrir (raro: sem browser no device).
  Future<bool> startConnect() async {
    try {
      final resp = await _api.dio.get('/gcal/auth-url');
      final url = (resp.data as Map)['url'] as String?;
      if (url == null) return false;
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[gcal] startConnect erro: $e');
      return false;
    }
  }

  /// Desconecta: apaga o refresh token do business (o Calendar continua
  /// com os eventos já criados — remoção retroativa é fora do MVP).
  Future<void> disconnect() async {
    try {
      await _api.dio.delete('/gcal');
    } catch (e) {
      debugPrint('[gcal] disconnect erro: $e');
      rethrow;
    }
  }
}
