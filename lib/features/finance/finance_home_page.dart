import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'cash_models.dart';
import 'finance_api.dart';
import 'money.dart';
import 'payment_models.dart';
import 'receive_payment_sheet.dart';

/// Área "Finanças" (TASK-F1-12, F2): A receber, Caixa do dia, Despesas e
/// Receber avulso; o resumo do mês chega na Fase 3.
class FinanceHomePage extends ConsumerStatefulWidget {
  const FinanceHomePage({super.key});

  @override
  ConsumerState<FinanceHomePage> createState() => _FinanceHomePageState();
}

class _FinanceHomePageState extends ConsumerState<FinanceHomePage> {
  late Future<Receivables> _open = _loadOpen();
  late Future<CashSession?> _cash = ref.read(financeApiProvider).cashCurrent();
  static final _time = DateFormat('HH:mm', 'pt_BR');

  Future<Receivables> _loadOpen() => ref.read(financeApiProvider).receivables();

  void _refresh() {
    setState(() {
      _open = _loadOpen();
      _cash = ref.read(financeApiProvider).cashCurrent();
    });
  }

  /// Abre a tela e, ao voltar, atualiza os resumos.
  Future<void> _go(String path) async {
    await context.push(path);
    if (mounted) _refresh();
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
              onTap: () => _go('/finance/receivables'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const Key('finance-cash'),
              leading: Icon(Icons.point_of_sale, color: primary),
              title: const Text('Caixa do dia'),
              subtitle: FutureBuilder<CashSession?>(
                future: _cash,
                builder: (_, snap) => Text(
                  !snap.hasData
                      ? (snap.connectionState == ConnectionState.done
                          ? 'Fechado'
                          : 'Abrir, conferir e fechar o dinheiro do dia')
                      : 'Aberto às ${_time.format(snap.data!.openedAt)} • '
                          'esperado ${formatCents(snap.data!.expectedCents)}',
                  key: const Key('finance-cash-status'),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go('/finance/cash'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const Key('finance-expenses'),
              leading: Icon(Icons.receipt_long_outlined, color: primary),
              title: const Text('Despesas'),
              subtitle:
                  const Text('Materiais, aluguel, taxas e contas a pagar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go('/finance/expenses'),
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
