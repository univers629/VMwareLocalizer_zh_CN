import 'dart:io';

import 'i18n.dart';

class VmwareInstall {
  const VmwareInstall({
    required this.installPath,
    required this.version,
    required this.productVersion,
  });

  final String installPath;

  final String version;

  final String productVersion;

  String get baseDllPath => '$installPath\\vmwarebase.dll';
  String get exePath => '$installPath\\vmware.exe';
  String get messagesPath => '$installPath\\messages';
  String get zhCnPath => '$messagesPath\\zh_CN';
}

enum LocalizationState {
  notInstalled,

  original,

  localized,

  inconsistent,

  unsupported,
}

class InstallationReport {
  const InstallationReport({
    required this.install,
    required this.state,
    required this.baseDllHash,
    required this.zhCnPresent,
    required this.zhCnMatching,
    required this.vmwareRunning,
    this.detail,
  });

  final VmwareInstall? install;
  final LocalizationState state;

  final String? baseDllHash;

  final bool zhCnPresent;

  final bool zhCnMatching;

  final bool vmwareRunning;

  final Str? detail;

  bool get canLocalize =>
      state == LocalizationState.original ||
      state == LocalizationState.inconsistent;

  bool get canRestore =>
      state == LocalizationState.localized ||
      state == LocalizationState.inconsistent;
}

class PayloadFile {
  const PayloadFile(this.name, this.sha256);
  final String name;
  final String sha256;
}

const List<PayloadFile> payloadFiles = <PayloadFile>[
  PayloadFile(
      'vmui-zh_CN.dll',
      '18d5d7544cd1542181f68d9e8c65289590fa7ef869b5362832196b6fc9818019'),
  PayloadFile(
      'vmappsdk-zh_CN.dll',
      'efaed649414b133d1b023b8756a3afea60b43bedf64a170581bd506566c6f17e'),
  PayloadFile(
      'vmware.vmsg',
      'c29a99869e013d1de32eb5a7af2fee87af96e3e27fe662d6400141e33cc5cfb3'),
];

const Map<int, String> vmwareLanguageIds = <int, String>{
  0x0A: 'Español',
  0x0C: 'Français',
  0x11: '日本語',
  0x04: '简体中文',
};

const String supportedVersion = '26.0.1.2799';

bool get isWindows => Platform.isWindows;
