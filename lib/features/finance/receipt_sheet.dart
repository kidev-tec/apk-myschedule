import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_config.dart';
import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'cashflow_models.dart';
import 'finance_api.dart';
import 'money.dart';

final _when = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

/// Texto do comprovante (copiar/colar no WhatsApp).
String receiptText(Receipt r) {
  final lines = <String>[
    r.businessName,
    if (r.businessAddress != null) r.businessAddress!,
    '',
    'COMPROVANTE Nº ${r.number.toString().padLeft(4, '0')}',
    _when.format(r.occurredAt),
    if (r.clientName != null) 'Cliente: ${r.clientName}',
    if (r.serviceName != null)
      'Serviço: ${r.serviceName}'
          '${r.appointmentAt != null ? ' (${_when.format(r.appointmentAt!)})' : ''}',
    '${r.isDeposit ? 'Sinal recebido' : 'Valor recebido'}: '
        '${formatCents(r.amountCents)}',
    'Forma: ${r.method?.label ?? 'Outro'}'
        '${r.installments > 1 ? ' em ${r.installments}x' : ''}',
    if (r.priceCents != null) ...[
      'Total do atendimento: ${formatCents(r.priceCents!)}',
      if ((r.balanceCents ?? 0) > 0)
        'Falta pagar: ${formatCents(r.balanceCents!)}'
      else
        'Atendimento quitado',
    ],
    if (r.notes != null && r.notes!.isNotEmpty) 'Obs.: ${r.notes}',
  ];
  return lines.join('\n');
}

/// Compartilhamento do comprovante (injetável nos testes).
class ReceiptSharer {
  const ReceiptSharer();

  Future<void> shareImage(Uint8List png, String fileName, String text) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
    ));
  }

  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Comprovante de um recebimento (TASK-F4-11, RF-F12): prévia, compartilhar
/// como imagem e copiar o texto.
class ReceiptSheet extends StatefulWidget {
  final String paymentId;
  final FinanceApi api;
  final ReceiptSharer sharer;

  const ReceiptSheet({
    super.key,
    required this.paymentId,
    required this.api,
    this.sharer = const ReceiptSharer(),
  });

  @override
  State<ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<ReceiptSheet> {
  final _boundary = GlobalKey();
  late final Future<Receipt> _future = widget.api.receipt(widget.paymentId);
  bool _busy = false;

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Uint8List> _png() async {
    final b =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _share(Receipt r) async {
    setState(() => _busy = true);
    try {
      final png = await _png();
      await widget.sharer.shareImage(
        png,
        'comprovante-${r.number.toString().padLeft(4, '0')}.png',
        receiptText(r),
      );
    } catch (e) {
      if (mounted) _snack('Não consegui compartilhar: ${humanError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(Receipt r) async {
    await widget.sharer.copyText(receiptText(r));
    if (mounted) _snack('Texto do comprovante copiado');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('receipt-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FutureBuilder<Receipt>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 160, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(humanError(snap.error!),
                  key: const Key('receipt-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error)),
            );
          }
          final r = snap.data!;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(key: _boundary, child: _ReceiptCard(r)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('receipt-copy'),
                      onPressed: () => _copy(r),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar texto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('receipt-share'),
                      onPressed: _busy ? null : () => _share(r),
                      icon: const Icon(Icons.share),
                      label: const Text('Compartilhar'),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// O comprovante em si (vira a imagem compartilhada): fundo branco fixo.
class _ReceiptCard extends StatelessWidget {
  final Receipt r;
  const _ReceiptCard(this.r);

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1A1A1A);
    const muted = Color(0xFF6B6B6B);
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(color: muted))),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: ink,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            ),
          ]),
        );
    final logo = r.logoUrl == null
        ? null
        : Uri.parse(ApiConfig.baseUrl).resolve(r.logoUrl!).toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: ink, fontSize: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (logo != null) ...[
                Image.network(logo,
                    width: 44,
                    height: 44,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.businessName,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    if (r.businessAddress != null)
                      Text(r.businessAddress!,
                          style: const TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const Divider(height: 24),
            Text('COMPROVANTE Nº ${r.number.toString().padLeft(4, '0')}',
                key: const Key('receipt-number'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 8),
            row('Data', _when.format(r.occurredAt)),
            if (r.clientName != null) row('Cliente', r.clientName!),
            if (r.serviceName != null) row('Serviço', r.serviceName!),
            if (r.appointmentAt != null)
              row('Atendimento', _when.format(r.appointmentAt!)),
            row('Forma',
                '${r.method?.label ?? 'Outro'}${r.installments > 1 ? ' em ${r.installments}x' : ''}'),
            const Divider(height: 20),
            row(r.isDeposit ? 'Sinal' : 'Valor pago',
                formatCents(r.amountCents),
                bold: true),
            if (r.priceCents != null) ...[
              row('Total', formatCents(r.priceCents!)),
              row(
                  'Situação',
                  (r.balanceCents ?? 0) > 0
                      ? 'Falta ${formatCents(r.balanceCents!)}'
                      : 'Quitado'),
            ],
            if (r.notes != null && r.notes!.isNotEmpty) row('Obs.', r.notes!),
            const SizedBox(height: 12),
            const Text('Gerado pelo Agenva',
                style: TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Abre o comprovante de um recebimento.
Future<void> showReceipt(BuildContext context, FinanceApi api, String paymentId,
    {ReceiptSharer sharer = const ReceiptSharer()}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        ReceiptSheet(paymentId: paymentId, api: api, sharer: sharer),
  );
}
