// Fase C (Asaas): card Assinatura no settings — estados + checkout.
// A página usa ApiClient() direto; os testes mockam o adapter global do Dio
// via mesma técnica do client_form (injeção não existe aqui, então mockamos
// o HttpClientAdapter default com DioAdapter e interceptores capturam paths).

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/features/settings/settings_page.dart';

/// Firebase mockado (padrão do login_page_test): o AuthController toca
/// FirebaseAuth.instance no construtor, e o settings lê authControllerProvider.
class _FakeFirebasePlatform extends FirebasePlatform {
  final Map<String, FirebaseAppPlatform> _apps = {};

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final n = name ?? defaultFirebaseAppName;
    _apps[n] ??= FirebaseAppPlatform(
        n,
        options ??
            const FirebaseOptions(
              apiKey: 'test',
              appId: 'test',
              messagingSenderId: 'test',
              projectId: 'test',
            ));
    return _apps[n]!;
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _apps[name]!;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super.forTest();
}

/// Captura launch() em vez de abrir browser real.
class _FakeLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

Widget _wrap(ApiClient api) {
  final router = GoRouter(initialLocation: '/settings', routes: [
    GoRoute(path: '/settings', builder: (_, __) => SettingsPage(api: api)),
    GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
  ]);
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  late DioAdapter adapter;
  late ApiClient api;
  late _FakeLauncher launcher;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;

    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(adapter: adapter);

    adapter.onGet(
        '/me',
        (s) => s.reply(200, {
              'name': 'Studio Teste',
              'business_type': 'beauty',
              'subscription_status': 'trial',
              'trial_ends_at':
                  DateTime.now().add(const Duration(days: 7)).toIso8601String(),
              'email': 'x@t.com',
            }));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
  }

  testWidgets('trial: mostra dias restantes e botão Assinar agora',
      (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('dias restantes'), findsOneWidget);
    expect(find.text('Assinar agora'), findsOneWidget);
  });

  testWidgets('active: sem botão de assinar', (tester) async {
    adapter.onGet(
        '/me',
        (s) => s.reply(200, {
              'name': 'Studio Teste',
              'subscription_status': 'active',
              'trial_ends_at': null,
              'email': 'x@t.com',
            }));
    await pumpPage(tester);
    expect(find.text('Assinatura ativa'), findsOneWidget);
    expect(find.text('Assinar agora'), findsNothing);
  });

  testWidgets('past_due: copy de pagamento pendente + botão', (tester) async {
    adapter.onGet(
        '/me',
        (s) => s.reply(200, {
              'name': 'Studio Teste',
              'subscription_status': 'past_due',
              'trial_ends_at': null,
              'email': 'x@t.com',
            }));
    await pumpPage(tester);
    expect(find.text('Pagamento pendente'), findsOneWidget);
    expect(find.text('Confere no teu e-mail'), findsOneWidget);
    expect(find.text('Assinar agora'), findsOneWidget);
  });

  testWidgets('checkout: POST + abre invoiceUrl no browser', (tester) async {
    adapter.onPost('/billing/checkout',
        (s) => s.reply(201, {'invoiceUrl': 'https://pay.asaas.com/x'}),
        data: Matchers.any);

    await pumpPage(tester);
    await tester.tap(find.text('Assinar agora'));
    await tester.pumpAndSettle();

    // dialog de CPF
    expect(find.text('Seu CPF'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'CPF (só números)'), '20447670824');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(launcher.launched, ['https://pay.asaas.com/x']);
    // snackbar com ação de atualizar
    expect(find.text('Já paguei — atualizar'), findsOneWidget);
  });

  testWidgets('checkout 503: SnackBar humano, sem crash', (tester) async {
    adapter.onPost('/billing/checkout',
        (s) => s.reply(503, {'error': 'Cobrança indisponível no momento'}),
        data: Matchers.any);

    await pumpPage(tester);
    await tester.tap(find.text('Assinar agora'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'CPF (só números)'), '20447670824');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(launcher.launched, isEmpty);
    expect(find.text('Cobrança indisponível no momento'), findsOneWidget);
  });

  testWidgets('CPF com menos de 11 dígitos → SnackBar, sem chamar API',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Assinar agora'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'CPF (só números)'), '123');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(launcher.launched, isEmpty);
    expect(find.text('CPF precisa ter 11 números'), findsOneWidget);
  });
}
