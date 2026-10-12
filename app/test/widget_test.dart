import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/models.dart';
import 'package:vmware_localizer/src/core/patch_table.dart';
import 'package:vmware_localizer/src/core/sha256.dart';
import 'package:vmware_localizer/src/ui/theme.dart';

void main() {
  group('patch table', () {
    test('every entry actually changes the byte', () {
      for (final BytePatch p in vmwareBasePatch) {
        expect(p.original, isNot(p.localized),
            reason: 'offset 0x${p.offset.toRadixString(16)} is a no-op');
      }
    });

    test('offsets are inside the file and strictly increasing', () {
      int previous = -1;
      for (final BytePatch p in vmwareBasePatch) {
        expect(p.offset, greaterThanOrEqualTo(0));
        expect(p.offset, lessThan(vmwareBaseDllSize));
        expect(p.offset, greaterThan(previous),
            reason: 'offsets must be unique and sorted');
        previous = p.offset;
      }
    });

    test('the language dispatch is the Japanese to Chinese rewrite', () {
      final BytePatch dispatch =
          vmwareBasePatch.firstWhere((BytePatch p) => p.offset == 0x243004);
      expect(dispatch.original, 0x11);
      expect(dispatch.localized, 0x04);
    });

    test('count and hashes match the verified restoration', () {
      expect(vmwareBasePatch.length, 45);
      expect(sha256Original,
          'c071cb126f64d4fa4d5f89f73e5e46d6632109c4439496d978db0f9ac4a849a4');
      expect(sha256Localized,
          '0c1bb51493261846f0a2e8a3c8b7df5f7d85f3afec22033b48f79af8f4f5efa9');
    });
  });

  group('payload manifest', () {
    test('lists the three resource satellites with their verified hashes', () {
      expect(payloadFiles.map((PayloadFile f) => f.name).toList(),
          <String>['vmui-zh_CN.dll', 'vmappsdk-zh_CN.dll', 'vmware.vmsg']);
      for (final PayloadFile f in payloadFiles) {
        expect(f.sha256.length, 64,
            reason: '${f.name} must carry a full SHA-256');
      }
    });
  });

  group('hash hygiene', () {
    test('every recorded hash is well-formed lowercase hex', () {
      for (final String h in <String>[
        sha256Original,
        sha256Localized,
        ...payloadFiles.map((PayloadFile f) => f.sha256),
      ]) {
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue,
            reason: 'bad hash: $h');
      }
    });

    test('the empty-string digest matches the reference', () {
      expect(Sha256.hex(const <int>[]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });

  group('themes', () {
    test('light and dark are both Material 3 and differ in brightness', () {
      final ThemeData light = AppTheme.light();
      final ThemeData dark = AppTheme.dark();
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });
  });
}
