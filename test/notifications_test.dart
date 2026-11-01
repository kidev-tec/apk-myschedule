// Central de notificações: sino com contagem de não lidas (atualiza com
// push), lista agrupada por dia, marcar lida/todas, abrir o dia do
// agendamento, estados vazio/erro e "carregar mais".

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/push/push_events.dart';
import 'package:minha_agenda/features/notifications/notification_bell.dart';
import 'package:minha_agenda/features/notifications/notifications_page.dart';

/// "Agora" fixo dos testes: 30/10/2026 15:00.
final _now = DateTime(2026, 10, 30, 15);

class _Backend implements HttpClientAdapter {
  _Backend(this.items);
  final List<Map<String, dynamic>> items;
  final calls = <String>[];
  bool fail = false;
  int unreadOverride = -1;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    ResponseBody json(int status, Object data) =>
        ResponseBody.fromString(jsonEncode(data), status, headers: {
          'content-type': ['application/json'],
        });
    calls.add(
        '${o.method} ${o.path}${o.queryParameters.isEmpty ? '' : '?${o.queryParameters.keys.join(',')}'}');
    if (fail) return json(500, {'error': 'Servidor fora do ar'});
    final unread = items.where((n) => n['read'] != true).length;
    if (o.path.endsWith('/unread-count')) {
      return json(
          200, {'unread': unreadOverride >= 0 ? unreadOverride : unread});
    }
    if (o.path.endsWith('/read-all')) {
      for (final n in items) {
        n['read'] = true;
      }
      return json(200, {'unread': 0});
    }
    if (o.path.endsWith('/read')) {
      final id = o.path.split('/')[o.path.split('/').length - 2];
      items.firstWhere((n) => n['id'] == id)['read'] = true;
      return json(200, {'ok': true});
    }
    // lista com paginação simples (limit/before)
    final limit = o.queryParameters['limit'] as int? ?? 30;
    final before = o.queryParameters['before'] as String?;
    final list = items
        .where((n) =>
            before == null ||
            DateTime.parse(n['created_at'] as String)
                .isBefore(DateTime.parse(before)))
        .take(limit)
        .toList();
    return json(200, {'notifications': list, 'unread': unread});
  }
}

Map<String, dynamic> _n(String id, String type, String title, DateTime at,
        {bool read = false, String? startsAt}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'body': 'Corpo $id',
      'data': {if (startsAt != null) 'starts_at': startsAt},
      'read': read,
      'created_at': at.toUtc().toIso8601String(),
    };

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      home: home,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  List<Map<String, dynamic>> sample() => [
        _n('n1', 'new_booking', 'Novo agendamento',
            _now.subtract(const Duration(hours: 1)),
            startsAt: DateTime(2026, 11, 2, 9).toUtc().toIso8601String()),
        _n('n2', 'client_canceled', '❌ Cancelamento',
            _now.subtract(const Duration(hours: 3))),
        _n('n3', 'reminder', 'Lembrete de agendamento',
            _now.subtract(const Duration(days: 1)),
            read: true),
        _n('n4', 'waitlist', 'Vaga abriu', DateTime(2026, 10, 20, 10),
            read: true),
      ];

  testWidgets('sino: bolinha com não lidas e atualiza quando chega push',
      (tester) async {
    final b = _Backend(sample());
    var opened = 0;
    await tester.pumpWidget(_app(Scaffold(
      appBar: AppBar(actions: [
        NotificationBell(
            api: ApiClient(adapter: b), onOpen: () async => opened++),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsOneWidget);

    // chega push de notificação → recarrega a contagem
    b.unreadOverride = 5;
    PushEvents.instance.handle({'type': 'new_booking', 'notification_id': 'x'});
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);

    // sem não lidas: sino vazio, sem bolinha
    b.unreadOverride = 0;
    await tester.tap(find.byKey(const Key('notification-bell')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('lista por dia, destaque das não lidas e marcar todas',
      (tester) async {
    final b = _Backend(sample());
    await tester.pumpWidget(
        _app(NotificationsPage(api: ApiClient(adapter: b), clock: () => _now)));
    await tester.pumpAndSettle();

    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Ontem'), findsOneWidget);
    expect(find.text('Terça-feira, 20 de outubro'), findsOneWidget);
    expect(find.text('Novo agendamento'), findsOneWidget);
    expect(find.byKey(const Key('notification-unread-n1')), findsOneWidget);
    expect(find.byKey(const Key('notification-unread-n2')), findsOneWidget);
    expect(find.byKey(const Key('notification-unread-n3')), findsNothing);
    // ícone por tipo
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.alarm), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-read-all')));
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST /notifications/read-all'));
    expect(find.byKey(const Key('notification-unread-n1')), findsNothing);
    expect(find.byKey(const Key('notifications-read-all')), findsNothing);
  });

  testWidgets('tocar marca como lida e volta com o dia do agendamento',
      (tester) async {
    final b = _Backend(sample());
    DateTime? result;
    await tester.pumpWidget(_app(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await Navigator.of(ctx).push<DateTime>(
            MaterialPageRoute(
                builder: (_) => NotificationsPage(
                    api: ApiClient(adapter: b), clock: () => _now))),
        child: const Text('ABRIR'),
      ),
    )));
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();

    // sem agendamento ligado: marca como lida e fica na tela
    await tester.tap(find.text('❌ Cancelamento'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST /notifications/n2/read'));
    expect(find.byKey(const Key('notification-unread-n2')), findsNothing);
    expect(result, isNull);

    // de agendamento: volta pra agenda no dia dele
    await tester.tap(find.text('Novo agendamento'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST /notifications/n1/read'));
    expect(result, DateTime(2026, 11, 2, 9));
  });

  testWidgets('vazio, erro com Tentar de novo e Carregar mais', (tester) async {
    final vazio = _Backend([]);
    await tester.pumpWidget(_app(
        NotificationsPage(api: ApiClient(adapter: vazio), clock: () => _now)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nenhuma notificação ainda'), findsOneWidget);

    final erro = _Backend(sample())..fail = true;
    await tester.pumpWidget(_app(NotificationsPage(
        key: const Key('p2'),
        api: ApiClient(adapter: erro),
        clock: () => _now)));
    await tester.pumpAndSettle();
    expect(find.text('Servidor fora do ar'), findsOneWidget);
    erro.fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Novo agendamento'), findsOneWidget);

    // 31 notificações: 1ª página traz 30 e mostra "Carregar mais"
    final muitas = _Backend([
      for (var i = 0; i < 31; i++)
        _n('m$i', 'reminder', 'Lembrete $i',
            _now.subtract(Duration(minutes: i)),
            read: true),
    ]);
    await tester.pumpWidget(_app(NotificationsPage(
        key: const Key('p3'),
        api: ApiClient(adapter: muitas),
        clock: () => _now)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('notifications-more')), 400);
    await tester.tap(find.byKey(const Key('notifications-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lembrete 30'), 400);
    expect(find.text('Lembrete 30'), findsOneWidget);
    expect(find.byKey(const Key('notifications-more')), findsNothing);
  });
}
