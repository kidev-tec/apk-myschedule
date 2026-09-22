import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado de conectividade pra UI (banner offline).
/// Stream de connectivity_plus; começa assumindo online (não bloquear
/// 1º paint com query de rede) — o primeiro evento corrige.
final connectivityProvider = StateNotifierProvider<ConnectivityNotifier, bool>(
  (ref) => ConnectivityNotifier(),
);

class ConnectivityNotifier extends StateNotifier<bool> {
  ConnectivityNotifier() : super(true) {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      // connectivity_plus 7 devolve lista de resultados
      final offline =
          results.isEmpty || results.every((c) => c == ConnectivityResult.none);
      state = !offline;
    });
    // Sonda imediata (o stream só dispara em mudança).
    Connectivity().checkConnectivity().then((results) {
      final offline =
          results.isEmpty || results.every((c) => c == ConnectivityResult.none);
      state = !offline;
    });
  }

  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
