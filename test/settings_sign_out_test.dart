// Sair da conta: desvincula o aparelho antes e termina mesmo se a tela de
// Configurações fechar durante a desvinculação (revisão da PR #76).

import 'dart:async';

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

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/features/settings/device_token_service.dart';
import 'package:minha_agenda/features/settings/push_init_service.dart';
import 'package:minha_agenda/features/settings/settings_page.dart';

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

class _FakeAuth extends AuthController {
  _FakeAuth() : super.forTest();
  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('tela fechada durante a desvinculação: a saída termina',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet(
        '/me',
        (s) => s.reply(200, {
              'name': 'Studio',
              'business_type': 'beauty',
              'subscription_status': 'active',
              'email': 'x@t.com',
            }));
    final token = Completer<String?>();
    final push = PushInitService(
        tokens: DeviceTokenService(dio: dio), readToken: () => token.future);
    final auth = _FakeAuth();
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('INICIO')),
          routes: [
            GoRoute(
                path: 'settings',
                builder: (_, __) =>
                    SettingsPage(api: ApiClient(adapter: adapter), push: push)),
          ]),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
      ),
    ));
    router.push('/settings');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
    await tester.pump();
    expect(auth.signOuts, 0); // ainda desvinculando

    // a pessoa volta enquanto a desvinculação está no ar: a tela é descartada
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);

    token.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(auth.signOuts, 1);
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
