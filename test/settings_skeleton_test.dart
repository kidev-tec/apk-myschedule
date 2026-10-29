// B2: Configurações abre lenta/parcial — skeleton único + erro com retry.
// Mesma técnica do settings_subscription_test (DioAdapter global + Firebase fake).

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
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

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super.forTest();
}

/// Adapter que nunca responde — mantém /me pendente para sempre.
class _StalledAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      Completer<ResponseBody>().future;
}

/// Adapter programável: fila de [status, body]; esgota → última resposta repete.
/// (O DioAdapter do http_mock_adapter mostrou-se não determinístico p/ respostas
/// distintas na mesma rota; aqui a fila é avaliada em cada fetch real.)
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);
  final List<MapEntry<int, String>> script;
  var _i = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final entry = script[_i < script.length ? _i++ : script.length - 1];
    return ResponseBody.fromString(entry.value, entry.key, headers: {
      'content-type': ['application/json'],
    });
  }
}

Widget _wrap(ApiClient api) {
  final router = GoRouter(initialLocation: '/settings', routes: [
    GoRoute(path: '/settings', builder: (_, __) => SettingsPage(api: api)),
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

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('B2: /me pendente → skeleton, sem cards de negócio em cascata',
      (tester) async {
    // Adapter travado: /me nunca responde; Dio estoura receiveTimeout (15s).
    final stalled = ApiClient(adapter: _StalledAdapter());

    await tester.pumpWidget(_wrap(stalled));
    await tester.pump(); // um frame: initState disparou _loadMe (pendente)

    // nenhum card de negócio ainda
    expect(find.text('Meus serviços'), findsNothing);
    expect(find.text('Google Calendar'), findsNothing);
    expect(find.text('Segmento'), findsNothing);
    expect(find.text('Teu link de agendamento'), findsNothing);
    // skeleton presente (Key de teste no placeholder)
    expect(find.byKey(const Key('settings-skeleton')), findsWidgets);

    // deixa o timeout do Dio (15s) estourar para o teste fechar sem timer pendente
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
  });

  testWidgets('B2: /me falha → mensagem + Tentar de novo; retry recupera',
      (tester) async {
    // Configurações é uma lista longa: tela alta pra todos os cards montarem
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Script: 1ª chamada 500, 2ª (retry) 200 com /me válido.
    final scripted = ApiClient(
      // ignore: unused_local_variable — script define respostas em fila
      adapter: _ScriptedAdapter(const [
        MapEntry(500, '{"error":"boom"}'),
        MapEntry(
            200,
            '{"name":"Studio Teste","business_type":"beauty",'
            '"subscription_status":"active","trial_ends_at":null,'
            '"email":"x@t.com"}'),
      ]),
    );

    await tester.pumpWidget(_wrap(scripted));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não consegui carregar'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    // recuperou: cards de negócio presentes
    expect(find.textContaining('Não consegui carregar'), findsNothing);
    expect(find.text('Meus serviços'), findsOneWidget);
    expect(find.text('Segmento'), findsOneWidget);
    expect(find.text('Tema e identidade visual'), findsOneWidget);
  });
}
