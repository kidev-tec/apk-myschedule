import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Subtítulo de serviço/kit nas listas:
///   avulso: "60 min • R$ 80,00"
///   kit:    "Kit: Corte + Barba"
///           "50 min • de ~~R$ 70,00~~ por R$ 60,00"  (com desconto)
class ServiceSubtitle extends StatelessWidget {
  final int durationMin;
  final int priceCents;

  /// Itens do kit (vazio = serviço avulso).
  final List<String> kitItems;

  /// Soma dos preços dos itens; > preço = kit com desconto.
  final int kitFullCents;

  const ServiceSubtitle({
    super.key,
    required this.durationMin,
    required this.priceCents,
    this.kitItems = const [],
    this.kitFullCents = 0,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final discounted = kitItems.isNotEmpty && kitFullCents > priceCents;
    return Text.rich(TextSpan(children: [
      if (kitItems.isNotEmpty) TextSpan(text: 'Kit: ${kitItems.join(' + ')}\n'),
      TextSpan(text: '$durationMin min • '),
      if (discounted) ...[
        const TextSpan(text: 'de '),
        TextSpan(
            text: money.format(kitFullCents / 100),
            style: const TextStyle(decoration: TextDecoration.lineThrough)),
        const TextSpan(text: ' por '),
      ],
      TextSpan(
          text: money.format(priceCents / 100),
          style: discounted
              ? TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.green.shade700)
              : null),
    ]));
  }
}
