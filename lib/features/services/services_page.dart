import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  List<Service> _services = [];
  bool _loading = true;
  final priceFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/services');
      _services = (resp.data as List).map((j) => Service.fromJson(j)).toList();
    } catch (e) {
      debugPrint('[services] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteService(Service s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir serviço?'),
        content: Text('${s.name} será arquivado.'),
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
      await api.dio.delete('/services/${s.id}');
      _loadServices();
    } catch (e) {
      debugPrint('[services] erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serviços'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/services/new'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.content_cut_outlined,
                          size: 64, color: AppColors.neutral),
                      const SizedBox(height: 16),
                      Text('Nenhum serviço ainda',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Toque em + pra criar o primeiro',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.neutral)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      16 + MediaQuery.of(context).padding.bottom),
                  itemCount: _services.length,
                  itemBuilder: (_, i) {
                    final s = _services[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryOf(context),
                          child: const Icon(Icons.content_cut, color: Colors.white),
                        ),
                        title: Text(s.name),
                        subtitle: Text(
                            '${s.durationMin} min • ${priceFmt.format(s.priceCents / 100)}'),

                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              context.push('/services/${s.id}/edit');
                            }
                            if (v == 'delete') _deleteService(s);
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/services/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class Service {
  final String id;
  final String name;
  final int durationMin;
  final int priceCents;

  Service(
      {required this.id,
      required this.name,
      required this.durationMin,
      required this.priceCents});

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'],
        name: j['name'],
        durationMin: j['duration_min'] ?? j['durationMin'],
        priceCents: j['price_cents'] ?? j['priceCents'],
      );
}
