import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

/// Edição de horário de funcionamento (RF-04) — acessível a qualquer
/// momento nas Configurações, não só no onboarding.
///
/// Mesmo contrato do onboarding: weekday 0=Dom..6=Sáb, intervalos por dia,
/// replace-total no PUT /working-hours.
class WorkingHoursPage extends ConsumerStatefulWidget {
  const WorkingHoursPage({super.key});

  @override
  ConsumerState<WorkingHoursPage> createState() => _WorkingHoursPageState();
}

class _WorkingHoursPageState extends ConsumerState<WorkingHoursPage> {
  static const _names = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

  final Map<int, List<_Range>> _hours = {
    for (var d = 0; d < 7; d++) d: [],
  };
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiClient();
      final r = await api.dio.get('/working-hours');
      final rows = (r.data as List).cast<Map<String, dynamic>>();
      setState(() => _loading = false);
      for (final row in rows) {
        final d = row['weekday'] as int;
        final start = _parse(row['start_time'] as String);
        final end = _parse(row['end_time'] as String);
        if (start != null && end != null) {
          _hours[d]?.add(_Range(start, end));
        }
      }
    } catch (e) {
      debugPrint('[working-hours] erro ao carregar: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// "09:00:00" → 540
  int? _parse(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  String _fmt(int minuteOfDay) {
    final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final slots = <Map<String, dynamic>>[];
      _hours.forEach((weekday, ranges) {
        for (final r in ranges) {
          slots.add({
            'weekday': weekday,
            'start_minute': r.startMinute,
            'end_minute': r.endMinute,
          });
        }
      });
      await ApiClient().dio.put('/working-hours', data: {'slots': slots});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Horários salvos!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[working-hours] erro ao salvar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não consegui salvar. Tenta de novo.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toggleDay(int weekday) {
    setState(() {
      final list = _hours[weekday]!;
      if (list.isEmpty) {
        list.add(_Range(9 * 60, 18 * 60)); // 09:00–18:00 default
      } else {
        list.clear();
      }
    });
  }

  Future<void> _pickTime(int weekday, _Range range, bool isStart) async {
    final initial = TimeOfDay(
      hour: (isStart ? range.startMinute : range.endMinute) ~/ 60,
      minute: (isStart ? range.startMinute : range.endMinute) % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (isStart) {
        range.startMinute = minutes;
      } else {
        range.endMinute = minutes;
      }
      // sanidade: troca se ficar invertido
      if (range.startMinute >= range.endMinute) {
        if (isStart) {
          range.endMinute = (range.startMinute + 60).clamp(0, 24 * 60);
        } else {
          range.startMinute = (range.endMinute - 60).clamp(0, 24 * 60);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horário de funcionamento'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 7,
              itemBuilder: (_, weekday) {
                final enabled = _hours[weekday]!.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Switch(
                        value: enabled,
                        activeThumbColor: AppColors.primaryOf(context),
                        onChanged: (_) => _toggleDay(weekday),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 44,
                        child: Text(
                          _names[weekday],
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: enabled
                            ? Column(
                                children: [
                                  for (final range in _hours[weekday]!)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _pickTime(
                                                  weekday, range, true),
                                              child:
                                                  Text(_fmt(range.startMinute)),
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8),
                                            child: Text('às'),
                                          ),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _pickTime(
                                                  weekday, range, false),
                                              child:
                                                  Text(_fmt(range.endMinute)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              )
                            : Text(
                                'Fechado',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.neutral),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Range {
  int startMinute;
  int endMinute;
  _Range(this.startMinute, this.endMinute);
}
