import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'goal_card.dart';
import 'money.dart';
import 'report_models.dart';
import 'report_period.dart';

typedef _ReportData = (ReportSummary, List<ServiceRevenue>, Goal);

/// Relatórios (TASK-F3-11, RF-F07 a RF-F10): faturamento, despesas e
/// resultado por dia/semana/mês/período, gráfico diário, por forma, ticket
/// médio, por serviço e a meta do mês.
class ReportsPage extends ConsumerStatefulWidget {
  final DateTime Function() now;
  const ReportsPage({super.key, this.now = DateTime.now});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late ReportPeriod _period =
      ReportPeriod.of(ReportGranularity.month, widget.now());
  late Future<_ReportData> _future = _load();

  Future<_ReportData> _load() async {
    final api = ref.read(financeApiProvider);
    final p = _period;
    final results = await Future.wait([
      api.reportSummary(p.from, p.to),
      api.reportServices(p.from, p.to),
      api.goal(p.from),
    ]);
    return (
      results[0] as ReportSummary,
      results[1] as List<ServiceRevenue>,
      results[2] as Goal,
    );
  }

  void _set(ReportPeriod p) {
    setState(() {
      _period = p;
      _future = _load();
    });
  }

  Future<void> _pickRange() async {
    final now = widget.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
    );
    if (r != null && mounted) _set(ReportPeriod.custom(r.start, r.end));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = _period.granularity == ReportGranularity.custom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: const [HomeAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<ReportGranularity>(
            key: const Key('report-granularity'),
            segments: [
              for (final g in ReportGranularity.values)
                ButtonSegment(value: g, label: Text(g.label)),
            ],
            selected: {_period.granularity},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              final g = s.first;
              _set(ReportPeriod.of(g, _period.from));
              if (g == ReportGranularity.custom) _pickRange();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (!custom)
              IconButton(
                key: const Key('report-prev'),
                tooltip: 'Anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _set(_period.shift(-1)),
              ),
            Expanded(
              child: custom
                  ? TextButton.icon(
                      key: const Key('report-range'),
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range),
                      label: Text(_period.label),
                    )
                  : Text(_period.label,
                      key: const Key('report-label'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium),
            ),
            if (!custom)
              IconButton(
                key: const Key('report-next'),
                tooltip: 'Próximo',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _set(_period.shift(1)),
              ),
          ]),
          const SizedBox(height: 8),
          FutureBuilder<_ReportData>(
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
                      onPressed: () => _set(_period),
                      child: const Text('Tentar de novo')),
                ]);
              }
              final (s, services, goal) = snap.data!;
              return _content(theme, s, services, goal);
            },
          ),
        ],
      ),
    );
  }

  Widget _content(ThemeData theme, ReportSummary s,
      List<ServiceRevenue> services, Goal goal) {
    Widget card(String label, int cents, Key key, {Color? color}) => Expanded(
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
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        );
    Widget section(String title, List<Widget> children) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        );
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );

    final isMonth = _period.granularity == ReportGranularity.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          card('Recebido', s.revenueCents, const Key('report-revenue')),
          card('Despesas', s.expensesCents, const Key('report-expenses')),
        ]),
        Row(children: [
          card('Resultado', s.resultCents, const Key('report-result'),
              color: s.resultCents < 0 ? AppColors.error : AppColors.success),
          card('Em aberto', s.openCents, const Key('report-open')),
        ]),
        if (isMonth)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GoalCard(
                goal: goal,
                month: _period.from,
                api: ref.read(financeApiProvider),
                onChanged: () => _set(_period),
              ),
            ),
          ),
        if (s.series.length > 1)
          section('Recebido × despesas por dia', [
            _BarChart(series: s.series),
            const SizedBox(height: 4),
            Row(children: [
              _legend(AppColors.success, 'Recebido'),
              const SizedBox(width: 16),
              _legend(AppColors.error, 'Despesas'),
            ]),
          ]),
        if (s.byMethod.isNotEmpty)
          section('Recebido por forma de pagamento', [
            for (final e in s.byMethod.entries)
              line(e.key.label, formatCents(e.value)),
          ]),
        section('Atendimentos concluídos', [
          line('Quantidade', '${s.doneCount}'),
          line('Valor vendido', formatCents(s.soldCents)),
          line('Ticket médio por atendimento', formatCents(s.avgTicketCents)),
          line('Ticket médio por cliente', formatCents(s.avgPerClientCents)),
        ]),
        section('Por serviço', [
          if (services.isEmpty)
            const Text('Nenhum atendimento concluído no período.'),
          for (final sv in services)
            line('${sv.name}${sv.isKit ? ' (kit)' : ''} • ${sv.count}x',
                formatCents(sv.totalCents)),
        ]),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Barras diárias (recebido e despesas) desenhadas com widgets — sem
/// biblioteca de gráficos (dependência nova é decisão bloqueada).
class _BarChart extends StatelessWidget {
  final List<DayValues> series;
  const _BarChart({required this.series});

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final maxV = series.fold<int>(
        1, (m, d) => math.max(m, math.max(d.revenueCents, d.expensesCents)));
    double h(int v) => v == 0 ? 0 : math.max(2, _height * v / maxV);
    return SizedBox(
      key: const Key('report-chart'),
      height: _height + 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in series)
            Expanded(
              child: Tooltip(
                message: '${d.date.day}/${d.date.month}: '
                    '${formatCents(d.revenueCents)} recebido, '
                    '${formatCents(d.expensesCents)} em despesas',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: Container(
                                height: h(d.revenueCents),
                                color: AppColors.success)),
                        Expanded(
                            child: Container(
                                height: h(d.expensesCents),
                                color: AppColors.error)),
                      ],
                    ),
                    SizedBox(
                      height: 18,
                      child: series.length <= 7 || d.date.day % 5 == 1
                          ? FittedBox(
                              child: Text('${d.date.day}',
                                  style: Theme.of(context).textTheme.bodySmall))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
