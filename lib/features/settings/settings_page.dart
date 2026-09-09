import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
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
      if (mounted) setState(() => _me = Map<String, dynamic>.from(resp.data));
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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

          // Account section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(
                        (auth.user?.displayName ?? auth.user?.email ?? 'U')[0]
                            .toUpperCase(),
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
