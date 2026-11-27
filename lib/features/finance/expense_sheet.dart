import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'expense_models.dart';
import 'money.dart';
import 'payment_models.dart';

/// Painel "Nova despesa" (TASK-F2-11, RF-F06): valor, categoria e
/// "Já paguei" (forma + data) ou a pagar (vencimento). Fecha com `true`.
class ExpenseSheet extends StatefulWidget {
  final Future<void> Function(NewExpense expense) onSubmit;

  /// Relógio injetável nos testes.
  final DateTime Function() now;

  const ExpenseSheet(
      {super.key, required this.onSubmit, this.now = DateTime.now});

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.materiais;
  bool _paid = true;
  PaymentMethod _method = PaymentMethod.pix;
  late DateTime _paidOn = _day(widget.now());
  DateTime? _dueOn;
  bool _saving = false;
  String? _error;

  static final _fmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  /// Meio-dia local: a data não "anda" um dia ao virar UTC.
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _notes.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _cents => parseMoney(_amount.text) ?? 0;

  bool get _needsNotes =>
      _category == ExpenseCategory.outros && _notes.text.trim().isEmpty;

  bool get _canSave =>
      !_saving && _cents > 0 && !_needsNotes && (_paid || _dueOn != null);

  Future<void> _pickDate({required bool due}) async {
    final now = widget.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? (_dueOn ?? now) : _paidOn,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (due) {
        _dueOn = _day(picked);
      } else {
        _paidOn = _day(picked);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(NewExpense(
        amountCents: _cents,
        category: _category,
        paid: _paid,
        date: _paid ? _paidOn : _dueOn,
        method: _paid ? _method : null,
        notes: _notes.text,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = humanError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('expense-sheet'),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nova despesa', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('expense-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [CentsInputFormatter()],
              decoration:
                  const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 16),
            Text('Categoria', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in ExpenseCategory.values)
                ChoiceChip(
                  key: Key('category-${c.api}'),
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const Key('expense-notes'),
              controller: _notes,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _category == ExpenseCategory.outros
                    ? 'Descrição (obrigatória)'
                    : 'Descrição (opcional)',
              ),
            ),
            SwitchListTile(
              key: const Key('expense-paid'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Já paguei'),
              subtitle: Text(_paid
                  ? 'Sai do caixa se for em dinheiro e o caixa estiver aberto'
                  : 'Fica em "a pagar" até a data de vencimento'),
              value: _paid,
              onChanged: (v) => setState(() => _paid = v),
            ),
            if (_paid) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    key: Key('expense-method-${m.api}'),
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ]),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('expense-paid-on'),
                onPressed: () => _pickDate(due: false),
                icon: const Icon(Icons.event),
                label: Text('Pago em ${_fmt.format(_paidOn)}'),
              ),
            ] else
              TextButton.icon(
                key: const Key('expense-due-on'),
                onPressed: () => _pickDate(due: true),
                icon: const Icon(Icons.event),
                label: Text(_dueOn == null
                    ? 'Escolher vencimento'
                    : 'Vence em ${_fmt.format(_dueOn!)}'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('expense-save'),
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar despesa'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
