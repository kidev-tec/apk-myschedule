/// Estado global do paywall (RF-14).
///
/// O interceptor do Dio grava a última mensagem 402 aqui (sem contexto de
/// widget disponível); a Home observa e exibe o banner de bloqueio.
/// Solução simples de propósito — ValueNotifier evita overhead de Riverpod
/// pra um único booleano + string.
library;

import 'package:flutter/foundation.dart';

class PaywallFlag {
  PaywallFlag._();

  static final ValueNotifier<String?> lastMessage = ValueNotifier(null);

  static void hit(String message) => lastMessage.value = message;

  static void clear() => lastMessage.value = null;
}
