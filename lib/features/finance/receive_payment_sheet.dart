import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'money.dart';
import 'payment_models.dart';

/// Painel "Receber": valor (padrão = saldo), forma, parcelas (só crédito)
/// e observação. Valida valor ≤ saldo ANTES de enviar. Fecha com `true`
/// quando o recebimento foi registrado.
///
/// [balanceCents] null = recebimento avulso (sem limite de saldo).
class ReceivePaymentSheet extends StatefulWidget {
  final int? balanceCents;
  final String title;
  final Future<void> Function(NewPayment payment) onSubmit;

  const ReceivePaymentSheet({
    super.key,
    required this.onSubmit,
    this.balanceCents,
    this.title = 'Receber',
  });

  @override
  State<ReceivePaymentSheet> createState() => _ReceivePaymentSheetState();
}

class _ReceivePaymentSheetState extends State<ReceivePaymentSheet> {
  late final _amount = TextEditingController(
      text: widget.balanceCents == null || widget.balanceCents == 0
          ? ''
          : centsToField(widget.balanceCents!));
  final _notes = TextEditingController();
  PaymentMethod _method = PaymentMethod.pix;
  int _installments = 1;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? get _cents => parseMoney(_amount.text);

  String? get _amountProblem {
    final c = _cents;
    if (c == null || c <= 0) return null; // vazio: só desabilita
    final b = widget.balanceCents;
    if (b != null && c > b) {
      return 'Maior que o saldo restante (${formatCents(b)})';
    }
    return null;
  }

  bool get _canSave => !_saving && (_cents ?? 0) > 0 && _amountProblem == null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(NewPayment(
        amountCents: _cents!,
        method: _method,
        installments: _method == PaymentMethod.credit ? _installments : 1,
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
    final b = widget.balanceCents;
    return Padding(
      key: const Key('receive-sheet'),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            if (b != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Saldo restante: ${formatCents(b)}',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('receive-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [CentsInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                errorText: _amountProblem,
              ),
            ),
            const SizedBox(height: 16),
            Text('Forma de pagamento', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    key: Key('method-${m.api}'),
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            if (_method == PaymentMethod.credit) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: const Key('receive-installments'),
                initialValue: _installments,
                decoration: const InputDecoration(labelText: 'Parcelas'),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(
                        value: i, child: Text(i == 1 ? 'À vista' : '${i}x')),
                ],
                onChanged: (v) => setState(() => _installments = v ?? 1),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('receive-notes'),
              controller: _notes,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Observação (opcional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    key: const Key('receive-error'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('receive-save'),
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Registrar recebimento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
