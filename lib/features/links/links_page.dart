import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';
import '../settings/logo_service.dart';
import 'links_service.dart';

/// Vínculos do módulo agregador (API 0026, docs/plano-agregador.md §6).
///
/// A mesma tela serve os dois lados, conforme o `account_kind` do GET /me:
/// - estabelecimento → "Profissionais": convidar pelo código P-, responder
///   pedidos, ligar/desligar quem aparece no link, ordenar e encerrar;
/// - profissional → "Meus estabelecimentos": entrar pelo código E-,
///   responder convites, cancelar pedido e sair.
class LinksPage extends StatefulWidget {
  final ApiClient? api;
  const LinksPage({super.key, this.api});

  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final LinksService _links = LinksService(_api);

  bool _loading = true;
  String? _error;
  bool _aggregator = false;
  String? _myCode;
  String _myName = '';
  List<ProfessionalLink> _items = [];

  /// Ids com ação em andamento (desabilita os botões daquele item).
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [quiet]: recarrega sem trocar a tela pelo "carregando" (depois de uma
  /// ação ou ao puxar para atualizar) — a lista atual fica visível.
  Future<void> _load({bool quiet = false}) async {
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final me = await _api.dio.get('/me');
      final data = (me.data as Map).cast<String, dynamic>();
      final aggregator = data['account_kind'] == 'aggregator';
      final items = await _links.list(asAggregator: aggregator);
      if (!mounted) return;
      setState(() {
        _aggregator = aggregator;
        _myCode = (aggregator ? data['aggregator_code'] : data['pro_code'])
            as String?;
        _myName = data['name'] as String? ?? '';
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanError(e);
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.error : Colors.green));
  }

  /// Roda uma ação no vínculo, mostra o resultado e recarrega a lista.
  Future<void> _run(String id, Future<String?> Function() action) async {
    setState(() => _busy.add(id));
    try {
      final msg = await action();
      if (!mounted) return;
      if (msg != null) _snack(msg);
      await _load(quiet: true);
    } catch (e) {
      if (mounted) _snack(humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  // ─── ações ────────────────────────────────────────────────────────────

  Future<void> _addByCode() async {
    final ctrl = TextEditingController();
    final hint = _aggregator ? 'P-XXXXXXXX' : 'E-XXXXXXXX';
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_aggregator
            ? 'Convidar profissional'
            : 'Entrar em um estabelecimento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_aggregator
                ? 'Peça ao profissional o código dele. Está em Configurações, '
                    'no app do Agenva. Ele precisa aceitar o convite.'
                : 'Peça ao estabelecimento o código dele. O estabelecimento '
                    'precisa aceitar o seu pedido.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('link-code-field'),
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: _aggregator
                    ? 'Código do profissional'
                    : 'Código do estabelecimento',
                hintText: hint,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(_aggregator ? 'Convidar' : 'Enviar pedido')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _run('new', () async {
      await _links.create(code);
      return _aggregator
          ? 'Convite enviado! O profissional precisa aceitar.'
          : 'Pedido enviado! Agora é só aguardar o estabelecimento aceitar.';
    });
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _end(ProfessionalLink l) async {
    final ok = _aggregator
        ? await _confirm(
            'Encerrar vínculo com ${l.name}?',
            '${l.name} deixa de aparecer no seu link. Os agendamentos já '
                'marcados continuam na agenda do profissional.',
            'Encerrar')
        : await _confirm(
            'Sair de ${l.name}?',
            'Você deixa de aparecer no link do estabelecimento. Os '
                'agendamentos já marcados continuam na sua agenda.',
            'Sair');
    if (!ok || !mounted) return;
    await _run(l.id, () async {
      final future = await _links.end(l.id);
      if (_aggregator) return 'Vínculo com ${l.name} encerrado.';
      if (future == 0) return 'Você saiu de ${l.name}.';
      return 'Você saiu de ${l.name}. '
          '${future == 1 ? '1 agendamento futuro continua' : '$future agendamentos futuros continuam'} '
          'na sua agenda.';
    });
  }

  /// Liga/desliga "Aparece no meu link". A chave fica travada até a API
  /// responder (dois toques seguidos não viram dois PATCH fora de ordem); se
  /// falhar, recarrega o valor real do servidor.
  Future<void> _toggleShow(ProfessionalLink l, bool show) async {
    setState(() {
      _busy.add(l.id);
      _items = [
        for (final x in _items) x.id == l.id ? x.copyWith(showOnLink: show) : x,
      ];
    });
    try {
      await _links.update(l.id, showOnLink: show);
    } catch (e) {
      if (!mounted) return;
      _snack(humanError(e), error: true);
      await _load(quiet: true);
    } finally {
      if (mounted) setState(() => _busy.remove(l.id));
    }
  }

  /// Move o profissional uma posição (delta -1 = sobe) e grava a ordem nova
  /// de quem mudou de lugar.
  Future<void> _move(ProfessionalLink l, int delta) async {
    final active = _active;
    final from = active.indexWhere((x) => x.id == l.id);
    final to = from + delta;
    if (to < 0 || to >= active.length) return;
    final reordered = [...active]..removeAt(from);
    reordered.insert(to, l);
    final changed = <ProfessionalLink>[];
    final updated = <String, ProfessionalLink>{};
    for (var p = 0; p < reordered.length; p++) {
      final x = reordered[p];
      if (x.position != p) changed.add(x);
      updated[x.id] = x.copyWith(position: p);
    }
    setState(() {
      _busy.add(_reorderKey);
      _items = [
        for (final x in _items) updated[x.id] ?? x,
      ];
    });
    try {
      for (final x in changed) {
        await _links.update(x.id, position: updated[x.id]!.position);
      }
    } catch (e) {
      if (!mounted) return;
      _snack(humanError(e), error: true);
      // parte das posições pode ter sido gravada: a ordem certa é a do
      // servidor, não a foto de antes
      await _load(quiet: true);
    } finally {
      if (mounted) setState(() => _busy.remove(_reorderKey));
    }
  }

  /// Marca de "reordenando" em [_busy]: trava os menus de todos os itens.
  static const _reorderKey = '__reorder__';

  Future<void> _shareCode() async {
    final code = _myCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    await SharePlus.instance.share(ShareParams(
        text: _aggregator
            ? 'Para entrar${_myName.isEmpty ? '' : ' no $_myName'} pelo '
                'Agenva, use o código do estabelecimento: $code'
            : 'Meu código de profissional no Agenva: $code'));
  }

  // ─── listas ───────────────────────────────────────────────────────────

  List<ProfessionalLink> get _awaitingMe =>
      _items.where((l) => l.isPending && l.awaitingMe).toList();
  List<ProfessionalLink> get _sent =>
      _items.where((l) => l.isPending && !l.awaitingMe).toList();
  List<ProfessionalLink> get _active => _items.where((l) => l.isActive).toList()
    ..sort((a, b) => a.position != b.position
        ? a.position.compareTo(b.position)
        : a.name.compareTo(b.name));

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_loading && _error == null
              ? ''
              : _aggregator
                  ? 'Profissionais'
                  : 'Meus estabelecimentos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: () => _load(quiet: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: _content(),
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 64, color: AppColors.neutral),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _load, child: const Text('Tentar de novo')),
          ]),
        ),
      );

  List<Widget> _content() {
    final theme = Theme.of(context);
    final awaiting = _awaitingMe;
    final sent = _sent;
    final active = _active;
    return [
      if (_myCode != null)
        Card(
          child: ListTile(
            leading: Icon(
                _aggregator ? Icons.groups_outlined : Icons.badge_outlined,
                color: AppColors.primaryOf(context)),
            title: Text(_aggregator
                ? 'Código do estabelecimento'
                : 'Seu código de profissional'),
            subtitle: Text(_myCode!,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            trailing: IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartilhar código',
              onPressed: _shareCode,
            ),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('link-add'),
        onPressed: _busy.contains('new') ? null : _addByCode,
        icon: Icon(_aggregator ? Icons.person_add_alt_1 : Icons.login),
        label: Text(_aggregator
            ? 'Convidar profissional'
            : 'Entrar em um estabelecimento'),
      ),
      if (awaiting.isNotEmpty) ...[
        _header('Esperando sua resposta'),
        for (final l in awaiting) _awaitingTile(l),
      ],
      if (sent.isNotEmpty) ...[
        _header(_aggregator ? 'Convites enviados' : 'Pedidos enviados'),
        for (final l in sent) _sentTile(l),
      ],
      _header(_aggregator ? 'Na equipe' : 'Estabelecimentos'),
      if (active.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            _aggregator
                ? 'Nenhum profissional na equipe ainda. Envie o código do '
                    'estabelecimento ou convide pelo código do profissional.'
                : 'Você ainda não faz parte de nenhum estabelecimento. '
                    'Peça o código e envie um pedido.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: AppColors.neutral),
          ),
        )
      else ...[
        if (_aggregator)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'No seu link, o cliente vê os profissionais nesta ordem.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < active.length; i++)
          _activeTile(active[i], i, active.length),
      ],
    ];
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _avatar(ProfessionalLink l) {
    final logo = l.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      return CircleAvatar(
          backgroundImage: NetworkImage(LogoService.absoluteUrl(logo)));
    }
    return CircleAvatar(
      backgroundColor: AppColors.softOf(context),
      child: Text(l.name.isEmpty ? '?' : l.name[0].toUpperCase(),
          style: TextStyle(color: AppColors.primaryOf(context))),
    );
  }

  String? _detail(ProfessionalLink l) {
    if (_aggregator) {
      return [
        if (l.businessName != null && l.businessName != l.name) l.businessName!,
        if (l.proCode != null) l.proCode!,
      ].join(' · ');
    }
    return l.city;
  }

  /// Detalhe (negócio · código / cidade) em cima do texto do pedido —
  /// o nome do usuário sozinho pode ser genérico ("Profissional").
  String _withDetail(ProfessionalLink l, String text) {
    final d = _detail(l);
    return d == null || d.isEmpty ? text : '$d\n$text';
  }

  Widget _awaitingTile(ProfessionalLink l) {
    final busy = _busy.contains(l.id);
    return Card(
      key: Key('link-awaiting-${l.id}'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            ListTile(
              leading: _avatar(l),
              title: Text(l.name),
              subtitle: Text(_withDetail(
                  l,
                  _aggregator
                      ? 'Quer fazer parte da sua equipe.'
                      : 'Convidou você para fazer parte da equipe.')),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _run(l.id, () async {
                            await _links.reject(l.id);
                            return 'Pedido recusado.';
                          }),
                  child: const Text('Recusar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => _run(l.id, () async {
                            await _links.accept(l.id);
                            return _aggregator
                                ? '${l.name} agora faz parte da equipe.'
                                : 'Pronto! Você agora faz parte de ${l.name}.';
                          }),
                  child: const Text('Aceitar'),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sentTile(ProfessionalLink l) {
    final busy = _busy.contains(l.id);
    return Card(
      key: Key('link-sent-${l.id}'),
      child: ListTile(
        leading: _avatar(l),
        title: Text(l.name),
        subtitle: Text(_withDetail(l, 'Aguardando resposta')),
        trailing: TextButton(
          onPressed: busy
              ? null
              : () => _run(l.id, () async {
                    await _links.cancel(l.id);
                    return _aggregator
                        ? 'Convite cancelado.'
                        : 'Pedido cancelado.';
                  }),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  Widget _activeTile(ProfessionalLink l, int index, int total) {
    final busy = _busy.contains(l.id) || _busy.contains(_reorderKey);
    final detail = _detail(l);
    return Card(
      key: Key('link-active-${l.id}'),
      child: Column(
        children: [
          ListTile(
            leading: _avatar(l),
            title: Text(l.name),
            subtitle: detail == null || detail.isEmpty ? null : Text(detail),
            trailing: PopupMenuButton<String>(
              key: Key('link-menu-${l.id}'),
              enabled: !busy,
              tooltip: 'Mais opções',
              onSelected: (v) {
                switch (v) {
                  case 'up':
                    _move(l, -1);
                  case 'down':
                    _move(l, 1);
                  case 'end':
                    _end(l);
                }
              },
              itemBuilder: (_) => [
                if (_aggregator && index > 0)
                  const PopupMenuItem(
                      value: 'up', child: Text('Mover para cima')),
                if (_aggregator && index < total - 1)
                  const PopupMenuItem(
                      value: 'down', child: Text('Mover para baixo')),
                PopupMenuItem(
                    value: 'end',
                    child: Text(_aggregator
                        ? 'Encerrar vínculo'
                        : 'Sair do estabelecimento')),
              ],
            ),
          ),
          if (_aggregator)
            SwitchListTile(
              key: Key('link-show-${l.id}'),
              dense: true,
              title: const Text('Aparece no meu link'),
              value: l.showOnLink,
              onChanged: busy ? null : (v) => _toggleShow(l, v),
            ),
        ],
      ),
    );
  }
}
