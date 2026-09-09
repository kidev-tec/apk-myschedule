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

  Future<void> createAccount(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e.code));
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
    } catch (_) {
      // silencioso — backend sync é idempotente; retry na próxima abertura
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
