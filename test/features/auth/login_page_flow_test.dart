import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/features/auth/login_page.dart';

/// Cobertura dos fluxos de SUBMIT da LoginPage (gaps de linha):
/// login OK/erro de rede, criar conta, Google sign-in, sync e navegação
/// condicionada à flag de onboarding (login → /agenda ou /onboarding).
///
/// O AuthController real toca Firebase/GoogleSignIn — a gente sobrescreve o
/// provider com um fake com o MESMO contrato (forTest) que grava o que foi
/// chamado e controla se autentica. O roteamento é GoRouter mínimo com
/// páginas dummy, igual ao padrão do booking_wizard_integration_test.

class _FakeAuthUser implements User {
  @override
  String get uid => 'uid-teste';
  @override
  String? get email => 'rafa@oficina.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(
    AuthState initial, {
    this.onSignIn,
    this.onCreate,
    this.onGoogle,
  }) : super.forTest(initial: initial);

  final Future<void> Function(String email, String password)? onSignIn;
  final Future<void> Function(String email, String password)? onCreate;
  final Future<void> Function()? onGoogle;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await onSignIn?.call(email, password);
  }

  @override
  Future<void> createAccount(String email, String password) async {
    await onCreate?.call(email, password);
  }

  @override
  Future<void> signInWithGoogle() async {
    await onGoogle?.call();
  }

  @override
  Future<void> syncWithBackend() async {}
}

Widget _wrap({
  AuthState? authState,
  Future<void> Function(String, String)? onSignIn,
  Future<void> Function(String, String)? onCreate,
  Future<void> Function()? onGoogle,
}) {
  final router = GoRouter(initialLocation: '/login', routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('PAGINA AGENDA'))),
    GoRoute(
        path: '/onboarding',
        builder: (_, __) => const Scaffold(body: Text('PAGINA ONBOARDING'))),
  ]);
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(
            authState ?? const AuthState(),
            onSignIn: onSignIn,
            onCreate: onCreate,
            onGoogle: onGoogle,
          )),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'), 'rafa@oficina.com');
  await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'senha1234');
  await tester.ensureVisible(find.text('Entrar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Entrar'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  testWidgets('submit OK + onboarding completo → sync e vai pra /agenda',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'true'});
    final chamados = <String>[];

    await tester.pumpWidget(_wrap(
      authState: AuthState(user: _FakeAuthUser(), idToken: 'tok'),
      onSignIn: (e, p) async => chamados.add('signIn:$e'),
    ));

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(chamados, ['signIn:rafa@oficina.com']);
    expect(find.text('PAGINA AGENDA'), findsOneWidget);
  });

  testWidgets('submit OK + onboarding pendente → vai pra /onboarding',
      (tester) async {
    // sem flag no storage → isComplete false
    await tester.pumpWidget(_wrap(
      authState: AuthState(user: _FakeAuthUser(), idToken: 'tok'),
    ));

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('PAGINA ONBOARDING'), findsOneWidget);
    expect(find.text('PAGINA AGENDA'), findsNothing);
  });

  testWidgets('submit em modo "criar conta" chama createAccount e navega',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'true'});
    final criadas = <String>[];

    await tester.pumpWidget(_wrap(
      authState: AuthState(user: _FakeAuthUser(), idToken: 'tok'),
      onCreate: (e, p) async => criadas.add(e),
    ));
    // alterna pra modo criar conta
    await tester.ensureVisible(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'), 'novo@user.com');
    await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'senha1234');
    await tester.ensureVisible(find.text('Criar conta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta').first);
    await tester.pumpAndSettle();

    expect(criadas, ['novo@user.com']);
    expect(find.text('PAGINA AGENDA'), findsOneWidget);
  });

  testWidgets('signIn lança (Firebase down) → fica na tela, sem crash',
      (tester) async {
    await tester.pumpWidget(_wrap(
      onSignIn: (e, p) async => throw Exception('network'),
    ));

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    // continua na login page
    expect(find.text('Minha Agenda'), findsOneWidget);
    expect(find.text('PAGINA AGENDA'), findsNothing);
  });

  testWidgets('autenticou sem idToken → não navega (isAuthenticated false)',
      (tester) async {
    // Fake controller autentica mas o estado não tem idToken
    await tester.pumpWidget(_wrap(
      authState: const AuthState(), // user null e idToken null
    ));

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Minha Agenda'), findsOneWidget);
    expect(find.text('PAGINA AGENDA'), findsNothing);
    expect(find.text('PAGINA ONBOARDING'), findsNothing);
  });

  testWidgets('Google sign-in autenticado + onboarding completo → /agenda',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'true'});
    final googleChamado = <bool>[];

    await tester.pumpWidget(_wrap(
      authState: AuthState(user: _FakeAuthUser(), idToken: 'tok'),
      onGoogle: () async => googleChamado.add(true),
    ));

    await tester.ensureVisible(find.text('Continuar com Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar com Google'));
    await tester.pumpAndSettle();

    expect(googleChamado, [true]);
    expect(find.text('PAGINA AGENDA'), findsOneWidget);
  });

  testWidgets('Google sign-in cancelado (não autenticou) → fica na tela',
      (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.ensureVisible(find.text('Continuar com Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar com Google'));
    await tester.pumpAndSettle();

    expect(find.text('Minha Agenda'), findsOneWidget);
    expect(find.text('PAGINA AGENDA'), findsNothing);
  });

  testWidgets('submit via keyboard (onSubmitted do campo senha)', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'true'});
    final chamados = <String>[];

    await tester.pumpWidget(_wrap(
      authState: AuthState(user: _FakeAuthUser(), idToken: 'tok'),
      onSignIn: (e, p) async => chamados.add('signIn:$e'),
    ));

    await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'), 'rafa@oficina.com');
    await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'senha1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(chamados, ['signIn:rafa@oficina.com']);
    expect(find.text('PAGINA AGENDA'), findsOneWidget);
  });

  test('const constructor da LoginPage é utilizável sem key', () {
    const LoginPage(); // linha da classe/construtor const
  });

  testWidgets('loading desabilita também o botão do Google', (tester) async {
    await tester.pumpWidget(_wrap(
      authState: const AuthState(isLoading: true),
    ));

    final google = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Continuar com Google'));
    expect(google.onPressed, isNull);
  });
}

/// Platform Firebase mínima — igual ao login_page_test.dart.
class _FakeFirebasePlatform extends FirebasePlatform {
  final Map<String, FirebaseAppPlatform> _apps = {};

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final n = name ?? defaultFirebaseAppName;
    if (!_apps.containsKey(n)) {
      _apps[n] = FirebaseAppPlatform(
          n,
          options ??
              const FirebaseOptions(
                apiKey: 'test',
                appId: 'test',
                messagingSenderId: 'test',
                projectId: 'test',
              ));
    }
    return _apps[n]!;
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final a = _apps[name];
    if (a == null) throw StateError('No Firebase App $name');
    return a;
  }

  @override
  List<FirebaseAppPlatform> get apps => _apps.values.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
