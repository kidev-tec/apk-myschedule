// Regressão: criar/editar serviço trocava a pilha (context.go) e a lista de
// serviços ficava sem a seta de voltar — o usuário ficava preso na tela.
// Agora o form volta com pop(true) e a lista recarrega.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/services/service_form_page.dart';
import 'package:minha_agenda/features/services/services_page.dart';

/// Backend fake em memória: GET /services lista, POST /services adiciona,
/// GET/PATCH /services/:id lê/edita.
class _FakeServicesAdapter implements HttpClientAdapter {
  /// Simula a API recusando o POST (400 com `error` em PT-BR).
  bool failPost = false;

  final services = <Map<String, dynamic>>[
    {'id': 's1', 'name': 'Corte', 'duration_min': 30, 'price_cents': 4000},
    {'id': 's2', 'name': 'Barba', 'duration_min': 20, 'price_cents': 3000},
  ];
  final posts = <Map<String, dynamic>>[];

  /// GET /services: atraso (simula rede lenta) e quantas falhas antes de ok.
  Duration listDelay = Duration.zero;
  int listFailures = 0;
  final deletes = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ResponseBody json(int status, Object body) =>
        ResponseBody.fromString(jsonEncode(body), status, headers: {
          'content-type': ['application/json'],
        });
    Future<Map<String, dynamic>> body() async {
      final chunks = await requestStream?.toList() ?? [];
      return jsonDecode(utf8.decode(chunks.expand((c) => c).toList()))
          as Map<String, dynamic>;
    }

    final path = options.path;
    if (path.endsWith('/services') && options.method == 'GET') {
      await Future<void>.delayed(listDelay);
      if (listFailures > 0) {
        listFailures--;
        return json(500, {'error': 'boom'});
      }
      return json(200, services);
    }
    if (path.endsWith('/services') && options.method == 'POST' && failPost) {
      return json(400, {'error': 'Duração inválida'});
    }
    if (path.endsWith('/services') && options.method == 'POST') {
      final b = await body();
      posts.add(Map.of(b));
      final items = b.remove('items') as List?;
      final s = {
        'id': 's${services.length + 1}',
        ...b,
        'is_kit': items != null,
        if (items != null)
          'items': [
            for (final i in items) services.firstWhere((x) => x['id'] == i)
          ],
      };
      services.add(s);
      return json(201, s);
    }
    final id = path.split('/').last;
    if (options.method == 'DELETE') {
      deletes.add(options);
      final kits = services
          .where((k) =>
              k['is_kit'] == true &&
              (k['items'] as List).any((i) => i['id'] == id))
          .toList();
      if (kits.isNotEmpty && options.queryParameters['kits'] != 'archive') {
        return json(409, {
          'error': 'está em kit',
          'kits': [
            for (final k in kits) {'id': k['id'], 'name': k['name']}
          ],
        });
      }
      services.removeWhere((x) => x['id'] == id || kits.contains(x));
      return json(200, {'ok': true});
    }
    final svc = services.firstWhere((s) => s['id'] == id);
    if (options.method == 'PATCH') svc.addAll(await body());
    return json(200, svc);
  }
}

