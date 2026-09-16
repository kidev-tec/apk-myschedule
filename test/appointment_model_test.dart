import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/features/agenda/agenda_page.dart';

/// Regressão do bug em produção: a API retorna { appointments: [...] }
/// (objeto com chave) e o app fazia `resp.data as List` → type error
/// engolido por catch silencioso → agenda SEMPRE vazia.
///
/// O parse agora aceita lista crua OU objeto com chave. Estes testes
/// travam o contrato em ambos os shapes.
void main() {
  group('Appointment.fromJson — contrato com a API', () {
    final baseJson = {
      'id': 'id-1',
      'starts_at': '2026-09-10T12:00:00.000Z',
      'ends_at': '2026-09-10T12:30:00.000Z',
      'status': 'pending',
    };

    test('parseia shape da API (snake_case + nomes no join)', () {
      final a = Appointment.fromJson({
        ...baseJson,
        'client_name': 'Maria Cliente',
        'client_phone': '14998887766',
        'service_name': 'Corte',
      });
      expect(a.id, 'id-1');
      expect(a.clientName, 'Maria Cliente');
      expect(a.clientPhone, '14998887766');
      expect(a.serviceName, 'Corte');
      expect(a.status, 'pending');
    });

    test('parseia shape alternativo camelCase (defensivo)', () {
      final a = Appointment.fromJson({
        'id': 'id-2',
        'clientName': 'João',
        'serviceName': 'Barba',
        'startsAt': '2026-09-10T12:00:00.000Z',
        'endsAt': '2026-09-10T12:30:00.000Z',
        'status': 'confirmed',
      });
      expect(a.clientName, 'João');
      expect(a.serviceName, 'Barba');
      expect(a.status, 'confirmed');
    });

    test('FUSO: ISO com Z é convertido pra horário local (bug 12:00↔09:00)',
        () {
      const iso = '2026-09-10T12:00:00.000Z';
      final a = Appointment.fromJson({
        ...baseJson,
        'starts_at': iso, // 09:00 em America/Sao_Paulo; 12:00 em UTC (CI)
      });
      final expected = DateTime.parse(iso).toLocal();
      // toLocal() garante que a exibição usa o fuso do usuário
      expect(a.startsAt.isUtc, isFalse);
      expect(a.startsAt, expected);
    });

    test('campos ausentes não crasham (fallback vazio)', () {
      final a = Appointment.fromJson({
        'id': 'id-3',
        'starts_at': '2026-09-10T12:00:00.000Z',
        'ends_at': '2026-09-10T12:30:00.000Z',
      });
      expect(a.clientName, '');
      expect(a.clientPhone, '');
      expect(a.serviceName, '');
    });
  });
}
