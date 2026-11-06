import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/push/push_events.dart';

void main() {
  test('novo agendamento avisa quem escuta (agenda recarrega)', () {
    final events = PushEvents();
    var count = 0;
    events.agendaChanged.addListener(() => count++);
    events.handle({'type': 'new_booking', 'appointment_id': 'a1'});
    expect(count, 1);
  });

  test('push sem relação com a agenda não recarrega', () {
    final events = PushEvents();
    var count = 0;
    events.agendaChanged.addListener(() => count++);
    events.handle({'type': 'trial_reminder'});
    events.handle(const {});
    expect(count, 0);
  });

  testWidgets('app aberto: mostra o aviso na tela (título + texto)',
      (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: key, home: const Scaffold(body: SizedBox())));
    showForegroundPush(key, 'Novo agendamento', 'Ana — Corte em 30/10, 09:00');
    await tester.pump();
    expect(find.text('Novo agendamento'), findsOneWidget);
    expect(find.text('Ana — Corte em 30/10, 09:00'), findsOneWidget);
  });

  test('avisos de vínculo abrem a tela de vínculos', () {
    for (final type in linkNotificationTypes) {
      final t = PushTarget.from({'type': type, 'link_id': 'x'});
      expect(t?.openLinks, isTrue, reason: type);
      expect(t?.day, isNull);
    }
  });

  test('agendamento pelo link do estabelecimento não abre a agenda do dono',
      () {
    expect(
        PushTarget.from({
          'type': 'aggregator_booking',
          'starts_at': '2026-11-10T13:00:00.000Z',
        }),
        isNull);
    // os demais com starts_at continuam abrindo o dia
    expect(
        PushTarget.from({
          'type': 'new_booking',
          'starts_at': '2026-11-10T13:00:00.000Z',
        })?.openLinks,
        isFalse);
  });
}
