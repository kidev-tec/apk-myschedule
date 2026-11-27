/// Modelos do módulo de finanças (contrato da API: /v1/finance/*).
library;

enum PaymentMethod {
  pix('pix', 'Pix'),
  cash('cash', 'Dinheiro'),
  debit('debit', 'Débito'),
  credit('credit', 'Crédito'),
  paymentLink('payment_link', 'Link de pagamento'),
  other('other', 'Outro');

  const PaymentMethod(this.api, this.label);
  final String api;
  final String label;

  static PaymentMethod? fromApi(String? v) {
    for (final m in values) {
      if (m.api == v) return m;
    }
    return null;
  }
}

/// Situação da cobrança (derivada na API).
enum PaymentStatus {
  none('none', ''),
  open('open', 'Em aberto'),
  partial('partial', 'Parcial'),
  paid('paid', 'Pago');

  const PaymentStatus(this.api, this.label);
  final String api;
  final String label;

  static PaymentStatus fromApi(String? v) =>
      values.firstWhere((s) => s.api == v, orElse: () => none);
}

class Payment {
  final String id;
  final int amountCents;
  final PaymentMethod? method;
  final int installments;

  /// 'deposit' = sinal (pago antes do atendimento).
  final String kind;
  final DateTime occurredAt;
  final String? notes;
  final DateTime? voidedAt;

  const Payment({
    required this.id,
    required this.amountCents,
    required this.method,
    required this.installments,
    required this.kind,
    required this.occurredAt,
    this.notes,
    this.voidedAt,
  });

  bool get isVoided => voidedAt != null;
  bool get isDeposit => kind == 'deposit';

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: j['id'] as String,
        amountCents: j['amount_cents'] as int,
        method: PaymentMethod.fromApi(j['payment_method'] as String?),
        installments: (j['installments'] ?? 1) as int,
        kind: (j['kind'] ?? 'payment') as String,
        occurredAt: DateTime.parse(j['occurred_at'] as String).toLocal(),
        notes: j['notes'] as String?,
        voidedAt: j['voided_at'] == null
            ? null
            : DateTime.parse(j['voided_at'] as String).toLocal(),
      );
}

/// Valor, recebido, saldo e situação de um agendamento.
class AppointmentFinance {
  final int priceCents;
  final int paidCents;
  final int balanceCents;
  final PaymentStatus status;
  final List<Payment> payments;

  const AppointmentFinance({
    required this.priceCents,
    required this.paidCents,
    required this.balanceCents,
    required this.status,
    this.payments = const [],
  });

  factory AppointmentFinance.fromJson(Map<String, dynamic> j) =>
      AppointmentFinance(
        priceCents: (j['price_cents'] ?? 0) as int,
        paidCents: (j['paid_cents'] ?? 0) as int,
        balanceCents: (j['balance_cents'] ?? 0) as int,
        status: PaymentStatus.fromApi(j['payment_status'] as String?),
        payments: [
          for (final p in (j['payments'] as List? ?? const []))
            Payment.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// Dados de um novo recebimento.
class NewPayment {
  final int amountCents;
  final PaymentMethod method;
  final int installments;
  final String? notes;

  /// Cliente do recebimento avulso (opcional).
  final String? clientId;

  const NewPayment({
    required this.amountCents,
    required this.method,
    this.installments = 1,
    this.notes,
    this.clientId,
  });

  Map<String, dynamic> toJson({String? appointmentId, String? clientId}) => {
        if (appointmentId != null) 'appointment_id': appointmentId,
        if ((clientId ?? this.clientId) != null)
          'client_id': clientId ?? this.clientId,
        'amount_cents': amountCents,
        'payment_method': method.api,
        if (method == PaymentMethod.credit) 'installments': installments,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      };
}

/// Item de "A receber": agendamento com saldo em aberto.
class Receivable {
  final String id;
  final DateTime startsAt;
  final String status;
  final String clientName;
  final String serviceName;
  final int priceCents;
  final int paidCents;
  final int balanceCents;
  final PaymentStatus paymentStatus;

  const Receivable({
    required this.id,
    required this.startsAt,
    required this.status,
    required this.clientName,
    required this.serviceName,
    required this.priceCents,
    required this.paidCents,
    required this.balanceCents,
    required this.paymentStatus,
  });

  /// Já aconteceu (ou começou) e não foi pago por inteiro.
  bool isOverdue(DateTime now) => !startsAt.isAfter(now);

  factory Receivable.fromJson(Map<String, dynamic> j) => Receivable(
        id: j['id'] as String,
        startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
        status: (j['status'] ?? 'pending') as String,
        clientName: (j['client_name'] ?? '') as String,
        serviceName: (j['service_name'] ?? '') as String,
        priceCents: (j['price_cents'] ?? 0) as int,
        paidCents: (j['paid_cents'] ?? 0) as int,
        balanceCents: (j['balance_cents'] ?? 0) as int,
        paymentStatus: PaymentStatus.fromApi(j['payment_status'] as String?),
      );
}

/// Resposta de GET /finance/receivables.
class Receivables {
  final List<Receivable> items;
  final int totalOpenCents;
  final int overdueCents;
  final int upcomingCents;

  const Receivables({
    required this.items,
    required this.totalOpenCents,
    required this.overdueCents,
    required this.upcomingCents,
  });

  factory Receivables.fromJson(Map<String, dynamic> j) => Receivables(
        items: [
          for (final i in (j['items'] as List? ?? const []))
            Receivable.fromJson(i as Map<String, dynamic>),
        ],
        totalOpenCents: (j['total_open_cents'] ?? 0) as int,
        overdueCents: (j['overdue_cents'] ?? 0) as int,
        upcomingCents: (j['upcoming_cents'] ?? 0) as int,
      );
}

/// Cliente para os filtros/avulso (só o necessário).
class ClientOption {
  final String id;
  final String name;
  const ClientOption(this.id, this.name);
}
