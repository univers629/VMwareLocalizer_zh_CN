import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'i18n.dart';
import 'models.dart';
import 'patch_table.dart';
import 'sha256.dart';
import 'win32.dart';

class OpProgress {
  const OpProgress(this.fraction, this.message, {this.log, this.failed = false});

  final double fraction;

  final String message;

  final String? log;

  final bool failed;
}

Future<VmwareInstall?> _readInstall() async {
  if (!Platform.isWindows) return null;
  try {
    final ProcessResult r = await Process.run('reg', <String>[
      'query',
      r'HKLM\SOFTWARE\VMware, Inc.\VMware Workstation',
    ], runInShell: false);
    if (r.exitCode != 0) return null;

    String? installPath;
    String? productVersion;
    for (final String line in (r.stdout as String).split('\n')) {
      final List<String> parts = line.trim().split(RegExp(r'\s{2,}'));
      if (parts.length < 3) continue;
      final String name = parts[0];
      final String value = parts.sublist(2).join(' ').trim();
      if (name == 'InstallPath') installPath = value;
      if (name == 'ProductVersion') productVersion = value;
    }
    if (installPath == null || installPath.trim().isEmpty) return null;

    String path = installPath.trim();
    while (path.endsWith('\\')) {
      path = path.substring(0, path.length - 1);
    }

    final List<int>? v = Win32.fileVersion('$path\\vmware.exe');
    final String version = v == null
        ? ''
        : '${v[0]}.${v[1]}.${v[2]}.${v[3]}';

    return VmwareInstall(
      installPath: path,
      version: version,
      productVersion: productVersion ?? '',
    );
  } catch (_) {
    return null;
  }
}

Future<bool> _vmwareRunning() async {
  for (final String exe in <String>[
    'vmware.exe',
    'vmware-tray.exe',
    'vmware-vmx.exe',
  ]) {
    try {
      final ProcessResult r = await Process.run(
        'tasklist',
        <String>['/FI', 'IMAGENAME eq $exe', '/NH'],
        runInShell: false,
      );
      final String out = (r.stdout as String);
      if (out.contains(exe)) return true;
    } catch (_) {
    }
  }
  return false;
}

class PayloadLoader {
  PayloadLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  static const String _asset = 'assets/payload.zip';
  static const String _cachePrefix = 'vmware_localizer_payload_';

  static const String _payloadSubdir = 'messages\\zh_CN';

  Directory? _cacheDir;
  Future<void>? _preparing;

  Future<void> prepare() {
    return _preparing ??= _prepare();
  }

  Future<void> _prepare() async {
    final ByteData archive = await _bundle.load(_asset);
    final Uint8List archiveBytes =
        archive.buffer.asUint8List(archive.offsetInBytes, archive.lengthInBytes);

    final String tag = Sha256.hex(archiveBytes).substring(0, 16);
    final Directory dir =
        Directory('${Directory.systemTemp.path}\\$_cachePrefix$tag');

    if (_isCacheValid(dir)) {
      _cacheDir = Directory('${dir.path}\\$_payloadSubdir');
      return;
    }

    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);

    final File zip = File('${dir.path}\\.payload.zip');
    zip.writeAsBytesSync(archiveBytes, flush: true);

    final ProcessResult r = await Process.run(
      'tar',
      <String>['-xf', zip.path, '-C', dir.path],
      runInShell: false,
    );
    if (r.exitCode != 0) {
      throw LocalizerException(Str.errPayloadExtract, <String, String>{
        'detail': '${r.exitCode}',
      });
    }
    zip.deleteSync();

    if (!_isCacheValid(dir)) {
      throw const LocalizerException(Str.errPayloadVerify);
    }

    _cacheDir = Directory('${dir.path}\\$_payloadSubdir');
    _pruneStaleCaches(keep: tag);
  }

  bool _isCacheValid(Directory dir) {
    if (!dir.existsSync()) return false;
    for (final PayloadFile f in payloadFiles) {
      final File file = File('${dir.path}\\$_payloadSubdir\\${f.name}');
      if (!file.existsSync()) return false;
      if (Sha256.hex(file.readAsBytesSync()) != f.sha256) return false;
    }
    return true;
  }

  void _pruneStaleCaches({required String keep}) {
    try {
      final Directory temp = Directory.systemTemp;
      for (final FileSystemEntity e in temp.listSync()) {
        if (e is! Directory) continue;
        final String name = e.path.split(Platform.pathSeparator).last;
        if (!name.startsWith(_cachePrefix) || name == '$_cachePrefix$keep') {
          continue;
        }
        try {
          e.deleteSync(recursive: true);
        } catch (_) {
        }
      }
    } catch (_) {
    }
  }

  Uint8List read(String name) {
    final Directory? dir = _cacheDir;
    if (dir == null) {
      throw const LocalizerException(Str.errPayloadNotExtracted);
    }
    return File('${dir.path}\\$name').readAsBytesSync();
  }

  Future<void> dispose() async {
    _cacheDir = null;
    _preparing = null;
  }
}

