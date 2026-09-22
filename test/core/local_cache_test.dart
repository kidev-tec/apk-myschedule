import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/storage/local_cache.dart';

void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('agenva_cache_test');
    await LocalCache.init(path: tmp.path);
  });

  group('LocalCache (offline-first fase 1)', () {
    test('putList/getList roundtrip + lastSync', () async {
      await LocalCache.putList(LocalCache.clientsBox, [
        {'id': 'c1', 'name': 'Ana'},
        {'id': 'c2', 'name': 'Beto'},
      ]);
      expect(LocalCache.getList(LocalCache.clientsBox).length, 2);
      expect(LocalCache.hasData(LocalCache.clientsBox), isTrue);
      expect(LocalCache.lastSync(LocalCache.clientsBox), isNotNull);
    });

    test('box nunca cacheada → vazio e lastSync null', () {
      expect(LocalCache.getList(LocalCache.workingHoursBox), isEmpty);
      expect(LocalCache.hasData(LocalCache.workingHoursBox), isFalse);
      expect(LocalCache.lastSync(LocalCache.workingHoursBox), isNull);
    });

    test('putBoxByDay/getListByDay por janela de agenda', () async {
      const key = 'appointments_dia_2026-9-21';
      await LocalCache.putBoxByDay([
        {'id': 'a1', 'status': 'confirmed'},
      ], key);
      expect(LocalCache.getListByDay(key).length, 1);
      expect(LocalCache.lastSync(key), isNotNull);
      // outra janela → vazia
      expect(LocalCache.getListByDay('appointments_dia_2026-9-22'), isEmpty);
    });

    test('putBoxByDay sobrescreve a janela (última carga vence)', () async {
      const key = 'appointments_semana_2026-9-21';
      await LocalCache.putBoxByDay([
        {'id': 'a1'},
        {'id': 'a2'},
      ], key);
      await LocalCache.putBoxByDay([
        {'id': 'a3'},
      ], key);
      expect(LocalCache.getListByDay(key).length, 1);
      expect(LocalCache.getListByDay(key).first['id'], 'a3');
    });
  });
}
