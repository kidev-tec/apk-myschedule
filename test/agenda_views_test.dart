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
import 'package:intl/intl.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/push/push_events.dart';
import 'package:minha_agenda/features/agenda/agenda_page.dart';
import 'package:minha_agenda/features/agenda/block_time_page.dart';
import 'package:minha_agenda/features/agenda/booking_wizard.dart' as booking;

Widget _wrap(ApiClient api, {booking.Appointment? rescheduleResult}) {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
        path: '/', builder: (_, __) => AgendaPage(onCheckUpdate: () async {})),
    GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('SETTINGS'))),
    GoRoute(
        path: '/agenda/booking',
        builder: (ctx, __) => Scaffold(
            body: FilledButton(
                onPressed: () => ctx.pop(rescheduleResult),
                child: const Text('SALVAR REMARCAÇÃO')))),
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
    // sino da central de notificações no topo
    expect(find.byKey(const Key('notification-bell')), findsOneWidget);
  });

  testWidgets('remarcação recarrega agenda e oferece WhatsApp com horário novo',
      (tester) async {
    final novo = booking.Appointment(
        id: 'novo-id',
        startsAt: DateTime(2031, 1, 5, 14, 30),
        endsAt: DateTime(2031, 1, 5, 15, 30),
        status: 'confirmed');
    await tester.pumpWidget(_wrap(api, rescheduleResult: novo));
    await tester.pumpAndSettle();
    final antes = capturedQueries.length;
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remarcar'));
    await tester.pumpAndSettle();
    adapter.onGet('/appointments', (s) => s.reply(200, {'appointments': []}),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await tester.tap(find.text('SALVAR REMARCAÇÃO'));
    await tester.pumpAndSettle();
    expect(find.text('Avisar o cliente?'), findsOneWidget);
    expect(find.textContaining('05/01 às 14:30'), findsOneWidget);
    await tester.tap(find.text('Não precisa'));
    await tester.pumpAndSettle();
    expect(capturedQueries.length, greaterThan(antes));
    expect(find.text('Ana'), findsNothing,
        reason: 'a linha antiga deve sair da agenda após a remarcação');
  });

  testWidgets('consulta da agenda envia o período em UTC (sufixo Z)',
      (tester) async {
    await pumpPage(tester);
    final q = capturedQueries.last!;
    expect(q['from'] as String, endsWith('Z'));
    expect(q['to'] as String, endsWith('Z'));
    final hoje = DateTime.now();
    expect(DateTime.parse(q['from'] as String).toLocal(),
        DateTime(hoje.year, hoje.month, hoje.day));
  });

  testWidgets('push de novo agendamento recarrega a agenda aberta',
      (tester) async {
    await pumpPage(tester);
    final antes = capturedQueries.length;
    PushEvents.instance.handle({'type': 'new_booking', 'appointment_id': 'x'});
    await tester.pumpAndSettle();
    expect(capturedQueries.length, greaterThan(antes));
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
    final from = DateTime.parse(q!['from'] as String).toLocal();
    final to = DateTime.parse(q['to'] as String).toLocal();
    expect(to.difference(from).inDays, 7);
    // começa no domingo da semana do dia focado
    expect(from.weekday, DateTime.sunday);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('card mostra o ícone de cadastro pelo link (toque explica)',
      (tester) async {
    Map<String, dynamic> appt(
        String id, String nome, int hora, String? origin) {
      final hoje = DateTime.now();
      final base = DateTime(hoje.year, hoje.month, hoje.day, hora);
      return {
        'id': id,
        'client_name': nome,
        'client_phone': '+5514999990001',
        'service_name': 'Barba',
        'starts_at': base.toIso8601String(),
        'ends_at': base.add(const Duration(minutes: 30)).toIso8601String(),
        'status': 'pending',
        'source': 'public_link',
        if (origin != null) 'client_origin': origin,
      };
    }

    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                appt('p1', 'Teste de cadastro', 15, 'public_link'),
                appt('p2', 'Cliente Antigo', 16, 'app'),
                appt('p3', 'Sem Origem', 17, null),
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await pumpPage(tester);

    expect(find.byKey(const Key('client-public-link-badge')), findsOneWidget);
    expect(
        find.descendant(
            of: find.widgetWithText(Card, 'Teste de cadastro'),
            matching: find.byKey(const Key('client-public-link-badge'))),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('client-public-link-badge')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Cadastro feito pelo cliente'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // visão em grade também mostra o ícone, no cartão certo
    await tester.tap(find.byTooltip('Grade'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-public-link-badge')), findsOneWidget);
    expect(
        find.descendant(
            of: find.ancestor(
                of: find.text('Teste de cadastro'),
                matching: find.byType(Card)),
            matching: find.byKey(const Key('client-public-link-badge'))),
        findsOneWidget);
  });

  testWidgets('Ver bloqueio mostra dia, horário, duração e motivo; libera',
      (tester) async {
    final amanha = DateTime.now().add(const Duration(days: 1));
    final ini = DateTime(amanha.year, amanha.month, amanha.day, 16, 40);
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                {
                  'id': 'b1',
                  'client_name': '— bloqueio —',
                  'client_phone': '',
                  'service_name': 'Bloqueio',
                  'starts_at': ini.toIso8601String(),
                  'ends_at':
                      ini.add(const Duration(minutes: 50)).toIso8601String(),
                  'status': 'confirmed',
                  'source': 'block',
                  'canceled_reason': 'Almoço',
                },
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    final patches = <String>[];
    adapter.onPatch('/appointments/b1', (s) {
      patches.add('b1');
      return s.reply(200, {'appointment': {}});
    }, data: Matchers.any);
    await pumpPage(tester);
    // vai pro dia do bloqueio
    await tester.tap(find.byIcon(Icons.chevron_right).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('Ver bloqueio'), findsOneWidget);
    await tester.tap(find.text('Ver bloqueio'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('block-details')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('block-details-time'))).data,
        '16:40 às 17:30 (50 minutos)');
    expect(
        tester.widget<Text>(find.byKey(const Key('block-details-reason'))).data,
        'Almoço');

    await tester.tap(find.byKey(const Key('block-details-release')));
    await tester.pumpAndSettle();
    expect(patches, ['b1']);
  });

  testWidgets('cadeado abre a tela de bloqueio no dia aberto na agenda',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Bloquear horário'));
    await tester.pumpAndSettle();
    final page = tester.widget<BlockTimePage>(find.byType(BlockTimePage));
    final hoje = DateTime.now();
    expect(page.initialDate.year, hoje.year);
    expect(page.initialDate.month, hoje.month);
    expect(page.initialDate.day, hoje.day);
  });

  testWidgets(
      'Marcar horário e Bloquear ficam no topo, abaixo do seletor, sem FAB',
      (tester) async {
    await pumpPage(tester);
    expect(find.byType(FloatingActionButton), findsNothing);

    final marcar = find.text('Marcar horário');
    final bloquear = find.byTooltip('Bloquear horário');
    expect(marcar, findsOneWidget);
    expect(bloquear, findsOneWidget);

    // abaixo do seletor Dia/Semana/Mês e acima da lista
    final ySeletor = tester.getBottomLeft(find.text('Semana')).dy;
    expect(tester.getTopLeft(marcar).dy, greaterThan(ySeletor));
    expect(tester.getTopLeft(marcar).dy,
        lessThan(tester.getTopLeft(find.text('Ana')).dy));

    // bloquear vem logo em seguida, na mesma linha
    expect(tester.getCenter(bloquear).dx,
        greaterThan(tester.getCenter(marcar).dx));
    expect((tester.getCenter(bloquear).dy - tester.getCenter(marcar).dy).abs(),
        lessThan(8));
  });

  testWidgets('alterna entre LISTA (padrão) e GRADE, no dia e na semana',
      (tester) async {
    await pumpPage(tester);
    final lista = find.byTooltip('Lista');
    final grade = find.byTooltip('Grade');
    expect(lista, findsOneWidget);
    expect(grade, findsOneWidget);

    // padrão: lista
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Ana'), findsOneWidget);

    // botões à direita do cadeado, na mesma linha
    expect(tester.getCenter(lista).dx,
        greaterThan(tester.getCenter(find.byTooltip('Bloquear horário')).dx));
    expect(tester.getCenter(grade).dx, greaterThan(tester.getCenter(lista).dx));

    await tester.tap(grade);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    // ações do agendamento continuam disponíveis na grade
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    // grade se mantém ao trocar pra semana
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);

    await tester.tap(lista);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('SEMANA: seta no cabeçalho do dia recolhe e mostra agendamentos',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    // aberto por padrão: seta pra cima (recolher)
    expect(find.text('Ana'), findsOneWidget);
    expect(find.byTooltip('Recolher'), findsOneWidget);

    await tester.tap(find.byTooltip('Recolher'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsNothing);
    expect(find.byTooltip('Mostrar'), findsOneWidget);

    await tester.tap(find.byTooltip('Mostrar'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);

    // também funciona na grade
    await tester.tap(find.byTooltip('Grade'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recolher'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('SEMANA: rodapé mostra os 7 dias da semana', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final domingo = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7));
    final rodape = find.byKey(const Key('week-strip'));
    expect(rodape, findsOneWidget);
    for (var i = 0; i < 7; i++) {
      final d = domingo.add(Duration(days: i));
      final label = d.day == now.day && d.month == now.month
          ? DateFormat('dd/MM').format(d)
          : '${d.day}';
      expect(find.descendant(of: rodape, matching: find.text(label)),
          findsOneWidget,
          reason: 'dia $label no rodapé');
    }
  });

  testWidgets(
      'SEMANA: tocar num dia do rodapé recolhe todos e abre só o dia tocado',
      (tester) async {
    final now = DateTime.now();
    final domingo = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7));
    final segunda = domingo.add(const Duration(days: 1));
    Map<String, dynamic> appt(String id, String nome, DateTime inicio) => {
          'id': id,
          'client_name': nome,
          'client_phone': '+5514999990001',
          'service_name': 'Corte',
          'starts_at': inicio.toIso8601String(),
          'ends_at': inicio.add(const Duration(minutes: 30)).toIso8601String(),
          'status': 'confirmed',
          'source': 'app',
        };
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                appt('d0', 'Bruno', domingo.add(const Duration(hours: 9))),
                appt('d1', 'Carla', segunda.add(const Duration(hours: 9))),
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Carla'), findsOneWidget);

    Finder diaRodape(DateTime d) =>
        find.byKey(Key('week-strip-${DateFormat('yyyy-MM-dd').format(d)}'));

    await tester.tap(diaRodape(segunda));
    await tester.pumpAndSettle();
    // continua na semana, só a segunda aberta e destacada no rodapé
    expect(find.byKey(const Key('week-strip')), findsOneWidget);
    expect(find.text('Carla'), findsOneWidget);
    expect(find.text('Bruno'), findsNothing);
    expect(
        find.descendant(
            of: diaRodape(segunda),
            matching: find.text(DateFormat('dd/MM').format(segunda))),
        findsOneWidget);

    await tester.tap(diaRodape(domingo));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Carla'), findsNothing);
  });

  testWidgets('SEMANA: setas do rodapé vão para a semana seguinte/anterior',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    final atual =
        DateTime.parse(capturedQueries.last!['from'] as String).toLocal();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final prox =
        DateTime.parse(capturedQueries.last!['from'] as String).toLocal();
    expect(prox, DateTime(atual.year, atual.month, atual.day + 7));
    expect(prox.weekday, DateTime.sunday);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final ant =
        DateTime.parse(capturedQueries.last!['from'] as String).toLocal();
    expect(ant, DateTime(atual.year, atual.month, atual.day - 7));
  });

  testWidgets('SEMANA: botão recolhe todos / expande todos os dias',
      (tester) async {
    await pumpPage(tester);
    // só existe na semana
    expect(find.byTooltip('Recolher todos'), findsNothing);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    final recolher = find.byTooltip('Recolher todos');
    expect(recolher, findsOneWidget);
    // à esquerda do alternador lista/grade
    expect(tester.getCenter(recolher).dx,
        lessThan(tester.getCenter(find.byTooltip('Lista')).dx));

    await tester.tap(recolher);
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsNothing);
    expect(find.byTooltip('Mostrar'), findsOneWidget);

    await tester.tap(find.byTooltip('Expandir todos'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.byTooltip('Recolher todos'), findsOneWidget);
  });

  testWidgets(
      'SEMANA: semáforo por dia (confirmado/cancelado/remarcado) e cor do horário',
      (tester) async {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    Map<String, dynamic> appt(String id, int hora, String status,
            [String? motivo]) =>
        {
          'id': id,
          'client_name': 'Cliente $id',
          'client_phone': '+5514999990001',
          'service_name': 'Corte',
          'starts_at': hoje.add(Duration(hours: hora)).toIso8601String(),
          'ends_at':
              hoje.add(Duration(hours: hora, minutes: 30)).toIso8601String(),
          'status': status,
          'source': 'app',
          'canceled_reason': motivo,
        };
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                appt('c1', 8, 'confirmed'),
                appt('c2', 9, 'confirmed'),
                appt('c3', 10, 'confirmed'),
                appt('x1', 11, 'canceled'),
                appt('r1', 12, 'canceled', 'remarcado'),
                appt('r2', 13, 'canceled', 'remarcado'),
                appt('d1', 14, 'done'),
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await pumpPage(tester);

    // DIA também mostra o semáforo, ao lado dos botões de layout
    String contagemDia(String tipo) => (tester
        .widget<Text>(find.descendant(
            of: find.descendant(
                of: find.byKey(const Key('day-semaphore')),
                matching: find.byKey(Key('semaforo-$tipo'))),
            matching: find.byType(Text)))
        .data)!;
    expect(contagemDia('confirmado'), '3');
    expect(contagemDia('cancelado'), '1');
    expect(contagemDia('remarcado'), '2');
    expect(contagemDia('concluido'), '1');
    // linha própria abaixo dos botões, alinhada à direita
    final semaforo = find.byKey(const Key('day-semaphore'));
    expect(
        tester.getTopLeft(semaforo).dy,
        greaterThan(
            tester.getBottomLeft(find.byTooltip('Bloquear horário')).dy));
    expect(tester.getCenter(find.byKey(const Key('semaforo-remarcado'))).dx,
        greaterThan(tester.getCenter(find.byTooltip('Grade')).dx));

    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day-semaphore')), findsNothing);

    String contagem(String tipo) => (tester
        .widget<Text>(find.descendant(
            of: find.byKey(Key('semaforo-$tipo')), matching: find.byType(Text)))
        .data)!;
    expect(contagem('confirmado'), '3');
    expect(contagem('cancelado'), '1');
    expect(contagem('remarcado'), '2');
    expect(contagem('concluido'), '1');

    // ordem: verde, vermelho, roxo
    final xC =
        tester.getCenter(find.byKey(const Key('semaforo-confirmado'))).dx;
    final xX = tester.getCenter(find.byKey(const Key('semaforo-cancelado'))).dx;
    final xR = tester.getCenter(find.byKey(const Key('semaforo-remarcado'))).dx;
    expect(xC < xX && xX < xR, isTrue);
    // concluído (azul) vem antes do verde
    final xD = tester.getCenter(find.byKey(const Key('semaforo-concluido'))).dx;
    expect(xD, lessThan(xC));

    // remarcado aparece como "Cancelado/Remarcado"
    expect(find.text('Corte • Cancelado/Remarcado'), findsNWidgets(2));

    Color fundoHorario(String id) =>
        ((tester.widget<Container>(find.byKey(Key('hora-$id'))).decoration
                as BoxDecoration)
            .color)!;
    expect(fundoHorario('c1').withValues(alpha: 1),
        const Color(0xFF2E7D32)); // verde
    expect(fundoHorario('x1').withValues(alpha: 1),
        const Color(0xFFC62828)); // vermelho
    expect(fundoHorario('r1').withValues(alpha: 1),
        const Color(0xFF7B1FA2)); // roxo
    expect(fundoHorario('d1').withValues(alpha: 1),
        const Color(0xFF1E96E8)); // azul

    // concluído ganha check azul junto do texto
    final check = find.byKey(const Key('check-concluido-d1'));
    expect(check, findsOneWidget);
    expect(tester.widget<Icon>(check).color, const Color(0xFF1E96E8));
  });

  testWidgets('SEMANA: controles acessíveis em celular de 360 pixels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final tooltip in [
      'Bloquear horário',
      'Recolher todos',
      'Lista',
      'Grade'
    ]) {
      final control = find.byTooltip(tooltip);
      expect(control.hitTestable(), findsOneWidget);
      expect(tester.getRect(control).right, lessThanOrEqualTo(360));
    }
    await tester.tap(find.byTooltip('Grade'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('SEMANA: novo agendamento reabre o dia recolhido',
      (tester) async {
    final start = DateTime.now().add(const Duration(hours: 2));
    final novo = booking.Appointment(
        id: 'criado',
        startsAt: start,
        endsAt: start.add(const Duration(minutes: 30)),
        status: 'confirmed');
    await tester.pumpWidget(_wrap(api, rescheduleResult: novo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recolher todos'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsNothing);

    await tester.tap(find.text('Marcar horário'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SALVAR REMARCAÇÃO'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.byTooltip('Recolher'), findsOneWidget);
  });

  testWidgets('Marcar horário: ao voltar recarrega a lista', (tester) async {
    await tester.pumpWidget(_wrap(api)); // stub do wizard volta sem resultado
    await tester.pumpAndSettle();
    final antes = capturedQueries.length;

    await tester.tap(find.text('Marcar horário'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SALVAR REMARCAÇÃO'));
    await tester.pumpAndSettle();

    expect(capturedQueries.length, greaterThan(antes));
  });

  testWidgets('Marcar horário: vai para o dia do agendamento criado',
      (tester) async {
    final novo = booking.Appointment(
        id: 'criado',
        startsAt: DateTime(2031, 1, 5, 14, 30),
        endsAt: DateTime(2031, 1, 5, 15, 30),
        status: 'confirmed');
    await tester.pumpWidget(_wrap(api, rescheduleResult: novo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcar horário'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SALVAR REMARCAÇÃO'));
    await tester.pumpAndSettle();

    final q = capturedQueries.last!;
    expect(DateTime.parse(q['from'] as String).toLocal(), DateTime(2031, 1, 5));
  });

  testWidgets(
      'menu ⋮: Remarcar/Cancelar em todos; Concluir só até hoje e se não concluído',
      (tester) async {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    Map<String, dynamic> appt(String nome, DateTime inicio, String status) => {
          'id': nome,
          'client_name': nome,
          'client_phone': '+5514999990001',
          'service_name': 'Corte',
          'starts_at': inicio.toIso8601String(),
          'ends_at': inicio.add(const Duration(minutes: 30)).toIso8601String(),
          'status': status,
          'source': 'app',
        };
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                appt('Ontem', hoje.subtract(const Duration(hours: 10)),
                    'confirmed'),
                appt('Amanha', hoje.add(const Duration(days: 1, hours: 10)),
                    'confirmed'),
                appt('Feito', hoje.subtract(const Duration(hours: 9)), 'done'),
                appt('Cancel', hoje.subtract(const Duration(hours: 8)),
                    'canceled'),
                {
                  ...appt('Remarc', hoje.subtract(const Duration(hours: 7)),
                      'canceled'),
                  'canceled_reason': 'remarcado',
                },
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await pumpPage(tester);

    Future<List<String>> opcoes(String nome) async {
      final card =
          find.ancestor(of: find.text(nome), matching: find.byType(Card));
      await tester.tap(find.descendant(
          of: card, matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      final itens = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((i) => (i.child as Text).data!)
          .toList();
      await tester.tapAt(const Offset(5, 5)); // fecha o menu
      await tester.pumpAndSettle();
      return itens;
    }

    // passado: tudo disponível
    expect(await opcoes('Ontem'), ['Remarcar', 'Concluir', 'Cancelar']);
    // dia futuro: sem Concluir
    expect(await opcoes('Amanha'), ['Remarcar', 'Cancelar']);
    // já concluído: sem Concluir de novo
    expect(await opcoes('Feito'), ['Remarcar', 'Cancelar']);
    // já cancelado: sem Cancelar nem Concluir
    expect(await opcoes('Cancel'), ['Remarcar']);

    // já remarcado: vira histórico, sem menu (o novo agendamento já existe)
    expect(
        find.descendant(
            of: find.ancestor(
                of: find.text('Remarc'), matching: find.byType(Card)),
            matching: find.byType(PopupMenuButton<String>)),
        findsNothing);
  });

  testWidgets('erro da API ao cancelar mostra a mensagem humana, não a exceção',
      (tester) async {
    adapter.onPatch(
        RegExp(r'/appointments/.*'),
        (s) => s.reply(400, {
              'error':
                  'Este horário já passou — não é possível alterar o agendamento'
            }),
        data: Matchers.any);
    await pumpPage(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(
        find.text('Não consegui cancelar: Este horário já passou — '
            'não é possível alterar o agendamento'),
        findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets(
      'card mostra as observações (lista) e o botão de detalhes (grade)',
      (tester) async {
    final inicio = DateTime.now().add(const Duration(hours: 1));
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                {
                  'id': 'n1',
                  'client_name': 'Ana',
                  'client_phone': '+5514999990001',
                  'service_name': 'Corte',
                  'starts_at': inicio.toIso8601String(),
                  'ends_at':
                      inicio.add(const Duration(minutes: 30)).toIso8601String(),
                  'status': 'confirmed',
                  'source': 'app',
                  'notes': 'alergia a pomada',
                },
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await pumpPage(tester);
    expect(find.text('alergia a pomada'), findsOneWidget);

    await tester.tap(find.byTooltip('Grade'));
    await tester.pumpAndSettle();
    // na grade o acesso é pelo botão de detalhes
    expect(find.byTooltip('Detalhes e observações'), findsOneWidget);
  });

  testWidgets('botão Detalhes abre o painel com a observação e permite editar',
      (tester) async {
    final inicio = DateTime.now().add(const Duration(hours: 1));
    Map<String, dynamic> appt(String? notes) => {
          'id': 'd1',
          'client_name': 'Ana',
          'client_phone': '+5514999990001',
          'service_name': 'Corte',
          'starts_at': inicio.toIso8601String(),
          'ends_at': inicio.add(const Duration(minutes: 30)).toIso8601String(),
          'status': 'confirmed',
          'source': 'app',
          'notes': notes,
        };
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [appt('alergia a pomada')]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    // PATCH só responde se o body tiver a observação nova (aparada)
    adapter.onPatch('/appointments/d1',
        (s) => s.reply(200, {'appointment': appt('usar máquina 2')}),
        data: {'notes': 'usar máquina 2'});
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Detalhes e observações'));
    await tester.pumpAndSettle();
    final painel = find.byKey(const Key('details-sheet'));
    expect(painel, findsOneWidget);
    expect(find.descendant(of: painel, matching: find.text('Ana')),
        findsOneWidget);
    expect(find.descendant(of: painel, matching: find.text('alergia a pomada')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('details-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('details-notes-field')), ' usar máquina 2 ');
    // depois de salvar, a agenda recarrega com a observação nova
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [appt('usar máquina 2')]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    await tester.tap(find.byKey(const Key('details-save')));
    await tester.pumpAndSettle();

    expect(find.text('Observação salva'), findsOneWidget);
    expect(painel, findsNothing);
    expect(find.text('usar máquina 2'), findsOneWidget);
  });

  testWidgets('Detalhes: informações do CLIENTE só aparecem ao tocar no botão',
      (tester) async {
    final inicio = DateTime.now().add(const Duration(hours: 1));
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                {
                  'id': 'd1',
                  'client_id': 'cli-1',
                  'client_name': 'Ana',
                  'client_phone': '+5514999990001',
                  'service_name': 'Corte',
                  'starts_at': inicio.toIso8601String(),
                  'ends_at':
                      inicio.add(const Duration(minutes: 30)).toIso8601String(),
                  'status': 'confirmed',
                  'source': 'app',
                },
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});
    adapter.onGet(
        '/clients/cli-1',
        (s) => s.reply(200, {
              'id': 'cli-1',
              'name': 'Ana',
              'phone_e164': '+5514999990001',
              'notes': 'alérgica a tinta',
            }));
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Detalhes e observações'));
    await tester.pumpAndSettle();
    // escondido por padrão
    expect(find.text('alérgica a tinta'), findsNothing);

    await tester.tap(find.byKey(const Key('details-client-info')));
    await tester.pumpAndSettle();
    expect(find.text('alérgica a tinta'), findsOneWidget);
  });

  testWidgets('Detalhes sem observação mostra "Sem observações"',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Detalhes e observações'));
    await tester.pumpAndSettle();
    expect(find.text('Sem observações'), findsOneWidget);
  });

  testWidgets('GRADE em celular de 360dp: cartões sem estourar a largura',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Grade'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Detalhes e observações'), findsOneWidget);
  });

  testWidgets('DIA: tocar na data do rodapé abre popup com os dias do mês',
      (tester) async {
    await pumpPage(tester);
    final now = DateTime.now();
    // rodapé do Dia: "Sexta-feira, 30/10" (nome do dia + data)
    final hoje = DateFormat("EEEE, dd/MM", 'pt_BR').format(now);
    expect(find.text('${hoje[0].toUpperCase()}${hoje.substring(1)}'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('day-footer-label')));
    await tester.pumpAndSettle();
    final popup = find.byKey(const Key('day-picker'));
    expect(popup, findsOneWidget);

    // todos os dias do mês, do 1 ao último
    final ultimo = DateTime(now.year, now.month + 1, 0).day;
    expect(
        find.descendant(of: popup, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.text('$ultimo')),
        findsOneWidget);

    final alvo = now.day == 15 ? 16 : 15;
    await tester.tap(find.descendant(of: popup, matching: find.text('$alvo')));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    final q = capturedQueries.last!;
    expect(DateTime.parse(q['from'] as String).toLocal(),
        DateTime(now.year, now.month, alvo));
    expect(find.text('Dia'), findsOneWidget);
  });

  testWidgets('SEMANA lista os dias do mais recente para o mais antigo',
      (tester) async {
    final now = DateTime.now();
    final domingo = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7));
    Map<String, dynamic> appt(String id, String nome, DateTime inicio) => {
          'id': id,
          'client_name': nome,
          'client_phone': '+5514999990001',
          'service_name': 'Corte',
          'starts_at': inicio.toIso8601String(),
          'ends_at': inicio.add(const Duration(minutes: 30)).toIso8601String(),
          'status': 'confirmed',
          'source': 'app',
        };
    adapter.onGet(
        '/appointments',
        (s) => s.reply(200, {
              'appointments': [
                appt('d0', 'Bruno', domingo.add(const Duration(hours: 9))),
                appt('d1', 'Carla',
                    domingo.add(const Duration(days: 1, hours: 9))),
              ]
            }),
        queryParameters: {'from': Matchers.any, 'to': Matchers.any});

    await pumpPage(tester);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    final yCarla = tester.getTopLeft(find.text('Carla')).dy;
    final yBruno = tester.getTopLeft(find.text('Bruno')).dy;
    expect(yCarla, lessThan(yBruno),
        reason: 'segunda (mais recente) vem antes do domingo');
  });

  testWidgets('MÊS mostra o calendário na própria tela com os agendamentos',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    // carrega o mês inteiro: do dia 1 ao dia 1 do mês seguinte
    final q = capturedQueries.last!;
    final from = DateTime.parse(q['from'] as String).toLocal();
    final to = DateTime.parse(q['to'] as String).toLocal();
    expect(from.day, 1);
    expect(to.day, 1);
    expect(to.month, from.month == 12 ? 1 : from.month + 1);

    // grade do mês na tela (sem bottom sheet), cabeçalho DOM..SÁB
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('DOM.'), findsOneWidget);
    expect(find.text('SÁB.'), findsOneWidget);
    // agendamento aparece dentro do dia
    expect(find.text('Ana'), findsOneWidget);
    // lista/grade não se aplicam ao mês
    expect(find.byTooltip('Grade'), findsNothing);
    expect(find.text('Marcar horário'), findsOneWidget);
  });

  testWidgets('MÊS: setas navegam de mês em mês', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();
    final atual =
        DateTime.parse(capturedQueries.last!['from'] as String).toLocal();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final prox =
        DateTime.parse(capturedQueries.last!['from'] as String).toLocal();
    expect(prox, DateTime(atual.year, atual.month + 1, 1));
    expect(find.text('DOM.'), findsOneWidget);
  });

  testWidgets('MÊS: tocar num dia abre a visão dia daquela data',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(find.text('DOM.'), findsNothing);
    final q = capturedQueries.last!;
    final from = DateTime.parse(q['from'] as String).toLocal();
    expect(from.day, 15);
    expect(
        DateTime.parse(q['to'] as String).toLocal().difference(from).inDays, 1);
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

  testWidgets('mês vazio mostra "Nada agendado neste mês"', (tester) async {
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

  testWidgets('mês COM eventos não mostra texto de vazio', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mês'));
    await tester.pumpAndSettle();

    expect(find.text('Nada agendado neste mês'), findsNothing);
  });
}
