import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'expense_models.dart';
import 'expense_sheet.dart';
import 'finance_api.dart';
import 'money.dart';
import 'payment_models.dart';

/// Despesas (TASK-F2-11, RF-F06): mês a mês, com totais (pagas, a pagar,
/// vencidas), lançar, pagar e estornar.
class ExpensesPage extends ConsumerStatefulWidget {
  final DateTime Function() now;
  const ExpensesPage({super.key, this.now = DateTime.now});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

enum _Status { all, paid, pending }

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  late DateTime _month = DateTime(widget.now().year, widget.now().month);
  _Status _status = _Status.all;
  late Future<Expenses> _future = _load();

  static final _monthFmt = DateFormat('MMMM yyyy', 'pt_BR');
  static final _dayFmt = DateFormat('dd/MM', 'pt_BR');

  Future<Expenses> _load() => ref.read(financeApiProvider).expenses(
        from: _month,
        to: DateTime(_month.year, _month.month + 1)
            .subtract(const Duration(milliseconds: 1)),
        status: switch (_status) {
          _Status.all => null,
          _Status.paid => 'paid',
          _Status.pending => 'pending',
        },
      );

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final api = ref.read(financeApiProvider);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          ExpenseSheet(onSubmit: api.createExpense, now: widget.now),
    );
    if (ok == true && mounted) {
      _snack('Despesa registrada');
      _reload();
    }
  }

  Future<void> _pay(Expense e) async {
    final method = await showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Pagar ${formatCents(e.amountCents)}'),
        children: [
          for (final m in PaymentMethod.values)
            SimpleDialogOption(
              key: Key('pay-with-${m.api}'),
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m.label),
            ),
        ],
      ),
    );
    if (method == null || !mounted) return;
    try {
      await ref.read(financeApiProvider).payExpense(e.id, method);
      if (!mounted) return;
      _snack('Despesa paga');
      _reload();
    } catch (err) {
      if (mounted) _snack(humanError(err));
    }
  }

  Future<void> _void(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar despesa?'),
        content: Text('${e.title} — ${formatCents(e.amountCents)} deixa de '
            'contar. O registro fica no histórico.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            key: const Key('expense-void-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(financeApiProvider).voidPayment(e.id);
      if (!mounted) return;
      _snack('Despesa estornada');
      _reload();
    } catch (err) {
      if (mounted) _snack(humanError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _monthFmt.format(_month);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Despesas'),
        actions: const [HomeAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('expense-add'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Nova despesa'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(children: [
            IconButton(
              key: const Key('month-prev'),
              tooltip: 'Mês anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                _month = DateTime(_month.year, _month.month - 1);
                _reload();
              },
            ),
            Expanded(
              child: Text(
                '${title[0].toUpperCase()}${title.substring(1)}',
                key: const Key('month-title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const Key('month-next'),
              tooltip: 'Próximo mês',
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                _month = DateTime(_month.year, _month.month + 1);
                _reload();
              },
            ),
          ]),
          Wrap(spacing: 8, children: [
            for (final (s, label) in [
              (_Status.all, 'Todas'),
              (_Status.paid, 'Pagas'),
              (_Status.pending, 'A pagar'),
            ])
              ChoiceChip(
                key: Key('expense-status-${s.name}'),
                label: Text(label),
                selected: _status == s,
                onSelected: (_) {
                  _status = s;
                  _reload();
                },
              ),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<Expenses>(
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
                      onPressed: _reload, child: const Text('Tentar de novo')),
                ]);
              }
              return _content(theme, snap.data!);
            },
          ),
        ],
      ),
    );
  }

  Widget _content(ThemeData theme, Expenses data) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          total('Pagas', data.paidCents, const Key('expenses-paid')),
          total('A pagar', data.pendingCents, const Key('expenses-pending')),
          total('Vencidas', data.overdueCents, const Key('expenses-overdue'),
              color: data.overdueCents > 0 ? AppColors.error : null),
        ]),
        const SizedBox(height: 8),
        if (data.items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text('Nenhuma despesa neste mês.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.neutral)),
          ),
        for (final e in data.items) _tile(theme, e),
      ],
    );
  }

  Widget _tile(ThemeData theme, Expense e) {
    final String subtitle;
    if (e.isVoided) {
      subtitle = 'Estornada';
    } else if (e.paid) {
      subtitle = 'Pago em ${_dayFmt.format(e.occurredAt)}'
          '${e.method != null ? ' • ${e.method!.label}' : ''}';
    } else {
      subtitle = '${e.overdue ? 'Vencida' : 'Vence'} em '
          '${_dayFmt.format(e.dueAt ?? e.occurredAt)}';
    }
    return Card(
      child: ListTile(
        key: Key('expense-${e.id}'),
        leading: Icon(e.category.icon,
            color:
                e.isVoided ? AppColors.neutral : AppColors.primaryOf(context)),
        title: Text(e.title,
            style: e.isVoided
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null),
        subtitle: Text(subtitle,
            style: e.overdue ? const TextStyle(color: AppColors.error) : null),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(formatCents(e.amountCents),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (!e.isVoided)
            PopupMenuButton<String>(
              key: Key('expense-menu-${e.id}'),
              onSelected: (v) => v == 'pay' ? _pay(e) : _void(e),
              itemBuilder: (_) => [
                if (!e.paid)
                  const PopupMenuItem(value: 'pay', child: Text('Pagar')),
                const PopupMenuItem(value: 'void', child: Text('Estornar')),
              ],
            ),
        ]),
      ),
    );
  }
}
