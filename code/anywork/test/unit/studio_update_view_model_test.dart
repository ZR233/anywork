import 'package:anywork/src/features/update/state/studio_update_view_state.dart';
import 'package:anywork/src/features/update/studio_update_actions.dart';
import 'package:anywork/src/features/update/view_models/studio_update_view_model.dart';
import 'package:anywork/src/presentation/providers/studio_update_controller.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 4, 1);
final _update = StudioUpdateInfoView(
  version: '1.2.3',
  publishedAt: _now,
  notesUrl: 'https://example.test/notes',
);

class _RecordingCommands implements StudioUpdateCommands {
  int installCount = 0;

  @override
  Future<void> check() async {}

  @override
  Future<void> install() async {
    installCount += 1;
  }

  @override
  Future<void> cancelInstall() async {}

  @override
  Future<void> openReleaseNotes() async {}
}

void main() {
  test('matching receipt and canonical errors render once while selection rejection stays visible', () {
    final snapshot = UpdaterStateSnapshot(
      activity: InstallFailedUpdaterActivity(
        revision: 2,
        failedAt: _now,
        update: _update,
        error: const UpdaterErrorView(
          code: 'network',
          message: 'offline',
          retryable: true,
        ),
      ),
    );
    final matching = projectStudioUpdateViewState(
      snapshot: snapshot,
      request: const StudioUpdateRequest(
        StudioUpdateRequestPhase.failed,
        error: 'offline',
      ),
      currentVersion: '1.0.0',
    );
    expect(matching.errorMessage, 'offline');
    expect(matching.requestErrorMessage, isNull);
    final rejected = projectStudioUpdateViewState(
      snapshot: snapshot,
      request: const StudioUpdateRequest(
        StudioUpdateRequestPhase.failed,
        error: 'update no longer available',
      ),
      currentVersion: '1.0.0',
    );
    expect(rejected.requestErrorMessage, 'update no longer available');
  });

  test(
    'retained installer remains actionable through later checks and failures',
    () {
      final activities = <UpdaterActivity>[
        CheckingUpdaterActivity(
          revision: 3,
          operationId: 'check',
          startedAt: _now,
        ),
        CheckFailedUpdaterActivity(
          revision: 4,
          failedAt: _now,
          error: const UpdaterErrorView(
            code: 'network',
            message: 'offline',
            retryable: true,
          ),
        ),
        InstallFailedUpdaterActivity(
          revision: 5,
          failedAt: _now,
          update: StudioUpdateInfoView(
            version: '2.0.0',
            publishedAt: _now,
            notesUrl: 'https://example.test/new',
          ),
          error: const UpdaterErrorView(
            code: 'signatureInvalid',
            message: 'invalid signature',
            retryable: false,
          ),
        ),
      ];
      for (final activity in activities) {
        final view = projectStudioUpdateViewState(
          snapshot: UpdaterStateSnapshot(
            activity: activity,
            readyUpdate: ReadyStudioUpdate(update: _update, readyAt: _now),
          ),
          request: const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
          currentVersion: '1.0.0',
        );
        expect(view.hasUpdate, isTrue);
        expect(
          view.statusKind,
          activity is CheckingUpdaterActivity
              ? StudioUpdateStatusKind.checking
              : StudioUpdateStatusKind.ready,
        );
        expect(view.readyVersion, '1.2.3');
        expect(view.primaryAction, StudioUpdatePrimaryAction.installAndRestart);
        expect(view.primaryEnabled, isTrue);
      }
    },
  );

  test('projects idle as no update', () {
    final state = projectStudioUpdateViewState(
      snapshot: UpdaterStateSnapshot(
        activity: IdleUpdaterActivity(revision: 1, updatedAt: _now),
      ),
      request: const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
      currentVersion: '1.0.0',
    );
    expect(state.hasUpdate, isFalse);
    expect(state.updateBusy, isFalse);
    expect(state.statusKind, StudioUpdateStatusKind.idle);
    expect(state.primaryAction, StudioUpdatePrimaryAction.check);
  });

  test('projects available update without forging ready', () {
    final state = projectStudioUpdateViewState(
      snapshot: UpdaterStateSnapshot(
        activity: AvailableUpdaterActivity(
          revision: 2,
          checkedAt: _now,
          update: _update,
        ),
      ),
      request: const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
      currentVersion: '1.0.0',
    );
    expect(state.hasUpdate, isTrue);
    expect(state.updateBusy, isFalse);
    expect(state.availableVersion, '1.2.3');
    expect(state.statusKind, StudioUpdateStatusKind.available);
    expect(state.primaryAction, StudioUpdatePrimaryAction.downloadAndRestart);
    expect(
      state.actionLayout,
      StudioUpdateSettingsActionLayout.updateAvailable,
    );
  });

  test('projects pending request as busy', () {
    final state = projectStudioUpdateViewState(
      snapshot: UpdaterStateSnapshot(
        activity: AvailableUpdaterActivity(
          revision: 2,
          checkedAt: _now,
          update: _update,
        ),
      ),
      request: const StudioUpdateRequest(StudioUpdateRequestPhase.preparing),
      currentVersion: '1.0.0',
    );
    expect(state.hasUpdate, isTrue);
    expect(state.updateBusy, isTrue);
    expect(state.primaryEnabled, isFalse);
    expect(state.actionLayout, StudioUpdateSettingsActionLayout.progress);
  });

  test('install forwards to update commands', () async {
    final commands = _RecordingCommands();
    final container = ProviderContainer(
      overrides: [
        studioUpdateControllerProvider.overrideWithValue(
          UpdaterStateSnapshot(
            activity: AvailableUpdaterActivity(
              revision: 2,
              checkedAt: _now,
              update: _update,
            ),
          ),
        ),
        studioUpdateRequestProvider.overrideWithValue(
          const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
        ),
        studioVersionProvider.overrideWithValue('1.0.0'),
        studioUpdateActionsProvider.overrideWithValue(commands),
      ],
    );
    addTearDown(container.dispose);

    final projected = container.read(studioUpdateViewModelProvider);
    expect(projected.hasUpdate, isTrue);
    expect(projected.statusKind, StudioUpdateStatusKind.available);
    expect(
      projected.primaryAction,
      isNot(StudioUpdatePrimaryAction.installAndRestart),
    );

    await container.read(studioUpdateViewModelProvider.notifier).install();
    expect(commands.installCount, 1);
    expect(
      container.read(studioUpdateViewModelProvider).statusKind,
      StudioUpdateStatusKind.available,
    );
  });
}
