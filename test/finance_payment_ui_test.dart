import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/agenda/agenda_page.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/payment_section.dart';
import 'package:minha_agenda/features/finance/payment_status_chip.dart';
import 'package:minha_agenda/features/finance/receive_payment_sheet.dart';

/// API falsa: guarda o estado e as chamadas, sem rede.
class FakeFinanceApi extends FinanceApi {
  FakeFinanceApi(this.state) : super(Dio());
  AppointmentFinance state;
  final received = <NewPayment>[];
  final voided = <String>[];
  final prices = <int>[];
  Object? failWith;

  @override
  Future<AppointmentFinance> appointment(String appointmentId) async => state;

  @override
  Future<void> receive(NewPayment p,
      {String? appointmentId, String? clientId}) async {
    if (failWith != null) throw failWith!;
    received.add(p);
    final paid = state.paidCents + p.amountCents;
    state = AppointmentFinance(
      priceCents: state.priceCents,
      paidCents: paid,
      balanceCents: state.priceCents - paid,
      status:
          paid >= state.priceCents ? PaymentStatus.paid : PaymentStatus.partial,
      payments: [
        ...state.payments,
        Payment(
          id: 'p${received.length}',
          amountCents: p.amountCents,
          method: p.method,
          installments: p.installments,
          kind: 'payment',
          occurredAt: DateTime(2026, 11, 27, 10),
        ),
      ],
    );
  }

  @override
  Future<void> voidPayment(String paymentId) async {
    voided.add(paymentId);
    state = AppointmentFinance(
      priceCents: state.priceCents,
      paidCents: 0,
      balanceCents: state.priceCents,
      status: PaymentStatus.open,
      payments: [
        for (final p in state.payments)
          Payment(
            id: p.id,
            amountCents: p.amountCents,
            method: p.method,
            installments: p.installments,
            kind: p.kind,
            occurredAt: p.occurredAt,
            voidedAt: DateTime(2026, 11, 27, 11),
          ),
      ],
    );
  }

  @override
  Future<void> updatePrice(String appointmentId, int priceCents) async {
    if (failWith != null) throw failWith!;
    prices.add(priceCents);
    state = AppointmentFinance(
      priceCents: priceCents,
      paidCents: state.paidCents,
      balanceCents: priceCents - state.paidCents,
      status: state.status,
    );
  }
}

AppointmentFinance _open(int price) => AppointmentFinance(
    priceCents: price,
    paidCents: 0,
    balanceCents: price,
    status: PaymentStatus.open);

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

