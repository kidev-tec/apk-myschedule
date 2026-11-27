import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/finance/cash_models.dart';
import 'package:minha_agenda/features/finance/cash_page.dart';
import 'package:minha_agenda/features/finance/expense_models.dart';
import 'package:minha_agenda/features/finance/expense_sheet.dart';
import 'package:minha_agenda/features/finance/expenses_page.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/finance_home_page.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/report_models.dart';

final _now = DateTime(2026, 11, 27, 12);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  final calls = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    return handler(options);
  }
}

ResponseBody _json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, dynamic> _sessionJson({String? closedAt, int expected = 10000}) => {
      'id': 's1',
      'opened_at': '2026-11-27T11:00:00.000Z',
      'opening_cents': 5000,
      'cash_in_cents': 12000,
      'cash_out_cents': 7000,
      'expected_cents': expected,
      'by_method': {'cash': 10000, 'pix': 8000, 'boleto': 1},
      'movements': [
        {
          'id': 'm1',
          'kind': 'cash_out',
          'type': 'expense',
          'amount_cents': 4000,
          'payment_method': 'cash',
          'notes': 'depósito',
          'occurred_at': '2026-11-27T12:00:00.000Z',
          'voided_at': null,
        },
        {
          'id': 'm2',
          'kind': 'payment',
          'type': 'income',
          'amount_cents': 10000,
          'payment_method': 'cash',
          'occurred_at': '2026-11-27T12:30:00.000Z',
          'voided_at': '2026-11-27T13:00:00.000Z',
        },
      ],
      'closed_at': closedAt,
      'counted_cents': closedAt == null ? null : 9500,
      'difference_cents': closedAt == null ? null : -500,
    };

Expense _expense(String id,
        {bool paid = true, bool overdue = false, String? voided}) =>
    Expense(
      id: id,
      amountCents: 3000,
      category: ExpenseCategory.aluguel,
      method: paid ? PaymentMethod.pix : null,
      paid: paid,
      occurredAt: _now,
      dueAt: paid ? null : _now,
      overdue: overdue,
      voidedAt: voided == null ? null : _now,
    );

/// API falsa da Fase 2.
class FakeF2Api extends FinanceApi {
  FakeF2Api() : super(Dio());
  List<Expense> expensesList = [];
  final expenseQueries = <(DateTime?, DateTime?, String?)>[];
  final created = <NewExpense>[];
  final paidCalls = <(String, PaymentMethod)>[];
  final voided = <String>[];
  CashSession? session;
  List<CashSession> history = [];
  final calls = <String>[];
  Object? failWith;

  @override
  Future<Expenses> expenses(
      {DateTime? from, DateTime? to, String? status}) async {
    expenseQueries.add((from, to, status));
    return Expenses(
        items: expensesList,
        paidCents: 3000,
        pendingCents: 2000,
        overdueCents: 1000);
  }

  @override
  Future<void> createExpense(NewExpense e) async => created.add(e);

  @override
  Future<void> payExpense(String id, PaymentMethod method) async =>
      paidCalls.add((id, method));

  @override
  Future<void> voidPayment(String paymentId) async => voided.add(paymentId);

  @override
  Future<CashSession?> cashCurrent() async => session;

  @override
  Future<List<CashSession>> cashHistory() async => history;

  @override
  Future<void> cashOpen(int openingCents) async {
    calls.add('open $openingCents');
    session = CashSession.fromJson(_sessionJson());
  }

  @override
  Future<void> cashMove(
      {required bool cashIn, required int amountCents, String? notes}) async {
    if (failWith != null) throw failWith!;
    calls.add('${cashIn ? 'in' : 'out'} $amountCents ${notes ?? ''}'.trim());
  }

  @override
  Future<CashSession> cashClose(int countedCents, {String? notes}) async {
    calls.add('close $countedCents');
    final closed = CashSession.fromJson(
        _sessionJson(closedAt: '2026-11-27T20:00:00.000Z'));
    session = null;
    history = [closed];
    return closed;
  }
}

