import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'cash_models.dart';
import 'finance_api.dart';
import 'money.dart';
import 'receipt_sheet.dart';

/// Caixa do dia (TASK-F2-12, RF-F05): abrir com troco, suprimento/sangria,
/// fechar com o valor contado (diferença ao vivo) e histórico.
class CashPage extends ConsumerStatefulWidget {
  const CashPage({super.key});

  @override
  ConsumerState<CashPage> createState() => _CashPageState();
}

typedef _CashData = (CashSession?, List<CashSession>);

class _CashPageState extends ConsumerState<CashPage> {
  late Future<_CashData> _future = _load();

  static final _time = DateFormat('HH:mm', 'pt_BR');
  static final _day = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

  Future<_CashData> _load() async {
    final api = ref.read(financeApiProvider);
    final current = await api.cashCurrent();
    final history = current == null ? await api.cashHistory() : <CashSession>[];
    return (current, history);
  }

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

  /// Executa a ação; erro da API vira aviso, sucesso recarrega.
  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      _snack(done);
      _reload();
    } catch (e) {
      if (mounted) _snack(humanError(e));
    }
  }

  Future<void> _open() async {
    final r = await showDialog<_AmountResult>(
      context: context,
      builder: (_) => const _AmountDialog(
          title: 'Abrir caixa',
          label: 'Saldo inicial (troco)',
          allowZero: true),
    );
    if (r == null || !mounted) return;
    final api = ref.read(financeApiProvider);
    await _run(() => api.cashOpen(r.cents), 'Caixa aberto');
  }

  Future<void> _move({required bool cashIn}) async {
    final r = await showDialog<_AmountResult>(
      context: context,
      builder: (_) => _AmountDialog(
        title: cashIn ? 'Suprimento' : 'Sangria',
        label: cashIn ? 'Valor colocado no caixa' : 'Valor retirado do caixa',
        withNotes: true,
      ),
    );
    if (r == null || !mounted) return;
    final api = ref.read(financeApiProvider);
    await _run(
        () =>
            api.cashMove(cashIn: cashIn, amountCents: r.cents, notes: r.notes),
        cashIn ? 'Suprimento registrado' : 'Sangria registrada');
  }

  Future<void> _close(CashSession s) async {
    final counted = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CloseSheet(expectedCents: s.expectedCents),
    );
    if (counted == null || !mounted) return;
    final api = ref.read(financeApiProvider);
    await _run(() => api.cashClose(counted), 'Caixa fechado');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caixa do dia'),
        actions: const [HomeAction()],
      ),
      body: FutureBuilder<_CashData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(humanError(snap.error!),
                    style: const TextStyle(color: AppColors.error)),
                TextButton(
                    onPressed: _reload, child: const Text('Tentar de novo')),
              ]),
            );
          }
          final (current, history) = snap.data!;
          return current == null ? _closedView(history) : _openView(current);
        },
      ),
    );
  }

  Widget _closedView(List<CashSession> history) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Icon(Icons.point_of_sale, size: 40),
              const SizedBox(height: 8),
              Text('Caixa fechado', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Abra o caixa para conferir o dinheiro do dia. '
                'Recebimentos e despesas funcionam mesmo sem caixa.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('cash-open'),
                onPressed: _open,
                icon: const Icon(Icons.lock_open),
                label: const Text('Abrir caixa'),
              ),
            ]),
          ),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Últimos caixas', style: theme.textTheme.titleSmall),
          for (final s in history)
            Card(
              child: ListTile(
                key: Key('cash-history-${s.id}'),
                title: Text(_day.format(s.openedAt)),
                subtitle: Text('Esperado ${formatCents(s.expectedCents)} • '
                    'Contado ${formatCents(s.countedCents ?? 0)}'),
                trailing: _DifferenceText(s.differenceCents ?? 0),
              ),
            ),
        ],
      ],
    );
  }

  Widget _openView(CashSession s) {
    final theme = Theme.of(context);
    Widget line(String label, String value, {Key? key, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value,
                key: key,
                style: bold
                    ? theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)
                    : null),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aberto às ${_time.format(s.openedAt)}',
                    style: theme.textTheme.titleMedium),
                const Divider(),
                line('Saldo inicial', formatCents(s.openingCents)),
                line('Entradas em dinheiro', '+ ${formatCents(s.cashInCents)}'),
                line('Saídas em dinheiro', '− ${formatCents(s.cashOutCents)}'),
                const Divider(),
                line('Esperado em dinheiro', formatCents(s.expectedCents),
                    key: const Key('cash-expected'), bold: true),
              ],
            ),
          ),
        ),
        if (s.byMethod.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recebido com o caixa aberto',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final e in s.byMethod.entries)
                    line(e.key.label, formatCents(e.value)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('cash-in'),
            onPressed: () => _move(cashIn: true),
            icon: const Icon(Icons.add),
            label: const Text('Suprimento'),
          ),
          OutlinedButton.icon(
            key: const Key('cash-out'),
            onPressed: () => _move(cashIn: false),
            icon: const Icon(Icons.remove),
            label: const Text('Sangria'),
          ),
          FilledButton.icon(
            key: const Key('cash-close'),
            onPressed: () => _close(s),
            icon: const Icon(Icons.lock),
            label: const Text('Fechar caixa'),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Movimentos (${s.movements.length})',
            style: theme.textTheme.titleSmall),
        for (final m in s.movements)
          ListTile(
            key: Key('cash-movement-${m.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(m.isIn ? Icons.south_west : Icons.north_east,
                color: m.isVoided
                    ? AppColors.neutral
                    : (m.isIn ? AppColors.success : AppColors.error)),
            title: Text(
              '${m.label} • ${m.method?.label ?? ''}',
              style: m.isVoided
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Text(m.isVoided
                ? 'Estornado'
                : [_time.format(m.occurredAt), if (m.notes != null) m.notes!]
                    .join(' • ')),
            trailing:
                Text('${m.isIn ? '+' : '−'} ${formatCents(m.amountCents)}'),
            // recebimento: toque abre o comprovante
            onTap: m.isReceivable
                ? () => showReceipt(context, ref.read(financeApiProvider), m.id)
                : null,
          ),
      ],
    );
  }
}

