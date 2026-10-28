import 'package:flutter/material.dart';

import '../../core/cep/cep_service.dart';
import '../../core/utils/cpf.dart';

/// Origens "como conheceu" (valor da API → rótulo).
const referralSources = <String, String>{
  'indicacao': 'Indicação',
  'instagram': 'Instagram',
  'google': 'Google',
  'passou_na_frente': 'Passou na frente',
  'outro': 'Outro',
};

/// Estado do cadastro complementar do cliente (aniversário, apelido, CPF,
/// como conheceu, consentimento e endereço). Compartilhado entre o
/// formulário de cliente e o "Adicionar cliente" do agendamento.
class ClientProfileData {
  final nickname = TextEditingController();
  final birthday = TextEditingController(); // DD/MM/AAAA
  final cpf = TextEditingController();
  final zip = TextEditingController();
  final street = TextEditingController();
  final number = TextEditingController();
  final complement = TextEditingController();
  final district = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();
  String? referralSource;
  bool marketingConsent = false;

  /// Preenche a partir do JSON da API (GET /clients/:id).
  void loadFrom(Map<String, dynamic> j) {
    nickname.text = j['nickname'] ?? '';
    if (j['birthday'] != null) {
      final dt = DateTime.parse(j['birthday'] as String);
      birthday.text = _ddmmyyyy(dt);
    }
    cpf.text = formatCpf(j['cpf'] as String?);
    referralSource = referralSources.containsKey(j['referral_source'])
        ? j['referral_source'] as String
        : null;
    marketingConsent = j['marketing_consent'] == true;
    final a = j['address'];
    if (a is Map) {
      zip.text = formatCep(a['zip'] as String?);
      street.text = a['street'] ?? '';
      number.text = a['number'] ?? '';
      complement.text = a['complement'] ?? '';
      district.text = a['district'] ?? '';
      city.text = a['city'] ?? '';
      state.text = a['state'] ?? '';
    }
  }

  /// Campos pro POST/PATCH. Sempre envia tudo: o PATCH substitui o cadastro.
  Map<String, dynamic> toJson() {
    DateTime? b;
    final parts = birthday.text.split('/');
    if (parts.length == 3) {
      b = DateTime(
          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    }
    return {
      'nickname': nickname.text.trim(),
      if (b != null) 'birthday': b.toIso8601String().split('T')[0],
      'cpf': onlyDigits(cpf.text),
      'referral_source': referralSource,
      'marketing_consent': marketingConsent,
      'address': {
        'zip': onlyDigits(zip.text),
        'street': street.text.trim(),
        'number': number.text.trim(),
        'complement': complement.text.trim(),
        'district': district.text.trim(),
        'city': city.text.trim(),
        'state': state.text.trim().toUpperCase(),
      },
    };
  }

  void dispose() {
    for (final c in [
      nickname,
      birthday,
      cpf,
      zip,
      street,
      number,
      complement,
      district,
      city,
      state
    ]) {
      c.dispose();
    }
  }

  static String _ddmmyyyy(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

/// Campos do cadastro complementar. Deve ficar dentro de um [Form]
/// (o CPF tem validador).
class ClientProfileFields extends StatefulWidget {
  final ClientProfileData data;
  final CepService? cepService;

  const ClientProfileFields({super.key, required this.data, this.cepService});

  @override
  State<ClientProfileFields> createState() => _ClientProfileFieldsState();
}

class _ClientProfileFieldsState extends State<ClientProfileFields> {
  late final CepService _cep = widget.cepService ?? CepService();
  bool _searching = false;
  String? _cepMessage;
  String _lastZip = '';

  ClientProfileData get d => widget.data;

  Future<void> _lookupCep() async {
    final zip = onlyDigits(d.zip.text);
    if (zip.length != 8 || zip == _lastZip) return;
    _lastZip = zip;
    setState(() {
      _searching = true;
      _cepMessage = null;
    });
    try {
      final r = await _cep.lookup(zip);
      if (!mounted) return;
      setState(() {
        if (r == null) {
          _cepMessage = 'CEP não encontrado. Preenche o endereço à mão.';
        } else {
          d.street.text = r.street;
          d.district.text = r.district;
          d.city.text = r.city;
          d.state.text = r.state;
        }
      });
    } on CepException catch (e) {
      if (mounted) setState(() => _cepMessage = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
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
      setState(() => d.birthday.text = ClientProfileData._ddmmyyyy(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('client-nickname'),
          controller: d.nickname,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Como prefere ser chamado (opcional)',
            helperText: 'Usado nas mensagens de WhatsApp',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        gap,
        TextFormField(
          key: const Key('client-birthday'),
          controller: d.birthday,
          readOnly: true,
          onTap: _pickBirthday,
          decoration: const InputDecoration(
            labelText: 'Aniversário (opcional)',
            hintText: 'DD/MM/AAAA',
            prefixIcon: Icon(Icons.cake_outlined),
            suffixIcon: Icon(Icons.calendar_today),
          ),
        ),
        gap,
        TextFormField(
          key: const Key('client-cpf'),
          controller: d.cpf,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'CPF (opcional)',
            prefixIcon: Icon(Icons.assignment_ind_outlined),
          ),
          validator: (v) => (v == null || v.trim().isEmpty || isValidCpf(v))
              ? null
              : 'CPF inválido',
        ),
        gap,
        DropdownButtonFormField<String>(
          key: const Key('client-referral'),
          initialValue: d.referralSource,
          decoration: const InputDecoration(
            labelText: 'Como conheceu (opcional)',
            prefixIcon: Icon(Icons.campaign_outlined),
          ),
          items: [
            for (final e in referralSources.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => d.referralSource = v),
        ),
        gap,
        Text('Endereço (opcional)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('client-zip'),
          controller: d.zip,
          keyboardType: TextInputType.number,
          onChanged: (v) {
            if (onlyDigits(v).length == 8) _lookupCep();
          },
          decoration: InputDecoration(
            labelText: 'CEP',
            hintText: '00000-000',
            prefixIcon: const Icon(Icons.location_on_outlined),
            helperText: _cepMessage ?? 'Digite o CEP pra preencher o endereço',
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Buscar CEP',
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      _lastZip = '';
                      _lookupCep();
                    },
                  ),
          ),
        ),
        gap,
        TextFormField(
          key: const Key('client-street'),
          controller: d.street,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Rua'),
        ),
        Row(children: [
          Expanded(
            child: TextFormField(
              key: const Key('client-number'),
              controller: d.number,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Número'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: const Key('client-complement'),
              controller: d.complement,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Complemento'),
            ),
          ),
        ]),
        TextFormField(
          key: const Key('client-district'),
          controller: d.district,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Bairro'),
        ),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              key: const Key('client-city'),
              controller: d.city,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Cidade'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const Key('client-state'),
              controller: d.state,
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'UF'),
            ),
          ),
        ]),
        SwitchListTile(
          key: const Key('client-consent'),
          contentPadding: EdgeInsets.zero,
          value: d.marketingConsent,
          onChanged: (v) => setState(() => d.marketingConsent = v),
          title: const Text('Aceita receber mensagens'),
          subtitle: const Text('Promoções e novidades pelo WhatsApp (LGPD)'),
        ),
      ],
    );
  }
}
