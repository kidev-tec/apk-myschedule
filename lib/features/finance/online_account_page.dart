import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/widgets/home_action.dart';
import '../../theme/app_theme.dart';
import 'finance_api.dart';
import 'money.dart';
import 'online_models.dart';

/// Recebimento online (F5-11, RF-F13): ativa a subconta Asaas do negócio e
/// mostra a situação (em análise, aprovada, recusada).
class OnlineAccountPage extends ConsumerStatefulWidget {
  const OnlineAccountPage({super.key});

  @override
  ConsumerState<OnlineAccountPage> createState() => _OnlineAccountPageState();
}

class _OnlineAccountPageState extends ConsumerState<OnlineAccountPage> {
  late Future<OnlineAccount> _future = _load();

  Future<OnlineAccount> _load() => ref.read(financeApiProvider).onlineAccount();

  void _reload() {
    setState(() {
      // erro tratado pelo FutureBuilder; .ignore() evita o aviso de erro
      // "não tratado" entre o setState e o próximo build
      _future = _load()..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recebimento online'),
        actions: const [HomeAction()],
      ),
      body: FutureBuilder<OnlineAccount>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(humanError(snap.error!),
                    style: const TextStyle(color: AppColors.error)),
                TextButton(
                    onPressed: _reload, child: const Text('Tentar de novo')),
              ]),
            );
          }
          final a = snap.data!;
          if (!a.available) {
            return const _Message(
              key: Key('online-unavailable'),
              icon: Icons.schedule,
              title: 'Em breve',
              text: 'O recebimento online ainda não está disponível. '
                  'Enquanto isso, registre os pagamentos pelo botão Receber.',
            );
          }
          return switch (a.status) {
            'pending' => _Message(
                key: const Key('online-pending'),
                icon: Icons.hourglass_top,
                title: 'Cadastro em análise no Asaas',
                text: 'Enviamos um e-mail do Asaas para você criar a senha e '
                    'mandar os documentos (identidade e selfie). Assim que for '
                    'aprovado, o botão "Cobrar pelo link" aparece nos '
                    'agendamentos.',
                action: TextButton.icon(
                  key: const Key('online-refresh'),
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Verificar de novo'),
                ),
              ),
            'approved' => const _Message(
                key: Key('online-approved'),
                icon: Icons.check_circle,
                color: AppColors.success,
                title: 'Recebimento online ativo',
                text: 'Abra um agendamento e toque em "Cobrar pelo link". O '
                    'cliente paga por Pix, cartão ou boleto, o dinheiro cai na '
                    'sua conta Asaas e o pagamento entra sozinho no Agenva.',
              ),
            'rejected' => const _Message(
                key: Key('online-rejected'),
                icon: Icons.error_outline,
                color: AppColors.error,
                title: 'Cadastro não aprovado',
                text: 'O Asaas não aprovou o cadastro. Veja o e-mail que eles '
                    'enviaram com o motivo ou fale com o suporte do Agenva.',
              ),
            _ => _ActivateForm(
                onDone: _reload,
                api: ref.read(financeApiProvider),
              ),
          };
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color? color;
  final Widget? action;
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(24), children: [
      Icon(icon, size: 56, color: color ?? AppColors.primaryOf(context)),
      const SizedBox(height: 12),
      Text(title,
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]);
  }
}

/// Formulário de ativação (dados exigidos pelo Asaas para abrir a subconta).
class _ActivateForm extends StatefulWidget {
  final FinanceApi api;
  final VoidCallback onDone;
  const _ActivateForm({required this.api, required this.onDone});

  @override
  State<_ActivateForm> createState() => _ActivateFormState();
}

class _ActivateFormState extends State<_ActivateForm> {
  final _form = GlobalKey<FormState>();
  final _doc = TextEditingController();
  final _birth = TextEditingController();
  final _phone = TextEditingController();
  final _income = TextEditingController();
  final _cep = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _complement = TextEditingController();
  final _district = TextEditingController();
  String _companyType = 'MEI';
  bool _saving = false;
  String? _error;

  static const _companyTypes = {
    'MEI': 'MEI',
    'LIMITED': 'Limitada (LTDA)',
    'INDIVIDUAL': 'Empresário individual',
    'ASSOCIATION': 'Associação',
  };

