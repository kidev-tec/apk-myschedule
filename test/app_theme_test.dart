import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:minha_agenda_app/main.dart';
import 'package:minha_agenda_app/theme/app_theme.dart';

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

    testWidgets('HomePage renderiza título e botão Entrar', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HomePage())),
      );

      expect(find.text('Minha Agenda'), findsOneWidget);
      expect(find.text('Oficina da Beleza'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    });

    testWidgets('botão Entrar usa a cor primária Rubi', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Entrar'),
      );
      final style = button.style ?? buildAppTheme().filledButtonTheme.style!;
      final bgColor = style.backgroundColor?.resolve({});
      expect(bgColor, AppColors.primary);
    });
  });
}
