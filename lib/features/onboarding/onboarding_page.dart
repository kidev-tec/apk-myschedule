import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import 'onboarding_provisioning.dart';
import '../../main.dart' show segmentPresetProvider;
import '../../core/segment/segment_preset.dart';
import '../../core/storage/onboarding_store.dart';
import '../../theme/app_theme.dart';

/// Onboarding em 5 passos (copy leiga):
/// 0. Tipo da conta: profissional independente (padrão, como sempre foi)
///    ou estabelecimento agregador (docs/plano-agregador.md, API 0026)
/// 1. Teu segmento (define o tema e os serviços sugeridos)
/// 2. Teu perfil (nome do negócio)
/// 3. Teu primeiro serviço
/// 4. Teus horários de atendimento
///
/// Estabelecimento termina no passo 2: serviços e horários são de cada
/// profissional (D4) — se o dono também atende, cadastra depois.
///
/// A conta já foi criada na LoginPage — aqui só configuramos o negócio.
class OnboardingPage extends ConsumerStatefulWidget {
  /// Injetável em teste; padrão = ApiClient real.
  final ApiClient? api;

  const OnboardingPage({super.key, this.api});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _finishing = false;
  SegmentPreset _segment = SegmentPresets.beauty;
  bool _aggregator = false;
  final _businessNameController = TextEditingController();
  final _addrStreetController = TextEditingController();
  final _addrNumberController = TextEditingController();
  final _addrDistrictController = TextEditingController();
  final _addrCityController = TextEditingController();
  final _addrStateController = TextEditingController();
  final _serviceNameController = TextEditingController();
  final _serviceDurationController = TextEditingController(text: '60');
  final _servicePriceController = TextEditingController();

  // Horários: por dia da semana, lista de intervalos (início/fim em minutos)
  final Map<int, List<_TimeRange>> _workingHours = {
    for (final d in [1, 2, 3, 4, 5, 6]) d: [const _TimeRange(9 * 60, 18 * 60)],
  };

  @override
  void dispose() {
    _pageController.dispose();
    _businessNameController.dispose();
    _addrStreetController.dispose();
    _addrNumberController.dispose();
    _addrDistrictController.dispose();
    _addrCityController.dispose();
    _addrStateController.dispose();
    _serviceNameController.dispose();
    _serviceDurationController.dispose();
    _servicePriceController.dispose();
    super.dispose();
  }

  /// Último passo: estabelecimento para no perfil; independente vai até os
  /// horários.
  int get _lastStep => _aggregator ? 2 : 4;

  /// A partir de qual passo o botão principal diz "Começar".
  int get _startStep => _aggregator ? 2 : 3;

