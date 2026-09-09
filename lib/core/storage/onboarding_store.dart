import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Flag persistida de onboarding completo.
/// O router consulta isso pra decidir login → onboarding ou login → agenda.
class OnboardingStore {
  static const _key = 'onboarding_complete';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> isComplete() async {
    try {
      return await _storage.read(key: _key) == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markComplete() async {
    await _storage.write(key: _key, value: 'true');
  }

  static Future<void> reset() async {
    await _storage.delete(key: _key);
  }
}
