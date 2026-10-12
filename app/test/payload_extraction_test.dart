@Tags(<String>['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/localizer_service.dart';
import 'package:vmware_localizer/src/core/models.dart';
import 'package:vmware_localizer/src/core/sha256.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('payload archive loads, extracts and verifies', () async {
    final PayloadLoader loader = PayloadLoader();
    try {
      await loader.prepare();

      for (final PayloadFile f in payloadFiles) {
        final List<int> data = loader.read(f.name);
        expect(data, isNotEmpty, reason: '${f.name} came out empty');
        expect(Sha256.hex(data), f.sha256,
            reason: '${f.name} does not match its manifest hash');
        // ignore: avoid_print
        print('${f.name.padRight(24)} ${data.length.toString().padLeft(10)} bytes  ok');
      }
    } finally {
      await loader.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('two independent loaders share one cache without interfering', () async {
    final PayloadLoader a = PayloadLoader();
    final PayloadLoader b = PayloadLoader();
    try {
      await a.prepare();
      final List<int> fromA = a.read(payloadFiles.first.name);

      await b.prepare();
      final List<int> fromB = b.read(payloadFiles.first.name);
      expect(Sha256.hex(fromB), Sha256.hex(fromA));

      await a.dispose();
      final List<int> afterDispose = b.read(payloadFiles.first.name);
      expect(Sha256.hex(afterDispose), Sha256.hex(fromA));
    } finally {
      await b.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the extracted cache survives and is reused on a later loader', () async {
    final PayloadLoader first = PayloadLoader();
    await first.prepare();
    final List<int> bytes = first.read(payloadFiles.first.name);
    await first.dispose();

    final PayloadLoader second = PayloadLoader();
    try {
      await second.prepare();
      expect(Sha256.hex(second.read(payloadFiles.first.name)),
          Sha256.hex(bytes));
    } finally {
      await second.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
