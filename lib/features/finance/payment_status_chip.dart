import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'payment_models.dart';

/// Situação do pagamento no card da agenda: Em aberto / Parcial / Pago.
/// Sem valor (bloqueio, serviço gratuito) não mostra nada.
class PaymentStatusChip extends StatelessWidget {
  final PaymentStatus status;
  const PaymentStatusChip(this.status, {super.key});

  static const _amber = Color(0xFFB26A00);

  @override
  Widget build(BuildContext context) {
    if (status == PaymentStatus.none) return const SizedBox.shrink();
    final (IconData icon, Color color) = switch (status) {
      PaymentStatus.paid => (Icons.check_circle, AppColors.success),
      PaymentStatus.partial => (Icons.timelapse, _amber),
      _ => (Icons.payments_outlined, AppColors.midOf(context)),
    };
    return Semantics(
      label: 'Pagamento: ${status.label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
