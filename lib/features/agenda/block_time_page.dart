import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/utils/duration_text.dart';
import '../../theme/app_theme.dart';
import 'agenda_page.dart' show Appointment;
import 'block_logic.dart';
import 'booking_wizard.dart' show WorkingHour, StringExtension;

/// "Bloquear horário": grade do dia (uma linha por hora, quadradinhos de
/// 5 min) com livre/ocupado/passado. O prestador marca os trechos que
/// quiser (toca no início e no fim de cada um) e bloqueia todos de uma vez,
/// com o mesmo motivo. Devolve quantos trechos foram bloqueados.
class BlockTimePage extends StatefulWidget {
  final ApiClient api;
  final DateTime initialDate;
  final DateTime Function() clock;

  const BlockTimePage({
    super.key,
    required this.api,
    required this.initialDate,
    this.clock = DateTime.now,
  });

  @override
  State<BlockTimePage> createState() => _BlockTimePageState();
}

class _BlockTimePageState extends State<BlockTimePage> {
  static const _reasons = ['Almoço', 'Médico', 'Pessoal', 'Folga'];

  late DateTime _day;
  List<WorkingHour> _hours = [];
  List<HourRow> _grid = [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  /// Quadradinhos marcados (início de cada um) e o "início" pendente de um
  /// trecho (primeiro toque; o segundo toque fecha o trecho).
  final Set<DateTime> _selected = {};
  DateTime? _anchor;
  final _reasonCtrl = TextEditingController();

  final _hm = DateFormat('HH:mm', 'pt_BR');

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    _day = DateTime(d.year, d.month, d.day);
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = widget.clock();
    return DateTime(n.year, n.month, n.day);
  }

