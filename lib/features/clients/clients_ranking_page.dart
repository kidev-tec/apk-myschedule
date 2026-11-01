import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';

/// Uma linha do ranking (GET /clients/ranking).
class RankingEntry {
  final int position;
  final String clientId;
  final String name;
  final bool archived;
  final int visits;
  final DateTime lastVisit;
  final int totalCents;

  RankingEntry.fromJson(Map<String, dynamic> j)
      : position = j['position'] as int,
        clientId = j['client_id'] as String,
        name = j['name'] as String,
        archived = j['archived'] == true,
        visits = j['visits'] as int,
        lastVisit = DateTime.parse(j['last_visit'] as String).toLocal(),
        totalCents = j['total_cents'] as int? ?? 0;
}

/// Ranking de clientes: quem mais foi atendido no período. Conta concluídos
/// e horários que já passaram (sem cancelados, faltas e bloqueios).
class ClientsRankingPage extends StatefulWidget {
  final ApiClient? api;
  const ClientsRankingPage({super.key, this.api});

  @override
  State<ClientsRankingPage> createState() => _ClientsRankingPageState();
}

class _ClientsRankingPageState extends State<ClientsRankingPage> {
  static const _periods = {'all': 'Sempre', '365': '12 meses', '30': '30 dias'};

  late final ApiClient _api = widget.api ?? ApiClient();
  String _period = 'all';
  List<RankingEntry> _items = [];
  bool _loading = true;
  String? _error;

  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.dio
          .get('/clients/ranking', queryParameters: {'period': _period});
      _items = [
        for (final j in (r.data['ranking'] as List))
          RankingEntry.fromJson(j as Map<String, dynamic>),
      ];
    } catch (e) {
      _error = humanError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking de clientes'),
        actions: const [HomeAction()],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            key: const Key('ranking-period'),
            segments: [
              for (final e in _periods.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_period},
            onSelectionChanged: (v) {
              setState(() => _period = v.first);
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
              'Clientes que mais foram atendidos. Conta os atendimentos '
              'concluídos e os horários que já passaram (sem cancelados e '
              'faltas).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.neutral)),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _message(Icons.cloud_off, _error!, retry: true)
                  : _items.isEmpty
                      ? _message(Icons.emoji_events_outlined,
                          'Nenhum atendimento neste período ainda.')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _tile(_items[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _medal(int pos) {
    const colors = {
      1: Color(0xFFD4AF37), // ouro
      2: Color(0xFFA8A9AD), // prata
      3: Color(0xFFCD7F32), // bronze
    };
    final c = colors[pos];
    return CircleAvatar(
      backgroundColor: c ?? AppColors.softOf(context),
      child: c != null
          ? const Icon(Icons.emoji_events, color: Colors.white)
          : Text('$posº',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryOf(context))),
    );
  }

  Widget _tile(RankingEntry e) {
    final theme = Theme.of(context);
    return Card(
      key: Key('ranking-${e.position}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _medal(e.position),
        title: Row(children: [
          Flexible(
            child: Text('${e.position}. ${e.name}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (e.archived) ...[
            const SizedBox(width: 6),
            Text('arquivado',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.neutral)),
          ],
        ]),
        subtitle: Text('${e.visits} atendimento${e.visits > 1 ? 's' : ''}'
            ' · último em ${_date.format(e.lastVisit)}'),
        trailing: Text(_money.format(e.totalCents / 100),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _message(IconData icon, String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: AppColors.neutral),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: const Text('Tentar novamente')),
            ],
          ]),
        ),
      );
}
