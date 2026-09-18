import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minha_agenda/core/segment/segment_preset.dart';
import 'package:minha_agenda/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('cor primária default é o azul da marca AGENVA (#1E96E8)', () {
      expect(AppColors.primary, const Color(0xFF1E96E8));
    });

    test('pressed é o azul escuro derivado (#1573B5)', () {
      expect(AppColors.primaryPressed, const Color(0xFF1573B5));
    });

    test('paleta da marca AGENVA bate com o DESIGN.md v2', () {
      expect(AppColors.agenvaBlue, const Color(0xFF1E96E8));
      expect(AppColors.agenvaNavy, const Color(0xFF16325C));
      expect(AppColors.agenvaSky, const Color(0xFF54B7EA));
      expect(AppColors.agenvaSurface, const Color(0xFFF8F9FA));
    });

    test('preset de segmento sobrepõe a marca (beauty segue Rubi)', () {
      final theme = buildAppTheme(SegmentPresets.beauty);
      expect(theme.colorScheme.primary, const Color(0xFFB51F4D));
    });

    test('buildAppTheme retorna tema Material 3 com primary da marca', () {
      final theme = buildAppTheme();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('buildAppTheme é determinístico (duas chamadas = mesmo primary)', () {
      final t1 = buildAppTheme();
      final t2 = buildAppTheme();
      expect(t1.colorScheme.primary, t2.colorScheme.primary);
      expect(t1.colorScheme.secondary, t2.colorScheme.secondary);
    });
  });
}
