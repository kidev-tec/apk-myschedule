import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minha_agenda/core/segment/segment_preset.dart';
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

    test('buildAppTheme(null) usa o preset beauty (default)', () {
      final theme = buildAppTheme(null);
      expect(theme.colorScheme.primary, SegmentPresets.beauty.primary);
      expect(theme.colorScheme.secondary, SegmentPresets.beauty.secondary);
    });

    test('buildAppTheme(barber) colore o scheme com o Âmbar couro', () {
      final barber = SegmentPreset.byId('barber');
      final theme = buildAppTheme(barber);

      expect(theme.colorScheme.primary, barber.primary);
      expect(theme.colorScheme.secondary, barber.secondary);
      expect(theme.colorScheme.primary, isNot(AppColors.primary));
    });

    test('tokens de tipografia apontam pras fontes do site', () {
      expect(AppTypography.displayFamily, 'Marcellus');
      expect(AppTypography.bodyFamily, 'Poppins');
      expect(AppTypography.textTheme.bodyMedium?.fontSize, 14);
      expect(AppTypography.textTheme.displayLarge?.fontFamily, 'Marcellus');
    });
  });

  group('AppColors contextuais (derivadas do scheme do tema ativo)', () {
    Widget host(WidgetBuilder builder) => MaterialApp(
          theme: buildAppTheme(SegmentPreset.byId('barber')),
          home: Builder(builder: builder),
        );

    testWidgets('primaryOf lê do segmento ativo (barber = âmbar)', (tester) async {
      Color? got;
      await tester.pumpWidget(host((context) {
        got = AppColors.primaryOf(context);
        return const SizedBox.shrink();
      }));

      expect(got, SegmentPreset.byId('barber').primary);
    });

    testWidgets('softOf = primary com alpha 0.12', (tester) async {
      Color? got;
      await tester.pumpWidget(host((context) {
        got = AppColors.softOf(context);
        return const SizedBox.shrink();
      }));

      expect(((got!.a * 255.0).round()), closeTo((255 * 0.12).round(), 1));
      expect((got!.r * 255.0).round(), (SegmentPreset.byId('barber').primary.r * 255.0).round());
    });

    testWidgets('midOf = primary com alpha 0.45', (tester) async {
      Color? got;
      await tester.pumpWidget(host((context) {
        got = AppColors.midOf(context);
        return const SizedBox.shrink();
      }));

      expect((got!.a * 255.0).round(), closeTo((255 * 0.45).round(), 1));
    });
  });

  group('tema aplicado nos componentes', () {
    testWidgets('appBar branco, texto neutral, sem elevation', (tester) async {
      final theme = buildAppTheme();
      expect(theme.appBarTheme.backgroundColor, AppColors.surface);
      expect(theme.appBarTheme.foregroundColor, AppColors.neutral);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.centerTitle, isTrue);
    });

    testWidgets('FilledButton Rubi com cantos 12', (tester) async {
      final theme = buildAppTheme();
      final style = theme.filledButtonTheme.style;
      expect(style?.backgroundColor?.resolve({}), AppColors.primary);
      expect(style?.foregroundColor?.resolve({}), Colors.white);
    });

    testWidgets('inputs com fill rosa translúcido e borda focus Rubi',
        (tester) async {
      final theme = buildAppTheme();
      final input = theme.inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(
        input.fillColor,
        AppColors.pinkSoft.withValues(alpha: 0.3),
      );
      expect(input.focusedBorder?.borderSide.color, AppColors.primary);
      expect(input.focusedBorder?.borderSide.width, 2);
      expect(input.border?.borderSide.color, AppColors.pinkMid);
    });
  });
}
