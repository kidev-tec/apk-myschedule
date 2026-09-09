import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

class ClientFormPage extends ConsumerStatefulWidget {
  final String? clientId; // null = novo

  const ClientFormPage({super.key, this.clientId});

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _birthdayController = TextEditingController();

  bool _loading = false;
  bool get _isEditing => widget.clientId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadClient();
  }

  Future<void> _loadClient() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/clients/\${widget.clientId}');
      final data = resp.data;
      _nameController.text = data['name'];
      _phoneController.text = data['phone_e164'] ?? data['phoneE164'] ?? '';
      _emailController.text = data['email'] ?? '';
      if (data['birthday'] != null) {
        final dt = DateTime.parse(data['birthday']);
        _birthdayController.text = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    DateTime? birthday;
    if (_birthdayController.text.isNotEmpty) {
      final parts = _birthdayController.text.split('/');
      if (parts.length == 3) {
        birthday = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    }

    final data = {
      'name': _nameController.text.trim(),
      'phone_e164': _phoneController.text.trim(),
      if (_emailController.text.trim().isNotEmpty) 'email': _emailController.text.trim(),
      if (birthday != null) 'birthday': birthday.toIso8601String().split('T')[0],
    };

    try {
      final api = ApiClient();
      if (_isEditing) {
        await api.dio.patch('/clients/\${widget.clientId}', data: data);
      } else {
        await api.dio.post('/clients', data: data);
      }
      if (mounted) context.go('/clients');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha: \$e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1920),
      lastDate: now,
    );
    if (picked != null) {
      _birthdayController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar cliente' : 'Novo cliente')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nome é obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp *',
                      hintText: '(11) 99999-9999',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Telefone é obrigatório' : null,
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
                  TextFormField(
                    controller: _birthdayController,
                    readOnly: true,
                    onTap: _pickBirthday,
                    decoration: const InputDecoration(
                      labelText: 'Aniversário (opcional)',
                      hintText: 'DD/MM/AAAA',
                      prefixIcon: Icon(Icons.cake_outlined),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEditing ? 'Salvar alterações' : 'Criar cliente'),
                  ),
                ],
              ),
            ),
    );
  }
}
