// GAP-1 (RF-02): fluxo de edição de cliente end-to-end.
// Rota /clients/:id/edit → ClientFormPage(clientId) → PATCH /clients/:id.
// Regressão: form em modo edição NUNCA pode chamar POST (criaria duplicado).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/cep/cep_service.dart';
import 'package:minha_agenda/features/clients/client_form_page.dart';

// O form cria o próprio ApiClient (não tem provider de DI como o wizard) —
// mocka o adapter global do Dio via HttpOverrides? Não: injeta via
// dart-define não dá em teste. O ClientFormPage usa ApiClient() direto,
// então mockamos no nível do DioAdapter via constructor? Também não.
// Solução do repo: o form usa ApiClient() — pra testar, extraímos o método
// _save via widget com ApiClient injetado. Como o form NÃO aceita injeção,
// este teste valida o WIRE (rota + payload) via interceptor global capturado
// no ApiClient real com adapter de teste montado pelo http_mock_adapter
// através do HttpClientAdapter default substituível.
// ATUALIZAÇÃO (GAP-1): o form ganhou parâmetro opcional `api` pra DI.

Widget _wrap({required String? clientId, required ApiClient api}) {
  final router = GoRouter(initialLocation: '/clients/$clientId/edit', routes: [
    GoRoute(
      path: '/clients/:id/edit',
      builder: (_, state) => ClientFormPage(
        clientId: state.pathParameters['id'],
        api: api,
      ),
    ),
    GoRoute(
        path: '/clients',
        builder: (_, __) => const Scaffold(body: Text('LISTA CLIENTES'))),
  ]);
  return ProviderScope(
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Formulário de cliente é longo: tela alta pra todos os campos montarem.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;
  final requests = <({String method, String path, dynamic body})>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    requests.clear();

    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(adapter: adapter);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, h) {
      requests.add((
        method: options.method,
        path: options.path,
        body: options.data,
      ));
      h.next(options);
    }));
  });

  testWidgets('modo edição carrega cliente e salva com PATCH (não POST)',
      (tester) async {
    _tall(tester);
    adapter.onGet(
        '/clients/abc-123',
        (s) => s.reply(200, {
              'id': 'abc-123',
              'name': 'Ana',
              'phone_e164': '+5514999990001',
              'email': 'ana@x.com',
              'notes': 'alérgica a tinta',
            }));
    adapter.onPatch('/clients/abc-123', (s) => s.reply(200, {'id': 'abc-123'}),
        data: Matchers.any);

    await tester.pumpWidget(_wrap(clientId: 'abc-123', api: api));
    await tester.pumpAndSettle();

    // carregou os dados pro form
    expect(find.widgetWithText(TextFormField, 'Nome *'), findsOneWidget);
    final nameField = tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, 'Nome *'));
    expect(nameField.controller!.text, 'Ana');
    // informações do cliente carregadas no campo próprio
    final notesField =
        tester.widget<TextFormField>(find.byKey(const Key('client-notes')));
    expect(notesField.controller!.text, 'alérgica a tinta');

    // edita o nome e salva
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Ana Silva');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();

    // PATCH (não POST!) com o payload correto
    final patch = requests.where((r) => r.method == 'PATCH').toList();
    expect(patch, hasLength(1));
    expect(patch.single.path, '/clients/abc-123');
    expect(patch.single.body['name'], 'Ana Silva');
    // PATCH substitui tudo: as informações precisam ir junto (senão apagam)
    expect(patch.single.body['notes'], 'alérgica a tinta');
    expect(requests.where((r) => r.method == 'POST'), isEmpty);

    // volta pra lista
    expect(find.text('LISTA CLIENTES'), findsOneWidget);
  });

  testWidgets('modo criação continua com POST', (tester) async {
    _tall(tester);
    adapter.onPost('/clients', (s) => s.reply(201, {'id': 'novo'}),
        data: Matchers.any);

    final router = GoRouter(initialLocation: '/clients/new', routes: [
      GoRoute(
        path: '/clients/new',
        builder: (_, __) => ClientFormPage(api: api),
      ),
      GoRoute(
          path: '/clients',
          builder: (_, __) => const Scaffold(body: Text('LISTA CLIENTES'))),
    ]);

    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Beto');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '+5514999990002');
    await tester.enterText(
        find.byKey(const Key('client-notes')), '  gosta de café  ');
    await tester.ensureVisible(find.text('Criar cliente'));
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();

    final post = requests.where((r) => r.method == 'POST').toList();
    expect(post, hasLength(1));
    expect(post.single.path, '/clients');
    expect(post.single.body['notes'], 'gosta de café');
    expect(find.text('LISTA CLIENTES'), findsOneWidget);
  });

  testWidgets('cadastro completo: CEP preenche endereço e tudo vai no POST',
      (tester) async {
    _tall(tester);
    adapter.onPost('/clients', (s) => s.reply(201, {'id': 'novo'}),
        data: Matchers.any);
    final cep = CepService(
        lookupOverride: (c) async => c == '17012000'
            ? const CepAddress(
                street: 'Rua Batista de Carvalho',
                district: 'Centro',
                city: 'Bauru',
                state: 'SP')
            : null);

    final router = GoRouter(initialLocation: '/clients/new', routes: [
      GoRoute(
          path: '/clients/new',
          builder: (_, __) => ClientFormPage(api: api, cepService: cep)),
      GoRoute(
          path: '/clients',
          builder: (_, __) => const Scaffold(body: Text('LISTA CLIENTES'))),
    ]);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'), 'Eduardo Mello');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '14999990005');
    await tester.enterText(find.byKey(const Key('client-nickname')), 'Dudu');
    await tester.enterText(
        find.byKey(const Key('client-cpf')), '529.982.247-25');

    // CEP com 8 dígitos busca e preenche rua/bairro/cidade/UF
    await tester.ensureVisible(find.byKey(const Key('client-zip')));
    await tester.enterText(find.byKey(const Key('client-zip')), '17012-000');
    await tester.pumpAndSettle();
    expect(find.text('Rua Batista de Carvalho'), findsOneWidget);
    expect(find.text('Bauru'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('client-number')), '100');

    // como conheceu + consentimento
    await tester.ensureVisible(find.byKey(const Key('client-referral')));
    await tester.tap(find.byKey(const Key('client-referral')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indicação').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('client-consent')));
    await tester.tap(find.byKey(const Key('client-consent')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Criar cliente'));
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();

    final body = requests.singleWhere((r) => r.method == 'POST').body as Map;
    expect(body['nickname'], 'Dudu');
    expect(body['cpf'], '52998224725');
    expect(body['referral_source'], 'indicacao');
    expect(body['marketing_consent'], isTrue);
    expect(body['address'], {
      'zip': '17012000',
      'street': 'Rua Batista de Carvalho',
      'number': '100',
      'complement': '',
      'district': 'Centro',
      'city': 'Bauru',
      'state': 'SP',
    });
    expect(find.text('LISTA CLIENTES'), findsOneWidget);
  });

  testWidgets('CPF inválido bloqueia o salvar com mensagem', (tester) async {
    _tall(tester);
    final router = GoRouter(initialLocation: '/clients/new', routes: [
      GoRoute(
          path: '/clients/new', builder: (_, __) => ClientFormPage(api: api)),
    ]);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Zé');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '14999990006');
    await tester.enterText(
        find.byKey(const Key('client-cpf')), '111.111.111-11');
    await tester.ensureVisible(find.text('Criar cliente'));
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('CPF inválido'), findsOneWidget);
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('edição carrega o cadastro completo', (tester) async {
    _tall(tester);
    adapter.onGet(
        '/clients/abc-9',
        (s) => s.reply(200, {
              'id': 'abc-9',
              'name': 'Eduardo',
              'phone_e164': '5514999990005',
              'cpf': '52998224725',
              'nickname': 'Dudu',
              'referral_source': 'instagram',
              'marketing_consent': true,
              'address': {
                'zip': '17012000',
                'street': 'Rua X',
                'number': '10',
                'complement': null,
                'district': 'Centro',
                'city': 'Bauru',
                'state': 'SP',
              },
            }));
    await tester.pumpWidget(_wrap(clientId: 'abc-9', api: api));
    await tester.pumpAndSettle();
    String txt(String k) =>
        tester.widget<TextFormField>(find.byKey(Key(k))).controller!.text;
    expect(txt('client-nickname'), 'Dudu');
    expect(txt('client-cpf'), '529.982.247-25');
    expect(txt('client-zip'), '17012-000');
    expect(txt('client-city'), 'Bauru');
    expect(find.text('Instagram'), findsOneWidget);
  });

  testWidgets(
      'aberto a partir da lista: salvar VOLTA (pop), sem perder o voltar',
      (tester) async {
    _tall(tester);
    adapter.onPost('/clients', (s) => s.reply(201, {'id': 'novo'}),
        data: Matchers.any);
    final router = GoRouter(initialLocation: '/settings', routes: [
      GoRoute(
          path: '/settings',
          builder: (ctx, __) => Scaffold(
              body: TextButton(
                  onPressed: () => ctx.push('/clients/new'),
                  child: const Text('ABRIR FORM')))),
      GoRoute(
          path: '/clients/new', builder: (_, __) => ClientFormPage(api: api)),
      GoRoute(
          path: '/clients',
          builder: (_, __) => const Scaffold(body: Text('LISTA CLIENTES'))),
    ]);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABRIR FORM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Lia');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'WhatsApp *'), '14999990007');
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();
    // voltou pra tela de origem (pilha preservada)
    expect(find.text('ABRIR FORM'), findsOneWidget);
    expect(find.text('LISTA CLIENTES'), findsNothing);
  });

  testWidgets('CEP e CPF só aceitam dígitos/máscara e no tamanho certo',
      (tester) async {
    _tall(tester);
    final router = GoRouter(initialLocation: '/clients/new', routes: [
      GoRoute(
          path: '/clients/new',
          builder: (_, __) => ClientFormPage(
              api: api,
              cepService: CepService(lookupOverride: (_) async => null))),
    ]);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    String txt(String k) =>
        tester.widget<TextFormField>(find.byKey(Key(k))).controller!.text;

    await tester.enterText(
        find.byKey(const Key('client-zip')), '1198888777701310100');
    expect(txt('client-zip'), '11988-887');
    await tester.enterText(
        find.byKey(const Key('client-cpf')), '529982247251234abc');
    expect(txt('client-cpf'), '529.982.247-25');
  });
}
