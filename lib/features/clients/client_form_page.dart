import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/cep/cep_service.dart';
import '../../core/utils/phone_br.dart';
import '../../theme/app_theme.dart';
import 'client_profile_fields.dart';
import '../../core/widgets/home_action.dart';

class ClientFormPage extends ConsumerStatefulWidget {
  final String? clientId; // null = novo
  final ApiClient? api; // DI pra testes (mock da rede)
  final CepService? cepService; // DI pra testes (busca de CEP)

  const ClientFormPage({super.key, this.clientId, this.api, this.cepService});

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  /// Aniversário, apelido, CPF, como conheceu, consentimento e endereço.
  final _profile = ClientProfileData();

  /// Informações sobre o cliente (privadas do prestador).
  final _notesController = TextEditingController();

  bool _loading = false;
  bool get _isEditing => widget.clientId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadClient();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _profile.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadClient() async {
    setState(() => _loading = true);
    try {
      final api = widget.api ?? ApiClient();
      final resp = await api.dio.get('/clients/${widget.clientId}');
      final data = resp.data;
      _nameController.text = data['name'];
      _phoneController.text =
          phoneForDisplay(data['phone_e164'] ?? data['phoneE164'] ?? '');
      _emailController.text = data['email'] ?? '';
      _notesController.text = data['notes'] ?? '';
      _profile.loadFrom(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      debugPrint('[client_form] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final data = {
      'name': _nameController.text.trim(),
      'phone_e164': normalizePhoneBr(_phoneController.text),
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      ..._profile.toJson(),
      // sempre enviado: o PATCH substitui tudo (sem o campo, apagaria)
      'notes': _notesController.text.trim(),
    };

    try {
      final api = widget.api ?? ApiClient();
      if (_isEditing) {
        await api.dio.patch('/clients/${widget.clientId}', data: data);
      } else {
        await api.dio.post('/clients', data: data);
      }
      if (!mounted) return;
      // Volta pra tela de origem (lista/configurações) preservando a pilha;
      // sem origem (deep link), cai na lista.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/clients');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não consegui salvar: ${humanError(e)}'),
              backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Editar cliente' : 'Novo cliente'),
          actions: const [HomeAction()]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 +
                        MediaQuery.of(context).padding.bottom +
                        MediaQuery.of(context).viewInsets.bottom),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nome é obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    // (11) 98765-4321 enquanto digita
                    inputFormatters: [PhoneBrInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp *',
                      hintText: '(11) 99999-9999',
                      helperText:
                          'Com DDD — o código 55 do Brasil é adicionado automaticamente',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => normalizePhoneBr(v ?? '').isEmpty
                        ? 'Telefone inválido (informe DDD)'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail (opcional)',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClientProfileFields(
                      data: _profile, cepService: widget.cepService),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('client-notes'),
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Informações / Observações (opcional)',
                      hintText:
                          'Ex.: alergias, preferências, como gosta do corte',
                      helperText: 'Só você vê — o cliente não recebe.',
                      prefixIcon: Icon(Icons.person_search_outlined),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            _isEditing ? 'Salvar alterações' : 'Criar cliente'),
                  ),
                ],
              ),
            ),
    );
  }
}
