import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Marca "via {Estabelecimento}": o cliente marcou pelo link de um
/// estabelecimento em que o profissional atende (módulo agregador, API 0026).
/// O agendamento é do profissional; a marca só mostra de onde ele veio.
class ViaAggregatorBadge extends StatelessWidget {
  final String name;
  const ViaAggregatorBadge(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primaryOf(context);
    return Semantics(
      label: 'Agendado pelo link de $name',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'via $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
