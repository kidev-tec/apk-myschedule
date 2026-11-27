import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'online_models.dart';

/// Envio do link (injetável nos testes).
class LinkSharer {
  const LinkSharer();
  Future<void> share(String text) =>
      SharePlus.instance.share(ShareParams(text: text));
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Mensagem enviada ao cliente com o link de pagamento.
String chargeMessage(Charge c) =>
    'Olá! Segue o link para pagamento de ${formatCents(c.amountCents)} '
    '(Pix, cartão ou boleto), com vencimento em '
    '${DateFormat('dd/MM', 'pt_BR').format(c.dueDate)}:\n${c.invoiceUrl ?? ''}';

/// Cobrar pelo link (F5-12, RF-F13): gera a cobrança no Asaas, compartilha o
/// link e acompanha a situação; o pagamento entra sozinho pelo webhook.
class OnlineChargeSheet extends StatefulWidget {
  final String appointmentId;
  final int balanceCents;
  final FinanceApi api;
  final LinkSharer sharer;
  final VoidCallback? onChanged;

  const OnlineChargeSheet({
    super.key,
    required this.appointmentId,
    required this.balanceCents,
    required this.api,
    this.sharer = const LinkSharer(),
    this.onChanged,
  });

  @override
  State<OnlineChargeSheet> createState() => _OnlineChargeSheetState();
}

class _OnlineChargeSheetState extends State<OnlineChargeSheet> {
  late Future<List<Charge>> _future = _load();
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<List<Charge>> _load() => widget.api.charges(widget.appointmentId);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
    widget.onChanged?.call();
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) _reload();
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(int openCents) => _run(() async {
        final typed = parseMoney(_amount.text);
        final c = await widget.api.createCharge(widget.appointmentId,
            amountCents: typed == null || typed == openCents ? null : typed);
        _amount.clear();
        await widget.sharer.share(chargeMessage(c));
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('charge-sheet'),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: FutureBuilder<List<Charge>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Text(humanError(snap.error!),
                style: const TextStyle(color: AppColors.error));
          }
          final list = snap.data!;
          final openSum = list
              .where((c) => c.isOpen)
              .fold<int>(0, (s, c) => s + c.amountCents);
          final toCharge = widget.balanceCents - openSum;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cobrar pelo link', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                    'O cliente escolhe Pix, cartão ou boleto. Quando ele '
                    'pagar, o recebimento entra sozinho no Agenva.'),
                const SizedBox(height: 12),
                for (final c in list) _chargeTile(c),
                if (toCharge > 0) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('charge-amount'),
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CentsInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Valor (vazio = ${formatCents(toCharge)})',
                      prefixText: 'R\$ ',
                      helperText:
                          'Para cobrar só o sinal, digite um valor menor',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          key: const Key('charge-error'),
                          style: const TextStyle(color: AppColors.error)),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('charge-create'),
                      onPressed: _busy ? null : () => _create(toCharge),
                      icon: const Icon(Icons.link),
                      label: const Text('Gerar e enviar link'),
                    ),
                  ),
                ] else if (list.isEmpty)
                  const Text('Este agendamento não tem saldo a cobrar.'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chargeTile(Charge c) {
    final color = switch (c.status) {
      'paid' => AppColors.success,
      'overdue' => AppColors.error,
      _ => null,
    };
    return Card(
      child: ListTile(
        key: Key('charge-${c.id}'),
        title: Text(formatCents(c.amountCents)),
        subtitle: Text(
          '${c.statusLabel} • vence ${DateFormat('dd/MM', 'pt_BR').format(c.dueDate)}',
          style: color == null ? null : TextStyle(color: color),
        ),
        trailing: !c.isOpen
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: Key('charge-share-${c.id}'),
                  tooltip: 'Enviar link',
                  icon: const Icon(Icons.share),
                  onPressed: () => widget.sharer.share(chargeMessage(c)),
                ),
                IconButton(
                  key: Key('charge-copy-${c.id}'),
                  tooltip: 'Copiar link',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await widget.sharer.copy(c.invoiceUrl ?? '');
                    if (mounted) _snack('Link copiado');
                  },
                ),
                IconButton(
                  key: Key('charge-cancel-${c.id}'),
                  tooltip: 'Cancelar cobrança',
                  icon: const Icon(Icons.close),
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.api.cancelCharge(c.id)),
                ),
              ]),
      ),
    );
  }
}
