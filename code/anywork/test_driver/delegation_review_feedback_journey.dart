// Explicit native manual-gui journey; never a Flutter test or a verdict engine.
// All product mutations are real UI actions. Fixture reads coordinate the
// controlled external supplier and never modify Client, Runtime or persistence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'package:anywork/src/shared/studio_driver_key_values.dart';

import 'cold_start_navigation.dart';
import 'driver_read_commands.dart';
import 'flutter_driver_session.dart';
import 'realtime_journey.dart' show workspaceOf;
import 'timeline_observation.dart';
import 'tool_probe.dart';

const _bodySentinel = 'RF_FULLBODY_ONLY_c4286037';
const _commentarySentinel = 'RF_COMMENTARY_ONLY_a93f8712';

Future<void> main(List<String> args) async {
  if (args.length != 6 || !['first', 'reopen'].contains(args[4])) {
    throw ArgumentError(
      'usage: delegation_review_feedback_journey.dart '
      'VM_URL PROJECT_DIR OUTPUT_DIR ENVIRONMENT first|reopen FIXTURE_ORIGIN',
    );
  }
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  final journey = _Journey(driver, args);
  Object? failure;
  try {
    await journey.run();
  } catch (error, stack) {
    failure = error;
    await journey.failureEvidence(error, stack);
    rethrow;
  } finally {
    try {
      // Do not request shutdown: manual_capture owns the subsequent capture and
      // native shutdown. Only release this script's Driver connection.
      await driver.close().timeout(const Duration(seconds: 10));
    } catch (error) {
      journey.evidence['driverCloseError'] = '$error';
      if (failure == null) {
        failure = error;
        rethrow;
      }
    } finally {
      await journey.writeSummary(failure);
    }
  }
}

class _Journey {
  _Journey(this.driver, List<String> args)
    : project = args[1],
      output = Directory(args[2]),
      environment = Directory(args[3]),
      phase = args[4],
      origin = Uri.parse(args[5]);

  final FlutterDriverSession driver;
  final String project;
  final Directory output;
  final Directory environment;
  final String phase;
  final Uri origin;
  final Map<String, Object?> evidence = {};
  final List<Map<String, Object?>> sidebarVisibilityActions = [];
  String stage = 'connected';

  File get baseline =>
      File('${environment.path}/review-feedback-baseline.json');

  File get firstEvidence =>
      File('${environment.path}/review-feedback-first-evidence.json');

  Future<void> tap(String key) async {
    await driver.waitFor(
      find.byValueKey(key),
      timeout: const Duration(seconds: 30),
    );
    await driver.rawTap(find.byValueKey(key));
  }