Widget _wrap(ApiClient api) {
  final router = GoRouter(initialLocation: '/settings', routes: [
    GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('PAGINA AGENDA'))),
    GoRoute(
      path: '/settings',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push('/services'),
            child: const Text('Meus serviços'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/services',
      builder: (_, __) => ServicesPage(api: api),
      routes: [
        GoRoute(path: 'new', builder: (_, __) => ServiceFormPage(api: api)),
        GoRoute(
            path: 'new-kit',
            builder: (_, __) => ServiceFormPage(kit: true, api: api)),
        GoRoute(
            path: ':id/edit',
            builder: (_, s) =>
                ServiceFormPage(serviceId: s.pathParameters['id'], api: api)),
      ],
    ),
  ]);
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('criar serviço volta pra lista COM seta de voltar e já listado',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    expect(find.text('Corte'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-service')));
    await tester.pumpAndSettle();
    expect(find.text('Novo serviço'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Sobrancelha');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Duração (min) *'), '70');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Preço *'), '25,00');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // de volta na lista, com o novo serviço e a seta de voltar
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Sobrancelha'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    // e a seta leva de volta pra tela de origem
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Meus serviços'), findsOneWidget);
  });

  testWidgets('editar serviço também preserva a seta e atualiza a lista',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar serviço'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Corte degradê');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Corte degradê'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('erro da API aparece em português, sem exceção crua',
      (tester) async {
    final backend = _FakeServicesAdapter()..failPost = true;
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-service')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Depilação');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Duração (min) *'), '70');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Preço *'), '150');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Não consegui salvar: Duração inválida'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('Novo serviço'), findsOneWidget); // continua no form
  });

  testWidgets('form valida duração fora de 5..480 / passo 5', (tester) async {
    await tester.pumpWidget(_wrap(ApiClient(adapter: _FakeServicesAdapter())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-service')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Duração (min) *'), '72');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('5 a 480 min, de 5 em 5'), findsOneWidget);
  });

  testWidgets('setas da duração andam de 5 em 5 dentro de 5..480; preço em R\$',
      (tester) async {
    await tester.pumpWidget(_wrap(ApiClient(adapter: _FakeServicesAdapter())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-service')));
    await tester.pumpAndSettle();

    final dur = find.widgetWithText(TextFormField, 'Duração (min) *');
    String valor() => tester.widget<TextFormField>(dur).controller!.text;
    expect(valor(), '60');
    String extenso() =>
        tester.widget<Text>(find.byKey(const Key('duration-human'))).data!;
    expect(extenso(), 'Duração: 1 hora');

    await tester.tap(find.byKey(const Key('duration-up')));
    await tester.pump();
    expect(valor(), '65');
    expect(extenso(), 'Duração: 1 hora e 5 minutos');
    await tester.tap(find.byKey(const Key('duration-down')));
    await tester.tap(find.byKey(const Key('duration-down')));
    await tester.pump();
    expect(valor(), '55');

    expect(extenso(), 'Duração: 55 minutos');

    // digitado fora do passo: sem extenso (inválido)…
    await tester.enterText(dur, '62');
    await tester.pump();
    expect(extenso(), 'Duração: —');
    // …e a seta encaixa no múltiplo de 5
    await tester.enterText(dur, '62');
    await tester.tap(find.byKey(const Key('duration-up')));
    await tester.pump();
    expect(valor(), '65');
    await tester.enterText(dur, '62');
    await tester.tap(find.byKey(const Key('duration-down')));
    await tester.pump();
    expect(valor(), '60');

    // limites: não passa de 480 nem desce de 5
    await tester.enterText(dur, '480');
    await tester.pump();
    await tester.tap(find.byKey(const Key('duration-up')));
    await tester.pump();
    expect(valor(), '480');
    await tester.enterText(dur, '5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('duration-down')));
    await tester.pump();
    expect(valor(), '5');

    expect(find.byKey(const Key('price-currency')), findsOneWidget);
    expect(find.text('R\$'), findsOneWidget);
  });
  Future<void> openNewKit(WidgetTester tester, _FakeServicesAdapter b) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-kit')));
    await tester.pumpAndSettle();
  }

  testWidgets('kit: marca serviços, soma sugerida, desconto e cria',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    expect(find.text('Novo kit'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'), 'Corte + Barba');
    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();

    final dur = find.widgetWithText(TextFormField, 'Duração (min) *');
    String txt(Finder f) => tester.widget<TextFormField>(f).controller!.text;
    String val(String k) =>
        tester.widget<Text>(find.byKey(Key(k))).data!.replaceAll('\u00a0', ' ');
    // kit não tem campo de preço: preço = soma − desconto
    expect(find.widgetWithText(TextFormField, 'Preço *'), findsNothing);
    // soma: 30 + 20 min, R$ 40 + R$ 30
    expect(txt(dur), '50');
    expect(val('kit-sum'), 'R\$ 70,00');
    expect(val('kit-price'), 'R\$ 70,00');
    expect(find.byKey(const Key('kit-discount-value')), findsNothing);

    // desconto só em %: o "%" fica fixo ao lado (sem R$)
    expect(find.byKey(const Key('discount-unit')), findsOneWidget);
    final desconto = find.byKey(const Key('kit-discount'));
    await tester.enterText(desconto, '20'); // 20% de 70 = 14
    await tester.pump();
    expect(val('kit-discount-value'), '− R\$ 14,00');
    expect(find.text('Desconto (20%)'), findsOneWidget);
    expect(val('kit-price'), 'R\$ 56,00');
    expect(
        tester.widget<Text>(find.byKey(const Key('kit-sum'))).style?.decoration,
        TextDecoration.lineThrough);

    // duração ajustada à mão → "Usar a soma" volta pra 50
    await tester.tap(find.byKey(const Key('duration-down')));
    await tester.pump();
    expect(txt(dur), '45');
    await tester.tap(find.byKey(const Key('kit-use-sum')));
    await tester.pump();
    expect(txt(dur), '50');

    // % quebrado: 12,5% de 70 = 8,75 → R$ 61,25
    await tester.enterText(desconto, '12,5');
    await tester.pump();
    expect(val('kit-price'), 'R\$ 61,25');

    await tester.tap(find.text('Criar kit'));
    await tester.pumpAndSettle();

    final post = backend.posts.single;
    expect(post['items'], ['s1', 's2']);
    expect(post['duration_min'], 50);
    expect(post['price_cents'], 6125);
    // de volta na lista, mostrando o que o kit inclui e o desconto
    expect(find.textContaining('Kit: Corte + Barba'), findsOneWidget);
    expect(find.textContaining(RegExp(r'de R\$.70,00 por R\$.61,25')),
        findsOneWidget);
  });

  testWidgets('desconto acima de 100% ou inválido não salva', (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'K');
    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();
    final desconto = find.byKey(const Key('kit-discount'));
    await tester.enterText(desconto, '120');
    await tester.tap(find.text('Criar kit'));
    await tester.pump();
    expect(find.text('Até 100%'), findsOneWidget);
    await tester.enterText(desconto, 'x');
    await tester.tap(find.text('Criar kit'));
    await tester.pump();
    expect(find.text('Inválido'), findsOneWidget);
    expect(backend.posts, isEmpty);
  });

  testWidgets('kit com menos de 2 serviços não salva', (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'K');
    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.pump();
    await tester.tap(find.text('Criar kit'));
    await tester.pump();
    expect(find.text('Escolhe pelo menos 2 serviços pro kit'), findsOneWidget);
    expect(backend.posts, isEmpty);
  });

  testWidgets('excluir serviço que está em kit: avisa e exclui junto se pedir',
      (tester) async {
    final backend = _FakeServicesAdapter();
    backend.services.add({
      'id': 'k1',
      'name': 'Combo',
      'duration_min': 50,
      'price_cents': 6000,
      'is_kit': true,
      'items': [backend.services[0], backend.services[1]],
    });
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first); // Corte
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(find.text('Serviço está em kit'), findsOneWidget);
    expect(find.textContaining('faz parte de: Combo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-with-kits')));
    await tester.pumpAndSettle();

    expect(backend.deletes.last.queryParameters['kits'], 'archive');
    expect(find.text('Corte'), findsNothing);
    expect(find.text('Combo'), findsNothing);
    expect(find.text('Barba'), findsOneWidget);
  });

  testWidgets('editar kit com desconto traz o desconto preenchido',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _FakeServicesAdapter();
    backend.services.add({
      'id': 'k1',
      'name': 'Combo',
      'duration_min': 50,
      'price_cents': 6000,
      'is_kit': true,
      'items': [backend.services[0], backend.services[1]],
    });
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last); // Combo
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Editar kit'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('kit-discount')))
            .controller!
            .text,
        '14,3'); // (70 − 60) / 70
    expect(
        tester
            .widget<Text>(find.byKey(const Key('kit-price')))
            .data!
            .replaceAll('\u00a0', ' '),
        'R\$ 60,00'); // preço salvo exato, não 14,3% arredondado

    // salvar sem mexer mantém o preço salvo (R$ 60,00)
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(backend.services.firstWhere((x) => x['id'] == 'k1')['price_cents'],
        6000);
  });

  testWidgets('setas do desconto: 1 em 1 ponto %, encaixa e respeita 0..100',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    final desconto = find.byKey(const Key('kit-discount'));
    String txt() => tester.widget<TextFormField>(desconto).controller!.text;
    bool enabled(String k) =>
        tester.widget<InkWell>(find.byKey(Key(k))).onTap != null;

    // sem serviço marcado não dá pra subir; vazio não desce
    expect(enabled('discount-up'), isFalse);
    expect(enabled('discount-down'), isFalse);

    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('discount-up')));
    await tester.pump();
    expect(txt(), '1');
    expect(find.text('Desconto (1%)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discount-up')));
    await tester.pump();
    expect(txt(), '2');
    await tester.tap(find.byKey(const Key('discount-down')));
    await tester.pump();
    expect(txt(), '1');
    // quebrado (7,5) sobe pra 8 e desce pra 7
    await tester.enterText(desconto, '7,5');
    await tester.tap(find.byKey(const Key('discount-up')));
    await tester.pump();
    expect(txt(), '8');
    await tester.enterText(desconto, '7,5');
    await tester.tap(find.byKey(const Key('discount-down')));
    await tester.pump();
    expect(txt(), '7');
    // limite 100
    await tester.enterText(desconto, '99,5');
    await tester.tap(find.byKey(const Key('discount-up')));
    await tester.pump();
    expect(txt(), '100');
    expect(enabled('discount-up'), isFalse);
    // descer até 0 limpa o campo
    await tester.enterText(desconto, '1');
    await tester.tap(find.byKey(const Key('discount-down')));
    await tester.pump();
    expect(txt(), '');
  });

  testWidgets('nome do kit é preenchido com os serviços marcados',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    final nome = find.widgetWithText(TextFormField, 'Nome');
    String txt() => tester.widget<TextFormField>(nome).controller!.text;

    // ordem de marcação: Barba, depois Corte → campo preenchido
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();
    expect(txt(), 'Barba');
    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.pump();
    expect(txt(), 'Barba + Corte');
    expect(find.text('Nome automático com os serviços — pode editar'),
        findsOneWidget);

    // desmarcar atualiza também
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();
    expect(txt(), 'Corte');
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();
    expect(txt(), 'Corte + Barba');

    await tester.tap(find.text('Criar kit'));
    await tester.pumpAndSettle();
    expect(backend.posts.single['name'], 'Corte + Barba');
    expect(backend.posts.single['items'], ['s1', 's2']);
  });

  testWidgets('nome digitado não é sobrescrito; apagado volta o automático',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend);
    final nome = find.widgetWithText(TextFormField, 'Nome');
    String txt() => tester.widget<TextFormField>(nome).controller!.text;

    await tester.tap(find.byKey(const Key('kit-item-s1')));
    await tester.pump();
    await tester.enterText(nome, 'Combo do pai');
    await tester.pump();
    expect(find.text('Nome automático com os serviços — pode editar'),
        findsNothing);
    await tester.tap(find.byKey(const Key('kit-item-s2')));
    await tester.pump();
    expect(txt(), 'Combo do pai');

    // apagou → próxima marcação volta pro automático
    await tester.enterText(nome, '');
    await tester.tap(find.byKey(const Key('kit-item-s2'))); // desmarca
    await tester.pump();
    expect(txt(), 'Corte');
  });

  testWidgets('kit: mostra carregando enquanto a lista de serviços não chega',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    backend.listDelay = const Duration(seconds: 2);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-kit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // abriu a tela

    expect(find.text('Carregando serviços…'), findsOneWidget);
    expect(find.textContaining('Cadastra os serviços avulsos'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Carregando serviços…'), findsNothing);
    expect(find.byKey(const Key('kit-item-s1')), findsOneWidget);
  });

  testWidgets('kit: falha ao carregar mostra Tentar de novo', (tester) async {
    final backend = _FakeServicesAdapter();
    await tester.pumpWidget(_wrap(ApiClient(adapter: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    backend.listFailures = 1;
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-kit')));
    await tester.pumpAndSettle();

    expect(find.text('Não consegui carregar os serviços.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kit-items-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kit-item-s2')), findsOneWidget);
  });

  testWidgets('ícone Início leva direto pra agenda de qualquer tela interna',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openNewKit(tester, backend); // Configurações → Serviços → Novo kit
    expect(find.text('Novo kit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('go-home')));
    await tester.pumpAndSettle();
    expect(find.text('PAGINA AGENDA'), findsOneWidget);
    expect(find.text('Novo kit'), findsNothing);
    expect(find.text('Serviços'), findsNothing);
  });

  Future<void> openEditCombo(
      WidgetTester tester, _FakeServicesAdapter b, int durationMin) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    b.services.add({
      'id': 'k1',
      'name': 'Combo',
      'duration_min': durationMin,
      'price_cents': 7000,
      'is_kit': true,
      'items': [b.services[0], b.services[1]], // 30 + 20 = 50 min
    });
    b.services.add({
      'id': 's3',
      'name': 'Sobrancelha',
      'duration_min': 15,
      'price_cents': 2000
    });
    await tester.pumpWidget(_wrap(ApiClient(adapter: b)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meus serviços'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).at(2)); // Combo
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar kit'), findsOneWidget);
  }

  testWidgets('editar kit: duração igual à soma acompanha os serviços',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openEditCombo(tester, backend, 50);
    final dur = find.widgetWithText(TextFormField, 'Duração (min) *');
    String txt() => tester.widget<TextFormField>(dur).controller!.text;
    expect(txt(), '50');
    await tester.tap(find.byKey(const Key('kit-item-s3'))); // +15
    await tester.pump();
    expect(txt(), '65');
  });

  testWidgets('editar kit: duração ajustada à mão fica até "Usar a soma"',
      (tester) async {
    final backend = _FakeServicesAdapter();
    await openEditCombo(tester, backend, 40);
    final dur = find.widgetWithText(TextFormField, 'Duração (min) *');
    String txt() => tester.widget<TextFormField>(dur).controller!.text;
    await tester.tap(find.byKey(const Key('kit-item-s3')));
    await tester.pump();
    expect(txt(), '40');
    await tester.tap(find.byKey(const Key('kit-use-sum')));
    await tester.pump();
    expect(txt(), '65');
  });
}
