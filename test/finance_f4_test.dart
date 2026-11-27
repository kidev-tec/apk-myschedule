import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/finance/cash_models.dart';
import 'package:minha_agenda/features/finance/cash_page.dart';
import 'package:minha_agenda/features/finance/cashflow_models.dart';
import 'package:minha_agenda/features/finance/cashflow_page.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/payment_section.dart';
import 'package:minha_agenda/features/finance/receipt_sheet.dart';

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    final body = o.path == '/finance/cashflow'
        ? {'inflow_cents': 100, 'days': []}
        : _receiptJson();
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

Map<String, dynamic> _receiptJson({bool full = true}) => {
      'number': 7,
      'payment': {
        'id': 'p1',
        'amount_cents': 3000,
        'payment_method': 'credit',
        'installments': 2,
        'kind': full ? 'deposit' : 'payment',
        'occurred_at': '2026-11-27T13:00:00.000Z',
        'notes': full ? 'Pago na hora' : null,
      },
      'business': {
        'name': 'Studio Ana',
        'address': full ? 'Rua A, 10 — Bauru/SP' : null,
        'logo_url': null,
      },
      'client': full ? {'name': 'Maria'} : null,
      'appointment': full
          ? {
              'service_name': 'Escova',
              'starts_at': '2026-11-30T15:00:00.000Z',
              'price_cents': 10000,
              'paid_cents': 3000,
              'balance_cents': 7000,
            }
          : null,
    };

Cashflow _flow({bool overdue = true, bool empty = false}) => Cashflow.fromJson({
      'inflow_cents': empty ? 0 : 7000,
      'outflow_cents': empty ? 0 : 9000,
      'net_cents': empty ? 0 : -2000,
      'overdue_in_cents': overdue ? 5000 : 0,
      'overdue_out_cents': overdue ? 800 : 0,
      'days': [
        {
          'date': '2026-11-27',
          'inflow_cents': 0,
          'outflow_cents': 0,
          'balance_cents': 0,
          'items': []
        },
        if (!empty) ...[
          {
            'date': '2026-11-29',
            'inflow_cents': 7000,
            'outflow_cents': 0,
            'balance_cents': 7000,
            'items': [
              {
                'kind': 'appointment',
                'id': 'a1',
                'label': 'Ana • Escova',
                'amount_cents': 7000
              }
            ]
          },
          {
            'date': '2026-12-02',
            'inflow_cents': 0,
            'outflow_cents': 9000,
            'balance_cents': -2000,
            'items': [
              {
                'kind': 'expense',
                'id': 'e1',
                'label': 'Aluguel',
                'amount_cents': 9000
              }
            ]
          },
        ],
      ],
    });

class FakeF4Api extends FinanceApi {
  FakeF4Api() : super(Dio());
  final windows = <int>[];
  Cashflow flow = _flow();
  Object? receiptError;
  CashSession? session;

  @override
  Future<Cashflow> cashflow({int days = 30}) async {
    windows.add(days);
    return flow;
  }

  @override
  Future<Receipt> receipt(String paymentId) async {
    if (receiptError != null) throw receiptError!;
    return Receipt.fromJson(_receiptJson());
  }

  @override
  Future<AppointmentFinance> appointment(String appointmentId) async =>
      AppointmentFinance(
        priceCents: 10000,
        paidCents: 3000,
        balanceCents: 7000,
        status: PaymentStatus.partial,
        payments: [
          Payment(
            id: 'p1',
            amountCents: 3000,
            method: PaymentMethod.credit,
            installments: 2,
            kind: 'deposit',
            occurredAt: DateTime(2026, 11, 27, 10),
          ),
        ],
      );

  @override
  Future<CashSession?> cashCurrent() async => session;
}

class FakeSharer extends ReceiptSharer {
  final images = <(int, String, String)>[];
  final copied = <String>[];
  @override
  Future<void> shareImage(Uint8List png, String fileName, String text) async =>
      images.add((png.length, fileName, text));
  @override
  Future<void> copyText(String text) async => copied.add(text);
}

