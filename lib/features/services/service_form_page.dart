import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/utils/duration_text.dart';
import '../../theme/app_theme.dart';
import '../../core/widgets/home_action.dart';

class ServiceFormPage extends ConsumerStatefulWidget {
  final String? serviceId;

  /// Criar um kit (combo). Na edição o tipo vem da API (is_kit).
  final bool kit;

  /// DI pra teste (mock de rede). Padrão: ApiClient real.
  final ApiClient? api;

  const ServiceFormPage(
      {super.key, this.serviceId, this.kit = false, this.api});

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

  // ---- kit (0021)
  late bool _isKit = widget.kit;

  /// Serviços avulsos ativos que podem entrar no kit.
  List<_Option> _options = [];
  bool _optionsLoading = false;
  bool _optionsError = false;

  /// Itens escolhidos, na ordem em que foram marcados.
  final List<String> _items = [];
  String? _itemsError;

  /// Duração segue a soma dos itens até o prestador mexer nela.
  bool _durTouched = false;

  /// Desconto opcional do kit, em % sobre a soma dos serviços.
  /// O preço do kit é sempre soma − desconto (sem campo de preço próprio).
  final _discountCtrl = TextEditingController();

  /// Preço salvo (edição): vira % quando os itens carregam. Enquanto o
  /// prestador não mexe no desconto nem nos itens, o preço salvo vale
  /// exato (o % exibido é arredondado).
  int? _savedKitPrice;
  bool _kitEdited = false;

