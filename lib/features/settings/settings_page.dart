import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/segment/segment_preset.dart';
import '../../core/auth/auth_controller.dart';
import '../../theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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
      if (end == null || end.isAfter(DateTime.now()))
        return AppColors.primaryOf(context);
    }
    return AppColors.error;
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
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
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

          // Segmento do negócio — definido no onboarding, VINCULADO à conta
          // (produto: não troca depois de configurado; serviços/tema se apoiam nele)
          if (_me != null)
            Card(
              child: ListTile(
                leading: Icon(
                    SegmentPreset.byId(
                            _me?['business_type'] as String? ?? 'beauty')
                        .icon,
                    color: AppColors.primaryOf(context)),
                title: const Text('Segmento'),
                subtitle: Text(SegmentPreset.byId(
                        _me?['business_type'] as String? ?? 'beauty')
                    .label),
              ),
            ),
          const SizedBox(height: 8),

          // Link público de agendamento (RF-07)
          if (_me != null && _publicUrl != null)
            Card(
              child: ListTile(
                leading:
                    Icon(Icons.public, color: AppColors.primaryOf(context)),
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
                    backgroundColor: AppColors.primaryOf(context),
                    child: Text(_initial(auth.user),
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