Widget _app(FinanceApi api, Widget home) => ProviderScope(
      overrides: [financeApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('modelos e API F4', () {
    test('fromJson e rotas', () async {
      final f = _flow();
      expect(f.days.where((d) => d.items.isNotEmpty), hasLength(2));
      expect(f.days[1].items.single.isIn, isTrue);
      expect(Cashflow.fromJson({}).days, isEmpty);
      final r = Receipt.fromJson(_receiptJson(full: false));
      expect(r.clientName, isNull);
      expect(r.appointmentAt, isNull);
      expect(r.isDeposit, isFalse);

      final adapter = _Adapter();
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);
      await api.cashflow(days: 7);
      await api.cashflow();
      final rc = await api.receipt('p1');
      expect(rc.number, 7);
      expect(adapter.calls.map((c) => '${c.path} ${c.queryParameters}'), [
        '/finance/cashflow {days: 7}',
        '/finance/cashflow {days: 30}',
        '/finance/transactions/p1/receipt {}',
      ]);
    });

    test('receiptText: completo e avulso', () {
      final full = receiptText(Receipt.fromJson(_receiptJson()));
      expect(full, contains('COMPROVANTE Nº 0007'));
      expect(full, contains('Sinal recebido: R\$ 30,00'));
      expect(full, contains('Forma: Crédito em 2x'));
      expect(full, contains('Cliente: Maria'));
      expect(full, contains('Falta pagar: R\$ 70,00'));
      expect(full, contains('Obs.: Pago na hora'));
      final paid = Receipt.fromJson({
        ..._receiptJson(),
        'appointment': {
          'service_name': 'Escova',
          'starts_at': '2026-11-30T15:00:00Z',
          'price_cents': 3000,
          'paid_cents': 3000,
          'balance_cents': 0,
        },
      });
      expect(receiptText(paid), contains('Atendimento quitado'));
      final walk = receiptText(Receipt.fromJson(_receiptJson(full: false)));
      expect(walk, contains('Valor recebido: R\$ 30,00'));
      expect(walk, isNot(contains('Cliente')));
      expect(walk, isNot(contains('Total do atendimento')));
    });
  });

  group('RF-F11 — CashflowPage', () {
    Widget routed(FinanceApi api) => ProviderScope(
          overrides: [financeApiProvider.overrideWithValue(api)],
          child: MaterialApp.router(
            routerConfig: GoRouter(routes: [
              GoRoute(path: '/', builder: (_, __) => const CashflowPage()),
              GoRoute(
                  path: '/finance/receivables',
                  builder: (_, __) => const Text('tela a receber')),
              GoRoute(
                  path: '/finance/expenses',
                  builder: (_, __) => const Text('tela despesas')),
            ]),
          ),
        );

    testWidgets('totais, dias com movimento, saldo negativo e atrasados',
        (t) async {
      final api = FakeF4Api();
      await t.pumpWidget(routed(api));
      await t.pumpAndSettle();
      expect(api.windows, [30]);
      expect(t.widget<Text>(find.byKey(const Key('cashflow-net'))).data,
          '-R\$ 20,00');
      expect(find.text('Ana • Escova'), findsOneWidget);
      expect(find.text('+ R\$ 70,00'), findsOneWidget);
      expect(find.text('Saldo -R\$ 20,00'), findsOneWidget);
      expect(find.byKey(const Key('cashflow-day-2026-11-27')), findsNothing);

      await t.tap(find.byKey(const Key('overdue-in')));
      await t.pumpAndSettle();
      expect(find.text('tela a receber'), findsOneWidget);
    });

    testWidgets('trocar a janela; sem atrasados e sem movimento', (t) async {
      final api = FakeF4Api()..flow = _flow(overdue: false, empty: true);
      await t.pumpWidget(routed(api));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('cashflow-overdue')), findsNothing);
      expect(
          find.text('Nada previsto para os próximos 30 dias.'), findsOneWidget);
      await t.tap(find.byKey(const Key('cashflow-7')));
      await t.pumpAndSettle();
      expect(api.windows.last, 7);
      expect(
          find.text('Nada previsto para os próximos 7 dias.'), findsOneWidget);
    });

    testWidgets('atalho para despesas vencidas', (t) async {
      await t.pumpWidget(routed(FakeF4Api()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('overdue-out')));
      await t.pumpAndSettle();
      expect(find.text('tela despesas'), findsOneWidget);
    });
  });

  group('RF-F12 — comprovante', () {
    testWidgets('prévia, copiar texto e compartilhar imagem', (t) async {
      final sharer = FakeSharer();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReceiptSheet(paymentId: 'p1', api: FakeF4Api(), sharer: sharer),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('COMPROVANTE Nº 0007'), findsOneWidget);
      expect(find.text('Studio Ana'), findsOneWidget);
      expect(find.text('Falta R\$ 70,00'), findsOneWidget);
      expect(find.text('Crédito em 2x'), findsOneWidget);

      await t.tap(find.byKey(const Key('receipt-copy')));
      await t.pumpAndSettle();
      expect(sharer.copied.single, contains('COMPROVANTE Nº 0007'));
      expect(find.text('Texto do comprovante copiado'), findsOneWidget);

      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('receipt-share')));
        for (var i = 0; i < 20 && sharer.images.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await t.pump();
      final (bytes, name, text) = sharer.images.single;
      expect(bytes, greaterThan(0));
      expect(name, 'comprovante-0007.png');
      expect(text, contains('Studio Ana'));
    });

    testWidgets('erro ao carregar mostra a mensagem', (t) async {
      final api = FakeF4Api()
        ..receiptError = DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: 409,
              data: {'error': 'Recebimento estornado não gera comprovante'}),
        );
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: ReceiptSheet(paymentId: 'p1', api: api)),
      ));
      await t.pumpAndSettle();
      expect(find.text('Recebimento estornado não gera comprovante'),
          findsOneWidget);
    });

    testWidgets('falha ao compartilhar vira aviso', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReceiptSheet(
              paymentId: 'p1', api: FakeF4Api(), sharer: _FailingSharer()),
        ),
      ));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('receipt-share')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(find.textContaining('Não consegui compartilhar'), findsOneWidget);
    });

    testWidgets('botão Comprovante no bloco Pagamento abre o comprovante',
        (t) async {
      final api = FakeF4Api();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: PaymentSection(appointmentId: 'a1', api: api)),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('receipt-p1')));
      await t.pumpAndSettle();
      expect(find.text('COMPROVANTE Nº 0007'), findsOneWidget);
    });

    testWidgets('caixa: toque num recebimento abre o comprovante', (t) async {
      final api = FakeF4Api()
        ..session = CashSession.fromJson({
          'id': 's1',
          'opened_at': '2026-11-27T11:00:00Z',
          'movements': [
            {
              'id': 'p1',
              'kind': 'payment',
              'type': 'income',
              'amount_cents': 3000,
              'payment_method': 'cash',
              'occurred_at': '2026-11-27T12:00:00Z',
            },
            {
              'id': 'm2',
              'kind': 'cash_in',
              'type': 'income',
              'amount_cents': 100,
              'payment_method': 'cash',
              'occurred_at': '2026-11-27T12:10:00Z',
            },
          ],
        });
      await t.pumpWidget(_app(api, const CashPage()));
      await t.pumpAndSettle();
      expect(
          t.widget<ListTile>(find.byKey(const Key('cash-movement-m2'))).onTap,
          isNull);
      await t.tap(find.byKey(const Key('cash-movement-p1')));
      await t.pumpAndSettle();
      expect(find.text('COMPROVANTE Nº 0007'), findsOneWidget);
    });
  });
}

class _FailingSharer extends ReceiptSharer {
  @override
  Future<void> shareImage(Uint8List png, String fileName, String text) =>
      Future.error(Exception('sem app'));
}
