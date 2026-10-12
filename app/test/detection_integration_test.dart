@Tags(<String>['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/localizer_service.dart';
import 'package:vmware_localizer/src/core/models.dart';
import 'package:vmware_localizer/src/core/patch_table.dart';

void main() {
  test('detects the localisation state of the real installation', () async {
    final LocalizerService service = LocalizerService();
    final InstallationReport r = await service.detect();

    // ignore: avoid_print
    print('state          : ${r.state}');
    // ignore: avoid_print
    print('install path   : ${r.install?.installPath}');
    // ignore: avoid_print
    print('vmware version : ${r.install?.version}');
    // ignore: avoid_print
    print('product version: ${r.install?.productVersion}');
    // ignore: avoid_print
    print('dll sha256     : ${r.baseDllHash}');
    // ignore: avoid_print
    print('zh_CN present  : ${r.zhCnPresent}');
    // ignore: avoid_print
    print('zh_CN matching : ${r.zhCnMatching}');
    // ignore: avoid_print
    print('vmware running : ${r.vmwareRunning}');
    // ignore: avoid_print
    print('detail         : ${r.detail}');

    if (r.state == LocalizationState.notInstalled) {
      expect(r.install, isNull);
      return;
    }

    expect(r.install, isNotNull,
        reason: 'a non-notInstalled state must carry an install');
    expect(r.install!.installPath, isNotEmpty);
    expect(r.install!.installPath.endsWith(r'\\'), isFalse,
        reason: 'trailing separator should be trimmed');

    if (r.install!.version.isNotEmpty) {
      expect(RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(r.install!.version),
          isTrue,
          reason: 'bad version string: ${r.install!.version}');
    }

    if (r.baseDllHash != null) {
      final bool known = r.baseDllHash == sha256Original ||
          r.baseDllHash == sha256Localized;
      if (!known) {
        expect(r.state, LocalizationState.unsupported);
      }
    }

    switch (r.state) {
      case LocalizationState.original:
        expect(r.baseDllHash, sha256Original);
        expect(r.zhCnMatching, isFalse,
            reason: 'original DLL with matching resources should be inconsistent');
      case LocalizationState.localized:
        expect(r.baseDllHash, sha256Localized);
        expect(r.zhCnPresent, isTrue);
        expect(r.zhCnMatching, isTrue);
      case LocalizationState.inconsistent:
        final bool dllOk = r.baseDllHash == sha256Original ||
            r.baseDllHash == sha256Localized;
        expect(dllOk, isTrue);
        expect(r.zhCnMatching, isFalse);
      case LocalizationState.unsupported:
      case LocalizationState.notInstalled:
        break;
    }

    if (r.state == LocalizationState.original) {
      expect(r.canLocalize, isTrue);
      expect(r.canRestore, isFalse);
    }
    if (r.state == LocalizationState.localized) {
      expect(r.canLocalize, isFalse);
      expect(r.canRestore, isTrue);
    }
    if (r.state == LocalizationState.unsupported ||
        r.state == LocalizationState.notInstalled) {
      expect(r.canLocalize, isFalse);
      expect(r.canRestore, isFalse);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
