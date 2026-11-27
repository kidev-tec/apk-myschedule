import 'payment_models.dart';

/// Movimento do caixa (recebimento, despesa, suprimento ou sangria).
class CashMovement {
  final String id;

  /// payment | deposit | expense | cash_in | cash_out
  final String kind;

  /// income | expense
  final String type;
  final int amountCents;
  final PaymentMethod? method;
  final String? notes;
  final DateTime occurredAt;
  final DateTime? voidedAt;

  const CashMovement({
    required this.id,
    required this.kind,
    required this.type,
    required this.amountCents,
    required this.occurredAt,
    this.method,
    this.notes,
    this.voidedAt,
  });

  bool get isIn => type == 'income';
  bool get isVoided => voidedAt != null;

  String get label => switch (kind) {
        'cash_in' => 'Suprimento',
        'cash_out' => 'Sangria',
        'expense' => 'Despesa',
        'deposit' => 'Sinal',
        _ => 'Recebimento',
      };

  factory CashMovement.fromJson(Map<String, dynamic> j) => CashMovement(
        id: j['id'] as String,
        kind: (j['kind'] ?? 'payment') as String,
        type: (j['type'] ?? 'income') as String,
        amountCents: j['amount_cents'] as int,
        method: PaymentMethod.fromApi(j['payment_method'] as String?),
        notes: j['notes'] as String?,
        occurredAt: DateTime.parse(j['occurred_at'] as String).toLocal(),
        voidedAt: j['voided_at'] == null
            ? null
            : DateTime.parse(j['voided_at'] as String).toLocal(),
      );
}

class CashSession {
  final String id;
  final DateTime openedAt;
  final int openingCents;
  final int cashInCents;
  final int cashOutCents;
  final int expectedCents;

  /// Recebido por forma (informativo): {'pix': 8000, 'cash': 10000}.
  final Map<PaymentMethod, int> byMethod;
  final List<CashMovement> movements;
  final DateTime? closedAt;
  final int? countedCents;
  final int? differenceCents;

  const CashSession({
    required this.id,
    required this.openedAt,
    required this.openingCents,
    required this.cashInCents,
    required this.cashOutCents,
    required this.expectedCents,
    this.byMethod = const {},
    this.movements = const [],
    this.closedAt,
    this.countedCents,
    this.differenceCents,
  });

  bool get isOpen => closedAt == null;

  factory CashSession.fromJson(Map<String, dynamic> j) => CashSession(
        id: j['id'] as String,
        openedAt: DateTime.parse(j['opened_at'] as String).toLocal(),
        openingCents: (j['opening_cents'] ?? 0) as int,
        cashInCents: (j['cash_in_cents'] ?? 0) as int,
        cashOutCents: (j['cash_out_cents'] ?? 0) as int,
        expectedCents: (j['expected_cents'] ?? 0) as int,
        byMethod: {
          for (final e in ((j['by_method'] as Map?) ?? const {}).entries)
            if (PaymentMethod.fromApi(e.key as String) != null)
              PaymentMethod.fromApi(e.key as String)!: e.value as int,
        },
        movements: [
          for (final m in (j['movements'] as List? ?? const []))
            CashMovement.fromJson(m as Map<String, dynamic>),
        ],
        closedAt: j['closed_at'] == null
            ? null
            : DateTime.parse(j['closed_at'] as String).toLocal(),
        countedCents: j['counted_cents'] as int?,
        differenceCents: j['difference_cents'] as int?,
      );
}
