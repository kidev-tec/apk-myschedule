import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import 'service_subtitle.dart';
import '../../core/widgets/home_action.dart';

class ServicesPage extends ConsumerStatefulWidget {
  /// DI pra teste (mock de rede). Padrão: ApiClient real.
  final ApiClient? api;

  const ServicesPage({super.key, this.api});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  List<Service> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() => _loading = true);
    try {
      final api = widget.api ?? ApiClient();
      final resp = await api.dio.get('/services');
      _services = (resp.data as List).map((j) => Service.fromJson(j)).toList();
    } catch (e) {
      debugPrint('[services] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Abre o formulário e recarrega a lista quando ele salvar (pop(true)).
  Future<void> _openForm([String? id, bool kit = false]) async {
    final saved = await context.push<bool>(id != null
        ? '/services/$id/edit'
        : kit
            ? '/services/new-kit'
            : '/services/new');
    if (saved == true && mounted) _loadServices();
  }

  /// "+" pergunta o que criar: serviço avulso ou kit (combo).
  Future<void> _chooseNew() async {
    final kit = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('new-service'),
            leading: const Icon(Icons.miscellaneous_services),
            title: const Text('Serviço'),
            subtitle: const Text('Um atendimento, ex.: Corte'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            key: const Key('new-kit'),
            leading: const Icon(Icons.style_outlined),
            title: const Text('Kit (combo)'),
            subtitle: const Text('Vários serviços juntos, ex.: Corte + Barba'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    );
    if (kit != null && mounted) await _openForm(null, kit);
  }

  Future<void> _deleteService(Service s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir serviço?'),
        content: Text('"${s.name}" não vai mais aparecer pra novos '
            'agendamentos (nem no teu link). Os agendamentos que já usaram '
            'esse serviço continuam mostrando ele na agenda e no histórico.'),
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

    final api = widget.api ?? ApiClient();
    try {
      await api.dio.delete('/services/${s.id}');
      _loadServices();
    } on DioException catch (e) {
      // 409: o serviço está num kit — pergunta se exclui os kits junto
      final data = e.response?.data;
      if (e.response?.statusCode == 409 && data is Map && mounted) {
        final kits = [
          for (final k in (data['kits'] as List? ?? [])) k['name'] as String,
        ];
        final junto = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Serviço está em kit'),
            content: Text('"${s.name}" faz parte de: ${kits.join(', ')}.\n\n'
                'Pra excluir, tira ele do kit (editando o kit) ou exclui '
                '${kits.length > 1 ? 'os kits' : 'o kit'} junto. '
                'Agendamentos já feitos continuam no histórico.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  key: const Key('delete-with-kits'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(kits.length > 1
                      ? 'Excluir com os kits'
                      : 'Excluir com o kit')),
            ],
          ),
        );
        if (junto == true) {
          try {
            await api.dio.delete('/services/${s.id}',
                queryParameters: {'kits': 'archive'});
          } catch (e2) {
            debugPrint('[services] erro: $e2');
          }
          if (mounted) _loadServices();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não consegui excluir: ${humanError(e)}'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serviços'),
        // "+" só no botão flutuante (o do topo era redundante)
        actions: const [HomeAction()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.miscellaneous_services_outlined,
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
                  // 88 = altura do FAB + margem: o "+" não cobre o ⋮ do último
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 88 + MediaQuery.of(context).padding.bottom),
                  itemCount: _services.length,
                  itemBuilder: (_, i) {
                    final s = _services[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryOf(context),
                          child: Icon(
                              s.isKit
                                  ? Icons.style_outlined
                                  : Icons.miscellaneous_services,
                              color: Colors.white),
                        ),
                        title: Text(s.name),
                        subtitle: ServiceSubtitle(
                            durationMin: s.durationMin,
                            priceCents: s.priceCents,
                            kitItems: s.itemNames,
                            kitFullCents: s.itemsFullCents),
                        isThreeLine: s.isKit,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _openForm(s.id);
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
        onPressed: _chooseNew,
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

  /// Kit (combo): nomes dos serviços incluídos, em ordem.
  final bool isKit;
  final List<String> itemNames;

  /// Soma dos preços dos itens (kit) — mostra "de X por Y" se tem desconto.
  final int itemsFullCents;

  Service(
      {required this.id,
      required this.name,
      required this.durationMin,
      required this.priceCents,
      this.isKit = false,
      this.itemNames = const [],
      this.itemsFullCents = 0});

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'],
        name: j['name'],
        durationMin: j['duration_min'] ?? j['durationMin'],
        priceCents: j['price_cents'] ?? j['priceCents'],
        isKit: j['is_kit'] == true,
        itemNames: [
          for (final i in (j['items'] as List? ?? [])) i['name'] as String,
        ],
        itemsFullCents: [
          for (final i in (j['items'] as List? ?? []))
            (i['price_cents'] ?? 0) as int,
        ].fold(0, (a, b) => a + b),
      );
}