  List<(DateTime, DateTime)> get _ranges => mergeSelection(_selected);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _selected.clear();
      _anchor = null;
    });
    try {
      final results = await Future.wait([
        if (_hours.isEmpty) widget.api.dio.get('/working-hours'),
        widget.api.dio.get('/appointments', queryParameters: {
          'from': _day.toUtc().toIso8601String(),
          'to': _day.add(const Duration(days: 1)).toUtc().toIso8601String(),
        }),
        widget.api.dio.get('/time-offs'),
      ]);
      var i = 0;
      if (_hours.isEmpty) {
        _hours = (results[i++].data as List)
            .map((j) => WorkingHour.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      final apptData = results[i++].data;
      final appts =
          ((apptData is Map ? apptData['appointments'] : apptData) as List? ??
                  [])
              .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
              .where((a) => a.status == 'pending' || a.status == 'confirmed');
      final offs = (results[i++].data as List? ?? []).cast<Map>();
      String withReason(String base, String? reason) =>
          (reason ?? '').isEmpty ? base : '$base · $reason';

      _grid = dayGrid(
        date: _day,
        workingHours: _hours,
        now: widget.clock(),
        busy: [
          for (final a in appts)
            BusyRange(
              a.startsAt,
              a.endsAt.add(Duration(minutes: a.bufferMin)),
              a.isBlock
                  ? withReason('Bloqueado', a.canceledReason)
                  : '${a.clientName} · ${a.serviceName}',
            ),
          for (final t in offs)
            BusyRange(
              DateTime.parse(t['starts_at'] as String).toLocal(),
              DateTime.parse(t['ends_at'] as String).toLocal(),
              withReason('Bloqueio de agenda', t['reason'] as String?),
            ),
        ],
      );
    } catch (e) {
      _loadError = humanError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _changeDay(int delta) {
    _day = _day.add(Duration(days: delta));
    _load();
  }

  /// 1º toque num livre: marca e vira início do trecho. 2º toque: preenche
  /// até ali (pulando ocupados). Toque num marcado: desmarca só ele.
  void _tapCell(SlotCell c) {
    if (c.state == CellState.busy) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('${_hm.format(c.start)} ocupado: ${c.label}')));
      return;
    }
    if (!c.isFree) return;
    setState(() {
      if (_selected.contains(c.start) && _anchor == null) {
        _selected.remove(c.start);
      } else if (_anchor == null) {
        _selected.add(c.start);
        _anchor = c.start;
      } else {
        _selected.addAll(freeBetween(_grid, _anchor!, c.start));
        _anchor = null;
      }
    });
  }

  void _selectAllFree() => setState(() {
        _anchor = null;
        _selected.addAll([
          for (final r in _grid)
            for (final c in r.cells)
              if (c != null && c.isFree) c.start,
        ]);
      });

  void _removeRange((DateTime, DateTime) r) => setState(() {
        _anchor = null;
        _selected.removeWhere((s) => !s.isBefore(r.$1) && s.isBefore(r.$2));
      });

  Future<void> _submit() async {
    final ranges = _ranges;
    setState(() => _saving = true);
    var done = 0;
    try {
      for (final (s, e) in ranges) {
        await widget.api.dio.post('/appointments', data: {
          'startsAt': s.toUtc().toIso8601String(),
          'endsAt': e.toUtc().toIso8601String(),
          'source': 'block',
          if (_reasonCtrl.text.trim().isNotEmpty)
            'canceledReason': _reasonCtrl.text.trim(),
        });
        done++;
      }
      if (mounted) Navigator.pop(context, done);
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não consegui bloquear: ${humanError(e)}'),
          backgroundColor: AppColors.error));
      if (done > 0) {
        // parte já bloqueou: volta pra agenda mostrar o que entrou
        Navigator.pop(context, done);
        return;
      }
      await _load(); // a agenda mudou: recarrega o dia
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');
    final ranges = _ranges;
    final total =
        ranges.fold<int>(0, (sum, r) => sum + r.$2.difference(r.$1).inMinutes);
    final hasFree = _grid.any((r) => r.cells.any((c) => c?.isFree ?? false));

    return Scaffold(
      appBar: AppBar(title: const Text('Bloquear horário')),
      body: Column(
        children: [
          Container(
            color: AppColors.softOf(context).withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                key: const Key('block-prev-day'),
                icon: const Icon(Icons.chevron_left),
                onPressed: _day.isAfter(_today) ? () => _changeDay(-1) : null,
              ),
              Expanded(
                child: Text(dateFmt.format(_day).capitalize(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                key: const Key('block-next-day'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeDay(1),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? _message(Icons.cloud_off, _loadError!, retry: true)
                    : _grid.isEmpty
                        ? _message(Icons.event_busy,
                            'Sem expediente neste dia — nada pra bloquear.')
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                            children: [
                              Text(
                                  _anchor == null
                                      ? 'Toque no início e depois no fim de cada trecho. '
                                          'Pode marcar vários.'
                                      : 'Agora toque no fim do trecho que começa às '
                                          '${_hm.format(_anchor!)}.',
                                  key: const Key('block-hint'),
                                  style: theme.textTheme.bodyMedium),
                              const SizedBox(height: 8),
                              _legend(),
                              const SizedBox(height: 8),
                              _minuteHeader(),
                              for (final r in _grid) _hourRow(r),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, children: [
                                if (hasFree)
                                  OutlinedButton.icon(
                                    key: const Key('block-all-free'),
                                    onPressed: _selectAllFree,
                                    icon:
                                        const Icon(Icons.select_all, size: 18),
                                    label: const Text('Marcar todos os livres'),
                                  ),
                                if (_selected.isNotEmpty)
                                  TextButton.icon(
                                    key: const Key('block-clear'),
                                    onPressed: () => setState(() {
                                      _selected.clear();
                                      _anchor = null;
                                    }),
                                    icon: const Icon(Icons.clear, size: 18),
                                    label: const Text('Limpar'),
                                  ),
                              ]),
                              if (ranges.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text('Trechos',
                                    style: theme.textTheme.titleSmall),
                                const SizedBox(height: 4),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  for (final r in ranges)
                                    InputChip(
                                      key: Key(
                                          'block-range-${_hm.format(r.$1)}'),
                                      label: Text(
                                          '${_hm.format(r.$1)} – ${_hm.format(r.$2)}'),
                                      deleteIcon:
                                          const Icon(Icons.close, size: 18),
                                      deleteButtonTooltipMessage:
                                          'Remover trecho',
                                      onDeleted: () => _removeRange(r),
                                    ),
                                ]),
                                const SizedBox(height: 16),
                                _reasonField(),
                              ],
                            ],
                          ),
          ),
        ],
      ),
      bottomNavigationBar: ranges.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('block-submit'),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_outline),
                  label: Text(ranges.length == 1
                      ? 'Bloquear ${_hm.format(ranges.first.$1)} às '
                          '${_hm.format(ranges.first.$2)}'
                      : 'Bloquear ${ranges.length} trechos '
                          '(${humanDuration(total)})'),
                ),
              ),
            ),
    );
  }

  Widget _message(IconData icon, String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.neutral),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ]),
        ),
      );

  static const _labelWidth = 40.0;

  Color _freeColor(BuildContext c) =>
      AppColors.primaryOf(c).withValues(alpha: 0.12);
  static final _busyColor = AppColors.neutral.withValues(alpha: 0.45);
  static final _pastColor = AppColors.neutral.withValues(alpha: 0.12);

  Widget _legend() {
    Widget item(Color color, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(text, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
    return Wrap(spacing: 12, runSpacing: 4, children: [
      item(_freeColor(context), 'Livre'),
      item(AppColors.primaryOf(context), 'Marcado'),
      item(_busyColor, 'Ocupado'),
      item(_pastColor, 'Já passou'),
    ]);
  }

  /// ":00 :15 :30 :45" alinhado com as colunas de 5 min.
  Widget _minuteHeader() => Padding(
        padding: const EdgeInsets.only(left: _labelWidth, bottom: 2),
        child: Row(children: [
          for (var m = 0; m < 60; m += blockCellMin)
            Expanded(
              child: Text(m % 15 == 0 ? ':${m.toString().padLeft(2, '0')}' : '',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.neutral)),
            ),
        ]),
      );

  Widget _hourRow(HourRow r) {
    final primary = AppColors.primaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: _labelWidth,
          child: Text('${r.hour.toString().padLeft(2, '0')}h',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        for (var i = 0; i < r.cells.length; i++)
          Expanded(
            child: _cell(r.cells[i], primary, first: i % 3 == 0),
          ),
      ]),
    );
  }

  Widget _cell(SlotCell? c, Color primary, {required bool first}) {
    if (c == null) return const SizedBox(height: 36);
    final selected = _selected.contains(c.start);
    final isAnchor = _anchor == c.start;
    final color = selected
        ? primary
        : switch (c.state) {
            CellState.free => _freeColor(context),
            CellState.busy => _busyColor,
            CellState.past => _pastColor,
          };
    return GestureDetector(
      key: Key('cell-${_hm.format(c.start)}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapCell(c),
      child: Container(
        height: 36,
        // espaço maior a cada 15 min ajuda a ler a grade
        margin: EdgeInsets.only(left: first ? 3 : 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: isAnchor ? Border.all(color: Colors.black87, width: 2) : null,
        ),
      ),
    );
  }

  Widget _reasonField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Motivo (opcional, só você vê)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reasonCtrl.text == r,
                onSelected: (_) => setState(() => _reasonCtrl.text = r),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('block-reason'),
            controller: _reasonCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'ou escreve: ex.: dentista',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );
}