  void _nextStep() {
    if (_currentStep < _lastStep) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _finishing = true);
    try {
      final api = widget.api ?? ApiClient();

      // 0. Garante provisionamento (user+business no Postgres) — ver
      // onboarding_provisioning.dart. Testado em onboarding_provisioning_test.dart.
      await ensureProvisioned(api.dio, segmentId: _segment.id);

      // 1. Perfil do negócio (+ endereço F1 — campos vazios são omitidos)
      final address = <String, String>{
        'street': _addrStreetController.text.trim(),
        'number': _addrNumberController.text.trim(),
        'district': _addrDistrictController.text.trim(),
        'city': _addrCityController.text.trim(),
        'state': _addrStateController.text.trim().toUpperCase(),
      }..removeWhere((_, v) => v.isEmpty);
      await api.dio.patch('/me', data: {
        'business_name': _businessNameController.text.trim(),
        'business_type': _segment.id,
        if (address.isNotEmpty) 'address': address,
      });

      if (_aggregator) {
        // Estabelecimento: gera o código E- (idempotente). Serviços e
        // horários ficam opcionais (D4).
        await api.dio
            .put('/me/account-kind', data: {'account_kind': 'aggregator'});
        await OnboardingStore.markComplete();
        if (mounted) context.go('/agenda');
        return;
      }

      // 2. Primeiro serviço
      final price =
          double.tryParse(_servicePriceController.text.replaceAll(',', '.'));
      await api.dio.post('/services', data: {
        'name': _serviceNameController.text.trim(),
        'duration_min': int.tryParse(_serviceDurationController.text) ?? 60,
        'price_cents': price != null ? (price * 100).round() : 0,
      });

      // 3. Horários de trabalho
      final workingHours = <Map<String, dynamic>>[];
      _workingHours.forEach((weekday, ranges) {
        for (final r in ranges) {
          workingHours.add({
            'weekday': weekday,
            'start_minute': r.startMinute,
            'end_minute': r.endMinute,
          });
        }
      });
      await api.dio.put('/working-hours', data: {'slots': workingHours});

      // Marca onboarding completo
      await OnboardingStore.markComplete();
    } on DioException catch (e) {
      if (mounted) {
        // Erros de validação do servidor têm mensagem humana — mostra direto
        // (ex: 409 "Já existe um estabelecimento com esse nome neste segmento").
        final serverMsg = e.response?.data is Map
            ? (e.response?.data['error'] as String?)
            : null;
        final msg =
            serverMsg ?? 'Não foi possível salvar tudo. Tente novamente.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
      if (mounted) setState(() => _finishing = false);
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não consegui salvar tudo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      if (mounted) setState(() => _finishing = false);
      return;
    }
    if (mounted) context.go('/agenda');
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        _nextStep();
        return true;
      case 1:
        // Segmento escolhido: pré-preenche o primeiro serviço sugerido
        // (pontos de partida, não prisão — usuário edita à vontade).
        final sug = _segment.suggestedServices;
        if (sug.isNotEmpty && _serviceNameController.text.trim().isEmpty) {
          _serviceNameController.text = sug.first.name;
          _serviceDurationController.text = '${sug.first.durationMin}';
          _servicePriceController.text = (sug.first.priceCents / 100)
              .toStringAsFixed(2)
              .replaceAll('.', ',');
        }
        _nextStep();
        return true;
      case 2:
        if (_businessNameController.text.trim().isEmpty) {
          _showError('Qual é o nome do seu espaço?');
          return false;
        }
        _nextStep();
        return true;
      case 3:
        if (_serviceNameController.text.trim().isEmpty) {
          _showError('Qual serviço você oferece?');
          return false;
        }
        // B3: mesma regra da API — 15..480, múltiplo de 15
        final dur = int.tryParse(_serviceDurationController.text);
        if (dur == null || dur < 5 || dur > 480 || dur % 5 != 0) {
          _showError('Duração entre 5 e 480 minutos, de 5 em 5');
          return false;
        }
        final price =
            double.tryParse(_servicePriceController.text.replaceAll(',', '.'));
        if (price == null || price < 0) {
          _showError('Preço inválido — use números, ex.: 80,00');
          return false;
        }
        _nextStep();
        return true;
      case 4:
        final hasAny = _workingHours.values.any((r) => r.isNotEmpty);
        if (!hasAny) {
          _showError('Marque pelo menos um dia com horário');
          return false;
        }
        _finishOnboarding();
        return true;
    }
    return false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  /// B7: "Pular" no passo do serviço — cria o serviço genérico "Atendimento"
  /// (60 min, R$ 0) e avança. Leigo nunca fica travado sem serviço.
  void _skipService() {
    _serviceNameController.text = 'Atendimento';
    _serviceDurationController.text = '60';
    _servicePriceController.text = '0,00';
    _validateCurrentStep();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: List.generate(
                  _lastStep + 1,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < _lastStep ? 8 : 0),
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? _segment.primary
                            : _segment.secondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentStep = i),
                children: [
                  _buildKindStep(),
                  _buildStep0(),
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            // Navigation
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentStep > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _prevStep,
                        child: const Text('Voltar'),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (_currentStep == 3) ...[
                    // B7: pular cria o serviço genérico — leigo nunca travado
                    Expanded(
                      child: TextButton(
                        onPressed: _finishing ? null : _skipService,
                        child: const Text('Pular'),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _finishing ? null : _validateCurrentStep,
                      child: _finishing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_currentStep >= _startStep
                              ? 'Começar'
                              : 'Continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Passo 0: tipo da conta. Independente é o padrão (o app de sempre).
  Widget _buildKindStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Como você vai usar o Agenva?',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Você pode mudar isso depois em Configurações.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _KindCard(
            icon: Icons.person_outline,
            title: 'Atendo meus clientes',
            subtitle:
                'Você tem a sua agenda e o seu link para os clientes marcarem horário.',
            selected: !_aggregator,
            color: _segment.primary,
            onTap: () => setState(() => _aggregator = false),
          ),
          const SizedBox(height: 12),
          _KindCard(
            icon: Icons.groups_outlined,
            title: 'Tenho um estabelecimento com profissionais',
            subtitle:
                'Os profissionais entram com o código do seu estabelecimento e, '
                'no seu link, o cliente escolhe com quem quer marcar.',
            selected: _aggregator,
            color: _segment.primary,
            onTap: () => setState(() => _aggregator = true),
          ),
        ],
      ),
    );
  }

  // PASSO 2 — Perfil
  /// Passo 1: "Qual é o teu negócio?" — grade de segmentos. Define tema,
  /// serviços sugeridos e copy. (Decisão multi-segmento 09/09/2026.)
  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Qual é o seu negócio?',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Isso personaliza as cores e sugere serviços de exemplo. Você pode mudar tudo depois.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              for (final s in SegmentPreset.all)
                _SegmentCard(
                  preset: s,
                  selected: _segment.id == s.id,
                  onTap: () {
                    setState(() => _segment = s);
                    // Tema ao vivo: o form inteiro adota a paleta do
                    // segmento já no onboarding (não só pós-conclusão).
                    ref.read(segmentPresetProvider.notifier).state = s;
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_aggregator ? 'Seu estabelecimento' : 'Seu espaço',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _aggregator
                ? 'Qual é o nome do estabelecimento? Ele aparece no seu link. '
                    'Os serviços e horários são de cada profissional — se você '
                    'também atende, cadastre os seus depois em Configurações.'
                : 'Qual é o nome do seu espaço ou atendimento? Ele aparece na agenda.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.neutral),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _businessNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nome do espaço',
              hintText: 'Ex: Studio Ana Beleza',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 16),
          // Endereço (F1): onde os clientes vão te encontrar. Opcional —
          // quem atende fora de um espaço fixo pode pular.
          Text(
            'Onde os clientes encontram você? (opcional)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addrStreetController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
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
                child: TextField(
                  controller: _addrNumberController,
                  decoration: const InputDecoration(labelText: 'Número'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _addrDistrictController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Bairro'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _addrCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Cidade'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _addrStateController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'UF',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PASSO 2 — Primeiro serviço
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seu primeiro serviço',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          // B7/B14: copy exata — deixa claro que pode adicionar mais depois
          // (leigo não trava com medo de "só 1 serviço pra sempre").
          Text(
            'Cadastre seu primeiro serviço — você pode adicionar quantos quiser depois',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.neutral),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _serviceNameController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nome do serviço',
              hintText: 'Ex: Corte feminino',
              prefixIcon: Icon(Icons.miscellaneous_services_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceDurationController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Duração (min)',
                    hintText: '60',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _servicePriceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Preço (R\$)',
                    hintText: '80,00',
                    prefixIcon: Icon(Icons.attach_money_outlined),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PASSO 3 — Horários
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seus horários',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Em quais dias você atende? Toque no dia para ligar/desligar.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.neutral),
          ),
          const SizedBox(height: 24),
          ...List.generate(7, (i) => _buildDayRow(i)),
        ],
      ),
    );
  }

  Widget _buildDayRow(int weekday) {
    const names = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    final enabled = (_workingHours[weekday] ?? []).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Switch(
              value: enabled,
              activeThumbColor: AppColors.primaryOf(context),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => _toggleDay(weekday),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              names[weekday],
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color:
                        enabled ? AppColors.neutral : AppColors.midOf(context),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: enabled
                ? Column(
                    children: [
                      for (final range in _workingHours[weekday]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _pickTime(weekday, range, true),
                                  child: Text(range.startLabel),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text('às'),
                              ),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _pickTime(weekday, range, false),
                                  child: Text(range.endLabel),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Text(
                      'Fechado',
                      style: TextStyle(color: AppColors.midOf(context)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _toggleDay(int weekday) {
    setState(() {
      final current = _workingHours[weekday] ?? const <_TimeRange>[];
      _workingHours[weekday] = current.isEmpty
          ? [const _TimeRange(9 * 60, 18 * 60)]
          : <_TimeRange>[];
    });
  }

  Future<void> _pickTime(int weekday, _TimeRange range, bool isStart) async {
    final initial = TimeOfDay(
      hour: (isStart ? range.startMinute : range.endMinute) ~/ 60,
      minute: (isStart ? range.startMinute : range.endMinute) % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      final ranges = <_TimeRange>[
        ...(_workingHours[weekday] ?? const <_TimeRange>[])
      ];
      final idx = ranges.indexOf(range);
      if (idx >= 0) {
        ranges[idx] = isStart
            ? _TimeRange(minutes, range.endMinute)
            : _TimeRange(range.startMinute, minutes);
        _workingHours[weekday] = ranges;
      }
    });
  }
}

class _TimeRange {
  final int startMinute;
  final int endMinute;

  const _TimeRange(this.startMinute, this.endMinute);

  String get startLabel =>
      '${(startMinute ~/ 60).toString().padLeft(2, '0')}:${(startMinute % 60).toString().padLeft(2, '0')}';

  String get endLabel =>
      '${(endMinute ~/ 60).toString().padLeft(2, '0')}:${(endMinute % 60).toString().padLeft(2, '0')}';
}

/// Opção do tipo da conta (passo 0).
class _KindCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? color : Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? color : Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de segmento na grade do passo 1.
class _SegmentCard extends StatelessWidget {
  final SegmentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color:
              selected ? preset.primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? preset.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(preset.icon,
                color: selected ? preset.primary : Colors.grey.shade600,
                size: 28),
            const SizedBox(height: 6),
            Text(
              preset.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? preset.primaryPressed : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
