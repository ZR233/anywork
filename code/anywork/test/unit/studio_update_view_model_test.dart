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
  test('projects idle as no update', () {
    final state = projectStudioUpdateViewState(
      snapshot: IdleUpdaterStateSnapshot(revision: 1, updatedAt: _now),
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
      snapshot: AvailableUpdaterStateSnapshot(
        revision: 2,
        checkedAt: _now,
        update: _update,
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
      snapshot: AvailableUpdaterStateSnapshot(
        revision: 2,
        checkedAt: _now,
        update: _update,
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
          AvailableUpdaterStateSnapshot(
            revision: 2,
            checkedAt: _now,
            update: _update,
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
