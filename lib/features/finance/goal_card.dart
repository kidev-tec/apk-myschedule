import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'report_models.dart';

/// Meta do mês (TASK-F3-11, RF-F10): barra de progresso, quanto falta e
/// quanto precisa por dia; toque define/altera/remove.
class GoalCard extends StatelessWidget {
  final Goal goal;
  final DateTime month;
  final FinanceApi api;

  /// Avisa quem mostra o card para recarregar depois de mudar a meta.
  final VoidCallback onChanged;

  const GoalCard({
    super.key,
    required this.goal,
    required this.month,
    required this.api,
    required this.onChanged,
  });

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<_GoalResult>(
      context: context,
      builder: (_) => _GoalDialog(current: goal.targetCents),
    );
    if (result == null || !context.mounted) return;
    try {
      if (result.remove) {
        await api.deleteGoal(month);
      } else {
        await api.setGoal(month, result.cents);
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(humanError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!goal.hasTarget) {
      return OutlinedButton.icon(
        key: const Key('goal-define'),
        onPressed: () => _edit(context),
        icon: const Icon(Icons.flag_outlined),
        label: const Text('Definir meta do mês'),
      );
    }
    final pct = goal.percent ?? 0;
    final done = pct >= 100;
    return InkWell(
      key: const Key('goal-card'),
      onTap: () => _edit(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.flag, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Meta ${formatCents(goal.targetCents!)}',
                  style: theme.textTheme.titleSmall),
            ),
            Text('$pct%',
                key: const Key('goal-percent'),
                style: theme.textTheme.titleSmall?.copyWith(
                    color: done ? AppColors.success : null,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: done ? AppColors.success : AppColors.primaryOf(context),
              backgroundColor: AppColors.softOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? 'Meta batida! 🎉'
                : 'Faltam ${formatCents(goal.remainingCents)}'
                    '${goal.daysLeft > 0 ? ' • ${formatCents(goal.neededPerDayCents)} por dia '
                        '(${goal.daysLeft} ${goal.daysLeft == 1 ? 'dia' : 'dias'})' : ''}',
            key: const Key('goal-remaining'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GoalResult {
  final int cents;
  final bool remove;
  const _GoalResult(this.cents, {this.remove = false});
}

class _GoalDialog extends StatefulWidget {
  final int? current;
  const _GoalDialog({this.current});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _ctrl = TextEditingController(
      text: widget.current == null ? '' : centsToField(widget.current!));

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cents = parseMoney(_ctrl.text) ?? 0;
    return AlertDialog(
      title: const Text('Meta do mês'),
      content: TextField(
        key: const Key('goal-field'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [CentsInputFormatter()],
        decoration: const InputDecoration(
          labelText: 'Quanto quer faturar no mês?',
          prefixText: 'R\$ ',
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            key: const Key('goal-remove'),
            onPressed: () =>
                Navigator.pop(context, const _GoalResult(0, remove: true)),
            child: const Text('Remover meta'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          key: const Key('goal-save'),
          onPressed: cents > 0
              ? () => Navigator.pop(context, _GoalResult(cents))
              : null,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
