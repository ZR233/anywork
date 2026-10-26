import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/modes/state/mode_editor_state.dart';
import 'package:anywork/src/features/settings/modes/view_models/mode_editor_view_model.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/modes_fixture.dart';
import 'pump_client_future.dart';

ModesFixture settingsLeaveModesFixture() {
  final fixture = ModesFixture();
  final document = modeDocument();
  fixture.port.definitions[document.definition.id.id] = ModeDefinitionSnapshot(
    revision: 1,
    document: document,
    readOnly: false,
  );
  fixture.port.validation = ModeValidationResult(
    document: document,
    issues: const [],
  );
  return fixture;
}

/// A localized WidgetRef/BuildContext for the real Smart confirmation helpers.
/// No fake Repository, VM, dialog algorithm or navigation writer is installed.
final class SettingsLeaveFixture {
  SettingsLeaveFixture(this.tester, this.original)
    : container = ProviderContainer(
        // Observe the original failed build, not Riverpod's timed retry loop.
        retry: (_, _) => null,
        overrides: [
          modesRepositoryProvider.overrideWithValue(original.repository),
        ],
      ) {
    fixtures.add(original);
  }
  final WidgetTester tester;
  final ModesFixture original;
  final ProviderContainer container;
  final fixtures = <ModesFixture>[];
  late BuildContext context;
  late WidgetRef ref;

  ModeEditorViewModel get vm =>
      container.read(modeEditorViewModelProvider.notifier);
  ModeEditorViewState get state =>
      container.read(modeEditorViewModelProvider).requireValue;
  SettingsNavigationViewModel get navigation =>
      container.read(settingsNavigationViewModelProvider.notifier);
  SettingsNavigationState get navigationState =>
      container.read(settingsNavigationViewModelProvider).requireValue;

  static Future<SettingsLeaveFixture> create(
    WidgetTester tester, {
    bool open = true,
  }) async {
    final original = settingsLeaveModesFixture();
    await original.establish();
    final harness = SettingsLeaveFixture(tester, original);
    addTearDown(harness.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, child) {
              harness.context = context;
              harness.ref = ref;
              ref.watch(modeEditorViewModelProvider);
              ref.watch(settingsNavigationViewModelProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await harness.container.read(modeEditorViewModelProvider.future);
    await harness.container.read(settingsNavigationViewModelProvider.future);
    if (open) expect(await harness.vm.open('mode.custom'), isTrue);
    harness.navigation.enter(SettingsTab.modes);
    await tester.pump();
    return harness;
  }

  Future<void> replace(ModesFixture replacement) async {
    fixtures.add(replacement);
    container.updateOverrides([
      modesRepositoryProvider.overrideWithValue(replacement.repository),
    ]);
    await container.read(modeEditorViewModelProvider.future);
  }

  Future<void> choose(ModeLeaveChoice choice) async {
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
      findsOneWidget,
    );
    final key = switch (choice) {
      ModeLeaveChoice.save => 'mode-editor-unsaved-save',
      ModeLeaveChoice.discard => 'mode-editor-unsaved-discard',
      ModeLeaveChoice.stay => 'mode-editor-unsaved-cancel',
    };
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (final fixture in fixtures) {
      final pending = fixture.port.queryReceipt;
      if (pending != null && !pending.isCompleted) pending.complete();
      for (final call in fixture.port.commands) {
        if (!call.reply.isCompleted) {
          call.reply.completeError(
            const CommandDispatchFailure.rejected(
              failure: StudioFailure(
                code: StudioFailureCode.cancelled,
                message: 'The scripted test is closing.',
                retryable: false,
                correlationId: 'settings-leave-test',
              ),
            ),
          );
        }
      }
      final report = await pumpClientFuture(
        tester,
        fixture.repository.close(
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        ),
        'Settings leave Repository cleanup',
      );
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    }
  }
}
