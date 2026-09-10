import 'package:flutter/material.dart';
import '../core/segment/segment_preset.dart';

/// Tema Rubi — tokens extraídos do site oficial da Oficina da Beleza
/// (ver .planning/tokens.json no repo de planejamento).
///
/// Cor dominante do site: Rubi #B51F4D (5 ocorrências).
/// Pressed state: Rubi Escuro #9A0835.
class AppColors {
  static const Color primary = Color(0xFFB51F4D); // Rubi (default beauty)
  static const Color primaryPressed = Color(0xFF9A0835); // Rubi Escuro
  static const Color pinkSoft = Color(0xFFF7E3E9); // Rosa Suave
  static const Color pinkMid = Color(0xFFE8A7BC); // Rosa Médio
  static const Color neutral = Color(0xFF2B2B2B); // Texto principal
  static const Color neutralDark = Color(0xFF1A1A1A); // Fundo escuro
  static const Color surface = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFC62828);
  static const Color success = Color(0xFF2E7D32);

  /// Cores do TEMA ATIVO (respeitam o segmento escolhido).
  ///
  /// Usar AppColors.primary direto nos widgets hardcoda o Rubi e ignora o
  /// segmento — barbearia ficava rosa. Estes getters leem do ColorScheme
  /// do ThemeData em vigor, que o buildAppTheme(preset) já coloriu.
  static Color primaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Tom suave (container) derivado do primary ativo — substitui pinkSoft.
  static Color softOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);

  /// Tom médio derivado do primary ativo — substitui pinkMid.
  static Color midOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary.withValues(alpha: 0.45);
}

/// Tipografia: Marcellus (títulos, serif elegante do site) + Poppins (corpo).
/// Fontes são assets — ver pubspec.yaml. Fallback para fontes do sistema
/// até os TTFs serem baixados (F0-T2 pendência visual).
class AppTypography {
  static const String displayFamily = 'Marcellus';
  static const String bodyFamily = 'Poppins';

  static TextTheme get textTheme => const TextTheme(
        displayLarge: TextStyle(
            fontFamily: displayFamily,
            fontSize: 32,
            fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(
            fontFamily: displayFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400),
        titleLarge: TextStyle(
            fontFamily: displayFamily,
            fontSize: 20,
            fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(fontFamily: bodyFamily, fontSize: 14),
        bodySmall: TextStyle(fontFamily: bodyFamily, fontSize: 12),
        labelLarge: TextStyle(
            fontFamily: bodyFamily, fontSize: 14, fontWeight: FontWeight.w600),
      );
}

ThemeData buildAppTheme([SegmentPreset? preset]) {
  final p = preset ?? SegmentPresets.beauty;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      primary: p.primary,
      secondary: p.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    textTheme: AppTypography.textTheme,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.neutral,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: AppTypography.displayFamily,
        fontSize: 20,
        color: AppColors.neutral,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Pressed → Rubi Escuro #9A0835 (site oficial)
        // Overlay darkening nativo do Material 3 cobre; cor explícita
        // no pressedState via WidgetStateProperty quando necessário.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.pinkSoft.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.pinkMid),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );
}
