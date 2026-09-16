import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'logo_service.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/segment/segment_preset.dart';
import '../../core/auth/auth_controller.dart';
import '../../theme/app_theme.dart';
import 'gcal_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Map<String, dynamic>? _me;
  String? _slug;
  bool? _gcalConnected; // null = verificando
  bool _gcalBusy = false;
  bool _logoBusy = false;
  final _gcal = GCalService();
  final _logoService = LogoService();

  /// Avatar com a logo atual (se houver) ou ícone padrão.
  Widget _logoLeading() {
    final logoUrl = _me?['logo_url'] as String?;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: AppColors.primaryOf(context),
        backgroundImage: NetworkImage(LogoService.absoluteUrl(logoUrl)),
      );
    }
    return Icon(Icons.storefront, color: AppColors.primaryOf(context));
  }

  /// Abre o seletor, valida e envia a logo. Mensagens sempre humanas.
  Future<void> _pickAndUploadLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    final mime = picked.mimeType ??
        (picked.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');
    setState(() => _logoBusy = true);
    try {
      final result = await _logoService.upload(File(picked.path), mime);
      if (!mounted) return;
      if (result.logoUrl != null) {
        await _loadMe();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo atualizada!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMessage ?? 'Não deu. Tenta de novo')));
      }
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

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
    _loadGCalStatus();
  }

  Future<void> _loadGCalStatus() async {
    final connected = await _gcal.isConnected();
    if (!mounted) return;
    setState(() => _gcalConnected = connected);
  }

  /// Conecta (abre consent Google) ou desconecta, com diálogo de confirmação
  /// no disconnect — leigo não pode cortar a integração sem entender o efeito.
  Future<void> _toggleGCal() async {
    if (_gcalConnected == true) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Desconectar o Google Calendar?'),
          content: const Text(
              'Os agendamentos novos não vão mais aparecer na tua agenda Google. '
              'Os que já entraram, continuam lá.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Manter conectado')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Desconectar')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => _gcalBusy = true);
    try {
      if (_gcalConnected == true) {
        await _gcal.disconnect();
        if (!mounted) return;
        setState(() => _gcalConnected = false);
      } else {
        final ok = await _gcal.startConnect();
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Não consegui abrir o navegador. Tenta de novo')));
        }
        // Ao voltar do browser, o usuário reabre Configurações e o status
        // recarrega (initState). Refresh leve ao retomar:
        _loadGCalStatus();
      }
    } catch (e) {
      debugPrint('[settings] gcal toggle: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Deu erro na conexão. Tenta de novo')));
      }
    } finally {
      if (mounted) setState(() => _gcalBusy = false);
    }
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
      if (end == null || end.isAfter(DateTime.now())) {
        return AppColors.primaryOf(context);
      }
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

          // Logo do estabelecimento (upload próprio, servido pela API)
          if (_me != null)
            Card(
              child: ListTile(
                leading: _logoLeading(),
                title: const Text('Logo do estabelecimento'),
                subtitle: const Text('Aparece no teu link de agendamento'),
                trailing: _logoBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _logoBusy ? null : _pickAndUploadLogo,
              ),
            ),
          const SizedBox(height: 8),

          // Meu negócio (RF-02): gerenciar serviços a qualquer momento —
          // não só no onboarding. O onboarding define o segmento; aqui o
          // prestador mantém o catálogo (criar, editar preço/duração, arquivar).
          if (_me != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.content_cut,
                    color: AppColors.primaryOf(context)),
                title: const Text('Meus serviços'),
                subtitle:
                    const Text('Adicionar, editar preço e duração, arquivar'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/services'),
              ),
            ),
          const SizedBox(height: 8),

          if (_me != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.schedule,
                    color: AppColors.primaryOf(context)),
                title: const Text('Horário de funcionamento'),
                subtitle: const Text('Quando tu atende, dia a dia'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/working-hours'),
              ),
            ),
          const SizedBox(height: 8),

          // Google Calendar (RF-08): espelha agendamentos confirmados na
          // agenda do profissional — lembretes herdados do Calendar dele.
          if (_me != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.event_available,
                    color: _gcalConnected == true
                        ? Colors.green
                        : AppColors.primaryOf(context)),
                title: const Text('Google Calendar'),
                subtitle: Text(_gcalConnected == null
                    ? 'Verificando…'
                    : _gcalConnected == true
                        ? 'Conectado — agendamentos confirmados vão pra tua agenda'
                        : 'Conectar pra ver agendamentos na tua agenda Google'),
                trailing: _gcalBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_gcalConnected == true
                        ? Icons.link_off
                        : Icons.chevron_right),
                onTap: _gcalBusy ? null : _toggleGCal,
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
                  onTap: () => context
                      .push('/terms', extra: {'isPrivacy': true}),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Termos de uso'),
                  onTap: () => context.push('/terms'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
