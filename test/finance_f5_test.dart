import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/online_account_page.dart';
import 'package:minha_agenda/features/finance/online_charge_sheet.dart';
import 'package:minha_agenda/features/finance/online_models.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';
import 'package:minha_agenda/features/finance/payment_section.dart';

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    final body = switch (o.path) {
      '/finance/online/account' => {'available': true, 'status': 'pending'},
      '/finance/charges' when o.method == 'GET' => {
          'charges': [_chargeJson('c1')]
        },
      '/finance/charges' => {'charge': _chargeJson('c2')},
      _ => <String, dynamic>{},
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

Map<String, dynamic> _chargeJson(String id,
        {String status = 'pending', int amount = 7000}) =>
    {
      'id': id,
      'amount_cents': amount,
      'status': status,
      'invoice_url': 'https://asaas.test/i/$id',
      'due_date': '2026-11-30',
    };

DioException _apiError(String msg) => DioException(
      requestOptions: RequestOptions(),
      response: Response(
          requestOptions: RequestOptions(),
          statusCode: 422,
          data: {'error': msg}),
    );

class FakeOnlineApi extends FinanceApi {
  FakeOnlineApi() : super(Dio());
  OnlineAccount account = const OnlineAccount(available: true, status: 'none');
  final activations = <OnlineActivation>[];
  List<Charge> list = [];
  final created = <int?>[];
  final canceled = <String>[];
  Object? failWith;

  @override
  Future<OnlineAccount> onlineAccount() async => account;

  @override
  Future<OnlineAccount> activateOnline(OnlineActivation a) async {
    if (failWith != null) throw failWith!;
    activations.add(a);
    account = const OnlineAccount(available: true, status: 'pending');
    return account;
  }

  @override
  Future<List<Charge>> charges(String appointmentId) async => list;

  @override
  Future<Charge> createCharge(String appointmentId, {int? amountCents}) async {
    if (failWith != null) throw failWith!;
    created.add(amountCents);
    final c = Charge.fromJson(
        _chargeJson('n${created.length}', amount: amountCents ?? 7000));
    list = [...list, c];
    return c;
  }

  @override
  Future<void> cancelCharge(String chargeId) async {
    canceled.add(chargeId);
    list = [
      for (final c in list)
        c.id == chargeId
            ? Charge.fromJson(
                _chargeJson(c.id, status: 'canceled', amount: c.amountCents))
            : c,
    ];
  }

  @override
  Future<AppointmentFinance> appointment(String appointmentId) async =>
      const AppointmentFinance(
          priceCents: 10000,
          paidCents: 3000,
          balanceCents: 7000,
          status: PaymentStatus.partial);
}

class FakeSharer extends LinkSharer {
  final shared = <String>[];
  final copied = <String>[];
  @override
  Future<void> share(String text) async => shared.add(text);
  @override
  Future<void> copy(String text) async => copied.add(text);
}

Widget _app(FinanceApi api, Widget home) => ProviderScope(
      overrides: [financeApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

/// A lista do formulário (os campos de texto têm Scrollables próprios).
final _formScroll = find
    .descendant(
        of: find.byKey(const Key('online-form')),
        matching: find.byType(Scrollable))
    .first;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('modelos e API F5', () {
    test('fromJson, toJson e rotas', () async {
      expect(
          OnlineAccount.fromJson({'available': true, 'status': 'approved'})
              .isApproved,
          isTrue);
      expect(OnlineAccount.fromJson({}).status, 'none');
      final c = Charge.fromJson(_chargeJson('x', status: 'overdue'));
      expect(c.isOpen, isTrue);
      expect(c.statusLabel, 'Vencida');
      for (final (s, l) in [
        ('paid', 'Paga'),
        ('canceled', 'Cancelada'),
        ('refunded', 'Estornada'),
        ('pending', 'Aguardando pagamento'),
      ]) {
        expect(Charge.fromJson(_chargeJson('x', status: s)).statusLabel, l);
      }
      expect(chargeMessage(c), contains('R\$ 70,00'));
      expect(chargeMessage(c), contains('https://asaas.test/i/x'));
      expect(
        const OnlineActivation(
          cpfCnpj: '12345678909',
          birthDate: '1990-05-10',
          mobilePhone: '11987654321',
          incomeCents: 500000,
          postalCode: '17010000',
          address: 'Rua A',
          addressNumber: '1',
          complement: ' ',
          province: 'Centro',
        ).toJson(),
        {
          'cpf_cnpj': '12345678909',
          'birth_date': '1990-05-10',
          'mobile_phone': '11987654321',
          'income_cents': 500000,
          'postal_code': '17010000',
          'address': 'Rua A',
          'address_number': '1',
          'province': 'Centro',
        },
      );

      final adapter = _Adapter();
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);
      expect((await api.onlineAccount()).status, 'pending');
      await api.activateOnline(const OnlineActivation(
          cpfCnpj: '11222333000181',
          companyType: 'MEI',
          mobilePhone: '1',
          incomeCents: 1,
          postalCode: '1',
          address: 'a',
          addressNumber: '1',
          complement: 'sala 2',
          province: 'b'));
      expect((await api.charges('a1')).single.id, 'c1');
      expect((await api.createCharge('a1')).id, 'c2');
      await api.createCharge('a1', amountCents: 3000);
      await api.cancelCharge('c1');
      final c0 = adapter.calls;
      expect(c0[1].data, containsPair('company_type', 'MEI'));
      expect(c0[1].data, containsPair('complement', 'sala 2'));
      expect(c0[2].queryParameters, {'appointment_id': 'a1'});
      expect(c0[3].data, {'appointment_id': 'a1'});
      expect(c0[4].data, {'appointment_id': 'a1', 'amount_cents': 3000});
      expect('${c0[5].method} ${c0[5].path}', 'DELETE /finance/charges/c1');
    });
  });

  group('RF-F13 — OnlineAccountPage', () {
    testWidgets('indisponível, em análise, aprovado e recusado', (t) async {
      for (final (account, key) in [
        (
          const OnlineAccount(available: false, status: 'none'),
          'online-unavailable'
        ),
        (
          const OnlineAccount(available: true, status: 'pending'),
          'online-pending'
        ),
        (
          const OnlineAccount(available: true, status: 'approved'),
          'online-approved'
        ),
        (
          const OnlineAccount(available: true, status: 'rejected'),
          'online-rejected'
        ),
      ]) {
        final api = FakeOnlineApi()..account = account;
        await t.pumpWidget(_app(api, OnlineAccountPage(key: Key('p-$key'))));
        await t.pumpAndSettle();
        expect(find.byKey(Key(key)), findsOneWidget);
        if (key == 'online-pending') {
          await t.tap(find.byKey(const Key('online-refresh')));
          await t.pumpAndSettle();
          expect(find.byKey(Key(key)), findsOneWidget);
        }
      }
    });

    testWidgets('CPF: valida, envia e passa para em análise', (t) async {
      final api = FakeOnlineApi();
      await t.pumpWidget(_app(api, const OnlineAccountPage()));
      await t.pumpAndSettle();
      final submit = find.byKey(const Key('online-submit'));
      await t.scrollUntilVisible(submit, 200, scrollable: _formScroll);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.text('CPF ou CNPJ inválido'), findsOneWidget);
      expect(api.activations, isEmpty);

      Future<void> type(String key, String text) async {
        final f = find.byKey(Key(key));
        await t.scrollUntilVisible(f, 100, scrollable: _formScroll);
        await t.enterText(f, text);
      }

      await t.scrollUntilVisible(find.byKey(const Key('online-doc')), -400,
          scrollable: _formScroll);
      await type('online-doc', '123.456.789-09');
      await t.pump();
      await type('online-birth', '31/02/1990');
      await type('online-phone', '(11) 98765-4321');
      await type('online-income', '500000');
      await type('online-cep', '17010-000');
      await type('online-street', 'Rua A');
      await type('online-number', '10');
      await type('online-district', 'Centro');
      await t.scrollUntilVisible(submit, 200, scrollable: _formScroll);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.text('Data inválida'), findsOneWidget);
      await type('online-birth', '10/05/1990');
      await t.scrollUntilVisible(submit, 200, scrollable: _formScroll);
      await t.tap(submit);
      await t.pumpAndSettle();
      final a = api.activations.single;
      expect(a.toJson(), {
        'cpf_cnpj': '12345678909',
        'birth_date': '1990-05-10',
        'mobile_phone': '11987654321',
        'income_cents': 500000,
        'postal_code': '17010000',
        'address': 'Rua A',
        'address_number': '10',
        'province': 'Centro',
      });
      expect(find.byKey(const Key('online-pending')), findsOneWidget);
    });

    testWidgets('CNPJ pede o tipo de empresa; erro do Asaas aparece',
        (t) async {
      final api = FakeOnlineApi()..failWith = _apiError('CNPJ já cadastrado');
      await t.pumpWidget(_app(api, const OnlineAccountPage()));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('online-doc')), '11222333000181');
      await t.pump();
      expect(find.byKey(const Key('online-birth')), findsNothing);
      expect(find.byKey(const Key('online-company-type')), findsOneWidget);
      await t.tap(find.byKey(const Key('online-company-type')));
      await t.pumpAndSettle();
      await t.tap(find.text('Limitada (LTDA)').last);
      await t.pumpAndSettle();
      for (final (k, v) in [
        ('online-phone', '11987654321'),
        ('online-income', '100000'),
        ('online-cep', '17010000'),
        ('online-street', 'Rua B'),
        ('online-number', '5'),
        ('online-district', 'Centro'),
      ]) {
        final f = find.byKey(Key(k));
        await t.scrollUntilVisible(f, 100, scrollable: _formScroll);
        await t.enterText(f, v);
      }
      final submit = find.byKey(const Key('online-submit'));
      await t.scrollUntilVisible(submit, 200, scrollable: _formScroll);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.text('CNPJ já cadastrado'), findsOneWidget);
    });

    testWidgets('erro ao carregar e tentar de novo', (t) async {
      final api = _FailingAccountApi();
      await t.pumpWidget(_app(api, const OnlineAccountPage()));
      await t.pumpAndSettle();
      expect(find.text('Tentar de novo'), findsOneWidget);
      await t.tap(find.text('Tentar de novo'));
      await t.pumpAndSettle();
      expect(api.calls, 2);
    });
  });

  group('RF-F13 — Cobrar pelo link', () {
    testWidgets('botão só com recebimento online aprovado', (t) async {
      final api = FakeOnlineApi()
        ..account = const OnlineAccount(available: true, status: 'pending');
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PaymentSection(appointmentId: 'a1', api: api)))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('payment-charge-link')), findsNothing);

      api.account = const OnlineAccount(available: true, status: 'approved');
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PaymentSection(
                      key: const Key('b'), appointmentId: 'a1', api: api)))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('payment-charge-link')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('charge-sheet')), findsOneWidget);
    });

    testWidgets('gera o saldo, compartilha, copia e cancela', (t) async {
      final api = FakeOnlineApi();
      final sharer = FakeSharer();
      var changed = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnlineChargeSheet(
            appointmentId: 'a1',
            balanceCents: 7000,
            api: api,
            sharer: sharer,
            onChanged: () => changed++,
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Valor (vazio = R\$ 70,00)'), findsOneWidget);
      await t.tap(find.byKey(const Key('charge-create')));
      await t.pumpAndSettle();
      expect(api.created, [null]);
      expect(sharer.shared.single, contains('https://asaas.test/i/n1'));
      expect(changed, 1);
      expect(find.byKey(const Key('charge-create')), findsNothing);
      expect(find.text('Aguardando pagamento • vence 30/11'), findsOneWidget);

      await t.tap(find.byKey(const Key('charge-copy-n1')));
      await t.pumpAndSettle();
      expect(sharer.copied.single, 'https://asaas.test/i/n1');
      await t.tap(find.byKey(const Key('charge-share-n1')));
      expect(sharer.shared, hasLength(2));

      await t.tap(find.byKey(const Key('charge-cancel-n1')));
      await t.pumpAndSettle();
      expect(api.canceled, ['n1']);
      expect(find.text('Cancelada • vence 30/11'), findsOneWidget);
      expect(find.byKey(const Key('charge-create')), findsOneWidget);
    });

    testWidgets('cobrar só o sinal; valor igual ao saldo vai vazio; erro',
        (t) async {
      final api = FakeOnlineApi();
      final sharer = FakeSharer();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnlineChargeSheet(
              appointmentId: 'a1',
              balanceCents: 7000,
              api: api,
              sharer: sharer),
        ),
      ));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('charge-amount')), '3000');
      await t.tap(find.byKey(const Key('charge-create')));
      await t.pumpAndSettle();
      expect(api.created, [3000]);
      await t.enterText(find.byKey(const Key('charge-amount')), '4000');
      await t.tap(find.byKey(const Key('charge-create')));
      await t.pumpAndSettle();
      expect(api.created, [3000, null]);

      final api2 = FakeOnlineApi()
        ..failWith = _apiError('Cadastre o CPF do cliente para cobrar online');
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnlineChargeSheet(
              key: const Key('x'),
              appointmentId: 'a1',
              balanceCents: 7000,
              api: api2,
              sharer: sharer),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('charge-create')));
      await t.pumpAndSettle();
      expect(find.text('Cadastre o CPF do cliente para cobrar online'),
          findsOneWidget);
    });

    testWidgets('pago e sem saldo: sem botão de gerar', (t) async {
      final api = FakeOnlineApi()
        ..list = [Charge.fromJson(_chargeJson('p', status: 'paid'))];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              OnlineChargeSheet(appointmentId: 'a1', balanceCents: 0, api: api),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Paga • vence 30/11'), findsOneWidget);
      expect(find.byKey(const Key('charge-create')), findsNothing);
      expect(find.byKey(const Key('charge-cancel-p')), findsNothing);

      final empty = FakeOnlineApi();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnlineChargeSheet(
              key: const Key('e'),
              appointmentId: 'a1',
              balanceCents: 0,
              api: empty),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Este agendamento não tem saldo a cobrar.'),
          findsOneWidget);
    });
  });
}

class _FailingAccountApi extends FinanceApi {
  _FailingAccountApi() : super(Dio());
  int calls = 0;
  @override
  Future<OnlineAccount> onlineAccount() async {
    calls++;
    throw _apiError('Falha');
  }
}
