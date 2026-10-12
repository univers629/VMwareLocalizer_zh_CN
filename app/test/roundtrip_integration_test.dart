@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/localizer_service.dart';
import 'package:vmware_localizer/src/core/op_batch.dart';
import 'package:vmware_localizer/src/core/models.dart';
import 'package:vmware_localizer/src/core/patch_table.dart';
import 'package:vmware_localizer/src/core/sha256.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String fixtures = Platform.environment['VMWL_FIXTURES'] ?? '';
  final File pristine = File('$fixtures\\original.dll');
  if (fixtures.isEmpty || !pristine.existsSync()) {
    test('round trip', () {},
        skip: 'set VMWL_FIXTURES to a directory containing original.dll');
    return;
  }

  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('vmwl_roundtrip_');
    File('${sandbox.path}\\vmwarebase.dll')
        .writeAsBytesSync(pristine.readAsBytesSync());
  });

  tearDown(() {
    try {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    } catch (_) {
    }
  });

  test('localize then restore returns the directory to its original state',
      () async {
    final LocalizerService service = LocalizerService();

    final OpBatchResult localized =
        await OpBatch.collect(service.localizeDirectory(sandbox.path));
    expect(localized.errors, isEmpty,
        reason: 'localize reported errors: ${localized.errors}');

    final File dll = File('${sandbox.path}\\vmwarebase.dll');
    expect(Sha256.hex(dll.readAsBytesSync()), sha256Localized,
        reason: 'localized DLL does not match the known localized hash');
    expect(dll.lengthSync(), vmwareBaseDllSize);

    final Directory zh = Directory('${sandbox.path}\\messages\\zh_CN');
    expect(zh.existsSync(), isTrue);
    for (final PayloadFile f in payloadFiles) {
      final File file = File('${zh.path}\\${f.name}');
      expect(file.existsSync(), isTrue, reason: '${f.name} was not installed');
      expect(Sha256.hex(file.readAsBytesSync()), f.sha256,
          reason: '${f.name} installed with wrong content');
    }

    expect(File('${sandbox.path}\\.vmwl_vmwarebase.tmp').existsSync(), isFalse);

    final OpBatchResult restored =
        await OpBatch.collect(service.restoreDirectory(sandbox.path));
    expect(restored.errors, isEmpty,
        reason: 'restore reported errors: ${restored.errors}');

    expect(Sha256.hex(dll.readAsBytesSync()), sha256Original,
        reason: 'restore did not return the DLL to its original bytes');
    expect(dll.lengthSync(), vmwareBaseDllSize);

    expect(zh.existsSync(), isFalse,
        reason: 'the empty zh_CN directory should have been removed');
    expect(File('${sandbox.path}\\.vmwl_vmwarebase.tmp').existsSync(), isFalse);

    await service.dispose();

    final List<String> entries = sandbox
        .listSync()
        .map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
    expect(entries, <String>['vmwarebase.dll']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restore keeps a zh_CN directory that holds unrelated files', () async {
    final LocalizerService service = LocalizerService();
    final OpBatchResult localized =
        await OpBatch.collect(service.localizeDirectory(sandbox.path));
    expect(localized.errors, isEmpty);

    final Directory zh = Directory('${sandbox.path}\\messages\\zh_CN');
    File('${zh.path}\\user-notes.txt').writeAsStringSync('do not delete me');

    final OpBatchResult restored =
        await OpBatch.collect(service.restoreDirectory(sandbox.path));
    expect(restored.errors, isEmpty);

    expect(zh.existsSync(), isTrue,
        reason: 'a non-empty zh_CN directory must not be deleted');
    expect(File('${zh.path}\\user-notes.txt').readAsStringSync(),
        'do not delete me');
    for (final PayloadFile f in payloadFiles) {
      expect(File('${zh.path}\\${f.name}').existsSync(), isFalse);
    }

    await service.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restore never removes other VMware language packs', () async {
    final Directory messages = Directory('${sandbox.path}\\messages');
    Directory('${messages.path}\\ja').createSync(recursive: true);
    File('${messages.path}\\ja\\vmui-ja.dll').writeAsStringSync('not ours');

    final LocalizerService service = LocalizerService();
    expect((await OpBatch.collect(service.localizeDirectory(sandbox.path))).errors,
        isEmpty);
    expect((await OpBatch.collect(service.restoreDirectory(sandbox.path))).errors,
        isEmpty);

    expect(Directory('${messages.path}\\ja').existsSync(), isTrue,
        reason: 'the Japanese language pack must be untouched');
    expect(File('${messages.path}\\ja\\vmui-ja.dll').readAsStringSync(),
        'not ours');
    expect(Directory('${messages.path}\\zh_CN').existsSync(), isFalse,
        reason: 'our own zh_CN directory should still be cleaned up');
    expect(messages.existsSync(), isTrue,
        reason: 'messages must survive while other packs are present');

    await service.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('localize refuses a DLL whose hash it does not recognise', () async {
    final File dll = File('${sandbox.path}\\vmwarebase.dll');
    final List<int> bytes = dll.readAsBytesSync();
    bytes[0] = bytes[0] ^ 0xff;
    dll.writeAsBytesSync(bytes);
    final LocalizerService service = LocalizerService();
    final OpBatchResult r =
        await OpBatch.collect(service.localizeDirectory(sandbox.path));

    expect(r.errors, isNotEmpty,
        reason: 'an unknown DLL must be refused, not patched');
    expect(Sha256.hex(dll.readAsBytesSync()),
        isNot(anyOf(sha256Original, sha256Localized)));
    await service.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
