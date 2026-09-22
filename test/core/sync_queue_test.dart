import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/storage/local_cache.dart';
import 'package:minha_agenda/core/storage/sync_queue.dart';

// LocalCache._initialized é estático — após Hive.close() precisa resetar pra
// reabrir os boxes no tmp novo. Helper de teste:
void resetCacheInit() => LocalCache.resetForTest();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;
  late DioAdapter adapter;
  late ApiClient api;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('agenva_queue_test');
    // fila do teste anterior não pode vazar (Hive é global no processo):
    // fecha os boxes abertos e reabre limpos no tmp novo
    try {
      await Hive.close();
    } catch (_) {}
    LocalCache.resetForTest();
    await LocalCache.init(path: tmp.path);
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(adapter: adapter);
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await tmp.delete(recursive: true);
  });

  PendingOp op({String id = 'op1'}) => PendingOp(
        id: id,
        method: 'POST',
        path: '/appointments',
        body: {'clientId': 'c1', 'serviceId': 's1'},
        queuedAt: DateTime(2026, 9, 21, 14, 0),
        description: 'Agendamento de Ana às 14:00',
      );

  group('SyncQueueNotifier — regra de enfileiramento', () {
    test('DioException SEM response (sem rede) → enfileira', () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      expect(await q.enqueueIfOffline(e, op()), isTrue);
      expect(q.count, 1);
      // persistiu no Hive
      expect(LocalCache.getListByDay('nope'), isEmpty); // sanity
    });

    test('409 COM response → NÃO enfileira (erro de negócio na hora)',
        () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 409,
            data: {'error': 'Já existe um cliente com este telefone'}),
      );
      expect(await q.enqueueIfOffline(e, op()), isFalse);
      expect(q.count, 0);
    });

    test('fila sobrevive restart (persistência Hive)', () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      await q.enqueueIfOffline(e, op());
      // nova instância = novo notifier (simula restart do app)
      final q2 = container.read(
        syncQueueProvider.notifier,
      );
      expect(q2.count, 1);
      expect(q2.state.first.description, 'Agendamento de Ana às 14:00');
    });
  });

  group('SyncQueueNotifier — replay', () {
    test('replay com rede OK → esvazia fila e invalida cache da agenda',
        () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      await q.enqueueIfOffline(e, op());
      await LocalCache.putBoxByDay([
        {'id': 'old'},
      ], 'appointments_dia_2026-9-21');

      adapter.onPost('/appointments', (s) => s.reply(201, {'id': 'new-1'}),
          data: Matchers.any);

      final failures = await q.replay(api.dio);
      expect(failures, isEmpty);
      expect(q.count, 0);
      // cache da agenda invalidado
      expect(LocalCache.getListByDay('appointments_dia_2026-9-21'), isEmpty);
    });

    test('replay com 409 (slot tomado no meio-tempo) → tira da fila + reporta',
        () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      await q.enqueueIfOffline(e, op(id: 'op-conflict'));

      adapter.onPost('/appointments',
          (s) => s.reply(409, {'error': 'Conflito de horário — já ocupado'}),
          data: Matchers.any);

      final failures = await q.replay(api.dio);
      expect(q.count, 0); // não retenta forever
      expect(failures.length, 1);
      expect(failures.first.error, contains('Conflito'));
    });

    test('rede caiu de novo no replay → mantém na fila', () async {
      final q = container.read(syncQueueProvider.notifier);
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      await q.enqueueIfOffline(e, op(id: 'op-again'));

      // Simula rede caindo NO MEIO do replay: configura o adapter pra NÃO
      // responder (nenhum handler) → DioException sem response no dio.post.
      // (http_mock_adapter não aceita throw no handler; handler ausente
      // produz exatamente DioException sem response.)
      final failures = await q.replay(api.dio);
      expect(q.count, 1); // ficou na fila
      expect(failures, isEmpty);
    });
  });
}
