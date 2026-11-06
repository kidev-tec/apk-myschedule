import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

/// Módulo agregador (API 0026, docs/plano-agregador.md): tipo da conta e
/// códigos, a partir do GET /me (`account_kind`, `pro_code`,
/// `aggregator_code`).
///
/// - Independente: mostra o código de profissional (P-) para o
///   estabelecimento convidar e oferece "Transformar em estabelecimento".
/// - Estabelecimento: mostra o código do estabelecimento (E-) para os
///   profissionais pedirem para entrar e oferece voltar a independente
///   (a API recusa com 409 se ainda houver vínculos — D1).
class AccountKindCard extends StatefulWidget {
  final Map<String, dynamic> me;
  final ApiClient? api;

  /// Chamado depois de trocar o tipo da conta (recarregar o /me).
  final Future<void> Function() onChanged;

  /// Abre a tela de vínculos (padrão: rota /links). Injetável em teste.
  final VoidCallback? onOpenLinks;

  const AccountKindCard({
    super.key,
    required this.me,
    required this.onChanged,
    this.api,
    this.onOpenLinks,
  });

  @override
  State<AccountKindCard> createState() => _AccountKindCardState();
}

class _AccountKindCardState extends State<AccountKindCard> {
  bool _busy = false;

  bool get _aggregator => widget.me['account_kind'] == 'aggregator';
  String? get _proCode => widget.me['pro_code'] as String?;
  String? get _aggCode => widget.me['aggregator_code'] as String?;
  String get _name => widget.me['name'] as String? ?? '';

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Código $code copiado')));
  }

  Future<void> _share(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    final text = _aggregator
        ? 'Para entrar${_name.isEmpty ? '' : ' no $_name'} pelo Agenva, '
            'use o código do estabelecimento: $code'
        : 'Meu código de profissional no Agenva: $code';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _changeKind() async {
    final toAggregator = !_aggregator;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(toAggregator
            ? 'Transformar em estabelecimento?'
            : 'Voltar a ser profissional independente?'),
        content: Text(toAggregator
            ? 'Você ganha um código para os profissionais pedirem para entrar '
                'e, no seu link, o cliente escolhe com quem quer marcar. '
                'Sua agenda, serviços e clientes continuam como estão.'
            : 'O código do estabelecimento deixa de valer e o seu link volta '
                'a mostrar só a sua agenda.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(toAggregator ? 'Transformar' : 'Voltar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = widget.api ?? ApiClient();
      await api.dio.put('/me/account-kind', data: {
        'account_kind': toAggregator ? 'aggregator' : 'independent',
      });
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(toAggregator
              ? 'Pronto! Agora você é um estabelecimento.'
              : 'Pronto! Você voltou a ser profissional independente.'),
          backgroundColor: Colors.green));
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Não foi possível mudar agora. Tente novamente.';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _codeTile({
    required String title,
    required String code,
    required String hint,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryOf(context)),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copiar código',
                onPressed: () => _copy(code),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Compartilhar código',
                onPressed: () => _share(code),
              ),
            ],
          ),
          Text(hint),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aggCode = _aggCode;
    final proCode = _proCode;
    return Card(
      child: Column(
        children: [
          if (_aggregator && aggCode != null)
            _codeTile(
              title: 'Código do estabelecimento',
              code: aggCode,
              hint: 'Envie para os profissionais pedirem para entrar.',
              icon: Icons.groups_outlined,
            ),
          if (!_aggregator && proCode != null)
            _codeTile(
              title: 'Seu código de profissional',
              code: proCode,
              hint: 'Envie para um estabelecimento te convidar.',
              icon: Icons.badge_outlined,
            ),
          ListTile(
            key: const Key('open-links'),
            leading: Icon(
                _aggregator
                    ? Icons.groups
                    : Icons.store_mall_directory_outlined,
                color: AppColors.primaryOf(context)),
            title:
                Text(_aggregator ? 'Profissionais' : 'Meus estabelecimentos'),
            subtitle: Text(_aggregator
                ? 'Convidar, aceitar pedidos e organizar o seu link'
                : 'Estabelecimentos em que você atende'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenLinks ?? () => context.push('/links'),
          ),
          ListTile(
            leading: Icon(
                _aggregator ? Icons.person_outline : Icons.storefront_outlined,
                color: AppColors.primaryOf(context)),
            title: Text(_aggregator
                ? 'Voltar a ser profissional independente'
                : 'Transformar em estabelecimento'),
            subtitle: Text(_aggregator
                ? 'Só é possível sem profissionais vinculados'
                : 'Tenho profissionais atendendo comigo'),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _changeKind,
          ),
        ],
      ),
    );
  }
}
