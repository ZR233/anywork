import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'realtime_journey.dart'
    show
        isDurableSettled,
        summarize,
        threadFaulted,
        timelineRows,
        turnId,
        turnStatus;
import 'sidebar_navigation.dart' show clearSidebarSearch, revealSidebarThread;
import 'timeline_observation.dart'
    show
        TimelineObservation,
        TimelineViewportStability,
        timelineViewportSettled;

const _directoryMarker = '[[delegation:worktree:directory]]';
const _dirtyMarker = '[[delegation:worktree:dirty]]';
const _guardsMarker = '[[delegation:worktree:guards]]';
const _nestedMarker = '[[delegation:worktree:nested]]';
const _reopenMarker = '[[delegation:worktree:reopen]]';
const _handoffName = 'delegation-worktree-observed.json';
const _stageTimeout = Duration(minutes: 8);
const _pollInterval = Duration(milliseconds: 250);

Future<void> main(List<String> args) async {
  if (args.length != 6 || !const {'first', 'reopen'}.contains(args[4])) {
    stderr.writeln(
      'usage: delegation_worktree_journey.dart VM_URL PROJECT_DIR OUTPUT_DIR ENVIRONMENT_ROOT first|reopen FIXTURE_ORIGIN',
    );
    exitCode = 64;
    return;
  }

  final vmUrl = args[0];
  final projectPath = args[1];
  final output = Directory(args[2]);
  final environment = Directory(args[3]);
  final phase = args[4];
  final Uri fixtureOrigin;
  try {
    fixtureOrigin = _parseFixtureOrigin(args[5]);
  } on FormatException catch (error) {
    stderr.writeln('usage error: ${error.message}');
    exitCode = 64;
    return;
  }

  await output.create(recursive: true);
  await environment.create(recursive: true);
  final http = HttpClient();
  FlutterDriverSession? driver;
  Object? failure;
  Object? artifactFailure;
  Object? closeFailure;
  var stage = 'connect';
  Map<String, dynamic>? lastSnapshot;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: vmUrl);
    final journey = _Journey(
      driver: driver,
      projectPath: projectPath,
      output: output,
      environment: environment,
      fixtureOrigin: fixtureOrigin,
      http: http,
      setStage: (value) => stage = value,
      observe: (snapshot) => lastSnapshot = snapshot,
    );
    if (phase == 'first') {
      await journey.first();
    } else {
      await journey.reopen();
    }
  } catch (error, stackTrace) {
    failure = error;
    try {
      final diagnostic = <String, Object?>{
        'stage': stage,
        'error': _redactConnectionValues('$error', vmUrl, fixtureOrigin),
        'stackTrace': _redactConnectionValues(
          '$stackTrace',
          vmUrl,
          fixtureOrigin,
        ),
        'snapshot': lastSnapshot == null ? null : summarize(lastSnapshot!),
      };
      await File(
        '${output.path}/failure.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(diagnostic));
      if (lastSnapshot != null) {
        await _writeJson(
          File('${output.path}/failure-snapshot.json'),
          lastSnapshot!,
        );
      }
    } catch (diagnosticError, diagnosticStack) {
      artifactFailure = diagnosticError;
      stderr.writeln(
        'diagnostic artifact failure trace: ${_redactConnectionValues('$diagnosticStack', vmUrl, fixtureOrigin)}',
      );
    }
  } finally {
    http.close(force: true);
    if (driver != null) {
      try {
        await driver.close().timeout(const Duration(seconds: 5));
      } catch (error, stackTrace) {
        closeFailure = error;
        stderr.writeln(
          'Driver cleanup failure trace: ${_redactConnectionValues('$stackTrace', vmUrl, fixtureOrigin)}',
        );
      }
    }
  }
  if (artifactFailure != null) {
    stderr.writeln(
      'diagnostic artifact failure: ${_redactConnectionValues('$artifactFailure', vmUrl, fixtureOrigin)}',
    );
    failure ??= artifactFailure;
  }
  if (closeFailure != null) {
    stderr.writeln(
      'Driver cleanup failure: ${_redactConnectionValues('$closeFailure', vmUrl, fixtureOrigin)}',
    );
    failure ??= closeFailure;
  }
  if (failure != null) {
    stderr.writeln(
      'Journey failed: ${_redactConnectionValues('$failure', vmUrl, fixtureOrigin)}',
    );
    exitCode = 1;
  }
}

String _redactConnectionValues(
  String message,
  String vmUrl,
  Uri fixtureOrigin,
) {
  var safe = message;
  if (vmUrl.isNotEmpty) safe = safe.replaceAll(vmUrl, '<VM_URL>');
  return safe.replaceAll(fixtureOrigin.toString(), '<FIXTURE_ORIGIN>');
}

