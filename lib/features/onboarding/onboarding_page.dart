import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/segment/segment_preset.dart';
import '../../core/storage/onboarding_store.dart';
import '../../theme/app_theme.dart';

/// Onboarding em 4 passos (copy leiga):
/// 0. Teu segmento (define o tema e os serviços sugeridos)
/// 1. Teu perfil (nome do negócio)
/// 2. Teu primeiro serviço
/// 3. Teus horários de atendimento
///
/// A conta já foi criada na LoginPage — aqui só configuramos o negócio.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _finishing = false;
  SegmentPreset _segment = SegmentPresets.beauty;

  final _businessNameController = TextEditingController();
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
    _serviceNameController.dispose();
    _serviceDurationController.dispose();
    _servicePriceController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 3) {
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
      final api = ApiClient();

      // 1. Perfil do negócio
      await api.dio.patch('/me', data: {
        'business_name': _businessNameController.text.trim(),
        'business_type': _segment.id,
      });

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
      case 1:
        if (_businessNameController.text.trim().isEmpty) {
          _showError('Como teu espaço se chama?');
          return false;
        }
        _nextStep();
        return true;
      case 2:
        if (_serviceNameController.text.trim().isEmpty) {
          _showError('Qual serviço tu oferece?');
          return false;
        }
        final dur = int.tryParse(_serviceDurationController.text);
        if (dur == null || dur < 15 || dur > 480 || dur % 15 != 0) {
          _showError('Duração entre 15 e 480 minutos, de 15 em 15');
          return false;
        }
        final price =
            double.tryParse(_servicePriceController.text.replaceAll(',', '.'));
        if (price == null || price <= 0) {
          _showError('Preço inválido — usa números, ex: 80,00');
          return false;
        }
        _nextStep();
        return true;
      case 3:
        final hasAny = _workingHours.values.any((r) => r.isNotEmpty);
        if (!hasAny) {
          _showError('Marca pelo menos um dia com horário');
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
                  3,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
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
                          : Text(_currentStep == 2 ? 'Começar' : 'Continuar'),
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

  // PASSO 1 — Perfil
  /// Passo 0: "Qual é o teu negócio?" — grade de segmentos. Define tema,
  /// serviços sugeridos e copy. (Decisão multi-segmento 09/09/2026.)
  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Qual é o teu negócio?',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Isso personaliza as cores e te dá serviços de exemplo. Tu pode mudar tudo depois.',
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
                  onTap: () => setState(() => _segment = s),
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
          Text('Teu espaço', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Como teu espaço ou teu atendimento se chama? A gente usa isso na agenda.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.neutral),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _businessNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nome do espaço',
              hintText: 'Ex: Studio Ana Beleza',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
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
          Text('Teu primeiro serviço',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'O que tu oferece? Ex: Corte, Design de sobrancelha, Alongamento...',
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
              prefixIcon: Icon(Icons.content_cut_outlined),
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
          Text('Teus horários',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Quando atendes? Toque no dia pra ligar/desligar.',
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
    const names = [
      'Domingo',
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado'
    ];
    final enabled = (_workingHours[weekday] ?? []).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Row(
              children: [
                Switch(
                  value: enabled,
                  activeThumbColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _toggleDay(weekday),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    names[weekday],
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color:
                              enabled ? AppColors.neutral : AppColors.pinkMid,
                        ),
                  ),
                ),
              ],
            ),
          ),
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
                : const Text(
                    'Fechado',
                    style: TextStyle(color: AppColors.pinkMid),
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

/// Card de segmento na grade do passo 0.
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
