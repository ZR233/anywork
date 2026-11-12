import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/production_studio_harness.dart';
import 'support/sidebar_fixture.dart';

// Run only through the session-owned thread_lsp_status_setup.sh delivered with
// this task.
// It supplies a fresh sandbox and builds the existing pl-provider-fixture
// binary. This test creates two projects, their same-ID LSP TOML fixtures and
// two Native Threads through production Client commands. It never opens an
// account or data root outside that sandbox.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'Native Thread LSP status is scoped and reload targets its binding',
    (tester) async {
      expect(
        Platform.operatingSystem,
        'linux',
        reason: 'This case uses the Linux LSP fixture process identity record',
      );
      final sandboxPath = _requiredEnvironment('ANYWORK_THREAD_LSP_SANDBOX');
      final homePath = _requiredEnvironment('ANYWORK_HOME');
      final projectAPath = _requiredEnvironment('ANYWORK_THREAD_LSP_PROJECT_A');
      final projectBPath = _requiredEnvironment('ANYWORK_THREAD_LSP_PROJECT_B');
      final outputPath = _requiredEnvironment('ANYWORK_THREAD_LSP_OUTPUT');
      final fixturePath = _requiredEnvironment('ANYWORK_THREAD_LSP_FIXTURE');
      final sandbox = Directory(sandboxPath);
      if (!await sandbox.exists()) {
        throw StateError('The setup script must create the fresh sandbox');
      }
      final canonicalSandbox = await sandbox.resolveSymbolicLinks();
      final home = Directory(homePath);
      expect(
        p.equals(homePath, p.join(canonicalSandbox, 'studio-home')),
        isTrue,
      );
      expect(
        p.equals(projectAPath, p.join(canonicalSandbox, 'project-a')),
        isTrue,
      );
      expect(
        p.equals(projectBPath, p.join(canonicalSandbox, 'project-b')),
        isTrue,
      );
      expect(
        p.equals(outputPath, p.join(canonicalSandbox, 'artifacts')),
        isTrue,
      );
      expect(p.isWithin(canonicalSandbox, homePath), isTrue);
      expect(p.isWithin(canonicalSandbox, projectAPath), isTrue);
      expect(p.isWithin(canonicalSandbox, projectBPath), isTrue);
      expect(p.isWithin(canonicalSandbox, outputPath), isTrue);
      if (await home.exists() ||
          await Directory(projectAPath).exists() ||
          await Directory(projectBPath).exists() ||
          await Directory(outputPath).exists()) {
        throw StateError(
          'Refusing to use an existing home, project, or output directory',
        );
      }
      if (!await File(fixturePath).exists()) {
        throw StateError('The isolated LSP fixture executable is missing');
      }

      final existingSandboxEntries = await sandbox.list().toList();
      if (existingSandboxEntries.isNotEmpty) {
        throw StateError(
          'Refusing a non-empty LSP sandbox: '
          '${existingSandboxEntries.map((entry) => p.basename(entry.path))}',
        );
      }

      await home.create(recursive: true);
      final projectA = Directory(projectAPath);
      final projectB = Directory(projectBPath);
      await projectA.create(recursive: true);
      await projectB.create(recursive: true);
      final coordinateA = p.join(canonicalSandbox, 'lsp-a-process.json');
      final coordinateB = p.join(canonicalSandbox, 'lsp-b-process.json');
      final configA = await _writeLspConfig(
        project: projectA,
        displayName: 'Thread A LSP fixture · ready',
        command: fixturePath,
        args: ['--lsp-stdio', '--coord-file', coordinateA],
      );
      final missingCommand = p.join(canonicalSandbox, 'missing-lsp-command');
      final configB = await _writeLspConfig(
        project: projectB,
        displayName: 'Thread B LSP fixture · unavailable',
        command: missingCommand,
      );

      final snapshots = <String, Object?>{};
      final screenshots = <String>[];
      final evidence = <String, Object?>{
        'platform': Platform.operatingSystem,
        'nativeRunnerPid': pid,
        'sandbox': canonicalSandbox,
        'projects': {'A': projectAPath, 'B': projectBPath},
        'lspConfigId': 'thread-lsp-status-probe',
        'lspConfigPaths': {'A': configA.path, 'B': configB.path},
        'realModelProvider': false,
        'syntheticAccountCredential': 'clear; no keyring entry',
        'threadCreation': 'public Client threadCommands.submitNewThread',
        'snapshots': snapshots,
        'screenshots': screenshots,
        'reload': <String, Object?>{},
      };
      await Directory(outputPath).create(recursive: true);
      final reportFile = File(p.join(outputPath, 'thread-lsp-status.json'));

      ProductionStudioHarness? harness;
      ProductionStudioScene? scene;
      SidebarProviderFixture? provider;
      var sceneDisposed = false;
      var harnessClosed = false;
      var providerClosed = false;
      Object? testFailure;
      StackTrace? testFailureStack;

      Future<void> writeReport() async {
        await reportFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            ...evidence,
            if (testFailure != null) 'failure': testFailure.toString(),
            if (testFailureStack != null)
              'failureStack': testFailureStack.toString(),
          }),
          flush: true,
        );
      }

      addTearDown(() async {
        Object? cleanupFailure;
        StackTrace? cleanupStack;
        try {
          if (!sceneDisposed && scene != null) {
            await scene.dispose();
            sceneDisposed = true;
          }
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          evidence['sceneDisposeFailure'] = error.toString();
        }
        try {
          if (!harnessClosed && harness != null) {
            await harness.close();
            harnessClosed = true;
          }
          final shutdown = File(p.join(outputPath, 'sidebar-shutdown.json'));
          if (await shutdown.exists()) {
            evidence['productionShutdown'] = jsonDecode(
              await shutdown.readAsString(),
            );
          }
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          evidence['productionShutdownFailure'] = error.toString();
        }
        try {
          if (!providerClosed && provider != null) {
            await provider.close();
            providerClosed = true;
          }
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          evidence['loopbackFixtureShutdownFailure'] = error.toString();
        }
        try {
          final processes = evidence['ownedLspProcesses'] as List? ?? const [];
          final remaining = <Map<String, Object?>>[];
          for (final raw in processes) {
            final process = (raw as Map).cast<String, Object?>();
            if (await _sameLinuxProcess(process)) remaining.add(process);
          }
          evidence['ownedLspProcessesStillPresent'] = remaining;
          evidence['loopbackRequests'] = provider?.requests;
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          evidence['processObservationFailure'] = error.toString();
        } finally {
          await writeReport();
        }
        if (cleanupFailure != null) {
          Error.throwWithStackTrace(cleanupFailure, cleanupStack!);
        }
        expect(
          evidence['ownedLspProcessesStillPresent'],
          isEmpty,
          reason: 'The production shutdown must reclaim this case’s LSP tree',
        );
      });

      try {
        final localProvider = await SidebarProviderFixture.start();
        provider = localProvider;
        final activeHarness = await ProductionStudioHarness.start(
          binding: binding,
          artifactsEnvironmentVariable: 'ANYWORK_THREAD_LSP_OUTPUT',
        );
        harness = activeHarness;
        final activeScene = await activeHarness.mount(tester);
        scene = activeScene;
        final graph = activeHarness.graph;
        final accounts = graph.accounts.observeSummaries();
        addTearDown(accounts.release);

        await graph.accounts.state.waitFor((state) => state.loaded);
        await graph.accounts.loadTemplates();
        final template = graph.accounts.state.value.templates.templates
            .where((candidate) => candidate.protocol == 'open_ai_compatible')
            .single;
        const accountId = 'thread-lsp-local-fixture';
        const modelId = SidebarFixture.modelId;
        const identity = NativeAccountIdentity(accountId);
        expect(graph.accounts.state.value.account(identity), isNull);
        final created = await graph.accounts.create(
          CreateAccountCommand(
            identity: identity,
            name: 'Thread LSP local fixture',
            protocol: template.protocol,
            templateId: template.id,
            baseUrl: '${localProvider.origin}/v1',
            secret: const AccountSecretCommand.clear(),
            customModels: const [
              AccountModelCommand(
                modelId: modelId,
                displayName: 'Thread LSP local fixture model',
                wireApi: 'responses',
                contextWindow: 65536,
                maxOutputTokens: 4096,
              ),
            ],
          ),
        );
        if (created.error != null || !created.observed) {
          throw StateError(
            'Synthetic local fixture account failed: ${created.error}',
          );
        }
        final defaultAccount = await graph.accounts.setDefault(identity);
        if (defaultAccount.error != null) {
          throw StateError(
            'Synthetic local fixture route failed: ${defaultAccount.error}',
          );
        }
        await graph.accounts.state.waitFor(
          (state) => state.account(identity)?.isDefault == true,
        );
        const route = ModeModelRouteView(
          modeId: ThreadModeId.simple,
          accountId: accountId,
          modelId: modelId,
          effort: '',
        );

        final openedA = await activeHarness.openProject(
          activeScene,
          projectAPath,
        );
        final threadA = await _submitRoot(
          graph,
          openedA.id,
          inputId: 'thread-lsp-a-input',
          route: route,
        );
        final openedB = await activeHarness.openProject(
          activeScene,
          projectBPath,
        );
        final threadB = await _submitRoot(
          graph,
          openedB.id,
          inputId: 'thread-lsp-b-input',
          route: route,
        );
        expect(threadA.id, isNot(threadB.id));
        expect(threadA.workspaceId, openedA.id);
        expect(threadB.workspaceId, openedB.id);
        evidence['threads'] = {
          'A': {'threadId': threadA.id, 'workspaceId': threadA.workspaceId},
          'B': {'threadId': threadB.id, 'workspaceId': threadB.workspaceId},
        };

        graph.setConversationPageVisible(true);
        final snapshotA = await _openAndRead(
          activeScene,
          graph,
          threadA.id,
          serverName: 'Thread A LSP fixture · ready',
          expectedState: LspAvailableState,
          expectedLabel: 'ready',
        );
        final serverA = _onlyServer(snapshotA);
        expect(serverA.id, 'thread-lsp-status-probe');
        expect(serverA.configurationPath, contains(projectAPath));
        expect(snapshotA.bindingId, isNotNull);
        final initialCoord = await _readCoord(coordinateA);
        _recordOwnedProcesses(
          evidence,
          initialCoord,
          threadA.id,
          'beforeReset',
        );
        snapshots['A-before-reset'] = _snapshotJson(snapshotA);
        await activeScene.capture('thread-lsp-a-ready');
        screenshots.add('thread-lsp-a-ready.png');
        await _closeStartedItems(activeScene);

        final snapshotB = await _openAndRead(
          activeScene,
          graph,
          threadB.id,
          serverName: 'Thread B LSP fixture · unavailable',
          expectedState: LspUnavailableState,
          expectedLabel: 'failed',
        );
        final serverB = _onlyServer(snapshotB);
        expect(serverB.id, serverA.id);
        expect(serverB.displayName, isNot(serverA.displayName));
        expect(serverB.configurationPath, contains(projectBPath));
        expect(snapshotB.bindingId, isNotNull);
        expect(snapshotB.bindingId, isNot(snapshotA.bindingId));
        expect(await File(coordinateB).exists(), isFalse);
        snapshots['B-unavailable'] = _snapshotJson(snapshotB);
        await activeScene.capture('thread-lsp-b-unavailable');
        screenshots.add('thread-lsp-b-unavailable.png');
        await _closeStartedItems(activeScene);

        await _selectThread(activeScene, graph, threadB.id);
        await _openStartedItems(activeScene);
        final rowB = find.byKey(StudioDriverKeys.statusLspServer(serverB.id));
        final reloadB = find.byKey(StudioDriverKeys.lspResetServer(serverB.id));
        expect(rowB, findsOneWidget);
        expect(reloadB, findsOneWidget);
        expect(find.text(serverA.displayName), findsNothing);
        final localizations = AppLocalizations.of(tester.element(rowB));
        expect(
          find.descendant(
            of: rowB,
            matching: find.text(localizations.settingsLspPhaseFailed),
          ),
          findsOneWidget,
        );
        const recoveredName = 'Thread B LSP fixture · recovered';
        await _writeLspConfig(
          project: projectB,
          displayName: recoveredName,
          command: fixturePath,
          args: ['--lsp-stdio', '--coord-file', coordinateB],
        );
        evidence['reload'] = {
          'requestedThrough': 'StudioDriverKeys.lspResetServer',
          'threadId': snapshotB.threadId,
          'bindingId': snapshotB.bindingId,
          'serverId': serverB.id,
          'projectPath': projectBPath,
          'stateBefore': _snapshotJson(snapshotB),
          'configChangedInIsolatedProject': configB.path,
        };
        await tester.tap(reloadB);

        await activeScene.until(() {
          final coord = _tryReadCoord(coordinateB);
          final state = graph.client.existingThreadLsp(threadB.id)?.state.value;
          final server = state?.servers.where((item) => item.id == serverB.id);
          return coord != null &&
              state != null &&
              state.revision > snapshotB.revision &&
              server != null &&
              server.isNotEmpty &&
              server.first.displayName == recoveredName &&
              server.first.state is LspAvailableState;
        }, 'B’s failed LSP becomes ready in the open status popover');
        final snapshotBAfter = graph.client
            .existingThreadLsp(threadB.id)!
            .state
            .value!;
        final afterResetCoord = await _readCoord(coordinateB);
        _recordOwnedProcesses(
          evidence,
          afterResetCoord,
          threadB.id,
          'recoveredAfterReset',
        );
        expect(snapshotBAfter.bindingId, snapshotB.bindingId);
        expect(_onlyServer(snapshotBAfter).id, serverB.id);
        expect(snapshotBAfter.revision, greaterThan(snapshotB.revision));
        expect(
          find.byKey(StudioDriverKeys.statusLspServer(serverB.id)),
          findsOneWidget,
        );
        expect(find.text(recoveredName), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(StudioDriverKeys.statusLspServer(serverB.id)),
            matching: find.text(localizations.settingsLspPhaseReady),
          ),
          findsOneWidget,
        );

        final snapshotAAfter = await graph.client.directoryCommands
            .readThreadLspState(threadA.id);
        final coordinateAAfter = await _readCoord(coordinateA);
        expect(_snapshotJson(snapshotAAfter), _snapshotJson(snapshotA));
        expect(coordinateAAfter, initialCoord);
        snapshots['A-after-reset-of-B'] = _snapshotJson(snapshotAAfter);
        snapshots['B-after-reset'] = _snapshotJson(snapshotBAfter);
        (evidence['reload'] as Map<String, Object?>)['newProcess'] =
            afterResetCoord;
        (evidence['reload'] as Map<String, Object?>)['unaffectedAProcess'] =
            coordinateAAfter;
        await activeScene.capture('thread-lsp-b-after-reset');
        screenshots.add('thread-lsp-b-after-reset.png');
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        testFailure = error;
        testFailureStack = stack;
        rethrow;
      }
    },
  );
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) throw StateError('Supply $name');
  return value;
}

