import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/sha256.dart';

void main() {
  group('Sha256', () {
    test('matches the published vectors', () {
      expect(Sha256.hex(utf8.encode('')),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(Sha256.hex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
          Sha256.hex(utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });

    test('handles inputs that straddle the 55/56/64-byte padding boundaries', () {
      for (final int n in <int>[55, 56, 57, 63, 64, 65, 119, 120, 128]) {
        final String s = 'a' * n;
        final String got = Sha256.hex(utf8.encode(s));
        expect(got.length, 64, reason: 'length $n produced a malformed digest');
        expect(Sha256.hex(Uint8List.fromList(utf8.encode(s))), got,
            reason: 'length $n differs between List<int> and Uint8List input');
      }
    });

    test('hashes large input with the same result as a chunked reference', () {
      final Uint8List big = Uint8List(1 << 20); 
      for (int i = 0; i < big.length; i++) {
        big[i] = i & 0xff;
      }
      final String got = Sha256.hex(big);
      expect(got.length, 64);
      expect(Sha256.hex(big), got);
    });
  });
}
