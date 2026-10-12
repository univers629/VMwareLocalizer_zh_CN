import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/patch_table.dart';
import 'package:vmware_localizer/src/core/sha256.dart';

String get _fixtures => Platform.environment['VMWL_FIXTURES'] ?? '';

void main() {
  final String dir = _fixtures;
  final File original = File('$dir\\original.dll');
  final File localized = File('$dir\\localized.dll');
  final bool haveFixtures = dir.isNotEmpty &&
      original.existsSync() &&
      localized.existsSync();

  group('vmwarebase.dll patch', () {
    test('forward: original becomes the localized build, byte-for-byte',
        () {
      final Uint8List bytes = original.readAsBytesSync();
      expect(bytes.length, vmwareBaseDllSize);
      expect(Sha256.hex(bytes), sha256Original);

      for (final BytePatch p in vmwareBasePatch) {
        expect(bytes[p.offset], p.original,
            reason: 'precondition failed at 0x${p.offset.toRadixString(16)}');
        bytes[p.offset] = p.localized;
      }

      final String got = Sha256.hex(bytes);
      expect(got, sha256Localized);
      expect(got, Sha256.hex(localized.readAsBytesSync()));
    });

    test('inverse: localized returns to the original, byte-for-byte', () {
      final Uint8List bytes = localized.readAsBytesSync();
      expect(Sha256.hex(bytes), sha256Localized);

      for (final BytePatch p in vmwareBasePatch) {
        expect(bytes[p.offset], p.localized,
            reason: 'precondition failed at 0x${p.offset.toRadixString(16)}');
        bytes[p.offset] = p.original;
      }

      final String got = Sha256.hex(bytes);
      expect(got, sha256Original);
      expect(got, Sha256.hex(original.readAsBytesSync()));
    });

    test('the patch is a size-preserving, fully reversible in-place edit', () {
      final Uint8List bytes = Uint8List.fromList(original.readAsBytesSync());
      final Uint8List snapshot = Uint8List.fromList(bytes);

      for (final BytePatch p in vmwareBasePatch) {
        bytes[p.offset] = p.localized;
      }
      for (final BytePatch p in vmwareBasePatch) {
        bytes[p.offset] = p.original;
      }

      expect(bytes.length, snapshot.length);
      expect(Sha256.hex(bytes), sha256Original);
    });
  }, skip: haveFixtures
      ? false
      : 'set VMWL_FIXTURES to a directory with original.dll and localized.dll');
}