Future<File> _writeLspConfig({
  required Directory project,
  required String displayName,
  required String command,
  List<String> args = const [],
}) async {
  final directory = Directory(p.join(project.path, '.anywork', 'lsp'));
  await directory.create(recursive: true);
  final config = File(p.join(directory.path, 'thread-lsp-status-probe.toml'));
  await config.writeAsString(
    [
      'schema_version = 1',
      'id = "thread-lsp-status-probe"',
      'display_name = ${jsonEncode(displayName)}',
      'command = ${jsonEncode(command)}',
      'args = ${jsonEncode(args)}',
      'language_ids = ["anywork-thread-lsp-fixture"]',
      'extensions = ["lspfixture"]',
      'detection = []',
      '',
    ].join('\n'),
    flush: true,
  );
  return config;
}

Future<StudioThread> _submitRoot(
  AppGraph graph,
  String workspaceId, {
  required String inputId,
  required ModeModelRouteView route,
}) async {
  final result = await graph.client.threadCommands.submitNewThread(
    workspaceId: workspaceId,
    input: StudioPromptInput(
      inputId: inputId,
      text: 'Create an isolated LSP status test session.',
      attachmentDraftIds: const [],
    ),
    mode: ThreadModeId.simple,
    route: route,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    onProgress: (_) {},
  );
  if (result == null) {
    throw StateError('The local fixture did not create a Native Thread');
  }
  return result.thread;
}

