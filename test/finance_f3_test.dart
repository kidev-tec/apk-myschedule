import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/finance/cash_models.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/finance_home_page.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/report_models.dart';
import 'package:minha_agenda/features/finance/report_period.dart';
import 'package:minha_agenda/features/finance/reports_page.dart';

final _now = DateTime(2026, 11, 27, 12); // sexta-feira

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    final body = o.path.startsWith('/finance/reports/services')
        ? {
            'items': [
              {
                'service_name': 'Corte',
                'is_kit': false,
                'count': 2,
                'total_cents': 9000
              }
            ]
          }
        : o.path.startsWith('/finance/goals')
            ? {'month': '2026-11', 'target_cents': null}
            : {'revenue_cents': 100};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

const _summary = ReportSummary(
  revenueCents: 15000,
  expensesCents: 20000,
  resultCents: -5000,
  byMethod: {PaymentMethod.pix: 10000, PaymentMethod.cash: 5000},
  doneCount: 3,
  soldCents: 15000,
  avgTicketCents: 5000,
  avgPerClientCents: 7500,
  openCents: 6000,
);

/// API falsa de relatórios/metas.
class FakeReportsApi extends FinanceApi {
  FakeReportsApi() : super(Dio());
  final periods = <(DateTime, DateTime)>[];
  Goal goalValue = const Goal(month: '2026-11');
  final goalCalls = <String>[];
  List<ServiceRevenue> services = const [];

  @override
  Future<ReportSummary> reportSummary(DateTime from, DateTime to) async {
    periods.add((from, to));
    final days = to.difference(from).inDays + 1;
    return ReportSummary(
      revenueCents: _summary.revenueCents,
      expensesCents: _summary.expensesCents,
      resultCents: _summary.resultCents,
      byMethod: _summary.byMethod,
      doneCount: 3,
      soldCents: 15000,
      avgTicketCents: 5000,
      avgPerClientCents: 7500,
      openCents: 6000,
      series: [
        for (var i = 0; i < days; i++)
          DayValues(from.add(Duration(days: i)), i * 100, i.isEven ? 50 : 0),
      ],
    );
  }

  @override
  Future<List<ServiceRevenue>> reportServices(
          DateTime from, DateTime to) async =>
      services;

  @override
  Future<Goal> goal(DateTime month) async => goalValue;

  @override
  Future<Goal> setGoal(DateTime month, int targetCents) async {
    goalCalls.add('set ${monthKey(month)} $targetCents');
    goalValue = Goal(
      month: monthKey(month),
      targetCents: targetCents,
      achievedCents: 15000,
      percent: 15000 * 100 ~/ targetCents,
      remainingCents: targetCents - 15000,
      daysLeft: 4,
      neededPerDayCents: (targetCents - 15000) ~/ 4,
    );
    return goalValue;
  }

  @override
  Future<Goal> deleteGoal(DateTime month) async {
    goalCalls.add('delete ${monthKey(month)}');
    goalValue = Goal(month: monthKey(month));
    return goalValue;
  }

  @override
  Future<Receivables> receivables(
          {DateTime? from, DateTime? to, String? clientId}) async =>
      const Receivables(
          items: [], totalOpenCents: 0, overdueCents: 0, upcomingCents: 0);

  @override
  Future<CashSession?> cashCurrent() async => null;
}