  /// Último nome automático escrito no campo: enquanto o campo tiver ele
  /// (ou estiver vazio), marcar/desmarcar serviços atualiza o nome.
  String _lastAutoName = '';
  bool get _nameIsAuto =>
      _nameController.text.trim().isEmpty ||
      _nameController.text == _lastAutoName;
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_isEditing) await _loadService();
    if (_isKit) await _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _optionsLoading = true;
      _optionsError = false;
    });
    try {
      final api = widget.api ?? ApiClient();
      final resp = await api.dio.get('/services');
      _options = [
        for (final j in resp.data as List)
          if (j['is_kit'] != true && j['id'] != widget.serviceId)
            _Option(j['id'] as String, j['name'] as String,
                j['duration_min'] as int, j['price_cents'] as int),
      ];
      // edição: nome salvo igual ao automático segue automático
      if (_nameController.text == _autoKitName) _lastAutoName = _autoKitName;
      // edição: duração salva = soma dos itens → segue a soma ao mudar os
      // serviços; diferente (ajuste à mão) → fica até "Usar a soma"
      if (_isEditing && _items.isNotEmpty) {
        _durTouched = int.tryParse(_durationController.text) != _sumMin;
      }
      // edição: desconto (%) = (soma atual dos itens − preço salvo) / soma
      final saved = _savedKitPrice;
      if (saved != null && saved < _sumCents) {
        _discountCtrl.text = _pctText((_sumCents - saved) * 100 / _sumCents);
      }
    } catch (e) {
      debugPrint('[service_form] erro ao listar serviços: $e');
      _optionsError = true;
    }
    if (mounted) setState(() => _optionsLoading = false);
  }

  int get _sumMin => _chosen.fold(0, (a, o) => a + o.durationMin);
  int get _sumCents => _chosen.fold(0, (a, o) => a + o.priceCents);
  List<_Option> get _chosen => [
        for (final id in _items) ..._options.where((o) => o.id == id),
      ];

  /// "10" ou "14,3" (uma casa só quando precisa).
  String _pctText(double pct) {
    final r = (pct * 10).round() / 10;
    return (r == r.roundToDouble()
            ? r.toStringAsFixed(0)
            : r.toStringAsFixed(1))
        .replaceAll('.', ',');
  }

  double? _parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

  /// Desconto em centavos (0 se vazio/inválido), nunca maior que a soma.
  int get _discountCents {
    final saved = _savedKitPrice;
    if (!_kitEdited && saved != null) {
      return (_sumCents - saved).clamp(0, _sumCents);
    }
    final v = _parse(_discountCtrl.text);
    if (v == null || v <= 0) return 0;
    return (_sumCents * v / 100).round().clamp(0, _sumCents);
  }

  int get _kitPriceCents => _sumCents - _discountCents;

  /// Nome automático do kit quando o prestador não digita: "Corte + Barba"
  /// (ordem em que marcou; API aceita até 120 caracteres).
  String get _autoKitName {
    final n = _chosen.map((o) => o.name).join(' + ');
    return n.length <= 120 ? n : '${n.substring(0, 119)}…';
  }

  String? _validateDiscount(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = _parse(v);
    if (n == null || n < 0) return 'Inválido';
    if (n > 100) return 'Até 100%';
    return null;
  }

  /// Marca/desmarca um item e, se o prestador ainda não mexeu, atualiza
  /// duração e preço com a soma.
  void _toggleItem(String id) {
    setState(() {
      final auto = _nameIsAuto;
      _items.contains(id) ? _items.remove(id) : _items.add(id);
      _itemsError = null;
      _kitEdited = true;
      // nome automático "A + B" até o prestador digitar o dele
      if (auto) {
        _lastAutoName = _autoKitName;
        _nameController.text = _lastAutoName;
      }
      _applySum(force: false);
    });
  }

  /// Duração = soma dos itens, a menos que o prestador tenha ajustado.
  void _applySum({required bool force}) {
    if (_items.isEmpty) return;
    if (force || !_durTouched) {
      _durationController.text = '${_sumMin.clamp(_minDur, _maxDur)}';
    }
    if (force) _durTouched = false;
  }

  Future<void> _loadService() async {
    setState(() => _loading = true);
    try {
      final api = widget.api ?? ApiClient();
      final resp = await api.dio.get('/services/${widget.serviceId}');
      final data = resp.data;
      _nameController.text = data['name'] ?? '';
      _durationController.text =
          (data['duration_min'] ?? data['durationMin'] ?? 60).toString();
      final cents = data['price_cents'] ?? data['priceCents'] ?? 0;
      _priceController.text = (cents is num ? cents / 100 : 0.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      if (data['is_kit'] == true) {
        _isKit = true;
        _items.addAll([
          for (final i in (data['items'] as List? ?? [])) i['id'] as String,
        ]);
        // editando: _loadOptions decide se a duração segue a soma; o preço
        // salvo vira desconto quando os itens carregam
        _durTouched = true;
        _savedKitPrice = cents is int ? cents : null;
      }
    } catch (e) {
      debugPrint('[service_form] erro: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _stepMin = 5, _minDur = 5, _maxDur = 480;

  /// Soma/subtrai 5 min respeitando 5..480. Valor digitado fora do passo
  /// (ex.: 62) encaixa no múltiplo de 5 seguinte/anterior.
  void _stepDuration(int dir) {
    final cur = int.tryParse(_durationController.text) ?? 60;
    final base = dir > 0
        ? (cur ~/ _stepMin) * _stepMin + _stepMin
        : ((cur + _stepMin - 1) ~/ _stepMin) * _stepMin - _stepMin;
    final next = base.clamp(_minDur, _maxDur);
    setState(() {
      _durationController.text = '$next';
      _durTouched = true;
    });
  }

  Widget _durationStepper() {
    final cur = int.tryParse(_durationController.text);
    Widget arrow(Key key, IconData icon, String tip, int dir, bool enabled) =>
        InkWell(
          key: key,
          onTap: enabled ? () => _stepDuration(dir) : null,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: tip,
            child: Icon(icon,
                size: 22,
                color: enabled
                    ? AppColors.primaryOf(context)
                    : AppColors.neutral.withValues(alpha: 0.4)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          arrow(const Key('duration-up'), Icons.keyboard_arrow_up,
              'Mais 5 minutos', 1, cur == null || cur < _maxDur),
          arrow(const Key('duration-down'), Icons.keyboard_arrow_down,
              'Menos 5 minutos', -1, cur == null || cur > _minDur),
        ],
      ),
    );
  }

  /// "Duração: 1 hora e 10 minutos" — só quando o valor é válido.
  Widget _durationPreview() {
    final n = int.tryParse(_durationController.text);
    final ok = n != null && n >= _minDur && n <= _maxDur && n % _stepMin == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          Icon(Icons.schedule,
              size: 16,
              color: ok ? AppColors.primaryOf(context) : AppColors.neutral),
          const SizedBox(width: 6),
          Text(
            ok ? 'Duração: ${humanDuration(n)}' : 'Duração: —',
            key: const Key('duration-human'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ok ? null : AppColors.neutral,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    if (_isKit && _items.length < 2) {
      setState(() => _itemsError = 'Escolha pelo menos 2 serviços para o kit');
      return;
    }
    if (!formOk) return;
    setState(() => _loading = true);

    final dur = int.tryParse(_durationController.text);
    // kit: preço = soma − desconto; avulso: o digitado
    final priceCents = _isKit
        ? _kitPriceCents
        : ((_parse(_priceController.text) ?? -1) * 100).round();
    if (dur == null || priceCents < 0) return;

    final data = {
      'name': _nameController.text.trim().isEmpty && _isKit
          ? _autoKitName
          : _nameController.text.trim(),
      'duration_min': dur,
      'price_cents': priceCents,
      if (_isKit) 'items': _items,
    };

    try {
      final api = widget.api ?? ApiClient();
      if (_isEditing) {
        await api.dio.patch('/services/${widget.serviceId}', data: data);
      } else {
        await api.dio.post('/services', data: data);
      }
      if (!mounted) return;
      // Volta pra lista preservando a pilha (Configurações → Serviços):
      // context.go trocava a pilha inteira e a seta de voltar sumia.
      // Sem origem (deep link), cai na lista.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/services');
      }
      return;
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

  /// Lista de serviços avulsos pra marcar no kit (ordem = ordem de marcação).
  Widget _kitItemsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Serviços do kit', style: theme.textTheme.titleSmall),
        Text('Marque 2 ou mais. O kit é agendado como um único serviço.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.neutral)),
        const SizedBox(height: 4),
        if (_optionsLoading)
          const Padding(
            key: Key('kit-items-loading'),
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Carregando serviços…'),
            ]),
          )
        else if (_optionsError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const Expanded(child: Text('Não consegui carregar os serviços.')),
              TextButton(
                key: const Key('kit-items-retry'),
                onPressed: _loadOptions,
                child: const Text('Tentar de novo'),
              ),
            ]),
          )
        else if (_options.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Cadastre os serviços avulsos primeiro '
                '(ex.: Corte, Barba) para montar um kit.'),
          ),
        for (final o in _options)
          CheckboxListTile(
            key: Key('kit-item-${o.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _items.contains(o.id),
            onChanged: (_) => _toggleItem(o.id),
            title: Text(o.name),
            subtitle: Text(
                '${humanDuration(o.durationMin)} • ${_money.format(o.priceCents / 100)}'),
          ),
        if (_itemsError != null)
          Text(_itemsError!,
              key: const Key('kit-items-error'),
              style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }

  /// ▲▼ do desconto: 1 em 1 ponto %, entre 0 e 100.
  /// Valor quebrado (ex.: 7,5) encaixa no inteiro seguinte/anterior.
  void _stepDiscount(int dir) {
    final cur = _parse(_discountCtrl.text) ?? 0;
    final next = (dir > 0 ? cur.floor() + 1 : cur.ceil() - 1).clamp(0, 100);
    setState(() {
      _kitEdited = true;
      _discountCtrl.text = next == 0 ? '' : '$next'; // 0 limpa o campo
    });
  }

  Widget _discountArrows() {
    final cur = _parse(_discountCtrl.text) ?? 0;
    Widget arrow(Key key, IconData icon, String tip, int dir, bool enabled) =>
        InkWell(
          key: key,
          onTap: enabled ? () => _stepDiscount(dir) : null,
          borderRadius: BorderRadius.circular(8),
          // Semantics (não Tooltip): tooltip dentro do sufixo do campo
          // quebrava a árvore de acessibilidade
          child: Semantics(
            label: tip,
            button: true,
            child: Icon(icon,
                size: 22,
                color: enabled
                    ? AppColors.primaryOf(context)
                    : AppColors.neutral.withValues(alpha: 0.4)),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(const Key('discount-up'), Icons.keyboard_arrow_up, 'Mais 1%', 1,
            _items.isNotEmpty && cur < 100),
        arrow(const Key('discount-down'), Icons.keyboard_arrow_down, 'Menos 1%',
            -1, cur > 0),
      ],
    );
  }

  /// Desconto (opcional) em %, ao lado da duração.
  Widget _discountField() {
    return TextFormField(
      key: const Key('kit-discount'),
      controller: _discountCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Desconto',
        hintText: 'opcional',
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _discountArrows(),
            const SizedBox(width: 4),
            Text('%',
                key: const Key('discount-unit'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryOf(context))),
          ]),
        ),
      ),
      onChanged: (_) => setState(() => _kitEdited = true),
      validator: _validateDiscount,
    );
  }

  /// Valor dos serviços (riscado se tem desconto), desconto e preço do kit.
  Widget _kitSumInfo() {
    if (_items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final disc = _discountCents;
    final dur = int.tryParse(_durationController.text);
    final pct = _sumCents == 0 ? 0.0 : (disc * 100 / _sumCents);
    final pctTxt = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1).replaceAll('.', ',');
    Widget line(String label, String value,
            {Key? key, TextStyle? style, bool strike = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: style)),
            Text(value,
                key: key,
                style: (style ?? theme.textTheme.bodyMedium)?.copyWith(
                    decoration: strike ? TextDecoration.lineThrough : null,
                    color: strike ? AppColors.neutral : null)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line('Valor dos serviços', _money.format(_sumCents / 100),
                key: const Key('kit-sum'), strike: disc > 0),
            if (disc > 0)
              line('Desconto ($pctTxt%)', '− ${_money.format(disc / 100)}',
                  key: const Key('kit-discount-value'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.green.shade700)),
            const Divider(height: 12),
            line('Preço do kit', _money.format(_kitPriceCents / 100),
                key: const Key('kit-price'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (dur != _sumMin) ...[
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text('Soma das durações: ${humanDuration(_sumMin)}',
                      style: theme.textTheme.bodySmall),
                ),
                TextButton(
                  key: const Key('kit-use-sum'),
                  onPressed: () => setState(() => _applySum(force: true)),
                  child: const Text('Usar a soma'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isKit
              ? (_isEditing ? 'Editar kit' : 'Novo kit')
              : (_isEditing ? 'Editar serviço' : 'Novo serviço')),
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
                    // re-render: a dica "nome automático" some ao editar
                    onChanged: _isKit ? (_) => setState(() {}) : null,
                    decoration: InputDecoration(
                      // kit: nome é opcional — vazio vira "A + B + C"
                      labelText: _isKit ? 'Nome' : 'Nome *',
                      hintText: _isKit ? 'Ex.: Corte + Barba' : null,
                      helperText: _isKit && _items.isNotEmpty && _nameIsAuto
                          ? 'Nome automático com os serviços — pode editar'
                          : null,
                      prefixIcon: Icon(_isKit
                          ? Icons.style_outlined
                          : Icons.miscellaneous_services_outlined),
                    ),
                    validator: (v) => !_isKit && (v == null || v.trim().isEmpty)
                        ? 'Nome é obrigatório'
                        : null,
                  ),
                  if (_isKit) ...[
                    const SizedBox(height: 16),
                    _kitItemsSection(),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Duração (min) *',
                            hintText: '60',
                            prefixIcon: const Icon(Icons.timer_outlined),
                            // setas ▲▼ de 5 em 5 (o passo que o sistema aceita)
                            suffixIcon: _durationStepper(),
                          ),
                          // re-render pra habilitar/desabilitar as setas
                          onChanged: (_) => setState(() => _durTouched = true),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null ||
                                n < _minDur ||
                                n > _maxDur ||
                                n % _stepMin != 0) {
                              return '5 a 480 min, de 5 em 5';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_isKit)
                        Expanded(child: _discountField())
                      else
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Preço *',
                              hintText: '80,00',
                              prefixIcon: Padding(
                                padding:
                                    const EdgeInsets.only(left: 12, right: 8),
                                child: Text('R\$',
                                    key: const Key('price-currency'),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryOf(context))),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                            ),
                            validator: (v) {
                              final n = double.tryParse(
                                  (v ?? '').replaceAll(',', '.'));
                              if (n == null || n <= 0) return 'Inválido';
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                  _durationPreview(),
                  if (_isKit) _kitSumInfo(),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEditing
                            ? 'Salvar alterações'
                            : (_isKit ? 'Criar kit' : 'Criar serviço')),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Serviço avulso que pode entrar num kit.
class _Option {
  final String id;
  final String name;
  final int durationMin;
  final int priceCents;
  const _Option(this.id, this.name, this.durationMin, this.priceCents);
}
