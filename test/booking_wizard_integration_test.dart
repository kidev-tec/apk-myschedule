import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/agenda/booking_wizard.dart';

Widget _wrapWithApi(ApiClient api) {
  // GoRouter mínimo: o wizard faz context.go('/agenda') no sucesso do POST.
  // Sem router, o go() lança ANTES do SnackBar de sucesso — página AGENDA
  // dummy prova que a navegação aconteceu.
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => const BookingWizardPage()),
    GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('PAGINA AGENDA'))),
  ]);
  return ProviderScope(
    // Sobrescreve o wizardApiProvider DO PRÓPRIO wizard (booking_wizard.dart) —
    // não criar provider duplicado aqui, senão o override não pega.
    overrides: [wizardApiProvider.overrideWithValue(api)],
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

  setUpAll(() async {
    // O wizard usa DateFormat('pt_BR') — main.dart inicializa os dados de
    // locale; em teste a gente faz o mesmo (DateFormat enxerga 'pt_BR').
    await initializeDateFormatting('pt_BR', null);
  });

  late DioAdapter adapter;
  late ApiClient api;
  final posted = <Map<String, dynamic>>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    posted.clear();

    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    adapter.onGet(
        '/clients',
        (s) => s.reply(200, [
              {'id': 'c1', 'name': 'Ana', 'phone_e164': '+5514999990001'},
              {'id': 'c2', 'name': 'Beto', 'phone_e164': '+5514999990002'},
            ]));
    adapter.onGet(
        '/services',
        (s) => s.reply(200, [
              {
                'id': 's1',
                'name': 'Corte',
                'duration_min': 60,
                'price_cents': 5000
              },
            ]));
    adapter.onGet(
        '/working-hours',
        (s) => s.reply(200, [
              {'weekday': 1, 'start_time': '09:00', 'end_time': '12:00'},
            ]));
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                {
                  'id': 'a1',
                  'starts_at': '2026-09-14T09:00:00.000Z',
                  'ends_at': '2026-09-14T10:00:00.000Z',
                  'status': 'confirmed',
                },
              ],
            }));
    adapter.onPost('/appointments', (s) => s.reply(201, {'id': 'new-1'}),
        data: Matchers.any);

    api = ApiClient(adapter: adapter);
    // Captura o payload real do POST no dio DO ApiClient (o dio do adapter é
    // outro — interceptors lá não veem os requests do app).
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST') {
        posted.add(Map<String, dynamic>.from(options.data as Map));
      }
      handler.next(options);
    }));
  });

  testWidgets('fluxo completo: cliente → serviço → slot → POST /appointments',
      (tester) async {
    await tester.pumpWidget(_wrapWithApi(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // Step 1: escolhe cliente Ana
    expect(find.text('Escolhe o cliente'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Beto'), findsOneWidget);
    // botão desabilitado antes da seleção
    final btn1 = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'));
    expect(btn1.onPressed, isNull);

    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Step 2: escolhe serviço Corte
    expect(find.text('Escolhe o serviço'), findsOneWidget);
    expect(find.textContaining('Corte'), findsOneWidget);
    await tester.tap(find.text('Corte'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Step 3: slots — o dia corrente pode não ter working hour (fixture =
    // segunda). Navega com o chevron até a PRÓXIMA segunda (dinâmico:
    // teste data-dependent com "3 cliques" quebrava quando o calendário andou).
    expect(find.text('Escolhe o horário'), findsOneWidget);
    final today = DateTime.now();
    final daysToMonday = (DateTime.monday - today.weekday) % 7;
    final taps = daysToMonday == 0 ? 7 : daysToMonday;
    if (today.weekday != DateTime.monday) {
      // estado vazio visível (sem slots hoje) — valida o empty state do step
      expect(find.text('Sem horários livres neste dia'), findsOneWidget);
    }
    for (var i = 0; i < taps; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }
    // appt 09-10 bloqueado; primeiro livre deve ser 10:00
    expect(find.text('10:00'), findsOneWidget); // pós-conflito
    await tester.tap(find.text('10:00'));
    await tester.pump();

    await tester.ensureVisible(find.text('Confirmar agendamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar agendamento'));
    await tester.pumpAndSettle();

    // POST 201 → wizard navega pra /agenda (prova que o fluxo concluiu)
    expect(find.text('PAGINA AGENDA'), findsOneWidget);

    // payload validado: campos que o wizard manda (capturado no interceptor)
    expect(posted, hasLength(1));
    expect(posted.first['clientId'], 'c1');
    expect(posted.first['serviceId'], 's1');
    // source foi removido: a API só aceita 'block' ou ausente
    expect(posted.first.containsKey('source'), isFalse);
    expect(DateTime.parse(posted.first['startsAt'] as String).hour, 10);
    // ends_at = starts_at + duração do serviço (60min)
    final start = DateTime.parse(posted.first['startsAt'] as String);
    final end = DateTime.parse(posted.first['endsAt'] as String);
    expect(end.difference(start), const Duration(minutes: 60));
  });

  testWidgets('fluxo: POST falha → SnackBar de erro, sem sucesso',
      (tester) async {
    adapter.onPost(
        '/appointments',
        (s) => s.reply(409, {
              'error': 'slot já reservado',
            }),
        data: Matchers.any);

    await tester.pumpWidget(_wrapWithApi(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corte'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // navega a data até a próxima segunda (dinâmico, não data-fixo)
    final today2 = DateTime.now();
    final days2 = (DateTime.monday - today2.weekday) % 7;
    final taps2 = days2 == 0 ? 7 : days2;
    if (today2.weekday != DateTime.monday) {
      expect(find.text('Sem horários livres neste dia'), findsOneWidget);
    }
    for (var i = 0; i < taps2; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('10:00'));
    await tester.pump();
    await tester.ensureVisible(find.text('Confirmar agendamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar agendamento'));
    await tester.pumpAndSettle();

    // 409 → fica no wizard, sem navegar, com SnackBar de erro
    expect(find.text('PAGINA AGENDA'), findsNothing);
    expect(find.textContaining('Falha'), findsOneWidget);
  });

  testWidgets('busca filtra clientes por nome', (tester) async {
    await tester.pumpWidget(_wrapWithApi(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Buscar cliente'), 'Ana');
    await tester.pump();

    // Card do cliente Ana (Text dentro de Card, não o EditableText da busca)
    expect(_clientCard(tester, 'Ana'), findsOneWidget);
    expect(_clientCard(tester, 'Beto'), findsNothing);
  });

  testWidgets('busca vazia mostra botão Adicionar cliente → cria e seleciona',
      (tester) async {
    await tester.pumpWidget(_wrapWithApi(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // busca sem resultado → empty state com botão de criar
    await tester.enterText(
        find.widgetWithText(TextField, 'Buscar cliente'), 'Zé Novato');
    await tester.pump();
    expect(find.text('Nenhum cliente encontrado'), findsOneWidget);
    expect(find.text('Adicionar cliente'), findsOneWidget);

    adapter.onPost(
        '/clients',
        (s) => s.reply(201,
            {'id': 'c-novo', 'name': 'Zé Novato', 'phone_e164': '+5514999977'}),
        data: Matchers.any);

    await tester.tap(find.text('Adicionar cliente'));
    await tester.pumpAndSettle();

    // bottom sheet: preenche nome + telefone e salva
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Zé Novato');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '+5514999977');
    await tester.tap(find.text('Criar e usar'));
    await tester.pumpAndSettle();

    // sheet fechou e o cliente novo JÁ tá selecionado no wizard
    expect(find.byType(BottomSheet), findsNothing);
    expect(_clientCard(tester, 'Zé Novato'), findsOneWidget);
    // Continuar habilitado = cliente selecionado
    final btn = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets(
      'criar cliente com telefone duplicado (409) → oferece selecionar existente',
      (tester) async {
    await tester.pumpWidget(_wrapWithApi(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Buscar cliente'), 'Zé Novato');
    await tester.pump();
    await tester.tap(find.text('Adicionar cliente'));
    await tester.pumpAndSettle();

    adapter.onPost(
        '/clients',
        (s) => s.reply(409, {
              'error': 'Já existe um cliente com esse telefone',
              'existing': {
                'id': 'c1',
                'name': 'Ana',
                'phone_e164': '+551****0001'
              },
            }),
        data: Matchers.any);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Zé Novato');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '+551****0001');
    await tester.tap(find.text('Criar e usar'));
    await tester.pumpAndSettle();

    // 409 → oferece o cliente existente; tocar nele seleciona e fecha
    expect(find.text('Já existe um cliente com esse telefone'), findsOneWidget);
    await tester.tap(find.text('Usar Ana'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    // Ana aparece no card E no botão "Usar Ana" sumiu; o card conta 1x
    expect(_clientCard(tester, 'Ana'), findsWidgets);
    final btn = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'));
    expect(btn.onPressed, isNotNull);
  });
}

Finder _clientCard(WidgetTester tester, String name) {
  return find.descendant(
    of: find.byType(Card),
    matching: find.text(name),
  );
}
