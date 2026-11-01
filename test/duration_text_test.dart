import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/utils/duration_text.dart';

void main() {
  test('duração por extenso', () {
    expect(humanDuration(1), '1 minuto');
    expect(humanDuration(55), '55 minutos');
    expect(humanDuration(60), '1 hora');
    expect(humanDuration(61), '1 hora e 1 minuto');
    expect(humanDuration(70), '1 hora e 10 minutos');
    expect(humanDuration(120), '2 horas');
    expect(humanDuration(150), '2 horas e 30 minutos');
    expect(humanDuration(480), '8 horas');
  });
}
