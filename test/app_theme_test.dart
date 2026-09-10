import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minha_agenda/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('cor primária é o Rubi do site oficial (#B51F4D)', () {
      expect(AppColors.primary, const Color(0xFFB51F4D));
    });

    test('pressed é o Rubi Escuro (#9A0835)', () {
      expect(AppColors.primaryPressed, const Color(0xFF9A0835));
    });

    test('buildAppTheme retorna tema Material 3 com primary Rubi', () {
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
