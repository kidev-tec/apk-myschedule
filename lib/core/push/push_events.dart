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

  /// Notificação tocada, à espera da agenda (que pode ainda nem estar aberta
  /// se o toque abriu o app). Quem trata consome com [takeOpened].
  final opened = ValueNotifier<Map<String, dynamic>?>(null);

  /// Tocou na notificação do sistema.
  void handleOpened(Map<String, dynamic> data) {
    handle(data);
    opened.value = data;
  }

  /// Devolve a notificação tocada e limpa (trata uma vez só).
  Map<String, dynamic>? takeOpened() {
    final data = opened.value;
    opened.value = null;
    return data;
  }

  /// Trata os dados (`data`) do push.
  void handle(Map<String, dynamic> data) {
    if (data['type'] == 'new_booking') agendaChanged.value++;
    // todo push da central (notify) traz o id da notificação
    if (data['notification_id'] != null) notificationsChanged.value++;
  }
}

/// Avisos de vínculo estabelecimento ↔ profissional (módulo agregador).
const linkNotificationTypes = {
  'link_request',
  'link_accepted',
  'link_rejected',
  'link_ended',
};

/// Para onde vai o toque numa notificação: lista de espera ([waitlistDate],
/// `YYYY-MM-DD`), tela de vínculos ([openLinks]) ou o agendamento ([day], e
/// [appointmentId] para abrir os detalhes dele). Nulo = só abre o app.
class PushTarget {
  const PushTarget(
      {this.waitlistDate,
      this.day,
      this.appointmentId,
      this.openLinks = false});
  final String? waitlistDate;
  final DateTime? day;
  final String? appointmentId;
  final bool openLinks;

  static PushTarget? from(Map<String, dynamic> data) {
    if (linkNotificationTypes.contains(data['type'])) {
      return const PushTarget(openLinks: true);
    }
    // agendamento pelo link do estabelecimento: fica na agenda do
    // profissional, não na de quem recebe este aviso — só abre o app
    if (data['type'] == 'aggregator_booking') return null;
    final date = data['date'];
    if (data['type'] == 'waitlist' && date is String) {
      return PushTarget(waitlistDate: date);
    }
    final starts = data['starts_at'];
    final day = starts is String ? DateTime.tryParse(starts)?.toLocal() : null;
    if (day == null) return null;
    final id = data['appointment_id'];
    return PushTarget(day: day, appointmentId: id is String ? id : null);
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
