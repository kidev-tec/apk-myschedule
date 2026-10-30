import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../main.dart' show segmentPresetProvider;
import '../../theme/app_theme.dart';
import '../../theme/theme_palette.dart';
import '../../core/widgets/home_action.dart';

/// Configurações → Tema e identidade visual: escolhe a cor do app a partir da
/// paleta (ou volta pra cor do segmento). Salva no negócio (PATCH /me
/// `theme_color`), então vale em qualquer aparelho.
class ThemePage extends ConsumerStatefulWidget {
  final ApiClient? api; // DI pra testes

  const ThemePage({super.key, this.api});

  @override
  ConsumerState<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends ConsumerState<ThemePage> {
  late Color? _selected = ref.read(themeColorProvider);
  bool _saving = false;

  Future<void> _save() async {
    final submitted = _selected;
    setState(() => _saving = true);
    try {
      await (widget.api ?? ApiClient()).dio.patch('/me', data: {
        'theme_color': submitted == null ? null : colorToHex(submitted),
      });
      if (!mounted) return;
      ref.read(themeColorProvider.notifier).state = submitted;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tema atualizado')));
      if (context.canPop()) context.pop();
    } catch (e) {
      debugPrint('[tema] falha ao salvar: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanError(e)), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segment = ref.watch(segmentPresetProvider);
    final segmentColor = applyThemeColor(segment, null).primary;
    final preview = buildAppTheme(applyThemeColor(segment, _selected));
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Tema e identidade visual'),
          actions: const [HomeAction()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Escolhe a cor principal do app.', style: textTheme.bodyLarge),
          const SizedBox(height: 16),
          // Padrão: cor do segmento
          Card(
            child: ListTile(
              onTap: () => setState(() => _selected = null),
              leading:
                  _Swatch(color: segmentColor, selected: _selected == null),
              title: Text(
                  'Cor do segmento${segment == null ? '' : ' (${segment.label})'}'),
              subtitle: const Text('Padrão — muda junto com o segmento'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Paleta disponível', style: textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final o in themePalette)
                Tooltip(
                  message: o.name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _selected = o.color),
                    child:
                        _Swatch(color: o.color, selected: _selected == o.color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Prévia', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          // Prévia ao vivo com o tema escolhido (antes de salvar)
          Theme(
            data: preview,
            child: Builder(builder: (context) {
              final primary = Theme.of(context).colorScheme.primary;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('09:00',
                              style: TextStyle(
                                  color: primary, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Cliente • Corte')),
                        Icon(Icons.sticky_note_2, color: primary),
                      ]),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                        label: const Text('Marcar horário'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar tema'),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  const _Swatch({required this.color, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            color: selected ? AppColors.neutral : Colors.transparent, width: 3),
      ),
      child: selected ? const Icon(Icons.check, color: Colors.white) : null,
    );
  }
}
