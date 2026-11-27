import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'cashflow_models.dart';
import 'finance_api.dart';
import 'money.dart';

/// Fluxo de caixa projetado (TASK-F4-11, RF-F11): o que entra (agendamentos)
/// e o que sai (despesas a pagar) nos próximos dias, com saldo acumulado.
class CashflowPage extends ConsumerStatefulWidget {
  const CashflowPage({super.key});

  @override
  ConsumerState<CashflowPage> createState() => _CashflowPageState();
}

class _CashflowPageState extends ConsumerState<CashflowPage> {
  static const _windows = [7, 15, 30, 60];
  int _days = 30;
  late Future<Cashflow> _future = _load();

  static final _dayFmt = DateFormat("EEE, dd/MM", 'pt_BR');

  Future<Cashflow> _load() =>
      ref.read(financeApiProvider).cashflow(days: _days);

  void _set(int days) {
    setState(() {
      _days = days;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo projetado'),
        actions: const [HomeAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(spacing: 8, children: [
            for (final d in _windows)
              ChoiceChip(
                key: Key('cashflow-$d'),
                label: Text('$d dias'),
                selected: _days == d,
                onSelected: (_) => _set(d),
              ),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<Cashflow>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Column(children: [
                  Text(humanError(snap.error!),
                      style: const TextStyle(color: AppColors.error)),
                  TextButton(
                      onPressed: () => _set(_days),
                      child: const Text('Tentar de novo')),
                ]);
              }
              return _content(theme, snap.data!);
            },
          ),
        ],
      ),
    );
  }

  Widget _content(ThemeData theme, Cashflow f) {
    Widget total(String label, int cents, Key key, {Color? color}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(formatCents(cents),
                      key: key,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        );
    final active = f.days.where((d) => d.items.isNotEmpty).toList();
    final overdue = f.overdueInCents > 0 || f.overdueOutCents > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          total('A entrar', f.inflowCents, const Key('cashflow-in'),
              color: AppColors.success),
          total('A sair', f.outflowCents, const Key('cashflow-out'),
              color: AppColors.error),
          total('Saldo do período', f.netCents, const Key('cashflow-net'),
              color: f.netCents < 0 ? AppColors.error : null),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Previsão com base na agenda e nas despesas a pagar. '
            'Não inclui o dinheiro que você já tem em caixa ou na conta.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.neutral),
          ),
        ),
        if (overdue)
          Card(
            key: const Key('cashflow-overdue'),
            color: AppColors.error.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Atrasados (fora da previsão)',
                      style: theme.textTheme.titleSmall),
                  if (f.overdueInCents > 0)
                    ListTile(
                      key: const Key('overdue-in'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text('A receber: ${formatCents(f.overdueInCents)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/finance/receivables'),
                    ),
                  if (f.overdueOutCents > 0)
                    ListTile(
                      key: const Key('overdue-out'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          'Despesas vencidas: ${formatCents(f.overdueOutCents)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/finance/expenses'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text('Nada previsto para os próximos $_days dias.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.neutral)),
          ),
        for (final d in active)
          Card(
            key: Key(
                'cashflow-day-${d.date.toIso8601String().substring(0, 10)}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(_dayFmt.format(d.date),
                          style: theme.textTheme.titleSmall),
                    ),
                    Text('Saldo ${formatCents(d.balanceCents)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color:
                                d.balanceCents < 0 ? AppColors.error : null)),
                  ]),
                  const SizedBox(height: 4),
                  for (final i in d.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Icon(i.isIn ? Icons.south_west : Icons.north_east,
                            size: 16,
                            color:
                                i.isIn ? AppColors.success : AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(i.label)),
                        Text(
                            '${i.isIn ? '+' : '−'} ${formatCents(i.amountCents)}'),
                      ]),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