Widget _app(FinanceApi api, Widget home) => ProviderScope(
      overrides: [financeApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('RF-F07 — ReportPeriod', () {
    test('dia, semana (seg–dom), mês e navegação', () {
      final d = ReportPeriod.of(ReportGranularity.day, _now);
      expect((d.from, d.to), (DateTime(2026, 11, 27), DateTime(2026, 11, 27)));
      expect(d.shift(1).from, DateTime(2026, 11, 28));
      expect(d.label, 'Sexta-feira, 27 de novembro');

      final w = ReportPeriod.of(ReportGranularity.week, _now);
      expect((w.from, w.to), (DateTime(2026, 11, 23), DateTime(2026, 11, 29)));
      expect(w.shift(-1).from, DateTime(2026, 11, 16));
      expect(w.label, '23/11 a 29/11');
      // domingo pertence à semana que começou na segunda anterior
      expect(
          ReportPeriod.of(ReportGranularity.week, DateTime(2026, 11, 29)).from,
          DateTime(2026, 11, 23));

      final m = ReportPeriod.of(ReportGranularity.month, _now);
      expect((m.from, m.to), (DateTime(2026, 11), DateTime(2026, 11, 30)));
      expect(m.shift(1).to, DateTime(2026, 12, 31));
      expect(m.shift(-11).from, DateTime(2025, 12));
      expect(m.label, 'Novembro 2026');

      final c =
          ReportPeriod.custom(DateTime(2026, 11, 3, 15), DateTime(2026, 11, 9));
      expect(c.from, DateTime(2026, 11, 3));
      expect(identical(c.shift(1), c), isTrue);
      expect(c.label, '03/11 a 09/11');
      expect(ReportPeriod.of(ReportGranularity.custom, _now).to,
          DateTime(2026, 11, 30));
    });

    test('dateKey / monthKey', () {
      expect(dateKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(monthKey(DateTime(2026, 3, 5)), '2026-03');
    });
  });

  group('modelos e API F3', () {
    test('fromJson e rotas', () async {
      final s = ReportSummary.fromJson({
        'revenue_cents': 100,
        'by_method': {'pix': 60, 'boleto': 40},
        'series': [
          {'date': '2026-11-01', 'revenue_cents': 100}
        ],
      });
      expect(s.byMethod, {PaymentMethod.pix: 60, PaymentMethod.other: 40});
      expect(s.series.single.expensesCents, 0);
      expect(ReportSummary.fromJson({}).openCents, 0);
      final g = Goal.fromJson({'month': '2026-11', 'target_cents': 500});
      expect(g.hasTarget, isTrue);
      expect(g.percent, isNull);

      final adapter = _Adapter();
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);
      await api.reportSummary(DateTime(2026, 11), DateTime(2026, 11, 30));
      final sv =
          await api.reportServices(DateTime(2026, 11), DateTime(2026, 11, 30));
      await api.goal(DateTime(2026, 11, 15));
      await api.setGoal(DateTime(2026, 11), 1000);
      await api.deleteGoal(DateTime(2026, 11));
      expect(sv.single.totalCents, 9000);
      expect(
          adapter.calls
              .map((c) => '${c.method} ${c.path} ${c.queryParameters}'),
          [
            'GET /finance/reports/summary {from: 2026-11-01, to: 2026-11-30}',
            'GET /finance/reports/services {from: 2026-11-01, to: 2026-11-30}',
            'GET /finance/goals/2026-11 {}',
            'PUT /finance/goals/2026-11 {}',
            'DELETE /finance/goals/2026-11 {}',
          ]);
      expect(adapter.calls[3].data, {'target_cents': 1000});
    });
  });

  group('RF-F07 a RF-F10 — ReportsPage', () {
    testWidgets('mostra os números do mês e anda pelos períodos', (t) async {
      final api = FakeReportsApi()
        ..services = const [ServiceRevenue('Combo', true, 1, 6000)];
      await t.pumpWidget(_app(api, ReportsPage(now: () => _now)));
      await t.pumpAndSettle();

      expect(find.text('Novembro 2026'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('report-result'))).data,
          '-R\$ 50,00');
      expect(find.byKey(const Key('report-chart')), findsOneWidget);
      expect(find.text('Pix'), findsOneWidget);
      expect(find.text('R\$ 75,00'), findsOneWidget); // ticket por cliente
      await t.scrollUntilVisible(find.text('Combo (kit) • 1x'), 200);
      expect(find.text('Combo (kit) • 1x'), findsOneWidget);
      expect(api.periods.last, (DateTime(2026, 11), DateTime(2026, 11, 30)));

      await t.scrollUntilVisible(find.byKey(const Key('report-next')), -200);
      await t.tap(find.byKey(const Key('report-next')));
      await t.pumpAndSettle();
      expect(api.periods.last, (DateTime(2026, 12), DateTime(2026, 12, 31)));

      await t.tap(find.text('Semana'));
      await t.pumpAndSettle();
      expect(api.periods.last, (DateTime(2026, 11, 30), DateTime(2026, 12, 6)));
      expect(
          find.byKey(const Key('goal-define')), findsNothing); // meta só no mês
      await t.tap(find.byKey(const Key('report-prev')));
      await t.pumpAndSettle();
      expect(api.periods.last.$1, DateTime(2026, 11, 23));

      await t.tap(find.text('Dia'));
      await t.pumpAndSettle();
      expect(
          api.periods.last, (DateTime(2026, 11, 23), DateTime(2026, 11, 23)));
      expect(find.byKey(const Key('report-chart')), findsNothing);
      expect(
          find.text('Nenhum atendimento concluído no período.'), findsNothing);
    });

    testWidgets('período livre abre o seletor de datas', (t) async {
      final api = FakeReportsApi();
      await t.pumpWidget(_app(api, ReportsPage(now: () => _now)));
      await t.pumpAndSettle();
      await t.tap(find.text('Período'));
      await t.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('report-range')), findsOneWidget);
      expect(find.byKey(const Key('report-prev')), findsNothing);
      expect(find.text('Nenhum atendimento concluído no período.'),
          findsOneWidget);
    });

    testWidgets('definir, mostrar e remover a meta', (t) async {
      final api = FakeReportsApi();
      await t.pumpWidget(_app(api, ReportsPage(now: () => _now)));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('goal-define')));
      await t.pumpAndSettle();
      final save = find.byKey(const Key('goal-save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      await t.enterText(find.byKey(const Key('goal-field')), '100000');
      await t.pump();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.goalCalls, ['set 2026-11 100000']);
      expect(t.widget<Text>(find.byKey(const Key('goal-percent'))).data, '15%');
      expect(find.textContaining('Faltam R\$ 850,00'), findsOneWidget);
      expect(find.textContaining('por dia (4 dias)'), findsOneWidget);

      await t.tap(find.byKey(const Key('goal-card')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('goal-remove')));
      await t.pumpAndSettle();
      expect(api.goalCalls.last, 'delete 2026-11');
      expect(find.byKey(const Key('goal-define')), findsOneWidget);
    });

    testWidgets('meta batida e último dia', (t) async {
      final api = FakeReportsApi()
        ..goalValue = const Goal(
            month: '2026-11',
            targetCents: 10000,
            achievedCents: 15000,
            percent: 150);
      await t.pumpWidget(_app(api, ReportsPage(now: () => _now)));
      await t.pumpAndSettle();
      expect(find.text('Meta batida! 🎉'), findsOneWidget);

      api.goalValue = const Goal(
          month: '2026-11',
          targetCents: 20000,
          achievedCents: 15000,
          percent: 75,
          remainingCents: 5000,
          daysLeft: 1,
          neededPerDayCents: 5000);
      await t.pumpWidget(
          _app(api, ReportsPage(key: const Key('b'), now: () => _now)));
      await t.pumpAndSettle();
      expect(find.textContaining('(1 dia)'), findsOneWidget);
    });
  });

  group('FinanceHomePage — resumo do mês', () {
    testWidgets('recebido, despesas, resultado e meta', (t) async {
      final api = FakeReportsApi();
      await t.pumpWidget(_app(api, FinanceHomePage(now: () => _now)));
      await t.pumpAndSettle();
      expect(find.text('Novembro'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('month-revenue'))).data,
          'R\$ 150,00');
      expect(find.byKey(const Key('goal-define')), findsOneWidget);
      expect(api.periods.single, (DateTime(2026, 11), DateTime(2026, 11, 30)));
      await t.scrollUntilVisible(find.byKey(const Key('finance-reports')), 200);
      expect(find.byKey(const Key('finance-reports')), findsOneWidget);
    });
  });
}
