import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'cash_models.dart';
import 'finance_api.dart';
import 'goal_card.dart';
import 'money.dart';
import 'payment_models.dart';
import 'receive_payment_sheet.dart';
import 'report_models.dart';

/// Área "Finanças": resumo do mês com a meta (F3), A receber, Caixa do dia,
/// Despesas, Relatórios e Receber avulso.
class FinanceHomePage extends ConsumerStatefulWidget {
  /// Relógio injetável nos testes.
  final DateTime Function() now;
  const FinanceHomePage({super.key, this.now = DateTime.now});

  @override
  ConsumerState<FinanceHomePage> createState() => _FinanceHomePageState();
}

class _FinanceHomePageState extends ConsumerState<FinanceHomePage> {
  late Future<Receivables> _open = _loadOpen();
  late Future<CashSession?> _cash = ref.read(financeApiProvider).cashCurrent();
  late Future<(ReportSummary, Goal)> _monthData = _loadMonth();

  DateTime get _month => DateTime(widget.now().year, widget.now().month);

  Future<(ReportSummary, Goal)> _loadMonth() async {
    final api = ref.read(financeApiProvider);
    final m = _month;
    final summary = api.reportSummary(m, DateTime(m.year, m.month + 1, 0));
    return (await summary, await api.goal(m));
  }

  static final _time = DateFormat('HH:mm', 'pt_BR');

  Future<Receivables> _loadOpen() => ref.read(financeApiProvider).receivables();

  void _refresh() {
    setState(() {
      _open = _loadOpen();
      _cash = ref.read(financeApiProvider).cashCurrent();
      _monthData = _loadMonth();
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
          _monthCard(context),
          const SizedBox(height: 8),
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
              key: const Key('finance-reports'),
              leading: Icon(Icons.bar_chart, color: primary),
              title: const Text('Relatórios'),
              subtitle:
                  const Text('Faturamento, por serviço, ticket médio e metas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go('/finance/reports'),
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

  static final _monthFmt = DateFormat('MMMM', 'pt_BR');

  /// Resumo do mês: recebido, despesas, resultado e a meta.
  Widget _monthCard(BuildContext context) {
    final theme = Theme.of(context);
    final name = _monthFmt.format(_month);
    return Card(
      key: const Key('finance-month'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<(ReportSummary, Goal)>(
          future: _monthData,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return TextButton(
                  onPressed: _refresh,
                  child: const Text('Não consegui carregar o resumo. '
                      'Tentar de novo'));
            }
            final (s, goal) = snap.data!;
            Widget value(String label, int cents, Key key, {Color? color}) =>
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      Text(formatCents(cents),
                          key: key,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${name[0].toUpperCase()}${name.substring(1)}',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  value('Recebido', s.revenueCents, const Key('month-revenue')),
                  value(
                      'Despesas', s.expensesCents, const Key('month-expenses')),
                  value('Resultado', s.resultCents, const Key('month-result'),
                      color: s.resultCents < 0
                          ? AppColors.error
                          : AppColors.success),
                ]),
                const SizedBox(height: 12),
                GoalCard(
                  goal: goal,
                  month: _month,
                  api: ref.read(financeApiProvider),
                  onChanged: _refresh,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
