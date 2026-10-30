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
import 'package:minha_agenda/features/agenda/booking_logic.dart' as logic;
import 'package:minha_agenda/features/agenda/booking_wizard.dart';

/// B3 (SPEC f43dd5b):
/// CA1 — generateSlots: excludeId libera o slot do próprio agendamento.
/// CA2 — wizard remarcar: abre no passo do horário com cliente/serviço
///       pré-selecionados (título "Remarcar", sem voltar pra cliente).
/// CA3 — salvar faz PATCH e devolve a nova linha para a agenda.
/// CA4 — Appointment.fromJson parseia clientId/serviceId.

/// Observações e resumo ficam no último passo ("Confirma o agendamento"):
/// avança pra ele a partir da escolha do horário.
Future<void> goToReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wizard-save')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await initializeDateFormatting('pt_BR', null));

  final day = DateTime(2026, 10, 28); // quarta
  WorkingHour wh(String s, String e) => WorkingHour(
      weekday: 3,
      startTime: TimeOfDay(
          hour: int.parse(s.split(':')[0]), minute: int.parse(s.split(':')[1])),
      endTime: TimeOfDay(
          hour: int.parse(e.split(':')[0]),
          minute: int.parse(e.split(':')[1])));

  group('CA1 generateSlots excludeId', () {
    final appts = [
      Appointment(
          id: 'appt-1',
          startsAt: DateTime(2026, 10, 28, 10),
          endsAt: DateTime(2026, 10, 28, 11),
          status: 'pending'),
    ];
    test('sem excludeId, slot 10:00 bloqueado pelo agendamento', () {
      final slots = logic.generateSlots(
          date: day,
          workingHours: [wh('09:00', '12:00')],
          appointments: appts,
          durationMin: 60);
      expect(slots.contains(DateTime(2026, 10, 28, 10)), isFalse);
    });
    test('com excludeId do próprio, 10:00 liberado', () {
      final slots = logic.generateSlots(
          date: day,
          workingHours: [wh('09:00', '12:00')],
          appointments: appts,
          durationMin: 60,
          excludeId: 'appt-1');
      expect(slots.contains(DateTime(2026, 10, 28, 10)), isTrue);
    });
  });

  test('Appointment.fromJson lê notes', () {
    final a = Appointment.fromJson({
      'id': 'a1',
      'starts_at': '2026-10-28T10:00:00.000',
      'ends_at': '2026-10-28T11:00:00.000',
      'status': 'confirmed',
      'notes': 'obs',
    });
    expect(a.notes, 'obs');
  });

  test('CA4 Appointment.fromJson parseia clientId/serviceId (snake/camel)', () {
    final a = Appointment.fromJson({
      'id': 'a1',
      'starts_at': '2026-10-28T10:00:00.000',
      'ends_at': '2026-10-28T11:00:00.000',
      'status': 'pending',
      'client_id': 'c1',
      'service_id': 's1',
    });
    expect(a.clientId, 'c1');
    expect(a.serviceId, 's1');
    final b = Appointment.fromJson({
      'id': 'a2',
      'starts_at': '2026-10-28T10:00:00.000',
      'ends_at': '2026-10-28T11:00:00.000',
      'status': 'pending',
      'clientId': 'c9',
      'serviceId': 's9',
    });
    expect(b.clientId, 'c9');
    expect(b.serviceId, 's9');
  });

  group('CA2/CA3 wizard reschedule (integração)', () {
    // Relógio fixo: 28/10/2026 08:00 — os horários de 10:00 em diante do
    // dia ainda não passaram, qualquer que seja a hora real do teste.
    DateTime relogio() => DateTime(2026, 10, 28, 8);

    Widget wrapWithApi(ApiClient api, Appointment target,
        {void Function(Appointment?)? onResult}) {
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
                body: Builder(
                    builder: (ctx) => FilledButton(
                        key: const Key('open-wizard'),
                        onPressed: () async {
                          final result = await ctx.push<Appointment>('/booking',
                              extra: {'reschedule': target});
                          onResult?.call(result);
                        },
                        child: const Text('ABRIR'))))),
        GoRoute(
            path: '/booking',
            builder: (ctx, state) => BookingWizardPage(
                  reschedule: (state.extra
                      as Map<String, dynamic>?)?['reschedule'] as Appointment?,
                  clock: relogio,
                )),
      ]);
      return ProviderScope(
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

    // Mesma receita do booking_wizard_integration_test: DioAdapter com os
    // 4 GETs + PATCH; interceptor captura METHOD+path no dio DO ApiClient.
    (ApiClient, List<MapEntry<String, String>>) fakeApi() {
      final calls = <MapEntry<String, String>>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
          '/clients',
          (s) => s.reply(200, [
                {'id': 'c1', 'name': 'Maria', 'phone_e164': '+551****0001'},
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
      // folga padrão do negócio (intervalo entre atendimentos)
      adapter.onGet('/me', (s) => s.reply(200, {'buffer_min': 0}));
      adapter.onGet(
          '/working-hours',
          (s) => s.reply(200, [
                {'weekday': 3, 'start_time': '09:00', 'end_time': '12:00'},
              ]));
      adapter.onGet(
          '/appointments',
          (s) => s.reply(200, {
                'appointments': [
                  {
                    'id': 'appt-9',
                    'starts_at': '2026-10-28T10:00:00.000',
                    'ends_at': '2026-10-28T11:00:00.000',
                    'status': 'pending',
                    'client_id': 'c1',
                    'service_id': 's1',
                  },
                ],
              }));
      adapter.onPatch(
          '/appointments/appt-9',
          (s) => s.reply(200, {
                'appointment': {
                  'id': 'appt-new',
                  'starts_at': '2026-10-28T11:00:00.000',
                  'ends_at': '2026-10-28T12:00:00.000',
                  'status': 'pending',
                  'client_id': 'c1',
                  'service_id': 's1',
                },
                'rescheduled': true,
              }),
          data: Matchers.any);
      adapter.onPost('/appointments', (s) => s.reply(201, {'id': 'X'}),
          data: Matchers.any);

      final api = ApiClient(adapter: adapter);
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(MapEntry(options.method, options.uri.path));
          handler.next(options);
        },
      ));
      return (api, calls);
    }

    final target = Appointment(
        id: 'appt-9',
        startsAt: DateTime(2026, 10, 28, 10),
        endsAt: DateTime(2026, 10, 28, 11),
        status: 'pending',
        clientId: 'c1',
        serviceId: 's1');

    Future<void> pumpOpen(WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (api, _) = fakeApi();
      await tester.pumpWidget(wrapWithApi(api, target));
      await tester.tap(find.byKey(const Key('open-wizard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'CA2 abre no passo do horário com pré-seleção e título Remarcar',
        (tester) async {
      await pumpOpen(tester);
      // título trocou; não mostra a lista de clientes (passo 1)
      expect(find.text('Remarcar'), findsOneWidget);
      expect(find.text('Escolhe o cliente'), findsNothing);
      // grade de slots visível com o horário atual pré-selecionável
      expect(find.text('10:00'), findsWidgets);
    });

    testWidgets(
        'remarcar agendamento atrasado abre em HOJE, sem horários passados',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (api, _) = fakeApi();
      final atrasado = Appointment(
          id: 'appt-old',
          startsAt: DateTime(2026, 10, 27, 10),
          endsAt: DateTime(2026, 10, 27, 11),
          status: 'confirmed',
          clientId: 'c1',
          serviceId: 's1');
      await tester.pumpWidget(wrapWithApi(api, atrasado));
      await tester.tap(find.byKey(const Key('open-wizard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // abre no dia de hoje (28/10), não no dia do agendamento (27/10)
      expect(find.textContaining('28 de outubro'), findsOneWidget);
      expect(find.textContaining('27 de outubro'), findsNothing);
      // não volta pra dias passados
      final voltar = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_left));
      expect(voltar.onPressed, isNull);
    });

    testWidgets('remarcar traz as observações já preenchidas', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (api, _) = fakeApi();
      final comObs = Appointment(
          id: 'appt-9',
          startsAt: DateTime(2026, 10, 28, 10),
          endsAt: DateTime(2026, 10, 28, 11),
          status: 'confirmed',
          clientId: 'c1',
          serviceId: 's1',
          notes: 'prefere máquina 2');
      await tester.pumpWidget(wrapWithApi(api, comObs));
      await tester.tap(find.byKey(const Key('open-wizard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // horário atual pré-selecionado → campo visível e preenchido
      await goToReview(tester);
      final campo =
          tester.widget<TextField>(find.byKey(const Key('wizard-notes')));
      expect(campo.controller?.text, 'prefere máquina 2');
    });

    testWidgets('CA3 salvar faz PATCH (nunca POST) e volta pra tela anterior',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (api, calls) = fakeApi();
      Appointment? returned;
      await tester.pumpWidget(
          wrapWithApi(api, target, onResult: (value) => returned = value));
      await tester.tap(find.byKey(const Key('open-wizard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // horário atual já pré-selecionado; salva direto
      await tester.ensureVisible(find.text('10:00').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10:00').first);
      await tester.pumpAndSettle();
      await goToReview(tester);
      await tester.tap(find.byKey(const Key('wizard-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(
          calls.any(
              (c) => c.key == 'PATCH' && c.value == '/v1/appointments/appt-9'),
          isTrue,
          reason: 'remarcar deve PATCH no próprio id');
      expect(calls.any((c) => c.key == 'POST'), isFalse,
          reason: 'remarcar deve PATCH, nunca POST');
      expect(returned?.id, 'appt-new');
      expect(returned?.startsAt, DateTime(2026, 10, 28, 11));
      expect(logic.buildRescheduleMessage('Maria', returned),
          contains('28/10 às 11:00'));
      // Retorna o novo agendamento e fecha o wizard.
      expect(find.byType(BookingWizardPage), findsNothing);
      expect(find.text('ABRIR'), findsOneWidget);
    });

    testWidgets(
        'serviço excluído: remarca com os dados do agendamento e mantém a folga',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (api, calls) = fakeApi();
      // 's-old' não vem em GET /services (arquivado)
      final antigo = Appointment(
          id: 'appt-9',
          startsAt: DateTime(2026, 10, 28, 10),
          endsAt: DateTime(2026, 10, 28, 11, 10),
          status: 'pending',
          clientId: 'c1',
          serviceId: 's-old',
          serviceName: 'Depilação',
          servicePriceCents: 15000,
          bufferMin: 10);
      await tester.pumpWidget(wrapWithApi(api, antigo));
      await tester.tap(find.byKey(const Key('open-wizard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // duração e folga originais preservadas
      expect(find.text('70 min'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      await tester.ensureVisible(find.text('10:00').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10:00').first);
      await tester.pumpAndSettle();
      await goToReview(tester);

      // (NumberFormat usa espaço não-quebrável depois do R\$)
      expect(find.textContaining(RegExp(r'^Depilação · R\$.150,00$')),
          findsOneWidget);
      expect(find.text('10:00 às 11:10 (70 min)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wizard-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(
          calls.any(
              (c) => c.key == 'PATCH' && c.value == '/v1/appointments/appt-9'),
          isTrue);
    });
  });
}
