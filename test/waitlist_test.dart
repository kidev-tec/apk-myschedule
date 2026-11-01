// Lista de espera: data em português, celular formatado, Avisar abre o
// WhatsApp e marca avisado, Atendido, remover, adicionar (cliente cadastrado
// ou novo), erro/vazio e "Vaga abriu" na central abrindo a lista no dia.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/notifications/notifications_page.dart';
import 'package:minha_agenda/features/settings/waitlist_page.dart';

/// Dia dos testes: sempre no futuro (o botão Adicionar some em dia passado).
final _day = DateTime(2030, 11, 3); // domingo
const _ds = '2030-11-03';

class _Backend implements HttpClientAdapter {
  final entries = <Map<String, dynamic>>[
    {
      'id': 'w1',
      'client_id': 'c1',
      'client_name': 'Ana Souza',
      'phone': '5511987650001',
      'status': 'waiting',
      'created_at': '2030-11-01T10:00:00.000Z',
    },
    {
      'id': 'w2',
      'client_id': 'c2',
      'client_name': 'Bia',
      'phone': '5511987650002',
      'status': 'notified',
      'created_at': '2030-11-01T11:00:00.000Z',
    },
  ];
  final calls = <String>[];
  final bodies = <Object?>[];
  bool fail = false;
  bool duplicate = false;

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
    bodies.add(o.data);
    if (fail) return json(500, {'error': 'Servidor fora do ar'});
    if (o.path.endsWith('/clients')) {
      return json(200, [
        {'id': 'c1', 'name': 'Ana Souza', 'phone_e164': '5511987650001'},
        {'id': 'c9', 'name': 'Caio Lima', 'phone_e164': '5511987650009'},
      ]);
    }
    final id = o.path.split('/').last;
    switch (o.method) {
      case 'GET':
        return json(200, {'waitlist': entries});
      case 'PATCH':
        entries.firstWhere((e) => e['id'] == id)['status'] =
            (o.data as Map)['status'];
        return json(200, {'ok': true});
      case 'DELETE':
        entries.removeWhere((e) => e['id'] == id);
        return json(200, {'ok': true});
      default: // POST /waitlist
        if (duplicate) {
          return json(
              409, {'error': 'Ana Souza já está na lista de espera de 03/11'});
        }
        final b = o.data as Map;
        final name = b['name'] ?? 'Caio Lima';
        entries.add({
          'id': 'w3',
          'client_id': 'c9',
          'client_name': name,
          'phone': '5511987650009',
          'status': 'waiting',
          'created_at': '2030-11-01T12:00:00.000Z',
        });
        return json(201, {'ok': true, 'id': 'w3', 'client_name': name});
    }
  }
}

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
        locale: const Locale('pt', 'BR'),
        home: home,
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('dia em português, celular formatado e status', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(
        _app(WaitlistPage(api: ApiClient(adapter: b), initialDay: _day)));
    await tester.pumpAndSettle();
    expect(b.calls.first, 'GET /waitlist?date=$_ds');
    expect(find.text('Domingo, 03/11'), findsOneWidget);
    expect(find.text('(11) 98765-0001 · aguardando'), findsOneWidget);
    expect(find.text('(11) 98765-0002 · avisado'), findsOneWidget);
    expect(find.textContaining('Eles entram pelo seu link'), findsOneWidget);

    await tester.tap(find.byTooltip('Próximo dia'));
    await tester.pumpAndSettle();
    expect(find.text('Segunda-feira, 04/11'), findsOneWidget);
    expect(b.calls.last, 'GET /waitlist?date=2030-11-04');
  });

  testWidgets('Avisar abre o WhatsApp com a mensagem e marca avisado',
      (tester) async {
    final b = _Backend();
    Uri? opened;
    await tester.pumpWidget(_app(WaitlistPage(
        api: ApiClient(adapter: b),
        initialDay: _day,
        openUrl: (u) async => opened = u)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-notify-w1')));
    await tester.pumpAndSettle();
    expect(opened?.host, 'wa.me');
    expect(opened?.path, '/5511987650001');
    expect(
        opened?.queryParameters['text'],
        'Olá, Ana! Abriu um horário no dia 03/11 (domingo). '
        'Você ainda tem interesse? Me responda por aqui que eu agendo 🙂');
    expect(b.calls, contains('PATCH /waitlist/w1'));
    expect(find.text('(11) 98765-0001 · avisado'), findsOneWidget);

    // avisada → Atendido
    await tester.tap(find.byKey(const Key('waitlist-served-w2')));
    await tester.pumpAndSettle();
    expect(find.text('(11) 98765-0002 · atendido'), findsOneWidget);
  });

  testWidgets('WhatsApp não abre: avisa e não marca', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(WaitlistPage(
        api: ApiClient(adapter: b),
        initialDay: _day,
        openUrl: (_) async => throw Exception('sem app'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-notify-w1')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível abrir o WhatsApp.'), findsOneWidget);
    expect(b.calls.where((c) => c.startsWith('PATCH')), isEmpty);
  });

  testWidgets('menu: voltar para aguardando e remover', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(
        _app(WaitlistPage(api: ApiClient(adapter: b), initialDay: _day)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-menu-w2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar para aguardando'));
    await tester.pumpAndSettle();
    expect(find.text('(11) 98765-0002 · aguardando'), findsOneWidget);

    await tester.tap(find.byKey(const Key('waitlist-menu-w1')));
    await tester.pumpAndSettle();
    expect(find.text('Avisar de novo'), findsNothing); // ainda aguardando
    await tester.tap(find.text('Remover da lista'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('DELETE /waitlist/w1'));
    expect(find.text('Ana Souza saiu da lista de espera.'), findsOneWidget);
    expect(find.text('Ana Souza'), findsNothing);
  });

  testWidgets('adicionar cliente cadastrado (busca) e cliente novo',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester.pumpWidget(
        _app(WaitlistPage(api: ApiClient(adapter: b), initialDay: _day)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-add')));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar à espera de 03/11'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('waitlist-search')), 'caio');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waitlist-pick-c1')), findsNothing);
    await tester.tap(find.byKey(const Key('waitlist-pick-c9')));
    await tester.pumpAndSettle();
    expect(b.bodies[b.calls.indexOf('POST /waitlist')],
        {'client_id': 'c9', 'desired_date': _ds});
    expect(find.text('Caio Lima entrou na lista de espera.'), findsOneWidget);

    // cliente novo, com máscara no WhatsApp
    await tester.tap(find.byKey(const Key('waitlist-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente novo'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('waitlist-new-name')), 'Duda Nova');
    await tester.enterText(
        find.byKey(const Key('waitlist-new-phone')), '11987650012');
    await tester.pump();
    expect(find.text('(11) 98765-0012'), findsOneWidget);
    await tester.tap(find.byKey(const Key('waitlist-new-save')));
    await tester.pumpAndSettle();
    expect(b.bodies[b.calls.lastIndexOf('POST /waitlist')],
        {'name': 'Duda Nova', 'phone': '(11) 98765-0012', 'desired_date': _ds});
    expect(find.text('Duda Nova entrou na lista de espera.'), findsOneWidget);
  });

  testWidgets('adicionar quem já está: mensagem no próprio painel',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = _Backend()..duplicate = true;
    await tester.pumpWidget(
        _app(WaitlistPage(api: ApiClient(adapter: b), initialDay: _day)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitlist-pick-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Ana Souza já está na lista de espera de 03/11'),
        findsOneWidget);
  });

  testWidgets('dia passado: sem botão Adicionar; vazio e erro', (tester) async {
    final b = _Backend()..entries.clear();
    await tester.pumpWidget(_app(WaitlistPage(
        api: ApiClient(adapter: b), initialDay: DateTime(2020, 1, 6))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waitlist-add')), findsNothing);
    expect(find.text('Ninguém na espera para esse dia.'), findsOneWidget);

    final e = _Backend()..fail = true;
    await tester.pumpWidget(_app(WaitlistPage(
        key: const Key('p2'), api: ApiClient(adapter: e), initialDay: _day)));
    await tester.pumpAndSettle();
    expect(find.text('Servidor fora do ar'), findsOneWidget);
    e.fail = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Souza'), findsOneWidget);
  });

  testWidgets('"Vaga abriu" na central abre a lista de espera no dia',
      (tester) async {
    String? openedDate;
    final api = ApiClient(adapter: _NotifBackend());
    await tester.pumpWidget(_app(
        NotificationsPage(api: api, onOpenWaitlist: (d) => openedDate = d)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaga abriu — lista de espera'));
    await tester.pumpAndSettle();
    expect(openedDate, _ds);
  });
}

class _NotifBackend implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final data = o.path.endsWith('/notifications')
        ? {
            'unread': 1,
            'notifications': [
              {
                'id': 'n1',
                'type': 'waitlist',
                'title': 'Vaga abriu — lista de espera',
                'body': '1 cliente na espera para 03/11. Toque para avisar.',
                'data': {'date': _ds},
                'read': false,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              }
            ]
          }
        : {'ok': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      'content-type': ['application/json'],
    });
  }
}
