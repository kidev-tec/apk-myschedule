import 'package:hive_flutter/hive_flutter.dart';

/// Cache local offline-first (Fase 1 do plano Offline-First 2026-09-21).
///
/// Estratégia: toda carga bem-sucedida da API grava aqui ANTES de setState;
/// sem rede, as pages servem do cache e mostram banner "dados de HH:mm".
/// Cache é stale-by-design — nunca mentir que é fresco.
///
/// Boxes por entidade + um box `_meta` com o timestamp `last_sync` de cada.
/// Injeção de diretório pra testes (Hive.init(tempDir)).
class LocalCache {
  static bool _initialized = false;

  static const clientsBox = 'clients';
  static const servicesBox = 'services';
  static const appointmentsBox = 'appointments';
  static const workingHoursBox = 'working_hours';
  static const _metaBox = '_meta';

  /// Inicializa o Hive. Idempotente; [path] permite teste com tmp dir.
  static Future<void> init({String? path}) async {
    if (_initialized) return;
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    await Hive.openBox(clientsBox);
    await Hive.openBox(servicesBox);
    await Hive.openBox(appointmentsBox);
    await Hive.openBox(workingHoursBox);
    await Hive.openBox(_metaBox);
    _initialized = true;
  }

  /// Grava uma lista de dados brutos (JSON maps) numa box + marca o sync.
  static Future<void> putList(String boxName, List<dynamic> items) async {
    final box = Hive.box(boxName);
    await box.clear();
    for (var i = 0; i < items.length; i++) {
      await box.put(i, items[i]);
    }
    await _markSync(boxName);
  }

  /// Lê a lista crua de uma box; lista vazia se nunca cacheada.
  static List<dynamic> getList(String boxName) {
    final box = Hive.box(boxName);
    return box.values.toList();
  }

  static Future<void> _markSync(String boxName) async {
    await Hive.box(_metaBox).put(boxName, DateTime.now().toIso8601String());
  }

  /// Grava uma lista de dados brutos numa box, sob uma chave (ex: janela
  /// dia/semana da agenda), + marca o sync.
  static Future<void> putBoxByDay(List<dynamic> items, String key) async {
    await Hive.box(appointmentsBox).put(key, items);
    await Hive.box(_metaBox).put(key, DateTime.now().toIso8601String());
  }

  /// Lê a lista crua sob uma chave; vazia se nunca cacheada.
  static List<dynamic> getListByDay(String key) {
    final v = Hive.box(appointmentsBox).get(key);
    return v is List ? v : [];
  }

  /// Quando a box foi sincronizada com sucesso (null = nunca).
  static DateTime? lastSync(String boxName) {
    final raw = Hive.box(_metaBox).get(boxName) as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Indica se a box tem algum conteúdo cacheado.
  static bool hasData(String boxName) => Hive.box(boxName).isNotEmpty;
}
