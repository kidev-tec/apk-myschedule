import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

/// F3 — Bloqueios de agenda: almoço, feriado, férias, compromissos.
/// Janelas em que o profissional não aceita agendamentos mesmo dentro
/// do expediente. Clientes veem "indisponível" no link de agendamento.
class TimeOffsPage extends ConsumerStatefulWidget {
  const TimeOffsPage({super.key});

  @override
  ConsumerState<TimeOffsPage> createState() => _TimeOffsPageState();
}

class _TimeOffsPageState extends ConsumerState<TimeOffsPage> {
  List<Map<String, dynamic>>? _timeOffs;
  bool _loading = true;
  bool _saving = false;

  final _reasonController = TextEditingController();
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient().dio.get('/time-offs');
      if (mounted) {
        setState(() {
          _timeOffs = (r.data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        (isStart ? _start : _end) ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = dt;
        // end default = start + 1h
        if (_end == null || _end!.isBefore(dt)) {
          _end = dt.add(const Duration(hours: 1));
        }
      } else {
        _end = dt;
      }
    });
  }

  String _fmt(DateTime d) =>
      DateFormat('dd/MM HH:mm').format(d);

  Future<void> _save() async {
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escolhe início e fim do bloqueio'),
          backgroundColor: AppColors.error));
      return;
    }
    if (!_end!.isAfter(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O fim precisa ser depois do início'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient().dio.post('/time-offs', data: {
        'starts_at': _start!.toUtc().toIso8601String(),
        'ends_at': _end!.toUtc().toIso8601String(),
        'reason': _reasonController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bloqueio criado'),
          backgroundColor: AppColors.success));
      _reasonController.clear();
      setState(() {
        _start = null;
        _end = null;
      });
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? (e.response?.data['error'] as String? ?? 'Não deu pra criar o bloqueio')
          : 'Não deu pra criar o bloqueio. Verifica a internet.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await ApiClient().dio.delete('/time-offs/$id');
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não deu pra remover'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bloqueios de agenda')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Horários em que tu NÃO atende — almoço, feriado, consulta. '
                  'Clientes veem esses horários como indisponíveis.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_timeOffs == null || _timeOffs!.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Nenhum bloqueio. Tua agenda tá aberta. 📅',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  )
                else
                  ..._timeOffs!.map((t) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.block, color: AppColors.error),
                          title: Text(
                              '${_fmt(DateTime.parse(t['starts_at']))} → ${_fmt(DateTime.parse(t['ends_at']))}'),
                          subtitle: t['reason'] != null && (t['reason'] as String).isNotEmpty
                              ? Text(t['reason'])
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(t['id'] as String),
                          ),
                        ),
                      )),
                const SizedBox(height: 24),
                Text('Novo bloqueio',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                    hintText: 'Ex: Almoço, Feriado, Consulta',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_start == null
                            ? 'Início'
                            : _fmt(_start!)),
                        onPressed: () => _pick(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stop),
                        label: Text(_end == null ? 'Fim' : _fmt(_end!)),
                        onPressed: () => _pick(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.block),
                  label: const Text('Bloquear horário'),
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
