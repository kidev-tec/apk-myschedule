// RF-A/RF-B/RF-C — testes do modelo Appointment e das ações da agenda.
// Foco: source='block' (isBlock), parse de canceled_reason e label do menu.
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/features/agenda/agenda_page.dart';

Appointment apptFromJson(Map<String, dynamic> j) => Appointment.fromJson(j);

void main() {
  group('RF-A — Appointment.isBlock (source do agendamento)', () {
    test('source=block → isBlock true e motivo preservado', () {
      final a = apptFromJson({
        'id': 'x1',
        'client_name': '— bloqueio —',
        'client_phone': '',
        'service_name': 'Bloqueio',
        'starts_at': '2026-09-17T12:00:00.000Z',
        'ends_at': '2026-09-17T13:00:00.000Z',
        'status': 'confirmed',
        'source': 'block',
        'canceled_reason': 'dentista',
      });
      expect(a.isBlock, isTrue);
      expect(a.canceledReason, 'dentista');
    });

    test('source ausente → app (não é bloqueio); source=public_link idem', () {
      final base = {
        'id': 'x2',
        'starts_at': '2026-09-17T12:00:00.000Z',
        'ends_at': '2026-09-17T13:00:00.000Z',
      };
      expect(apptFromJson({...base}).isBlock, isFalse);
      expect(
        apptFromJson({...base, 'source': 'public_link'}).isBlock,
        isFalse,
      );
    });
  });

  group('RF-B/RF-C — payload do modelo', () {
    test('parse com chaves alternativas (snake/camel)', () {
      final a = apptFromJson({
        'id': 'x3',
        'clientName': 'Ana',
        'clientPhone': '+5516999998888',
        'serviceName': 'Corte',
        'startsAt': '2026-09-17T12:00:00.000Z',
        'endsAt': '2026-09-17T12:30:00.000Z',
        'status': 'pending',
        'source': 'public_link',
      });
      expect(a.clientName, 'Ana');
      expect(a.clientPhone, '+5516999998888');
      expect(a.status, 'pending');
      expect(a.isBlock, isFalse);
    });
  });
}
