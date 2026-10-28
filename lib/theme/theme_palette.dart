import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/segment/segment_preset.dart';

/// Cor do tema escolhida pelo prestador (identidade visual); null = cor do
/// segmento. Vem de `GET /me` (`theme_color`) e muda em Configurações → Tema.
final themeColorProvider = StateProvider<Color?>((ref) => null);

class ThemeColorOption {
  final String name;
  final Color color;
  const ThemeColorOption(this.name, this.color);
}

/// Paleta disponível: as cores dos segmentos + algumas extras.
const themePalette = <ThemeColorOption>[
  ThemeColorOption('Azul AGENVA', Color(0xFF1E96E8)),
  ThemeColorOption('Rubi', Color(0xFFB51F4D)),
  ThemeColorOption('Rosa', Color(0xFFD81B60)),
  ThemeColorOption('Vinho', Color(0xFF7B1F3A)),
  ThemeColorOption('Âmbar couro', Color(0xFF8B5E34)),
  ThemeColorOption('Dourado', Color(0xFFB8860B)),
  ThemeColorOption('Laranja', Color(0xFFF57C00)),
  ThemeColorOption('Azul clínico', Color(0xFF1976D2)),
  ThemeColorOption('Azul marinho', Color(0xFF16325C)),
  ThemeColorOption('Verde clínico', Color(0xFF00897B)),
  ThemeColorOption('Verde saúde', Color(0xFF2E7D32)),
  ThemeColorOption('Roxo', Color(0xFF5E35B1)),
  ThemeColorOption('Lavanda', Color(0xFF8E6CC4)),
  ThemeColorOption('Grafite', Color(0xFF37474F)),
  ThemeColorOption('Azul aço', Color(0xFF455A64)),
  ThemeColorOption('Preto', Color(0xFF212121)),
];

/// "#RRGGBB" → Color (null se vazio/inválido).
Color? parseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// Color → "#RRGGBB" (maiúsculo, sem alpha).
String colorToHex(Color c) {
  String h(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// Aplica a cor escolhida sobre o preset do segmento (ou da marca, antes do
/// segmento): troca a primária e deriva a versão escura (pressionado) e a
/// clara (secundária). Ícone, nome e serviços sugeridos continuam do segmento.
SegmentPreset applyThemeColor(SegmentPreset? base, Color? color) {
  final p = base ?? SegmentPresets.brand;
  if (color == null) return p;
  final hsl = HSLColor.fromColor(color);
  return SegmentPreset(
    id: p.id,
    label: p.label,
    icon: p.icon,
    primary: color,
    primaryPressed:
        hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor(),
    secondary: hsl
        .withLightness(0.88)
        .withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0))
        .toColor(),
    suggestedServices: p.suggestedServices,
  );
}
