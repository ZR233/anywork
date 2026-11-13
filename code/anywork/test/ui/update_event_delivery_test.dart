import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/update/connectors/sidebar_footer_connector.dart';
import 'package:anywork/src/features/update/connectors/studio_update_settings_connector.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final class _UpdateApi implements StudioUpdateApi {
  int starts = 0;
  int stops = 0;
  @override
  Future<void> startAutomaticUpdate() async {
    starts++;
  }

  @override
  Future<void> stopAutomaticUpdate() async {
    stops++;
  }

  @override
  Future<void> cancelCurrentPreparation() async {}
  @override
  Future<void> check() async {}
  @override
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'one canonical update reaches sidebar and late settings, even after settings unmounts',
    (tester) async {
      final api = _UpdateApi();
      final client = AnyworkClient(
        clientId: 'update-event-delivery',
        transport: DemoStudioTransport(),
        updateApi: api,
        updatesEnabled: true,
      );
      client.updates.attach();
      final now = DateTime.utc(2026);
      final ready = ReadyStudioUpdate(
        update: StudioUpdateInfoView(
          version: '2.0.0',
          publishedAt: now,
          notesUrl: 'https://example.test/notes',
        ),
        readyAt: now,
      );
      Widget host({required bool settings}) => ProviderScope(
        overrides: [anyworkClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 336,
                  child: SidebarFooterConnector(
                    archived: false,
                    onToggleArchived: () {},
                  ),
                ),
                if (settings) const StudioUpdateSettingsConnector(),
              ],
            ),
          ),
        ),
      );
      client.updater.apply(
        UpdaterStateSnapshot.idle(revision: 1, updatedAt: now),
      );
      await tester.pumpWidget(host(settings: false));
      expect(find.byKey(StudioDriverKeys.sidebarUpdateNow), findsNothing);
      client.updater.apply(
        UpdaterStateSnapshot(
          activity: CheckFailedUpdaterActivity(
            revision: 2,
            failedAt: now,
            error: const UpdaterErrorView(
              code: 'network',
              message: 'offline',
              retryable: true,
            ),
          ),
          readyUpdate: ready,
        ),
      );
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.sidebarUpdateNow), findsOneWidget);
      await tester.pumpWidget(host(settings: true));
      expect(
        find.byKey(const ValueKey('studio-update-install')),
        findsOneWidget,
      );
      expect(find.textContaining('2.0.0'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.pumpWidget(host(settings: false));
      client.updater.apply(
        UpdaterStateSnapshot(
          activity: CheckingUpdaterActivity(
            revision: 3,
            operationId: 'next',
            startedAt: now,
          ),
          readyUpdate: ready,
        ),
      );
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.sidebarUpdateNow), findsOneWidget);
      expect(api.starts, 1);
      expect(api.stops, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final report = await client.close();
      expect(report.complete, isTrue);
      expect(api.stops, 1);
    },
  );
}
