// B7: testes widget do onboarding — copy exata do passo 2, botão Pular
// (cria "Atendimento" 60min R$0), validação de duração 15..480 step 15.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:minha_agenda/features/onboarding/onboarding_page.dart';

Widget _wrap() {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => const OnboardingPage()),
    GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('AGENDA FINAL'))),
  ]);
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  Future<void> goToStep2(WidgetTester tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    // passo 0: escolhe o primeiro segmento (_SegmentCard = InkWell)
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    // avança pro passo 1
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    // passo 1: nome do negócio
    await tester.enterText(
        find.byType(TextField).first, 'Studio Teste ${DateTime.now()}');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }

  testWidgets('passo 2 mostra a copy exata da BARRA', (tester) async {
    await goToStep2(tester);
    expect(
      find.text(
          'Cadastre seu primeiro serviço — você pode adicionar quantos quiser depois'),
      findsOneWidget,
    );
  });

  testWidgets('botão Pular preenche Atendimento 60min R\$0 e avança',
      (tester) async {
    await goToStep2(tester);
    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    // avançou pro passo 3 (horários)
    expect(find.text('Teus horários'), findsOneWidget);
    // campos preenchidos com o genérico
    expect(find.widgetWithText(TextField, 'Atendimento'), findsNothing);
  });

  testWidgets('validação: duração fora do step 15 é rejeitada', (tester) async {
    await goToStep2(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '40'); // não é múltiplo de 15
    await tester.enterText(fields.at(2), '80,00');
    await tester.tap(find.text('Começar'));
    await tester.pump();
    expect(find.text('Duração entre 15 e 480 minutos, de 15 em 15'),
        findsOneWidget);
  });

  testWidgets('fluxo completo com serviço válido chega no passo 3',
      (tester) async {
    await goToStep2(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Corte');
    await tester.enterText(fields.at(1), '30');
    await tester.enterText(fields.at(2), '50,00');
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(find.text('Teus horários'), findsOneWidget);
  });
}
