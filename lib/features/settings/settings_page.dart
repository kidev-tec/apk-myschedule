import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/segment/segment_preset.dart';
import '../../main.dart' show segmentPresetProvider;
import '../../core/auth/auth_controller.dart';
import '../../theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _gcalConnected = false;
  bool _loadingGcal = false;
  Map<String, dynamic>? _me;
  String? _slug;

  /// Link público do negócio. Em dev usa o host da API; o path /p/<slug> é
  /// servido pela própria API (RF-07).
  String? get _publicUrl {
    if (_slug == null) return null;
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/v1/?$'), '');
    return '$base/p/$_slug';
  }

  @override
  void initState() {
    super.initState();
    _checkGcalStatus();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/me');
      if (!mounted) return;
      setState(() {
        _me = Map<String, dynamic>.from(resp.data);
        _slug = resp.data['slug'] as String?;
      });
    } catch (e) {
      debugPrint('[settings] erro: $e');
    }
  }

  Future<void> _sharePublicLink() async {
    if (_publicUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _publicUrl!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Link copiado! Cola no teu WhatsApp ou Instagram')),
      );
    }
  }

  Future<void> _changeSegment() async {
    final current = _me?['business_type'] as String?;
    final picked = await showModalBottomSheet<SegmentPreset>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Teu segmento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Muda as cores e os serviços sugeridos do app',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            ...SegmentPreset.all.map(
              (s) => ListTile(
                leading: Icon(s.icon, color: AppColors.primary),
                title: Text(s.label),
                trailing: current == s.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == current) return;
    try {
      final api = ApiClient();
      await api.dio.patch('/me', data: {'business_type': picked.id});
      if (!mounted) return;
      setState(() => _me?['business_type'] = picked.id);
      // tema global reage na hora
      ProviderScope.containerOf(context)
          .read(segmentPresetProvider.notifier)
          .state = picked;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Segmento alterado pra ${picked.label}')));
    } catch (e) {
      debugPrint('[settings] falha ao trocar segmento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não consegui trocar o segmento'),
            backgroundColor: AppColors.error));
      }
    }
  }

  String get _subscriptionLabel {
    final status = _me?['subscription_status'] as String? ?? 'trial';
    final trialEnds = _me?['trial_ends_at'] as String?;
    switch (status) {
      case 'active':
        return 'Assinatura ativa';
      case 'canceled':
        return 'Assinatura cancelada';
      case 'past_due':
        return 'Pagamento pendente';
      default: // trial
        if (trialEnds == null) return 'Período de teste';
        final end = DateTime.tryParse(trialEnds);
        if (end == null) return 'Período de teste';
        final days = end.difference(DateTime.now()).inDays;
        return days >= 0
            ? "Teste: $days dia${days == 1 ? '' : 's'} restantes"
            : 'Teste encerrado';
    }
  }

  Color get _subscriptionColor {
    final status = _me?['subscription_status'] as String? ?? 'trial';
    if (status == 'active') return Colors.green;
    if (status == 'trial') {
      final end = DateTime.tryParse(_me?['trial_ends_at'] as String? ?? '');
      if (end == null || end.isAfter(DateTime.now())) return AppColors.primary;
    }
    return AppColors.error;
  }

  Future<void> _checkGcalStatus() async {
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/settings/google-calendar/status');
      setState(() => _gcalConnected = resp.data['connected'] ?? false);
    } catch (e) {
      debugPrint('[settings] erro: $e');
    }
  }

  Future<void> _connectGcal() async {
    setState(() => _loadingGcal = true);
    try {
      final api = ApiClient();
      final resp = await api.dio.post('/settings/google-calendar/connect');
      final authUrl = resp.data['auth_url'];
      // Launch browser for OAuth
      // For now just show the URL
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Conectar Google Calendar'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Abre este link no navegador e autoriza o acesso:'),
                const SizedBox(height: 12),
                SelectableText(authUrl,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Copiei, vou lá')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Falha: \$e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _loadingGcal = false);
  }

  Future<void> _disconnectGcal() async {
    try {
      final api = ApiClient();
      await api.dio.delete('/settings/google-calendar');
      setState(() => _gcalConnected = false);
    } catch (e) {
      debugPrint('[settings] erro: $e');
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair da conta?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authControllerProvider.notifier).signOut();
      if (mounted) context.go('/login');
    }
  }

  /// Inicial do avatar — tolerante a nome/email vazios ou whitespace.
  /// ('' ?? fallback NÃO cai no fallback pois '' não é null; ''[0] estoura
  /// RangeError: Valid value range is empty: 0 — o crash que víamos.)
  String _initial(dynamic user) {
    final raw = (user?.displayName ?? '').trim().isNotEmpty
        ? user!.displayName!.trim()
        : (user?.email ?? '').trim();
    return raw.isNotEmpty ? raw[0].toUpperCase() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        // padding explícito em ListView SOBRESCREVE o MediaQuery.padding —
        // por isso os últimos itens ficavam atrás da barra de gestos mesmo
        // com o builder global. Somo o bottom real aqui.
        padding: EdgeInsets.fromLTRB(16, 16, 16,
            16 + MediaQuery.of(context).padding.bottom),
        children: [
          // Assinatura (RF-14)
          if (_me != null)
            Card(
              child: ListTile(
                leading:
                    Icon(Icons.workspace_premium, color: _subscriptionColor),
                title: Text(_subscriptionLabel),
                subtitle: Text(_me?['name'] as String? ?? ''),
              ),
            ),
          const SizedBox(height: 8),

          // Segmento do negócio (troca tema na hora)
          if (_me != null)
            Card(
              child: ListTile(
                leading: Icon(
                    SegmentPreset.byId(
                            _me?['business_type'] as String? ?? 'beauty')
                        .icon,
                    color: AppColors.primary),
                title: const Text('Teu segmento'),
                subtitle: Text(SegmentPreset.byId(
                        _me?['business_type'] as String? ?? 'beauty')
                    .label),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changeSegment,
              ),
            ),
          const SizedBox(height: 8),

          // Link público de agendamento (RF-07)
          if (_me != null && _publicUrl != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.public, color: AppColors.primary),
                title: const Text('Teu link de agendamento'),
                subtitle: Text(
                  _publicUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Compartilhar link',
                  onPressed: _sharePublicLink,
                ),
              ),
            ),
          const SizedBox(height: 8),

          // Account section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(
                        _initial(auth.user),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(
                    auth.user?.displayName ?? 'Usuário',
                  ),
                  subtitle: Text(auth.user?.email ?? ''),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.error),
                  title: const Text('Sair da conta',
                      style: TextStyle(color: AppColors.error)),
                  onTap: _signOut,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Google Calendar section
          Text('Google Calendar',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Espelha teus agendamentos no Calendar — 2 toques',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.neutral)),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _gcalConnected ? Icons.check_circle : Icons.cloud_off,
                    color: _gcalConnected ? Colors.green : AppColors.neutral,
                  ),
                  title: Text(_gcalConnected ? 'Conectado' : 'Desconectado'),
                  subtitle: Text(_gcalConnected
                      ? 'Agendamentos sincronizados automaticamente'
                      : 'Toque em conectar pra autorizar (OAuth 2 toques)'),
                  trailing: _loadingGcal
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : FilledButton(
                          onPressed:
                              _gcalConnected ? _disconnectGcal : _connectGcal,
                          style: FilledButton.styleFrom(
                            backgroundColor: _gcalConnected
                                ? AppColors.error
                                : AppColors.primary,
                          ),
                          child:
                              Text(_gcalConnected ? 'Desconectar' : 'Conectar'),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App info
          Text('App', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Versão'),
                  subtitle: Text('1.0.0-dev'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de privacidade'),
                  onTap: () {
                    // TODO
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Termos de uso'),
                  onTap: () {
                    // TODO
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
