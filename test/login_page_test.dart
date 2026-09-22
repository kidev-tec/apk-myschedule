import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/features/auth/login_page.dart';

/// Widget tests da LoginPage.
///
/// O AuthController real toca Firebase/GoogleSignIn no constructor, então
/// pra widget test a gente substitui o provider por um controller fake
/// com o mesmo estado (não testamos o Firebase aqui, testamos a UI).
class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial) : super.forTest(initial: initial);
}

Widget _wrap({AuthState? authState}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authState ?? const AuthState())),
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

    expect(find.text('Cria tua conta'), findsOneWidget);
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
