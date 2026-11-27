import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'payment_models.dart';
import 'receive_payment_sheet.dart';

/// Área "Finanças" (TASK-F1-12). Fase 1: atalhos para "A receber" e
/// "Receber avulso"; o resumo do mês chega na Fase 3.
class FinanceHomePage extends ConsumerStatefulWidget {
  const FinanceHomePage({super.key});

  @override
  ConsumerState<FinanceHomePage> createState() => _FinanceHomePageState();
}

class _FinanceHomePageState extends ConsumerState<FinanceHomePage> {
  late Future<Receivables> _open = _loadOpen();

  Future<Receivables> _loadOpen() => ref.read(financeApiProvider).receivables();

  void _refresh() {
    setState(() {
      _open = _loadOpen();
    });
  }

  Future<void> _receiveWalkIn() async {
    final api = ref.read(financeApiProvider);
    List<ClientOption> clients = const [];
    try {
      clients = await api.clients();
    } catch (_) {
      // sem a lista, o avulso segue sem cliente
    }
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReceivePaymentSheet(
        title: 'Receber avulso',
        clients: clients,
        onSubmit: (p) => api.receive(p),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Recebimento registrado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        actions: const [HomeAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              key: const Key('finance-receivables'),
              leading: Icon(Icons.pending_actions, color: primary),
              title: const Text('A receber'),
              subtitle: FutureBuilder<Receivables>(
                future: _open,
                builder: (_, snap) => Text(
                  snap.hasData
                      ? 'Em aberto: ${formatCents(snap.data!.totalOpenCents)}'
                      : 'Atendimentos com saldo em aberto',
                  key: const Key('finance-open-total'),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push('/finance/receivables');
                if (mounted) _refresh();
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const Key('finance-walk-in'),
              leading: Icon(Icons.point_of_sale, color: primary),
              title: const Text('Receber avulso'),
              subtitle: const Text('Venda de produto ou valor sem agendamento'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _receiveWalkIn,
            ),
          ),
        ],
      ),
    );
  }
}
