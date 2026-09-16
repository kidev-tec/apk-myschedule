import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/features/agenda/booking_logic.dart';
import 'package:minha_agenda/features/agenda/booking_wizard.dart'
    show Appointment, Client, WorkingHour;

/// Testes da lógica pura de slots extraída do BookingWizardPage.
/// A regra de negócio é: slot válido só se cabe na janela de trabalho,
/// não sobrepõe agendamento pending/confirmed, step de 15 min.
void main() {
  // Segunda-feira 15/09/2026 (weekday 1 → %7 = 1)
  final segunda = DateTime(2026, 9, 14, 0, 0);

  WorkingHour wh(int weekday, String start, String end) {
    TimeOfDay t(String s) {
      final p = s.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }

    return WorkingHour(weekday: weekday, startTime: t(start), endTime: t(end));
  }

  Appointment appt(String startIso, String endIso,
      [String status = 'confirmed']) {
    return Appointment(
      id: 'a-${startIso.hashCode}',
      startsAt: DateTime.parse(startIso).toLocal(),
      endsAt: DateTime.parse(endIso).toLocal(),
      status: status,
    );
  }

  group('generateSlots', () {
    test('dia sem working hour → lista vazia', () {
      // segunda tem wh weekday 1; passei wh só de terça (2)
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(2, '09:00', '12:00')],
        appointments: [],
        durationMin: 60,
      );
      expect(slots, isEmpty);
    });

    test('janela 09:00-12:00, serviço 60min → slots a cada 15min', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [],
        durationMin: 60,
      );
      // último slot que cabe: 11:00 + 60 = 12:00 (isAtSameMomentAs end) ✓
      // slots: 09:00, 09:15, ..., 11:00 → 9 slots
      expect(slots.length, 9);
      expect(slots.first.hour, 9);
      expect(slots.first.minute, 0);
      expect(slots.last.hour, 11);
      expect(slots.last.minute, 0);
      // step de 15 min
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].difference(slots[i - 1]),
          const Duration(minutes: 15),
        );
      }
    });

    test('serviço de 30min gera mais slots que 60min', () {
      final slots30 = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [],
        durationMin: 30,
      );
      // último: 11:30 + 30 = 12:00 → 09:00..11:30 = 11 slots
      expect(slots30.length, 11);
    });

    test('appointment confirmado bloqueia slots sobrepostos', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [
          appt('2026-09-14T09:00:00.000', '2026-09-14T10:00:00.000'),
        ],
        durationMin: 60,
      );
      // 09:00 sobrepõe (bloqueado), 09:15 sobrepõe (10:15 > 09:00 e < 10:00 fim do appt? sim)
      // slot livre só quando cursor + 60 <= 10:00 → 10:00 é o primeiro
      final horasLivres = slots.map((s) => s.hour).toSet();
      expect(horasLivres.contains(9), isFalse);
      expect(horasLivres.contains(10), isTrue);
    });

    test('appointment pending TAMBÉM bloqueia', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [
          appt('2026-09-14T09:00:00.000', '2026-09-14T10:00:00.000', 'pending'),
        ],
        durationMin: 60,
      );
      final horasLivres = slots.map((s) => s.hour).toSet();
      expect(horasLivres.contains(9), isFalse);
    });

    test('appointment cancelado NÃO bloqueia', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [
          appt('2026-09-14T09:00:00.000', '2026-09-14T10:00:00.000',
              'cancelled'),
        ],
        durationMin: 60,
      );
      expect(slots.length, 9); // dia inteiro livre
    });

    test('appointment de OUTRO dia não interfere', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [
          appt('2026-09-15T09:00:00.000', '2026-09-15T10:00:00.000'),
        ],
        durationMin: 60,
      );
      expect(slots.length, 9);
    });

    test('contorno: appt que só toca na borda (fim == início do slot) libera',
        () {
      // appt 09:00-10:00. Slot das 10:00: appt.endsAt (10:00).isAfter(10:00) = false → sem overlap
      final slots = generateSlots(
        date: segunda,
        workingHours: [wh(1, '09:00', '12:00')],
        appointments: [
          appt('2026-09-14T09:00:00.000', '2026-09-14T10:00:00.000'),
        ],
        durationMin: 60,
      );
      expect(slots.any((s) => s.hour == 10 && s.minute == 0), isTrue);
    });

    test('múltiplas janelas no mesmo dia (manhã e tarde)', () {
      final slots = generateSlots(
        date: segunda,
        workingHours: [
          wh(1, '09:00', '10:00'),
          wh(1, '14:00', '15:00'),
        ],
        appointments: [],
        durationMin: 60,
      );
      // manhã: 09:00 (só 1 slot cabe: 09:00+60=10:00)
      // tarde: 14:00 (só 1)
      expect(slots.length, 2);
      expect(slots[0].hour, 9);
      expect(slots[1].hour, 14);
    });
  });

  group('filterClients', () {
    final clientes = [
      Client(id: '1', name: 'Maria Silva', phoneE164: '+5514998887766'),
      Client(id: '2', name: 'João Souza', phoneE164: '+5514991112233'),
      Client(id: '3', name: 'maria aparício', phoneE164: '+5514933334444'),
    ];

    test('query vazia → lista completa', () {
      expect(filterClients(clientes, '').length, 3);
      expect(filterClients(clientes, '   ').length, 3);
    });

    test('busca por nome case-insensitive', () {
      final r = filterClients(clientes, 'MARIA');
      expect(r.length, 2);
    });

    test('busca por telefone', () {
      final r = filterClients(clientes, '98887766');
      expect(r.length, 1);
      expect(r.first.id, '1');
    });

    test('sem match → vazio', () {
      expect(filterClients(clientes, 'zzz'), isEmpty);
    });
  });
}
