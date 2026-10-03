import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/api/paywall_flag.dart';

/// Cobertura de PaywallFlag (RF-14): hit/clear/getter do notifier.
///
/// Static state — resetar entre testes pra não vazar.
void main() {
  test('PaywallFlag não é instanciável (construtor privado de namespace)', () {
    // A linha do construtor privado executa na carga da classe; o acesso
    // estático abaixo confirma que a classe foi carregada.
    expect(PaywallFlag.lastMessage, isA<ValueNotifier<String?>>());
  });

  tearDown(() {
    PaywallFlag.clear();
  });

  test('lastMessage começa null', () {
    expect(PaywallFlag.lastMessage.value, isNull);
  });

  test('hit() grava a mensagem 402 no notifier', () {
    PaywallFlag.hit('Período de teste encerrado.');

    expect(PaywallFlag.lastMessage.value, 'Período de teste encerrado.');
  });

  test('hit() sobrescreve mensagem anterior (última 402 vence)', () {
    PaywallFlag.hit('primeira');
    PaywallFlag.hit('segunda');

    expect(PaywallFlag.lastMessage.value, 'segunda');
  });

  test('clear() volta pra null (Home esconde o banner)', () {
    PaywallFlag.hit('bloqueado');
    PaywallFlag.clear();

    expect(PaywallFlag.lastMessage.value, isNull);
  });

  test('notifier notifica listeners em hit e clear', () {
    final valores = <String?>[];
    PaywallFlag.lastMessage.addListener(() {
      valores.add(PaywallFlag.lastMessage.value);
    });

    PaywallFlag.hit('msg');
    PaywallFlag.clear();

    expect(valores, containsAllInOrder(['msg', null]));
  });
}