Widget _app(FinanceApi api, Widget home) => ProviderScope(
      overrides: [financeApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('modelos F2', () {
    test('Expense/Expenses.fromJson', () {
      final e = Expenses.fromJson({
        'items': [
          {
            'id': 'e1',
            'amount_cents': 2500,
            'category': 'outros',
            'payment_method': null,
            'paid': false,
            'due_at': '2026-11-20T15:00:00.000Z',
            'occurred_at': '2026-11-20T15:00:00.000Z',
            'notes': 'Cadeira',
            'voided_at': null,
            'overdue': true,
          },
          {
            'id': 'e2',
            'amount_cents': 100,
            'category': 'xyz',
            'occurred_at': '2026-11-20T15:00:00.000Z',
          },
        ],
        'paid_cents': 100,
        'pending_cents': 2500,
        'overdue_cents': 2500,
      });
      expect(e.items.first.title, 'Cadeira');
      expect(e.items.first.overdue, isTrue);
      expect(e.items.first.dueAt, isNotNull);
      expect(e.items.last.category, ExpenseCategory.outros);
      expect(e.items.last.title, 'Outros');
      expect(e.items.last.paid, isTrue);
      expect(e.pendingCents, 2500);
      expect(Expenses.fromJson({}).items, isEmpty);
    });

    test('NewExpense.toJson: forma só quando paga', () {
      final d = DateTime.utc(2026, 11, 27, 15);
      expect(
        NewExpense(
          amountCents: 100,
          category: ExpenseCategory.energiaAgua,
          paid: false,
          date: d,
          method: PaymentMethod.pix,
          notes: '  ',
        ).toJson(),
        {
          'amount_cents': 100,
          'category': 'energia_agua',
          'paid': false,
          'date': '2026-11-27T15:00:00.000Z',
        },
      );
      expect(
        const NewExpense(
                amountCents: 100,
                category: ExpenseCategory.taxas,
                method: PaymentMethod.cash,
                notes: ' Boleto ')
            .toJson(),
        {
          'amount_cents': 100,
          'category': 'taxas',
          'paid': true,
          'payment_method': 'cash',
          'notes': 'Boleto',
        },
      );
    });

    test('CashSession.fromJson ignora forma desconhecida', () {
      final s = CashSession.fromJson(_sessionJson());
      expect(s.isOpen, isTrue);
      expect(s.byMethod, {PaymentMethod.cash: 10000, PaymentMethod.pix: 8000});
      expect(s.movements.first.label, 'Sangria');
      expect(s.movements.first.isIn, isFalse);
      expect(s.movements.last.isVoided, isTrue);
      final closed =
          CashSession.fromJson(_sessionJson(closedAt: '2026-11-27T20:00:00Z'));
      expect(closed.isOpen, isFalse);
      expect(closed.differenceCents, -500);
      for (final (kind, label) in [
        ('cash_in', 'Suprimento'),
        ('expense', 'Despesa'),
        ('deposit', 'Sinal'),
        ('payment', 'Recebimento'),
      ]) {
        expect(
            CashMovement.fromJson({
              'id': 'x',
              'kind': kind,
              'amount_cents': 1,
              'occurred_at': '2026-11-27T12:00:00Z',
            }).label,
            label);
      }
    });
  });

  group('FinanceApi F2', () {
    test('rotas de despesas e caixa', () async {
      final adapter = _Adapter((o) => switch (o.path) {
            '/finance/expenses' when o.method == 'GET' =>
              _json({'items': [], 'paid_cents': 0}),
            '/finance/cash/current' => _json({'session': null}),
            '/finance/cash' => _json({
                'sessions': [_sessionJson(closedAt: '2026-11-27T20:00:00Z')]
              }),
            '/finance/cash/close' => _json(
                {'session': _sessionJson(closedAt: '2026-11-27T20:00:00Z')}),
            _ => _json({}),
          });
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);

      await api.expenses(
          from: DateTime.utc(2026, 11),
          to: DateTime.utc(2026, 12),
          status: 'paid');
      await api.expenses();
      await api.createExpense(const NewExpense(
          amountCents: 100,
          category: ExpenseCategory.taxas,
          method: PaymentMethod.pix));
      await api.payExpense('e1', PaymentMethod.debit);
      expect(await api.cashCurrent(), isNull);
      await api.cashOpen(5000);
      await api.cashMove(cashIn: true, amountCents: 200, notes: ' troco ');
      await api.cashMove(cashIn: false, amountCents: 100);
      final closed = await api.cashClose(9500, notes: 'ok');
      await api.cashClose(9500);
      final hist = await api.cashHistory();

      expect(closed.differenceCents, -500);
      expect(hist.single.countedCents, 9500);
      final c = adapter.calls;
      expect(c[0].queryParameters, {
        'from': '2026-11-01T00:00:00.000Z',
        'to': '2026-12-01T00:00:00.000Z',
        'status': 'paid',
      });
      expect(c[1].queryParameters, isEmpty);
      expect(c[3].data, {'payment_method': 'debit'});
      expect(c[3].path, '/finance/expenses/e1/pay');
      expect(c[5].data, {'opening_cents': 5000});
      expect(c[6].data,
          {'direction': 'in', 'amount_cents': 200, 'notes': 'troco'});
      expect(c[7].data, {'direction': 'out', 'amount_cents': 100});
      expect(c[8].data, {'counted_cents': 9500, 'notes': 'ok'});
      expect(c[9].data, {'counted_cents': 9500});
    });
  });

  group('RF-F06 — ExpenseSheet', () {
    Future<List<NewExpense>> open(WidgetTester t) async {
      final sent = <NewExpense>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              ExpenseSheet(onSubmit: (e) async => sent.add(e), now: () => _now),
        ),
      ));
      return sent;
    }

    testWidgets('paga: envia valor, categoria, forma e a data de hoje',
        (t) async {
      final sent = await open(t);
      final save = find.byKey(const Key('expense-save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      await t.enterText(find.byKey(const Key('expense-amount')), '15000');
      await t.tap(find.byKey(const Key('category-aluguel')));
      await t.tap(find.byKey(const Key('expense-method-cash')));
      await t.pump();
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      final e = sent.single;
      expect(e.amountCents, 15000);
      expect(e.category, ExpenseCategory.aluguel);
      expect(e.paid, isTrue);
      expect(e.method, PaymentMethod.cash);
      expect(e.date, DateTime(2026, 11, 27, 12));
    });

    testWidgets('outros exige descrição; a pagar exige vencimento', (t) async {
      final sent = await open(t);
      final save = find.byKey(const Key('expense-save'));
      await t.enterText(find.byKey(const Key('expense-amount')), '2500');
      await t.tap(find.byKey(const Key('category-outros')));
      await t.pump();
      expect(find.text('Descrição (obrigatória)'), findsOneWidget);
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      await t.enterText(find.byKey(const Key('expense-notes')), 'Cadeira');
      await t.tap(find.byKey(const Key('expense-paid')));
      await t.pump();
      expect(find.byKey(const Key('expense-method-pix')), findsNothing);
      expect(t.widget<FilledButton>(save).onPressed, isNull);

      await t.ensureVisible(find.byKey(const Key('expense-due-on')));
      await t.tap(find.byKey(const Key('expense-due-on')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Vence em 27/11/2026'), findsOneWidget);
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(sent.single.paid, isFalse);
      expect(sent.single.method, isNull);
      expect(sent.single.notes, 'Cadeira');
      expect(sent.single.date, DateTime(2026, 11, 27, 12));
    });

    testWidgets('trocar a data do pagamento', (t) async {
      await open(t);
      await t.ensureVisible(find.byKey(const Key('expense-paid-on')));
      await t.tap(find.byKey(const Key('expense-paid-on')));
      await t.pumpAndSettle();
      await t.tap(find.text('26'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Pago em 26/11/2026'), findsOneWidget);
    });

    testWidgets('erro da API aparece no painel', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExpenseSheet(
            now: () => _now,
            onSubmit: (_) async => throw DioException(
              requestOptions: RequestOptions(),
              response: Response(
                  requestOptions: RequestOptions(),
                  statusCode: 400,
                  data: {'error': 'Categoria inválida'}),
            ),
          ),
        ),
      ));
      await t.enterText(find.byKey(const Key('expense-amount')), '100');
      await t.pump();
      final save = find.byKey(const Key('expense-save'));
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.text('Categoria inválida'), findsOneWidget);
    });
  });

  group('RF-F06 — ExpensesPage', () {
    testWidgets('totais, mês, status, pagar e estornar', (t) async {
      final api = FakeF2Api()
        ..expensesList = [
          _expense('a'),
          _expense('b', paid: false, overdue: true),
          _expense('c', voided: 'x'),
        ];
      await t.pumpWidget(_app(api, ExpensesPage(now: () => _now)));
      await t.pumpAndSettle();

      expect(find.text('Novembro 2026'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('expenses-paid'))).data,
          'R\$ 30,00');
      expect(find.text('Vencida em 27/11'), findsOneWidget);
      expect(find.text('Estornada'), findsOneWidget);
      expect(find.byKey(const Key('expense-menu-c')), findsNothing);
      expect(api.expenseQueries.first, (
        DateTime(2026, 11),
        DateTime(2026, 12).subtract(const Duration(milliseconds: 1)),
        null
      ));

      await t.tap(find.byKey(const Key('month-prev')));
      await t.pumpAndSettle();
      expect(find.text('Outubro 2026'), findsOneWidget);
      await t.tap(find.byKey(const Key('month-next')));
      await t.tap(find.byKey(const Key('expense-status-pending')));
      await t.pumpAndSettle();
      expect(api.expenseQueries.last.$3, 'pending');
      await t.tap(find.byKey(const Key('expense-status-paid')));
      await t.pumpAndSettle();
      expect(api.expenseQueries.last.$3, 'paid');

      await t.tap(find.byKey(const Key('expense-menu-b')));
      await t.pumpAndSettle();
      await t.tap(find.text('Pagar'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pay-with-cash')));
      await t.pumpAndSettle();
      expect(api.paidCalls.single, ('b', PaymentMethod.cash));

      await t.tap(find.byKey(const Key('expense-menu-a')));
      await t.pumpAndSettle();
      expect(find.text('Pagar'), findsNothing);
      await t.tap(find.text('Estornar'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('expense-void-confirm')));
      await t.pumpAndSettle();
      expect(api.voided, ['a']);
    });

    testWidgets('nova despesa pelo botão e lista vazia', (t) async {
      final api = FakeF2Api();
      await t.pumpWidget(_app(api, ExpensesPage(now: () => _now)));
      await t.pumpAndSettle();
      expect(find.text('Nenhuma despesa neste mês.'), findsOneWidget);
      await t.tap(find.byKey(const Key('expense-add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('expense-amount')), '900');
      await t.pump();
      final save = find.byKey(const Key('expense-save'));
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.created.single.amountCents, 900);
      expect(find.text('Despesa registrada'), findsOneWidget);
    });
  });

  group('RF-F05 — CashPage', () {
    testWidgets('fechado: abrir com troco; histórico com a diferença',
        (t) async {
      final api = FakeF2Api()
        ..history = [
          CashSession.fromJson(_sessionJson(closedAt: '2026-11-26T20:00:00Z'))
        ];
      await t.pumpWidget(_app(api, const CashPage()));
      await t.pumpAndSettle();
      expect(find.text('Caixa fechado'), findsOneWidget);
      expect(find.text('Falta R\$ 5,00'), findsOneWidget);

      await t.tap(find.byKey(const Key('cash-open')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('cash-amount')), '5000');
      await t.tap(find.byKey(const Key('cash-amount-save')));
      await t.pumpAndSettle();
      expect(api.calls, ['open 5000']);
      expect(t.widget<Text>(find.byKey(const Key('cash-expected'))).data,
          'R\$ 100,00');
      expect(find.text('Estornado'), findsOneWidget);
      expect(find.text('Recebido com o caixa aberto'), findsOneWidget);
    });

    testWidgets('aberto: suprimento, sangria com erro e fechar', (t) async {
      final api = FakeF2Api()..session = CashSession.fromJson(_sessionJson());
      await t.pumpWidget(_app(api, const CashPage()));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('cash-in')));
      await t.pumpAndSettle();
      final ok = find.byKey(const Key('cash-amount-save'));
      expect(t.widget<FilledButton>(ok).onPressed, isNull);
      await t.enterText(find.byKey(const Key('cash-amount')), '2000');
      await t.enterText(find.byKey(const Key('cash-notes')), 'troco');
      await t.pump();
      await t.tap(ok);
      await t.pumpAndSettle();
      expect(api.calls.last, 'in 2000 troco');
      expect(find.text('Suprimento registrado'), findsOneWidget);

      api.failWith = DioException(
        requestOptions: RequestOptions(),
        response: Response(
            requestOptions: RequestOptions(),
            statusCode: 422,
            data: {'error': 'Não há dinheiro suficiente no caixa'}),
      );
      await t.tap(find.byKey(const Key('cash-out')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('cash-amount')), '999999');
      await t.pump();
      await t.tap(find.byKey(const Key('cash-amount-save')));
      await t.pumpAndSettle();
      expect(find.text('Não há dinheiro suficiente no caixa'), findsOneWidget);

      await t.tap(find.byKey(const Key('cash-close')));
      await t.pumpAndSettle();
      final confirm = find.byKey(const Key('cash-close-confirm'));
      expect(t.widget<FilledButton>(confirm).onPressed, isNull);
      await t.enterText(find.byKey(const Key('cash-counted')), '10500');
      await t.pump();
      expect(find.text('Sobra R\$ 5,00'), findsOneWidget);
      await t.enterText(find.byKey(const Key('cash-counted')), '10000');
      await t.pump();
      expect(find.text('Confere'), findsOneWidget);
      await t.enterText(find.byKey(const Key('cash-counted')), '9500');
      await t.pump();
      expect(find.text('Falta R\$ 5,00'), findsOneWidget);
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(api.calls.last, 'close 9500');
      expect(find.text('Caixa fechado'), findsWidgets);
    });

    testWidgets('cancelar diálogos não chama a API', (t) async {
      final api = FakeF2Api();
      await t.pumpWidget(_app(api, const CashPage()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cash-open')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
    });
  });

  group('FinanceHomePage — caixa', () {
    testWidgets('mostra Fechado ou o horário e o esperado', (t) async {
      final api = _HomeApi();
      await t.pumpWidget(_app(api, const FinanceHomePage()));
      await t.pumpAndSettle();
      expect(find.text('Fechado'), findsOneWidget);
      expect(find.byKey(const Key('finance-expenses')), findsOneWidget);

      api.session = CashSession.fromJson(_sessionJson());
      await t.pumpWidget(_app(api, const FinanceHomePage(key: Key('again'))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('finance-cash-status'))).data,
          contains('esperado R\$ 100,00'));
    });
  });
}

/// Home também consulta "A receber".
class _HomeApi extends FakeF2Api {
  @override
  Future<ReportSummary> reportSummary(DateTime from, DateTime to) async =>
      const ReportSummary(revenueCents: 0, expensesCents: 0, resultCents: 0);

  @override
  Future<Goal> goal(DateTime month) async => const Goal(month: '2026-11');

  @override
  Future<Receivables> receivables(
          {DateTime? from, DateTime? to, String? clientId}) async =>
      const Receivables(
          items: [], totalOpenCents: 0, overdueCents: 0, upcomingCents: 0);
}
