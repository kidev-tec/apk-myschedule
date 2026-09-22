import 'package:flutter/material.dart';
import '../core/segment/segment_preset.dart';

/// Tema do AGENVA — default = identidade da MARCA (azul #1E96E8, paleta do
/// logo, ver DESIGN.md v2 em ~/logo-agenva/). Cor do SEGMENTO entra via
/// buildAppTheme(preset) após o onboarding.
class AppColors {
  // ---- Identidade AGENVA (DESIGN.md v2: paleta extraída do logo) ----
  static const Color agenvaBlue = Color(0xFF1E96E8); // primária da marca
  static const Color agenvaNavy = Color(0xFF16325C); // secundária (texto forte)
  static const Color agenvaSky = Color(0xFF54B7EA); // destaque/badges
  static const Color agenvaSurface = Color(0xFFF8F9FA); // fundo claro padrão

  static const Color primary = agenvaBlue; // default do PRODUTO (marca AGENVA)
  static const Color primaryPressed = Color(0xFF1573B5); // azul escuro derivado
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
  // Default = MARCA AGENVA (azul), não mais o preset beauty — evita o
  // "flash rosa" nas telas de marca antes do onboarding escolher segmento.
  final p = preset ?? SegmentPresets.brand;
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
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.primary,
        side: BorderSide(color: p.primary),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.primary.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary, width: 2),
      ),
    ),
  );
}
