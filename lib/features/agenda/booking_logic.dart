import 'booking_wizard.dart' show Client, WorkingHour, Appointment;

/// Lógica pura de geração de slots de agenda — extraída do BookingWizardPage
/// pra ser testável sem widget. Mesma regra que o wizard usa na tela.
///
/// Regras:
/// - só gera slots em dias que têm WorkingHour pro weekday (0=dom..6=sáb)
/// - slot cabe dentro da janela (start + duration <= end)
/// - step de 15 min entre slots candidatos
/// - slot é descartado se sobrepõe appointment pending/confirmed do dia
List<DateTime> generateSlots({
  required DateTime date,
  required List<WorkingHour> workingHours,
  required List<Appointment> appointments,
  required int durationMin,
}) {
  final weekday = date.weekday % 7; // 0=dom..6=sáb
  final dayHours = workingHours.where((h) => h.weekday == weekday).toList();
  if (dayHours.isEmpty) return [];

  final slots = <DateTime>[];
  final dayAppointments = appointments
      .where((a) =>
          a.startsAt.year == date.year &&
          a.startsAt.month == date.month &&
          a.startsAt.day == date.day)
      .where((a) => a.status == 'pending' || a.status == 'confirmed')
      .toList();

  for (final wh in dayHours) {
    var cursor = DateTime(
        date.year, date.month, date.day, wh.startTime.hour, wh.startTime.minute);
    final end = DateTime(
        date.year, date.month, date.day, wh.endTime.hour, wh.endTime.minute);

    while (cursor.add(Duration(minutes: durationMin)).isBefore(end) ||
        cursor.add(Duration(minutes: durationMin)).isAtSameMomentAs(end)) {
      final slotEnd = cursor.add(Duration(minutes: durationMin));
      final overlaps = dayAppointments
          .any((a) => a.startsAt.isBefore(slotEnd) && a.endsAt.isAfter(cursor));
      if (!overlaps) slots.add(cursor);
      cursor = cursor.add(const Duration(minutes: 15)); // step 15 min
    }
  }
  return slots;
}

/// Busca local de clientes por nome ou telefone (case-insensitive).
List<Client> filterClients(List<Client> clients, String query) {
  if (query.trim().isEmpty) return clients;
  final q = query.trim().toLowerCase();
  return clients
      .where((c) =>
          c.name.toLowerCase().contains(q) ||
          c.phoneE164.toLowerCase().contains(q))
      .toList();
}

class BookingWizardLogic {
  BookingWizardLogic._();
}
