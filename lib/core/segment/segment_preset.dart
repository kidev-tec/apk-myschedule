import 'package:flutter/material.dart';

/// Presets de segmento — decisão multi-segmento (Rafael, 09/09/2026).
/// O preset define cor primária, ícone, copy e serviços sugeridos.
/// É ponto de partida: o usuário customiza por cima.
class SegmentPreset {
  final String id;
  final String label;
  final IconData icon;
  final Color primary;
  final Color primaryPressed;
  final Color secondary;
  final List<({String name, int durationMin, int priceCents})>
      suggestedServices;

  const SegmentPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.primary,
    required this.primaryPressed,
    required this.secondary,
    required this.suggestedServices,
  });

  static const _rubi = Color(0xFFB51F4D);
  static const _rubiPressed = Color(0xFF9A0835);

  static const all = [
    SegmentPreset(
      id: 'beauty',
      label: 'Estética & Beleza',
      icon: Icons.face_retouching_natural,
      primary: _rubi,
      primaryPressed: _rubiPressed,
      secondary: Color(0xFFE8A7BC),
      suggestedServices: [
        (name: 'Corte', durationMin: 60, priceCents: 8000),
        (name: 'Escova', durationMin: 45, priceCents: 6000),
        (name: 'Manicure', durationMin: 60, priceCents: 5000),
      ],
    ),
    SegmentPreset(
      id: 'barber',
      label: 'Barbearia',
      icon: Icons.content_cut,
      primary: Color(0xFF8B5E34), // Âmbar couro
      primaryPressed: Color(0xFF6D4524),
      secondary: Color(0xFFE7D8C5),
      suggestedServices: [
        (name: 'Corte máquina', durationMin: 40, priceCents: 5000),
        (name: 'Barba', durationMin: 30, priceCents: 3500),
        (name: 'Combo corte + barba', durationMin: 60, priceCents: 7500),
      ],
    ),
    SegmentPreset(
      id: 'dental',
      label: 'Odontologia',
      icon: Icons.medical_services_outlined,
      primary: Color(0xFF1976D2), // Azul clínico
      primaryPressed: Color(0xFF125AA5),
      secondary: Color(0xFFDBEAF8),
      suggestedServices: [
        (name: 'Consulta', durationMin: 40, priceCents: 20000),
        (name: 'Limpeza', durationMin: 60, priceCents: 25000),
        (name: 'Avaliação', durationMin: 30, priceCents: 15000),
      ],
    ),
    SegmentPreset(
      id: 'medical',
      label: 'Medicina',
      icon: Icons.health_and_safety_outlined,
      primary: Color(0xFF00897B), // Verde clínico
      primaryPressed: Color(0xFF00695F),
      secondary: Color(0xFFD7F0EC),
      suggestedServices: [
        (name: 'Consulta', durationMin: 40, priceCents: 30000),
        (name: 'Retorno', durationMin: 20, priceCents: 10000),
      ],
    ),
    SegmentPreset(
      id: 'auto_detailing',
      label: 'Estética Automotiva',
      icon: Icons.directions_car_filled,
      primary: Color(0xFF37474F), // Grafite
      primaryPressed: Color(0xFF263238),
      secondary: Color(0xFFDCE3E8),
      suggestedServices: [
        (name: 'Lavagem simples', durationMin: 60, priceCents: 6000),
        (name: 'Polimento', durationMin: 240, priceCents: 35000),
        (name: 'Higienização interna', durationMin: 180, priceCents: 28000),
      ],
    ),
    SegmentPreset(
      id: 'pet_grooming',
      label: 'Banho e Tosa',
      icon: Icons.pets,
      primary: Color(0xFFF57C00), // Laranja pet
      primaryPressed: Color(0xFFD96700),
      secondary: Color(0xFFFDEBD7),
      suggestedServices: [
        (name: 'Banho pequeno porte', durationMin: 60, priceCents: 6000),
        (name: 'Tosa higiênica', durationMin: 45, priceCents: 5000),
        (name: 'Banho + tosa', durationMin: 120, priceCents: 9000),
      ],
    ),
    SegmentPreset(
      id: 'veterinary',
      label: 'Veterinária',
      icon: Icons.volunteer_activism_outlined,
      primary: Color(0xFF2E7D32), // Verde saúde
      primaryPressed: Color(0xFF1B5E20),
      secondary: Color(0xFFDCEFE0),
      suggestedServices: [
        (name: 'Consulta', durationMin: 40, priceCents: 25000),
        (name: 'Vacinação', durationMin: 20, priceCents: 15000),
      ],
    ),
    SegmentPreset(
      id: 'mechanic',
      label: 'Mecânica',
      icon: Icons.build_circle_outlined,
      primary: Color(0xFF455A64), // Azul aço
      primaryPressed: Color(0xFF32414A),
      secondary: Color(0xFFDEE5E9),
      suggestedServices: [
        (name: 'Revisão', durationMin: 120, priceCents: 30000),
        (name: 'Troca de óleo', durationMin: 45, priceCents: 12000),
      ],
    ),
    SegmentPreset(
      id: 'other',
      label: 'Outro',
      icon: Icons.calendar_today_outlined,
      primary: Color(0xFF5E35B1), // Roxo neutro
      primaryPressed: Color(0xFF4527A0),
      secondary: Color(0xFFE8E0F5),
      suggestedServices: [],
    ),
  ];

  static SegmentPreset byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

/// Alias estático para defaults legíveis (usado em buildAppTheme).
class SegmentPresets {
  static SegmentPreset get beauty => SegmentPreset.byId('beauty');

  /// Tema da MARCA AGENVA (DESIGN.md v2 — paleta do logo). É o default do
  /// app antes do usuário escolher segmento: splash, login e onboarding
  /// passo 0 usam o azul da marca; dentro da agenda vence o preset do
  /// segmento (decisão multi-segmento 09/09).
  static const SegmentPreset brand = SegmentPreset(
    id: '__brand__',
    label: 'AGENVA',
    icon: Icons.event_available,
    primary: Color(0xFF1E96E8), // agenva-blue
    primaryPressed: Color(0xFF1573B5), // derivado escuro
    secondary: Color(0xFF54B7EA), // agenva-sky
    suggestedServices: [],
  );
}
