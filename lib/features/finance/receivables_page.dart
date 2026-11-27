import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'payment_models.dart';
import 'payment_status_chip.dart';
import 'receive_payment_sheet.dart';

/// Período do filtro de "A receber".
enum ReceivablesPeriod {
  all('Até 60 dias'),
  overdue('Atrasados'),
  next7('Próximos 7 dias'),
  month('Este mês');

  const ReceivablesPeriod(this.label);
  final String label;

  /// Intervalo enviado à API (null = padrão da API).
  (DateTime?, DateTime?) range(DateTime now) => switch (this) {
        all => (null, null),
        overdue => (null, now),
        next7 => (now, now.add(const Duration(days: 7))),
        month => (
            DateTime(now.year, now.month),
            DateTime(now.year, now.month + 1)
                .subtract(const Duration(milliseconds: 1)),
          ),
      };
}

/// "A receber" (TASK-F1-12, RF-F04): agendamentos com saldo em aberto,
/// em Atrasados e Próximos, com totais; tocar recebe o saldo.
class ReceivablesPage extends ConsumerStatefulWidget {
  /// Relógio injetável nos testes.
  final DateTime Function() now;
  const ReceivablesPage({super.key, this.now = DateTime.now});

  @override
  ConsumerState<ReceivablesPage> createState() => _ReceivablesPageState();
}

class _ReceivablesPageState extends ConsumerState<ReceivablesPage> {
  ReceivablesPeriod _period = ReceivablesPeriod.all;
  String? _clientId;
  List<ClientOption> _clients = const [];
  late Future<Receivables> _future = _load();

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final list = await ref.read(financeApiProvider).clients();
      if (mounted) setState(() => _clients = list);
    } catch (_) {
      // filtro de cliente é opcional: sem a lista, a tela segue funcionando
    }
  }

  Future<Receivables> _load() {
    final (from, to) = _period.range(widget.now());
    return ref
        .read(financeApiProvider)
        .receivables(from: from, to: to, clientId: _clientId);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _receive(Receivable r) async {
    final api = ref.read(financeApiProvider);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReceivePaymentSheet(
        title: 'Receber de ${r.clientName}',
        balanceCents: r.balanceCents,
        onSubmit: (p) => api.receive(p, appointmentId: r.id),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Recebimento registrado')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('A receber'),
        actions: const [HomeAction()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _future.catchError((_) => _emptyReceivables);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ReceivablesPeriod.values)
                  ChoiceChip(
                    key: Key('period-${p.name}'),
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) {
                      _period = p;
                      _reload();
                    },
                  ),
              ],
            ),
            if (_clients.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('receivables-client'),
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Todos os clientes')),
                  for (final c in _clients)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  _clientId = v;
                  _reload();
                },
              ),
            ],
            const SizedBox(height: 16),
            FutureBuilder<Receivables>(
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
                        onPressed: _reload,
                        child: const Text('Tentar de novo')),
                  ]);
                }
                return _content(theme, snap.data!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, Receivables data) {
    Widget total(String label, int cents, {Color? color, Key? key}) => Expanded(
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

    final now = widget.now();
    final overdue = data.items.where((i) => i.isOverdue(now)).toList();
    final upcoming = data.items.where((i) => !i.isOverdue(now)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          total('Total em aberto', data.totalOpenCents,
              key: const Key('total-open')),
        ]),
        Row(children: [
          total('Atrasado', data.overdueCents,
              color: AppColors.error, key: const Key('total-overdue')),
          total('A receber', data.upcomingCents,
              key: const Key('total-upcoming')),
        ]),
        const SizedBox(height: 8),
        if (data.items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text('Nada a receber no período.',
                key: const Key('receivables-empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.neutral)),
          ),
        if (overdue.isNotEmpty) ...[
          _header(theme, 'Atrasados', overdue.length),
          for (final r in overdue) _tile(r),
        ],
        if (upcoming.isNotEmpty) ...[
          _header(theme, 'Próximos', upcoming.length),
          for (final r in upcoming) _tile(r),
        ],
      ],
    );
  }

  Widget _header(ThemeData theme, String title, int count) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text('$title ($count)', style: theme.textTheme.titleSmall),
      );

  static final _when = DateFormat("EEE, dd/MM 'às' HH:mm", 'pt_BR');

  Widget _tile(Receivable r) => Card(
        child: ListTile(
          key: Key('receivable-${r.id}'),
          title: Text(r.clientName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r.serviceName} • ${_when.format(r.startsAt)}'),
              const SizedBox(height: 4),
              PaymentStatusChip(r.paymentStatus),
            ],
          ),
          trailing: Text(formatCents(r.balanceCents),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          onTap: () => _receive(r),
        ),
      );
}

const _emptyReceivables = Receivables(
    items: [], totalOpenCents: 0, overdueCents: 0, upcomingCents: 0);
