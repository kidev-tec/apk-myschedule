import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

/// Edição do negócio pós-onboarding: nome, segmento e endereço.
/// Serve pros prestadores antigos (adesão antes do F1) adicionarem
/// endereço e pra qualquer um corrigir dados depois.
class EditBusinessPage extends ConsumerStatefulWidget {
  const EditBusinessPage({super.key});

  @override
  ConsumerState<EditBusinessPage> createState() => _EditBusinessPageState();
}

class _EditBusinessPageState extends ConsumerState<EditBusinessPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _districtController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _zipLookingUp = false;
  String? _currentSegment;
  DateTime? _lastZipLookup;

  static const _segments = {
    'beauty': 'Beleza / Estética',
    'barber': 'Barbearia',
    'dental': 'Odontologia',
    'medical': 'Saúde / Consultas',
    'auto_detailing': 'Estética Automotiva',
    'pet_grooming': 'Pet Grooming',
    'veterinary': 'Veterinária',
    'mechanic': 'Mecânica',
    'other': 'Outro',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().dio.get('/me');
      final data = r.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _nameController.text = data['name'] ?? '';
        _currentSegment = data['business_type'] ?? 'other';
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        _streetController.text = addr['street'] ?? '';
        _numberController.text = addr['number'] ?? '';
        _districtController.text = addr['district'] ?? '';
        _cityController.text = addr['city'] ?? '';
        _stateController.text = addr['state'] ?? '';
        _zipController.text = addr['zip'] ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final address = <String, String>{
        'street': _streetController.text.trim(),
        'number': _numberController.text.trim(),
        'district': _districtController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'zip': _zipController.text.trim(),
      }..removeWhere((_, v) => v.isEmpty);

      await ApiClient().dio.patch('/me', data: {
        'business_name': _nameController.text.trim(),
        if (_currentSegment != null) 'business_type': _currentSegment,
        'address': address,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dados do negócio atualizados'),
          backgroundColor: AppColors.success));
      Navigator.of(context).pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? (e.response?.data['error'] as String? ?? 'Não deu pra salvar')
          : 'Não deu pra salvar. Verifica a internet.';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// CEP: máscara 00000-000 e, ao completar 8 dígitos, busca no ViaCEP
  /// e preenche rua/bairro/cidade/UF. Usuário só digita número/complemento.
  Future<void> _onZipChanged(String value) async {
    // máscara
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    var masked = digits;
    if (digits.length > 5) masked = '${digits.substring(0, 5)}-${digits.substring(5, 8)}';
    if (masked != value) {
      _zipController.value = TextEditingValue(
          text: masked, selection: TextSelection.collapsed(offset: masked.length));
    }

    // debounce: só busca 800ms depois da última digitação e com 8 dígitos
    _lastZipLookup = DateTime.now();
    final myLookup = _lastZipLookup;
    if (digits.length != 8 || _zipLookingUp) return;
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted ||
        _lastZipLookup != myLookup ||
        _zipController.text.replaceAll(RegExp(r'[^0-9]'), '') != digits) {
      return;
    }

    setState(() => _zipLookingUp = true);
    try {
      final r = await Dio()
          .get('https://viacep.com.br/ws/$digits/json/');
      if (!mounted) return;
      if (r.data is Map && r.data['erro'] == true) {
        _snack('CEP não encontrado — preenche manualmente');
        return;
      }
      setState(() {
        _streetController.text = r.data['logradouro'] ?? '';
        _districtController.text = r.data['bairro'] ?? '';
        _cityController.text = r.data['localidade'] ?? '';
        _stateController.text = r.data['uf'] ?? '';
      });
    } catch (_) {
      if (mounted) _snack('Não deu pra buscar o CEP — preenche manualmente');
    } finally {
      if (mounted) setState(() => _zipLookingUp = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _districtController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu negócio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Perfil',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Informe o nome' : null,
                    decoration: const InputDecoration(
                      labelText: 'Nome do negócio',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _currentSegment,
                    decoration: const InputDecoration(
                      labelText: 'Segmento',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _segments.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _currentSegment = v),
                  ),
                  const SizedBox(height: 24),
                  Text('Endereço (onde os clientes te encontram)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Aparece no teu link de agendamento público. '
                      'Deixa vazio se atende em todo lugar ou online.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.neutral)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _streetController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Rua',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _numberController,
                          decoration:
                              const InputDecoration(labelText: 'Número'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _districtController,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                              const InputDecoration(labelText: 'Bairro'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _cityController,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                              const InputDecoration(labelText: 'Cidade'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _stateController,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: const InputDecoration(
                              labelText: 'UF', counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _zipController,
                          keyboardType: TextInputType.number,
                          maxLength: 9,
                          onChanged: _onZipChanged,
                          decoration: InputDecoration(
                            labelText: 'CEP',
                            counterText: '',
                            suffixIcon: _zipLookingUp
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  )
                                : const Icon(Icons.travel_explore_outlined),
                            helperText: 'Preenche o resto sozinho',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Salvar alterações'),
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }
}
