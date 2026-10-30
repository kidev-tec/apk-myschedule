import 'package:flutter/material.dart';

/// Eventos de push que mexem na tela: hoje, "novo agendamento" (cliente
/// agendou pelo link) → a agenda aberta recarrega sozinha.
class PushEvents {
  PushEvents();

  /// Instância do app (a agenda escuta; o PushInitService dispara).
  static final instance = PushEvents();

  /// Incrementa quando a agenda precisa recarregar.
  final agendaChanged = ValueNotifier<int>(0);

  /// Incrementa quando chega notificação nova (o sino recarrega a contagem).
  final notificationsChanged = ValueNotifier<int>(0);

  /// Trata os dados (`data`) do push.
  void handle(Map<String, dynamic> data) {
    if (data['type'] == 'new_booking') agendaChanged.value++;
    // todo push da central (notify) traz o id da notificação
    if (data['notification_id'] != null) notificationsChanged.value++;
  }
}

/// Com o app aberto o Android não mostra a notificação do sistema: exibe o
/// aviso na própria tela.
void showForegroundPush(
    GlobalKey<ScaffoldMessengerState> key, String title, String body) {
  key.currentState?.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 6),
    content: Row(children: [
      const Icon(Icons.notifications_active, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
      ),
    ]),
  ));
}
