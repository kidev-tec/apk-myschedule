// Clientes: arquivar com aviso dos agendamentos futuros (e opção de cancelar
// junto), filtro Ativos/Arquivados, reativar, e celular repetido no
// formulário (abrir/reativar o cadastro existente em vez de duplicar).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/clients/client_form_page.dart';
import 'package:minha_agenda/features/clients/clients_page.dart';

class _Backend implements HttpClientAdapter {
  final clients = <Map<String, dynamic>>[
    {'id': 'c1', 'name': 'Ana', 'phone_e164': '5511987650001'},
    {'id': 'c2', 'name': 'Bia', 'phone_e164': '5511987650002'},
    {
      'id': 'c3',
      'name': 'Caio',
      'phone_e164': '5511987650003',
      'archived': true
    },
  ];
  final calls = <String>[];
  Map<String, dynamic>? duplicateOnPost;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    ResponseBody json(int status, Object data) =>
        ResponseBody.fromString(jsonEncode(data), status, headers: {
          'content-type': ['application/json'],
        });
    final q = o.queryParameters.isEmpty
        ? ''
        : '?${o.queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    calls.add('${o.method} ${o.path}$q');
    final parts = o.path.split('/');
    if (o.path.endsWith('/upcoming')) {
      final id = parts[parts.length - 2];
      return json(200, {
        'upcoming': id == 'c1'
            ? [
                {
                  'id': 'a1',
                  'starts_at':
                      DateTime(2030, 1, 7, 9).toUtc().toIso8601String(),
                  'service_name': 'Corte'
                },
                {
                  'id': 'a2',
                  'starts_at':
                      DateTime(2030, 1, 14, 14).toUtc().toIso8601String(),
                  'service_name': 'Barba'
                },
              ]
            : []
      });
    }
    if (o.path.endsWith('/restore')) {
      final id = parts[parts.length - 2];
      final c = clients.firstWhere((x) => x['id'] == id)..['archived'] = false;
      return json(200, c);
    }
    if (o.method == 'DELETE') {
      final c = clients.firstWhere((x) => x['id'] == parts.last)
        ..['archived'] = true;
      return json(200, {
        ...c,
        'canceled_appointments':
            o.queryParameters['cancel_future'] == '1' ? 2 : 0
      });
    }
    if (o.method == 'POST' && o.path.endsWith('/clients')) {
      if (duplicateOnPost != null) return json(409, duplicateOnPost!);
      return json(201, {'id': 'new', 'name': 'X', 'phone_e164': '1'});
    }
    if (o.path.endsWith('/clients')) {
      final archived = o.queryParameters['archived'] == '1';
      return json(200, [
        for (final c in clients)
          if ((c['archived'] == true) == archived) c
      ]);
    }
    // GET /clients/:id
    return json(200, clients.firstWhere((x) => x['id'] == parts.last));
  }
}

Widget _app(ApiClient api, {String initial = '/clients'}) {
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
      path: '/clients',
      builder: (_, __) => ClientsPage(api: api),
      routes: [
        GoRoute(path: 'new', builder: (_, __) => ClientFormPage(api: api)),
        GoRoute(
            path: ':id/edit',
            builder: (_, s) =>
                ClientFormPage(clientId: s.pathParameters['id'], api: api)),
      ],
    ),
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
  setUpAll(() => initializeDateFormatting('pt_BR', null));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> openMenu(WidgetTester tester, String name) async {
    await tester.tap(find.descendant(
        of: find.widgetWithText(Card, name),
        matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
  }

  testWidgets('arquivar avisa os futuros e pode cancelar junto',
      (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    expect(find.text('Caio'), findsNothing); // arquivado fora dos ativos

    await openMenu(tester, 'Ana');
    expect(find.text('Excluir'), findsNothing);
    await tester.tap(find.text('Arquivar'));
    await tester.pumpAndSettle();

    expect(find.text('Arquivar Ana?'), findsOneWidget);
    expect(find.text('Ana tem 2 agendamentos futuros:'), findsOneWidget);
    expect(find.text('• 07/01 às 09:00 — Corte'), findsOneWidget);
    expect(find.textContaining('O histórico de atendimentos fica guardado'),
        findsOneWidget);
    expect(find.text('Eles continuam na agenda normalmente.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive-cancel-future')));
    await tester.pump();
    expect(find.text('Os horários ficam livres na agenda.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive-confirm')));
    await tester.pumpAndSettle();

    expect(b.calls, contains('DELETE /clients/c1?cancel_future=1'));
    expect(find.textContaining('2 agendamentos cancelados'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('sem futuros: aviso só do histórico; arquiva sem cancelar',
      (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    await openMenu(tester, 'Bia');
    await tester.tap(find.text('Arquivar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archive-upcoming-count')), findsNothing);
    expect(find.byKey(const Key('archive-cancel-future')), findsNothing);
    await tester.tap(find.byKey(const Key('archive-confirm')));
    await tester.pumpAndSettle();
    expect(b.calls, contains('DELETE /clients/c2'));
  });

  testWidgets('filtro Arquivados lista e reativa', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arquivados'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('GET /clients?archived=1'));
    expect(find.text('Caio'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);

    await tester.tap(find.byKey(const Key('restore-c3')));
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST /clients/c3/restore'));
    expect(find.text('Caio foi reativado(a).'), findsOneWidget);
    expect(find.text('Nenhum cliente arquivado'), findsOneWidget);

    await tester.tap(find.text('Ativos'));
    await tester.pumpAndSettle();
    expect(find.text('Caio'), findsOneWidget);
  });

  testWidgets('novo cliente com celular de arquivado → reativar e abrir',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = _Backend()
      ..duplicateOnPost = {
        'error': 'Esse celular já é de Caio (cliente arquivado)',
        'archived': true,
        'existing': {'id': 'c3', 'name': 'Caio', 'phone_e164': '5511987650003'},
      };
    await tester
        .pumpWidget(_app(ApiClient(adapter: b), initial: '/clients/new'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Caio Novo');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '11987650003');
    await tester.ensureVisible(find.text('Criar cliente'));
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();

    expect(find.text('Celular já cadastrado'), findsOneWidget);
    expect(find.textContaining('Esse celular já é de Caio (cliente arquivado)'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-open-existing')));
    await tester.pumpAndSettle();

    expect(b.calls, contains('POST /clients/c3/restore'));
    expect(find.text('Editar cliente'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Caio'), findsOneWidget);
  });

  testWidgets('celular de cliente ativo → "Corrigir número" fica no form',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = _Backend()
      ..duplicateOnPost = {
        'error': 'Esse celular já é de Ana',
        'archived': false,
        'existing': {'id': 'c1', 'name': 'Ana', 'phone_e164': '5511987650001'},
      };
    await tester
        .pumpWidget(_app(ApiClient(adapter: b), initial: '/clients/new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'X');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '11987650001');
    await tester.ensureVisible(find.text('Criar cliente'));
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir Ana'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-fix-phone')));
    await tester.pumpAndSettle();
    expect(find.text('Novo cliente'), findsOneWidget);
    expect(b.calls.where((c) => c.contains('restore')), isEmpty);
  });
}
