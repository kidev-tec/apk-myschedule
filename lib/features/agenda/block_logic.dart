import 'booking_wizard.dart' show WorkingHour;

/// Lógica pura do "Bloquear horário": grade do dia em quadradinhos de
/// [blockCellMin] minutos (uma linha por hora), marcando o que está livre,
/// ocupado ou já passou — o prestador monta os trechos que quiser só com
/// o que está livre, então o bloqueio nunca dá conflito.

/// Resolução da grade: 5 min (permite 12:00–12:45 e 15:30–16:20).
const blockCellMin = 5;

/// Intervalo ocupado: agendamento (fim + folga), bloqueio ou bloqueio de agenda.
class BusyRange {
  final DateTime start;
  final DateTime end;
  final String label;
  const BusyRange(this.start, this.end, this.label);
}

enum CellState { free, busy, past }

class SlotCell {
  final DateTime start;
  final CellState state;

  /// Quem ocupa (só nos ocupados): "Ana · Corte", "Bloqueado · almoço"…
  final String? label;
  const SlotCell(this.start, this.state, [this.label]);

  bool get isFree => state == CellState.free;
}

/// Uma hora da grade: 60/[blockCellMin] posições; null = fora do expediente.
class HourRow {
  final int hour;
  final List<SlotCell?> cells;
  const HourRow(this.hour, this.cells);
}

/// Grade do [date]: só as horas que tocam alguma janela de expediente.
/// Quadradinho dentro do expediente é ocupado se cruza algum [busy],
/// "passado" se começa antes de [now], senão livre.
List<HourRow> dayGrid({
  required DateTime date,
  required List<WorkingHour> workingHours,
  required List<BusyRange> busy,
  required DateTime now,
}) {
  final weekday = date.weekday % 7; // 0=dom..6=sáb
  DateTime at(int min) =>
      DateTime(date.year, date.month, date.day).add(Duration(minutes: min));
  final windows = [
    for (final w in workingHours.where((w) => w.weekday == weekday))
      (
        w.startTime.hour * 60 + w.startTime.minute,
        w.endTime.hour * 60 + w.endTime.minute
      ),
  ];
  if (windows.isEmpty) return [];
  final firstHour =
      windows.map((w) => w.$1).reduce((a, b) => a < b ? a : b) ~/ 60;
  final lastMin = windows.map((w) => w.$2).reduce((a, b) => a > b ? a : b);
  final lastHour = (lastMin - 1) ~/ 60;

  final rows = <HourRow>[];
  for (var h = firstHour; h <= lastHour; h++) {
    final cells = <SlotCell?>[];
    for (var m = 0; m < 60; m += blockCellMin) {
      final s = h * 60 + m;
      final e = s + blockCellMin;
      final inWindow = windows.any((w) => w.$1 <= s && e <= w.$2);
      if (!inWindow) {
        cells.add(null);
        continue;
      }
      final start = at(s);
      final end = at(e);
      final hit = busy
          .where((b) => b.start.isBefore(end) && b.end.isAfter(start))
          .firstOrNull;
      if (hit != null) {
        cells.add(SlotCell(start, CellState.busy, hit.label));
      } else if (start.isBefore(now)) {
        cells.add(SlotCell(start, CellState.past));
      } else {
        cells.add(SlotCell(start, CellState.free));
      }
    }
    if (cells.any((c) => c != null)) rows.add(HourRow(h, cells));
  }
  return rows;
}

/// Junta os quadradinhos marcados (inícios) em trechos contínuos [início, fim).
List<(DateTime, DateTime)> mergeSelection(Iterable<DateTime> starts) {
  const step = Duration(minutes: blockCellMin);
  final sorted = starts.toSet().toList()..sort();
  final out = <(DateTime, DateTime)>[];
  for (final s in sorted) {
    if (out.isNotEmpty && out.last.$2 == s) {
      out[out.length - 1] = (out.last.$1, s.add(step));
    } else {
      out.add((s, s.add(step)));
    }
  }
  return out;
}

/// Quadradinhos livres entre [a] e [b] (inclusive, em qualquer ordem) —
/// pula ocupados/passados no meio (vira mais de um trecho).
List<DateTime> freeBetween(List<HourRow> grid, DateTime a, DateTime b) {
  final lo = a.isBefore(b) ? a : b;
  final hi = a.isBefore(b) ? b : a;
  return [
    for (final r in grid)
      for (final c in r.cells)
        if (c != null &&
            c.isFree &&
            !c.start.isBefore(lo) &&
            !c.start.isAfter(hi))
          c.start,
  ];
}
