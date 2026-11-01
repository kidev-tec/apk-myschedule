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

import 'package:flutter/services.dart';

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

/// Máscara BR enquanto digita: (11) 98765-4321 (celular) / (11) 3456-7890
/// (fixo). Só dígitos, até 11. Mesma regra do link público (maskPhone).
String maskPhoneBr(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  // colou com DDI (+55 11 98765-4321): tira o 55. Com 11 dígitos, 55 é DDD
  // (RS) e fica.
  if (d.length > 11 && d.startsWith('55')) d = d.substring(2);
  if (d.length > 11) d = d.substring(0, 11);
  if (d.isEmpty) return '';
  if (d.length <= 2) return '($d';
  final ddd = d.substring(0, 2);
  if (d.length <= 6) return '($ddd) ${d.substring(2)}';
  if (d.length <= 10) {
    return '($ddd) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  return '($ddd) ${d.substring(2, 7)}-${d.substring(7)}';
}

/// Telefone salvo (E.164 BR, ex.: 5511987654321) pra exibir no campo com
/// máscara, sem o 55. Fora do padrão BR, devolve como veio.
String phoneForDisplay(String e164) {
  final d = e164.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('55') && d.length >= 12 && d.length <= 13) {
    return maskPhoneBr(d.substring(2));
  }
  if (d.length >= 10 && d.length <= 11) return maskPhoneBr(d);
  return e164;
}

/// TextInputFormatter com [maskPhoneBr] (cursor vai pro fim).
class PhoneBrInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = maskPhoneBr(newValue.text);
    return TextEditingValue(
        text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