Uri _parseFixtureOrigin(String value) {
  late final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    throw const FormatException(
      'FIXTURE_ORIGIN must be a valid loopback HTTP origin',
    );
  }
  if (uri.scheme != 'http' ||
      !const {
        'localhost',
        '127.0.0.1',
        '::1',
      }.contains(uri.host.toLowerCase()) ||
      uri.authority.contains('@') ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'FIXTURE_ORIGIN must be an HTTP loopback origin without credentials, path, query, or fragment',
    );
  }
  return uri;
}

final class _Journey {
  _Journey({
    required this.driver,
    required this.projectPath,
    required this.output,
    required this.environment,
    required this.fixtureOrigin,
    required this.http,
    required this.setStage,
    required this.observe,
  });

  final FlutterDriverSession driver;
  final String projectPath;
  final Directory output;
  final Directory environment;
  final Uri fixtureOrigin;
  final HttpClient http;
  final void Function(String) setStage;
  final void Function(Map<String, dynamic>) observe;
  final Map<String, String> turns = {};
  final Map<String, Map<String, Object?>> providerReceipts = {};
  final Map<String, Map<String, Object?>> stageRows = {};
  Map<String, dynamic>? latest;

  Future<void> first() async {
    final handoff = File('${environment.path}/$_handoffName');
    if (await handoff.exists()) {
      throw StateError('first phase refuses to overwrite existing handoff');
    }
    setStage('open-project');
    await _openProject();
    await _waitFor((state) {
      final navigation = _map(state['navigation']);
      final project = _map(state['project']);
      return navigation?['selectedProjectId'] is String &&
          (navigation!['selectedProjectId'] as String).isNotEmpty &&
          project?['id'] == navigation['selectedProjectId'] &&
          project?['path'] == projectPath;
    }, 'canonical project selection');
    final projectId = _requiredString(
      _map(latest!['project'])?['id'],
      'project.id',
    );

    setStage('configure-local-root');
    await _configureRoot(projectId, worktree: false);
    await _capture('workspace-settings');

    final directoryReceipt = await _submitAndWait(
      label: 'directory',
      marker: _directoryMarker,
      note: 'worktree_directory_baseline_complete',
      expectedPhase: 'directory',
    );
    final directoryRoot = _requiredString(
      directoryReceipt['rootAgentId'],
      'directory rootAgentId',
    );
    final localSidebar = _sidebar(latest!);
    _expect(
      localSidebar['workspaceModes']?[directoryRoot] == 'local',
      'directory root is not shown as local',
    );
    _requiredString(
      localSidebar['workspacePaths']?[directoryRoot],
      'directory workspace path',
    );
    await _capture('directory');

    final dirtyReceipt = await _submitAndWait(
      label: 'dirty',
      marker: _dirtyMarker,
      note: 'worktree_dirty_admission_complete',
      expectedPhase: 'dirty',
      rootId: directoryRoot,
    );
    final guardsReceipt = await _submitAndWait(
      label: 'guards',
      marker: _guardsMarker,
      note: 'worktree_cleanup_guards_complete',
      expectedPhase: 'guards',
      rootId: directoryRoot,
    );
    await _capture('directory-guards');

    setStage('new-worktree-root');
    await _tap('sidebar-new-session');
    await _waitFor(
      (state) => _map(state['navigation'])?['selectedThreadId'] == null,
      'new session start page',
    );
    await _configureRoot(projectId, worktree: true);
    _expect(
      _map(latest!['navigation'])?['newThreadWorkspaceMode'] == 'worktree',
      'new thread workspace mode is not worktree',
    );
    await _capture('worktree-settings');
    final nestedReceipt = await _submitAndWait(
      label: 'nested',
      marker: _nestedMarker,
      note: 'worktree_nested_baseline_complete',
      expectedPhase: 'nested',
    );
    final nestedRoot = _requiredString(
      nestedReceipt['rootAgentId'],
      'nested rootAgentId',
    );
    _expect(
      nestedRoot != directoryRoot,
      'nested and directory root ids must differ',
    );
    final nestedSidebar = _sidebar(latest!);
    _expect(
      nestedSidebar['workspaceModes']?[nestedRoot] == 'worktree',
      'nested root is not shown as worktree',
    );
    final directoryPath = _requiredString(
      nestedSidebar['workspacePaths']?[directoryRoot],
      'directory workspace path',
    );
    final nestedPath = _requiredString(
      nestedSidebar['workspacePaths']?[nestedRoot],
      'nested workspace path',
    );
    _expect(directoryPath != nestedPath, 'root workspace paths must differ');
    await _capture('nested');

    final handoffValue = <String, Object?>{
      'schemaVersion': 1,
      'phase': 'first',
      'humanVerdict': 'pending',
      'projectId': projectId,
      'projectPath': projectPath,
      'directoryRootId': directoryRoot,
      'nestedRootId': nestedRoot,
      'workspacePaths': {directoryRoot: directoryPath, nestedRoot: nestedPath},
      'turnIds': Map<String, String>.from(turns),
      'providerOrdinals': {
        for (final entry in providerReceipts.entries)
          entry.key: entry.value['ordinal'],
      },
      'stageRows': stageRows,
      'receipts': {
        'directory': directoryReceipt,
        'dirty': dirtyReceipt,
        'guards': guardsReceipt,
        'nested': nestedReceipt,
      },
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await handoff.create(exclusive: true);
    await handoff.writeAsString(
      const JsonEncoder.withIndent('  ').convert(handoffValue),
      flush: true,
    );
    await _capture('first-final');
  }

  Future<void> reopen() async {
    final handoffFile = File('${environment.path}/$_handoffName');
    if (!await handoffFile.exists()) {
      throw StateError('first-phase handoff is missing');
    }
    final decoded = jsonDecode(await handoffFile.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['phase'] != 'first' ||
        decoded['humanVerdict'] != 'pending') {
      throw const FormatException('invalid delegation worktree handoff');
    }
    final directoryRoot = _requiredString(
      decoded['directoryRootId'],
      'directoryRootId',
    );
    final nestedRoot = _requiredString(decoded['nestedRootId'], 'nestedRootId');
    final expectedProjectId = _requiredString(
      decoded['projectId'],
      'projectId',
    );
    final savedStageRows =
        _map(decoded['stageRows']) ??
        (throw const FormatException('handoff stageRows missing'));
    final savedWorkspacePaths =
        _map(decoded['workspacePaths']) ??
        (throw const FormatException('handoff workspacePaths missing'));
    _expect(
      decoded['projectPath'] == projectPath,
      'handoff project path differs from invocation',
    );

    setStage('reopen-directory-history');
    await revealSidebarThread(driver, directoryRoot);
    await _tap('thread-row-$directoryRoot');
    await clearSidebarSearch(driver);
    await _waitFor(
      (state) {
        final nav = _map(state['navigation']);
        final workspace = _map(state['workspace']);
        return nav?['selectedThreadId'] == directoryRoot &&
            workspace != null &&
            workspace['threadId'] == directoryRoot &&
            turnId(state) == _stageTurn(savedStageRows, 'guards') &&
            workspace['syncState'] == 'ready' &&
            workspace['threadStatus'] != 'faulted';
      },
      'directory history loaded',
      expectedThreadId: directoryRoot,
    );
    _expect(
      _map(latest!['project'])?['id'] == expectedProjectId,
      'reopened project identity differs',
    );
    _assertRootIdentity(
      latest!,
      directoryRoot,
      'local',
      savedWorkspacePaths[directoryRoot],
    );
    _expect(
      turnId(latest!) == _stageTurn(savedStageRows, 'guards'),
      'reopened directory root latest Turn differs from saved guards Turn',
    );
    _assertRootIdentity(
      latest!,
      nestedRoot,
      'worktree',
      savedWorkspacePaths[nestedRoot],
    );
    await _collectAndVerifyHistory(
      <String, Map<String, dynamic>>{
        for (final label in const ['directory', 'dirty', 'guards'])
          label: _requiredStage(savedStageRows, label),
      },
      'directory',
      expectedThreadId: directoryRoot,
    );
    await _capture('reopen-before');
    await revealSidebarThread(driver, nestedRoot);
    await _tap('thread-row-$nestedRoot');
    await clearSidebarSearch(driver);
    await _waitFor(
      (state) =>
          _map(state['navigation'])?['selectedThreadId'] == nestedRoot &&
          _map(state['workspace'])?['threadId'] == nestedRoot &&
          turnId(state) == _stageTurn(savedStageRows, 'nested') &&
          _map(state['workspace'])?['syncState'] == 'ready',
      'nested history loaded',
      expectedThreadId: nestedRoot,
    );
    _assertRootIdentity(
      latest!,
      nestedRoot,
      'worktree',
      savedWorkspacePaths[nestedRoot],
    );
    _expect(
      turnId(latest!) == _stageTurn(savedStageRows, 'nested'),
      'reopened nested root latest Turn differs from saved nested Turn',
    );
    await _collectAndVerifyHistory(
      <String, Map<String, dynamic>>{
        'nested': _requiredStage(savedStageRows, 'nested'),
      },
      'nested',
      expectedThreadId: nestedRoot,
    );
    await _capture('nested-reopen-before');

    await revealSidebarThread(driver, directoryRoot);
    await _tap('thread-row-$directoryRoot');
    await clearSidebarSearch(driver);
    await _waitFor(
      (state) =>
          _map(state['navigation'])?['selectedThreadId'] == directoryRoot &&
          _map(state['workspace'])?['threadId'] == directoryRoot &&
          _map(state['workspace'])?['syncState'] == 'ready',
      'directory root selected before reopen submit',
      expectedThreadId: directoryRoot,
    );
    final beforeProvider = await _providerState();
    _assertProviderHealthy(beforeProvider);
    final beforeProviderOrdinal = _latestOrdinal(beforeProvider);
    await _writeJson(
      File('${output.path}/reopen-before.provider.json'),
      <String, Object?>{
        'observedOrdinal': beforeProviderOrdinal,
        'observationCount': (beforeProvider['observations'] as List).length,
        'humanVerdict': 'pending',
      },
    );
    await _capture('reopen-before');

    final receipt = await _submitAndWait(
      label: 'reopen',
      marker: _reopenMarker,
      note: 'worktree_reopened_complete',
      expectedPhase: 'reopen',
      rootId: directoryRoot,
    );
    _expect(
      receipt['rootAgentId'] == directoryRoot,
      'reopen receipt root does not match directory root',
    );
    await _capture('reopen-result');

    setStage('verify-nested-history');
    await revealSidebarThread(driver, nestedRoot);
    await _tap('thread-row-$nestedRoot');
    await clearSidebarSearch(driver);
    await _waitFor(
      (state) =>
          _map(state['navigation'])?['selectedThreadId'] == nestedRoot &&
          _map(state['workspace'])?['threadId'] == nestedRoot &&
          _map(state['workspace'])?['syncState'] == 'ready',
      'nested history reselected',
      expectedThreadId: nestedRoot,
    );
    _assertRootIdentity(
      latest!,
      nestedRoot,
      'worktree',
      savedWorkspacePaths[nestedRoot],
    );
    _expect(
      turnId(latest!) == _stageTurn(savedStageRows, 'nested'),
      'nested root latest Turn changed after directory reopen',
    );
    await _capture('nested-reopened');
    await revealSidebarThread(driver, directoryRoot);
    await _tap('thread-row-$directoryRoot');
    await clearSidebarSearch(driver);
    await _waitFor(
      (state) =>
          _map(state['navigation'])?['selectedThreadId'] == directoryRoot &&
          _map(state['workspace'])?['threadId'] == directoryRoot &&
          _map(state['workspace'])?['syncState'] == 'ready',
      'directory root returned',
      expectedThreadId: directoryRoot,
    );
    _assertRootIdentity(
      latest!,
      directoryRoot,
      'local',
      savedWorkspacePaths[directoryRoot],
    );
    await _capture('reopen-final');
    await _writeJson(File('${output.path}/summary.json'), <String, Object?>{
      'humanVerdict': 'pending',
      'directoryRootId': directoryRoot,
      'nestedRootId': nestedRoot,
      'turnIds': turns,
      'stageRows': stageRows,
      'providerReceipts': providerReceipts,
      'automaticEvidence': receipt,
    });
  }

  Future<void> _openProject() async {
    await _tap('sidebar-open-project');
    await _tap('add-project-local');
    await driver.waitFor(
      find.byValueKey('add-project-continue-ready'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('add-project-continue-ready');
    await driver.waitFor(
      find.byValueKey('project-path-input'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('project-path-input');
    await driver.enterText(projectPath);
    await _tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _configureRoot(
    String projectId, {
    required bool worktree,
  }) async {
    await _tap('delegation-session-settings');
    await _tap('session-workspace-mode-selector');
    final workspaceChoice = worktree
        ? 'session-workspace-mode-worktree'
        : 'session-workspace-mode-local';
    await _tap(workspaceChoice);
    await _waitMenuClosed(workspaceChoice);

    await _tap('delegation-session-settings');
    await _ensureMenuChoice(
      'delegation-draft-mode',
      'delegation-draft-mode-automatic',
    );
    await _tap('delegation-session-settings');
    await _ensureMenuChoice(
      'delegation-draft-preference',
      'delegation-draft-preference-balanced',
    );
    final snapshot = await _read();
    final drafts = _map(snapshot['delegation'])?['drafts'];
    final draft = drafts is List
        ? drafts.whereType<Map>().cast<Map>().firstWhere(
            (item) => item['projectId'] == projectId,
            orElse: () => <String, Object?>{},
          )
        : <String, Object?>{};
    _expect(
      draft['effectiveMode'] == 'automatic',
      'automatic delegation draft not applied',
    );
    _expect(
      draft['effectivePreference'] == 'balanced',
      'balanced delegation draft not applied',
    );
    final navigation = _map(snapshot['navigation']);
    if (worktree) {
      _expect(
        navigation?['newThreadWorkspaceMode'] == 'worktree',
        'worktree draft not applied',
      );
    }
    if (!worktree) {
      _expect(
        navigation?['newThreadWorkspaceMode'] == 'local',
        'local draft not applied',
      );
    }
  }

  Future<void> _ensureMenuChoice(String menuKey, String choiceKey) async {
    await _tap(menuKey);
    await driver.waitFor(
      find.byValueKey(choiceKey),
      timeout: const Duration(seconds: 30),
    );
    await _tap(choiceKey);
    await _waitMenuClosed(choiceKey);
  }

  Future<void> _waitMenuClosed(String leafKey) async {
    // MenuItemButton closes the containing menu by default. Observe that real
    // closure before reopening settings; never toggle an uncertain menu state.
    await driver.waitForAbsent(
      find.byValueKey(leafKey),
      timeout: const Duration(seconds: 15),
    );
  }

  Future<Map<String, Object?>> _submitAndWait({
    required String label,
    required String marker,
    required String note,
    required String expectedPhase,
    String? rootId,
  }) async {
    setStage('submit-$label');
    final baseline = await _providerState();
    _assertProviderHealthy(baseline);
    final baselineOrdinal = _latestOrdinal(baseline);
    final before = await _read();
    if (rootId != null) {
      _expect(
        _map(before['navigation'])?['selectedThreadId'] == rootId,
        'selected root mismatch before $label submission',
      );
    }
    final priorTurn = turnId(before);
    final priorRowIds = <String>{
      for (final row in timelineRows(before))
        if (row['id'] is String) row['id'] as String,
    };
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-input');
    await driver.enterText(marker);
    _expect(
      await driver.getText(find.byValueKey('composer-input')) == marker,
      'composer text does not match marker',
    );
    await driver.waitFor(
      find.byValueKey('composer-submit'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-submit');

    final deadline = DateTime.now().add(_stageTimeout);
    String? submittedRoot;
    String? newTurn;
    String? submittedInputId;
    var nextHealthCheck = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      final state = await _read();
      final navigation = _map(state['navigation']);
      final workspace = _map(state['workspace']);
      final selected = navigation?['selectedThreadId'];
      if (selected is String && selected.isNotEmpty) {
        if (rootId != null && selected != rootId) {
          throw StateError(
            '$label selection changed to unexpected root $selected',
          );
        }
        if (submittedRoot != null && selected != submittedRoot) {
          throw StateError(
            '$label selected root changed from $submittedRoot to $selected',
          );
        }
        if (workspace?['threadId'] != selected) {
          if (submittedRoot != null) {
            throw StateError(
              '$label workspace thread no longer matches selected root',
            );
          }
        } else {
          submittedRoot ??= selected;
        }
      }
      if (submittedRoot != null &&
          (navigation?['selectedThreadId'] != submittedRoot ||
              workspace?['threadId'] != submittedRoot)) {
        throw StateError(
          '$label root identity changed from submitted root $submittedRoot',
        );
      }
      if (threadFaulted(state) &&
          (submittedRoot == null || workspace?['threadId'] == submittedRoot)) {
        throw StateError('$label target thread faulted: ${summarize(state)}');
      }

      final now = DateTime.now();
      if (!now.isBefore(nextHealthCheck)) {
        final health = await _providerState();
        _assertProviderHealthy(health);
        nextHealthCheck = DateTime.now().add(const Duration(seconds: 1));
      }

      final currentTurn = turnId(state);
      if (submittedRoot != null &&
          navigation?['selectedThreadId'] == submittedRoot &&
          workspace?['threadId'] == submittedRoot &&
          currentTurn != null &&
          currentTurn.isNotEmpty &&
          currentTurn != priorTurn) {
        if (newTurn != null && currentTurn != newTurn) {
          throw StateError(
            '$label active turn changed from $newTurn to $currentTurn',
          );
        }
        newTurn ??= currentTurn;
      }
      if (newTurn != null && currentTurn != newTurn) {
        throw StateError(
          '$label active turn changed or disappeared from $newTurn',
        );
      }

      final rows = timelineRows(state);
      final markerRows = rows.where(
        (row) =>
            _isUserInputRow(row) &&
            row['text'] == marker &&
            row['id'] is String &&
            !priorRowIds.contains(row['id']),
      );
      if (markerRows.length > 1) {
        throw StateError('$label has multiple new userInput rows for marker');
      }
      if (markerRows.length == 1) {
        final id = markerRows.single['id'] as String;
        if (submittedInputId != null && submittedInputId != id) {
          throw StateError('$label submitted marker row identity changed');
        }
        submittedInputId = id;
      }
      final status = turnStatus(state);
      if (submittedRoot != null &&
          workspace?['threadId'] == submittedRoot &&
          const {'failed', 'cancelled', 'budgetLimited'}.contains(status)) {
        throw StateError(
          '$label turn terminated unsuccessfully: ${summarize(state)}',
        );
      }
      if (newTurn != null &&
          turnId(state) == newTurn &&
          submittedInputId != null) {
        if (navigation?['selectedThreadId'] != submittedRoot ||
            workspace?['threadId'] != submittedRoot) {
          throw StateError(
            '$label root identity changed while waiting for turn completion',
          );
        }
        if (status == 'completed' && isDurableSettled(state)) {
          _expect(
            _lastTurnInputId(state) == submittedInputId,
            '$label completed Turn inputId does not match submitted marker row',
          );
          final provider = await _providerState();
          _assertProviderHealthy(provider);
          final matches = _matchingFinal(
            provider,
            note,
            marker,
            submittedRoot!,
            expectedPhase,
            baselineOrdinal,
          );
          if (matches.length > 1) {
            throw StateError('multiple final provider observations for $label');
          }
          if (matches.length == 1) {
            final accepted = matches.single;
            _expect(
              accepted.rootAgentId == submittedRoot,
              'provider root id differs from selected GUI thread',
            );
            _expect(
              _map(accepted.receipt)?['phase'] == expectedPhase,
              'provider receipt phase mismatch',
            );
            _expect(
              accepted.ordinal > baselineOrdinal,
              'provider ordinal did not advance',
            );
            final evidence = _map(accepted.receipt)?['evidence'];
            _expect(evidence is Map, 'provider receipt evidence missing');
            turns[label] = newTurn;
            stageRows[label] = _captureStageRows(
              rows,
              submittedInputId,
              marker,
              note,
              newTurn,
              priorRowIds,
            );
            providerReceipts[label] = <String, Object?>{
              'ordinal': accepted.ordinal,
              'note': accepted.note,
              'rootAgentId': accepted.rootAgentId,
              'phase': expectedPhase,
              'receipt': accepted.receipt,
            };
            return Map<String, Object?>.from(_map(accepted.receipt)!);
          }
        }
      }
      await Future<void>.delayed(_pollInterval);
    }
    throw StateError(
      '$label timed out: turn=$newTurn status=${turnStatus(latest ?? const {})} providerOrdinal>$baselineOrdinal',
    );
  }

  Future<Map<String, dynamic>> _providerState() async {
    final uri = fixtureOrigin.resolve('/delegation/state');
    final request = await http.getUrl(uri).timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('fixture state HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> ||
        decoded['scenario'] is! String ||
        decoded['observations'] is! List ||
        decoded['failures'] is! List) {
      throw const FormatException('invalid delegation fixture state schema');
    }
    return decoded;
  }

  void _assertProviderHealthy(Map<String, dynamic> state) {
    final failures = state['failures'] as List;
    _expect(failures.isEmpty, 'fixture reports failures: $failures');
    for (final observation in state['observations'] as List) {
      if (observation is Map && observation['accepted'] == false) {
        throw StateError(
          'fixture rejected observation: ${observation['marker']}',
        );
      }
    }
  }

  List<_ProviderObservation> _matchingFinal(
    Map<String, dynamic> state,
    String note,
    String marker,
    String rootId,
    String phase,
    int baselineOrdinal,
  ) {
    final results = <_ProviderObservation>[];
    for (final raw in state['observations'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('provider observation must be an object');
      }
      if (raw['note'] != note) {
        continue;
      }
      final item = _ProviderObservation.parse(raw);
      if (item.marker != marker ||
          item.rootAgentId != rootId ||
          item.phase != phase ||
          item.ordinal <= baselineOrdinal) {
        continue;
      }
      results.add(item);
    }
    return results;
  }

  int _latestOrdinal(Map<String, dynamic> state) {
    var ordinal = 0;
    for (final raw in state['observations'] as List) {
      if (raw is! Map) {
        throw const FormatException('provider observation must be an object');
      }
      final value = raw['ordinal'];
      if (value is! int) {
        throw const FormatException('provider ordinal must be integer');
      }
      if (value > ordinal) ordinal = value;
    }
    return ordinal;
  }

  Future<Map<String, dynamic>> _read() async {
    latest = await driver.readSnapshot().timeout(const Duration(seconds: 20));
    observe(latest!);
    return latest!;
  }

  Future<Map<String, dynamic>> _waitFor(
    bool Function(Map<String, dynamic>) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 90),
    String? expectedThreadId,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var nextProviderCheck = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      final state = await _read();
      if (expectedThreadId != null) {
        _checkExpectedThreadFault(state, expectedThreadId, label);
        if (!DateTime.now().isBefore(nextProviderCheck)) {
          _assertProviderHealthy(await _providerState());
          nextProviderCheck = DateTime.now().add(const Duration(seconds: 1));
        }
      }
      if (predicate(state)) return state;
      await Future<void>.delayed(_pollInterval);
    }
    throw StateError(
      'timed out waiting for $label: ${summarize(latest ?? const {})}',
    );
  }

  void _checkExpectedThreadFault(
    Map<String, dynamic> state,
    String expectedThreadId,
    String label,
  ) {
    final workspace = _map(state['workspace']);
    if (workspace?['threadId'] == expectedThreadId && threadFaulted(state)) {
      throw StateError(
        '$label target thread $expectedThreadId faulted: ${summarize(state)}',
      );
    }
  }

  Future<void> _tap(String key) async {
    await driver.waitFor(
      find.byValueKey(key),
      timeout: const Duration(seconds: 30),
    );
    await driver.rawTap(
      find.byValueKey(key),
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> _capture(String name) async {
    final snapshot = await _read();
    await _writeJson(File('${output.path}/$name.snapshot.json'), snapshot);
    await File('${output.path}/$name.png').writeAsBytes(
      await driver.screenshot().timeout(const Duration(seconds: 20)),
      flush: true,
    );
  }

  void _assertRootIdentity(
    Map<String, dynamic> state,
    String id,
    String mode,
    Object? expectedPath,
  ) {
    final sidebar = _sidebar(state);
    _expect(
      sidebar['workspaceModes']?[id] == mode,
      '$id workspace mode changed',
    );
    _expect(
      expectedPath is String && sidebar['workspacePaths']?[id] == expectedPath,
      '$id workspace path changed',
    );
  }

  Map<String, dynamic> _sidebar(Map<String, dynamic> state) =>
      _map(state['sidebarDirectory']) ??
      (throw const FormatException('sidebarDirectory missing'));

  Map<String, Object?> _captureStageRows(
    List<Map<String, dynamic>> rows,
    String inputId,
    String marker,
    String expectedFinalText,
    String turn,
    Set<String> priorIds,
  ) {
    final inputIndex = rows.indexWhere(
      (row) =>
          row['id'] == inputId &&
          _isUserInputRow(row) &&
          row['text'] == marker &&
          !priorIds.contains(row['id']),
    );
    _expect(
      inputIndex >= 0,
      'new exact-marker userInput row missing at settle',
    );
    final input = rows[inputIndex];
    final answers = rows
        .skip(inputIndex + 1)
        .where(
          (row) =>
              _isFinalAnswerRow(row) &&
              row['id'] is String &&
              !priorIds.contains(row['id']),
        )
        .toList();
    _expect(
      answers.length == 1,
      'expected exactly one new finalAnswer after exact marker, found ${answers.length}',
    );
    final finalAnswer = answers.single;
    _expect(
      finalAnswer['text'] == expectedFinalText,
      'new finalAnswer text did not equal "$expectedFinalText"',
    );
    return <String, Object?>{
      'turnId': turn,
      'userInput': <String, Object?>{'id': input['id'], 'text': input['text']},
      'finalAnswer': <String, Object?>{
        'id': finalAnswer['id'],
        'text': finalAnswer['text'],
      },
    };
  }

  Future<void> _collectAndVerifyHistory(
    Map<String, Map<String, dynamic>> expected,
    String rootLabel, {
    required String expectedThreadId,
  }) async {
    setStage('load-$rootLabel-history');
    final deadline = DateTime.now().add(_stageTimeout);
    final initialStability = TimelineViewportStability();
    await _waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        return timeline?.threadId == expectedThreadId &&
            initialStability.accept(snapshot);
      },
      '$rootLabel initial timeline viewport ready and stable',
      timeout: _stageTimeout,
      expectedThreadId: expectedThreadId,
    );
    var nextProviderCheck = DateTime.now();
    while (true) {
      final current = latest ?? await _read();
      _checkExpectedThreadFault(current, expectedThreadId, '$rootLabel paging');
      if (TimelineObservation.optional(current)?.threadId != expectedThreadId) {
        throw StateError(
          '$rootLabel paging observed a different timeline thread',
        );
      }
      if (!DateTime.now().isBefore(nextProviderCheck)) {
        _assertProviderHealthy(await _providerState());
        nextProviderCheck = DateTime.now().add(const Duration(seconds: 1));
      }
      final rows = timelineRows(current);
      if (_historyRowsMatch(rows, expected)) return;
      final beforeTimeline = TimelineObservation.optional(current);
      if (beforeTimeline == null) {
        throw StateError(
          '$rootLabel history has no typed timeline observation',
        );
      }
      if (!beforeTimeline.hasOlder) {
        throw StateError(
          '$rootLabel history reached hasOlder=false before saved rows were found',
        );
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          '$rootLabel history paging exceeded its bounded deadline',
        );
      }
      await driver
          .requestData('load-older')
          .timeout(const Duration(seconds: 60));
      final pageDeadline = DateTime.now().add(const Duration(seconds: 60));
      Map<String, dynamic>? advanced;
      while (DateTime.now().isBefore(pageDeadline) &&
          DateTime.now().isBefore(deadline)) {
        final candidate = await _read();
        _checkExpectedThreadFault(
          candidate,
          expectedThreadId,
          '$rootLabel paging',
        );
        if (!DateTime.now().isBefore(nextProviderCheck)) {
          _assertProviderHealthy(await _providerState());
          nextProviderCheck = DateTime.now().add(const Duration(seconds: 1));
        }
        final timeline = TimelineObservation.optional(candidate);
        if (timeline != null && timeline.threadId != expectedThreadId) {
          throw StateError(
            '$rootLabel pagination switched timeline to ${timeline.threadId}',
          );
        }
        if (timeline != null &&
            !timeline.loadingOlder &&
            timeline.itemCount > beforeTimeline.itemCount &&
            timelineViewportSettled(candidate)) {
          advanced = candidate;
          break;
        }
        await Future<void>.delayed(_pollInterval);
      }
      if (advanced == null) {
        throw StateError(
          '$rootLabel history page did not advance within 60 seconds',
        );
      }
    }
  }

  bool _historyRowsMatch(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, dynamic>> expected,
  ) {
    for (final stage in expected.values) {
      final input = _map(stage['userInput']);
      final answer = _map(stage['finalAnswer']);
      if (input == null || answer == null) return false;
      final hasInput = rows.any(
        (row) =>
            _isUserInputRow(row) &&
            row['id'] == input['id'] &&
            row['text'] == input['text'],
      );
      final hasAnswer = rows.any(
        (row) =>
            _isFinalAnswerRow(row) &&
            row['id'] == answer['id'] &&
            row['text'] == answer['text'],
      );
      if (!hasInput || !hasAnswer) return false;
    }
    return true;
  }
}

final class _ProviderObservation {
  const _ProviderObservation({
    required this.ordinal,
    required this.marker,
    required this.note,
    required this.rootAgentId,
    required this.phase,
    required this.receipt,
  });

  final int ordinal;
  final String marker;
  final String note;
  final String rootAgentId;
  final String phase;
  final Map<String, dynamic>? receipt;

  static _ProviderObservation parse(Map<String, dynamic> value) {
    if (value['accepted'] != true) {
      throw const FormatException(
        'final provider observation was not accepted',
      );
    }
    final receipt = value['receipt'];
    final receiptMap = receipt is Map<String, dynamic> ? receipt : null;
    final evidence = receiptMap?['evidence'];
    if (receiptMap == null || evidence is! Map) {
      throw const FormatException(
        'final observation receipt/evidence is missing',
      );
    }
    return _ProviderObservation(
      ordinal: _requiredInt(value['ordinal'], 'observation.ordinal'),
      marker: _requiredString(value['marker'], 'observation.marker'),
      note: _requiredString(value['note'], 'observation.note'),
      rootAgentId: _requiredString(
        receiptMap['rootAgentId'],
        'receipt.rootAgentId',
      ),
      phase: _requiredString(receiptMap['phase'], 'receipt.phase'),
      receipt: receiptMap,
    );
  }
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

Map<String, dynamic> _requiredStage(
  Map<String, dynamic> stages,
  String label,
) =>
    _map(stages[label]) ??
    (throw FormatException('handoff stageRows.$label is missing'));

String _stageTurn(Map<String, dynamic> stages, String label) => _requiredString(
  _requiredStage(stages, label)['turnId'],
  'stageRows.$label.turnId',
);

bool _isUserInputRow(Map<String, dynamic> row) =>
    row['kind'] == 'userMessage' && row['channel'] == 'user';

bool _isFinalAnswerRow(Map<String, dynamic> row) =>
    row['kind'] == 'agentMessage' && row['channel'] == 'finalAnswer';

String? _lastTurnInputId(Map<String, dynamic> snapshot) {
  final workspace = _map(snapshot['workspace']);
  final lastTurn = _map(workspace?['lastTurn']);
  return lastTurn?['inputId'] as String?;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a nonempty string');
  }
  return value;
}

int _requiredInt(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _writeJson(File file, Object? value) => file.writeAsString(
  const JsonEncoder.withIndent('  ').convert(value),
  flush: true,
);
