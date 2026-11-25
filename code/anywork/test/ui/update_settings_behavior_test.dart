import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/update/connectors/studio_update_settings_connector.dart';
import 'package:anywork/src/features/update/state/studio_update_view_state.dart';
import 'package:anywork/src/features/update/view_models/studio_update_view_model.dart';
import 'package:anywork/src/features/update/views/studio_update_settings_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final downloading in [false, true]) {
    testWidgets('update actions fit narrow large text: $downloading', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var installs = 0;
      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: StudioUpdateSettingsView(
              state: _state(downloading: downloading),
              onCheck: () {},
              onInstall: () => installs++,
              onCancel: () {},
              onOpenReleaseNotes: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final install = find.byKey(const ValueKey('studio-update-install'));
      final bounds = tester.getRect(install);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      await tester.tap(install);
      expect(installs, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('release notes failures reach the existing update feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioUpdateViewModelProvider.overrideWith(
            _FailingNotesViewModel.new,
          ),
        ],
        child: _host(const StudioUpdateSettingsConnector()),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('studio-update-release-notes')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Cannot open release notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

StudioUpdateViewState _state({bool downloading = false}) =>
    StudioUpdateViewState(
      hasUpdate: true,
      updateBusy: false,
      currentVersion: '1.0.0',
      availableVersion: '2.0.0',
      statusKind: downloading
          ? StudioUpdateStatusKind.downloading
          : StudioUpdateStatusKind.available,
      requestKind: StudioUpdateRequestKind.idle,
      showProgress: downloading,
      progress: downloading ? 0.5 : null,
      progressPercent: 50,
      actionLayout: downloading
          ? StudioUpdateSettingsActionLayout.progress
          : StudioUpdateSettingsActionLayout.updateAvailable,
      primaryAction: StudioUpdatePrimaryAction.downloadAndRestart,
      primaryEnabled: true,
      showReleaseNotes: !downloading,
      showCancel: downloading,
      cancelEnabled: true,
      errorKind: StudioUpdateErrorKind.none,
      errorMessage: '',
    );

class _FailingNotesViewModel extends StudioUpdateViewModel {
  @override
  StudioUpdateViewState build() => _state();

  @override
  Future<void> openReleaseNotes() async {
    throw StateError('Cannot open release notes');
  }
}
