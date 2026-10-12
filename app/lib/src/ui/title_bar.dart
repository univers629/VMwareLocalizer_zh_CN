import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/window_control.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.strings,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final Strings strings;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);

    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowControl.startDrag(),
              onDoubleTap: WindowControl.toggleMaximize,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFF5B6BE8), Color(0xFF8B5BE8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.translate_rounded,
                          color: Colors.white, size: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings(Str.appTitle),
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _LanguageButton(
            strings: strings,
            language: language,
            onChanged: onLanguageChanged,
          ),
          const SizedBox(width: 4),
          _ThemeButton(
            strings: strings,
            mode: themeMode,
            onChanged: onThemeModeChanged,
          ),
          const SizedBox(width: 8),
          const _Separator(),
          _WindowButton(
            icon: Icons.remove_rounded,
            tooltip: strings(Str.windowMinimize),
            onPressed: WindowControl.minimize,
          ),
          _MaximizeButton(strings: strings),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: strings(Str.windowClose),
            onPressed: WindowControl.close,
            isClose: true,
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.strings,
    required this.language,
    required this.onChanged,
  });

  final Strings strings;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Tooltip(
      message: strings.format(
          Str.languageTooltip, <String, String>{'name': language.nativeName}),
      child: PopupMenuButton<AppLanguage>(
        initialValue: language,
        onSelected: onChanged,
        tooltip: '',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: t.colorScheme.outlineVariant),
        ),
        itemBuilder: (BuildContext c) => AppLanguage.values
            .map((AppLanguage l) => PopupMenuItem<AppLanguage>(
                  value: l,
                  height: 36,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 20,
                        child: l == language
                            ? Icon(Icons.check_rounded,
                                size: 15, color: t.colorScheme.primary)
                            : null,
                      ),
                      Text(l.nativeName, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ))
            .toList(),
        child: _Chip(
          child: Text(
            language.code.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.strings,
    required this.mode,
    required this.onChanged,
  });

  final Strings strings;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final (IconData icon, Str label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_rounded, Str.themeSystem),
      ThemeMode.light => (Icons.light_mode_rounded, Str.themeLight),
      ThemeMode.dark => (Icons.dark_mode_rounded, Str.themeDark),
    };

    return Tooltip(
      message: strings.format(
          Str.themeTooltip, <String, String>{'mode': strings(label)}),
      child: _HoverRegion(
        onTap: () {
          onChanged(switch (mode) {
            ThemeMode.system => ThemeMode.light,
            ThemeMode.light => ThemeMode.dark,
            ThemeMode.dark => ThemeMode.system,
          });
        },
        builder: (bool hovered) => _Chip(
          highlighted: hovered,
          width: 34,
          child: Icon(
            icon,
            size: 15,
            color: hovered
                ? t.colorScheme.onSurface
                : t.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.child,
    this.highlighted = false,
    this.width,
  });

  final Widget child;
  final bool highlighted;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Container(
      width: width,
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: width == null ? 9 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: t.colorScheme.outlineVariant),
        color: highlighted
            ? t.colorScheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent,
      ),
      child: child,
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: _HoverRegion(
        onTap: onPressed,
        builder: (bool hovered) => Container(
          width: 40,
          height: TitleBar.height,
          alignment: Alignment.center,
          color: hovered
              ? (isClose
                  ? const Color(0xFFE81123)
                  : t.colorScheme.onSurface.withValues(alpha: 0.08))
              : Colors.transparent,
          child: Icon(
            icon,
            size: 15,
            color: hovered && isClose
                ? Colors.white
                : t.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatelessWidget {
  const _MaximizeButton({required this.strings});
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WindowControl.isMaximized,
      builder: (BuildContext context, bool maximized, _) => _WindowButton(
        icon: maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
        tooltip: maximized ? strings(Str.windowRestore) : strings(Str.windowMaximize),
        onPressed: WindowControl.toggleMaximize,
      ),
    );
  }
}

class _HoverRegion extends StatefulWidget {
  const _HoverRegion({required this.builder, required this.onTap});

  final Widget Function(bool hovered) builder;
  final VoidCallback onTap;

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(_hovered),
      ),
    );
  }
}
