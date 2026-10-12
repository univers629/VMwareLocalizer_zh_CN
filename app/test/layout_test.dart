import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/i18n.dart';
import 'package:vmware_localizer/src/ui/home_page.dart';
import 'package:vmware_localizer/src/ui/theme.dart';
import 'package:vmware_localizer/src/ui/title_bar.dart';

void main() {
  const List<Size> sizes = <Size>[
    Size(520, 400), 
    Size(600, 452), 
    Size(900, 620),
    Size(1600, 900),
  ];

  group('startup background', () {
    int? readColorref(String source, String name) {
      final RegExp pattern = RegExp(
        'constexpr\\s+COLORREF\\s+$name\\s*=\\s*RGB\\(\\s*(0x[0-9A-Fa-f]+|\\d+)\\s*,'
        '\\s*(0x[0-9A-Fa-f]+|\\d+)\\s*,\\s*(0x[0-9A-Fa-f]+|\\d+)\\s*\\)',
      );
      final RegExpMatch? m = pattern.firstMatch(source);
      if (m == null) return null;
      int parse(String s) => s.startsWith('0x') || s.startsWith('0X')
          ? int.parse(s.substring(2), radix: 16)
          : int.parse(s);
      return (parse(m.group(1)!) << 16) |
          (parse(m.group(2)!) << 8) |
          parse(m.group(3)!);
    }

    int rgbOf(Color c) =>
        ((c.r * 255).round() << 16) |
        ((c.g * 255).round() << 8) |
        (c.b * 255).round();

    test('the runner paints the theme background', () {
      final File source = File('windows/runner/flutter_window.cpp');
      expect(source.existsSync(), isTrue,
          reason: 'expected to run from the app directory');

      final String text = source.readAsStringSync();

      expect(readColorref(text, 'kBackgroundLight'),
          rgbOf(AppTheme.light().scaffoldBackgroundColor),
          reason: 'kBackgroundLight in windows/runner/flutter_window.cpp no '
              'longer matches the light theme background');
      expect(readColorref(text, 'kBackgroundDark'),
          rgbOf(AppTheme.dark().scaffoldBackgroundColor),
          reason: 'kBackgroundDark in windows/runner/flutter_window.cpp no '
              'longer matches the dark theme background');
    });

    test('the runner honours a forced theme for the first paint', () {
      final String text =
          File('windows/runner/flutter_window.cpp').readAsStringSync();

      expect(text.contains('--theme='), isTrue,
          reason: 'the runner no longer parses --theme, so a forced theme will '
              'flash the system colour at startup');
      expect(text.contains('VMWL_THEME'), isTrue,
          reason: 'the runner no longer reads VMWL_THEME');
      expect(text.contains('ResolvedPrefersDark()'), isTrue,
          reason: 'the startup background no longer uses the forced theme');
    });
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    AppLanguage language,
    ThemeMode mode,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: HomePage(
        themeMode: mode,
        onThemeModeChanged: (_) {},
        language: language,
        onLanguageChanged: (_) {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final AppLanguage language in AppLanguage.values) {
    testWidgets('lays out without overflow in ${language.name}', (
      WidgetTester tester,
    ) async {
      for (final Size size in sizes) {
        await pumpAt(tester, size, language, ThemeMode.light);
        expect(tester.takeException(), isNull,
            reason: '${language.name} overflowed at '
                '${size.width.toInt()}x${size.height.toInt()}');
      }
    });
  }

  testWidgets('lays out without overflow in dark mode', (
    WidgetTester tester,
  ) async {
    for (final Size size in sizes) {
      await pumpAt(tester, size, AppLanguage.english, ThemeMode.dark);
      expect(tester.takeException(), isNull,
          reason: 'dark mode overflowed at '
              '${size.width.toInt()}x${size.height.toInt()}');
    }
  });

  testWidgets('the title bar carries the switches and the window controls', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(600, 452), AppLanguage.english,
        ThemeMode.light);

    expect(find.text('EN'), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.crop_square_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    final List<Rect> rects = <Rect>[
      tester.getRect(find.text('EN')),
      tester.getRect(find.byIcon(Icons.light_mode_rounded)),
      tester.getRect(find.byIcon(Icons.remove_rounded)),
      tester.getRect(find.byIcon(Icons.crop_square_rounded)),
      tester.getRect(find.byIcon(Icons.close_rounded)),
    ];
    for (final Rect rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: 'off the left edge');
      expect(rect.right, lessThanOrEqualTo(600.0),
          reason: 'off the right edge');
      expect(rect.top, greaterThanOrEqualTo(0.0));
      expect(rect.bottom, lessThanOrEqualTo(TitleBar.height),
          reason: 'not inside the title bar');
    }

    expect(rects[0].left, lessThan(rects[1].left));
    expect(rects[1].left, lessThan(rects[2].left));
    expect(rects[2].left, lessThan(rects[3].left));
    expect(rects[3].left, lessThan(rects[4].left));
  });

  testWidgets('the title bar controls stay inside the bar in every language', (
    WidgetTester tester,
  ) async {
    for (final AppLanguage language in AppLanguage.values) {
      await pumpAt(tester, const Size(520, 400), language, ThemeMode.light);

      final Rect close = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(close.right, lessThanOrEqualTo(520.0),
          reason: '${language.name}: the close control is outside the window');
      expect(close.top, lessThanOrEqualTo(TitleBar.height - 1));

      final Rect code = tester.getRect(find.text(language.code.toUpperCase()));
      expect(code.right, lessThanOrEqualTo(520.0),
          reason: '${language.name}: the language control is outside the window');

      expect(tester.takeException(), isNull,
          reason: '${language.name} overflowed at the minimum size');
    }
  });

  testWidgets('the language menu lists every language in its own script', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(600, 452), AppLanguage.english,
        ThemeMode.light);

    await tester.tap(find.text('EN'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    for (final AppLanguage l in AppLanguage.values) {
      expect(find.text(l.nativeName), findsOneWidget,
          reason: '${l.nativeName} is missing from the language menu');
    }
  });

  testWidgets('the theme switch reflects the active mode', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(600, 452), AppLanguage.english,
        ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    await pumpAt(tester, const Size(600, 452), AppLanguage.english,
        ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    await pumpAt(tester, const Size(600, 452), AppLanguage.english,
        ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
  });

  testWidgets('row labels do not overlap their values in any language', (
    WidgetTester tester,
  ) async {
    for (final AppLanguage language in AppLanguage.values) {
      await pumpAt(tester, const Size(600, 452), language, ThemeMode.light);

      final Strings s = Strings.of(language);
      for (final Str key in <Str>[
        Str.rowInstallDir,
        Str.rowAppVersion,
        Str.rowMainProgram,
        Str.rowResourceFiles,
      ]) {
        final Finder label = find.text(s(key));
        if (label.evaluate().isEmpty) continue; 
        final Rect labelRect = tester.getRect(label);

        expect(labelRect.width, greaterThan(0));
        expect(labelRect.right, lessThanOrEqualTo(600.0),
            reason: '${language.name}: "${s(key)}" runs past the window edge');
      }
    }
  });
}
