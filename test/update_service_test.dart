import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/update/update_service.dart';

/// Tabela de decisão do updater: quando o banner "Atualizar" aparece.
void main() {
  UpdateInfo info(String current, String remote) => UpdateInfo(
        currentVersion: current,
        remoteVersion: remote,
        changelog: '',
        apkUrl: '/apks/x.apk',
      );

  test('remota maior → hasUpdate true', () {
    expect(info('1.0.0', '1.0.1').hasUpdate, isTrue);
    expect(info('1.0.0', '2.0.0').hasUpdate, isTrue);
    expect(info('1.9.9', '2.0.0').hasUpdate, isTrue);
  });

  test('mesma versão → false', () {
    expect(info('1.0.0', '1.0.0').hasUpdate, isFalse);
  });

  test('remota menor (rollback) → false', () {
    expect(info('1.0.1', '1.0.0').hasUpdate, isFalse);
    expect(info('2.0.0', '1.9.9').hasUpdate, isFalse);
  });

  test('versão remota malformada → tratada como 0.0.0 (não atualiza)', () {
    expect(info('1.0.0', 'qualquer').hasUpdate, isFalse);
  });
}