class LocalizerException implements Exception {
  const LocalizerException(this.key, [this.values = const <String, String>{}]);

  final Str key;
  final Map<String, String> values;

  String render(Strings s) => s.format(key, values);

  @override
  String toString() => 'LocalizerException(${key.name})';
}

typedef _Emit = void Function(
  double fraction,
  Str key, {
  Str? log,
  Map<String, String>? values,
});

class LocalizerService {
  LocalizerService({
    PayloadLoader? payload,
    this.manageProcesses = true,
    Strings? strings,
  })  : _payload = payload ?? PayloadLoader(),
        _strings = strings ?? Strings.of(AppLanguage.english);

  final PayloadLoader _payload;

  final Strings _strings;

  final bool manageProcesses;

  Future<void> dispose() => _payload.dispose();

  Future<InstallationReport> detect() async {
    final VmwareInstall? install = await _readInstall();
    if (install == null) {
      return const InstallationReport(
        install: null,
        state: LocalizationState.notInstalled,
        baseDllHash: null,
        zhCnPresent: false,
        zhCnMatching: false,
        vmwareRunning: false,
      );
    }

    final File dll = File(install.baseDllPath);
    String? hash;
    if (dll.existsSync()) {
      hash = Sha256.hex(dll.readAsBytesSync());
    }

    final bool zhPresent = payloadFiles.every(
        (PayloadFile f) => File('${install.zhCnPath}\\${f.name}').existsSync());
    bool zhMatching = false;
    if (zhPresent) {
      zhMatching = true;
      for (final PayloadFile f in payloadFiles) {
        final File file = File('${install.zhCnPath}\\${f.name}');
        if (Sha256.hex(file.readAsBytesSync()) != f.sha256) {
          zhMatching = false;
          break;
        }
      }
    }

    final bool running = await _vmwareRunning();

    LocalizationState state;
    Str? detail;
    if (hash == null) {
      state = LocalizationState.unsupported;
      detail = Str.detailDllMissing;
    } else if (hash == sha256Original) {
      state = (zhPresent && zhMatching)
          ? LocalizationState.inconsistent
          : LocalizationState.original;
      if (state == LocalizationState.inconsistent) {
        detail = Str.detailOriginalWithResources;
      }
    } else if (hash == sha256Localized) {
      state = (zhPresent && zhMatching)
          ? LocalizationState.localized
          : LocalizationState.inconsistent;
      if (state == LocalizationState.inconsistent) {
        detail = Str.detailLocalizedMissingResources;
      }
    } else {
      state = LocalizationState.unsupported;
      detail = Str.detailUnsupportedVersion;
    }

    return InstallationReport(
      install: install,
      state: state,
      baseDllHash: hash,
      zhCnPresent: zhPresent,
      zhCnMatching: zhMatching,
      vmwareRunning: running,
      detail: detail,
    );
  }

