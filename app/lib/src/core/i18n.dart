import 'dart:io';

enum AppLanguage {
  english('en', 'English'),
  chineseSimplified('zh', '简体中文');

  const AppLanguage(this.code, this.nativeName);

  final String code;

  final String nativeName;

  static AppLanguage fromLocaleName(String localeName) {
    final String primary =
        localeName.split(RegExp('[-_]')).first.toLowerCase().trim();
    for (final AppLanguage l in AppLanguage.values) {
      if (l.code == primary) return l;
    }
    return AppLanguage.english;
  }

  static AppLanguage detect() {
    try {
      final String? override = Platform.environment['VMWL_LANGUAGE'];
      if (override != null && override.isNotEmpty) {
        return fromLocaleName(override);
      }
      return fromLocaleName(Platform.localeName);
    } catch (_) {
      return AppLanguage.english;
    }
  }
}

enum Str {
  appTitle,
  appSubtitle,
  windowTitle,

  themeTooltip,
  themeSystem,
  themeLight,
  themeDark,
  languageTooltip,

  windowMinimize,
  windowMaximize,
  windowRestore,
  windowClose,

  unsupportedPlatform,

  elevationTitle,
  elevationBody,
  elevationCancel,
  elevationContinue,
  toastElevationDenied,

  confirmCloseTitle,
  confirmCloseBody,
  confirmCloseCancel,
  confirmCloseContinue,

  resultTitleDone,
  resultTitleFailed,
  resultBodyDone,
  resultBodyFailed,
  resultBodyDetail,
  resultClose,

  toastLocalizeDone,
  toastRestoreDone,
  toastUnexpected,

  stateLocalized,
  stateOriginal,
  stateInconsistent,
  stateUnsupported,
  stateNotInstalled,
  chipVmwareRunning,
  rowInstallDir,
  rowAppVersion,
  rowMainProgram,
  rowResourceFiles,
  valueUnknown,
  valueUnknownVersion,
  valueMissing,
  valueOriginal,
  valueLocalized,
  valueNotInstalled,
  valueInstalledVerified,
  valuePresentInvalid,

  detailDllMissing,
  detailOriginalWithResources,
  detailLocalizedMissingResources,
  detailUnsupportedVersion,

  actionLocalize,
  actionRestore,
  actionRedetect,
  actionBlockedNotInstalled,
  actionBlockedUnsupported,
  actionHintBusy,
  actionHintBoth,
  actionHintLocalize,
  actionHintRestore,
  detecting,
  footerNote,

  logCheckingProcess,
  logClosingProcess,
  logStoppingServices,
  logStoppingService,
  logWritingPatch,
  logRestoringPatch,
  logInstallingResources,
  logRemovingResources,
  logStartingServices,
  logStartingService,
  logWritingFile,
  logRemovedFile,
  logPatchApplied,
  logNoChangeNeeded,
  logPatchVerified,
  logRemovedZhDir,
  logRemovedMessagesDir,
  logDirKept,
  logResourcesAbsent,
  logSkipped,
  doneLocalized,
  doneRestored,
  failPrefix,

  errNotInstalled,
  errStillRunning,
  errDllNotFound,
  errDllSizeAbnormal,
  errDllHashMismatch,
  errPatchDataMismatch,
  errVerifyAfterWrite,
  errTempIncomplete,
  errPayloadNotExtracted,
  errPayloadVerify,
  errPayloadExtract,
  errStillNoAccess,
}

class Strings {
  const Strings(this.language) : _values = null;

  const Strings._(this.language, this._values);

  final AppLanguage language;
  final Map<Str, String>? _values;

  String call(Str key) => _values?[key] ?? _translations[AppLanguage.english]![key]!;

  String format(Str key, Map<String, String> values) {
    String text = call(key);
    values.forEach((String name, String value) {
      text = text.replaceAll('{$name}', value);
    });
    return text;
  }

  static const Map<AppLanguage, Strings> _byLanguage = <AppLanguage, Strings>{
    AppLanguage.english: Strings._(AppLanguage.english, _en),
    AppLanguage.chineseSimplified:
        Strings._(AppLanguage.chineseSimplified, _zh),
  };

  static Strings of(AppLanguage l) => _byLanguage[l]!;

  static Map<Str, String>? tableFor(AppLanguage l) => _translations[l];

  static int get keyCount => Str.values.length;

  static const Map<AppLanguage, Map<Str, String>> _translations =
      <AppLanguage, Map<Str, String>>{
    AppLanguage.english: _en,
    AppLanguage.chineseSimplified: _zh,
  };


