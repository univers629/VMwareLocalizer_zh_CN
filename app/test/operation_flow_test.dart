import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vmware_localizer/src/core/i18n.dart';
import 'package:vmware_localizer/src/core/localizer_service.dart';
import 'package:vmware_localizer/src/core/models.dart';
import 'package:vmware_localizer/src/ui/home_page.dart';
import 'package:vmware_localizer/src/ui/theme.dart';

const VmwareInstall _install = VmwareInstall(
  installPath: r'C:\Program Files\VMware\VMware Workstation',
  version: '26.0.1.2799',
  productVersion: '26.0.1',
);

InstallationReport _report(LocalizationState state) => InstallationReport(
      install: _install,
      state: state,
      baseDllHash: null,
      zhCnPresent: false,
      zhCnMatching: false,
      vmwareRunning: false,
    );

class _FakeService extends LocalizerService {
  _FakeService({
    required this.startState,
    this.writable = true,
    this.running = false,
    this.failWith,
    this.afterState,
  });

  final LocalizationState startState;
  final bool writable;
  final bool running;
  final Str? failWith;

  // State reported by the second detection, which follows the operation.
  final LocalizationState? afterState;

  int detectCalls = 0;
  int closeCalls = 0;
  final List<PendingAction?> elevationRequests = <PendingAction?>[];
  bool elevationStarted = true;

