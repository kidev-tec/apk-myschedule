import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'local_cache.dart';

/// Fase 2 do offline-first: fila persistente de escritas.
///
/// Regra de enfileiramento (a parte crítica):
/// - DioException SEM response (connect timeout, sem rede) → ENFILEIRA
/// - 4xx/5xx COM response → NÃO enfileira: é regra de negócio (409 conflito
///   de slot, 400 validação) — o usuário tá online, mostrar o erro na hora.
/// - Replay FIFO no retorno da rede. Sucesso → remove + atualiza cache.
///   Erro de negócio no replay → remove + notifica (não retenta forever).
class PendingOp {
  final String id;
  final String method; // POST / PATCH
  final String path; // ex: /appointments
  final Map<String, dynamic> body;
  final DateTime queuedAt;
  final String description; // pra UI: "Agendamento de Ana às 14:00"

  PendingOp({
    required this.id,
    required this.method,
    required this.path,
    required this.body,
    required this.queuedAt,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'body': body,
        'queuedAt': queuedAt.toIso8601String(),
        'description': description,
      };

  static PendingOp fromJson(Map<dynamic, dynamic> j) => PendingOp(
        id: j['id'] as String,
        method: j['method'] as String,
        path: j['path'] as String,
        body: Map<String, dynamic>.from(j['body'] as Map),
        queuedAt: DateTime.parse(j['queuedAt'] as String),
        description: j['description'] as String? ?? '',
      );
}

final syncQueueProvider =
    StateNotifierProvider<SyncQueueNotifier, List<PendingOp>>(
  (ref) => SyncQueueNotifier(),
);

class SyncQueueNotifier extends StateNotifier<List<PendingOp>> {
  SyncQueueNotifier() : super([]) {
    _loaded = _loadFromDisk();
  }

  late final Future<void> _loaded;
  static const _queueBox = '_queue';

  Future<void> _loadFromDisk() async {
    try {
      final box = Hive.box(_queueBox);
      final ops = box.values
          .map((j) => PendingOp.fromJson(Map<dynamic, dynamic>.from(j as Map)))
          .toList()
        ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
      // não sobrescrever enqueues que aconteceram durante a leitura
      if (state.isEmpty && ops.isNotEmpty && mounted) state = ops;
    } catch (_) {
      // storage falhou → fila vazia em memória (degradação honesta)
    }
  }

  /// Awaitable pra testes/garantia de consistência.
  Future<void> get ready => _loaded;

  /// Avalia um erro de mutação: retorna true se ENFILEIROU (offline),
  /// false se é erro de negócio pra mostrar direto.
  Future<bool> enqueueIfOffline(DioException e, PendingOp op) async {
    final isConnectivityError =
        e.response == null || e.type == DioExceptionType.connectionError;
    if (!isConnectivityError) return false;
    try {
      final box = Hive.box(_queueBox);
      await box.put(op.id, op.toJson());
      state = [...state, op]..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
      return true;
    } catch (_) {
      return false; // não consegui persistir → tratar como erro mesmo
    }
  }

  /// Replay FIFO de toda a fila. Retorna os erros de negócio encontrados
  /// (pra UI notificar); cada op removida da fila ao resolver (ok ou erro).
  Future<List<({PendingOp op, String error})>> replay(Dio dio) async {
    final failures = <({PendingOp op, String error})>[];
    for (final op in List<PendingOp>.from(state)) {
      try {
        final resp = op.method == 'POST'
            ? await dio.post(op.path, data: op.body)
            : await dio.patch(op.path, data: op.body);
        await _remove(op.id);
        await _invalidateRelatedCache(op, resp);
      } on DioException catch (e) {
        final msg = e.response?.data is Map<String, dynamic>
            ? (e.response!.data as Map<String, dynamic>)['error'] as String? ??
                'Falha ao sincronizar'
            : 'Falha ao sincronizar';
        // conectividade caiu de novo no meio do replay → para e deixa na fila
        if (e.response == null) break;
        await _remove(op.id);
        failures.add((op: op, error: msg));
      } catch (e) {
        debugPrint('[sync_queue] replay ${op.id} erro inesperado: $e');
        break; // erro inesperado → para, tenta de novo no próximo replay
      }
    }
    return failures;
  }

  Future<void> _remove(String id) async {
    try {
      await Hive.box(_queueBox).delete(id);
    } catch (_) {}
    state = state.where((o) => o.id != id).toList();
  }

  /// Sucesso no replay → invalida a janela da agenda no cache pra forçar
  /// re-fetch fresco (o cache antigo não contém a mutação).
  Future<void> _invalidateRelatedCache(PendingOp op, Response resp) async {
    try {
      final box = Hive.box(LocalCache.appointmentsBox);
      for (final key in box.keys) {
        if (key.toString().startsWith('appointments_')) {
          await box.delete(key);
          await Hive.box('_meta').delete(key);
        }
      }
    } catch (_) {}
  }

  int get count => state.length;
}
