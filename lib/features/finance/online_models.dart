/// Recebimento online (Asaas, subconta do negócio) — F5.
library;

/// none | pending | approved | rejected
class OnlineAccount {
  final bool available;
  final String status;
  const OnlineAccount({required this.available, required this.status});

  bool get isApproved => available && status == 'approved';

  factory OnlineAccount.fromJson(Map<String, dynamic> j) => OnlineAccount(
        available: (j['available'] ?? false) as bool,
        status: (j['status'] ?? 'none') as String,
      );
}

/// Cobrança por link.
class Charge {
  final String id;
  final int amountCents;

  /// pending | paid | overdue | canceled | refunded
  final String status;
  final String? invoiceUrl;
  final DateTime dueDate;

  const Charge({
    required this.id,
    required this.amountCents,
    required this.status,
    required this.dueDate,
    this.invoiceUrl,
  });

  bool get isOpen => status == 'pending' || status == 'overdue';

  String get statusLabel => switch (status) {
        'paid' => 'Paga',
        'overdue' => 'Vencida',
        'canceled' => 'Cancelada',
        'refunded' => 'Estornada',
        _ => 'Aguardando pagamento',
      };

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'] as String,
        amountCents: j['amount_cents'] as int,
        status: (j['status'] ?? 'pending') as String,
        invoiceUrl: j['invoice_url'] as String?,
        dueDate: DateTime.parse(j['due_date'] as String),
      );
}

/// Dados para ativar o recebimento online.
class OnlineActivation {
  final String cpfCnpj;
  final String? birthDate;
  final String? companyType;
  final String mobilePhone;
  final int incomeCents;
  final String postalCode;
  final String address;
  final String addressNumber;
  final String? complement;
  final String province;

  const OnlineActivation({
    required this.cpfCnpj,
    required this.mobilePhone,
    required this.incomeCents,
    required this.postalCode,
    required this.address,
    required this.addressNumber,
    required this.province,
    this.birthDate,
    this.companyType,
    this.complement,
  });

  Map<String, dynamic> toJson() => {
        'cpf_cnpj': cpfCnpj,
        if (birthDate != null) 'birth_date': birthDate,
        if (companyType != null) 'company_type': companyType,
        'mobile_phone': mobilePhone,
        'income_cents': incomeCents,
        'postal_code': postalCode,
        'address': address,
        'address_number': addressNumber,
        if (complement != null && complement!.trim().isNotEmpty)
          'complement': complement!.trim(),
        'province': province,
      };
}
