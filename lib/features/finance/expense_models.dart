import 'package:flutter/material.dart';

import 'payment_models.dart';

/// Categorias fixas de despesa (decisão D5). "Outros" exige descrição.
enum ExpenseCategory {
  materiais('materiais', 'Materiais', Icons.inventory_2_outlined),
  aluguel('aluguel', 'Aluguel', Icons.home_work_outlined),
  taxas('taxas', 'Taxas', Icons.receipt_long_outlined),
  energiaAgua('energia_agua', 'Energia e água', Icons.bolt_outlined),
  marketing('marketing', 'Marketing', Icons.campaign_outlined),
  outros('outros', 'Outros', Icons.more_horiz);

  const ExpenseCategory(this.api, this.label, this.icon);
  final String api;
  final String label;
  final IconData icon;

  static ExpenseCategory fromApi(String? v) =>
      values.firstWhere((c) => c.api == v, orElse: () => outros);
}

class Expense {
  final String id;
  final int amountCents;
  final ExpenseCategory category;
  final PaymentMethod? method;
  final bool paid;
  final DateTime? dueAt;
  final DateTime occurredAt;
  final String? notes;
  final DateTime? voidedAt;
  final bool overdue;

  const Expense({
    required this.id,
    required this.amountCents,
    required this.category,
    required this.method,
    required this.paid,
    required this.occurredAt,
    this.dueAt,
    this.notes,
    this.voidedAt,
    this.overdue = false,
  });

  bool get isVoided => voidedAt != null;

  /// Título na lista: a descrição ou o nome da categoria.
  String get title =>
      (notes != null && notes!.isNotEmpty) ? notes! : category.label;

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        amountCents: j['amount_cents'] as int,
        category: ExpenseCategory.fromApi(j['category'] as String?),
        method: PaymentMethod.fromApi(j['payment_method'] as String?),
        paid: (j['paid'] ?? true) as bool,
        dueAt: _date(j['due_at']),
        occurredAt: _date(j['occurred_at'])!,
        notes: j['notes'] as String?,
        voidedAt: _date(j['voided_at']),
        overdue: (j['overdue'] ?? false) as bool,
      );
}

class Expenses {
  final List<Expense> items;
  final int paidCents;
  final int pendingCents;
  final int overdueCents;

  const Expenses({
    required this.items,
    required this.paidCents,
    required this.pendingCents,
    required this.overdueCents,
  });

  factory Expenses.fromJson(Map<String, dynamic> j) => Expenses(
        items: [
          for (final e in (j['items'] as List? ?? const []))
            Expense.fromJson(e as Map<String, dynamic>),
        ],
        paidCents: (j['paid_cents'] ?? 0) as int,
        pendingCents: (j['pending_cents'] ?? 0) as int,
        overdueCents: (j['overdue_cents'] ?? 0) as int,
      );
}

/// Nova despesa: paga (com forma) ou a pagar (com vencimento em [date]).
class NewExpense {
  final int amountCents;
  final ExpenseCategory category;
  final bool paid;
  final DateTime? date;
  final PaymentMethod? method;
  final String? notes;

  const NewExpense({
    required this.amountCents,
    required this.category,
    this.paid = true,
    this.date,
    this.method,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'amount_cents': amountCents,
        'category': category.api,
        'paid': paid,
        if (date != null) 'date': date!.toUtc().toIso8601String(),
        if (paid && method != null) 'payment_method': method!.api,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      };
}