  Future<Map<String, dynamic>> waitFor(
    FutureOr<bool> Function(Map<String, dynamic>) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 300),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await driver.readSnapshot();
      if (await predicate(last)) return last;
      // Polling cadence is not a completion proof; predicates use real facts.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await saveJson('timeout-$label', last);
    throw StateError('bounded wait timed out: $label');
  }

  bool settled(Map<String, dynamic> snapshot) {
    final workspace = workspaceOf(snapshot);
    final persistence = snapshot['persistence'];
    return workspace != null &&
        workspace['isBusy'] == false &&
        workspace['syncState'] == 'ready' &&
        (workspace['composer'] as Map?)?['submissionPending'] == false &&
        persistence is Map &&
        persistence['kind'] == 'ready' &&
        persistence['pendingCommits'] == 0;
  }

  Future<Map<String, dynamic>> fixture() async {
    if (!['localhost', '127.0.0.1', '::1'].contains(origin.host)) {
      throw StateError('fixture must be the owned loopback origin');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(origin.resolve('/delegation/state'));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) {
        throw StateError('fixture state returned ${response.statusCode}');
      }
      final raw = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 5)),
      );
      if (raw is! Map ||
          raw['scenario'] != 'review-feedback' ||
          raw['failures'] is! List) {
        throw StateError('invalid controlled review fixture state');
      }
      if ((raw['failures'] as List).isNotEmpty) {
        throw StateError('fixture rejected a real request: ${raw['failures']}');
      }
      return raw.cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic>? checkpoint(Map<String, dynamic> state, String note) {
    final rows = state['observations'];
    if (rows is! List) throw StateError('fixture observations missing');
    final found = rows
        .whereType<Map>()
        .where((row) => row['note'] == note && row['accepted'] == true)
        .toList();
    if (found.length > 1) throw StateError('duplicate checkpoint $note');
    return found.isEmpty ? null : found.single.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> submit(String marker, String note) async {
    stage = marker;
    final before = await driver.readSnapshot();
    final previous =
        TimelineObservation.optional(before)?.itemIds.toSet() ?? <String>{};
    await tap('composer-input');
    await driver.enterText(marker);
    await tap('composer-submit');
    final accepted = await waitFor((snapshot) {
      return TimelineObservation.optional(snapshot)?.items.any(
            (item) =>
                item.channel == 'user' &&
                item.text == marker &&
                !previous.contains(item.id),
          ) ??
          false;
    }, 'input-accepted');
    final input = TimelineObservation.parse(accepted).items
        .singleWhere(
          (item) =>
              item.channel == 'user' &&
              item.text == marker &&
              !previous.contains(item.id),
        )
        .id;
    final completed = await waitFor((snapshot) async {
      final turn = workspaceOf(snapshot)?['lastTurn'];
      if (turn is Map &&
          turn['inputId'] == input &&
          turn['status'] == 'failed') {
        throw StateError('root Turn failed for $marker: $turn');
      }
      if (!settled(snapshot) ||
          turn is! Map ||
          turn['inputId'] != input ||
          turn['status'] != 'completed') {
        return false;
      }
      return checkpoint(await fixture(), note) != null;
    }, note);
    await capture(note, completed);
    return completed;
  }

  Future<void> configureDraft() async {
    // The Mode selector also exists on a live Thread. Wait for the actual
    // project draft before using it, including after a project-scoped new session.
    await waitFor((snapshot) {
      final navigation = snapshot['navigation'];
      final selectedProject = snapshot['project'];
      return navigation is Map &&
          selectedProject is Map &&
          selectedProject['path'] == project &&
          selectedProject['id'] is String &&
          navigation['selectedProjectId'] == selectedProject['id'] &&
          navigation['selectedThreadId'] == null &&
          navigation['isStartPage'] == true;
    }, 'project-draft-ready');
    await tap(StudioDriverKeyValues.sessionMode);
    await tap(StudioDriverKeyValues.sessionModeOption('mode.simple'));
    await tap(StudioDriverKeyValues.sessionSettings);
    await tap(StudioDriverKeyValues.draftDelegationMode);
    await tap('delegation-draft-mode-automatic');
    await tap(StudioDriverKeyValues.sessionSettings);
    await tap(StudioDriverKeyValues.draftDelegationPreference);
    await tap('delegation-draft-preference-balanced');
    await waitFor((snapshot) {
      final delegation = snapshot['delegation'];
      final navigation = snapshot['navigation'] as Map?;
      final projectId = navigation?['selectedProjectId'];
      if (navigation?['newThreadMode'] != 'mode.simple') return false;
      if (delegation is! Map || delegation['drafts'] is! List) return false;
      return (delegation['drafts'] as List).whereType<Map>().any(
        (draft) =>
            draft['projectId'] == projectId &&
            draft['effectiveMode'] == 'automatic' &&
            draft['effectivePreference'] == 'balanced',
      );
    }, 'automatic-draft');
  }

  Future<void> openProject() async {
    stage = 'opening-project';
    // Follow the same local-project wizard as realtime_journey/stress_start.
    // The path dialog is created only after these real UI actions.
    await tap('sidebar-open-project');
    await tap('add-project-local');
    await tap('add-project-continue-ready');
    await tap('project-path-input');
    await driver.enterText(project);
    await tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
    await waitFor(
      (snapshot) => (snapshot['project'] as Map?)?['path'] == project,
      'project-open',
    );
  }

  Future<void> run() async {
    if (phase == 'reopen') {
      final saved = jsonDecode(await firstEvidence.readAsString());
      if (saved is! Map ||
          saved['exceptions'] is! Map ||
          saved['childRequests'] is! Map) {
        throw StateError(
          'persisted first report/exception evidence is missing',
        );
      }
      final cases = saved['exceptions'] as Map;
      for (final caseName in ['busy', 'changed', 'closed']) {
        final original = cases[caseName];
        if (original is! Map ||
            original['navigation'] is! Map ||
            original['first'] is! Map) {
          throw StateError('original $caseName root evidence is missing');
        }
        final identity = ColdStartIdentity.fromBaseline(
          (original['navigation'] as Map).cast<String, Object?>(),
        );
        await restoreOriginal(identity, 'reopen-$caseName');
        await submit(
          '[[delegation:review-feedback:reopen-$caseName]]',
          'rf-reopen-$caseName-checked',
        );
        final checked = checkpoint(
          await fixture(),
          'rf-reopen-$caseName-checked',
        )?['receipt'];
        final first = original['first'] as Map;
        if (checked is! Map ||
            jsonEncode(checked['first']) != jsonEncode(first) ||
            checked['submissionAfter'] != first['submission'] ||
            jsonEncode(checked['exceptionAfter']) !=
                jsonEncode(first['exception']) ||
            jsonEncode(checked['latestAfter']) != jsonEncode(first['latest'])) {
          throw StateError(
            'public reopened $caseName evidence differs from persisted first bytes/identity',
          );
        }
        requireCounts(
          saved['childRequests'] as Map,
          childCounts(await fixture()),
        );
        evidence['reopen-$caseName'] = checked;
      }
      final raw = jsonDecode(await baseline.readAsString());
      if (raw is! Map) throw StateError('first identity baseline missing');
      final identity = ColdStartIdentity.fromBaseline(
        raw.cast<String, Object?>(),
      );
      await restoreColdStartTarget(
        ColdStartDriverSurface(
          readSnapshot: driver.readSnapshot,
          tap: (finder, timeout) =>
              revealNavigationTarget(finder, timeout, identity),
        ),
        identity: identity,
        phase: phase,
        onStage: (value) async {
          stage = value;
        },
      );
      await submit(
        '[[delegation:review-feedback:reopen]]',
        'rf-reopen-complete',
      );
      final state = await fixture();
      final aggregate = checkpoint(state, 'rf-reopen-complete')?['receipt'];
      if (aggregate is! Map ||
          jsonEncode(aggregate['first']) != jsonEncode(saved['normal']) ||
          aggregate['exceptionReopens'] is! List ||
          (aggregate['exceptionReopens'] as List).length != 3) {
        throw StateError(
          'aggregate reopen lacks original normal and all three public exception queries',
        );
      }
      requireCounts(saved['childRequests'] as Map, childCounts(state));
      evidence['identity'] = identity.toJson();
      evidence['providerState'] = state;
      stage = 'complete';
      return;
    }
    await openProject();
    await configureDraft();
    final compact = await submit(
      '[[delegation:review-feedback:normal]]',
      'rf-normal-compact-complete',
    );
    final opened = readOpenedTimelineIdentity(compact);
    if (!opened.consistent) {
      throw StateError('normal root has inconsistent persisted identity');
    }
    await baseline.writeAsString(jsonEncode(opened.toJson()));
    final compactText = jsonEncode(compact);
    if (compactText.contains(_bodySentinel) ||
        compactText.contains(_commentarySentinel)) {
      throw StateError(
        'default parent GUI projection includes full findings/commentary',
      );
    }
    evidence['parentCompactUiNoSentinel'] = true;
    // The stronger zero-leak oracle is fixture::require_no_leak over each actual
    // parent provider input, not this screenshot/snapshot.
    final normalState = await fixture();
    final normal = checkpoint(normalState, 'rf-normal-compact-complete');
    final receipt = normal?['receipt'];
    final first = receipt is Map ? receipt['first'] : null;
    if (first is! Map ||
        first['reviewer'] is! Map ||
        first['executor'] is! Map) {
      throw StateError('normal real identities are missing');
    }
    final reviewerId = _requiredString(first['reviewer'] as Map, 'childId');
    final executorId = _requiredString(first['executor'] as Map, 'childId');
    final approval = first['approval'];
    if (approval is! Map) throw StateError('fresh approval identity missing');
    final approvalId = _requiredString(approval, 'childId');
    final root = opened.threadId!;
    evidence['normalReceipt'] = receipt;
    final exceptionRoots = <String, Object?>{};
    await captureAgents([executorId, reviewerId, approvalId]);
    // Explicitly authorize a public full-history read only after compact evidence.
    await submit(
      '[[delegation:review-feedback:normal-full]]',
      'rf-full-history-complete',
    );
    await selectAgent(reviewerId);
    await reviewerHistory();
    await selectAgent(root);
    for (final caseName in [
      'approved',
      'inconclusive',
      'natural',
      'omitted',
      'illegal',
      'busy',
      'changed',
      'closed',
    ]) {
      await tap('project-new-session-${opened.projectId}');
      await configureDraft();
      final snapshot = await submit(
        '[[delegation:review-feedback:$caseName]]',
        'rf-$caseName-complete',
      );
      if (['busy', 'changed', 'closed'].contains(caseName)) {
        final identity = readOpenedTimelineIdentity(snapshot);
        final caseReceipt = checkpoint(
          await fixture(),
          'rf-$caseName-complete',
        )?['receipt'];
        final caseFirst = caseReceipt is Map ? caseReceipt['first'] : null;
        if (!identity.consistent ||
            identity.projectId != opened.projectId ||
            caseFirst is! Map ||
            caseFirst['root'] != identity.threadId ||
            caseFirst['case'] != caseName ||
            caseFirst['submission'] is! String ||
            caseFirst['exception'] is! Map ||
            (caseFirst['exception'] as Map)['raw'] is! String ||
            (caseFirst['exception'] as Map)['exceptionId'] is! String) {
          throw StateError(
            'first $caseName lacks actual navigation and model-visible report/exception bytes',
          );
        }
        exceptionRoots[caseName] = {
          'navigation': identity.toJson(),
          'first': caseFirst,
        };
      }
    }
    final state = await fixture();
    final persisted = {
      'normal': first,
      'exceptions': exceptionRoots,
      'childRequests': childCounts(state),
    };
    // This is required evidence, not a best-effort cache. Write failures propagate.
    await firstEvidence.writeAsString(
      '${jsonEncode(persisted)}\n',
      flush: true,
    );
    await saveJson('review-feedback-first-evidence', persisted);
    // Leave the real original root visible for the harness-owned manual capture.
    final original = ColdStartIdentity(
      projectId: opened.projectId!,
      threadId: root,
    );
    await restoreColdStartTarget(
      ColdStartDriverSurface(
        readSnapshot: driver.readSnapshot,
        tap: (finder, timeout) =>
            revealNavigationTarget(finder, timeout, original),
      ),
      identity: original,
      phase: 'first-final',
      onStage: (value) async {
        stage = value;
      },
    );
    evidence['providerState'] = await fixture();
    stage = 'complete';
  }

  Future<void> restoreOriginal(ColdStartIdentity identity, String label) =>
      restoreColdStartTarget(
        ColdStartDriverSurface(
          readSnapshot: driver.readSnapshot,
          tap: (finder, timeout) =>
              revealNavigationTarget(finder, timeout, identity),
        ),
        identity: identity,
        phase: label,
        onStage: (value) async {
          stage = value;
        },
      );

  Map<String, int> childCounts(Map<String, dynamic> state) {
    final rows = state['observations'];
    if (rows is! List) throw StateError('provider observations absent');
    final counts = <String, int>{};
    for (final row in rows) {
      if (row is! Map || row['marker'] is! String) {
        throw StateError('invalid actual provider request observation');
      }
      final marker = row['marker'] as String;
      if (marker.startsWith('[[delegation:child:')) {
        counts[marker] = (counts[marker] ?? 0) + 1;
      }
    }
    return counts;
  }

  void requireCounts(Map first, Map<String, int> after) {
    if (first.length != after.length ||
        first.entries.any(
          (entry) => entry.value is! int || after[entry.key] != entry.value,
        )) {
      throw StateError(
        'reopen added a child provider request; root query requests are separate',
      );
    }
  }

  Future<void> revealNavigationTarget(
    SerializableFinder target,
    Duration timeout,
    ColdStartIdentity identity,
  ) async {
    final key = target is ByValueKey ? target.keyValue : null;
    final projectRow = 'project-row-${identity.projectId}';
    final threadRow = 'thread-row-${identity.threadId}';
    if (key != projectRow && key != threadRow) {
      // The explicit open-selected-Thread entry is outside the sidebar tree.
      await driver.rawTap(target, timeout: timeout);
      return;
    }
    final elapsed = Stopwatch()..start();
    Duration remaining() {
      final left = timeout - elapsed.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException(
          'sidebar visibility budget exhausted for $key',
          timeout,
        );
      }
      return left;
    }

    Future<bool> mounted(SerializableFinder finder) async {
      final result = await driver
          .sendCommand(ToolProbe(finder, 'observe'))
          .timeout(remaining());
      final samples = result['samples'];
      if (samples is! List || samples.isEmpty) {
        throw StateError('sidebar geometry observation has no samples');
      }
      final sample = samples.last;
      if (sample is! Map) {
        throw StateError('sidebar geometry sample is not a map');
      }
      if (sample['mounted'] == false) return false;
      for (final field in ['top', 'left', 'width', 'height']) {
        final value = sample[field];
        if (value is! num || !value.isFinite) {
          throw StateError('sidebar geometry has no finite $field');
        }
      }
      return true;
    }

    final tree = find.byValueKey('sidebar-project-tree');
    Future<void> reveal(SerializableFinder finder) => driver.scrollUntilVisible(
      tree,
      finder,
      dyScroll: -300,
      timeout: remaining(),
    );

    while (true) {
      if (await mounted(target)) {
        // Loaded rows are eagerly mounted in the sidebar Column, even when
        // clipped. The existing Driver helper ends with stock scrollIntoView.
        await reveal(target);
        await driver.rawTap(target, timeout: remaining());
        if (sidebarVisibilityActions.length < 32) {
          sidebarVisibilityActions.add({
            'phase': phase,
            'action': 'revealAndSelect',
            'key': key,
          });
        }
        return;
      }
      if (key == threadRow) {
        // The real sidebar query starts with eight roots; this scene has nine.
        // Read only mounted UI controls, never infer the sidebar's private page
        // from the Client directory or choose a same-title sibling.
        for (final label in ['Show earlier sessions', '查看更早会话']) {
          final earlier = find.text(label);
          if (await mounted(earlier)) {
            await reveal(earlier);
            await driver.rawTap(earlier, timeout: remaining());
            if (sidebarVisibilityActions.length < 32) {
              sidebarVisibilityActions.add({
                'phase': phase,
                'action': 'loadEarlier',
                'target': key,
              });
            }
            break;
          }
        }
      }
      // Query/layout polling cadence only. Success still requires the actual
      // row, a real UI selection, and the unchanged helper's identity/layout checks.
      final left = remaining();
      await Future<void>.delayed(
        left < const Duration(milliseconds: 100)
            ? left
            : const Duration(milliseconds: 100),
      );
    }
  }

  Future<void> captureAgents(List<String> ids) async {
    await tap('agent-switcher');
    for (final id in ids) {
      await driver.waitFor(
        find.byValueKey('agent-thread-$id'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitFor(
        find.byValueKey(StudioDriverKeyValues.agentModel(id)),
        timeout: const Duration(seconds: 30),
      );
    }
    await capture('normal-child-list', await driver.readSnapshot());
    await tap('agent-switcher');
    final state = await driver.readSnapshot();
    final delegation = state['delegation'];
    final agents = delegation is Map ? delegation['agents'] : null;
    if (agents is! List) {
      throw StateError('canonical child directory is unavailable');
    }
    for (final id in ids) {
      final rows = agents
          .whereType<Map>()
          .where((row) => row['threadId'] == id)
          .toList();
      if (rows.length != 1 || rows.single['frozenModel'] is! Map) {
        throw StateError('agent $id lacks one canonical frozen route');
      }
    }
    evidence['childList'] = agents;
  }

  Future<void> selectAgent(String id) async {
    await tap('agent-switcher');
    await tap('agent-thread-$id');
    await waitFor(
      (snapshot) =>
          workspaceOf(snapshot)?['threadId'] == id && settled(snapshot),
      'selected-agent',
    );
  }

  Future<void> reviewerHistory() async {
    final loaded = await waitFor((snapshot) {
      final timeline = TimelineObservation.parse(snapshot);
      return timeline.ready &&
          timeline.items.any(
            (item) =>
                item.isFinalAnswer &&
                item.text.startsWith('# Controlled findings: normal'),
          );
    }, 'reviewer-history');
    final body = TimelineObservation.parse(loaded).items.singleWhere(
      (item) =>
          item.isFinalAnswer &&
          item.text.startsWith('# Controlled findings: normal'),
    );
    if (body.detail('text') == null || !body.textTruncated) {
      throw StateError(
        'normal findings did not expose the real long-text detail entry',
      );
    }
    final key = StudioDriverKeyValues.timelineDetailOpen(body.id, 'text');
    await driver.scrollUntilVisible(
      find.byValueKey(StudioDriverKeyValues.timelineScrollable),
      find.byValueKey(key),
      dyScroll: -600,
      timeout: const Duration(seconds: 60),
    );
    await tap(key);
    await driver.waitFor(
      find.byValueKey(StudioDriverKeyValues.timelineDetailDialog),
    );
    final expected =
        '# Controlled findings: normal\n$_bodySentinel\n'
        '${List.filled(400, 'A synthetic finding whose full body must reach only the bound executor and reviewer history.\n').join()}'
        '\nEnd of complete findings: normal.\n';
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    DetailViewerRead? detail;
    while (DateTime.now().isBefore(deadline)) {
      detail = await DetailViewerRead.read(driver.requestData);
      if (detail.open && detail.characters == expected.length) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (detail?.characters != expected.length) {
      throw StateError('full detail did not load');
    }
    await tap(StudioDriverKeyValues.timelineDetailCopy);
    final copied = await ClipboardRead.read(driver.requestData, full: true);
    if (copied.text != expected) {
      throw StateError('real UI full report differs from exact reviewer body');
    }
    evidence['reviewerHistoryDetail'] = {
      'itemId': body.id,
      'characters': detail!.characters,
      'exactCopiedBody': true,
    };
    await capture('reviewer-full-history-detail', await driver.readSnapshot());
    await tap(StudioDriverKeyValues.timelineDetailClose);
  }

  Future<void> saveJson(String label, Object? value) => File(
    '${output.path}/$label.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');

  Future<void> capture(String label, Map<String, dynamic> snapshot) async {
    await saveJson(label, snapshot);
    await File('${output.path}/$label.png')
        .writeAsBytes(await driver.screenshot());
  }

  Future<void> failureEvidence(Object error, StackTrace stack) async {
    evidence['error'] = '$error';
    evidence['stack'] = '$stack';
    try {
      await capture('failure', await driver.readSnapshot());
    } catch (captureError) {
      evidence['captureError'] = '$captureError';
    }
  }

  Future<void> writeSummary(Object? failure) =>
      saveJson('review-feedback-driver', {
        'scenario': 'delegation-review-feedback',
        'phase': phase,
        'humanVerdict': 'pending',
        'scriptCompleted': failure == null && stage == 'complete',
        'stage': stage,
        'evidence': evidence,
        'sidebarVisibilityActions': sidebarVisibilityActions,
        'scope': 'Linux controlled supplier mechanism, not real Task/model review quality',
        'unproved': [
          'complete inbox consumption ledger',
          'observer crash handoff',
          'all-crash exactly-once',
        ],
      });
}

String _requiredString(Map value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw StateError('missing actual $key identity');
  }
  return result;
}
