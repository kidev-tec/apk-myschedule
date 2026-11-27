import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Dinheiro no app: SEMPRE em centavos (int), igual à API. Nunca `double`
/// para guardar ou somar valor — só na hora de formatar.

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// 123456 → "R$ 1.234,56" (espaço normal entre o símbolo e o valor).
String formatCents(int cents) =>
    _brl.format(cents / 100).replaceAll(RegExp(r'\s'), ' ');

/// Texto digitado ("1.234,56", "R$ 80", "0,5") → centavos.
/// Vazio ou inválido → null.
int? parseMoney(String text) {
  final t = text.replaceAll(RegExp(r'[R$\s.]'), '');
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:,(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final reais = int.parse(m.group(1)!);
  final dec = (m.group(2) ?? '').padRight(2, '0');
  return reais * 100 + int.parse(dec);
}

/// Campo de valor que se preenche da direita para a esquerda, como em
/// maquininha: digitar 1, 2, 5, 0 mostra 0,01 → 0,12 → 1,25 → 12,50.
class CentsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    // limita a 9 dígitos (até R$ 9.999.999,99)
    final cents = int.parse(
        digits.length > 9 ? digits.substring(digits.length - 9) : digits);
    final text = centsToField(cents);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Centavos no formato do campo, sem "R$": 125000 → "1.250,00".
String centsToField(int cents) => formatCents(cents).replaceFirst(r'R$ ', '');
