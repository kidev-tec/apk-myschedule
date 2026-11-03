import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/core/auth/saved_credentials.dart';
import 'package:minha_agenda/features/auth/login_page.dart';

/// Widget tests da LoginPage.
///
/// O AuthController real toca Firebase/GoogleSignIn no constructor, então
/// pra widget test a gente substitui o provider por um controller fake
/// com o mesmo estado (não testamos o Firebase aqui, testamos a UI).
class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial, {this.signInError})
      : super.forTest(initial: initial);

  final Object? signInError;
  final signIns = <String>[];

  @override
  Future<void> signInWithGoogle() async {
    state =
        state.copyWith(error: 'Falha no login com Google. Tente novamente.');
    throw Exception('ApiException: 10');
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    signIns.add('$email|$password');
    if (signInError != null) throw signInError!;
  }
}

Widget _wrap({AuthState? authState, _FakeAuthController? controller}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) =>
          controller ?? _FakeAuthController(authState ?? const AuthState())),
    ],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  // Firebase mockado — o widget nunca chama métodos reais, mas
  // FirebaseAuth.instance no _FakeAuthController precisa de um app DEFAULT.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('falha no Google: mostra a mensagem, sem erro sem tratamento',
      (tester) async {
    // a tela usa GoRouter.of no login com Google
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider
            .overrideWith((ref) => _FakeAuthController(const AuthState())),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const LoginPage()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar com Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar com Google'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Falha no login com Google. Tente novamente.'),
        findsOneWidget);
  });

  group('salvar senha', () {
    Future<void> login(WidgetTester tester, {bool tick = false}) async {
      await tester.enterText(
          find.widgetWithText(TextField, 'E-mail'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Senha'), 'segredo123');
      if (tick) {
        await tester.ensureVisible(find.byKey(const Key('remember-password')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('remember-password')));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
    }

    testWidgets('marcado: salva; reabrir preenche, sem o olho', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Salvar senha neste aparelho'), findsOneWidget);
      await login(tester, tick: true);
      final saved = await SavedCredentials.load();
      expect(saved?.email, 'a@b.com');
      expect(saved?.password, 'segredo123');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('a@b.com'), findsOneWidget);
      expect(find.text('segredo123'), findsOneWidget);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(const Key('remember-password')))
              .value,
          isTrue);
      expect(find.byKey(const Key('toggle-password')), findsNothing);

      // editar não libera o olho: a senha salva ainda poderia estar no campo
      await tester.enterText(
          find.widgetWithText(TextField, 'Senha'), 'segredo1234');
      await tester.pump();
      expect(find.byKey(const Key('toggle-password')), findsNothing);

      // só depois de apagar tudo o olho volta, com o campo oculto
      await tester.enterText(find.widgetWithText(TextField, 'Senha'), '');
      await tester.pump();
      expect(find.byKey(const Key('toggle-password')), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Senha'), 'nova12345');
      await tester.pump();
      expect(find.byKey(const Key('toggle-password')), findsOneWidget);
    });

    testWidgets('sem marcar não salva; e entrar desmarcado apaga',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await login(tester);
      expect(await SavedCredentials.load(), isNull);
    });

    testWidgets('desmarcar apaga na hora', (tester) async {
      await SavedCredentials.save('a@b.com', 'segredo123');
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('remember-password')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remember-password')));
      await tester.pumpAndSettle();
      expect(await SavedCredentials.load(), isNull);
    });

    testWidgets('senha salva recusada: apaga e limpa o campo', (tester) async {
      await SavedCredentials.save('a@b.com', 'velha12345');
      final c = _FakeAuthController(const AuthState(),
          signInError: FirebaseAuthException(code: 'invalid-credential'));
      await tester.pumpWidget(_wrap(controller: c));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(c.signIns, ['a@b.com|velha12345']);
      expect(await SavedCredentials.load(), isNull);
      expect(find.text('velha12345'), findsNothing);
      expect(find.text('a@b.com'), findsOneWidget);
    });

    testWidgets('senha editada e recusada: mantém a salva', (tester) async {
      await SavedCredentials.save('a@b.com', 'segredo123');
      final c = _FakeAuthController(const AuthState(),
          signInError: FirebaseAuthException(code: 'invalid-credential'));
      await tester.pumpWidget(_wrap(controller: c));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Senha'), 'digitei-errado');
      await tester.ensureVisible(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect((await SavedCredentials.load())?.password, 'segredo123');
    });

    testWidgets('falha de rede não apaga a senha salva', (tester) async {
      await SavedCredentials.save('a@b.com', 'segredo123');
      final c = _FakeAuthController(const AuthState(),
          signInError: FirebaseAuthException(code: 'network-request-failed'));
      await tester.pumpWidget(_wrap(controller: c));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect((await SavedCredentials.load())?.password, 'segredo123');
    });

    testWidgets('criar conta não mostra a opção', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Criar conta').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar conta').last);
      await tester.pump();
      expect(find.byKey(const Key('remember-password')), findsNothing);
    });
  });

  testWidgets('renderiza título, campos e botões', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('AGENVA'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Continuar com Google'), findsOneWidget);
  });

  testWidgets('email vazio → SnackBar "E-mail inválido"', (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.tap(find.text('Entrar'));
    await tester.pump(); // snackbar animando

    expect(find.text('E-mail inválido'), findsOneWidget);
  });

  testWidgets('email sem @ → SnackBar "E-mail inválido"', (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'), 'sem-arroba');
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('E-mail inválido'), findsOneWidget);
  });

  testWidgets('senha curta → SnackBar pedindo 8 caracteres', (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.enterText(find.widgetWithText(TextField, 'E-mail'), 'a@b.com');
    await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'curta12');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Senha deve ter pelo menos 8 caracteres'), findsOneWidget);
  });

  testWidgets('toggle login ↔ criar conta muda copy da tela', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    await tester.ensureVisible(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();

    expect(find.text('Crie sua conta'), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsNothing);
    // botão principal vira "Criar conta" e o toggle vira "Entrar"
    expect(find.text('Criar conta'), findsOneWidget);
    expect(
        find.text('Entrar'), findsOneWidget); // só o toggle (botão virou criar)
  });

  testWidgets('auth.error do provider aparece na tela', (tester) async {
    await tester.pumpWidget(_wrap(
      authState: const AuthState(error: 'E-mail ou senha incorretos.'),
    ));

    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
  });

  testWidgets('isLoading mostra spinner e desabilita botão', (tester) async {
    await tester.pumpWidget(_wrap(
      authState: const AuthState(isLoading: true),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // botão desabilitado: FilledButton com onPressed null (texto virou spinner)
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('toggle olho muda obscureText da senha', (tester) async {
    await tester.pumpWidget(_wrap());

    final senhaField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Senha'));
    expect(senhaField.obscureText, isTrue);

    // toca no ícone do olho (suffixIcon)
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    final depois =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Senha'));
    expect(depois.obscureText, isFalse);
  });

  testWidgets('F0: modo cadastro mostra campo "Seu nome" (login não mostra)',
      (tester) async {
    await tester.pumpWidget(_wrap());
    // toggle pra criar conta
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Criar conta'));
    await tester.tap(find.widgetWithText(TextButton, 'Criar conta'),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Seu nome'), findsOneWidget);
  });

  testWidgets('F0: modo login mostra link "Esqueci minha senha"',
      (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('Esqueci minha senha'), findsOneWidget);
  });

  testWidgets('F0: esqueci senha abre view dedicada de recuperação',
      (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.ensureVisible(find.text('Esqueci minha senha'));
    await tester.tap(find.text('Esqueci minha senha'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // view dedicada com copy empática e campo próprio
    expect(find.text('Recuperar senha'), findsOneWidget);
    expect(find.text('E-mail de cadastro'), findsOneWidget);
    expect(find.text('Enviar link de recuperação'), findsOneWidget);
  });
}

/// Platform Firebase mínima: só registra o app DEFAULT. Qualquer chamada
/// de método real retorna vazio — suficiente pra instanciar o controller.
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

// ---- F0: campo nome no cadastro + esqueci minha senha ----

void main2() {}