Future<ThreadLspStateSnapshot> _openAndRead(
  ProductionStudioScene scene,
  AppGraph graph,
  String threadId, {
  required String serverName,
  required Type expectedState,
  required String expectedLabel,
}) async {
  await _selectThread(scene, graph, threadId);
  await _openStartedItems(scene);
  final trigger = find.byKey(StudioDriverKeys.statusStartedItems);
  final row = find.byKey(
    StudioDriverKeys.statusLspServer('thread-lsp-status-probe'),
  );
  await scene.until(
    () => row.evaluate().length == 1,
    'the production started-items panel contains this Thread’s LSP row',
  );
  final localizations = AppLocalizations.of(scene.tester.element(row));
  final label = switch (expectedLabel) {
    'ready' => localizations.settingsLspPhaseReady,
    'failed' => localizations.settingsLspPhaseFailed,
    _ => throw StateError('Unsupported expected LSP label: $expectedLabel'),
  };
  await scene.until(
    () => find
        .descendant(of: row, matching: find.text(label))
        .evaluate()
        .isNotEmpty,
    'the visible LSP state label is $expectedLabel',
  );
  final snapshot = await graph.client.directoryCommands.readThreadLspState(
    threadId,
  );
  expect(snapshot.threadId, threadId);
  expect(snapshot.servers, hasLength(1));
  expect(snapshot.servers.single.displayName, serverName);
  expect(snapshot.servers.single.state.runtimeType, expectedState);
  expect(trigger, findsOneWidget);
  return snapshot;
}

