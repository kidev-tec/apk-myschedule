import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'online_charge_sheet.dart';
import 'payment_models.dart';
import 'payment_status_chip.dart';
import 'receipt_sheet.dart';
import 'receive_payment_sheet.dart';

/// Bloco "Pagamento" do detalhe do agendamento (TASK-F1-11, RF-F01/F02/F03):
/// valor, recebido, saldo e situação; Receber, Editar valor e estorno.
/// [onChanged] avisa quem abriu o painel para recarregar a agenda.
class PaymentSection extends StatefulWidget {
  final String appointmentId;
  final FinanceApi api;
  final VoidCallback? onChanged;

  const PaymentSection({
    super.key,
    required this.appointmentId,
    required this.api,
    this.onChanged,
  });

  @override
  State<PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<PaymentSection> {
  late Future<AppointmentFinance> _future = _load();

  /// Recebimento online aprovado? (F5) — falha na consulta = esconde o botão.
  late final Future<bool> _online = widget.api
      .onlineAccount()
      .then((a) => a.isApproved)
      .catchError((Object _) => false);

  Future<AppointmentFinance> _load() =>
      widget.api.appointment(widget.appointmentId);

  void _reload() {
    setState(() {
      _future = _load();
    });
    widget.onChanged?.call();
  }

  void _snack(String text) {
    // troca o aviso anterior em vez de enfileirar (ações seguidas)
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _receive(AppointmentFinance f) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReceivePaymentSheet(
        balanceCents: f.balanceCents,
        onSubmit: (p) =>
            widget.api.receive(p, appointmentId: widget.appointmentId),
      ),
    );
    if (ok == true && mounted) {
      _snack('Recebimento registrado');
      _reload();
    }
  }

  Future<void> _chargeLink(AppointmentFinance f) async {
    var changed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => OnlineChargeSheet(
        appointmentId: widget.appointmentId,
        balanceCents: f.balanceCents,
        api: widget.api,
        onChanged: () => changed = true,
      ),
    );
    if (changed && mounted) _reload();
  }

  Future<void> _editPrice(AppointmentFinance f) async {
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _PriceDialog(f),
    );
    if (cents == null || cents == f.priceCents || !mounted) return;
    try {
      await widget.api.updatePrice(widget.appointmentId, cents);
      if (!mounted) return;
      _snack('Valor atualizado');
      _reload();
    } catch (e) {
      if (mounted) _snack(humanError(e));
    }
  }

  Future<void> _void(Payment p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar recebimento?'),
        content: Text(
            '${formatCents(p.amountCents)} em ${p.method?.label ?? 'outro'} '
            'deixa de contar como recebido. O registro fica no histórico.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            key: const Key('void-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.api.voidPayment(p.id);
      if (!mounted) return;
      _snack('Recebimento estornado');
      _reload();
    } catch (e) {
      if (mounted) _snack(humanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<AppointmentFinance>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snap.hasError) {
          return Row(children: [
            Expanded(
              child: Text('Pagamento: ${humanError(snap.error!)}',
                  style: const TextStyle(color: AppColors.error)),
            ),
            TextButton(
                onPressed: () => setState(() {
                      _future = _load();
                    }),
                child: const Text('Tentar de novo')),
          ]);
        }
        final f = snap.data!;
        Widget line(String label, int cents, {bool bold = false}) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
                Text(formatCents(cents),
                    style: bold
                        ? theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700)
                        : theme.textTheme.bodyLarge),
              ]),
            );
        final dateFmt = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');
        return Column(
          key: const Key('payment-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Pagamento', style: theme.textTheme.titleSmall)),
              PaymentStatusChip(f.status),
            ]),
            const SizedBox(height: 8),
            line('Valor', f.priceCents),
            if (f.paidCents > 0) line('Recebido', f.paidCents),
            if (f.priceCents > 0)
              line('Falta receber', f.balanceCents, bold: true),
            for (final p in f.payments)
              ListTile(
                key: Key('payment-${p.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    p.isVoided ? Icons.undo : Icons.check_circle_outline,
                    size: 20,
                    color: p.isVoided ? AppColors.neutral : AppColors.success),
                title: Text(
                  '${formatCents(p.amountCents)} • ${p.method?.label ?? 'Outro'}'
                  '${p.installments > 1 ? ' ${p.installments}x' : ''}'
                  '${p.isDeposit ? ' (sinal)' : ''}',
                  style: p.isVoided
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null,
                ),
                subtitle: Text(p.isVoided
                    ? 'Estornado'
                    : [
                        dateFmt.format(p.occurredAt),
                        if (p.notes != null) p.notes!
                      ].join(' • ')),
                trailing: p.isVoided
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          key: Key('receipt-${p.id}'),
                          tooltip: 'Comprovante',
                          icon: const Icon(Icons.receipt_long_outlined),
                          onPressed: () =>
                              showReceipt(context, widget.api, p.id),
                        ),
                        IconButton(
                          key: Key('void-${p.id}'),
                          tooltip: 'Estornar',
                          icon: const Icon(Icons.undo),
                          onPressed: () => _void(p),
                        ),
                      ]),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (f.balanceCents > 0)
                FilledButton.icon(
                  key: const Key('payment-receive'),
                  onPressed: () => _receive(f),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Receber'),
                ),
              if (f.balanceCents > 0)
                FutureBuilder<bool>(
                  future: _online,
                  builder: (_, on) => on.data == true
                      ? OutlinedButton.icon(
                          key: const Key('payment-charge-link'),
                          onPressed: () => _chargeLink(f),
                          icon: const Icon(Icons.link),
                          label: const Text('Cobrar pelo link'),
                        )
                      : const SizedBox.shrink(),
                ),
              if (f.status != PaymentStatus.paid)
                OutlinedButton.icon(
                  key: const Key('payment-edit-price'),
                  onPressed: () => _editPrice(f),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Editar valor'),
                ),
            ]),
          ],
        );
      },
    );
  }
}

/// Diálogo do valor do atendimento; dono do próprio controller (descartado
/// só quando o diálogo sai da árvore, depois da animação de saída).
class _PriceDialog extends StatefulWidget {
  final AppointmentFinance finance;
  const _PriceDialog(this.finance);

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _ctrl =
      TextEditingController(text: centsToField(widget.finance.priceCents));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finance;
    return AlertDialog(
      title: const Text('Valor do atendimento'),
      content: TextField(
        key: const Key('price-field'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [CentsInputFormatter()],
        decoration: InputDecoration(
          prefixText: 'R\$ ',
          helperText: f.paidCents > 0
              ? 'Já recebido: ${formatCents(f.paidCents)}'
              : 'Desconto ou acréscimo só neste atendimento',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          key: const Key('price-save'),
          onPressed: () => Navigator.pop(context, parseMoney(_ctrl.text) ?? 0),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
