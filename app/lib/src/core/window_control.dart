import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowControl {
  WindowControl._();

  static const MethodChannel _channel =
      MethodChannel('vmware_localizer/window');

  static final ValueNotifier<bool> isMaximized = ValueNotifier<bool>(false);

  static bool _handlerInstalled = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'maximizedChanged') {
        isMaximized.value = call.arguments as bool? ?? false;
      }
      return null;
    });
  }

  static void initialize({int minWidth = 0, int minHeight = 0}) {
    _installHandler();
    if (minWidth > 0 && minHeight > 0) {
      unawaited(setMinimumSize(minWidth, minHeight));
    }
  }

  static Future<void> setMinimumSize(int width, int height) =>
      _invoke('setMinimumSize', <String, dynamic>{
        'width': width,
        'height': height,
      });

  static Future<void> setTitle(String title) => _invoke('setTitle', title);

  static Future<void> setDark(bool dark) => _invoke('setDark', dark);

  static Future<void> minimize() => _invoke('minimize');

  static Future<void> toggleMaximize() => _invoke('toggleMaximize');

  static Future<void> close() => _invoke('close');

  static Future<void> startDrag() => _invoke('startDrag');

  static Future<void> _invoke(String method, [dynamic arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