Future<void> _selectThread(
  ProductionStudioScene scene,
  AppGraph graph,
  String threadId,
) async {
  await graph.client.directoryCommands.selectThread(threadId);
  await graph.client.directoryCommands.openSelectedThread();
  await scene.until(
    () =>
        graph.client.selection.state.selectedThreadId == threadId &&
        find.byKey(StudioDriverKeys.statusStartedItems).evaluate().length == 1,
    'the production page is open on Thread $threadId',
  );
}

Future<void> _openStartedItems(ProductionStudioScene scene) async {
  final tester = scene.tester;
  final trigger = find.byKey(StudioDriverKeys.statusStartedItems);
  await scene.until(
    () => trigger.evaluate().length == 1,
    'started-items button',
  );
  await tester.tap(trigger);
  await scene.until(
    () =>
        find.byKey(StudioDriverKeys.statusStartedItems).evaluate().length ==
            1 &&
        find
                .byKey(
                  StudioDriverKeys.statusLspServer('thread-lsp-status-probe'),
                )
                .evaluate()
                .length ==
            1,
    'started-items popover opened',
  );
}

Future<void> _closeStartedItems(ProductionStudioScene scene) async {
  final trigger = find.byKey(StudioDriverKeys.statusStartedItems);
  if (find
      .byKey(StudioDriverKeys.statusLspServer('thread-lsp-status-probe'))
      .evaluate()
      .isEmpty) {
    return;
  }
  await scene.tester.tap(trigger);
  await scene.until(
    () => find
        .byKey(StudioDriverKeys.statusLspServer('thread-lsp-status-probe'))
        .evaluate()
        .isEmpty,
    'started-items popover closed',
  );
}

