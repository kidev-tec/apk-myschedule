// Módulo agregador (API 0026): card de tipo da conta e códigos no settings.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/features/settings/account_kind_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;
  final puts = <dynamic>[];
  var reloads = 0;
  String? clipboard;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    puts.clear();
    reloads = 0;
    clipboard = null;
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(
        adapter: adapter, idToken: ({forceRefresh = false}) async => null);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PUT') puts.add(o.data);
      h.next(o);
    }));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  var linksOpened = 0;

  Future<void> pump(WidgetTester tester, Map<String, dynamic> me) async {
    linksOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountKindCard(
          me: me,
          api: api,
          onChanged: () async => reloads++,
          onOpenLinks: () => linksOpened++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const indep = {
    'name': 'Ana Beleza',
    'account_kind': 'independent',
    'pro_code': 'P-ABCD2345',
    'aggregator_code': null,
  };
  const agg = {
    'name': 'Studio Central',
    'account_kind': 'aggregator',
    'pro_code': 'P-ABCD2345',
    'aggregator_code': 'E-WXYZ6789',
  };

  testWidgets('independente vê o código de profissional e copia',
      (tester) async {
    await pump(tester, indep);
    expect(find.text('Seu código de profissional'), findsOneWidget);
    expect(find.text('P-ABCD2345'), findsOneWidget);
    expect(find.text('Código do estabelecimento'), findsNothing);
    expect(find.text('Transformar em estabelecimento'), findsOneWidget);
    await tester.tap(find.byTooltip('Copiar código'));
    await tester.pumpAndSettle();
    expect(clipboard, 'P-ABCD2345');
    expect(find.text('Código P-ABCD2345 copiado'), findsOneWidget);
  });

  testWidgets('estabelecimento vê o código E- e não o P-', (tester) async {
    await pump(tester, agg);
    expect(find.text('Código do estabelecimento'), findsOneWidget);
    expect(find.text('E-WXYZ6789'), findsOneWidget);
    expect(find.text('P-ABCD2345'), findsNothing);
    expect(find.text('Voltar a ser profissional independente'), findsOneWidget);
  });

  testWidgets(
      'transformar em estabelecimento: confirma, chama a API e recarrega',
      (tester) async {
    adapter.onPut(
        '/me/account-kind', (s) => s.reply(200, {'account_kind': 'aggregator'}),
        data: Matchers.any);
    await pump(tester, indep);
    await tester.tap(find.text('Transformar em estabelecimento'));
    await tester.pumpAndSettle();
    expect(find.text('Transformar em estabelecimento?'), findsOneWidget);
    await tester.tap(find.text('Transformar'));
    await tester.pumpAndSettle();
    expect(puts, [
      {'account_kind': 'aggregator'}
    ]);
    expect(reloads, 1);
    expect(
        find.text('Pronto! Agora você é um estabelecimento.'), findsOneWidget);
  });

  testWidgets('cancelar o diálogo não chama a API', (tester) async {
    await pump(tester, indep);
    await tester.tap(find.text('Transformar em estabelecimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(puts, isEmpty);
    expect(reloads, 0);
  });

  testWidgets('voltar a independente com vínculos mostra a mensagem da API',
      (tester) async {
    adapter.onPut(
        '/me/account-kind',
        (s) => s.reply(409, {
              'error':
                  'Você ainda tem profissionais vinculados ou convites pendentes.'
            }),
        data: Matchers.any);
    await pump(tester, agg);
    await tester.tap(find.text('Voltar a ser profissional independente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(puts, [
      {'account_kind': 'independent'}
    ]);
    expect(reloads, 0);
    expect(
        find.text(
            'Você ainda tem profissionais vinculados ou convites pendentes.'),
        findsOneWidget);
  });

  testWidgets('erro sem mensagem cai no texto padrão', (tester) async {
    adapter.onPut('/me/account-kind', (s) => s.reply(500, 'boom'),
        data: Matchers.any);
    await pump(tester, indep);
    await tester.tap(find.text('Transformar em estabelecimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transformar'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível mudar agora. Tente novamente.'),
        findsOneWidget);
  });

  testWidgets('entrada para os vínculos muda o nome conforme o tipo',
      (tester) async {
    await pump(tester, indep);
    expect(find.text('Meus estabelecimentos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-links')));
    expect(linksOpened, 1);
    await pump(tester, agg);
    expect(find.text('Profissionais'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-links')));
    expect(linksOpened, 1);
  });
}
