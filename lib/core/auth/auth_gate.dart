import 'package:firebase_auth/firebase_auth.dart';

/// Tela de espera enquanto o Firebase diz se há sessão salva.
const splashRoute = '/splash';

/// Marca de [authGate]: logado na entrada → decidir onboarding ou agenda.
const resolveOnboarding = '__resolve_onboarding__';

/// Para onde ir, conforme a sessão. `null` = fica onde está.
String? authGate({
  required bool isResolving,
  required bool isAuthenticated,
  required String location,
}) {
  final isEntry = location == '/login' || location == splashRoute;
  if (isResolving) return location == splashRoute ? null : splashRoute;
  if (!isAuthenticated) {
    return location == '/login' || location == '/onboarding' ? null : '/login';
  }
  return isEntry ? resolveOnboarding : null;
}

/// O erro ao renovar o token significa que a sessão acabou de verdade?
/// Falha de rede ou demora NÃO desloga: o usuário segue no app e o token é
/// renovado na próxima chamada à API.
bool sessionEnded(Object error) =>
    error is FirebaseAuthException &&
    const {
      'user-disabled',
      'user-not-found',
      'user-token-expired',
      'invalid-user-token',
    }.contains(error.code);