LspServerStateView _onlyServer(ThreadLspStateSnapshot snapshot) {
  expect(snapshot.servers, hasLength(1));
  return snapshot.servers.single;
}

Map<String, Object?> _snapshotJson(ThreadLspStateSnapshot snapshot) => {
  'threadId': snapshot.threadId,
  'revision': snapshot.revision,
  'bindingId': snapshot.bindingId,
  'servers': snapshot.servers
      .map(
        (server) => {
          'id': server.id,
          'displayName': server.displayName,
          'configurationPath': server.configurationPath,
          'phase': server.phase,
          'state': _serverStateJson(server.state),
        },
      )
      .toList(growable: false),
};

Map<String, Object?> _serverStateJson(LspServerState state) => switch (state) {
  LspAvailableState(
    :final checkedAt,
    :final diagnosticCount,
    :final activity,
  ) =>
    {
      'kind': 'available',
      'checkedAt': checkedAt,
      'diagnosticCount': diagnosticCount,
      'activity': activity.runtimeType.toString(),
    },
  LspUnavailableState(
    :final checkedAt,
    :final code,
    :final message,
    :final retryable,
  ) =>
    {
      'kind': 'unavailable',
      'checkedAt': checkedAt,
      'code': code,
      'message': message,
      'retryable': retryable,
    },
  LspCheckingState(:final message) => {'kind': 'checking', 'message': message},
  LspDisabledState(:final message) => {'kind': 'disabled', 'message': message},
};

Future<Map<String, Object?>> _readCoord(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('The expected LSP process record is missing: $path');
  }
  return (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
}

Map<String, Object?>? _tryReadCoord(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

void _recordOwnedProcesses(
  Map<String, Object?> evidence,
  Map<String, Object?> coord,
  String threadId,
  String generation,
) {
  final processes = evidence.putIfAbsent(
    'ownedLspProcesses',
    () => <Map<String, Object?>>[],
  ) as List<Map<String, Object?>>;
  for (final role in ['lsp', 'grandchild']) {
    final pid = coord['${role}Pid'];
    final startTicks = coord['${role}StartTicks'];
    if (pid is! int || startTicks is! int) {
      throw StateError(
        'The LSP fixture omitted PID/start-time identity for $role',
      );
    }
    processes.add({
      'threadId': threadId,
      'generation': generation,
      'role': role,
      'pid': pid,
      'startTicks': startTicks,
    });
  }
}

Future<bool> _sameLinuxProcess(Map<String, Object?> process) async {
  if (Platform.operatingSystem != 'linux') return false;
  final pid = process['pid'] as int;
  final expectedStartTicks = process['startTicks'] as int;
  final stat = File('/proc/$pid/stat');
  if (!await stat.exists()) return false;
  final content = await stat.readAsString();
  final commandEnd = content.lastIndexOf(')');
  if (commandEnd < 0) return true;
  final fields = content.substring(commandEnd + 1).trim().split(RegExp(r'\s+'));
  // The suffix starts at proc stat field 3; starttime is field 22.
  if (fields.length <= 19) return true;
  return int.tryParse(fields[19]) == expectedStartTicks;
}
