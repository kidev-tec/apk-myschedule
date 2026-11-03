import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// E-mail e senha salvos no aparelho.
class SavedLogin {
  const SavedLogin(this.email, this.password);
  final String email;
  final String password;
}

/// "Salvar senha neste aparelho" do login manual. Só com o aceite do usuário
/// e no armazenamento criptografado do sistema (Keystore/Keychain).
/// Sair da conta mantém (é o que preenche o próximo login); desmarcar, senha
/// recusada e excluir a conta apagam. Falha de leitura/escrita nunca
/// atrapalha o login.
class SavedCredentials {
  static const _storage = FlutterSecureStorage();
  static const _emailKey = 'saved_login_email';
  static const _passwordKey = 'saved_login_password';

  static Future<SavedLogin?> load() async {
    try {
      final email = await _storage.read(key: _emailKey);
      final password = await _storage.read(key: _passwordKey);
      if (email == null || password == null) return null;
      return SavedLogin(email, password);
    } catch (e) {
      debugPrint('[login] senha salva indisponível: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> save(String email, String password) async {
    try {
      await _storage.write(key: _emailKey, value: email);
      await _storage.write(key: _passwordKey, value: password);
    } catch (e) {
      debugPrint('[login] não salvou a senha: ${e.runtimeType}');
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _passwordKey);
    } catch (e) {
      debugPrint('[login] não apagou a senha: ${e.runtimeType}');
    }
  }
}
