import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/segment/segment_preset.dart';
import 'package:minha_agenda/theme/theme_palette.dart';

void main() {
  test('hex ↔ Color', () {
    expect(parseHexColor('#8B5E34'), const Color(0xFF8B5E34));
    expect(parseHexColor('#8b5e34'), const Color(0xFF8B5E34));
    expect(parseHexColor(null), isNull);
    expect(parseHexColor('azul'), isNull);
    expect(colorToHex(const Color(0xFF1976D2)), '#1976D2');
  });

  test('sem cor escolhida: mantém o preset do segmento', () {
    final barber = SegmentPreset.byId('barber');
    expect(applyThemeColor(barber, null), same(barber));
  });

  test('cor escolhida: troca primária e deriva escura/clara', () {
    final barber = SegmentPreset.byId('barber');
    const roxo = Color(0xFF6A1B9A);
    final p = applyThemeColor(barber, roxo);
    expect(p.primary, roxo);
    expect(p.id, 'barber',
        reason: 'segmento continua o mesmo (ícone, serviços)');
    expect(HSLColor.fromColor(p.primaryPressed).lightness,
        lessThan(HSLColor.fromColor(roxo).lightness));
    expect(HSLColor.fromColor(p.secondary).lightness,
        greaterThan(HSLColor.fromColor(roxo).lightness));
  });

  test('sem segmento ainda: aplica sobre a marca AGENVA', () {
    const verde = Color(0xFF2E7D32);
    expect(applyThemeColor(null, verde).primary, verde);
    expect(applyThemeColor(null, null), same(SegmentPresets.brand));
  });

  test('paleta: cores únicas e com nome', () {
    final hexes = themePalette.map((o) => colorToHex(o.color)).toSet();
    expect(hexes.length, themePalette.length);
    expect(themePalette.every((o) => o.name.isNotEmpty), isTrue);
  });
}
