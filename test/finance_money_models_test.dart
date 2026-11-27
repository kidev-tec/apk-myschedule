import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/features/finance/finance_api.dart';
import 'package:minha_agenda/features/finance/money.dart';
import 'package:minha_agenda/features/finance/payment_models.dart';

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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  group('RF-F01 — dinheiro em centavos', () {
    test('formatCents', () {
      expect(formatCents(123456), 'R\$ 1.234,56');
      expect(formatCents(5), 'R\$ 0,05');
      expect(formatCents(0), 'R\$ 0,00');
    });

    test('parseMoney', () {
      expect(parseMoney('1.234,56'), 123456);
      expect(parseMoney('R\$ 80'), 8000);
      expect(parseMoney('0,05'), 5);
      expect(parseMoney('0,5'), 50);
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('1,234'), isNull);
    });

    test('CentsInputFormatter preenche da direita', () {
      final f = CentsInputFormatter();
      String type(String digits) => f
          .formatEditUpdate(
              TextEditingValue.empty, TextEditingValue(text: digits))
          .text;
      expect(type('1'), '0,01');
      expect(type('125'), '1,25');
      expect(type('125000'), '1.250,00');
      expect(type(''), '');
      expect(type('a1b2'), '0,12');
      // acima de 9 dígitos mantém os 9 últimos
      expect(type('1234567890'), '2.345.678,90');
    });
  });

  group('modelos', () {
    test('PaymentMethod/PaymentStatus da API', () {
      expect(PaymentMethod.fromApi('payment_link'), PaymentMethod.paymentLink);
      expect(PaymentMethod.fromApi('boleto'), isNull);
      expect(PaymentStatus.fromApi('partial').label, 'Parcial');
      expect(PaymentStatus.fromApi(null), PaymentStatus.none);
    });

    test('AppointmentFinance.fromJson com recebimentos', () {
      final f = AppointmentFinance.fromJson({
        'price_cents': 10000,
        'paid_cents': 3000,
        'balance_cents': 7000,
        'payment_status': 'partial',
        'payments': [
          {
            'id': 'p1',
            'amount_cents': 3000,
            'payment_method': 'pix',
            'installments': 1,
            'kind': 'deposit',
            'occurred_at': '2026-11-27T12:00:00.000Z',
            'notes': 'sinal',
            'voided_at': null,
          },
          {
            'id': 'p2',
            'amount_cents': 500,
            'payment_method': 'cash',
            'occurred_at': '2026-11-27T13:00:00.000Z',
            'voided_at': '2026-11-27T14:00:00.000Z',
          },
        ],
      });
      expect(f.status, PaymentStatus.partial);
      expect(f.balanceCents, 7000);
      expect(f.payments.first.isDeposit, isTrue);
      expect(f.payments.first.isVoided, isFalse);
      expect(f.payments.last.isVoided, isTrue);
      expect(f.payments.last.kind, 'payment');
    });

    test('AppointmentFinance.fromJson vazio', () {
      final f = AppointmentFinance.fromJson({});
      expect(f.priceCents, 0);
      expect(f.status, PaymentStatus.none);
      expect(f.payments, isEmpty);
    });

    test('NewPayment.toJson: parcelas só no crédito, obs. aparada', () {
      expect(
        const NewPayment(
                amountCents: 100, method: PaymentMethod.pix, installments: 3)
            .toJson(appointmentId: 'a1'),
        {'appointment_id': 'a1', 'amount_cents': 100, 'payment_method': 'pix'},
      );
      expect(
        const NewPayment(
                amountCents: 100,
                method: PaymentMethod.credit,
                installments: 3,
                notes: '  oi  ')
            .toJson(clientId: 'c1'),
        {
          'client_id': 'c1',
          'amount_cents': 100,
          'payment_method': 'credit',
          'installments': 3,
          'notes': 'oi',
        },
      );
    });
  });

  group('FinanceApi — a receber e clientes', () {
    test('receivables envia filtros em UTC e parseia a resposta', () async {
      final adapter = _Adapter((o) => o.path == '/clients'
          ? _json([
              {'id': 'c1', 'name': 'Ana'},
              {'id': 'c2'},
            ])
          : _json({
              'items': [
                {
                  'id': 'a1',
                  'starts_at': '2026-11-20T12:00:00.000Z',
                  'status': 'done',
                  'client_name': 'Ana',
                  'service_name': 'Corte',
                  'price_cents': 10000,
                  'paid_cents': 2000,
                  'balance_cents': 8000,
                  'payment_status': 'partial',
                },
                {'id': 'a2', 'starts_at': '2026-12-01T12:00:00.000Z'},
              ],
              'total_open_cents': 8000,
              'overdue_cents': 8000,
              'upcoming_cents': 0,
            }));
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);

      final from = DateTime.utc(2026, 11, 1);
      final r = await api.receivables(
          from: from, to: DateTime.utc(2026, 11, 30), clientId: 'c1');
      expect(adapter.calls.single.queryParameters, {
        'from': '2026-11-01T00:00:00.000Z',
        'to': '2026-11-30T00:00:00.000Z',
        'client_id': 'c1',
      });
      expect(r.items.first.balanceCents, 8000);
      expect(r.items.first.paymentStatus, PaymentStatus.partial);
      expect(r.items.first.isOverdue(DateTime.utc(2026, 11, 27)), isTrue);
      expect(r.items.last.clientName, '');
      expect(r.items.last.paymentStatus, PaymentStatus.none);
      expect(r.totalOpenCents, 8000);
      expect(r.overdueCents, 8000);
      expect(r.upcomingCents, 0);

      await api.receivables();
      expect(adapter.calls.last.queryParameters, isEmpty);

      final clients = await api.clients();
      expect(clients.map((c) => '${c.id}:${c.name}'), ['c1:Ana', 'c2:']);
    });

    test('Receivables.fromJson vazio', () {
      final r = Receivables.fromJson({});
      expect(r.items, isEmpty);
      expect(r.totalOpenCents, 0);
    });
  });

  group('FinanceApi', () {
    test('chama as rotas certas', () async {
      final adapter = _Adapter((o) {
        if (o.method == 'GET') {
          return _json({'price_cents': 5000, 'payment_status': 'open'});
        }
        return _json({}, o.method == 'POST' ? 201 : 200);
      });
      final api = FinanceApi(Dio()..httpClientAdapter = adapter);

      final f = await api.appointment('a1');
      expect(f.priceCents, 5000);
      await api.receive(
          const NewPayment(amountCents: 100, method: PaymentMethod.cash),
          appointmentId: 'a1');
      await api.voidPayment('p1');
      await api.updatePrice('a1', 4000);

      expect(adapter.calls.map((c) => '${c.method} ${c.path}').toList(), [
        'GET /finance/appointments/a1',
        'POST /finance/payments',
        'POST /finance/transactions/p1/void',
        'PATCH /appointments/a1',
      ]);
      expect(adapter.calls[1].data, {
        'appointment_id': 'a1',
        'amount_cents': 100,
        'payment_method': 'cash'
      });
      expect(adapter.calls[3].data, {'price_cents': 4000});
    });
  });
}
