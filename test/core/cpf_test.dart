import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/utils/cpf.dart';

void main() {
  test('CPF válido (com ou sem máscara)', () {
    for (final c in [
      '52998224725',
      '529.982.247-25',
      '11144477735',
      '10000000108'
    ]) {
      expect(isValidCpf(c), isTrue, reason: c);
    }
  });

  test('CPF inválido', () {
    for (final c in ['52998224724', '11111111111', '123', '']) {
      expect(isValidCpf(c), isFalse, reason: c);
    }
  });

  test('formata CPF e CEP', () {
    expect(formatCpf('52998224725'), '529.982.247-25');
    expect(formatCep('17012000'), '17012-000');
    expect(formatCpf(null), '');
  });
}
