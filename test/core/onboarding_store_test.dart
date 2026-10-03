import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/storage/onboarding_store.dart';

/// Cobertura de OnboardingStore: read/write/clear da flag persistida.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('sem flag gravada → isComplete false (primeiro boot)', () async {
    expect(await OnboardingStore.isComplete(), isFalse);
  });

  test('flag gravada como true → isComplete true', () async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'true'});

    expect(await OnboardingStore.isComplete(), isTrue);
  });

  test('flag com outro valor → isComplete false', () async {
    FlutterSecureStorage.setMockInitialValues({'onboarding_complete': 'nope'});

    expect(await OnboardingStore.isComplete(), isFalse);
  });

  test('markComplete grava "true" e isComplete passa a ser true', () async {
    await OnboardingStore.markComplete();

    expect(await OnboardingStore.isComplete(), isTrue);
  });

  test('reset apaga a flag e isComplete volta pra false', () async {
    await OnboardingStore.markComplete();
    expect(await OnboardingStore.isComplete(), isTrue);

    await OnboardingStore.reset();

    expect(await OnboardingStore.isComplete(), isFalse);
  });
}
