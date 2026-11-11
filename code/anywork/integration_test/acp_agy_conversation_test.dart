import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/composer/widgets/start_backend_selector.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/presentation_capture.dart';
import 'support/production_studio_harness.dart';

// Explicit live acceptance only. HOME is deliberately untouched: official agy
// owns authentication. The caller must provide an empty, disposable Studio home
// and synthetic project, both under ANYWORK_AGY_SANDBOX. No login is attempted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'logged-in agy through the complete production ACP conversation shell',
    (tester) async {
      String requiredEnvironment(String name) {
        final value = Platform.environment[name]?.trim();
        if (value == null || value.isEmpty) throw StateError('Supply $name');
        return value;
      }

      final sandbox = await Directory(
        requiredEnvironment('ANYWORK_AGY_SANDBOX'),
      ).resolveSymbolicLinks();
      final home = await Directory(requiredEnvironment('ANYWORK_HOME'))
          .resolveSymbolicLinks();
      final projectPath = await Directory(
        requiredEnvironment('ANYWORK_AGY_PROJECT'),
      ).resolveSymbolicLinks();
      expect(p.equals(home, p.join(sandbox, 'studio-home')), isTrue);
      expect(p.equals(projectPath, p.join(sandbox, 'project')), isTrue);
      // The native runner acquires its instance lock and opens logs before
      // Dart's test body. Those are not product configuration/history.
      final existing = await Directory(home).list().toList();
      expect(
        existing.map((entry) => p.basename(entry.path)),
        everyElement('studio'),
      );
      expect(await Directory(p.join(home, 'data')).exists(), isFalse);
      expect(await File(p.join(home, 'config.toml')).exists(), isFalse);
      expect(await Directory(p.join(home, 'acp')).exists(), isFalse);
      expect(
        await File(p.join(projectPath, 'README.md')).readAsString(),
        'Disposable ACP live acceptance workspace. No private data.\n',
      );
      final command = requiredEnvironment('ANYWORK_AGY_COMMAND');
      expect(p.isAbsolute(command), isTrue);
      expect(await File(command).exists(), isTrue);
      final harness = await ProductionStudioHarness.start(
        binding: binding,
        artifactsEnvironmentVariable: 'ANYWORK_AGY_ARTIFACTS',
      );
      addTearDown(harness.close);
      final scene = await harness.mount(tester);
      addTearDown(scene.dispose);
      final graph = harness.graph;
      final accounts = graph.accounts.observeSummaries();
      addTearDown(accounts.release);
      final evidence = <String, Object?>{
        'platform': Platform.operatingSystem,
        'guiPid': pid,
        'promptCount': 0,
        'permission': 'not requested by the text-only prompt; not covered',
        'cancellation': 'not attempted; no artificial in-flight run',
        'preparation':
            'public Client save/openProject; all business controls UI',
      };
      Future<void> record(String stage) async {
        evidence['stage'] = stage;
        await File(p.join(harness.artifacts.path, 'agy-live-report.json'))
            .writeAsString(
              const JsonEncoder.withIndent('  ').convert(evidence),
              flush: true,
            );
        debugPrint('AGY_LIVE $stage');
      }

      await record('production-shell-mounted');
      evidence['geometry'] = await configurePresentationWindow(
        tester,
        logicalWidth: 1440,
        logicalHeight: 1000,
        requireNativeResize: true,
      );
      const serviceId = 'agy-live-acceptance';
      const serviceName = 'AGY live acceptance';
      // Ordinary command definitions have no credential material or login step.
      final saved = await graph.acp.save(
        AcpAccountUpdateView(
          accountId: serviceId,
          name: serviceName,
          command: command,
          args: const ['acp'],
        ),
        expectedDocumentRevision: null,
      );
      expect(saved.failurePhase, isNull);
      await scene.until(
        () => graph.accounts.state.value.accounts.any(
          (account) =>
              account.identity.accountId == serviceId &&
              account.acpEnabled == true,
        ),
        'saved isolated ACP definition is observed',
      );
      final project = await harness.openProject(scene, projectPath);
      await scene.until(
        () => find.byType(StartBackendSelector).evaluate().length == 1,
        'project start page exposes backend selector',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(StartBackendSelector),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(serviceName).last);
      await scene.until(
        () => find.byType(AcpStartComposer).evaluate().length == 1,
        'ACP service selected through production start page',
      );
      final marker = 'ACP284LIVEOK${DateTime.now().millisecondsSinceEpoch}';
      final prompt =
          'Reply with exactly $marker and nothing else. Do not call tools, '
          'run commands, use the network, or read or write any files.';
      await tester.enterText(
        find.descendant(
          of: find.byType(AcpStartComposer),
          matching: find.byType(TextField),
        ),
        prompt,
      );
      await tester.tap(find.widgetWithText(FilledButton, '创建 ACP 会话'));
      await scene.until(() {
        final failure = graph
            .client
            .drafts
            .startDraft
            .state
            .preparations[project.id]
            ?.failure;
        if (failure != null) throw StateError('ACP create failed: $failure');
        return find.byType(AcpConversationComposer).evaluate().length == 1;
      }, 'explicit session/new completes without prompting');
      final threadId = tester
          .widget<AcpConversationComposer>(find.byType(AcpConversationComposer))
          .threadId;
      final owner = graph.client.acpSessions.conversationForThread(threadId)!;
      await scene.until(
        () => owner.state.ready && !owner.state.openPending,
        'real ACP owner ready',
      );
      void checkOwner() {
        expect(owner.state.error, isNull);
        expect(owner.state.observationGap, isNull);
        expect(owner.state.disconnected, isFalse);
        expect(owner.state.observationEnded, isFalse);
      }

      checkOwner();
      expect(owner.state.activeRun, isNull);
      expect(owner.state.lastCompleted, isNull);
      // ACP may publish commands/session metadata immediately after session/new.
      // Prove that creation did not prompt, rather than forbidding notifications.
      expect(
        owner.state.content.whereType<AcpConversationMessageItem>(),
        isEmpty,
      );
      expect(owner.state.content.whereType<AcpConversationToolItem>(), isEmpty);
      evidence['initialNotifications'] = owner.state.content
          .whereType<AcpConversationUpdateItem>()
          .map((item) => item.update.runtimeType.toString())
          .toList();
      final draft = graph.client.drafts.composer(threadId);
      expect(draft.state.draft, prompt);
      final caps = owner.state.capabilities!;
      evidence['capabilities'] = {
        'image': caps.image,
        'audio': caps.audio,
        'embeddedContext': caps.embeddedContext,
        'loadSession': caps.loadSession,
        'listSessions': caps.listSessions,
        'resumeSession': caps.resumeSession,
      };
      evidence['initialConfig'] = _configuration(owner.state);
      await record('created-ready-no-prompt-draft-retained');

      var pendingObserved = false;
      final configWatch = owner.source.watch((state) {
        if (state.configPending) pendingObserved = true;
      });
      addTearDown(configWatch.cancel);
      final options = owner.state.configOptions;
      if (options != null) {
        final selects = options.where((option) {
          final kind = option.kind;
          return kind is AcpSelectConfigView &&
              _values(kind).any((value) => value.value != kind.currentValue);
        }).toList();
        // Prefer effort/config over switching models or permission-related modes.
        selects.sort((a, b) => _priority(a).compareTo(_priority(b)));
        expect(selects, isNotEmpty, reason: 'No real alternate select config');
        final option = selects.first;
        final kind = option.kind as AcpSelectConfigView;
        final alternate = _values(kind)
            .firstWhere((value) => value.value != kind.currentValue);
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey(option.id)),
            matching: find.byType(DropdownButton<AcpConfigValueId>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(alternate.name).last);
        await scene.until(
          () => !owner.state.configPending && pendingObserved,
          'real configuration request leaves pending',
        );
        expect(owner.state.configError, isNull);
        final confirmed = owner.state.configOptions!.singleWhere(
          (value) => value.id == option.id,
        );
        expect(
          (confirmed.kind as AcpSelectConfigView).currentValue,
          alternate.value,
        );
        evidence['changedConfigId'] = option.id.value;
        evidence['changedConfigValue'] = alternate.value.value;
      } else {
        final modes = owner.state.modes!;
        final alternate = modes.availableModes.firstWhere(
          (mode) => mode.id != modes.currentModeId,
        );
        await tester.tap(find.byType(DropdownButton<AcpModeId>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(alternate.name).last);
        await scene.until(
          () => !owner.state.configPending && pendingObserved,
          'real legacy mode request leaves pending',
        );
        expect(owner.state.configError, isNull);
        expect(owner.state.modes!.currentModeId, alternate.id);
        evidence['changedModeId'] = alternate.id.value;
      }
      checkOwner();
      expect(draft.state.draft, prompt);
      expect(owner.state.lastCompleted, isNull);
      evidence['configPendingObserved'] = pendingObserved;
      evidence['confirmedConfig'] = _configuration(owner.state);
      await scene.capture('agy-live-configured-shell');
      await record('real-configuration-confirmed');

      // A single real prompt. No retries, callback calls or synthetic ACP frames.
      evidence['promptCount'] = 1;
      evidence['marker'] = marker;
      await record('prompt-dispatch-once');
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await scene.until(
        () {
          checkOwner();
          return owner.state.lastCompleted != null;
        },
        'actual prompt terminal result',
        timeout: const Duration(seconds: 120),
      );
      final completed = owner.state.lastCompleted!;
      final result = completed.result;
      expect(result, isA<AcpSuccessView<AcpPromptResponseView>>());
      final stop =
          (result as AcpSuccessView<AcpPromptResponseView>).value.stopReason;
      expect(stop, AcpStopReasonView.endTurn);
      expect(owner.state.activeRun, isNull);
      expect(owner.state.sendPending, isFalse);
      expect(draft.state.draft, isEmpty);
      final userMessages = owner.state.content
          .whereType<AcpConversationMessageItem>()
          .where((item) => item.kind == AcpConversationMessageKind.user)
          .toList();
      evidence['userMessageCount'] = userMessages.length;
      expect(userMessages, hasLength(1));
      final userText = userMessages.single.chunks
          .map((chunk) => chunk.content)
          .whereType<AcpTextContentView>()
          .map((block) => block.text)
          .join();
      expect(userText, prompt);
      evidence['actualUserText'] = userText;
      final text = owner.state.content
          .whereType<AcpConversationMessageItem>()
          .where((item) => item.kind == AcpConversationMessageKind.assistant)
          .expand((item) => item.chunks)
          .map((chunk) => chunk.content)
          .whereType<AcpTextContentView>()
          .map((block) => block.text)
          .join();
      expect(text.trim(), marker);
      expect(owner.state.pendingPermissions, isEmpty);
      evidence['stopReason'] = stop.name;
      evidence['actualAssistantText'] = text;
      await record('actual-text-and-end-turn-confirmed');
      // The production list is lazy. Scroll the exact assistant item into view,
      // and scope the rendered-text assertion so the user prompt cannot pass it.
      final assistantIndex = owner.state.content.lastIndexWhere(
        (item) =>
            item is AcpConversationMessageItem &&
            item.kind == AcpConversationMessageKind.assistant,
      );
      final assistantItem = find.byKey(ValueKey((threadId, assistantIndex)));
      await tester.scrollUntilVisible(
        assistantItem,
        250,
        scrollable: find
            .descendant(
              of: find.byType(AcpConversationContent),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 20,
      );
      await scene.until(
        () => find
            .descendant(
              of: assistantItem,
              matching: find.textContaining(marker, findRichText: true),
            )
            .evaluate()
            .isNotEmpty,
        'real assistant text rendered in production content',
      );
      await scene.capture('agy-live-response-shell');
      await record('real-text-and-end-turn-confirmed');
      expect(tester.takeException(), isNull);
      expect(
        graph.client.project.state.projects!.values.any(
          (item) => item.id == project.id,
        ),
        isTrue,
      );
    },
    skip: Platform.environment['ANYWORK_AGY_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

List<AcpSelectOptionView> _values(AcpSelectConfigView kind) =>
    switch (kind.options) {
      AcpUngroupedOptionsView(:final options) => options,
      AcpGroupedOptionsView(:final groups) => [
        for (final group in groups) ...group.options,
      ],
    };

int _priority(AcpSessionConfigOptionView option) =>
    switch (option.category?.kind) {
      AcpConfigCategoryKindView.thoughtLevel => 0,
      AcpConfigCategoryKindView.modelConfig => 1,
      AcpConfigCategoryKindView.model => 2,
      _ => 3,
    };

Map<String, Object?> _configuration(AcpConversationState state) => {
  'options': state.configOptions
      ?.map(
        (option) => {
          'id': option.id.value,
          'name': option.name,
          'kind': switch (option.kind) {
            AcpBooleanConfigView() => 'boolean',
            AcpSelectConfigView() => 'select',
          },
          'current': switch (option.kind) {
            AcpBooleanConfigView(:final currentValue) => currentValue,
            AcpSelectConfigView(:final currentValue) => currentValue.value,
          },
          if (option.kind case final AcpSelectConfigView kind)
            'available': _values(kind)
                .map((value) => {'id': value.value.value, 'name': value.name})
                .toList(),
        },
      )
      .toList(),
  'currentMode': state.modes?.currentModeId.value,
  'availableModes': state.modes?.availableModes
      .map((mode) => {'id': mode.id.value, 'name': mode.name})
      .toList(),
};
