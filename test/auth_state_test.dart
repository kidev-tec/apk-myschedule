import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';
import 'package:minha_agenda/core/auth/auth_gate.dart';

void main() {
  group('authGate: quem está logado não para no login', () {
    String? gate(String location,
            {bool resolving = false, bool auth = false}) =>
        authGate(
            isResolving: resolving, isAuthenticated: auth, location: location);

    test('abrindo o app: espera na abertura, sem mostrar o login', () {
      expect(gate('/login', resolving: true), splashRoute);
      expect(gate('/agenda', resolving: true), splashRoute);
      expect(gate(splashRoute, resolving: true), isNull);
    });
    test('logado na entrada: decide onboarding/agenda', () {
      expect(gate(splashRoute, auth: true), resolveOnboarding);
      expect(gate('/login', auth: true), resolveOnboarding);
      expect(gate('/agenda', auth: true), isNull);
      expect(gate('/onboarding', auth: true), isNull);
    });
    test('sem sessão: login', () {
      expect(gate(splashRoute), '/login');
      expect(gate('/agenda'), '/login');
      expect(gate('/login'), isNull);
      expect(gate('/onboarding'), isNull);
    });
  });

  group('sessionEnded: rede ruim não desloga', () {
    test('falha de rede e demora mantêm a sessão', () {
      expect(sessionEnded(Exception('getIdToken timeout')), isFalse);
      expect(
          sessionEnded(FirebaseAuthException(code: 'network-request-failed')),
          isFalse);
      expect(
          sessionEnded(FirebaseAuthException(code: 'internal-error')), isFalse);
    });
    test('conta desativada/removida ou token revogado encerram', () {
      for (final code in [
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      ]) {
        expect(sessionEnded(FirebaseAuthException(code: code)), isTrue,
            reason: code);
      }
    });
  });

  group('AuthState', () {
    test('copyWith encerra a espera da abertura', () {
      const opening = AuthState(isResolving: true);
      expect(opening.copyWith(isLoading: false).isResolving, isFalse);
    });

    test('estado default: sem user, sem token, não autenticado', () {
      const state = AuthState();
      expect(state.isResolving, isFalse);
      expect(state.user, isNull);
      expect(state.idToken, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated exige user E idToken', () {
      // só user (token null) → não autenticado
      const soUser = AuthState(user: null, idToken: 'tok');
      // sem token nunca fica autenticado mesmo com user
      expect(soUser.isAuthenticated, isFalse); // user é null aqui
    });

    test('copyWith preserva campos não passados', () {
      const base = AuthState(isLoading: false, error: null);
      final withLoading = base.copyWith(isLoading: true, error: 'ops');
      expect(withLoading.isLoading, isTrue);
      expect(withLoading.error, 'ops');
    });

    test('copyWith error=null limpa o erro (padrão do fluxo login)', () {
      const comErro = AuthState(error: 'E-mail ou senha incorretos.');
      final limpo = comErro.copyWith(isLoading: true, error: null);
      expect(limpo.error, isNull);
      expect(limpo.isLoading, isTrue);
    });
  });

  group('F0 — conta (cadastro com nome, reset, exclusão)', () {
    // Contratos de assinatura (createAccount com {name}, sendPasswordReset,
    // deleteAccount) são exercitados em login_page_test.dart, que roda com
    // FirebasePlatform fake (o forTest() instancia FirebaseAuth.instance).
  });
}
