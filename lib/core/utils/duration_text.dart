/// Duração em minutos por extenso, pra leigo ler de bate-pronto:
/// 55 → "55 minutos", 60 → "1 hora", 70 → "1 hora e 10 minutos",
/// 150 → "2 horas e 30 minutos", 1 → "1 minuto".
String humanDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hs = h == 1 ? '1 hora' : '$h horas';
  final ms = m == 1 ? '1 minuto' : '$m minutos';
  if (h == 0) return ms;
  if (m == 0) return hs;
  return '$hs e $ms';
}