/// "Sobra R$ X" (verde) / "Falta R$ X" (vermelho) / "Confere".
class _DifferenceText extends StatelessWidget {
  final int cents;
  const _DifferenceText(this.cents, {super.key});

  @override
  Widget build(BuildContext context) {
    final (text, color) = cents == 0
        ? ('Confere', AppColors.success)
        : cents > 0
            ? ('Sobra ${formatCents(cents)}', AppColors.success)
            : ('Falta ${formatCents(-cents)}', AppColors.error);
    return Text(text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }
}

class _AmountResult {
  final int cents;
  final String? notes;
  const _AmountResult(this.cents, this.notes);
}

/// Diálogo de valor (abrir, suprimento, sangria); dono dos controllers.
class _AmountDialog extends StatefulWidget {
  final String title;
  final String label;
  final bool withNotes;
  final bool allowZero;
  const _AmountDialog({
    required this.title,
    required this.label,
    this.withNotes = false,
    this.allowZero = false,
  });

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

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

  int get _cents => parseMoney(_amount.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final ok = widget.allowZero || _cents > 0;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const Key('cash-amount'),
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [CentsInputFormatter()],
          decoration:
              InputDecoration(labelText: widget.label, prefixText: 'R\$ '),
        ),
        if (widget.withNotes)
          TextField(
            key: const Key('cash-notes'),
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                const InputDecoration(labelText: 'Observação (opcional)'),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          key: const Key('cash-amount-save'),
          onPressed: ok
              ? () => Navigator.pop(context, _AmountResult(_cents, _notes.text))
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// Fechamento: valor contado com a diferença ao vivo.
class _CloseSheet extends StatefulWidget {
  final int expectedCents;
  const _CloseSheet({required this.expectedCents});

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  final _counted = TextEditingController();

  @override
  void initState() {
    super.initState();
    _counted.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = parseMoney(_counted.text);
    return Padding(
      key: const Key('cash-close-sheet'),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fechar caixa', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Esperado em dinheiro: ${formatCents(widget.expectedCents)}'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('cash-counted'),
            controller: _counted,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [CentsInputFormatter()],
            decoration: const InputDecoration(
                labelText: 'Quanto tem no caixa?', prefixText: 'R\$ '),
          ),
          const SizedBox(height: 12),
          if (counted != null)
            _DifferenceText(counted - widget.expectedCents,
                key: const Key('cash-difference')),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('cash-close-confirm'),
              onPressed: counted == null
                  ? null
                  : () => Navigator.pop(context, counted),
              child: const Text('Fechar caixa'),
            ),
          ),
        ],
      ),
    );
  }
}
