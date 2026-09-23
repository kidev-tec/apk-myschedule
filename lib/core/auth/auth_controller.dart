import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api/api_client.dart';

class AuthState {
  final User? user;
  final String? idToken;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.idToken,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith(
      {User? user, String? idToken, bool? isLoading, String? error}) {
    return AuthState(
      user: user ?? this.user,
      idToken: idToken ?? this.idToken,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get isAuthenticated => user != null && idToken != null;
}

class AuthController extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ApiClient _api = ApiClient();

  /// Construtor pra testes: pula o listener de authStateChanges (que toca
  /// Firebase nativo — impossível em testes unit/widget). Estado inicial
  /// injetado. Só expõe o state, métodos reais não são chamados nos tests.
  AuthController.forTest({AuthState? initial})
      : super(initial ?? const AuthState());

  AuthController() : super(const AuthState()) {
    _initAuthListener();
  }

  void _initAuthListener() {
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        try {
          // getIdToken() usa cache se estiver fresco — getIdToken(true)
          // força refresh na rede e pendura o state se a rede oscilar.
          final token = await user.getIdToken().timeout(
                    const Duration(seconds: 20),
                    onTimeout: () => throw Exception('getIdToken timeout'),
                  ) ??
              '';
          await _api.storeTokens(token, ''); // refresh handled by Firebase
          state = state.copyWith(user: user, idToken: token, isLoading: false);
        } catch (e) {
          // Token falhou: zera o loading e volta pro login com erro claro
          // (não deixa o botão pendurado em loading eterno).
          state = state.copyWith(
            isLoading: false,
            error:
                'Falha de rede ao validar sessão. Verifica o Wi-Fi e tenta de novo.',
          );
          await _auth.signOut();
        }
      } else {
        await _api.clearTokens();
        state = const AuthState();
      }
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e.code));
      rethrow;
    }
  }

  Future<void> createAccount(String email, String password,
      {String? name}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      // nome do prestador: seta no Firebase (o /auth/sync repassa pro
      // Postgres via authUser.name) e no perfil local na mesma hora.
      if (name != null && name.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(name.trim());
        await cred.user?.reload();
      }
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e.code));
      rethrow;
    }
  }

  /// Envia e-mail de redefinição de senha (Firebase cuida do fluxo todo).
  Future<void> sendPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e.code));
      rethrow;
    }
  }

  /// Exclui a conta: dados no Postgres (DELETE /auth/account) + registro
  /// no Firebase. Requer re-autenticação recente do Firebase — se o token
  /// estiver velho o servidor mantém Postgres limpo e o Firebase pode
  /// falhar; nesse caso o usuário sai com conta órfã inutilizável.
  Future<void> deleteAccount() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      try {
        await _api.dio.delete('/auth/account');
      } catch (_) {
        // se o Postgres falhar, não exclui o auth (evita órfão invertido)
        state = state.copyWith(
          isLoading: false,
          error:
              'Não deu pra excluir agora. Verifica a internet e tenta de novo.',
        );
        return;
      }
      await _auth.currentUser?.delete();
      state = const AuthState();
    } on FirebaseAuthException catch (e) {
      // requires-recent-login: pede login de novo e retry (fluxo do app
      // orienta: sair e entrar antes de excluir)
      state = state.copyWith(
        isLoading: false,
        error: e.code == 'requires-recent-login'
            ? 'Por segurança, sai da conta e entra de novo antes de excluir.'
            : _friendlyError(e.code),
      );
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        state = state.copyWith(isLoading: false);
        return; // user cancelled
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Falha no login com Google. Tenta de novo.');
      rethrow;
    }
  }

  Future<void> syncWithBackend() async {
    if (state.idToken == null) return;
    try {
      await _api.dio.post('/auth/sync', data: {'id_token': state.idToken});
    } catch (e) {
      // NÃO silencioso: se o sync falha, o user não existe no Postgres e
      // /me responde 404. O onboarding recupera disso (ensureProvisioned),
      // mas o log é essencial pra diagnosticar (bug mmmarckos 22/09: sync
      // falhava sem vestígio e a conta ficava fantasma no Firebase).
      debugPrint('[auth] /auth/sync falhou: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'weak-password':
        return 'Senha muito curta. Mínimo 8 caracteres.';
      case 'email-already-in-use':
        return 'Este e-mail já tem conta. Faz login ou recupera a senha.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      case 'network-request-failed':
        return 'Sem internet. Verifica a conexão.';
      default:
        return 'Erro ao acessar a conta. Tenta de novo.';
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});
