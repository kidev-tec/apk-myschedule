/// Normalização de telefone para E.164 BR (padrão exigido pelo wa.me).
///
/// O WhatsApp só resolve números em formato internacional. O usuário leigo
/// digita o telefone local (`(14) 99999-9999`) — prefixamos o DDI 55 quando
/// ausente. Regras:
/// - Extrai só dígitos
/// - Já começa com `55` e tem 12–13 dígitos → mantém
/// - 10–11 dígitos (fixal/celular BR) → prefixa `55`
/// - < 10 dígitos → retorna vazio (inválido, chamador valida)
library;

String normalizePhoneBr(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('55') && digits.length >= 12 && digits.length <= 13) {
    return digits;
  }
  if (digits.length >= 10 && digits.length <= 11) {
    return '55$digits';
  }
  return '';
}

/// Garante DDI 55 num telefone já semi-normalizado (só dígitos ou formatado).
/// Diferente de [normalizePhoneBr]: nunca descarta — se não conseguir validar,
/// devolve os dígitos com `55` na frente (best-effort pra link wa.me).
String ensureDdi55(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('55') && digits.length >= 12) return digits;
  return '55$digits';
}
