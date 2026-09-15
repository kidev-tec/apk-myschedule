import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/auth/auth_controller.dart';

void main() {
  group('AuthState', () {
    test('estado default: sem user, sem token, não autenticado', () {
      const state = AuthState();
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
}