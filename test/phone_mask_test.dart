import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/utils/phone_br.dart';

void main() {
  test('maskPhoneBr formata enquanto digita', () {
    expect(maskPhoneBr(''), '');
    expect(maskPhoneBr('1'), '(1');
    expect(maskPhoneBr('11'), '(11');
    expect(maskPhoneBr('1198'), '(11) 98');
    expect(maskPhoneBr('1134567890'), '(11) 3456-7890'); // fixo
    expect(maskPhoneBr('11987654321'), '(11) 98765-4321'); // celular
    expect(maskPhoneBr('abc11def9'), '(11) 9');
    expect(maskPhoneBr('11987654321999'), '(11) 98765-4321'); // corta
  });

  test('colar com DDI 55 tira o 55; DDD 55 (RS) com 11 dígitos fica', () {
    expect(maskPhoneBr('+55 11 98765-4321'), '(11) 98765-4321');
    expect(maskPhoneBr('5514999990002'), '(14) 99999-0002');
    expect(maskPhoneBr('55991234567'), '(55) 99123-4567');
  });

  test('phoneForDisplay mostra o salvo (E.164) com máscara, sem 55', () {
    expect(phoneForDisplay('5511987654321'), '(11) 98765-4321');
    expect(phoneForDisplay('+551134567890'), '(11) 3456-7890');
    expect(phoneForDisplay('11987654321'), '(11) 98765-4321');
    expect(phoneForDisplay('123'), '123'); // fora do padrão: como veio
  });

  test('PhoneBrInputFormatter aplica a máscara e põe o cursor no fim', () {
    final v = PhoneBrInputFormatter().formatEditUpdate(
        TextEditingValue.empty, const TextEditingValue(text: '11987654321'));
    expect(v.text, '(11) 98765-4321');
    expect(v.selection.baseOffset, v.text.length);
  });

  test('normalizePhoneBr continua aceitando o texto mascarado', () {
    expect(normalizePhoneBr('(11) 98765-4321'), '5511987654321');
  });
}
