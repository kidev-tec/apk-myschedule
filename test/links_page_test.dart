// Módulo agregador (API 0026): tela de vínculos — os dois lados.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/links/links_page.dart';
import 'package:minha_agenda/features/links/links_service.dart';

Map<String, dynamic> link(
  String id, {
  String status = 'active',
  String requestedBy = 'professional',
  bool awaitingMe = false,
  bool show = true,
  int position = 0,
  String name = 'Ana',
  String? businessName,
  String? proCode,
  String? city,
}) =>
    {
      'id': id,
      'status': status,
      'requested_by': requestedBy,
      'awaiting_me': awaitingMe,
      'show_on_link': show,
      'position': position,
      'created_at': '2026-11-06T10:00:00.000Z',
      'responded_at': null,
      'counterpart': {
        'name': name,
        'business_name': businessName ?? name,
        if (proCode != null) 'pro_code': proCode,
        if (city != null) 'city': city,
        'logo_url': null,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;
  final calls = <String>[];

  void mockMe(String kind) {
    adapter.onGet(
        '/me',
        (s) => s.reply(200, {
              'name': kind == 'aggregator' ? 'Studio Central' : 'Ana',
              'account_kind': kind,
              'pro_code': 'P-ABCD2345',
              'aggregator_code': kind == 'aggregator' ? 'E-WXYZ6789' : null,
            }));
  }

  void mockLinks(String as, List<Map<String, dynamic>> links) {
    adapter.onGet('/links', (s) => s.reply(200, {'links': links}),
        queryParameters: {'as': as});
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(
        adapter: adapter, idToken: ({forceRefresh = false}) async => null);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method != 'GET') calls.add('${o.method} ${o.path} ${o.data}');
      h.next(o);
    }));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: LinksPage(api: api)));
    await tester.pumpAndSettle();
  }

  group('estabelecimento', () {
    testWidgets('mostra código, pedidos, convites e equipe na ordem',
        (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [
        link('a1', status: 'pending', awaitingMe: true, name: 'Bruno'),
        link('a2',
            status: 'pending',
            requestedBy: 'aggregator',
            name: 'Carla',
            businessName: 'Studio Carla',
            proCode: 'P-CCCC3333'),
        link('a3', position: 1, name: 'Ana', proCode: 'P-AAAA2222'),
        link('a4', position: 0, name: 'Davi', show: false),
      ]);
      await pump(tester);
      expect(find.text('Profissionais'), findsOneWidget);
      expect(find.text('E-WXYZ6789'), findsOneWidget);
      expect(find.text('Esperando sua resposta'), findsOneWidget);
      expect(find.text('Quer fazer parte da sua equipe.'), findsOneWidget);
      // convite enviado mostra negócio · código, não só o nome do usuário
      expect(find.text('Studio Carla · P-CCCC3333\nAguardando resposta'),
          findsOneWidget);
      expect(find.text('Convites enviados'), findsOneWidget);
      expect(find.text('Na equipe'), findsOneWidget);
      expect(find.text('P-AAAA2222'), findsOneWidget);
      // ordem do link: Davi (0) antes de Ana (1)
      expect(tester.getTopLeft(find.text('Davi')).dy,
          lessThan(tester.getTopLeft(find.text('Ana')).dy));
      final davi =
          tester.widget<SwitchListTile>(find.byKey(const Key('link-show-a4')));
      expect(davi.value, isFalse);
    });

    testWidgets('aceita pedido e recarrega', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [
        link('a1', status: 'pending', awaitingMe: true, name: 'Bruno'),
      ]);
      adapter.onPost('/links/a1/accept', (s) => s.reply(200, {}));
      await pump(tester);
      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      // recarga silenciosa: o título e a lista não somem
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Profissionais'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(calls, contains('POST /links/a1/accept null'));
      expect(find.text('Bruno agora faz parte da equipe.'), findsOneWidget);
    });

    testWidgets('recusa pedido', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [
        link('a1', status: 'pending', awaitingMe: true, name: 'Bruno'),
      ]);
      adapter.onPost('/links/a1/reject', (s) => s.reply(200, {}));
      await pump(tester);
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();
      expect(calls, contains('POST /links/a1/reject null'));
      expect(find.text('Pedido recusado.'), findsOneWidget);
    });

    testWidgets('cancela convite enviado', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [
        link('a2', status: 'pending', requestedBy: 'aggregator', name: 'Carla'),
      ]);
      adapter.onPost('/links/a2/cancel', (s) => s.reply(200, {}));
      await pump(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, contains('POST /links/a2/cancel null'));
      expect(find.text('Convite cancelado.'), findsOneWidget);
    });

    testWidgets('convida pelo código; erro da API aparece em PT-BR',
        (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', []);
      adapter.onPost(
          '/links',
          (s) => s.reply(404,
              {'error': 'Não encontramos um profissional com esse código.'}),
          data: {'code': 'P-ZZZZ9999'});
      await pump(tester);
      expect(
          find.textContaining('Nenhum profissional na equipe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('link-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('link-code-field')), ' P-ZZZZ9999 ');
      await tester.tap(find.text('Convidar'));
      await tester.pumpAndSettle();
      expect(find.text('Não encontramos um profissional com esse código.'),
          findsOneWidget);
    });

    testWidgets('convite enviado com sucesso', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', []);
      adapter.onPost('/links', (s) => s.reply(201, {'id': 'x'}),
          data: {'code': 'P-ABCD2345'});
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('link-code-field')), 'P-ABCD2345');
      await tester.tap(find.text('Convidar'));
      await tester.pumpAndSettle();
      expect(find.text('Convite enviado! O profissional precisa aceitar.'),
          findsOneWidget);
    });

    testWidgets('desliga do link (otimista) e grava', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [link('a3', name: 'Ana')]);
      adapter.onPatch('/links/a3', (s) => s.reply(200, {}),
          data: {'show_on_link': false});
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-show-a3')));
      await tester.pumpAndSettle();
      expect(calls, contains('PATCH /links/a3 {show_on_link: false}'));
      expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('link-show-a3')))
              .value,
          isFalse);
    });

    testWidgets('falha ao desligar volta o valor', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [link('a3', name: 'Ana')]);
      adapter.onPatch('/links/a3', (s) => s.reply(500, {'error': 'Falhou'}),
          data: {'show_on_link': false});
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-show-a3')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('link-show-a3')))
              .value,
          isTrue);
      expect(find.text('Falhou'), findsOneWidget);
    });

    testWidgets('move para baixo grava a nova ordem', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [
        link('a3', position: 0, name: 'Ana'),
        link('a4', position: 1, name: 'Davi'),
      ]);
      adapter
        ..onPatch('/links/a3', (s) => s.reply(200, {}), data: {'position': 1})
        ..onPatch('/links/a4', (s) => s.reply(200, {}), data: {'position': 0});
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-menu-a3')));
      await tester.pumpAndSettle();
      // o primeiro não pode subir
      expect(find.text('Mover para cima'), findsNothing);
      await tester.tap(find.text('Mover para baixo'));
      await tester.pumpAndSettle();
      expect(calls, contains('PATCH /links/a3 {position: 1}'));
      expect(calls, contains('PATCH /links/a4 {position: 0}'));
      expect(tester.getTopLeft(find.text('Davi')).dy,
          lessThan(tester.getTopLeft(find.text('Ana')).dy));
    });

    testWidgets('encerra vínculo com confirmação', (tester) async {
      mockMe('aggregator');
      mockLinks('aggregator', [link('a3', name: 'Ana')]);
      adapter.onPost('/links/a3/end',
          (s) => s.reply(200, {'status': 'ended', 'future_appointments': 2}));
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-menu-a3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encerrar vínculo'));
      await tester.pumpAndSettle();
      expect(find.text('Encerrar vínculo com Ana?'), findsOneWidget);
      await tester.tap(find.text('Encerrar'));
      await tester.pumpAndSettle();
      expect(calls, contains('POST /links/a3/end null'));
      expect(find.text('Vínculo com Ana encerrado.'), findsOneWidget);
    });
  });

  group('profissional', () {
    testWidgets('mostra código P-, convite recebido e estabelecimentos',
        (tester) async {
      mockMe('independent');
      mockLinks('professional', [
        link('p1',
            status: 'pending',
            requestedBy: 'aggregator',
            awaitingMe: true,
            name: 'Studio Central'),
        link('p2', name: 'Barbearia Sul', city: 'Recife'),
      ]);
      await pump(tester);
      expect(find.text('Meus estabelecimentos'), findsOneWidget);
      expect(find.text('P-ABCD2345'), findsOneWidget);
      expect(find.text('Convidou você para fazer parte da equipe.'),
          findsOneWidget);
      expect(find.text('Recife'), findsOneWidget);
      // profissional não organiza o link
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('aceita convite', (tester) async {
      mockMe('independent');
      mockLinks('professional', [
        link('p1',
            status: 'pending',
            requestedBy: 'aggregator',
            awaitingMe: true,
            name: 'Studio Central'),
      ]);
      adapter.onPost('/links/p1/accept', (s) => s.reply(200, {}));
      await pump(tester);
      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();
      expect(find.text('Pronto! Você agora faz parte de Studio Central.'),
          findsOneWidget);
    });

    testWidgets('pede para entrar e cancela o pedido', (tester) async {
      mockMe('independent');
      mockLinks('professional', [
        link('p3', status: 'pending', name: 'Studio Norte'),
      ]);
      adapter
        ..onPost('/links', (s) => s.reply(201, {'id': 'x'}),
            data: {'code': 'E-WXYZ6789'})
        ..onPost('/links/p3/cancel', (s) => s.reply(200, {}));
      await pump(tester);
      expect(find.text('Pedidos enviados'), findsOneWidget);
      await tester.tap(find.byKey(const Key('link-add')));
      await tester.pumpAndSettle();
      expect(find.text('Código do estabelecimento'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('link-code-field')), 'E-WXYZ6789');
      await tester.tap(find.text('Enviar pedido'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Pedido enviado! Agora é só aguardar o estabelecimento aceitar.'),
          findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Pedido cancelado.'), findsOneWidget);
    });

    testWidgets('sair do estabelecimento avisa os agendamentos que ficam',
        (tester) async {
      mockMe('independent');
      mockLinks('professional', [link('p2', name: 'Barbearia Sul')]);
      adapter.onPost('/links/p2/end',
          (s) => s.reply(200, {'status': 'ended', 'future_appointments': 1}));
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-menu-p2')));
      await tester.pumpAndSettle();
      expect(find.text('Mover para baixo'), findsNothing);
      await tester.tap(find.text('Sair do estabelecimento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Você saiu de Barbearia Sul. 1 agendamento futuro continua na sua agenda.'),
          findsOneWidget);
    });

    testWidgets('desistir na confirmação não encerra', (tester) async {
      mockMe('independent');
      mockLinks('professional', [link('p2', name: 'Barbearia Sul')]);
      await pump(tester);
      await tester.tap(find.byKey(const Key('link-menu-p2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair do estabelecimento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('lista vazia orienta a pedir o código', (tester) async {
      mockMe('independent');
      mockLinks('professional', []);
      await pump(tester);
      expect(
          find.textContaining(
              'Você ainda não faz parte de nenhum estabelecimento'),
          findsOneWidget);
    });
  });

  testWidgets('erro ao carregar mostra tentar de novo', (tester) async {
    adapter.onGet('/me', (s) => s.reply(500, {'error': 'Fora do ar'}));
    await pump(tester);
    expect(find.text('Fora do ar'), findsOneWidget);
    mockMe('independent');
    mockLinks('professional', []);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Meus estabelecimentos'), findsOneWidget);
  });

  test('ProfessionalLink.fromJson lê os campos e tem padrões seguros', () {
    final l = ProfessionalLink.fromJson(link('z',
        status: 'pending', awaitingMe: true, show: false, position: 3));
    expect(l.isPending, isTrue);
    expect(l.awaitingMe, isTrue);
    expect(l.showOnLink, isFalse);
    expect(l.position, 3);
    final bare = ProfessionalLink.fromJson({'id': 'y'});
    expect(bare.status, 'pending');
    expect(bare.showOnLink, isTrue);
    expect(bare.name, '');
  });
}
