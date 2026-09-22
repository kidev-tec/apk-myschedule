// B6: testes widget das visões da agenda (dia/semana/mês).
// DioAdapter mocka a API; UpdateService é noop via onCheckUpdate.

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
import 'package:minha_agenda/features/agenda/agenda_page.dart';

Widget _wrap(ApiClient api) {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
        path: '/', builder: (_, __) => AgendaPage(onCheckUpdate: () async {})),
    GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('SETTINGS'))),
    GoRoute(
        path: '/agenda/booking',
        builder: (_, __) => const Scaffold(body: Text('WIZARD'))),
  ]);
  return ProviderScope(
    overrides: [agendaApiProvider.overrideWithValue(api)],
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
    await initializeDateFormatting('pt_BR', null);
  });

  late DioAdapter adapter;
  late ApiClient api;
  final capturedQueries = <Map<String, dynamic>?>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    capturedQueries.clear();

    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    adapter.onGet(
      '/appointments',
      (s) {
        return s.reply(200, {
          'appointments': [
            {
              'id': 'a1',
              'client_name': 'Ana',
              'client_phone': '+5514999990001',
              'service_name': 'Corte',
              'starts_at': DateTime.now()
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
              'ends_at': DateTime.now()
                  .add(const Duration(hours: 2, minutes: 30))
                  .toIso8601String(),
              'status': 'confirmed',
              'source': 'app',
            },
          ]
        });
      },
      queryParameters: {'from': Matchers.any, 'to': Matchers.any},
    );

    api = ApiClient(adapter: adapter);
    // Captura a query real de cada GET /appointments
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.contains('/appointments') &&
          options.method == 'GET' &&
          !options.path.contains('confirm-link')) {
        capturedQueries.add(options.queryParameters);
      }
      handler.next(options);
    }));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
  }

  testWidgets('abre na visão DIA com seletor Dia/Semana/Mês', (tester) async {
    await pumpPage(tester);
    expect(find.text('Dia'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Mês'), findsOneWidget);
    // agendamento do dia aparece (card com o nome do cliente)
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('troca pra SEMANA: janela de 7 dias, agendamento agrupado',
      (tester) async {
    await pumpPage(tester);
    final diaQueries = capturedQueries.length;
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    // consulta refeita com janela de 7 dias (to - from == 7d)
    expect(capturedQueries.length, greaterThan(diaQueries));
    final q = capturedQueries.last;
    final from = DateTime.parse(q!['from'] as String);
    final to = DateTime.parse(q['to'] as String);
    expect(to.difference(from).inDays, 7);
    // começa no domingo da semana do dia focado
    expect(from.weekday, DateTime.sunday);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('MÊS abre o picker com dias e volta pra visão dia',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    // bottom sheet do mês: dia 1 existe sempre no grid
    expect(find.text('1'), findsWidgets);

    // toca num dia → fecha o sheet e volta pra agenda diária
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(find.text('Dia'), findsOneWidget);
  });

  testWidgets('navegação de dias mantém a visão corrente', (tester) async {
    await pumpPage(tester);
    final antes = capturedQueries.length;
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    // refetch da janela seguinte, seletor continua visível
    expect(capturedQueries.length, greaterThan(antes));
    expect(find.text('Dia'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Mês'), findsOneWidget);
  });

  testWidgets('botão Hoje some quando já estás em hoje, volta ao navegar',
      (tester) async {
    await pumpPage(tester);
    // em hoje: sem caminho redundante (1 ação dominante por tela)
    expect(find.byTooltip('Hoje'), findsNothing);

    // navega → Hoje volta como atalho pra voltar
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hoje'), findsOneWidget);

    // toca Hoje → volta pro dia corrente e some de novo
    await tester.tap(find.byTooltip('Hoje'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hoje'), findsNothing);
  });

  testWidgets('picker do mês vazio mostra "Nada agendado neste mês"',
      (tester) async {
    // nenhum evento no mês
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [],
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});

    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    expect(find.text('Nada agendado neste mês'), findsOneWidget);
  });

  testWidgets('picker do mês COM eventos não mostra texto de vazio',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    expect(find.text('Nada agendado neste mês'), findsNothing);
  });
}
