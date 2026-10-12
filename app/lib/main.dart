import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'src/core/i18n.dart';
import 'src/core/localizer_service.dart';
import 'src/core/models.dart';
import 'src/core/op_batch.dart';
import 'src/core/patch_table.dart';
import 'src/core/sha256.dart';
import 'src/core/window_control.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';

const String _languageFlag = '--language=';
const String _themeFlag = '--theme=';

const int _minWindowWidth = 520;
const int _minWindowHeight = 400;

String? _flag(List<String> args, String prefix) {
  for (final String a in args) {
    if (a.startsWith(prefix)) {
      final String v = a.substring(prefix.length).trim();
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--selftest') {
    WidgetsFlutterBinding.ensureInitialized();
    final int code = await SelfTest.run(args.length > 1 ? args[1] : '');

    exit(code);
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isWindows) {
    runApp(_UnsupportedPlatformApp(
      language: AppLanguage.fromLocaleName(_flag(args, _languageFlag) ??
          Platform.localeName),
    ));
    return;
  }

  final String? languageOverride =
      _flag(args, _languageFlag) ?? Platform.environment['VMWL_LANGUAGE'];
  final AppLanguage language = languageOverride == null
      ? AppLanguage.detect()
      : AppLanguage.fromLocaleName(languageOverride);

  final ThemeMode theme = switch (
      (_flag(args, _themeFlag) ?? Platform.environment['VMWL_THEME'])
          ?.toLowerCase()) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  runApp(LocalizerApp(
    initialLanguage: language,
    initialThemeMode: theme,
  ));
}

class SelfTest {
  SelfTest._();

  static Future<int> run(String sourceDll) async {
    stdout.writeln('vmware_localizer self-test');
    stdout.writeln('--------------------------');

    final File source = File(sourceDll);
    if (!source.existsSync()) {
      stderr.writeln('FAIL: pristine vmwarebase.dll not found at $sourceDll');
      stderr.writeln('      usage: vmware_localizer.exe --selftest <path to '
          'original vmwarebase.dll>');
      return 2;
    }
    if (Sha256.hex(source.readAsBytesSync()) != sha256Original) {
      stderr.writeln('FAIL: $sourceDll is not the expected original build');
      return 2;
    }
    stdout.writeln('source dll : $sourceDll  (original, hash ok)');

    final Directory sandbox =
        Directory.systemTemp.createTempSync('vmwl_selftest_');
    stdout.writeln('sandbox    : ${sandbox.path}');
    stdout.writeln('');

    final LocalizerService service = LocalizerService();
    int failures = 0;

    void check(String label, bool ok, [String? detail]) {
      stdout.writeln('  ${ok ? 'PASS' : 'FAIL'}  $label'
          '${detail == null ? '' : '  ($detail)'}');
      if (!ok) failures++;
    }

    try {
      final File dll = File('${sandbox.path}\\vmwarebase.dll');
      dll.writeAsBytesSync(source.readAsBytesSync());

      stdout.writeln('localize:');
      final OpBatchResult loc =
          await OpBatch.collect(service.localizeDirectory(sandbox.path));
      check('no errors reported', loc.errors.isEmpty,
          loc.errors.isEmpty ? null : loc.errors.join('; '));
      check('dll has the localized hash',
          Sha256.hex(dll.readAsBytesSync()) == sha256Localized);
      check('dll size unchanged', dll.lengthSync() == vmwareBaseDllSize);
      check('temp file cleaned up',
          !File('${sandbox.path}\\.vmwl_vmwarebase.tmp').existsSync());

      final Directory zh = Directory('${sandbox.path}\\messages\\zh_CN');
      check('messages/zh_CN created', zh.existsSync());
      for (final PayloadFile f in payloadFiles) {
        final File file = File('${zh.path}\\${f.name}');
        check(
            '${f.name} installed and verified',
            file.existsSync() &&
                Sha256.hex(file.readAsBytesSync()) == f.sha256);
      }
      check('progress reached 100%', loc.finalFraction == 1.0);

      stdout.writeln('');
      stdout.writeln('restore:');
      final OpBatchResult res =
          await OpBatch.collect(service.restoreDirectory(sandbox.path));
      check('no errors reported', res.errors.isEmpty,
          res.errors.isEmpty ? null : res.errors.join('; '));
      check('dll back to the original hash',
          Sha256.hex(dll.readAsBytesSync()) == sha256Original);
      check('dll size unchanged', dll.lengthSync() == vmwareBaseDllSize);
      check('messages/zh_CN removed', !zh.existsSync());
      check('temp file cleaned up',
          !File('${sandbox.path}\\.vmwl_vmwarebase.tmp').existsSync());

      stdout.writeln('');
      stdout.writeln('round trip:');
      final String remaining = _entries(sandbox).join(',');
      check('sandbox back to its initial state',
          remaining == 'vmwarebase.dll', remaining);
    } catch (e, st) {
      stderr.writeln('FAIL: unexpected error: $e');
      stderr.writeln(st.toString());
      failures++;
    } finally {
      try {
        if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
      } catch (_) {
      }
      await service.dispose();
    }

    stdout.writeln('');
    stdout.writeln(
        failures == 0 ? 'ALL CHECKS PASSED' : '$failures CHECK(S) FAILED');
    return failures == 0 ? 0 : 1;
  }

  static List<String> _entries(Directory dir) =>
      dir
          .listSync()
          .map((FileSystemEntity e) =>
              e.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();
}

class LocalizerApp extends StatefulWidget {
  const LocalizerApp({
    super.key,
    required this.initialLanguage,
    required this.initialThemeMode,
  });

  final AppLanguage initialLanguage;
  final ThemeMode initialThemeMode;

  @override
  State<LocalizerApp> createState() => _LocalizerAppState();
}

class _LocalizerAppState extends State<LocalizerApp> {
  late AppLanguage _language = widget.initialLanguage;

  late bool _followSystemTheme = widget.initialThemeMode == ThemeMode.system;
  late ThemeMode _explicitTheme = _followSystemTheme
      ? ThemeMode.light
      : widget.initialThemeMode;

  ThemeMode get _themeMode =>
      _followSystemTheme ? ThemeMode.system : _explicitTheme;

  Strings get _strings => Strings.of(_language);

  @override
  void initState() {
    super.initState();
    WindowControl.initialize(
      minWidth: _minWindowWidth,
      minHeight: _minWindowHeight,
    );
    _applyNativeTitle();
  }

  void _applyNativeTitle() {
    unawaited(WindowControl.setTitle(_strings(Str.windowTitle)));
  }

  void _setLanguage(AppLanguage language) {
    setState(() => _language = language);
    _applyNativeTitle();
  }

  void _setTheme(ThemeMode mode) {
    setState(() {
      if (mode == ThemeMode.system) {
        _followSystemTheme = true;
      } else {
        _followSystemTheme = false;
        _explicitTheme = mode;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Strings strings = _strings;
    return MaterialApp(
      title: strings(Str.windowTitle),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      builder: (BuildContext context, Widget? child) {
        final bool dark = Theme.of(context).brightness == Brightness.dark;
        unawaited(WindowControl.setDark(dark));
        return child ?? const SizedBox.shrink();
      },
      home: HomePage(
        themeMode: _themeMode,
        onThemeModeChanged: _setTheme,
        language: _language,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}

class _UnsupportedPlatformApp extends StatelessWidget {
  const _UnsupportedPlatformApp({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              Strings.of(language)(Str.unsupportedPlatform),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
