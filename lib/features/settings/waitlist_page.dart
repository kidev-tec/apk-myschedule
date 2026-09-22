import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

/// F5 — Lista de espera: quem quer vaga em um dia específico.
/// Ao cancelar um horário, o prestador vê quem avisar e marca como
/// notificado depois do contato.
class WaitlistPage extends ConsumerStatefulWidget {
  const WaitlistPage({super.key});

  @override
  ConsumerState<WaitlistPage> createState() => _WaitlistPageState();
}

class _WaitlistPageState extends ConsumerState<WaitlistPage> {
  DateTime _day = DateTime.now();
  List<Map<String, dynamic>>? _entries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_day);
    try {
      final r = await ApiClient()
          .dio
          .get('/waitlist', queryParameters: {'date': dateStr});
      if (mounted) {
        setState(() {
          _entries = (r.data['waitlist'] as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeDay(int days) async {
    setState(() => _day = _day.add(Duration(days: days)));
    await _load();
  }

  Future<void> _mark(String id, String status) async {
    try {
      await ApiClient().dio.patch('/waitlist/$id', data: {'status': status});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não deu pra atualizar'),
            backgroundColor: AppColors.error));
      }
    }
  }

  String _statusLabel(String s) => switch (s) {
        'waiting' => 'aguardando',
        'notified' => 'avisado',
        'served' => 'atendido',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de espera')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: () => _changeDay(-1),
                    icon: const Icon(Icons.chevron_left)),
                Text(DateFormat('EEEE, dd/MM').format(_day),
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    onPressed: () => _changeDay(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_entries == null || _entries!.isEmpty)
            Expanded(
              child: Center(
                child: Text('Ninguém na espera pra esse dia. 🗓️',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _entries!.map((e) {
                  final status = e['status'] as String;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        status == 'served'
                            ? Icons.check_circle
                            : status == 'notified'
                                ? Icons.notifications_active
                                : Icons.hourglass_top,
                        color: status == 'waiting'
                            ? AppColors.primaryOf(context)
                            : AppColors.success,
                      ),
                      title: Text(e['client_name'] as String),
                      subtitle: Text(
                          '${e['phone']} · ${_statusLabel(status)}'),
                      trailing: status == 'waiting'
                          ? TextButton(
                              onPressed: () => _mark(e['id'] as String, 'notified'),
                              child: const Text('Avisar'),
                            )
                          : status == 'notified'
                              ? TextButton(
                                  onPressed: () =>
                                      _mark(e['id'] as String, 'served'),
                                  child: const Text('Atendido'),
                                )
                              : null,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
