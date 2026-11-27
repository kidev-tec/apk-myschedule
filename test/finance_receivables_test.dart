import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/finance/cash_models.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/finance_home_page.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/report_models.dart';
import 'package:minha_agenda/features/finance/receivables_page.dart';

final _now = DateTime(2026, 11, 27, 12);

Receivable _item(String id, DateTime at, int balance,
        {PaymentStatus status = PaymentStatus.open}) =>
    Receivable(
      id: id,
      startsAt: at,
      status: 'confirmed',
      clientName: 'Cliente $id',
      serviceName: 'Corte',
      priceCents: 10000,
      paidCents: 10000 - balance,
      balanceCents: balance,
      paymentStatus: status,
    );

/// API falsa de "A receber": devolve [items] e grava filtros e recebimentos.
class FakeReceivablesApi extends FinanceApi {
  @override
  Future<ReportSummary> reportSummary(DateTime from, DateTime to) async =>
      const ReportSummary(revenueCents: 0, expensesCents: 0, resultCents: 0);

  @override
  Future<Goal> goal(DateTime month) async => const Goal(month: '2026-11');

  FakeReceivablesApi(this.items) : super(Dio());
  List<Receivable> items;
  final queries = <(DateTime?, DateTime?, String?)>[];
  final received = <(NewPayment, String?)>[];
  bool failClients = false;

  @override
  Future<Receivables> receivables(
      {DateTime? from, DateTime? to, String? clientId}) async {
    queries.add((from, to, clientId));
    final list = clientId == null ? items : <Receivable>[];
    final overdue = list
        .where((i) => i.isOverdue(_now))
        .fold<int>(0, (s, i) => s + i.balanceCents);
    final all = list.fold<int>(0, (s, i) => s + i.balanceCents);
    return Receivables(
        items: list,
        totalOpenCents: all,
        overdueCents: overdue,
        upcomingCents: all - overdue);
  }

  @override
  Future<CashSession?> cashCurrent() async => null;

  @override
  Future<List<ClientOption>> clients() async {
    if (failClients) throw Exception('offline');
    return const [ClientOption('c1', 'Ana'), ClientOption('c2', 'Bia')];
  }

  @override
  Future<void> receive(NewPayment p,
      {String? appointmentId, String? clientId}) async {
    received.add((p, appointmentId));
    items = [
      for (final i in items)
        if (i.id != appointmentId)
          i
        else if (i.balanceCents > p.amountCents)
          _item(i.id, i.startsAt, i.balanceCents - p.amountCents,
              status: PaymentStatus.partial),
    ];
  }
}

