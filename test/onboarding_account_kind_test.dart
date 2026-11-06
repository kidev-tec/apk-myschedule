// Módulo agregador (API 0026): passo 0 do onboarding escolhe o tipo da conta.
// Independente é o padrão e segue o fluxo de sempre; estabelecimento termina
// no perfil (serviços/horários opcionais — D4) e chama PUT /me/account-kind.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/onboarding/onboarding_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;
  final calls = <String>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(
        adapter: adapter, idToken: ({forceRefresh = false}) async => null);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      calls.add('${o.method} ${o.path} ${o.data}');
      h.next(o);
    }));
    adapter
      ..onPatch('/me', (s) => s.reply(200, {'ok': true}), data: Matchers.any)
      ..onPut('/me/account-kind',
          (s) => s.reply(200, {'account_kind': 'aggregator'}),
          data: Matchers.any);
  });

  Widget wrap() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, __) => OnboardingPage(api: api)),
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

  testWidgets('passo 0 pergunta o tipo da conta com independente marcado',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    expect(find.text('Como você vai usar o Agenva?'), findsOneWidget);
    expect(find.text('Atendo meus clientes'), findsOneWidget);
    expect(find.text('Tenho um estabelecimento com profissionais'),
        findsOneWidget);
    // independente é o padrão: só ele com o rádio marcado
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    final checked = tester.getTopLeft(find.byIcon(Icons.radio_button_checked));
    final indep = tester.getTopLeft(find.text('Atendo meus clientes'));
    expect((checked.dy - indep.dy).abs() < 40, isTrue);
    // 5 passos na barra de progresso do independente
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets(
      'estabelecimento: termina no perfil, sem serviço/horário, e vira agregador',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tenho um estabelecimento com profissionais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar')); // → segmento
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar')); // → perfil
    await tester.pumpAndSettle();
    expect(find.text('Seu estabelecimento'), findsOneWidget);
    // último passo do estabelecimento: botão já diz Começar, sem Pular
    expect(find.text('Começar'), findsOneWidget);
    expect(find.text('Pular'), findsNothing);
    // nome é obrigatório
    await tester.tap(find.text('Começar'));
    await tester.pump();
    expect(find.text('Qual é o nome do seu espaço?'), findsOneWidget);
    // tira o aviso para não cobrir o botão
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Studio Central');
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(find.text('AGENDA FINAL'), findsOneWidget);
    expect(calls.any((c) => c.startsWith('PUT /me/account-kind')), isTrue);
    expect(calls.any((c) => c.contains('aggregator')), isTrue);
    expect(calls.any((c) => c.contains('Studio Central')), isTrue);
    // nada de serviço nem horário
    expect(calls.any((c) => c.contains('/services')), isFalse);
    expect(calls.any((c) => c.contains('/working-hours')), isFalse);
  });

  testWidgets('voltar para independente no passo 0 mantém o fluxo completo',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tenho um estabelecimento com profissionais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atendo meus clientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Seu espaço'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });
}
