import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/update/update_service.dart';

void main() {
  group(
      'UpdateInfo.hasUpdate — lógica de versionamento (testa _versionToInt indiretamente)',
      () {
    test('versão padrão 1.0.0 igual → false', () {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '1.0.0',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('remote maior (major 2.0.0 > 1.0.0) → true', () {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '2.0.0',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isTrue);
    });

    test('remote maior (minor 1.3.0 > 1.2.0) → true', () {
      const info = UpdateInfo(
        currentVersion: '1.2.0',
        remoteVersion: '1.3.0',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isTrue);
    });

    test('remote maior (patch 1.2.4 > 1.2.3) → true', () {
      const info = UpdateInfo(
        currentVersion: '1.2.3',
        remoteVersion: '1.2.4',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isTrue);
    });

    test('remote menor (1.9.9 < 2.0.0) → false', () {
      const info = UpdateInfo(
        currentVersion: '2.0.0',
        remoteVersion: '1.9.9',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('versão com partes faltando (1.0 == 1.0.0) → false', () {
      const info = UpdateInfo(
        currentVersion: '1.0',
        remoteVersion: '1.0.0',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('versão com 4 partes ignora a 4ª (1.2.3.4 == 1.2.3) → false', () {
      const info = UpdateInfo(
        currentVersion: '1.2.3',
        remoteVersion: '1.2.3.4',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('versão com letras trata como 0 (1.a.3 == 1.0.3) → true para 1.0.4',
        () {
      const info = UpdateInfo(
        currentVersion: '1.0.3',
        remoteVersion: '1.a.4',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isTrue); // 1.0.4 > 1.0.3
    });

    test('versão vazia é 0 (0.0.0 < 1.0.0) → true', () {
      const info = UpdateInfo(
        currentVersion: '1.0.0',
        remoteVersion: '',
        changelog: '',
        apkUrl: '',
      );
      expect(info.hasUpdate, isFalse); // remote 0.0.0 < current 1.0.0
    });
  });

  group(
      'UpdateService.check — contrato (integração real no teste de integração)',
      () {
    final original = UpdateService.supportsInAppUpdate;
    tearDown(() => UpdateService.supportsInAppUpdate = original);

    test('iOS (sem atualização pelo app): check nem consulta a API', () async {
      UpdateService.supportsInAppUpdate = () => false;
      expect(await UpdateService.check(), isNull);
      expect(UpdateService.lastCheck, isNull);
    });

    test('iOS: Atualizar avisa da loja antes de baixar qualquer coisa',
        () async {
      UpdateService.supportsInAppUpdate = () => false;
      await expectLater(
        UpdateService.downloadAndInstall(const UpdateInfo(
            currentVersion: '1.0.0',
            remoteVersion: '1.5.0',
            changelog: '',
            apkUrl: '/apks/x.apk')),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message',
            'Neste aparelho a atualização é feita pela loja de aplicativos.')),
      );
    });
  });
}