Widget _app(FinanceApi api, Widget home) => ProviderScope(
      overrides: [financeApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('RF-F04 — ReceivablesPage', () {
    testWidgets('agrupa Atrasados e Próximos e mostra os totais', (t) async {
      final api = FakeReceivablesApi([
        _item('a', _now.subtract(const Duration(days: 2)), 10000),
        _item('b', _now.add(const Duration(days: 3)), 6000,
            status: PaymentStatus.partial),
      ]);
      await t.pumpWidget(_app(api, ReceivablesPage(now: () => _now)));
      await t.pumpAndSettle();

      expect(find.text('Atrasados (1)'), findsOneWidget);
      expect(find.text('Próximos (1)'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('total-open'))).data,
          'R\$ 160,00');
      expect(t.widget<Text>(find.byKey(const Key('total-overdue'))).data,
          'R\$ 100,00');
      expect(t.widget<Text>(find.byKey(const Key('total-upcoming'))).data,
          'R\$ 60,00');
      expect(find.text('Parcial'), findsOneWidget);
      // padrão: sem limites (a API aplica até +60 dias)
      expect(api.queries.first, (null, null, null));
    });

    testWidgets('estado vazio', (t) async {
      await t.pumpWidget(
          _app(FakeReceivablesApi([]), ReceivablesPage(now: () => _now)));
      await t.pumpAndSettle();
      expect(find.text('Nada a receber no período.'), findsOneWidget);
    });

    testWidgets('filtros de período e cliente vão para a API', (t) async {
      final api = FakeReceivablesApi([_item('a', _now, 1000)]);
      await t.pumpWidget(_app(api, ReceivablesPage(now: () => _now)));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('period-next7')));
      await t.pumpAndSettle();
      expect(api.queries.last, (_now, _now.add(const Duration(days: 7)), null));

      await t.tap(find.byKey(const Key('period-overdue')));
      await t.pumpAndSettle();
      expect(api.queries.last, (null, _now, null));

      await t.tap(find.byKey(const Key('period-month')));
      await t.pumpAndSettle();
      expect(api.queries.last.$1, DateTime(2026, 11));

      await t.tap(find.byKey(const Key('receivables-client')));
      await t.pumpAndSettle();
      await t.tap(find.text('Bia').last);
      await t.pumpAndSettle();
      expect(api.queries.last.$3, 'c2');
      expect(find.text('Nada a receber no período.'), findsOneWidget);
    });

    testWidgets('sem lista de clientes, some o filtro de cliente', (t) async {
      final api = FakeReceivablesApi([])..failClients = true;
      await t.pumpWidget(_app(api, ReceivablesPage(now: () => _now)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('receivables-client')), findsNothing);
    });

    testWidgets('receber o saldo inteiro tira o item; parcial atualiza',
        (t) async {
      final api = FakeReceivablesApi([
        _item('a', _now.subtract(const Duration(hours: 1)), 5000),
        _item('b', _now.add(const Duration(days: 1)), 8000),
      ]);
      await t.pumpWidget(_app(api, ReceivablesPage(now: () => _now)));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('receivable-a')));
      await t.pumpAndSettle();
      expect(find.text('Receber de Cliente a'), findsOneWidget);
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();
      expect(api.received.single.$2, 'a');
      expect(find.byKey(const Key('receivable-a')), findsNothing);

      await t.tap(find.byKey(const Key('receivable-b')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('receive-amount')), '3000');
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();
      expect(find.text('R\$ 50,00'), findsWidgets);
      expect(find.text('Parcial'), findsOneWidget);
    });
  });

  group('FinanceHomePage', () {
    Widget routed(FinanceApi api) => ProviderScope(
          overrides: [financeApiProvider.overrideWithValue(api)],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/finance',
              routes: [
                GoRoute(
                    path: '/agenda', builder: (_, __) => const Text('agenda')),
                GoRoute(
                  path: '/finance',
                  builder: (_, __) => const FinanceHomePage(),
                  routes: [
                    GoRoute(
                        path: 'receivables',
                        builder: (_, __) => const Text('tela a receber')),
                  ],
                ),
              ],
            ),
          ),
        );

    testWidgets('mostra o total em aberto e abre A receber', (t) async {
      final api = FakeReceivablesApi([_item('a', _now, 4500)]);
      await t.pumpWidget(routed(api));
      await t.pumpAndSettle();
      expect(find.text('Em aberto: R\$ 45,00'), findsOneWidget);

      await t.tap(find.byKey(const Key('finance-receivables')));
      await t.pumpAndSettle();
      expect(find.text('tela a receber'), findsOneWidget);
    });

    testWidgets('receber avulso com cliente opcional', (t) async {
      final api = FakeReceivablesApi([]);
      await t.pumpWidget(routed(api));
      await t.pumpAndSettle();

      // o resumo do mês (F3) fica no topo: rola até o atalho
      await t.scrollUntilVisible(find.byKey(const Key('finance-walk-in')), 200);
      await t.tap(find.byKey(const Key('finance-walk-in')));
      await t.pumpAndSettle();
      expect(find.text('Receber avulso'), findsWidgets);
      await t.enterText(find.byKey(const Key('receive-amount')), '2500');
      await t.tap(find.byKey(const Key('receive-client')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ana').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('method-cash')));
      await t.pump();
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();

      final (p, appointmentId) = api.received.single;
      expect(appointmentId, isNull);
      expect(p.amountCents, 2500);
      expect(p.clientId, 'c1');
      expect(p.toJson(), {
        'client_id': 'c1',
        'amount_cents': 2500,
        'payment_method': 'cash',
      });
      expect(find.text('Recebimento registrado'), findsOneWidget);
    });
  });
}
