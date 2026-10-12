import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/i18n.dart';

void main() {
  group('translation tables', () {
    test('every language defines every key', () {
      for (final AppLanguage language in AppLanguage.values) {
        final Map<Str, String>? table = Strings.tableFor(language);
        expect(table, isNotNull,
            reason: 'no table registered for ${language.name}');

        final List<Str> missing = Str.values
            .where((Str k) => !table!.containsKey(k))
            .toList();
        expect(missing, isEmpty,
            reason: '${language.name} is missing: '
                '${missing.map((Str k) => k.name).join(', ')}');
      }
    });

    test('no language defines a key outside the enum', () {
      final Set<Str> known = Str.values.toSet();
      for (final AppLanguage language in AppLanguage.values) {
        final Map<Str, String> table = Strings.tableFor(language)!;
        final List<Str> extra =
            table.keys.where((Str k) => !known.contains(k)).toList();
        expect(extra, isEmpty, reason: '${language.name} has stale keys');
      }
    });

    test('no translation is empty', () {
      for (final AppLanguage language in AppLanguage.values) {
        Strings.tableFor(language)!.forEach((Str key, String value) {
          expect(value.trim(), isNotEmpty,
              reason: '${language.name}.${key.name} is blank');
        });
      }
    });

    test('placeholders are consistent across languages', () {
      final RegExp token = RegExp(r'\{(\w+)\}');
      for (final Str key in Str.values) {
        final Set<String> reference = token
            .allMatches(Strings.tableFor(AppLanguage.english)![key]!)
            .map((RegExpMatch m) => m.group(1)!)
            .toSet();
        for (final AppLanguage language in AppLanguage.values) {
          final Set<String> actual = token
              .allMatches(Strings.tableFor(language)![key]!)
              .map((RegExpMatch m) => m.group(1)!)
              .toSet();
          expect(actual, reference,
              reason: '${language.name}.${key.name} placeholders $actual '
                  'differ from English $reference');
        }
      }
    });

    test('lookup falls back to English for an unknown key', () {
      final Strings zh = Strings.of(AppLanguage.chineseSimplified);
      expect(zh(Str.appTitle), Strings.tableFor(AppLanguage.chineseSimplified)![Str.appTitle]);
      expect(Strings.of(AppLanguage.english)(Str.appTitle), isNotEmpty);
    });

    test('format substitutes every named value', () {
      final Strings en = Strings.of(AppLanguage.english);
      final String result = en.format(
        Str.themeTooltip,
        <String, String>{'mode': 'Dark'},
      );
      expect(result, contains('Dark'));
      expect(result, isNot(contains('{mode}')));
    });
  });

  group('system language detection', () {
    test('locale names map to a supported language', () {
      expect(AppLanguage.fromLocaleName('zh-CN'), AppLanguage.chineseSimplified);
      expect(AppLanguage.fromLocaleName('zh_Hans_CN'),
          AppLanguage.chineseSimplified);
      expect(AppLanguage.fromLocaleName('zh-TW'),
          AppLanguage.chineseSimplified,
          reason: 'Chinese locales share one interface language');
      expect(AppLanguage.fromLocaleName('en-US'), AppLanguage.english);
    });

    test('an unsupported locale falls back to English', () {
      expect(AppLanguage.fromLocaleName('ja-JP'), AppLanguage.english);
      expect(AppLanguage.fromLocaleName('es-ES'), AppLanguage.english);
      expect(AppLanguage.fromLocaleName('fr-FR'), AppLanguage.english);
      expect(AppLanguage.fromLocaleName('de-DE'), AppLanguage.english);
      expect(AppLanguage.fromLocaleName('ko'), AppLanguage.english);
      expect(AppLanguage.fromLocaleName(''), AppLanguage.english);
      expect(AppLanguage.fromLocaleName('zhx'), AppLanguage.english);
    });

    test('detection never throws', () {
      expect(AppLanguage.detect(), isA<AppLanguage>());
    });

    test('every language reports a native name and an ISO code', () {
      for (final AppLanguage l in AppLanguage.values) {
        expect(l.code, matches(RegExp(r'^[a-z]{2}$')));
        expect(l.nativeName.trim(), isNotEmpty);
      }
      final Set<String> codes =
          AppLanguage.values.map((AppLanguage l) => l.code).toSet();
      expect(codes.length, AppLanguage.values.length);
    });
  });
}
