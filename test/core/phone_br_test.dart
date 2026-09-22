import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/utils/phone_br.dart';

void main() {
  group('normalizePhoneBr', () {
    test('celular local com formatação → 55 + dígitos', () {
      expect(normalizePhoneBr('(14) 99999-9999'), '5514999999999');
    });

    test('fixo local (10 dígitos) → prefixa 55', () {
      expect(normalizePhoneBr('14 3333-4444'), '551433334444');
    });

    test('já com 55 e DDD → mantém', () {
      expect(normalizePhoneBr('5514999999999'), '5514999999999');
    });

    test('55 formatado com + e espaços → mantém', () {
      expect(normalizePhoneBr('+55 (14) 99999-9999'), '5514999999999');
    });

    test('sem DDD (8-9 dígitos) → vazio (inválido)', () {
      expect(normalizePhoneBr('99999-9999'), '');
    });

    test('vazio → vazio', () {
      expect(normalizePhoneBr(''), '');
    });

    test('lixo sem dígitos suficientes → vazio', () {
      expect(normalizePhoneBr('abc 123'), '');
    });
  });

  group('ensureDdi55', () {
    test('sem 55 → prefixa', () {
      expect(ensureDdi55('14999999999'), '5514999999999');
    });

    test('já com 55 → mantém', () {
      expect(ensureDdi55('5514999999999'), '5514999999999');
    });

    test('curto demais → best-effort com 55 (não descarta)', () {
      expect(ensureDdi55('123'), '55123');
    });
  });
}
