// "Bloquear horário": a tela conhece o dia (expediente, agendamentos com
// folga, bloqueios de agenda) e só deixa escolher o que está livre.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/agenda/block_time_page.dart';

/// Backend fake: segunda 07/01/2030, expediente 09–18, Angelita 10–11 e
/// Ezequias 11:30–12:30 (+10 de folga), bloqueio de agenda 15–16.
class _Backend implements HttpClientAdapter {
  final posts = <Map<String, dynamic>>[];
  int failPostStatus = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    ResponseBody json(int status, Object data) =>
        ResponseBody.fromString(jsonEncode(data), status, headers: {
          'content-type': ['application/json'],
        });
    String iso(int h, [int m = 0]) =>
        DateTime(2030, 1, 7, h, m).toUtc().toIso8601String();
    if (o.path.endsWith('/working-hours')) {
      return json(200, [
        {'weekday': 1, 'start_time': '09:00:00', 'end_time': '18:00:00'}
      ]);
    }
    if (o.path.endsWith('/time-offs')) {
      return json(200, [
        {
          'id': 't1',
          'reason': 'feriado',
          'starts_at': iso(15),
          'ends_at': iso(16)
        }
      ]);
    }
    if (o.path.endsWith('/appointments') && o.method == 'GET') {
      Map<String, dynamic> a(String n, int h, int m, int eh, int em,
              {int buf = 0, String status = 'confirmed'}) =>
          {
            'id': n,
            'client_name': n,
            'service_name': 'Corte',
            'starts_at': iso(h, m),
            'ends_at': iso(eh, em),
            'status': status,
            'source': 'app',
            'buffer_min': buf,
          };
      return json(200, {
        'appointments': [
          a('Angelita', 10, 0, 11, 0),
          a('Ezequias', 11, 30, 12, 30, buf: 10),
          a('Cancelada', 13, 0, 14, 0, status: 'canceled'), // não ocupa
        ]
      });
    }
    if (o.method == 'POST') {
      final chunks = await body?.toList() ?? [];
      posts.add(jsonDecode(utf8.decode(chunks.expand((c) => c).toList()))
          as Map<String, dynamic>);
      if (failPostStatus != 0) {
        return json(failPostStatus, {'error': 'conflito de horário'});
      }
      return json(201, {'appointment': {}});
    }
    return json(404, {'error': 'n/a'});
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<(_Backend, List<int?>)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _Backend();
    final results = <int?>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => results.add(await Navigator.of(ctx).push<int>(
              MaterialPageRoute(
                  builder: (_) => BlockTimePage(
                      api: ApiClient(adapter: backend),
                      initialDate: DateTime(2030, 1, 7),
                      clock: () => DateTime(2030, 1, 7, 8))))),
          child: const Text('ABRIR'),
        ),
      ),
    ));
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    return (backend, results);
  }

  Future<void> tap(WidgetTester tester, String hm) async {
    await tester.ensureVisible(find.byKey(Key('cell-$hm')));
    await tester.tap(find.byKey(Key('cell-$hm')));
    await tester.pump();
  }

  testWidgets('grade do dia: ocupados (com folga) e livres', (tester) async {
    await open(tester);
    expect(find.text('Segunda-feira, 7 de janeiro'), findsOneWidget);
    for (final h in ['09h', '12h', '17h']) {
      expect(find.text(h), findsOneWidget);
    }
    // nada marcado: sem botão de bloquear
    expect(find.byKey(const Key('block-submit')), findsNothing);
    // tocar num ocupado diz quem ocupa (inclui a folga do Ezequias)
    await tap(tester, '12:35');
    expect(find.text('12:35 ocupado: Ezequias · Corte'), findsOneWidget);
    await tap(tester, '15:20');
    expect(find.text('15:20 ocupado: Bloqueio de agenda · feriado'),
        findsOneWidget);
    // cancelado não ocupa: 13:00 continua livre (marca)
    await tap(tester, '13:00');
    expect(find.byKey(const Key('block-range-13:00')), findsOneWidget);
  });

  testWidgets(
      'monta 12:00–12:45 e 15:30–16:20 com toques e bloqueia num POST por trecho',
      (tester) async {
    final (backend, results) = await open(tester);
    // fake: 15–16 é bloqueio de agenda, então o 2º trecho vai de 16:00
    await tap(tester, '12:40'); // início
    expect(find.textContaining('fim do trecho que começa às 12:40'),
        findsOneWidget);
    await tap(tester, '13:20'); // fim (inclusive) → 12:40–13:25
    await tap(tester, '16:00');
    await tap(tester, '16:15'); // → 16:00–16:20
    expect(find.byKey(const Key('block-range-12:40')), findsOneWidget);
    expect(find.text('12:40 – 13:25'), findsOneWidget);
    expect(find.text('16:00 – 16:20'), findsOneWidget);
    expect(
        find.text('Bloquear 2 trechos (1 hora e 5 minutos)'), findsOneWidget);

    // desmarca só um quadradinho (13:20) → 1º trecho vira 12:40–13:20
    await tap(tester, '13:20');
    expect(find.text('12:40 – 13:20'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Almoço'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Almoço'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('block-submit')));
    await tester.pumpAndSettle();

    expect(backend.posts, hasLength(2));
    DateTime local(Object? v) => DateTime.parse(v as String).toLocal();
    expect(local(backend.posts[0]['startsAt']), DateTime(2030, 1, 7, 12, 40));
    expect(local(backend.posts[0]['endsAt']), DateTime(2030, 1, 7, 13, 20));
    expect(local(backend.posts[1]['startsAt']), DateTime(2030, 1, 7, 16));
    expect(local(backend.posts[1]['endsAt']), DateTime(2030, 1, 7, 16, 20));
    expect(backend.posts.every((p) => p['source'] == 'block'), isTrue);
    expect(backend.posts.every((p) => p['canceledReason'] == 'Almoço'), isTrue);
    expect(results, [2]);
  });

  testWidgets('trecho que atravessa ocupado vira dois; ✕ remove o trecho',
      (tester) async {
    await open(tester);
    await tap(tester, '09:30');
    await tap(tester, '11:10'); // atravessa a Angelita (10–11)
    expect(find.text('09:30 – 10:00'), findsOneWidget);
    expect(find.text('11:00 – 11:15'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('block-range-09:30')),
        matching: find.byIcon(Icons.close)));
    await tester.pump();
    expect(find.text('09:30 – 10:00'), findsNothing);
    expect(find.text('Bloquear 11:00 às 11:15'), findsOneWidget);
  });

  testWidgets('marcar todos os livres e limpar', (tester) async {
    final (backend, _) = await open(tester);
    await tester.tap(find.byKey(const Key('block-all-free')));
    await tester.pump();
    // livres: 9–10, 11–11:30, 12:40–15, 16–18
    expect(
        find.text('Bloquear 4 trechos (5 horas e 50 minutos)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-clear')));
    await tester.pump();
    expect(find.byKey(const Key('block-submit')), findsNothing);
    expect(backend.posts, isEmpty);
  });

  testWidgets('erro da API: mostra a mensagem e recarrega o dia',
      (tester) async {
    final (backend, results) = await open(tester);
    backend.failPostStatus = 409;
    await tap(tester, '09:00');
    await tap(tester, '09:20');
    await tester.tap(find.byKey(const Key('block-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Não consegui bloquear: conflito de horário'),
        findsOneWidget);
    expect(results, isEmpty); // continua na tela, seleção limpa
    expect(find.byKey(const Key('block-submit')), findsNothing);
  });

  testWidgets('não volta pra dia passado; avança e volta pro dia seguinte',
      (tester) async {
    await open(tester);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('block-prev-day')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('block-next-day')));
    await tester.pumpAndSettle();
    // terça: sem expediente no fake
    expect(find.text('Sem expediente neste dia — nada pra bloquear.'),
        findsOneWidget);
  });
}