  Future<bool> canWriteInstall(VmwareInstall install) async {
    try {
      final File probe =
          File('${install.installPath}\\.vmwl_write_probe');
      probe.writeAsStringSync('probe', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> vmwareProcessesRunning() => _vmwareRunning();

  // Terminates every process that holds the installation directory open. Called
  // only after the user has agreed to it, since running virtual machines are
  // powered off as a side effect.
  Future<void> closeVmwareProcesses() async {
    for (final String exe in <String>[
      'vmware.exe',
      'vmware-tray.exe',
      'vmware-vmx.exe',
    ]) {
      try {
        await Process.run(
          'taskkill',
          <String>['/f', '/im', exe],
          runInShell: false,
        );
      } catch (_) {
        // A process that is not running makes taskkill fail; that is expected.
      }
    }

    // Give the killed processes a moment to release their file handles.
    for (int attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!await _vmwareRunning()) return;
    }
  }

  bool requestElevation({AppLanguage? language, PendingAction? action}) {
    return Win32.relaunchElevated(<String>[
      '--elevated',
      if (language != null) '--language=${language.code}',
      if (action != null) action.flag,
    ]);
  }

  Stream<OpProgress> localize(InstallationReport report,
          {AppLanguage? language}) =>
      _run(report, localizing: true, language: language);

  Stream<OpProgress> restore(InstallationReport report,
          {AppLanguage? language}) =>
      _run(report, localizing: false, language: language);

  Stream<OpProgress> localizeDirectory(String installPath,
          {AppLanguage? language}) =>
      _runOn(
        reportForPath(installPath),
        localizing: true,
        manageProcesses: false,
        strings: Strings.of(language ?? AppLanguage.english),
      );

  Stream<OpProgress> restoreDirectory(String installPath,
          {AppLanguage? language}) =>
      _runOn(
        reportForPath(installPath),
        localizing: false,
        manageProcesses: false,
        strings: Strings.of(language ?? AppLanguage.english),
      );

  InstallationReport reportForPath(String installPath, {bool zhCnPresent = true}) {
    String path = installPath;
    while (path.endsWith('\\')) {
      path = path.substring(0, path.length - 1);
    }
    return InstallationReport(
      install: VmwareInstall(
        installPath: path,
        version: supportedVersion,
        productVersion: '',
      ),
      state: LocalizationState.original,
      baseDllHash: null,
      zhCnPresent: zhCnPresent,
      zhCnMatching: zhCnPresent,
      vmwareRunning: false,
    );
  }

  Stream<OpProgress> _run(InstallationReport report,
      {required bool localizing, AppLanguage? language}) {
    return _runOn(
      report,
      localizing: localizing,
      manageProcesses: manageProcesses,
      strings: language == null ? null : Strings.of(language),
    );
  }

  Stream<OpProgress> _runOn(
    InstallationReport report, {
    required bool localizing,
    bool? manageProcesses,
    Strings? strings,
  }) {
    final StreamController<OpProgress> c = StreamController<OpProgress>();

    final bool manage = manageProcesses ?? this.manageProcesses;
    final Strings s = strings ?? _strings;

    Future<void> go() async {
      void emit(double fraction, Str key,
          {Str? log, Map<String, String>? values}) {
        if (c.isClosed) return;
        c.add(OpProgress(
          fraction,
          s.format(key, values ?? const <String, String>{}),
          log: log == null
              ? null
              : s.format(log, values ?? const <String, String>{}),
        ));
      }

      final VmwareInstall? install = report.install;
      if (install == null) {
        c.add(OpProgress(0, s(Str.errNotInstalled), failed: true));
        await c.close();
        return;
      }

      try {
        emit(0.02, Str.logCheckingProcess);
        if (manage && await _vmwareRunning()) {
          emit(0.04, Str.logClosingProcess);
          await Process.run('taskkill',
              <String>['/f', '/im', 'vmware-tray.exe'], runInShell: false);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (await _vmwareRunning()) {
            throw const LocalizerException(Str.errStillRunning);
          }
        }

        // Record which services were actually running, so the same set can be
        // put back afterwards rather than starting ones the user had stopped.
        final Map<String, bool> serviceWasRunning = <String, bool>{};
        if (manage) {
          emit(0.10, Str.logStoppingServices);
          for (final String svc in _services) {
            final bool running = await _serviceRunning(svc);
            serviceWasRunning[svc] = running;
            if (!running) continue;

            emit(0.10, Str.logStoppingService,
                log: Str.logStoppingService, values: <String, String>{'name': svc});
            await Process.run('net', <String>['stop', svc], runInShell: false);
          }
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }

        emit(0.30, localizing ? Str.logWritingPatch : Str.logRestoringPatch);
        await _applyPatch(install, localizing: localizing, emit: emit, s: s);

        if (localizing) {
          emit(0.70, Str.logInstallingResources);
          await _installResources(install, emit: emit, s: s);
        } else {
          emit(0.70, Str.logRemovingResources);
          await _removeResources(install, emit: emit, s: s);
        }

        emit(0.90, Str.logStartingServices);
        if (manage) {
          for (final String svc in _services) {
            if (serviceWasRunning[svc] != true) continue;
            emit(0.90, Str.logStartingService,
                log: Str.logStartingService, values: <String, String>{'name': svc});
            await Process.run('net', <String>['start', svc], runInShell: false);
          }
        }

        emit(1.0, localizing ? Str.doneLocalized : Str.doneRestored);
      } on LocalizerException catch (e) {
        if (!c.isClosed) {
          c.add(OpProgress(1.0, s.format(Str.failPrefix, const <String, String>{}) +
              e.render(s),
              failed: true));
        }
      } catch (e) {
        if (!c.isClosed) {
          c.add(OpProgress(1.0, s(Str.failPrefix) + e.toString(), failed: true));
        }
      } finally {
        await c.close();
      }
    }

    unawaited(go());
    return c.stream;
  }

  static const List<String> _services = <String>[
    'VMAuthdService',
    'VMnetDHCP',
    'VMware NAT Service',
    'VMUSBArbService',
  ];

  // The state names in sc output are not localised, so the text is stable
  // regardless of the display language.
  static Future<bool> _serviceRunning(String name) async {
    try {
      final ProcessResult r = await Process.run(
        'sc',
        <String>['query', name],
        runInShell: false,
      );
      return (r.stdout as String).contains('RUNNING');
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyPatch(
    VmwareInstall install, {
    required bool localizing,
    required _Emit emit,
    required Strings s,
  }) async {
    final File dll = File(install.baseDllPath);
    if (!dll.existsSync()) {
      throw const LocalizerException(Str.errDllNotFound);
    }

    final Uint8List bytes = dll.readAsBytesSync();

    if (bytes.length != vmwareBaseDllSize) {
      throw LocalizerException(Str.errDllSizeAbnormal, <String, String>{
        'actual': '${bytes.length}',
        'expected': '$vmwareBaseDllSize',
      });
    }

    final String before = Sha256.hex(bytes);
    final String from = localizing ? sha256Original : sha256Localized;
    final String to = localizing ? sha256Localized : sha256Original;

    if (before == to) {
      emit(0.45, Str.logSkipped, log: Str.logNoChangeNeeded);
      return;
    }
    if (before != from) {
      throw const LocalizerException(Str.errDllHashMismatch);
    }

    for (final BytePatch p in vmwareBasePatch) {
      final int expect = localizing ? p.original : p.localized;
      final int write = localizing ? p.localized : p.original;
      if (bytes[p.offset] != expect) {
        throw LocalizerException(Str.errPatchDataMismatch, <String, String>{
          'offset': '0x${p.offset.toRadixString(16)}',
        });
      }
      bytes[p.offset] = write;
    }

    final String after = Sha256.hex(bytes);
    if (after != to) {
      throw const LocalizerException(Str.errVerifyAfterWrite);
    }

    final File tmp = File('${install.installPath}\\.vmwl_vmwarebase.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    if (tmp.lengthSync() != vmwareBaseDllSize) {
      tmp.deleteSync();
      throw const LocalizerException(Str.errTempIncomplete);
    }
    tmp.renameSync(dll.path);

    emit(0.60, Str.logPatchVerified,
        log: Str.logPatchApplied,
        values: <String, String>{
          'from': before.substring(0, 12),
          'to': after.substring(0, 12),
        });
  }

  Future<void> _installResources(
    VmwareInstall install, {
    required _Emit emit,
    required Strings s,
  }) async {
    final Directory dir = Directory(install.zhCnPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await _payload.prepare();

    int done = 0;
    for (final PayloadFile f in payloadFiles) {
      final Uint8List data = _payload.read(f.name);
      final String got = Sha256.hex(data);
      if (got != f.sha256) {
        throw const LocalizerException(Str.errPayloadVerify);
      }
      File('${dir.path}\\${f.name}').writeAsBytesSync(data, flush: true);
      done++;
      emit(
        0.70 + 0.15 * (done / payloadFiles.length),
        Str.logWritingFile,
        log: Str.logWritingFile,
        values: <String, String>{'name': f.name, 'size': _mb(data.length)},
      );
    }
  }

  Future<void> _removeResources(
    VmwareInstall install, {
    required _Emit emit,
    required Strings s,
  }) async {
    final Directory dir = Directory(install.zhCnPath);
    if (!dir.existsSync()) {
      emit(0.85, Str.logResourcesAbsent);
      return;
    }
    for (final PayloadFile f in payloadFiles) {
      final File file = File('${dir.path}\\${f.name}');
      if (file.existsSync()) {
        file.deleteSync();
        emit(0.70, Str.logRemovedFile,
            log: Str.logRemovedFile, values: <String, String>{'name': f.name});
      }
    }
    if (dir.listSync().isEmpty) {
      dir.deleteSync();
      emit(0.85, Str.logRemovedZhDir);

      final Directory parent = dir.parent;
      if (parent.existsSync() &&
          parent.listSync().isEmpty &&
          parent.path == install.messagesPath) {
        parent.deleteSync();
        emit(0.86, Str.logRemovedMessagesDir);
      }
    } else {
      emit(0.85, Str.logDirKept);
    }
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(2)} MB';
}
