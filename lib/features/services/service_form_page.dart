import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

class ServiceFormPage extends ConsumerStatefulWidget {
  final String? serviceId;

  const ServiceFormPage({super.key, this.serviceId});

  @override
  ConsumerState<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends ConsumerState<ServiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _priceController = TextEditingController();

  bool _loading = false;
  bool get _isEditing => widget.serviceId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadService();
  }

  Future<void> _loadService() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/services/\${widget.serviceId}');
      final data = resp.data;
      _nameController.text = data['name'] ?? '';
      _durationController.text =
          (data['duration_min'] ?? data['durationMin'] ?? 60).toString();
      final cents = data['price_cents'] ?? data['priceCents'] ?? 0;
      _priceController.text = (cents is num ? cents / 100 : 0.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    } catch (e) {
      debugPrint('[service_form] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final dur = int.tryParse(_durationController.text);
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (dur == null || price == null) return;

    final data = {
      'name': _nameController.text.trim(),
      'duration_min': dur,
      'price_cents': (price * 100).round(),
    };

    try {
      final api = ApiClient();
      if (_isEditing) {
        await api.dio.patch('/services/\${widget.serviceId}', data: data);
      } else {
        await api.dio.post('/services', data: data);
      }
      if (mounted) context.go('/services');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Falha: \$e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(_isEditing ? 'Editar serviço' : 'Novo serviço')),
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
                      prefixIcon: Icon(Icons.content_cut_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nome é obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duração (min) *',
                            hintText: '60',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n < 5 || n > 600 || n % 5 != 0) {
                              return '5–600 minutos, de 5 em 5';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Preço (R\$) *',
                            hintText: '80,00',
                            prefixIcon: Icon(Icons.attach_money_outlined),
                          ),
                          validator: (v) {
                            final n =
                                double.tryParse((v ?? '').replaceAll(',', '.'));
                            if (n == null || n <= 0) return 'Inválido';
                            return null;
                          },
                        ),
                      ),
                    ],
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
                            _isEditing ? 'Salvar alterações' : 'Criar serviço'),
                  ),
                ],
              ),
            ),
    );
  }
}
