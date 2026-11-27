import 'payment_models.dart';

class CashflowItem {
  /// 'appointment' (entrada) | 'expense' (saída)
  final String kind;
  final String id;
  final String label;
  final int amountCents;
  const CashflowItem(this.kind, this.id, this.label, this.amountCents);

  bool get isIn => kind == 'appointment';
}

class CashflowDay {
  final DateTime date;
  final int inflowCents;
  final int outflowCents;
  final int balanceCents;
  final List<CashflowItem> items;
  const CashflowDay(this.date, this.inflowCents, this.outflowCents,
      this.balanceCents, this.items);
}

/// GET /finance/cashflow.
class Cashflow {
  final int inflowCents;
  final int outflowCents;
  final int netCents;
  final int overdueInCents;
  final int overdueOutCents;
  final List<CashflowDay> days;

  const Cashflow({
    required this.inflowCents,
    required this.outflowCents,
    required this.netCents,
    this.overdueInCents = 0,
    this.overdueOutCents = 0,
    this.days = const [],
  });

  factory Cashflow.fromJson(Map<String, dynamic> j) => Cashflow(
        inflowCents: (j['inflow_cents'] ?? 0) as int,
        outflowCents: (j['outflow_cents'] ?? 0) as int,
        netCents: (j['net_cents'] ?? 0) as int,
        overdueInCents: (j['overdue_in_cents'] ?? 0) as int,
        overdueOutCents: (j['overdue_out_cents'] ?? 0) as int,
        days: [
          for (final d in (j['days'] as List? ?? const []))
            CashflowDay(
              DateTime.parse((d as Map)['date'] as String),
              (d['inflow_cents'] ?? 0) as int,
              (d['outflow_cents'] ?? 0) as int,
              (d['balance_cents'] ?? 0) as int,
              [
                for (final i in (d['items'] as List? ?? const []))
                  CashflowItem(
                    (i as Map)['kind'] as String,
                    i['id'] as String,
                    (i['label'] ?? '') as String,
                    (i['amount_cents'] ?? 0) as int,
                  ),
              ],
            ),
        ],
      );
}

/// GET /finance/transactions/:id/receipt.
class Receipt {
  final int number;
  final int amountCents;
  final PaymentMethod? method;
  final int installments;
  final bool isDeposit;
  final DateTime occurredAt;
  final String? notes;
  final String businessName;
  final String? businessAddress;
  final String? logoUrl;
  final String? clientName;
  final String? serviceName;
  final DateTime? appointmentAt;
  final int? priceCents;
  final int? paidCents;
  final int? balanceCents;

  const Receipt({
    required this.number,
    required this.amountCents,
    required this.method,
    required this.occurredAt,
    required this.businessName,
    this.installments = 1,
    this.isDeposit = false,
    this.notes,
    this.businessAddress,
    this.logoUrl,
    this.clientName,
    this.serviceName,
    this.appointmentAt,
    this.priceCents,
    this.paidCents,
    this.balanceCents,
  });

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final p = j['payment'] as Map<String, dynamic>;
    final b = j['business'] as Map<String, dynamic>;
    final c = j['client'] as Map<String, dynamic>?;
    final a = j['appointment'] as Map<String, dynamic>?;
    return Receipt(
      number: j['number'] as int,
      amountCents: p['amount_cents'] as int,
      method: PaymentMethod.fromApi(p['payment_method'] as String?),
      installments: (p['installments'] ?? 1) as int,
      isDeposit: p['kind'] == 'deposit',
      occurredAt: DateTime.parse(p['occurred_at'] as String).toLocal(),
      notes: p['notes'] as String?,
      businessName: (b['name'] ?? '') as String,
      businessAddress: b['address'] as String?,
      logoUrl: b['logo_url'] as String?,
      clientName: c?['name'] as String?,
      serviceName: a?['service_name'] as String?,
      appointmentAt:
          a == null ? null : DateTime.parse(a['starts_at'] as String).toLocal(),
      priceCents: a?['price_cents'] as int?,
      paidCents: a?['paid_cents'] as int?,
      balanceCents: a?['balance_cents'] as int?,
    );
  }
}
