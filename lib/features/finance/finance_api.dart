import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'payment_models.dart';

final financeApiProvider =
    Provider<FinanceApi>((ref) => FinanceApi(ApiClient().dio));

/// Chamadas do módulo de finanças. Recebimentos são SOMENTE online
/// (não entram na fila offline): erro sobe para a tela mostrar.
class FinanceApi {
  FinanceApi(this._dio);
  final Dio _dio;

  Future<AppointmentFinance> appointment(String appointmentId) async {
    final r = await _dio.get('/finance/appointments/$appointmentId');
    return AppointmentFinance.fromJson(r.data as Map<String, dynamic>);
  }

  /// Recebimento de um agendamento ou avulso (sem [appointmentId]).
  Future<void> receive(NewPayment p,
      {String? appointmentId, String? clientId}) async {
    await _dio.post('/finance/payments',
        data: p.toJson(appointmentId: appointmentId, clientId: clientId));
  }

  Future<void> voidPayment(String paymentId) async {
    await _dio.post('/finance/transactions/$paymentId/void');
  }

  /// "A receber": [from]/[to] opcionais (padrão da API: até +60 dias).
  Future<Receivables> receivables(
      {DateTime? from, DateTime? to, String? clientId}) async {
    final r = await _dio.get('/finance/receivables', queryParameters: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (clientId != null) 'client_id': clientId,
    });
    return Receivables.fromJson(r.data as Map<String, dynamic>);
  }

  /// Clientes ativos, para filtro e recebimento avulso.
  Future<List<ClientOption>> clients() async {
    final r = await _dio.get('/clients');
    return [
      for (final c in (r.data as List))
        ClientOption((c as Map)['id'] as String, (c['name'] ?? '') as String),
    ];
  }

  /// Valor do atendimento (desconto/acréscimo).
  Future<void> updatePrice(String appointmentId, int priceCents) async {
    await _dio.patch('/appointments/$appointmentId',
        data: {'price_cents': priceCents});
  }
}
