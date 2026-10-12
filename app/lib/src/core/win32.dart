import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class Win32 {
  Win32._();

  static final DynamicLibrary _version = DynamicLibrary.open('version.dll');
  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');

  static final int Function(Pointer<Utf16>, Pointer<Uint32>)
      _getFileVersionInfoSizeW = _version.lookupFunction<
          Uint32 Function(Pointer<Utf16>, Pointer<Uint32>),
          int Function(Pointer<Utf16>, Pointer<Uint32>)>(
      'GetFileVersionInfoSizeW');

  static final int Function(
          Pointer<Utf16>, int, int, Pointer<Void>) _getFileVersionInfoW =
      _version.lookupFunction<
          Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>),
          int Function(Pointer<Utf16>, int, int, Pointer<Void>)>(
      'GetFileVersionInfoW');

  static final int Function(Pointer<Void>, Pointer<Utf16>, Pointer<Void>,
          Pointer<Uint32>, Pointer<Pointer<Uint16>>) _verQueryValueW =
      _version.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf16>, Pointer<Void>,
              Pointer<Uint32>, Pointer<Pointer<Uint16>>),
          int Function(Pointer<Void>, Pointer<Utf16>, Pointer<Void>,
              Pointer<Uint32>, Pointer<Pointer<Uint16>>)>('VerQueryValueW');

  static List<int>? fileVersion(String path) {
    final Pointer<Utf16> p = path.toNativeUtf16();
    final Pointer<Uint32> ignored = calloc<Uint32>();
    try {
      final int size = _getFileVersionInfoSizeW(p, ignored);
      if (size == 0) return null;

      final Pointer<Void> buf = calloc<Uint8>(size).cast<Void>();
      try {
        if (_getFileVersionInfoW(p, 0, size, buf) == 0) return null;

        final Pointer<Pointer<Uint16>> valuePtr =
            calloc<Pointer<Uint16>>();
        final Pointer<Uint32> valueLen = calloc<Uint32>();
        final Pointer<Utf16> root = r'\'.toNativeUtf16();
        try {
          final int ok =
              _verQueryValueW(buf, root, valuePtr.cast(), valueLen, valuePtr);
          if (ok == 0 || valueLen.value < 52) return null;

          final Pointer<Uint32> info = valuePtr.value.cast<Uint32>();
          final int fileVersionMs = info[2];
          final int fileVersionLs = info[3];
          return <int>[
            (fileVersionMs >> 16) & 0xffff,
            fileVersionMs & 0xffff,
            (fileVersionLs >> 16) & 0xffff,
            fileVersionLs & 0xffff,
          ];
        } finally {
          calloc.free(root);
          calloc.free(valuePtr);
          calloc.free(valueLen);
        }
      } finally {
        calloc.free(buf);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(p);
      calloc.free(ignored);
    }
  }

  static final int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
          Pointer<Utf16>, Pointer<Utf16>, int) _shellExecuteW =
      _shell32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
              Pointer<Utf16>, Pointer<Utf16>, Int32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
              Pointer<Utf16>, Pointer<Utf16>, int)>('ShellExecuteW');

  static bool relaunchElevated(List<String> arguments) {
    final Pointer<Utf16> verb = 'runas'.toNativeUtf16();
    final Pointer<Utf16> file = Platform.resolvedExecutable.toNativeUtf16();
    final Pointer<Utf16> params =
        arguments.map((String a) => '"$a"').join(' ').toNativeUtf16();
    try {
      final int r = _shellExecuteW(
        nullptr,
        verb,
        file,
        params,
        nullptr,
        1, 
      );
      return r > 32;
    } catch (_) {
      return false;
    } finally {
      calloc.free(verb);
      calloc.free(file);
      calloc.free(params);
    }
  }
}
