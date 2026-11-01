import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'public_link_badge.dart';
import '../../core/widgets/home_action.dart';

class ClientsPage extends ConsumerStatefulWidget {
  /// DI pra teste (mock de rede). Padrão: ApiClient real.
  final ApiClient? api;

  const ClientsPage({super.key, this.api});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  List<Client> _clients = [];
  bool _loading = true;

  /// Filtro: ativos (padrão) ou arquivados ("excluídos", recuperáveis).
  bool _showArchived = false;

  ApiClient get _api => widget.api ?? ApiClient();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  /// Abre o formulário (novo ou edição) e recarrega a lista ao voltar.
  Future<void> _openForm([String? id]) async {
    await context.push(id == null ? '/clients/new' : '/clients/$id/edit');
    if (mounted) _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/clients',
          queryParameters: _showArchived ? {'archived': '1'} : null);
      _clients = (resp.data as List).map((j) => Client.fromJson(j)).toList();
    } catch (e) {
      debugPrint('[clients_page] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Client> get _filteredClients {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return _clients;
    return _clients
        .where(
            (c) => c.name.toLowerCase().contains(q) || c.phoneE164.contains(q))
        .toList();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: error ? AppColors.error : null));
  }

  /// Arquivar: avisa os agendamentos futuros e que o histórico fica
  /// guardado; opção de cancelar os futuros junto.
  Future<void> _archiveClient(Client c) async {
    List<Map<String, dynamic>> upcoming = [];
    try {
      final r = await _api.dio.get('/clients/${c.id}/upcoming');
      upcoming = [
        for (final u in (r.data['upcoming'] as List? ?? []))
          Map<String, dynamic>.from(u as Map),
      ];
    } catch (e) {
      debugPrint('[clients_page] futuros indisponíveis: $e');
    }
    if (!mounted) return;
    final fmt = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');
    var cancelFuture = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Arquivar ${c.name}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (upcoming.isNotEmpty) ...[
                  Text(
                      '${c.name} tem ${upcoming.length} agendamento'
                      '${upcoming.length > 1 ? 's' : ''} futuro'
                      '${upcoming.length > 1 ? 's' : ''}:',
                      key: const Key('archive-upcoming-count'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (final u in upcoming.take(5))
                    Text(
                        '• ${fmt.format(DateTime.parse(u['starts_at'] as String).toLocal())}'
                        ' — ${u['service_name']}'),
                  if (upcoming.length > 5)
                    Text('• e mais ${upcoming.length - 5}…'),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const Key('archive-cancel-future'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: cancelFuture,
                    onChanged: (v) => setD(() => cancelFuture = v ?? false),
                    title: const Text('Cancelar também esses agendamentos'),
                    subtitle: Text(cancelFuture
                        ? 'Os horários ficam livres na agenda.'
                        : 'Eles continuam na agenda normalmente.'),
                  ),
                  const SizedBox(height: 4),
                ],
                const Text(
                    'O histórico de atendimentos fica guardado. O cliente sai '
                    'da lista e de novos agendamentos, e você pode reativá-lo '
                    'quando quiser em "Arquivados".'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                key: const Key('archive-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Arquivar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await _api.dio.delete('/clients/${c.id}',
          queryParameters: cancelFuture ? {'cancel_future': '1'} : null);
      final n =
          (r.data is Map ? r.data['canceled_appointments'] : 0) as int? ?? 0;
      if (!mounted) return;
      _snack('${c.name} foi arquivado(a). Para reativar, veja "Arquivados".'
          '${n > 0 ? ' $n agendamento${n > 1 ? 's' : ''} cancelado${n > 1 ? 's' : ''}.' : ''}');
      _loadClients();
    } catch (e) {
      if (mounted) {
        _snack('Não foi possível arquivar: ${humanError(e)}', error: true);
      }
    }
  }

  Future<void> _restoreClient(Client c) async {
    try {
      await _api.dio.post('/clients/${c.id}/restore');
      if (!mounted) return;
      _snack('${c.name} foi reativado(a).');
      _loadClients();
    } catch (e) {
      if (mounted) {
        _snack('Não foi possível reativar: ${humanError(e)}', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        // "+" só no botão flutuante (o do topo era redundante)
        actions: [
          IconButton(
            key: const Key('open-ranking'),
            tooltip: 'Ranking de clientes',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => context.push('/clients/ranking'),
          ),
          const HomeAction(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar',
                hintText: 'Nome ou telefone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedButton<bool>(
              key: const Key('clients-filter'),
              segments: const [
                ButtonSegment(value: false, label: Text('Ativos')),
                ButtonSegment(
                    value: true,
                    label: Text('Arquivados'),
                    icon: Icon(Icons.archive_outlined)),
              ],
              selected: {_showArchived},
              onSelectionChanged: (v) {
                setState(() => _showArchived = v.first);
                _loadClients();
              },
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filteredClients.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline,
                        size: 64, color: AppColors.neutral),
                    const SizedBox(height: 16),
                    Text(
                        _showArchived
                            ? 'Nenhum cliente arquivado'
                            : 'Nenhum cliente ainda',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (!_showArchived)
                      Text('Toque em + para adicionar o primeiro',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.neutral)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredClients.length,
                itemBuilder: (_, i) {
                  final c = _filteredClients[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryOf(context),
                        child: Text(c.name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Row(children: [
                        Flexible(child: Text(c.name)),
                        if (c.fromPublicLink) ...[
                          const SizedBox(width: 6),
                          const PublicLinkBadge(),
                        ],
                      ]),
                      subtitle: Text(c.phoneE164),
                      trailing: c.archived
                          ? TextButton.icon(
                              key: Key('restore-${c.id}'),
                              onPressed: () => _restoreClient(c),
                              icon: const Icon(Icons.unarchive_outlined),
                              label: const Text('Reativar'),
                            )
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _openForm(c.id);
                                if (v == 'archive') _archiveClient(c);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Editar')),
                                PopupMenuItem(
                                    value: 'archive', child: Text('Arquivar')),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class Client {
  final String id;
  final String name;
  final String phoneE164;
  final String? email;
  final DateTime? birthday;

  /// 'app' (cadastrado aqui) | 'public_link' (se cadastrou sozinho no
  /// agendamento online — só nome e celular).
  final String origin;
  bool get fromPublicLink => origin == 'public_link';

  /// Arquivado ("excluído"): fora da lista e de novos agendamentos.
  final bool archived;

  Client(
      {required this.id,
      required this.name,
      required this.phoneE164,
      this.email,
      this.birthday,
      this.origin = 'app',
      this.archived = false});

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: j['id'],
        name: j['name'],
        phoneE164: j['phone_e164'] ?? j['phoneE164'] ?? '',
        email: j['email'],
        birthday: j['birthday'] != null ? DateTime.parse(j['birthday']) : null,
        origin: j['origin'] as String? ?? 'app',
        archived: j['archived'] == true,
      );
}