  static const Map<Str, String> _en = <Str, String>{
    Str.appTitle: 'VMware Workstation Localizer',
    Str.appSubtitle: 'Applies and removes a language pack',
    Str.windowTitle: 'VMware Workstation Localizer',
    Str.themeTooltip: 'Theme: {mode} (click to change)',
    Str.themeSystem: 'System',
    Str.themeLight: 'Light',
    Str.themeDark: 'Dark',
    Str.languageTooltip: 'Interface language: {name}',
    Str.windowMinimize: 'Minimize',
    Str.windowMaximize: 'Maximize',
    Str.windowRestore: 'Restore',
    Str.windowClose: 'Close',
    Str.unsupportedPlatform: 'This tool runs on Windows only.',
    Str.elevationTitle: 'Administrator rights required',
    Str.elevationBody:
        'Modifying the VMware installation directory and controlling its services '
        'requires administrator rights.\n\nWindows will ask you to confirm after you '
        'press Continue.',
    Str.elevationCancel: 'Cancel',
    Str.elevationContinue: 'Continue',
    Str.toastElevationDenied:
        'Administrator rights were not granted, so the operation was cancelled.',
    Str.confirmCloseTitle: 'VMware is running',
    Str.confirmCloseBody:
        'VMware Workstation is currently running. Completing this operation '
        'requires VMware Workstation and its services to be closed.\n\n'
        'The running Virtual Machines will be shut down forcibly, and any '
        'unsaved data inside them will be lost.\n\n'
        'Please save your work and close VMware Workstation before continuing.',
    Str.confirmCloseCancel: 'Cancel',
    Str.confirmCloseContinue: 'Close and continue',
    Str.resultTitleDone: 'Completed',
    Str.resultTitleFailed: 'Failed',
    Str.resultBodyDone:
        'The operation finished successfully. The VMware Workstation interface '
        'has been updated.',
    Str.resultBodyFailed:
        'The operation did not complete. The installation was left untouched or '
        'rolled back; see the details below.',
    Str.resultBodyDetail: '{detail}',
    Str.resultClose: 'Close',
    Str.toastLocalizeDone: 'Language pack applied',
    Str.toastRestoreDone: 'Restored to the original state',
    Str.toastUnexpected:
        'The result is not the expected state. See the log for details.',
    Str.stateLocalized: 'Language pack applied',
    Str.stateOriginal: 'Original',
    Str.stateInconsistent: 'Incomplete state',
    Str.stateUnsupported: 'Unsupported version',
    Str.stateNotInstalled: 'Not installed',
    Str.chipVmwareRunning: 'VMware is running',
    Str.rowInstallDir: 'Install directory',
    Str.rowAppVersion: 'Product version',
    Str.rowMainProgram: 'Main program',
    Str.rowResourceFiles: 'Language files',
    Str.valueUnknown: 'Unknown',
    Str.valueUnknownVersion: 'Unrecognised version',
    Str.valueMissing: 'Missing',
    Str.valueOriginal: 'Original',
    Str.valueLocalized: 'Localized',
    Str.valueNotInstalled: 'Not installed',
    Str.valueInstalledVerified: 'Installed and verified',
    Str.valuePresentInvalid: 'Present but failed verification',
    Str.detailDllMissing:
        'vmwarebase.dll was not found. The installation may be damaged; reinstalling '
        'VMware Workstation is recommended.',
    Str.detailOriginalWithResources:
        'The main program is the original build, but language files are already '
        'present. Apply the language pack to finish, or restore to remove them.',
    Str.detailLocalizedMissingResources:
        'The main program is localized, but its language files are missing or have '
        'been modified. Apply the language pack again.',
    Str.detailUnsupportedVersion:
        'vmwarebase.dll does not match a version this tool recognises, so it will '
        'not be modified.',
    Str.actionLocalize: 'Apply',
    Str.actionRestore: 'Restore',
    Str.actionRedetect: 'Check again',
    Str.actionBlockedNotInstalled:
        'VMware Workstation was not found, so no operation is available.',
    Str.actionBlockedUnsupported:
        'This version is not supported. Operations are disabled to protect your '
        'installation.',
    Str.actionHintBusy: 'Working. Do not close the window.',
    Str.actionHintBoth: 'The current state is incomplete; either operation is available.',
    Str.actionHintLocalize: 'This will switch the VMware interface to the bundled language.',
    Str.actionHintRestore: 'This will return the VMware interface to its original language.',
    Str.detecting: 'Checking the installation…',
    Str.footerNote:
        'This tool localises an installed VMware Workstation directly. Every file is '
        'verified with SHA-256 before and after writing, and no other settings are '
        'changed.',
    Str.logCheckingProcess: 'Checking whether VMware is running…',
    Str.logClosingProcess: 'Closing VMware processes…',
    Str.logStoppingServices: 'Stopping VMware services…',
    Str.logStoppingService: 'Stopping {name}…',
    Str.logWritingPatch: 'Writing the localisation data…',
    Str.logRestoringPatch: 'Restoring the original data…',
    Str.logInstallingResources: 'Installing language files…',
    Str.logRemovingResources: 'Removing language files…',
    Str.logStartingServices: 'Starting VMware services…',
    Str.logStartingService: 'Starting {name}…',
    Str.logWritingFile: 'Writing {name} ({size})',
    Str.logRemovedFile: 'Removed {name}',
    Str.logPatchApplied: 'Main program verified: {from} → {to}',
    Str.logNoChangeNeeded: 'vmwarebase.dll already has the requested state',
    Str.logPatchVerified: 'Main program verified.',
    Str.logRemovedZhDir: 'Removed the empty language directory.',
    Str.logRemovedMessagesDir: 'Removed the empty messages directory.',
    Str.logDirKept: 'The language directory still holds other files, so it was kept.',
    Str.logResourcesAbsent: 'No language files are installed; nothing to remove.',
    Str.logSkipped: 'Already in the requested state; nothing to do.',
    Str.doneLocalized: 'Language pack applied.',
    Str.doneRestored: 'Restored to the original state.',
    Str.failPrefix: 'Failed: ',
    Str.errNotInstalled: 'VMware Workstation is not installed.',
    Str.errStillRunning:
        'VMware is still running. Close VMware Workstation completely and try again.',
    Str.errDllNotFound: 'vmwarebase.dll was not found.',
    Str.errDllSizeAbnormal:
        'vmwarebase.dll has an unexpected size ({actual} bytes, expected {expected}). '
        'The operation was stopped to avoid damaging the installation.',
    Str.errDllHashMismatch:
        'vmwarebase.dll does not match the expected checksum. The operation was '
        'stopped to avoid damaging the installation.',
    Str.errPatchDataMismatch:
        'The change data does not match the file (offset {offset}). The operation '
        'was stopped.',
    Str.errVerifyAfterWrite:
        'Verification after writing failed, so the file was not replaced.',
    Str.errTempIncomplete: 'The temporary file was incomplete; the operation was stopped.',
    Str.errPayloadNotExtracted: 'The bundled language files have not been unpacked.',
    Str.errPayloadVerify:
        'Verification of the bundled language files failed. The application package '
        'may be damaged.',
    Str.errPayloadExtract: 'The bundled language files could not be unpacked ({detail}).',
    Str.errStillNoAccess:
        'The installation directory could not be written to even with administrator '
        'rights, so nothing was changed.',
  };


