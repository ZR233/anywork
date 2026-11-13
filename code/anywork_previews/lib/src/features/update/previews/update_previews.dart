import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/update/state/studio_update_view_state.dart';
import 'package:anywork/src/features/update/views/studio_update_settings_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

@Preview(
  name: '新版检查失败 · 保留可安装更新',
  group: 'Settings · Updates',
  size: Size(760, 180),
)
Widget retainedUpdatePreview() => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: StudioUpdateSettingsView(
      state: const StudioUpdateViewState(
        hasUpdate: true,
        updateBusy: false,
        currentVersion: '1.0.0',
        availableVersion: '2.0.0',
        statusKind: StudioUpdateStatusKind.ready,
        requestKind: StudioUpdateRequestKind.idle,
        showProgress: false,
        progressPercent: 0,
        actionLayout: StudioUpdateSettingsActionLayout.updateAvailable,
        primaryAction: StudioUpdatePrimaryAction.installAndRestart,
        primaryEnabled: true,
        showReleaseNotes: true,
        showCancel: false,
        cancelEnabled: true,
        errorKind: StudioUpdateErrorKind.failed,
        errorMessage: '网络连接失败，下一周期将继续检查。',
      ),
      onCheck: () {},
      onInstall: () {},
      onCancel: () {},
      onOpenReleaseNotes: () {},
    ),
  ),
);
