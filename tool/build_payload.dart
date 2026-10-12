import 'dart:io';

const Map<String, String> payloadManifest = <String, String>{
  'vmui-zh_CN.dll':
      '18d5d7544cd1542181f68d9e8c65289590fa7ef869b5362832196b6fc9818019',
  'vmappsdk-zh_CN.dll':
      'efaed649414b133d1b023b8756a3afea60b43bedf64a170581bd506566c6f17e',
  'vmware.vmsg':
      'c29a99869e013d1de32eb5a7af2fee87af96e3e27fe662d6400141e33cc5cfb3',
};

const String archiveDir = 'messages/zh_CN';

Future<int> main(List<String> args) async {
  String source = Directory.current.path;
  String output = 'assets/payload.zip';

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        if (i + 1 >= args.length) {
          stderr.writeln('--from requires a directory');
          return 2;
        }
        source = args[++i];
      case '-o':
      case '--out':
        if (i + 1 >= args.length) {
          stderr.writeln('--out requires a path');
          return 2;
        }
        output = args[++i];
      case '-h':
      case '--help':
        stdout.writeln('usage: dart tool/build_payload.dart [--from DIR] '
            '[-o OUT]');
        return 0;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        return 2;
    }
  }

  final Directory srcDir = Directory(source);
  if (!srcDir.existsSync()) {
    stderr.writeln('source directory not found: $source');
    return 2;
  }

  final Map<String, List<int>> files = <String, List<int>>{};
  for (final MapEntry<String, String> e in payloadManifest.entries) {
    final File f = File('${srcDir.path}${Platform.pathSeparator}${e.key}');
    if (!f.existsSync()) {
      stderr.writeln('missing source file: ${f.path}');
      return 2;
    }
    final List<int> bytes = f.readAsBytesSync();
    final String got = _sha256Hex(bytes);
    if (got != e.value) {
      stderr.writeln('hash mismatch for ${e.key}');
      stderr.writeln('  expected ${e.value}');
      stderr.writeln('  actual   $got');
      return 1;
    }
    files[e.key] = bytes;
    stdout.writeln(
        '  ${e.key.padRight(22)} ${bytes.length.toString().padLeft(10)} bytes'
        '  verified');
  }

  final File out = File(output);
  out.parent.createSync(recursive: true);
  final List<int> archive = _buildZip(files);
  out.writeAsBytesSync(archive, flush: true);

  final int rawTotal =
      files.values.fold<int>(0, (int a, List<int> b) => a + b.length);
  stdout.writeln('');
  stdout.writeln('raw total : $rawTotal bytes '
      '(${(rawTotal / 1048576).toStringAsFixed(2)} MB)');
  stdout.writeln('archive   : ${archive.length} bytes '
      '(${(archive.length / 1048576).toStringAsFixed(2)} MB)');
  stdout.writeln('wrote     : ${out.path}');
  return 0;
}

List<int> _buildZip(Map<String, List<int>> files) {
  final List<int> out = <int>[];
  final List<_CentralEntry> central = <_CentralEntry>[];

  for (final MapEntry<String, List<int>> e in files.entries) {
    final String name = '$archiveDir/${e.key}';
    final List<int> nameBytes = _ascii(name);
    final List<int> raw = e.value;
    final List<int> deflated = _deflate(raw);
    final int crc = _crc32(raw);

    final int localHeaderOffset = out.length;
    out.addAll(_u32(0x04034b50));
    out.addAll(_u16(20)); 
    out.addAll(_u16(0x0800)); 
    out.addAll(_u16(8)); 
    out.addAll(_u16(0)); 
    out.addAll(_u16(0x21)); 
    out.addAll(_u32(crc));
    out.addAll(_u32(deflated.length));
    out.addAll(_u32(raw.length));
    out.addAll(_u16(nameBytes.length));
    out.addAll(_u16(0));
    out.addAll(nameBytes);
    out.addAll(deflated);

    central.add(_CentralEntry(nameBytes, crc, deflated.length, raw.length,
        localHeaderOffset));
  }

  final int centralStart = out.length;
  for (final _CentralEntry c in central) {
    out.addAll(_u32(0x02014b50));
    out.addAll(_u16(20)); 
    out.addAll(_u16(20)); 
    out.addAll(_u16(0x0800)); 
    out.addAll(_u16(8)); 
    out.addAll(_u16(0)); 
    out.addAll(_u16(0x21)); 
    out.addAll(_u32(c.crc));
    out.addAll(_u32(c.compressedSize));
    out.addAll(_u32(c.uncompressedSize));
    out.addAll(_u16(c.name.length));
    out.addAll(_u16(0)); 
    out.addAll(_u16(0)); 
    out.addAll(_u16(0)); 
    out.addAll(_u16(0)); 
    out.addAll(_u32(0)); 
    out.addAll(_u32(c.localHeaderOffset));
    out.addAll(c.name);
  }
  final int centralSize = out.length - centralStart;

  out.addAll(_u32(0x06054b50));
  out.addAll(_u16(0));
  out.addAll(_u16(0));
  out.addAll(_u16(central.length));
  out.addAll(_u16(central.length));
  out.addAll(_u32(centralSize));
  out.addAll(_u32(centralStart));
  out.addAll(_u16(0)); 

  return out;
}

class _CentralEntry {
  const _CentralEntry(this.name, this.crc, this.compressedSize,
      this.uncompressedSize, this.localHeaderOffset);
  final List<int> name;
  final int crc;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}

List<int> _deflate(List<int> data) {
  return ZLibCodec(raw: true, level: 9).encode(data);
}

List<int> _u16(int v) => <int>[v & 0xff, (v >> 8) & 0xff];

List<int> _u32(int v) =>
    <int>[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

List<int> _ascii(String s) => s.codeUnits;

int _crc32(List<int> data) {
  int crc = 0xffffffff;
  for (final int b in data) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

String _sha256Hex(List<int> data) {
  const List<int> k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final int len = data.length;
  final int bitLen = len * 8;
  final int total = ((len + 9 + 63) ~/ 64) * 64;
  final List<int> msg = List<int>.filled(total, 0);
  msg.setRange(0, len, data);
  msg[len] = 0x80;
  for (int i = 0; i < 8; i++) {
    msg[total - 1 - i] = (bitLen >> (8 * i)) & 0xff;
  }

  int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
  final List<int> w = List<int>.filled(64, 0);

  for (int off = 0; off < total; off += 64) {
    for (int i = 0; i < 16; i++) {
      final int j = off + i * 4;
      w[i] = (msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3];
    }
    for (int i = 16; i < 64; i++) {
      final int s0 =
          rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final int s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (int i = 0; i < 64; i++) {
      final int s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final int ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final int t1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final int s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final StringBuffer sb = StringBuffer();
  for (final int v in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    sb.write(v.toRadixString(16).padLeft(8, '0'));
  }
  return sb.toString();
}
