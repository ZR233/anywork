import 'dart:async';

import 'package:anywork/src/features/settings/connectors/settings_navigation_connector.dart';
import 'package:anywork/src/features/settings/modes/connectors/mode_editor_connector.dart';
import 'package:anywork/src/features/settings/modes/state/mode_editor_state.dart';
import 'package:anywork/src/features/settings/modes/view_models/mode_editor_view_model.dart';
import 'package:anywork/src/features/settings/presentation_api.dart'
    as settings;
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/features/settings/view_models/settings_tab_lifecycle.dart';
import 'package:anywork/src/features/settings/views/settings_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../anywork_client/test/support/modes_fixture.dart';
import 'support/pump_client_future.dart';
import 'support/settings_leave_fixture.dart';
import 'support/selector_environment.dart';

ThreadModeDescriptorRead _descriptor(ModeDocument value) =>
    ThreadModeDescriptorRead(
      id: value.definition.id,
      displayName: ReadText.inline(text: value.definition.displayName),
      description: ReadText.inline(text: value.definition.description),
      order: value.definition.order,
      hasWorkflow: value.definition.workflow != null,
      readOnly: false,
    );

void main() {
  testWidgets(
    'a superseded Settings request cannot use its old discard choice on the current Mode draft',
    (tester) async {
      final harness = await SettingsLeaveFixture.create(tester);
      harness.vm.edit(const ModeEdit.prompt('keep the original dirty draft'));
      final raw = harness.state.jsonText;
      final handoffs = <String>[];
      harness.navigation.register(
        SettingsTab.modes,
        SettingsTabLifecycle(
          handoff: () => handoffs.add('handoff'),
          visibility: (_) {},
        ),
      );
      final leaving = selectSettingsTab(
        harness.context,
        harness.ref,
        SettingsTab.instructions,
      );
      await tester.pumpAndSettle();
      final original = harness.navigationState.request!;
      final newer = harness.navigation.begin(SettingsTab.general)!;
      expect(harness.navigation.owns(original), isFalse);
      await harness.choose(ModeLeaveChoice.discard);
      expect(await leaving, isFalse);
      expect(harness.navigationState.request, same(newer));
      expect(harness.navigationState.tab, SettingsTab.modes);
      expect(harness.state.jsonText, raw);
      expect(harness.state.dirty, isTrue);
      expect(harness.original.port.commands, isEmpty);
      expect(handoffs, isEmpty);
      expect(
        find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
        findsNothing,
        reason:
            'An invalidated result does not automatically reopen confirmation',
      );
    },
  );

  testWidgets(
    'a newer raw edit or completed intent invalidates the previous Mode confirmation',
    (tester) async {
      for (final invalidateWithEdit in [true, false]) {
        final harness = await SettingsLeaveFixture.create(tester);
        harness.vm.edit(const ModeEdit.prompt('dirty before confirmation'));
        final leaving = confirmLeaveModeEditor(harness.context, harness.ref);
        await tester.pumpAndSettle();
        final before = harness.state;
        if (invalidateWithEdit) {
          harness.vm.editJson('{new unparsed raw input');
          expect(harness.state.editRevision, greaterThan(before.editRevision));
        } else {
          await harness.vm.validate();
          expect(harness.state.latestIntent, greaterThan(before.latestIntent));
          expect(harness.state.editRevision, before.editRevision);
          expect(harness.state.busy, isFalse);
        }
        final current = harness.state;
        await harness.choose(ModeLeaveChoice.discard);
        expect(await leaving, isFalse);
        expect(
          harness.state,
          current,
          reason: 'The modal cannot discard a newer editing identity',
        );
        expect(harness.state.dirty, isTrue);
        expect(harness.original.port.commands, isEmpty);
      }
    },
  );

  testWidgets(
    'the same notifier with repeated local edit counters still rejects its previous lifetime dialog',
    (tester) async {
      final harness = await SettingsLeaveFixture.create(tester, open: false);
      harness.vm.create(modeDocument());
      harness.vm.edit(const ModeEdit.prompt('old lifetime draft'));
      final vm = harness.vm;
      final lifetime = vm.lifetime;
      final before = harness.state;
      final leaving = confirmLeaveModeEditor(harness.context, harness.ref);
      await tester.pumpAndSettle();
      final replacement = settingsLeaveModesFixture();
      await replacement.establish();
      await harness.replace(replacement);
      expect(harness.vm, same(vm));
      harness.vm.create(modeDocument());
      harness.vm.edit(const ModeEdit.prompt('new lifetime draft'));
      expect(vm.lifetime, greaterThan(lifetime));
      expect(
        (
          harness.state.selectedModeId,
          harness.state.editRevision,
          harness.state.latestIntent,
        ),
        (before.selectedModeId, before.editRevision, before.latestIntent),
        reason: 'The test must isolate lifetime ABA, not merely changed local counters',
      );
      final current = harness.state;
      await harness.choose(ModeLeaveChoice.discard);
      expect(await leaving, isFalse);
      expect(harness.state, current);
      expect(harness.state.document!.definition.prompt, 'new lifetime draft');
      expect(harness.state.dirty, isTrue);
      expect(replacement.port.commands, isEmpty);
    },
  );

  testWidgets(
    'a pure catalog publication does not reject the original guard and handoff occurs before hiding',
    (tester) async {
      final harness = await SettingsLeaveFixture.create(tester);
      harness.vm.edit(const ModeEdit.prompt('discard this original edit'));
      final before = harness.state;
      final lifetime = harness.vm.lifetime;
      final events = <String>[];
      harness.navigation.register(
        SettingsTab.modes,
        SettingsTabLifecycle(
          handoff: () {
            expectSync(harness.navigationState.visible, isTrue);
            expectSync(harness.navigationState.tab, SettingsTab.modes);
            expectSync(harness.state.dirty, isFalse);
            events.add('handoff');
          },
          visibility: (visible) {
            if (!visible) events.add('hide');
          },
        ),
      );
      final leaving = selectSettingsTab(
        harness.context,
        harness.ref,
        SettingsTab.security,
      );
      await tester.pumpAndSettle();
      harness.original.port.publishChange(
        deliverySequence: 2,
        from: 1,
        to: 2,
        rows: [_descriptor(modeDocument())],
      );
      await harness.original.port.feed.acknowledged(2);
      expect(harness.vm.lifetime, lifetime);
      expect(
        (
          harness.state.selectedModeId,
          harness.state.editRevision,
          harness.state.latestIntent,
        ),
        (before.selectedModeId, before.editRevision, before.latestIntent),
      );
      await harness.choose(ModeLeaveChoice.discard);
      expect(await leaving, isTrue);
      expect(events, ['handoff', 'hide']);
      expect(harness.navigationState.tab, SettingsTab.security);
      expect(harness.navigationState.visible, isTrue);
      expect(harness.state.dirty, isFalse);
      expect(harness.original.port.commands, isEmpty);
    },
  );

  testWidgets(
    'busy, loading and failed real editor states refuse leave without opening a modal',
    (tester) async {
      final harness = await SettingsLeaveFixture.create(tester);
      harness.vm.edit(const ModeEdit.prompt('dirty editor'));
      final port = harness.original.port;
      final entered = port.queryEntered = Completer<void>();
      final reply = port.queryReceipt = Completer<void>();
      final validating = harness.vm.validate();
      await entered.future;
      expect(harness.state.busy, isTrue);
      expect(
        await confirmLeaveModeEditor(harness.context, harness.ref),
        isFalse,
      );
      reply.complete();
      await validating;

      final pending = settingsLeaveModesFixture();
      final rebuilding = harness.replace(pending);
      await pending.port.feed.listened.future;
      expect(
        harness.container.read(modeEditorViewModelProvider).isLoading,
        isTrue,
      );
      expect(
        await confirmLeaveModeEditor(harness.context, harness.ref),
        isFalse,
      );
      await pending.establish();
      await rebuilding;

      final closed = settingsLeaveModesFixture();
      await closed.establish();
      expect(
        (await pumpClientFuture(
          tester,
          closed.repository.close(),
          'closed replacement Repository',
        )).complete,
        isTrue,
      );
      // Real ResourceSource admission rejects observation of this closed owner;
      // no fake AsyncNotifier state or Repository is installed for the error.
      await expectLater(
        harness.replace(closed),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
      expect(
        harness.container.read(modeEditorViewModelProvider).hasError,
        isTrue,
      );
      expect(
        await confirmLeaveModeEditor(harness.context, harness.ref),
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
        findsNothing,
      );
      expect(port.commands, isEmpty);
      expect(pending.port.commands, isEmpty);
      expect(closed.port.commands, isEmpty);
    },
  );

  testWidgets(
    'a save admitted by the original confirmation retains its ticket but cannot complete a newer navigation',
    (tester) async {
      final harness = await SettingsLeaveFixture.create(tester);
      harness.vm.edit(const ModeEdit.prompt('save the original payload'));
      final payload = harness.state.document!;
      final port = harness.original.port;
      port.validation = ModeValidationResult(
        document: payload,
        issues: const [],
      );
      final handoffs = <String>[];
      harness.navigation.register(
        SettingsTab.modes,
        SettingsTabLifecycle(
          handoff: () => handoffs.add('handoff'),
          visibility: (_) {},
        ),
      );
      final leaving = confirmLeaveSettings(harness.context, harness.ref);
      await harness.choose(ModeLeaveChoice.save);
      final call = await port.command(0);
      expect(call.document, payload);
      final newer = harness.navigation.begin(SettingsTab.security)!;
      call.complete(
        revision: 2,
        definition: ModeDefinitionSnapshot(
          revision: 2,
          document: payload,
          readOnly: false,
        ),
      );
      port.publishChange(
        deliverySequence: 2,
        from: 1,
        to: 2,
        rows: [_descriptor(payload)],
      );
      expect(await leaving, isFalse);
      expect(
        harness.state.dirty,
        isFalse,
        reason: 'The admitted save still settles its original editor ticket',
      );
      expect(harness.state.operation!.operation!.observed, isTrue);
      expect(harness.state.savedRevision, 2);
      expect(harness.navigationState.request, same(newer));
      expect(harness.navigationState.tab, SettingsTab.modes);
      expect(harness.navigationState.visible, isTrue);
      expect(handoffs, isEmpty);
      expect(port.commands, hasLength(1));
      expect(
        find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Settings Back and rejected PopScope events each reach the router onExit guard and handoff once',
    (tester) async {
      // The real Settings shell now waits for canonical public configuration;
      // a navigation-only container cannot stand in for a ready application.
      final environment = SelectorEnvironment();
      await pumpClientFuture(
        tester,
        environment.establish(catalog: false),
        'Settings route fixture sources ready',
      );
      final container = environment.container;
      await pumpClientFuture(
        tester,
        container.read(settingsNavigationViewModelProvider.future),
        'Settings navigation owner ready',
      );
      late WidgetRef routeRef;
      var guards = 0;
      final events = <String>[];
      final navigation = container.read(
        settingsNavigationViewModelProvider.notifier,
      );
      navigation.register(
        SettingsTab.security,
        SettingsTabLifecycle(
          handoff: () {
            expectSync(
              container
                  .read(settingsNavigationViewModelProvider)
                  .requireValue
                  .visible,
              isTrue,
            );
            events.add('handoff');
          },
          visibility: (visible) {
            if (!visible) events.add('hide');
          },
        ),
      );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, state) =>
                const SizedBox(key: ValueKey('settings-home')),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, state) => const settings.SettingsScreen(
                  initialTab: settings.SettingsTab.security,
                ),
                onExit: (context, state) {
                  guards++;
                  return settings.confirmLeaveSettings(context, routeRef);
                },
              ),
            ],
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await pumpClientFuture(
          tester,
          environment.close(),
          'Settings route owners close',
        );
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) {
              routeRef = ref;
              return MaterialApp.router(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      for (final usePopScope in [false, true]) {
        final pushed = router.push<void>('/settings');
        await tester.pumpAndSettle();
        expect(
          container.read(settingsNavigationViewModelProvider).requireValue.tab,
          SettingsTab.security,
        );
        events.clear();
        final before = guards;
        if (usePopScope) {
          final scope = tester.widget<PopScope<void>>(
            find.descendant(
              of: find.byType(settings.SettingsScreen),
              matching: find.byType(PopScope<void>),
            ),
          );
          scope.onPopInvokedWithResult!(false, null);
        } else {
          tester.widget<SettingsView>(find.byType(SettingsView)).onBack();
        }
        await tester.pumpAndSettle();
        await pushed;
        expect(
          guards,
          before + 1,
          reason:
              'Back must not confirm before router.pop invokes its one onExit',
        );
        expect(events, ['handoff', 'hide']);
        expect(
          container
              .read(settingsNavigationViewModelProvider)
              .requireValue
              .visible,
          isFalse,
        );
        expect(find.byType(settings.SettingsScreen), findsNothing);
        expect(find.byKey(const ValueKey('settings-home')), findsOneWidget);
        expect(router.canPop(), isFalse);
      }
    },
  );
}
