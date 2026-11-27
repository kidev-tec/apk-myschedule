import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'cash_models.dart';
import 'cashflow_models.dart';
import 'expense_models.dart';
import 'payment_models.dart';
import 'report_models.dart';

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

  // ---- Despesas (F2) ----

  Future<Expenses> expenses(
      {DateTime? from, DateTime? to, String? status}) async {
    final r = await _dio.get('/finance/expenses', queryParameters: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (status != null) 'status': status,
    });
    return Expenses.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> createExpense(NewExpense e) async {
    await _dio.post('/finance/expenses', data: e.toJson());
  }

  Future<void> payExpense(String id, PaymentMethod method) async {
    await _dio.post('/finance/expenses/$id/pay',
        data: {'payment_method': method.api});
  }

  // ---- Caixa diário (F2) ----

  /// Caixa aberto (null = fechado).
  Future<CashSession?> cashCurrent() async {
    final r = await _dio.get('/finance/cash/current');
    final s = (r.data as Map<String, dynamic>)['session'];
    return s == null ? null : CashSession.fromJson(s as Map<String, dynamic>);
  }

  Future<void> cashOpen(int openingCents) async {
    await _dio
        .post('/finance/cash/open', data: {'opening_cents': openingCents});
  }

  /// [cashIn] true = suprimento; false = sangria.
  Future<void> cashMove(
      {required bool cashIn, required int amountCents, String? notes}) async {
    await _dio.post('/finance/cash/movements', data: {
      'direction': cashIn ? 'in' : 'out',
      'amount_cents': amountCents,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  Future<CashSession> cashClose(int countedCents, {String? notes}) async {
    final r = await _dio.post('/finance/cash/close', data: {
      'counted_cents': countedCents,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return CashSession.fromJson(
        (r.data as Map<String, dynamic>)['session'] as Map<String, dynamic>);
  }

  /// Últimos caixas fechados.
  Future<List<CashSession>> cashHistory() async {
    final r = await _dio.get('/finance/cash');
    return [
      for (final s in ((r.data as Map<String, dynamic>)['sessions'] as List))
        CashSession.fromJson(s as Map<String, dynamic>),
    ];
  }

  // ---- Relatórios e metas (F3) ----

  Future<ReportSummary> reportSummary(DateTime from, DateTime to) async {
    final r = await _dio.get('/finance/reports/summary',
        queryParameters: {'from': dateKey(from), 'to': dateKey(to)});
    return ReportSummary.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<ServiceRevenue>> reportServices(
      DateTime from, DateTime to) async {
    final r = await _dio.get('/finance/reports/services',
        queryParameters: {'from': dateKey(from), 'to': dateKey(to)});
    return [
      for (final i in ((r.data as Map<String, dynamic>)['items'] as List))
        ServiceRevenue.fromJson(i as Map<String, dynamic>),
    ];
  }

  Future<Goal> goal(DateTime month) async {
    final r = await _dio.get('/finance/goals/${monthKey(month)}');
    return Goal.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Goal> setGoal(DateTime month, int targetCents) async {
    final r = await _dio.put('/finance/goals/${monthKey(month)}',
        data: {'target_cents': targetCents});
    return Goal.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Goal> deleteGoal(DateTime month) async {
    final r = await _dio.delete('/finance/goals/${monthKey(month)}');
    return Goal.fromJson(r.data as Map<String, dynamic>);
  }

  // ---- Fluxo projetado e comprovante (F4) ----

  Future<Cashflow> cashflow({int days = 30}) async {
    final r =
        await _dio.get('/finance/cashflow', queryParameters: {'days': days});
    return Cashflow.fromJson(r.data as Map<String, dynamic>);
  }

  /// Dados do comprovante (a API atribui o número na 1ª emissão).
  Future<Receipt> receipt(String paymentId) async {
    final r = await _dio.get('/finance/transactions/$paymentId/receipt');
    return Receipt.fromJson(r.data as Map<String, dynamic>);
  }

  /// Valor do atendimento (desconto/acréscimo).
  Future<void> updatePrice(String appointmentId, int priceCents) async {
    await _dio.patch('/appointments/$appointmentId',
        data: {'price_cents': priceCents});
  }
}