  @override
  Future<InstallationReport> detect() async {
    detectCalls++;
    // The second detection follows the operation and reports its outcome.
    final LocalizationState state = detectCalls == 1
        ? startState
        : (afterState ?? startState);
    return _report(state);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> canWriteInstall(VmwareInstall install) async => writable;

  @override
  Future<bool> vmwareProcessesRunning() async => running;

  @override
  Future<void> closeVmwareProcesses() async {
    closeCalls++;
  }

  @override
  bool requestElevation({AppLanguage? language, PendingAction? action}) {
    elevationRequests.add(action);
    return elevationStarted;
  }

  @override
  Stream<OpProgress> localize(InstallationReport report,
      {AppLanguage? language}) async* {
    if (failWith != null) {
      yield OpProgress(1.0, 'Failed: ${Strings.of(AppLanguage.english)(failWith!)}',
          failed: true);
      return;
    }
    yield const OpProgress(1.0, 'done');
  }

  @override
  Stream<OpProgress> restore(InstallationReport report,
      {AppLanguage? language}) async* {
    if (failWith != null) {
      yield OpProgress(1.0, 'Failed: ${Strings.of(AppLanguage.english)(failWith!)}',
          failed: true);
      return;
    }
    yield const OpProgress(1.0, 'done');
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeService service, {
  PendingAction? pendingAction,
  Future<void> Function()? onQuit,
  Size size = const Size(600, 452),
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: HomePage(
      themeMode: ThemeMode.light,
      onThemeModeChanged: (_) {},
      language: language,
      onLanguageChanged: (_) {},
      service: service,
      pendingAction: pendingAction,
      onQuit: onQuit,
    ),
  ));

  // Let the detection future settle and the first frame paint.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('closing a running VMware is confirmed first', () {
    testWidgets('the confirmation appears instead of closing silently',
        (WidgetTester tester) async {
      final _FakeService service =
          _FakeService(startState: LocalizationState.original, running: true);
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.confirmCloseTitle)),
          findsOneWidget);
      expect(service.closeCalls, 0,
          reason: 'no process may be terminated before the user agrees');
    });

    testWidgets('cancelling leaves the processes alone and does nothing',
        (WidgetTester tester) async {
      final _FakeService service =
          _FakeService(startState: LocalizationState.original, running: true);
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.confirmCloseCancel)));
      await tester.pumpAndSettle();

      expect(service.closeCalls, 0);
      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsNothing);
    });

    testWidgets('agreeing terminates the processes before continuing',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        running: true,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      await tester.tap(
          find.text(Strings.of(AppLanguage.english)(Str.confirmCloseContinue)));
      await tester.pumpAndSettle();

      expect(service.closeCalls, 1);
    });

    testWidgets('no confirmation is shown when VMware is not running',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        running: false,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.confirmCloseTitle)),
          findsNothing);
    });
  });

  group('the result is reported before the application goes away', () {
    testWidgets('a successful operation shows a completion dialog',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsOneWidget);
      expect(find.text(Strings.of(AppLanguage.english)(Str.resultBodyDone)),
          findsOneWidget);
    });

    testWidgets('a failed operation shows the failure and its reason',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        failWith: Str.errDllHashMismatch,
      );
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleFailed)),
          findsOneWidget);
      expect(
          find.textContaining(
              Strings.of(AppLanguage.english)(Str.errDllHashMismatch)),
          findsOneWidget);
    });

    testWidgets('the dialog stays until it is dismissed',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionLocalize)));
      await tester.pumpAndSettle();
      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsOneWidget);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.resultClose)));
      await tester.pumpAndSettle();
      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsNothing);
    });
  });

  group('the dialogs fit the smallest window', () {
    for (final AppLanguage language in AppLanguage.values) {
      testWidgets('the close confirmation fits in ${language.name}',
          (WidgetTester tester) async {
        final _FakeService service =
            _FakeService(startState: LocalizationState.original, running: true);
        await _pump(tester, service, size: const Size(520, 400), language: language);

        await tester.tap(find.text(Strings.of(language)(Str.actionLocalize)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the confirmation overflowed at the minimum window size');
        expect(find.text(Strings.of(language)(Str.confirmCloseTitle)),
            findsOneWidget);
        expect(find.text(Strings.of(language)(Str.confirmCloseContinue)),
            findsOneWidget);
      });

      testWidgets('the result dialog fits in ${language.name}',
          (WidgetTester tester) async {
        final _FakeService service = _FakeService(
          startState: LocalizationState.original,
          afterState: LocalizationState.localized,
        );
        await _pump(tester, service, size: const Size(520, 400), language: language);

        await tester.tap(find.text(Strings.of(language)(Str.actionLocalize)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the result overflowed at the minimum window size');
        expect(find.text(Strings.of(language)(Str.resultTitleDone)), findsOneWidget);
      });
    }
  });

  group('elevation hands the operation over', () {
    testWidgets('the request carries the operation that was asked for',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.localized,
        writable: false,
      );
      bool quit = false;
      await _pump(tester, service, onQuit: () async => quit = true);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionRestore)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.elevationTitle)),
          findsOneWidget);

      await tester
          .tap(find.text(Strings.of(AppLanguage.english)(Str.elevationContinue)));
      await tester.pumpAndSettle();

      expect(service.elevationRequests, <PendingAction?>[PendingAction.restore]);
      expect(quit, isTrue,
          reason: 'the original instance must step aside for the elevated one');
    });

    testWidgets('declining the request leaves the instance running',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.localized,
        writable: false,
      );
      bool quit = false;
      await _pump(tester, service, onQuit: () async => quit = true);

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.actionRestore)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.elevationCancel)));
      await tester.pumpAndSettle();

      expect(service.elevationRequests, isEmpty);
      expect(quit, isFalse);
    });
  });

  group('an elevated launch performs the operation it was given', () {
    testWidgets('the pending operation runs once the state has been read',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service, pendingAction: PendingAction.localize);
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsOneWidget,
          reason: 'an elevated launch must not stop at the interface');
    });

    testWidgets('the pending operation is performed only once',
        (WidgetTester tester) async {
      final _FakeService service = _FakeService(
        startState: LocalizationState.original,
        afterState: LocalizationState.localized,
      );
      await _pump(tester, service, pendingAction: PendingAction.localize);
      await tester.pumpAndSettle();

      await tester.tap(find.text(Strings.of(AppLanguage.english)(Str.resultClose)));
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsNothing);
      expect(service.detectCalls, 2,
          reason: 'a second detection would mean the operation ran again');
    });

    testWidgets('no pending operation means nothing runs on its own',
        (WidgetTester tester) async {
      final _FakeService service =
          _FakeService(startState: LocalizationState.original);
      await _pump(tester, service);
      await tester.pumpAndSettle();

      expect(find.text(Strings.of(AppLanguage.english)(Str.resultTitleDone)),
          findsNothing);
      expect(service.detectCalls, 1);
    });
  });
}
