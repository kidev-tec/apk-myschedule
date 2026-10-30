import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Atalho "Início" no topo das telas internas (Configurações → Serviços →
/// Novo kit…): volta direto pra agenda sem precisar ir tela por tela.
class HomeAction extends StatelessWidget {
  const HomeAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('go-home'),
        tooltip: 'Ir para a agenda',
        icon: const Icon(Icons.home_outlined),
        onPressed: () => context.go('/agenda'),
      );
}
