// Cliente que se cadastrou pelo link público (origin=public_link) aparece
// com a etiqueta "Cadastro pelo link" na lista; cadastrado no app, não.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/clients/clients_page.dart';

class _Clients implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
          Future<void>? cancel) async =>
      ResponseBody.fromString(
          jsonEncode([
            {'id': 'c1', 'name': 'Angelita', 'phone_e164': '5513992050384'},
            {
              'id': 'c2',
              'name': 'kiki',
              'phone_e164': '5513992093812',
              'origin': 'public_link'
            },
            {
              'id': 'c3',
              'name': 'Ezequias',
              'phone_e164': '5513997080384',
              'origin': 'app'
            },
          ]),
          200,
          headers: {
            'content-type': ['application/json'],
          });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('ícone de cadastro pelo link só em quem veio do link',
      (tester) async {
    final api = ApiClient(adapter: _Clients());
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => ClientsPage(api: api)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('kiki'), findsOneWidget);
    expect(find.byKey(const Key('client-public-link-badge')), findsOneWidget);
    // só o ícone, no card da kiki; o texto não fica visível
    expect(find.text('Cadastro pelo link'), findsNothing);
    expect(
        find.descendant(
            of: find.widgetWithText(Card, 'kiki'),
            matching: find.byKey(const Key('client-public-link-badge'))),
        findsOneWidget);
    // tocar no ícone mostra a explicação
    await tester.tap(find.byKey(const Key('client-public-link-badge')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Cadastro feito pelo cliente'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
