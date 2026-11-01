// Ranking de clientes: lista com posição/medalha, atendimentos, último
// atendimento e total; troca de período; vazio e erro; atalho na lista.

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
import 'package:minha_agenda/features/clients/clients_page.dart';
import 'package:minha_agenda/features/clients/clients_ranking_page.dart';

class _Backend implements HttpClientAdapter {
  final periods = <String>[];
  bool fail = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    ResponseBody json(int status, Object data) =>
        ResponseBody.fromString(jsonEncode(data), status, headers: {
          'content-type': ['application/json'],
        });
    if (fail) return json(500, {'error': 'Servidor fora do ar'});
    if (o.path.endsWith('/clients')) return json(200, []);
    final p = o.queryParameters['period'] as String;
    periods.add(p);
    Map<String, dynamic> row(int pos, String name, int visits, int cents,
            {bool archived = false}) =>
        {
          'position': pos,
          'client_id': 'c$pos',
          'name': name,
          'phone_e164': '55119000000$pos',
          'archived': archived,
          'visits': visits,
          'last_visit': DateTime(2026, 10, 20, 10).toUtc().toIso8601String(),
          'total_cents': cents,
        };
    if (p == '30') return json(200, {'period': p, 'ranking': []});
    return json(200, {
      'period': p,
      'ranking': [
        row(1, 'Ana', 12, 60000),
        row(2, 'Caio', 8, 40000, archived: true),
        row(3, 'Bia', 5, 25000),
        row(4, 'Dani', 1, 5000),
      ]
    });
  }
}

Widget _app(ApiClient api, {String initial = '/clients/ranking'}) =>
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: initial, routes: [
          GoRoute(
              path: '/clients',
              builder: (_, __) => ClientsPage(api: api),
              routes: [
                GoRoute(
                    path: 'ranking',
                    builder: (_, __) => ClientsRankingPage(api: api)),
              ]),
        ]),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('lista com medalhas, atendimentos, último e total',
      (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();

    expect(b.periods, ['all']);
    expect(find.text('1. Ana'), findsOneWidget);
    expect(find.text('12 atendimentos · último em 20/10/2026'), findsOneWidget);
    expect(find.textContaining('600,00'), findsOneWidget);
    // top 3 com troféu; 4º com o número
    expect(find.byIcon(Icons.emoji_events), findsNWidgets(3));
    expect(find.text('4º'), findsOneWidget);
    expect(find.text('1 atendimento · último em 20/10/2026'), findsOneWidget);
    expect(find.text('arquivado'), findsOneWidget);
  });

  testWidgets('troca de período e vazio', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 dias'));
    await tester.pumpAndSettle();
    expect(b.periods, ['all', '30']);
    expect(
        find.text('Nenhum atendimento neste período ainda.'), findsOneWidget);
    await tester.tap(find.text('12 meses'));
    await tester.pumpAndSettle();
    expect(b.periods.last, '365');
    expect(find.text('1. Ana'), findsOneWidget);
  });

  testWidgets('erro com Tentar novamente', (tester) async {
    final b = _Backend()..fail = true;
    await tester.pumpWidget(_app(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    expect(find.text('Servidor fora do ar'), findsOneWidget);
    b.fail = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('1. Ana'), findsOneWidget);
  });

  testWidgets('troféu em Clientes abre o ranking', (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(ApiClient(adapter: b), initial: '/clients'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-ranking')));
    await tester.pumpAndSettle();
    expect(find.text('Ranking de clientes'), findsOneWidget);
    expect(find.text('1. Ana'), findsOneWidget);
  });
}
