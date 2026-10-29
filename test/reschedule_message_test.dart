import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/features/agenda/booking_logic.dart' as logic;
import 'package:minha_agenda/features/agenda/booking_wizard.dart'
    show Appointment;

/// B-remarque (t_b018bc6b):
/// CA1 — buildRescheduleMessage usa o startsAt NOVO (do PATCH response),
///       nunca texto genérico "o novo horário".
/// CA2 — sem appointment novo, fallback explícito mantém texto genérico
///       (não quebra o fluxo offline).
void main() {
  setUpAll(() async => await initializeDateFormatting('pt_BR', null));
  test('CA1 mensagem contém data/hora real do novo agendamento', () {
    final novo = Appointment(
      id: 'novo-1',
      startsAt: DateTime(2026, 10, 30, 14, 30),
      endsAt: DateTime(2026, 10, 30, 15, 30),
      status: 'confirmed',
      clientId: 'c1',
      serviceId: 's1',
    );
    final msg = logic.buildRescheduleMessage('Kim', novo);
    expect(msg, contains('30/10 às 14:30'));
    expect(msg, isNot(contains('o novo horário. Confirma')));
  });

  test('CA1b mensagem começa com nome do cliente e mantém tom da SPEC', () {
    final novo = Appointment(
      id: 'novo-2',
      startsAt: DateTime(2026, 11, 2, 9),
      endsAt: DateTime(2026, 11, 2, 10),
      status: 'confirmed',
      clientId: 'c1',
      serviceId: 's1',
    );
    final msg = logic.buildRescheduleMessage('Kim', novo);
    expect(msg, startsWith('Oi Kim!'));
    expect(msg, contains('02/11 às 09:00'));
    expect(msg, contains('funciona pra você?'));
  });

  test('CA2 fallback sem dados novos mantém texto genérico', () {
    final msg = logic.buildRescheduleMessage('Kim', null);
    expect(msg, contains('o novo horário'));
    expect(msg, startsWith('Oi Kim!'));
  });

  test('formatWhen: "dd/MM às HH:mm" (sem virar "à0")', () {
    expect(logic.formatWhen(DateTime(2026, 10, 27, 9, 0)), '27/10 às 09:00');
    expect(logic.formatWhen(DateTime(2026, 1, 5, 14, 30)), '05/01 às 14:30');
  });

  test('greetingName: usa como o cliente prefere ser chamado', () {
    expect(logic.greetingName('Eduardo Mello', 'Dudu'), 'Dudu');
    expect(logic.greetingName('Eduardo Mello', null), 'Eduardo Mello');
    expect(logic.greetingName('Eduardo Mello', '  '), 'Eduardo Mello');
  });
}
