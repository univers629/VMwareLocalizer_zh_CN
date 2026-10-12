import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/localizer_service.dart';
import '../core/models.dart';
import '../core/patch_table.dart';
import 'theme.dart';
import 'title_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocalizerService _service = LocalizerService();

  InstallationReport? _report;
  bool _busy = false;
  bool _detecting = true;
  double _progress = 0;
  String _progressLabel = '';
  final List<String> _log = <String>[];

  Strings get _s => Strings.of(widget.language);

  @override
  void initState() {
    super.initState();
    unawaited(_detect());
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
    });
    final InstallationReport r = await _service.detect();
    if (!mounted) return;
    setState(() {
      _report = r;
      _detecting = false;
    });
  }

  Future<void> _run({required bool localizing}) async {
    final InstallationReport? r = _report;
    if (r?.install == null) return;

    if (!await _service.canWriteInstall(r!.install!)) {
      if (!mounted) return;
      final bool go = await _confirmElevation();
      if (!go) return;
      final bool started =
          _service.requestElevation(language: widget.language);
      if (!mounted) return;
      if (!started) {
        _toast(_s(Str.toastElevationDenied));
        return;
      }
      unawaited(Future<void>.delayed(
          const Duration(milliseconds: 600), () => _quit()));
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _progressLabel = '';
      _log.clear();
    });

    final Stream<OpProgress> s = localizing
        ? _service.localize(r, language: widget.language)
        : _service.restore(r, language: widget.language);

    await for (final OpProgress p in s) {
      if (!mounted) return;
      setState(() {
        _progress = p.fraction;
        _progressLabel = p.message;
        if (p.log != null) _log.add(p.log!);
      });
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
    });
    await _detect();

    if (!mounted) return;
    final bool ok = _report?.state ==
        (localizing
            ? LocalizationState.localized
            : LocalizationState.original);
    _toast(ok
        ? (localizing ? _s(Str.toastLocalizeDone) : _s(Str.toastRestoreDone))
        : _s(Str.toastUnexpected));
  }

  void _quit() {
    exit(0);
  }

  Future<bool> _confirmElevation() async {
    final Strings s = _s;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(s(Str.elevationTitle)),
        content: Text(s(Str.elevationBody)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s(Str.elevationCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(s(Str.elevationContinue)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TitleBar(
                strings: _s,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
                language: widget.language,
                onLanguageChanged: widget.onLanguageChanged,
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            constraints.maxWidth < 620 ? constraints.maxWidth : 620;
        return Center(
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_detecting)
                      _LoadingCard(strings: _s)
                    else if (_report != null) ...<Widget>[
                      _StatusCard(report: _report!, strings: _s),
                      const SizedBox(height: 10),
                      _ActionCard(
                        report: _report!,
                        strings: _s,
                        busy: _busy,
                        onLocalize: () => _run(localizing: true),
                        onRestore: () => _run(localizing: false),
                        onRefresh: _busy ? null : _detect,
                      ),
                    ],
                    if (_busy || _log.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      _ProgressCard(
                        strings: _s,
                        progress: _progress,
                        label: _progressLabel,
                        log: _log,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}



class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.strings});
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(strings(Str.detecting),
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.report, required this.strings});

  final InstallationReport report;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final _StateStyle st = _StateStyle.of(report.state, t, strings);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(st.icon, size: 18, color: st.color),
                    const SizedBox(width: 8),
                    Text(
                      st.label,
                      style: t.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: st.color,
                      ),
                    ),
                  ],
                ),
                if (report.vmwareRunning)
                  _Chip(
                    label: strings(Str.chipVmwareRunning),
                    color: AppTheme.warning,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
            if (report.install != null) ...<Widget>[
              const SizedBox(height: 12),
              _Row(
                  label: strings(Str.rowInstallDir),
                  value: report.install!.installPath),
              _Row(
                label: strings(Str.rowAppVersion),
                value: report.install!.version.isEmpty
                    ? strings(Str.valueUnknown)
                    : report.install!.version,
                warn: report.install!.version.isNotEmpty &&
                    report.install!.version != supportedVersion,
              ),
              _Row(
                label: strings(Str.rowMainProgram),
                value: _dllStateLabel(),
              ),
              _Row(
                label: strings(Str.rowResourceFiles),
                value: report.zhCnPresent
                    ? (report.zhCnMatching
                        ? strings(Str.valueInstalledVerified)
                        : strings(Str.valuePresentInvalid))
                    : strings(Str.valueNotInstalled),
              ),
            ],
            if (report.detail != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: st.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: st.color.withValues(alpha: 0.25)),
                ),
                child: Text(
                  strings(report.detail!),
                  style: t.textTheme.bodySmall?.copyWith(height: 1.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dllStateLabel() {
    if (report.baseDllHash == null) return strings(Str.valueMissing);
    if (report.baseDllHash == sha256Original) {
      return strings(Str.valueOriginal);
    }
    if (report.baseDllHash == sha256Localized) {
      return strings(Str.valueLocalized);
    }
    return strings(Str.valueUnknownVersion);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final TextStyle? labelStyle = t.textTheme.bodySmall?.copyWith(
      color: t.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double labelWidth =
              (constraints.maxWidth * 0.42).clamp(84.0, 190.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: labelWidth,
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  value,
                  style: t.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    fontSize: 12.5,
                    color: warn ? AppTheme.warning : null,
                    fontWeight: warn ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.report,
    required this.strings,
    required this.busy,
    required this.onLocalize,
    required this.onRestore,
    required this.onRefresh,
  });

  final InstallationReport report;
  final Strings strings;
  final bool busy;
  final VoidCallback onLocalize;
  final VoidCallback onRestore;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final bool blocked = report.state == LocalizationState.notInstalled ||
        report.state == LocalizationState.unsupported;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (blocked)
              Row(
                children: <Widget>[
                  const Icon(Icons.block_rounded,
                      size: 17, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.state == LocalizationState.notInstalled
                          ? strings(Str.actionBlockedNotInstalled)
                          : strings(Str.actionBlockedUnsupported),
                      style: t.textTheme.bodySmall?.copyWith(
                        color: AppTheme.danger,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy || !report.canLocalize ? null : onLocalize,
                      icon: const Icon(Icons.translate_rounded, size: 18),
                      label: Text(strings(Str.actionLocalize)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy || !report.canRestore ? null : onRestore,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: Text(strings(Str.actionRestore)),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    busy
                        ? strings(Str.actionHintBusy)
                        : (report.canLocalize && report.canRestore
                            ? strings(Str.actionHintBoth)
                            : (report.canLocalize
                                ? strings(Str.actionHintLocalize)
                                : strings(Str.actionHintRestore))),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(strings(Str.actionRedetect)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.strings,
    required this.progress,
    required this.label,
    required this.log,
  });

  final Strings strings;
  final double progress;
  final String label;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: t.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: t.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (log.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: log
                        .map((String l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: SelectableText(
                                l,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11.5,
                                  height: 1.5,
                                  color: t.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateStyle {
  const _StateStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  static _StateStyle of(LocalizationState s, ThemeData t, Strings strings) {
    switch (s) {
      case LocalizationState.localized:
        return _StateStyle(strings(Str.stateLocalized), AppTheme.success,
            Icons.check_circle_rounded);
      case LocalizationState.original:
        return _StateStyle(strings(Str.stateOriginal),
            t.colorScheme.onSurfaceVariant, Icons.shield_outlined);
      case LocalizationState.inconsistent:
        return _StateStyle(strings(Str.stateInconsistent), AppTheme.warning,
            Icons.warning_amber_rounded);
      case LocalizationState.unsupported:
        return _StateStyle(strings(Str.stateUnsupported), AppTheme.danger,
            Icons.error_outline_rounded);
      case LocalizationState.notInstalled:
        return _StateStyle(strings(Str.stateNotInstalled),
            t.colorScheme.onSurfaceVariant, Icons.help_outline_rounded);
    }
  }
}
