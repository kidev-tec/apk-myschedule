import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  List<Client> _clients = [];
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/clients');
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

  Future<void> _deleteClient(Client c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir cliente?'),
        content: Text('${c.name} será arquivado (pode recuperar depois).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ApiClient();
      await api.dio.delete('/clients/${c.id}');
      _loadClients();
    } catch (e) {
      debugPrint('[clients_page] erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/clients/new'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              16 + MediaQuery.of(context).padding.bottom),
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
                    Text('Nenhum cliente ainda',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Toque em + pra adicionar o primeiro',
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
                      title: Text(c.name),
                      subtitle: Text(c.phoneE164),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            context.push('/clients/${c.id}/edit');
                          }
                          if (v == 'delete') _deleteClient(c);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Editar')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Excluir')),
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
        onPressed: () => context.push('/clients/new'),
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

  Client(
      {required this.id,
      required this.name,
      required this.phoneE164,
      this.email,
      this.birthday});

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: j['id'],
        name: j['name'],
        phoneE164: j['phone_e164'] ?? j['phoneE164'] ?? '',
        email: j['email'],
        birthday: j['birthday'] != null ? DateTime.parse(j['birthday']) : null,
      );
}
