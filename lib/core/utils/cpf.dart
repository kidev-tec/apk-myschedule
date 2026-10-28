// CPF/CEP: validação e máscara (o banco guarda só os dígitos).

String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');

/// CPF com dígitos verificadores válidos (aceita com ou sem máscara).
bool isValidCpf(String raw) {
  final d = _digits(raw);
  if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
  int digit(int len) {
    var sum = 0;
    for (var i = 0; i < len; i++) {
      sum += int.parse(d[i]) * (len + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return digit(9) == int.parse(d[9]) && digit(10) == int.parse(d[10]);
}

/// "52998224725" → "529.982.247-25" (vazio se não tiver 11 dígitos).
String formatCpf(String? raw) {
  final d = _digits(raw);
  if (d.length != 11) return d;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

/// "17012000" → "17012-000".
String formatCep(String? raw) {
  final d = _digits(raw);
  if (d.length != 8) return d;
  return '${d.substring(0, 5)}-${d.substring(5)}';
}

String onlyDigits(String? s) => _digits(s);
