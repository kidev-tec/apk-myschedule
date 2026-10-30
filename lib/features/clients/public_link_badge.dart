import 'package:flutter/material.dart';

/// Sinal de "cadastro pelo link": só o ícone (🌐 laranja). Tocar mostra a
/// explicação — o cliente se cadastrou sozinho ao agendar pelo link (só nome
/// e celular), dá pra pedir o cadastro completo depois.
class PublicLinkBadge extends StatelessWidget {
  const PublicLinkBadge({super.key});

  static const message = 'Cadastro feito pelo cliente no agendamento online '
      '(só nome e celular). Peça para ele completar o cadastro.';

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Tooltip(
      key: const Key('client-public-link-badge'),
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        label: 'Cadastro pelo link',
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.public, size: 16, color: color),
        ),
      ),
    );
  }
}
