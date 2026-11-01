import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/features/agenda/block_logic.dart';
import 'package:minha_agenda/features/agenda/booking_wizard.dart'
    show WorkingHour;

void main() {
  // segunda 07/01/2030
  final seg = DateTime(2030, 1, 7);
  DateTime t(int h, [int m = 0]) => DateTime(2030, 1, 7, h, m);
  WorkingHour wh(int sh, int sm, int eh, int em) => WorkingHour(
      weekday: 1,
      startTime: TimeOfDay(hour: sh, minute: sm),
      endTime: TimeOfDay(hour: eh, minute: em));
  final cedo = DateTime(2030, 1, 6, 20); // véspera: nada passou

  SlotCell? cell(List<HourRow> g, int h, int m) =>
      g.firstWhere((r) => r.hour == h).cells[m ~/ blockCellMin];

  test('uma linha por hora do expediente, 12 quadradinhos de 5 min', () {
    final g = dayGrid(
        date: seg, workingHours: [wh(9, 0, 12, 0)], busy: [], now: cedo);
    expect(g.map((r) => r.hour), [9, 10, 11]);
    expect(g.every((r) => r.cells.length == 12), isTrue);
    expect(g.every((r) => r.cells.every((c) => c!.isFree)), isTrue);
  });

  test('fora do expediente vira null (janela 09:30–11:15)', () {
    final g = dayGrid(
        date: seg, workingHours: [wh(9, 30, 11, 15)], busy: [], now: cedo);
    expect(g.map((r) => r.hour), [9, 10, 11]);
    expect(cell(g, 9, 25), isNull);
    expect(cell(g, 9, 30)!.isFree, isTrue);
    expect(cell(g, 11, 10)!.isFree, isTrue);
    expect(cell(g, 11, 15), isNull);
  });

  test('ocupado (com folga) e passado', () {
    final g = dayGrid(
        date: seg,
        workingHours: [wh(9, 0, 18, 0)],
        busy: [BusyRange(t(11, 30), t(12, 40), 'Ezequias · Corte')],
        now: t(9, 12));
    expect(cell(g, 9, 5)!.state, CellState.past);
    expect(cell(g, 9, 10)!.state, CellState.past); // começa antes de 9:12
    expect(cell(g, 9, 15)!.state, CellState.free);
    expect(cell(g, 11, 25)!.state, CellState.free);
    expect(cell(g, 11, 30)!.state, CellState.busy);
    expect(cell(g, 11, 30)!.label, 'Ezequias · Corte');
    expect(cell(g, 12, 35)!.state, CellState.busy); // folga
    expect(cell(g, 12, 40)!.state, CellState.free);
  });

  test('ocupado que termina no meio de um quadradinho ocupa ele todo', () {
    final g = dayGrid(
        date: seg,
        workingHours: [wh(9, 0, 10, 0)],
        busy: [BusyRange(t(9, 0), t(9, 7), 'X')],
        now: cedo);
    expect(cell(g, 9, 5)!.state, CellState.busy);
    expect(cell(g, 9, 10)!.state, CellState.free);
  });

  test('dia sem expediente = grade vazia', () {
    expect(
        dayGrid(
            date: seg.add(const Duration(days: 1)),
            workingHours: [wh(9, 0, 18, 0)],
            busy: [],
            now: cedo),
        isEmpty);
  });

  test('mergeSelection junta contínuos em trechos', () {
    final r = mergeSelection([
      t(15, 30), t(12, 0), t(12, 5), t(12, 10), t(15, 35), t(12, 5), //
    ]);
    expect(r, [
      (t(12, 0), t(12, 15)),
      (t(15, 30), t(15, 40)),
    ]);
    expect(mergeSelection([]), isEmpty);
  });

  test('freeBetween pula ocupados (vira dois trechos) e aceita ordem inversa',
      () {
    final g = dayGrid(
        date: seg,
        workingHours: [wh(9, 0, 18, 0)],
        busy: [BusyRange(t(12, 0), t(12, 30), 'Ana · Corte')],
        now: cedo);
    final cells = freeBetween(g, t(12, 45), t(11, 45));
    expect(mergeSelection(cells), [
      (t(11, 45), t(12, 0)),
      (t(12, 30), t(12, 50)),
    ]);
  });
}
