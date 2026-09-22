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
    adapter.onGet(
        '/clients/abc-123',
        (s) => s.reply(200, {
              'id': 'abc-123',
              'name': 'Ana',
              'phone_e164': '+5514999990001',
              'email': 'ana@x.com',
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
    expect(requests.where((r) => r.method == 'POST'), isEmpty);

    // volta pra lista
    expect(find.text('LISTA CLIENTES'), findsOneWidget);
  });

  testWidgets('modo criação continua com POST', (tester) async {
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
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();

    final post = requests.where((r) => r.method == 'POST').toList();
    expect(post, hasLength(1));
    expect(post.single.path, '/clients');
    expect(find.text('LISTA CLIENTES'), findsOneWidget);
  });
}