  static const Map<Str, String> _zh = <Str, String>{
    Str.appTitle: 'VMware Workstation 汉化工具',
    Str.appSubtitle: '应用与移除语言包',
    Str.windowTitle: 'VMware Workstation 汉化工具',
    Str.themeTooltip: '主题：{mode}（点击切换）',
    Str.themeSystem: '跟随系统',
    Str.themeLight: '浅色',
    Str.themeDark: '深色',
    Str.languageTooltip: '界面语言：{name}',
    Str.windowMinimize: '最小化',
    Str.windowMaximize: '最大化',
    Str.windowRestore: '向下还原',
    Str.windowClose: '关闭',
    Str.unsupportedPlatform: '本工具仅支持 Windows。',
    Str.elevationTitle: '需要管理员权限',
    Str.elevationBody:
        '修改 VMware 的安装目录并控制其服务需要管理员权限。\n\n'
        '点击“继续”后 Windows 会弹出权限确认窗口。',
    Str.elevationCancel: '取消',
    Str.elevationContinue: '继续',
    Str.toastElevationDenied: '未获得管理员权限，操作已取消。',
    Str.confirmCloseTitle: 'VMware 正在运行',
    Str.confirmCloseBody:
        'VMware Workstation 当前正在运行。完成本次操作需要关闭 VMware Workstation '
        '及其服务。\n\n'
        '正在运行的虚拟机会被强制关闭，其中的未保存数据将会丢失。\n\n'
        '请先保存工作并关闭 VMware Workstation，然后继续。',
    Str.confirmCloseCancel: '取消',
    Str.confirmCloseContinue: '关闭并继续',
    Str.resultTitleDone: '操作完成',
    Str.resultTitleFailed: '操作失败',
    Str.resultBodyDone: '操作已成功完成，VMware Workstation 的界面已更新。',
    Str.resultBodyFailed: '操作未能完成。安装目录未被改动或已回滚，详情见下方。',
    Str.resultBodyDetail: '{detail}',
    Str.resultClose: '关闭',
    Str.toastLocalizeDone: '语言包已应用',
    Str.toastRestoreDone: '已恢复为原版',
    Str.toastUnexpected: '操作未达到预期状态，请查看日志。',
    Str.stateLocalized: '已应用语言包',
    Str.stateOriginal: '原版',
    Str.stateInconsistent: '状态不完整',
    Str.stateUnsupported: '不受支持的版本',
    Str.stateNotInstalled: '未安装',
    Str.chipVmwareRunning: 'VMware 运行中',
    Str.rowInstallDir: '安装目录',
    Str.rowAppVersion: '程序版本',
    Str.rowMainProgram: '主程序状态',
    Str.rowResourceFiles: '语言文件',
    Str.valueUnknown: '未知',
    Str.valueUnknownVersion: '未知版本',
    Str.valueMissing: '缺失',
    Str.valueOriginal: '原版',
    Str.valueLocalized: '已汉化',
    Str.valueNotInstalled: '未安装',
    Str.valueInstalledVerified: '已安装且校验通过',
    Str.valuePresentInvalid: '存在但校验失败',
    Str.detailDllMissing:
        '找不到 vmwarebase.dll。安装可能已损坏，建议重新安装 VMware Workstation。',
    Str.detailOriginalWithResources:
        '主程序为原版，但已存在语言文件。可执行“应用”以完成安装，或“恢复”以清理。',
    Str.detailLocalizedMissingResources:
        '主程序已汉化，但语言文件缺失或被修改。请重新执行“应用”。',
    Str.detailUnsupportedVersion:
        'vmwarebase.dll 的版本无法识别，为避免损坏安装，本工具不会修改它。',
    Str.actionLocalize: '应用',
    Str.actionRestore: '恢复',
    Str.actionRedetect: '重新检测',
    Str.actionBlockedNotInstalled: '未检测到 VMware Workstation，无法执行操作。',
    Str.actionBlockedUnsupported: '当前版本不受支持，已禁用操作以保护你的安装。',
    Str.actionHintBusy: '操作进行中，请勿关闭窗口…',
    Str.actionHintBoth: '当前状态不完整，可执行任一操作。',
    Str.actionHintLocalize: '将把 VMware 界面切换为内置语言。',
    Str.actionHintRestore: '将把 VMware 界面恢复为原始语言。',
    Str.detecting: '正在检测安装状态…',
    Str.footerNote:
        '本工具直接对已安装的 VMware Workstation 进行本地化。所有文件在写入前后都会校验 '
        'SHA-256，且不会改动任何其他设置。',
    Str.logCheckingProcess: '检查 VMware 运行状态…',
    Str.logClosingProcess: '正在关闭 VMware 进程…',
    Str.logStoppingServices: '停止 VMware 服务…',
    Str.logStoppingService: '停止 {name}…',
    Str.logWritingPatch: '写入主程序本地化数据…',
    Str.logRestoringPatch: '还原主程序原始数据…',
    Str.logInstallingResources: '安装语言文件…',
    Str.logRemovingResources: '移除语言文件…',
    Str.logStartingServices: '启动 VMware 服务…',
    Str.logStartingService: '启动 {name}…',
    Str.logWritingFile: '写入 {name}（{size}）',
    Str.logRemovedFile: '已删除 {name}',
    Str.logPatchApplied: '主程序校验通过：{from} → {to}',
    Str.logNoChangeNeeded: 'vmwarebase.dll 已是目标状态',
    Str.logPatchVerified: '主程序校验通过。',
    Str.logRemovedZhDir: '已移除空的语言目录。',
    Str.logRemovedMessagesDir: '已移除空的 messages 目录。',
    Str.logDirKept: '语言目录中仍有其他文件，已保留。',
    Str.logResourcesAbsent: '未安装语言文件，无需移除。',
    Str.logSkipped: '已是目标状态，无需修改。',
    Str.doneLocalized: '语言包已应用。',
    Str.doneRestored: '已恢复为原版。',
    Str.failPrefix: '失败：',
    Str.errNotInstalled: 'VMware Workstation 未安装。',
    Str.errStillRunning: 'VMware 仍在运行。请先完全退出 VMware Workstation 后重试。',
    Str.errDllNotFound: '找不到 vmwarebase.dll。',
    Str.errDllSizeAbnormal:
        'vmwarebase.dll 大小异常（{actual} 字节，预期 {expected}）。为避免损坏安装，已中止。',
    Str.errDllHashMismatch: 'vmwarebase.dll 的校验值与预期不符，为避免损坏安装，已中止。',
    Str.errPatchDataMismatch: '改动数据与文件不匹配（偏移 {offset}）。已中止。',
    Str.errVerifyAfterWrite: '写入后的校验失败，文件未被替换。',
    Str.errTempIncomplete: '临时文件写入不完整，已中止。',
    Str.errPayloadNotExtracted: '内置语言文件尚未解压。',
    Str.errPayloadVerify: '内置语言文件校验失败，程序包可能已损坏。',
    Str.errPayloadExtract: '无法解压内置语言文件（{detail}）。',
    Str.errStillNoAccess: '即使拥有管理员权限仍无法写入安装目录，因此未做任何改动。',
  };

}
