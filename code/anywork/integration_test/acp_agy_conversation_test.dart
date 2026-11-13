import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/composer/widgets/start_backend_selector.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/agy_remote_workspace.dart';
import 'support/agy_host_trace.dart';
import 'support/presentation_capture.dart';
import 'support/production_studio_harness.dart';

// Explicit live acceptance only. HOME is deliberately untouched: official agy
// owns authentication. The caller must provide an empty, disposable Studio home
// under ANYWORK_AGY_SANDBOX. A local project is under the same sandbox; the
// explicit SSH variant uses an independently provisioned remote fixture.
// Neither variant attempts login or writes SSH configuration.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'logged-in agy through the complete production ACP conversation shell',
    (tester) async {
      if (Platform.environment['ANYWORK_AGY_LIVE'] != '1') {
        throw StateError('Explicit live opt-in requires ANYWORK_AGY_LIVE=1');
      }
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
      final remote = AgyRemoteWorkspace.fromEnvironment();
      final projectPath =
          remote?.path ??
          await Directory(requiredEnvironment('ANYWORK_AGY_PROJECT'))
              .resolveSymbolicLinks();
      expect(p.equals(home, p.join(sandbox, 'studio-home')), isTrue);
      if (remote == null) {
        expect(p.equals(projectPath, p.join(sandbox, 'project')), isTrue);
      }
      final existing = await Directory(home).list().toList();
      expect(
        existing.map((entry) => p.basename(entry.path)),
        everyElement('studio'),
      );
      expect(await Directory(p.join(home, 'data')).exists(), isFalse);
      expect(await File(p.join(home, 'config.toml')).exists(), isFalse);
      expect(await Directory(p.join(home, 'acp')).exists(), isFalse);
      if (remote == null) {
        expect(
          await File(p.join(projectPath, 'README.md')).readAsString(),
          'Disposable ACP live acceptance workspace. No private data.\n',
        );
      } else {
        await remote.verifyFixture();
      }
      // Managed acceptance uses the product template and a verified installation
      // prepared under this isolated home's studio directory, never a raw command.
      final managed = Platform.environment['ANYWORK_AGY_MANAGED'] == '1';
      if (remote != null && managed) {
        throw StateError(
          'Remote process evidence requires an explicit local '
          'ANYWORK_AGY_COMMAND; managed installation is a separate scenario',
        );
      }
      final command = managed
          ? null
          : requiredEnvironment('ANYWORK_AGY_COMMAND');
      List<String>? commandArgs;
      if (command != null) {
        expect(p.isAbsolute(command), isTrue);
        expect(await File(command).exists(), isTrue);
        final arguments = jsonDecode(
          Platform.environment['ANYWORK_AGY_ARGS'] ?? '["acp"]',
        ) as List<dynamic>;
        commandArgs = arguments.cast<String>();
        if (remote != null) {
          expect(commandArgs.first, 'acp');
          expect(commandArgs, isNot(contains('--login')));
          expect(
            commandArgs,
            isNot(contains('--dangerously-skip-permissions')),
          );
        }
      }
      final harness = await ProductionStudioHarness.start(
        binding: binding,
        artifactsEnvironmentVariable: 'ANYWORK_AGY_ARTIFACTS',
      );
      Future<void>? shutdown;
      Future<void> closeHarness() => shutdown ??= harness.close();
      addTearDown(closeHarness);
      final scene = await harness.mount(tester);
      addTearDown(scene.dispose);
      final graph = harness.graph;
      final accounts = graph.accounts.observeSummaries();
      addTearDown(accounts.release);
      final evidence = <String, Object?>{
        'platform': Platform.operatingSystem,
        'launchKind': managed ? 'managedAntigravityTemplate' : 'agyCli',
        'workspaceKind': remote == null ? 'local' : 'ssh',
        if (remote != null) 'remoteProjectPath': remote.path,
        if (remote != null) 'sshAlias': remote.alias,
        'coverage': remote == null
            ? 'text-only conversation'
            : 'remote file/command/STDIN/cancel/ACP child/process closure',
        'verdict': 'running',
        'overallAcceptance': 'Native mixed-direction regression is separate',
        'guiPid': pid,
        'promptCount': 0,
        'permission': remote == null
            ? 'not requested by the text-only prompt; not covered'
            : 'no auto-approval; unexpected permission requests fail',
        'cancellation': remote == null ? 'not attempted' : 'pending evidence',
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
      if (remote != null) {
        await remote.verifyServer(await graph.client.remote.listSshServers());
      }
      evidence['geometry'] = await configurePresentationWindow(
        tester,
        logicalWidth: 1440,
        logicalHeight: 1000,
        requireNativeResize: true,
      );
      const serviceId = 'agy-live-acceptance';
      const serviceName = 'AGY live acceptance';
      const childProfileId = 'agy-live-acceptance-child';
      final saved = await graph.acp.save(
        AcpAccountUpdateView(
          accountId: serviceId,
          name: serviceName,
          template: managed ? AcpProviderView.antigravity : null,
          command: command,
          args: commandArgs,
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
      if (remote != null) {
        // Isolated Studio configuration only, through the ordinary public
        // command also used by Settings. Never touch the operator's profiles.
        await graph.client.settingsCommands.saveUserAgentProfile(
          const AgentProfileDraft(
            definition: AgentDefinitionView(
              definitionId: childProfileId,
              displayName: 'AGY acceptance child',
              description: 'Synthetic remote ACP collaboration acceptance',
              whenToUse: 'Only for the disposable live acceptance workspace',
              source: '',
              revision: '',
              contentHash: '',
            ),
            binding: AcpAgentBindingView(accountId: serviceId),
          ),
        );
        await scene.until(
          () =>
              graph.client.settings.state.agentProfiles?.data.profiles.any(
                (profile) =>
                    profile.id == childProfileId &&
                    profile.enabled &&
                    profile.binding is AcpAgentBindingView,
              ) ==
              true,
          'isolated ACP child Profile is canonical before root creation',
        );
      }
      if (managed) {
        final authDemand = graph.acp.observeAuth();
        addTearDown(authDemand.release);
        const identity = AcpAccountIdentity(serviceId);
        final revision = graph.accounts.state.value
            .account(identity)!
            .acpConnectionRevision!;
        await graph.acp.check(identity);
        String? previousPhase;
        await scene.until(
          () {
            final auth = graph.acp.auth.value.value?.stateOf(
              serviceId,
              connectionRevision: revision,
            );
            final phase = auth.runtimeType.toString();
            if (phase != previousPhase) {
              previousPhase = phase;
              debugPrint('AGY_MANAGED_CHECK $phase');
            }
            if (auth is AcpFailedState) {
              throw StateError(
                'Managed check failed: ${auth.failure.stage.name}/${auth.failure.code.name}: ${auth.failure.message}',
              );
            }
            if (auth is AcpRequiredState) {
              throw StateError('Managed server requires an explicit login');
            }
            return auth is AcpVerifiedState;
          },
          'managed server connection and existing login are verified',
          timeout: const Duration(seconds: 90),
        );
        await record('managed-connection-verified');
      }
      final project = await harness.openProject(
        scene,
        projectPath,
        sshAlias: remote?.alias,
      );
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
        () => find.byType(AcpStartComposerView).evaluate().length == 1,
        'ACP service selected through production start page',
      );
      final marker = 'ACP284LIVEOK${DateTime.now().millisecondsSinceEpoch}';
      final prompt =
          remote?.prompt(marker, childProfileId) ??
          'Reply with exactly $marker and nothing else. Do not call tools, '
              'run commands, use the network, or read or write any files.';
      await tester.enterText(
        find.descendant(
          of: find.byType(AcpStartComposerView),
          matching: find.byType(TextField),
        ),
        prompt,
      );
      await tester.pumpAndSettle();
      await scene.capture('agy-live-start-card');
      await tester.tap(find.widgetWithText(FilledButton, '创建 ACP 会话'));
      await scene.until(
        () {
          final failure = graph.client.drafts.attachments.state
              .newThread(project.id)
              .failure;
          if (failure != null) throw StateError('ACP create failed: $failure');
          return find.byType(AcpComposerConnector).evaluate().length == 1;
        },
        'explicit session/new completes without prompting',
        // A live server starts its external harness here. It can take longer
        // than the local fixture's default deadline; this never retries new.
        timeout: const Duration(seconds: 90),
      );
      final threadId = tester
          .widget<AcpComposerConnector>(find.byType(AcpComposerConnector))
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
      if (remote != null) {
        expect(
          options,
          isNotNull,
          reason: 'Remote acceptance requires real configOptions',
        );
      }
      if (options != null) {
        final selects = options.where((option) {
          final kind = option.kind;
          return kind is AcpSelectConfigView &&
              _values(kind).any((value) => value.value != kind.currentValue);
        }).toList();
        selects.sort((a, b) => _priority(a).compareTo(_priority(b)));
        expect(selects, isNotEmpty, reason: 'No real alternate select config');
        final option = selects.first;
        final kind = option.kind as AcpSelectConfigView;
        final alternate = _values(kind)
            .firstWhere((value) => value.value != kind.currentValue);
        final controlAnchor = find.byKey(
          ValueKey(AcpViewKeyValues.configControl(option.id.value)),
        );
        if (controlAnchor.evaluate().isEmpty) {
          // If placed in the overflow popover, open "More settings" first.
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey(AcpViewKeyValues.configOverflow)),
              matching: find.byType(TextButton),
            ),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.descendant(
            of: find.byKey(
              ValueKey(AcpViewKeyValues.configControl(option.id.value)),
            ),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              AcpViewKeyValues.configChoice(
                option.id.value,
                alternate.value.value,
              ),
            ),
          ),
        );
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
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey(AcpViewKeyValues.configLegacyMode)),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              AcpViewKeyValues.configChoice(
                AcpViewKeyValues.configLegacyMode,
                alternate.id.value,
              ),
            ),
          ),
        );
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

      evidence['promptCount'] = 1;
      evidence['marker'] = marker;
      await record('prompt-dispatch-once');
      await tester.tap(
        find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction(threadId))),
      );
      await scene.until(
        () {
          checkOwner();
          if (remote != null && owner.state.pendingPermissions.isNotEmpty) {
            throw StateError(
              'Live remote run requires explicit permission handling; '
              'no blanket approval or bypass is allowed',
            );
          }
          return owner.state.lastCompleted != null;
        },
        'actual prompt terminal result',
        timeout: Duration(seconds: remote == null ? 120 : 240),
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
      final assistantMessages = owner.state.content
          .whereType<AcpConversationMessageItem>()
          .where((item) => item.kind == AcpConversationMessageKind.assistant)
          .toList();
      expect(assistantMessages, isNotEmpty);
      // Tool-driven acceptance may include legitimate progress messages.
      // Match the final response, not a concatenation of progress and final.
      final responseMessages = remote == null
          ? assistantMessages
          : [assistantMessages.last];
      final text = responseMessages
          .expand((item) => item.chunks)
          .map((chunk) => chunk.content)
          .whereType<AcpTextContentView>()
          .map((block) => block.text)
          .join();
      expect(text.trim(), marker);
      expect(owner.state.pendingPermissions, isEmpty);
      evidence['stopReason'] = stop.name;
      evidence['actualAssistantText'] = text;
      if (remote != null) {
        final tools = owner.state.content
            .whereType<AcpConversationToolItem>()
            .where(
              (item) => (item.fields.name ?? item.fields.title ?? '').contains(
                'anywork_',
              ),
            )
            .toList();
        expect(
          tools,
          isNotEmpty,
          reason: 'Expected real Host MCP tool updates',
        );
        expect(
          tools.map((item) => item.fields.status),
          everyElement(AcpToolCallStatusView.completed),
        );
        evidence['hostToolCalls'] = [
          for (final item in tools)
            {
              'toolCallId': item.toolCallId.value,
              'name': item.fields.name,
              'status': item.fields.status?.name,
            },
        ];
        evidence['remoteReadback'] = await remote.verifyResult(marker);
        final trace = AgyHostTrace(owner.state.content);
        evidence['taskLifecycle'] = trace.verifyTasks(
          marker,
          remote.processCommand,
        );
        evidence['childReport'] = trace.verifyChild(
          childProfileId,
          marker,
          owner.state.target!.agentId,
        );
        evidence['cancellation'] =
            'terminal payload and independent process exit';
        await record('independent-remote-file-command-readback-confirmed');
      }
      await record('actual-text-and-end-turn-confirmed');
      final assistantIndex = owner.state.content.lastIndexWhere(
        (item) =>
            item is AcpConversationMessageItem &&
            item.kind == AcpConversationMessageKind.assistant,
      );
      final assistantItem = find.byKey(
        ValueKey(AcpViewKeyValues.timelineItem(threadId, assistantIndex)),
      );
      await tester.scrollUntilVisible(
        assistantItem,
        250,
        scrollable: find
            .descendant(
              of: find.byType(AcpConversationContentView),
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
      if (remote != null) {
        final processes = AgyLocalProcesses();
        await processes.capture(command!);
        evidence['localOwnedBeforeClose'] = processes.evidence;
        evidence['actualLocalAgyExecutableObserved'] = true;
        await record('local-and-remote-process-identities-captured');
        final close = await owner.closeMember();
        evidence['acpClose'] = {
          'localComplete': close.localComplete,
          'sdkFinished': close.sdkFinished,
          'cleanupTimedOut': close.cleanupTimedOut,
          'unfinishedControls': close.unfinishedControls,
          'ownerFailureCount': close.ownerFailures.length,
          'remoteCloseErrorPresent': close.remoteCloseError != null,
          'sdkErrorPresent': close.sdkError != null,
          'workerErrorPresent': close.workerError != null,
          'driverErrorPresent': close.driverError != null,
        };
        await record('acp-member-close-returned');
        expect(close.localComplete, isTrue);
        expect(close.sdkFinished, isTrue);
        expect(close.cleanupTimedOut, isFalse);
        expect(close.unfinishedControls, isFalse);
        expect(close.unfinishedPrompt, isNull);
        expect(close.ownerFailures, isEmpty);
        expect(close.remoteCloseError, isNull);
        expect(close.sdkError, isNull);
        expect(close.workerError, isNull);
        expect(close.driverError, isNull);
        await scene.dispose();
        await closeHarness();
        evidence['remoteExitedAfterClose'] = await remote
            .verifyClosedProcesses();
        await processes.verifyClosed();
        evidence['localOwnedExited'] = true;
      }
      evidence['verdict'] = remote == null
          ? 'text-scenario-passed'
          : 'acp-remote-scenario-passed';
      await record('scenario-assertions-complete');
    },
    timeout: const Timeout(Duration(minutes: 10)),
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