  @override
  void initState() {
    super.initState();
    _doc.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [
      _doc,
      _birth,
      _phone,
      _income,
      _cep,
      _street,
      _number,
      _complement,
      _district
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _digits(String v) => v.replaceAll(RegExp(r'\D'), '');
  bool get _isCnpj => _digits(_doc.text).length > 11;

  /// "dd/mm/aaaa" → "aaaa-mm-dd"; inválida → null.
  static String? _isoDate(String v) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v.trim());
    if (m == null) return null;
    final d = DateTime.tryParse('${m[3]}-${m[2]}-${m[1]}');
    if (d == null || d.day != int.parse(m[1]!)) return null;
    return '${m[3]}-${m[2]}-${m[1]}';
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.activateOnline(OnlineActivation(
        cpfCnpj: _digits(_doc.text),
        birthDate: _isCnpj ? null : _isoDate(_birth.text),
        companyType: _isCnpj ? _companyType : null,
        mobilePhone: _digits(_phone.text),
        incomeCents: parseMoney(_income.text) ?? 0,
        postalCode: _digits(_cep.text),
        address: _street.text.trim(),
        addressNumber: _number.text.trim(),
        complement: _complement.text,
        province: _district.text.trim(),
      ));
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = humanError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration dec(String label, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint);
    final digitsOnly = [FilteringTextInputFormatter.allow(RegExp(r'[\d./-]'))];
    // SingleChildScrollView (não ListView): campos fora da tela continuam
    // construídos e são validados pelo Form
    return Form(
      key: _form,
      child: SingleChildScrollView(
        key: const Key('online-form'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Receba por Pix, cartão ou boleto',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Vamos abrir uma conta Asaas em seu nome. O dinheiro das cobranças '
              'cai nessa conta, e o Asaas vai pedir seus documentos por e-mail. '
              'Os dados abaixo vão só para o Asaas.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('online-doc'),
              controller: _doc,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: dec('CPF ou CNPJ'),
              validator: (v) {
                final n = _digits(v ?? '').length;
                return n == 11 || n == 14 ? null : 'CPF ou CNPJ inválido';
              },
            ),
            if (_isCnpj)
              DropdownButtonFormField<String>(
                key: const Key('online-company-type'),
                initialValue: _companyType,
                decoration: dec('Tipo de empresa'),
                items: [
                  for (final e in _companyTypes.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _companyType = v ?? 'MEI'),
              )
            else
              TextFormField(
                key: const Key('online-birth'),
                controller: _birth,
                keyboardType: TextInputType.datetime,
                decoration: dec('Data de nascimento', hint: 'dd/mm/aaaa'),
                validator: (v) =>
                    _isoDate(v ?? '') == null ? 'Data inválida' : null,
              ),
            TextFormField(
              key: const Key('online-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: dec('Celular com DDD'),
              validator: (v) {
                final n = _digits(v ?? '').length;
                return n == 10 || n == 11 ? null : 'Celular inválido';
              },
            ),
            TextFormField(
              key: const Key('online-income'),
              controller: _income,
              keyboardType: TextInputType.number,
              inputFormatters: [CentsInputFormatter()],
              decoration: const InputDecoration(
                  labelText: 'Faturamento mensal aproximado',
                  prefixText: 'R\$ '),
              validator: (v) => (parseMoney(v ?? '') ?? 0) > 0
                  ? null
                  : 'Informe o faturamento',
            ),
            TextFormField(
              key: const Key('online-cep'),
              controller: _cep,
              keyboardType: TextInputType.number,
              decoration: dec('CEP'),
              validator: (v) =>
                  _digits(v ?? '').length == 8 ? null : 'CEP inválido',
            ),
            TextFormField(
              key: const Key('online-street'),
              controller: _street,
              decoration: dec('Rua'),
              validator: _required,
            ),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: const Key('online-number'),
                  controller: _number,
                  decoration: dec('Número'),
                  validator: _required,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const Key('online-complement'),
                  controller: _complement,
                  decoration: dec('Complemento (opcional)'),
                ),
              ),
            ]),
            TextFormField(
              key: const Key('online-district'),
              controller: _district,
              decoration: dec('Bairro'),
              validator: _required,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    key: const Key('online-error'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('online-submit'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Ativar recebimento online'),
            ),
          ],
        ),
      ),
    );
  }
}