DioException _apiError(String msg) => DioException(
      requestOptions: RequestOptions(),
      response: Response(
          requestOptions: RequestOptions(),
          statusCode: 422,
          data: {'error': msg}),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('PaymentStatusChip', () {
    testWidgets('rótulo por situação; none não renderiza', (t) async {
      for (final s in [
        PaymentStatus.open,
        PaymentStatus.partial,
        PaymentStatus.paid
      ]) {
        await t.pumpWidget(_wrap(PaymentStatusChip(s)));
        expect(find.text(s.label), findsOneWidget);
      }
      await t.pumpWidget(_wrap(const PaymentStatusChip(PaymentStatus.none)));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('RF-F01 — ReceivePaymentSheet', () {
    Future<List<NewPayment>> open(WidgetTester t,
        {int? balance = 10000, Object? fail}) async {
      final sent = <NewPayment>[];
      await t.pumpWidget(_wrap(ReceivePaymentSheet(
        balanceCents: balance,
        onSubmit: (p) async {
          if (fail != null) throw fail;
          sent.add(p);
        },
      )));
      return sent;
    }

    testWidgets('valor começa no saldo; parcelas só no crédito', (t) async {
      await open(t);
      expect(find.text('100,00'), findsOneWidget);
      expect(find.byKey(const Key('receive-installments')), findsNothing);
      await t.tap(find.byKey(const Key('method-credit')));
      await t.pump();
      expect(find.byKey(const Key('receive-installments')), findsOneWidget);
    });

    testWidgets('valor acima do saldo desabilita e explica', (t) async {
      await open(t);
      await t.enterText(find.byKey(const Key('receive-amount')), '15000');
      await t.pump();
      expect(
          find.text('Maior que o saldo restante (R\$ 100,00)'), findsOneWidget);
      final btn = t.widget<FilledButton>(find.byKey(const Key('receive-save')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('envia centavos, forma e parcelas do crédito', (t) async {
      final sent = await open(t);
      await t.enterText(find.byKey(const Key('receive-amount')), '3000');
      await t.tap(find.byKey(const Key('method-credit')));
      await t.pump();
      await t.tap(find.byKey(const Key('receive-installments')));
      await t.pumpAndSettle();
      await t.tap(find.text('3x').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('receive-notes')), 'sinal');
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();
      expect(sent.single.amountCents, 3000);
      expect(sent.single.method, PaymentMethod.credit);
      expect(sent.single.installments, 3);
      expect(sent.single.notes, 'sinal');
    });

    testWidgets('erro da API aparece no painel', (t) async {
      await open(t, fail: _apiError('Este agendamento já está pago'));
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();
      expect(find.text('Este agendamento já está pago'), findsOneWidget);
    });

    testWidgets('avulso: sem saldo e começa vazio', (t) async {
      await open(t, balance: null);
      expect(find.textContaining('Saldo restante'), findsNothing);
      final btn = t.widget<FilledButton>(find.byKey(const Key('receive-save')));
      expect(btn.onPressed, isNull);
    });
  });

  group('RF-F02 — PaymentSection', () {
    testWidgets('receber o saldo inteiro: Em aberto → Pago', (t) async {
      final api = FakeFinanceApi(_open(5000));
      var changed = 0;
      await t.pumpWidget(_wrap(PaymentSection(
          appointmentId: 'a1', api: api, onChanged: () => changed++)));
      await t.pumpAndSettle();
      expect(find.text('Em aberto'), findsOneWidget);
      expect(find.text('R\$ 50,00'), findsNWidgets(2)); // valor e saldo

      await t.tap(find.byKey(const Key('payment-receive')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('receive-save')));
      await t.pumpAndSettle();

      expect(api.received.single.amountCents, 5000);
      expect(find.text('Pago'), findsOneWidget);
      expect(find.byKey(const Key('payment-receive')), findsNothing);
      expect(find.byKey(const Key('payment-edit-price')), findsNothing);
      expect(changed, 1);
    });

    testWidgets('estorno pede confirmação e volta a Em aberto', (t) async {
      final api = FakeFinanceApi(_open(5000));
      await api.receive(
          const NewPayment(amountCents: 5000, method: PaymentMethod.pix));
      await t.pumpWidget(_wrap(PaymentSection(appointmentId: 'a1', api: api)));
      await t.pumpAndSettle();
      expect(find.text('Pago'), findsOneWidget);

      await t.tap(find.byKey(const Key('void-p1')));
      await t.pumpAndSettle();
      expect(find.text('Estornar recebimento?'), findsOneWidget);
      await t.tap(find.byKey(const Key('void-confirm')));
      await t.pumpAndSettle();

      expect(api.voided, ['p1']);
      expect(find.text('Em aberto'), findsOneWidget);
      expect(find.text('Estornado'), findsOneWidget);
    });

    testWidgets('editar valor envia centavos; erro vira snackbar', (t) async {
      final api = FakeFinanceApi(_open(5000));
      await t.pumpWidget(_wrap(PaymentSection(appointmentId: 'a1', api: api)));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('payment-edit-price')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('price-field')), '4000');
      await t.tap(find.byKey(const Key('price-save')));
      await t.pumpAndSettle();
      expect(api.prices, [4000]);
      expect(find.text('R\$ 40,00'), findsNWidgets(2));

      api.failWith = _apiError('O valor não pode ser menor que o já recebido');
      await t.tap(find.byKey(const Key('payment-edit-price')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('price-field')), '100');
      await t.tap(find.byKey(const Key('price-save')));
      await t.pumpAndSettle();
      expect(find.text('O valor não pode ser menor que o já recebido'),
          findsOneWidget);
    });
  });

  group('Appointment.fromJson — finanças', () {
    final base = {
      'id': 'id-1',
      'starts_at': '2026-11-30T12:00:00.000Z',
      'ends_at': '2026-11-30T12:30:00.000Z',
      'status': 'confirmed',
    };

    test('lê os campos da API 0027', () {
      final a = Appointment.fromJson({
        ...base,
        'service_price_cents': 9000,
        'price_cents': 8000,
        'paid_cents': 3000,
        'balance_cents': 5000,
        'payment_status': 'partial',
      });
      expect(a.priceCents, 8000);
      expect(a.paidCents, 3000);
      expect(a.balanceCents, 5000);
      expect(a.paymentStatus, PaymentStatus.partial);
    });

    test('API antiga: usa o preço de tabela e fica sem situação', () {
      final a = Appointment.fromJson({...base, 'service_price_cents': 9000});
      expect(a.priceCents, 9000);
      expect(a.balanceCents, 9000);
      expect(a.paymentStatus, PaymentStatus.none);
    });
  });
}
