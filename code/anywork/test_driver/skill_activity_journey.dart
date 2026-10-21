// Manual native-GUI skill activity / compaction journey, not a Flutter test gate.
//
// Phase `first` loads real synthetic skills next to ordinary tools, forces one
// failing and one succeeding manual context compaction through the real status
// bar entry, and reloads one skill afterwards. Phase `reopen` reopens the same
// isolated home, proves the persisted history and activation, requires an
// automatic compaction to commit and clear the restored activation, and finally
// cancels the last Turn while its post-load compaction is really streaming.
//
// Every wait is bound to a canonical fact: a committed Timeline item, the typed
// runtime activation list, a real widget that exists, or the fixture's consumed
// script cursor. Screenshots are evidence for the human review that stays
// pending; they never decide the verdict.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'pointer_hover.dart';
import 'pointer_scroll.dart';
import 'realtime_journey.dart'
    show isBusy, isDurableSettled, turnFailed, turnId, turnStatus, workspaceOf;
import 'sidebar_navigation.dart';
import 'timeline_observation.dart';
import 'window_control.dart';

const _phaseFirst = 'first';
const _phaseReopen = 'reopen';

const _wideWidth = 1440;
const _wideHeight = 1000;
const _narrowWidth = 640;
const _narrowHeight = 600;

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    stderr.writeln(
      'usage: skill_activity_journey.dart PHASE VM_URL PROJECT OUTPUT COORD '
      'FIXTURE_STATUS_FILE',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args[3]);
  final coord = Directory(args[4]);
  final FlutterDriverSession driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  } catch (error, stackTrace) {
    await _recordConnectFailure(output, coord, args[0], error);
    Error.throwWithStackTrace(error, stackTrace);
  }
  final journey = SkillActivityJourney(
    driver: driver,
    phase: args[0],
    project: args[2],
    output: output,
    coord: coord,
    fixtureStatusPath: args[5],
  );
  Object? failure;
  StackTrace? failureStack;
  try {
    await journey.run();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    await journey.captureFailure();
  }
  Object? shutdownFailure;
  try {
    await journey.shutdown();
  } catch (error) {
    shutdownFailure = error;
    journey.shutdownError = '$error';
  }
  if (failure == null) {
    if (shutdownFailure != null) {
      journey.stage = 'shutdown_failed';
    } else if (journey.failed) {
      journey.stage = 'checks_failed';
    } else {
      journey.stage = 'complete';
    }
  }
  await journey.writeSummary(failure: failure);
  await journey.mark(journey.stage);
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  if (shutdownFailure != null) {
    throw StateError('native GUI shutdown failed: $shutdownFailure');
  }
  if (journey.failed) {
    throw StateError('skill-activity journey checks failed');
  }
}

Future<void> _recordConnectFailure(
  Directory output,
  Directory coord,
  String phase,
  Object error,
) async {
  try {
    await File('${coord.path}/skill-activity-stage')
        .writeAsString('connect_failed');
    final summary = <String, Object?>{
      'phase': phase,
      'status': 'failed',
      'stage': 'connect_failed',
      'error': '$error',
      'humanVerdict': 'pending',
    };
    await File(
      '${output.path}/skill-activity-$phase-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  } catch (_) {
    // Preserve the original connect failure.
  }
}

class SkillActivityJourney {
  SkillActivityJourney({
    required this.driver,
    required this.phase,
    required this.project,
    required this.output,
    required this.coord,
    required this.fixtureStatusPath,
  });

  final FlutterDriverSession driver;
  final String phase;
  final String project;
  final Directory output;
  final Directory coord;

  /// The fixture's live script counters; the compaction barrier reads the
  /// consumed cursor instead of guessing a time window.
  final String fixtureStatusPath;

  final Map<String, Object?> checks = <String, Object?>{};
  final Map<String, Object?> observations = <String, Object?>{};
  final List<Map<String, Object?>> captures = <Map<String, Object?>>[];
  final List<String> pendingEvidence = <String>[];
  String stage = 'created';
  String? shutdownError;
  String? _firstTurnSummary;
  int? _guiPid;

  File get stageFile => File('${coord.path}/skill-activity-stage');
  File get observedFile => File('${coord.path}/skill-activity-observed.json');
  File get threadFile => File('${coord.path}/skill-activity-thread');

  bool get failed =>
      checks.values.any((value) => value != true) || shutdownError != null;

  Future<void> run() async {
    await mark('connected');
    final pid = jsonDecode(await driver.requestData('pid'));
    if (pid is! Map || pid['pid'] is! int) {
      throw StateError('native GUI did not publish its process identity');
    }
    _guiPid = pid['pid'] as int;
    final wide = resizeOwnedWindow(
      guiPid: _guiPid!,
      width: _wideWidth,
      height: _wideHeight,
    );
    if (!wide.resized) {
      throw StateError(
        'native window could not be sized for layout evidence: ${wide.reason}',
      );
    }
    await mark('window-sized');
    if (phase == _phaseFirst) {
      await first();
    } else if (phase == _phaseReopen) {
      await reopen();
    } else {
      throw ArgumentError('unknown phase $phase');
    }
  }

  Future<void> first() async {
    await _openProject();
    await _requireSkillsDiscovered();
    await capture('project-opened');
    await _firstTurn();
    await _mixedTurn();
    await _manualCompactionFailure();
    await _manualCompactionSuccess();
    await _reloadTurn();
    await _layoutEvidence();
    final settled = await waitFor(
      (snapshot) => isDurableSettled(snapshot),
      'durable_settled',
      timeout: const Duration(seconds: 180),
    );
    // Record the whole committed history, not only the newest tail window, so
    // the reopened lifecycle compares like with like.
    final timeline = await _loadCompleteHistory();
    observations['firstPhaseHistory'] = <String, Object?>{
      'itemCount': timeline.itemCount,
      'skillNames': [for (final item in timeline.ofKind('skill')) item.text],
      'skillViewCalls': [for (final item in _skillViewCalls(timeline)) item.id],
      'contextCompactions': timeline.ofKind('contextCompaction').length,
    };
    final threadId = workspaceOf(settled)!['threadId'] as String;
    await File(threadFile.path).writeAsString(threadId);
    // The reopened lifecycle compares against this exact history, so the
    // expectations are recorded before the first GUI shuts down.
    await writeObserved(timeline, threadId: threadId);
    await capture('first-complete');
  }

  Future<void> reopen() async {
    if (!threadFile.existsSync()) {
      throw StateError(
        'the first lifecycle did not record its Thread identity',
      );
    }
    final threadId = await threadFile.readAsString();
    await revealSidebarThread(driver, threadId);
    await tap('thread-row-$threadId');
    await clearSidebarSearch(driver);
    final restored = await waitFor(
      (snapshot) =>
          workspaceOf(snapshot)?['threadId'] == threadId &&
          isDurableSettled(snapshot) &&
          TimelineObservation.optional(snapshot) != null,
      'restored_thread',
      timeout: const Duration(seconds: 120),
    );
    final observed =
        jsonDecode(await observedFile.readAsString()) as Map<String, dynamic>;
    // Load every older page through the real paging action so the restored
    // history is compared as a whole instead of only the newest tail window.
    final timeline = await _loadCompleteHistory();
    _requireRestoredHistory(timeline, observed);
    final activeSkills = this.activeSkills(restored);
    observations['restoredActiveSkills'] = activeSkills;
    _requireNames(activeSkills, <String>[
      observed['longName'] as String,
    ], 'cold restored activation list');
    checks['restoredActivationNotResurrected'] = true;
    checks['restoredHistoryRetained'] = true;
    await capture('reopened-history');
    await _automaticCompactionTurn(timeline);
    await _cancelCompactionTurn();
  }

  /// Cancels the last Turn while its post-load compaction is still streaming.
  ///
  /// Order inside this Turn: the one-token threshold compacts the admission first,
  /// the model then loads the synthetic short Skill through one real solo call, and
  /// the compaction that follows the tool result is the cancellation target.
  /// Nothing is submitted afterwards, so the cancelled stream is proven by the real
  /// stop entry, the canonical cancellation facts and the unchanged activation
  /// instead of a follow-up Turn.
  Future<void> _cancelCompactionTurn() async {
    const prompt = 'skill-activity-cancel-turn';
    const shortName = 'skill-activity-short';
    const callId = 'skill-cancel-load-call';
    final before = await _readStatus();
    await _submit(prompt, 'cancel');
    final admitted = await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        return timeline != null && _userMessages(timeline, prompt).length == 1;
      },
      'cancel_input_admitted',
      timeout: const Duration(seconds: 120),
    );
    final cancelInputId = _userMessages(_timeline(admitted), prompt).single.id;
    observations['cancelTurnInputId'] = cancelInputId;
    final running = await waitFor(
      (snapshot) => _turnInputId(snapshot) == cancelInputId && isBusy(snapshot),
      'cancel_turn_running',
      timeout: const Duration(seconds: 120),
    );
    final turn = turnId(running)!;
    // The activation has to come from this Turn's own solo load, so the wait binds
    // the typed activation list, the canonical Skill row and that one call identity.
    final activated = await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        if (timeline == null) return false;
        final window = _latestTurnItems(timeline);
        final skills = activeSkills(snapshot);
        return _windowSkillItems(window, shortName).length == 1 &&
            _windowSkillViewCalls(window)
                    .where((item) => item.tool?.callId == callId)
                    .length ==
                1 &&
            skills.length == 1 &&
            skills.single == shortName;
      },
      'cancel_skill_activated',
      timeout: const Duration(seconds: 180),
    );
    final timeline = _timeline(activated);
    final skill = _single(
      _windowSkillItems(_latestTurnItems(timeline), shortName),
    );
    final group = _activityGroupFor(timeline, skill.id, 'cancel turn');
    final paired = _requirePairing(timeline, group, skill, 'cancel turn');
    final pairedCall = timeline.item(paired)?.tool?.callId;
    if (pairedCall != callId) {
      throw StateError(
        'the cancel activation is paired with $pairedCall instead of $callId',
      );
    }
    checks['cancelledTurnReloadedSkill'] = true;
    observations['cancelActivation'] = <String, Object?>{
      'skillId': skill.id,
      'pairedToolId': paired,
      'callId': pairedCall,
    };
    // Everything this Turn already committed counts as the "before" state: the
    // admission compaction that succeeded is part of it.
    final compactionsBefore = timeline.ofKind('contextCompaction').length;
    observations['compactionsBeforeCancel'] = compactionsBefore;
    await _awaitCancelTarget(before, turn, shortName);
    await driver.waitFor(
      find.byValueKey('composer-stop'),
      timeout: const Duration(seconds: 30),
    );
    await capture('compaction-in-flight');
    await mark('cancel_compaction_tapped');
    await driver.rawTap(
      find.byValueKey('composer-stop'),
      timeout: const Duration(seconds: 30),
    );
    await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'cancelled',
      'cancel_turn_cancelled',
      timeout: const Duration(seconds: 120),
    );
    final settled = await waitFor(
      (snapshot) => _cancelSettled(snapshot, turn),
      'cancel_turn_settled',
      timeout: const Duration(seconds: 120),
    );
    // Count from the durable end, not from the first cancelled frame: a late
    // commit would otherwise read as "nothing was committed" while still landing
    // in the history right afterwards.
    final committed = _timeline(settled).ofKind('contextCompaction').length;
    if (committed != compactionsBefore) {
      throw StateError(
        'the cancelled compaction still committed an item: '
        '$compactionsBefore -> $committed',
      );
    }
    final after = activeSkills(settled);
    await _requireNames(after, const [
      shortName,
    ], 'activation after a cancelled compaction');
    checks['cancelledCompactionKeptActivation'] = true;
    checks['cancelledCompactionCommittedNothing'] = true;
    observations['cancelledCompactionSkills'] = after;
    observations['cancelFixtureStatus'] = (await _readStatus()).toJson();
    await capture('compaction-cancelled');
  }

  /// Whether the cancelled Turn reached its durable end.
  ///
  /// Cancellation is a normal stop: the Thread stays `queued` behind the
  /// cancelled Turn, so the shared "idle" durable predicate does not describe
  /// it. The wait still binds the same Turn and both canonical completion facts —
  /// the workspace finished syncing and persistence holds no pending commit — so
  /// the settled snapshot can carry the "nothing was committed" and "activation
  /// kept" assertions instead of a first cancelled frame.
  bool _cancelSettled(Map<String, dynamic> snapshot, String turn) {
    final workspace = workspaceOf(snapshot);
    final persistence = snapshot['persistence'];
    return turnId(snapshot) == turn &&
        turnStatus(snapshot) == 'cancelled' &&
        workspace != null &&
        workspace['isBusy'] == false &&
        workspace['syncState'] == 'ready' &&
        persistence is Map &&
        persistence['kind'] == 'ready' &&
        persistence['pendingCommits'] == 0;
  }

  /// Waits until the fixture really owns the cancellation target request.
  ///
  /// The last required script step is the delayed compaction summary, so
  /// `remaining_optional` can only be true after that exact request was accepted.
  /// Together with an advanced script cursor, the same busy Turn and the typed
  /// activation this Turn already accumulated, it proves the stop entry cancels the
  /// post-load compaction instead of the admission compaction that came before it.
  Future<void> _awaitCancelTarget(
    _FixtureStatus before,
    String turn,
    String skill,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    var latest = before;
    while (DateTime.now().isBefore(deadline)) {
      latest = await _readStatus();
      final state = await snapshot();
      if (latest.rejected > before.rejected) {
        throw StateError(
          'the fixture rejected the cancellation target request: '
          '${latest.toJson()}',
        );
      }
      final skills = activeSkills(state);
      if (latest.consumedSteps > before.consumedSteps &&
          latest.remainingOptional &&
          turnId(state) == turn &&
          isBusy(state) &&
          skills.length == 1 &&
          skills.single == skill) {
        return;
      }
      if (!isBusy(state) &&
          turnStatus(state) == 'cancelled' &&
          turnId(state) == turn) {
        throw StateError(
          'the Turn was cancelled before the target compaction reached the '
          'fixture (fixture ${latest.toJson()})',
        );
      }
      if (turnFailed(state) &&
          turnId(state) == turn &&
          turnStatus(state) != 'cancelled' &&
          !isBusy(state)) {
        throw StateError(
          'the cancellation target Turn already failed before it could be '
          'cancelled (fixture ${latest.toJson()})',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      'the cancellation target never became observable in flight '
      '(fixture ${latest.toJson()}); the stop entry cannot be proven to cancel '
      'the post-load compaction',
    );
  }

  /// Loads every older page with real wheel input on the native list.
  ///
  /// The stock viewport pagination runs through the normal reading intent; no
  /// Driver-only owner action is called. Each step waits for the canonical
  /// paging facts (no in-flight page, no error, cursor/EOF/count progress) and
  /// the scroll geometry to settle, then the list is returned to the newest end
  /// so a later input starts from Live.
  Future<TimelineObservation> _loadCompleteHistory() async {
    final scrollable = find.byValueKey('timeline-scrollable');
    for (var page = 0; page < 24; page++) {
      final before = _timeline(await snapshot());
      if (!before.hasOlder) {
        await _returnToLiveEdge();
        return _timeline(await snapshot());
      }
      await mark('older_scroll_$page');
      await driver.sendCommand(
        PointerScroll(
          scrollable,
          -1000000,
          timeout: const Duration(seconds: 30),
        ),
      );
      await waitFor(
        (snapshot) {
          final timeline = TimelineObservation.optional(snapshot);
          final scroll = TimelineScrollObservation.optional(snapshot);
          return timeline != null &&
              !timeline.loadingOlder &&
              timeline.olderError == null &&
              (scroll == null || !scroll.isScrolling) &&
              (timeline.itemCount > before.itemCount ||
                  timeline.olderCursor != before.olderCursor ||
                  (!timeline.hasOlder && before.hasOlder));
        },
        'older_page_$page',
        timeout: const Duration(seconds: 90),
      );
    }
    throw StateError(
      'older paging did not reach EOF after 24 real scrolls: '
      '${_timeline(await snapshot()).summary()}',
    );
  }

  /// Real wheel back to the newest end after older pages were read.
  Future<void> _returnToLiveEdge() async {
    final scrollable = find.byValueKey('timeline-scrollable');
    for (var step = 0; step < 24; step++) {
      final state = await snapshot();
      final scroll = TimelineScrollObservation.optional(state);
      if (scroll == null || !scroll.laidOut || scroll.atLiveEdge) return;
      await driver.sendCommand(
        PointerScroll(
          scrollable,
          1000000,
          timeout: const Duration(seconds: 30),
        ),
      );
      await waitFor(
        (snapshot) {
          final timeline = TimelineObservation.optional(snapshot);
          final scroll = TimelineScrollObservation.optional(snapshot);
          return timeline != null &&
              !timeline.preparingLive &&
              scroll != null &&
              scroll.laidOut &&
              !scroll.isScrolling;
        },
        'return_live_$step',
        timeout: const Duration(seconds: 60),
      );
    }
  }

  /// Every Skill item, `skill_view` call and committed compaction item, in
  /// canonical order, with its identity, status, arguments, result markers and
  /// skill-to-call pairing. Restoring must reproduce this exactly.
  List<Map<String, Object?>> _historyFingerprint(TimelineObservation timeline) {
    final fingerprint = <Map<String, Object?>>[];
    for (final id in timeline.itemIds) {
      final item = timeline.item(id);
      if (item == null) {
        throw StateError('canonical item $id is missing from items');
      }
      switch (item.kind) {
        case 'skill':
          final group = timeline.presentationFor(item.id);
          fingerprint.add(<String, Object?>{
            'id': item.id,
            'ordinal': item.ordinal,
            'kind': 'skill',
            'name': item.text,
            'status': item.status,
            'pair': group.skillPairs[item.id],
          });
        case 'toolCall':
          final tool = item.tool;
          if (tool == null || tool.name != 'skill_view') continue;
          fingerprint.add(<String, Object?>{
            'id': item.id,
            'ordinal': item.ordinal,
            'kind': 'skill_view',
            'status': item.status,
            'callId': tool.callId,
            'arguments': tool.arguments,
            'markers': _resultMarkers(tool.result),
          });
        case 'contextCompaction':
          fingerprint.add(<String, Object?>{
            'id': item.id,
            'ordinal': item.ordinal,
            'kind': 'contextCompaction',
            'status': item.status,
          });
      }
    }
    return fingerprint;
  }

  /// Key-order independent encoding: the reopen comparison must not depend on
  /// JSON object key order, only on content and list order.
  String _canonicalJson(Object? value) => jsonEncode(_sortedKeys(value));

  Object? _sortedKeys(Object? value) {
    if (value is Map) {
      final keys = [for (final key in value.keys) '$key']..sort();
      return <String, Object?>{
        for (final key in keys) key: _sortedKeys(value[key]),
      };
    }
    if (value is List) {
      return [for (final element in value) _sortedKeys(element)];
    }
    return value;
  }

  /// Markers that must survive in a committed result: the skill body markers,
  /// the support marker and the skill names (a failed load keeps its target).
  static const _resultMarkersInHistory = <String>[
    'skill-activity-body-alpha',
    'skill-activity-body-beta',
    'skill-activity-support-marker',
    'skill-activity-short',
    'skill-activity-long-name-for-narrow-window-layout-review',
    'skill-activity-missing',
  ];

  List<String> _resultMarkers(String? result) => [
    if (result != null)
      for (final marker in _resultMarkersInHistory)
        if (result.contains(marker)) marker,
  ];

  void _requireRestoredHistory(
    TimelineObservation timeline,
    Map<String, dynamic> observed,
  ) {
    final expected = observed['fingerprint'];
    if (expected is! List) {
      throw StateError('the first lifecycle recorded no history fingerprint');
    }
    final actual = _historyFingerprint(timeline);
    if (_canonicalJson(actual) != _canonicalJson(expected)) {
      throw StateError(
        'reopened history changed identity, order, content or pairing:\n'
        'expected ${_canonicalJson(expected)}\n'
        'actual   ${_canonicalJson(actual)}',
      );
    }
    if (timeline.ofKind('skill').isEmpty ||
        timeline.ofKind('contextCompaction').isEmpty) {
      throw StateError(
        'reopened history lost its Skill or compaction items: '
        '${timeline.summary()}',
      );
    }
    final failed = [
      for (final call in _skillViewCalls(timeline))
        if (call.status == 'failed') call,
    ];
    if (failed.length != 1) {
      throw StateError(
        'reopened history must keep exactly one failed skill_view call: '
        '${failed.length}',
      );
    }
  }

  Future<void> _firstTurn() async {
    const prompt = 'skill-activity-first';
    final context = await _submit(prompt, 'first');
    final running = await _awaitNewTurn(context, 'first');
    final turn = turnId(running)!;
    final withSkill = await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        if (timeline == null) return false;
        return _namedSkillItems(timeline, 'skill-activity-short').isNotEmpty &&
            _execItem(timeline) != null;
      },
      'first_skill_committed',
      timeout: const Duration(seconds: 90),
      abort: (snapshot) => turnFailed(snapshot) && turnId(snapshot) == turn,
    );
    final timeline = _timeline(withSkill);
    final window = _latestTurnItems(timeline);
    final skill = _single(_windowSkillItems(window, 'skill-activity-short'));
    final exec = _single(_windowToolItems(window, 'exec'));
    final group = _activityGroupFor(timeline, skill.id, 'first turn');
    _requirePairing(timeline, group, skill, 'first turn');
    final counts = _visibleCounts(timeline, group, 'first turn');
    if (counts.tools != 1 || counts.skills != 1) {
      throw StateError(
        'first turn group must present one tool row and one skill row: '
        'tools=${counts.tools} skills=${counts.skills} '
        'visible=${group.visibleMemberIds}',
      );
    }
    if (!group.visibleMemberIds.contains(exec.id)) {
      throw StateError(
        'first turn group lost the ordinary command row ${exec.id}',
      );
    }
    checks['firstSkillPaired'] = true;
    checks['firstOrdinaryToolVisible'] = true;
    observations['firstVisibleCounts'] = <String, Object?>{
      'tools': counts.tools,
      'skills': counts.skills,
    };
    final settled = await _awaitSettled(turn, 'first');
    final settledTimeline = _timeline(settled);
    await _expandTimelineGroup(settledTimeline.presentationFor(skill.id));
    await capture('group-expanded');
    await _requireVisibleSkillRow(settledTimeline, skill, 'first turn');
    await driver.waitFor(
      find.byValueKey('timeline-tool-details:${exec.id}'),
      timeout: const Duration(seconds: 15),
    );
    final summary = await _activitySummary(
      settledTimeline.presentationFor(skill.id),
    );
    observations['firstSummary'] = summary;
    _requireToolThenSkillSummary(summary, counts, 'first turn');
    _firstTurnSummary = summary;
    await _expandSkillDetails(skill.id, 'skill-activity-body-alpha');
    await capture('skill-detail');
    checks['skillDetailReadable'] = true;
    await _collapseSkillDetails(skill.id, 'skill-activity-body-alpha');
    await _collapseTimelineGroup(skill.id);
    await capture('group-collapsed');
    final skills = activeSkills(settled);
    _requireNames(skills, const [
      'skill-activity-short',
    ], 'first turn activation');
    checks['firstActivationTyped'] = true;
  }

  Future<void> _mixedTurn() async {
    const prompt = 'skill-activity-mixed';
    final context = await _submit(prompt, 'mixed');
    final running = await _awaitNewTurn(context, 'mixed');
    final turn = turnId(running)!;
    final settled = await _awaitSettled(turn, 'mixed');
    final timeline = _timeline(settled);
    // Three real main-document loads (the short name twice, the long name once),
    // one support-file read and one failed load. Everything is scoped to this
    // Turn so the earlier load of the same skill can never be counted twice.
    final window = _latestTurnItems(timeline);
    final short = _requireSkills(
      _windowSkillItems(window, 'skill-activity-short'),
      2,
    );
    final long = _single(
      _windowSkillItems(
        window,
        'skill-activity-long-name-for-narrow-window-layout-review',
      ),
    );
    final calls = _windowSkillViewCalls(window);
    if (calls.length != 5) {
      throw StateError(
        'mixed turn must commit five skill_view calls: '
        '${[for (final call in calls) '${call.id}:${call.status}']}',
      );
    }
    final succeeded = [
      for (final call in calls)
        if (call.status == 'succeeded') call,
    ];
    final failedCalls = [
      for (final call in calls)
        if (call.status == 'failed') call,
    ];
    if (succeeded.length != 4 || failedCalls.length != 1) {
      throw StateError(
        'mixed turn must keep four successful and one failing skill_view call: '
        'succeeded=${succeeded.length} failed=${failedCalls.length}',
      );
    }
    final group = _activityGroupFor(timeline, short.first.id, 'mixed turn');
    for (final skill in [...short, long]) {
      if (_activityGroupFor(timeline, skill.id, 'mixed turn').id != group.id) {
        throw StateError('mixed turn split the skill rows across groups');
      }
    }
    final pairedToolIds = <String>{};
    for (final skill in [...short, long]) {
      final paired = _requirePairing(timeline, group, skill, 'mixed turn');
      if (!pairedToolIds.add(paired)) {
        throw StateError(
          'two skill activations were paired with the same skill_view call $paired',
        );
      }
    }
    if (pairedToolIds.length != 3) {
      throw StateError(
        'mixed turn must pair three activations with three distinct calls: '
        '$pairedToolIds',
      );
    }
    final failed = failedCalls.single;
    final support = succeeded.singleWhere(
      (call) => !pairedToolIds.contains(call.id),
    );
    final counts = _visibleCounts(timeline, group, 'mixed turn');
    if (counts.tools != 2 || counts.skills != 3) {
      throw StateError(
        'mixed turn group must present two tool rows and three skill rows: '
        'tools=${counts.tools} skills=${counts.skills} '
        'visible=${group.visibleMemberIds}',
      );
    }
    if (!group.visibleMemberIds.contains(failed.id) ||
        !group.visibleMemberIds.contains(support.id)) {
      throw StateError(
        'support-file and failed calls must stay visible: '
        'visible=${group.visibleMemberIds} support=${support.id} '
        'failed=${failed.id}',
      );
    }
    checks['mixedRepeatedLoadsDistinct'] = true;
    checks['mixedFailedLoadVisible'] = true;
    checks['mixedSupportFileVisible'] = true;
    observations['mixedVisibleCounts'] = <String, Object?>{
      'tools': counts.tools,
      'skills': counts.skills,
    };
    observations['mixedPairedCalls'] = pairedToolIds.toList();
    await _expandTimelineGroup(group);
    await _parkPointerForCleanCapture('mixed-group-expanded');
    await capture('mixed-group-expanded');
    for (final skill in [...short, long]) {
      await _requireVisibleSkillRow(timeline, skill, 'mixed turn');
    }
    for (final call in [failed, support]) {
      await driver.waitFor(
        find.byValueKey('timeline-tool-details:${call.id}'),
        timeout: const Duration(seconds: 15),
      );
    }
    final summary = await _activitySummary(group);
    observations['mixedSummary'] = summary;
    _requireToolThenSkillSummary(summary, counts, 'mixed turn');
    await _collapseTimelineGroup(short.first.id);
    final skills = activeSkills(settled);
    _requireNames(skills, const [
      'skill-activity-long-name-for-narrow-window-layout-review',
      'skill-activity-short',
    ], 'mixed turn activation');
    // No compaction happened between the two Turns, so the activation the first
    // Turn accumulated must still be there next to the new one.
    checks['mixedTurnKeptEarlierActivation'] = true;
    checks['mixedActivationTyped'] = true;
  }

  Future<void> _manualCompactionFailure() async {
    final before = await _readStatus();
    final skillsBefore = activeSkills(await snapshot());
    final compactionsBefore = _timeline(await snapshot())
        .ofKind('contextCompaction')
        .length;
    final idleLabel = await _compactLabel();
    await capture('compaction-ready');
    await _tapCompact();
    await _awaitCompactionHandled(before, idleLabel, 'failed compaction');
    final after = await snapshot();
    final skillsAfter = activeSkills(after);
    final compactionsAfter = _timeline(after)
        .ofKind('contextCompaction')
        .length;
    if (jsonEncode(skillsAfter) != jsonEncode(skillsBefore)) {
      throw StateError(
        'a failed compaction changed the activation list: '
        '$skillsBefore -> $skillsAfter',
      );
    }
    if (compactionsAfter != compactionsBefore) {
      throw StateError(
        'a failed compaction committed a compaction item: '
        '$compactionsBefore -> $compactionsAfter',
      );
    }
    checks['failedCompactionKeptActivation'] = true;
    observations['failedCompactionSkills'] = skillsAfter;
    // Re-open the read-only detail so the screenshot really shows the failure
    // state next to the unchanged activation list.
    await _openCompactDetail();
    await capture('compaction-failed');
  }

  Future<void> _manualCompactionSuccess() async {
    final before = await _readStatus();
    final compactionsBefore = _timeline(await snapshot())
        .ofKind('contextCompaction')
        .length;
    final idleLabel = await _compactLabel();
    await _tapCompact();
    await _awaitCompactionHandled(before, idleLabel, 'successful compaction');
    final cleared = await waitFor(
      (snapshot) =>
          activeSkills(snapshot).isEmpty &&
          _timeline(snapshot).ofKind('contextCompaction').length >
              compactionsBefore,
      'compaction_cleared',
      timeout: const Duration(seconds: 60),
    );
    if (activeSkills(cleared).isNotEmpty) {
      throw StateError(
        'the successful compaction left active skills: '
        '${activeSkills(cleared)}',
      );
    }
    checks['successfulCompactionClearedActivation'] = true;
    checks['successfulCompactionCommittedItem'] = true;
    observations['clearedCompactionItems'] = _timeline(cleared)
        .ofKind('contextCompaction')
        .length;
    await capture('compaction-cleared');
    // The compact detail keeps its hover lifecycle; move the pointer away by
    // hovering the composer before the next real input.
    await driver.sendCommand(
      PointerHover(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 20),
      ),
    );
  }

  /// Parks the pointer on a control that owns no tooltip, then waits, bounded,
  /// for the framework's tooltip overlay to leave before a screenshot.
  ///
  /// Unfolding a group scrolls and taps rows with a real pointer, so the last
  /// hovered row can leave its `Tooltip` covering exactly the rows the capture
  /// must show. The wait uses the framework overlay widget the material
  /// `Tooltip` mounts (`_TooltipBox`): it exists only while a tooltip is on
  /// screen, so its absence is a fact instead of a guessed delay. If a framework
  /// upgrade renames that private widget the absence is immediate, and the parked
  /// pointer alone keeps the capture clean.
  Future<void> _parkPointerForCleanCapture(String label) async {
    await driver.sendCommand(
      PointerHover(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 20),
      ),
    );
    var clean = true;
    try {
      await driver.waitForAbsent(
        find.byType('_TooltipBox'),
        timeout: const Duration(seconds: 10),
      );
    } on DriverError {
      // A tooltip that refuses to leave must not change the functional checks;
      // the observation records it for the human review of that screenshot.
      clean = false;
    }
    observations['${label}TooltipGone'] = clean;
  }

  Future<void> _reloadTurn() async {
    const prompt = 'skill-activity-reload';
    final context = await _submit(prompt, 'reload');
    final running = await _awaitNewTurn(context, 'reload');
    final turn = turnId(running)!;
    final settled = await _awaitSettled(turn, 'reload');
    final skills = activeSkills(settled);
    _requireNames(skills, const [
      'skill-activity-long-name-for-narrow-window-layout-review',
    ], 'post-compaction reload activation');
    final timeline = _timeline(settled);
    // Two long-name loads now exist; the newest one is this Turn's activation,
    // and the earlier one must stay readable as its own history item.
    final long = _skillItems(
      timeline,
      const _ExpectedSkill(
        'skill-activity-long-name-for-narrow-window-layout-review',
        2,
      ),
    ).last;
    final group = _activityGroupFor(timeline, long.id, 'reload turn');
    _requirePairing(timeline, group, long, 'reload turn');
    // This group owns exactly one visible skill and no visible tool, so its
    // summary states the product's own skill wording for count one.
    final summary = await _activitySummary(group);
    observations['reloadSummary'] = summary;
    final skillsOnlyPhrase = _requireSingleSkillSummary(summary, 'reload turn');
    final firstSummary = _firstTurnSummary;
    if (firstSummary == null) {
      throw StateError('the first turn summary was never observed');
    }
    _requireSkillPhraseMatches(
      firstSummary,
      skillsOnlyPhrase,
      'first turn against the skills-only wording',
    );
    checks['summaryBindsToolAndSkillCounts'] = true;
    checks['reloadAccumulatedOnlyNewSkill'] = true;
    observations['reloadActivation'] = skills;
    await capture('reload');
  }

  Future<void> _layoutEvidence() async {
    final snapshot = await this.snapshot();
    final timeline = _timeline(snapshot);
    final long = _skillItems(
      timeline,
      const _ExpectedSkill(
        'skill-activity-long-name-for-narrow-window-layout-review',
        2,
      ),
    ).last;
    final group = _activityGroupFor(timeline, long.id, 'layout evidence');
    await _expandTimelineGroup(group);
    await _scrollRowIntoView(long.id);
    await capture('long-name-wide');
    final narrow = resizeOwnedWindow(
      guiPid: _guiPid!,
      width: _narrowWidth,
      height: _narrowHeight,
    );
    if (!narrow.resized) {
      throw StateError(
        'narrow window evidence is unavailable: ${narrow.reason}',
      );
    }
    await driver.waitUntilNoTransientCallbacks(
      timeout: const Duration(seconds: 20),
    );
    await _scrollRowIntoView(long.id);
    final row = find.byValueKey('timeline-skill-activation-${long.id}');
    // Content fidelity: the row still owns the complete name. Ellipsis is a
    // visual fact; the screenshot below stays a human judgement.
    final label = await _labelText(row);
    if (!label.contains(
      'skill-activity-long-name-for-narrow-window-layout-review',
    )) {
      throw StateError(
        'the long skill row lost its full name in the narrow window: $label',
      );
    }
    final topLeft = await driver.getTopLeft(row);
    final bottomRight = await driver.getBottomRight(row);
    final width = bottomRight.dx - topLeft.dx;
    final height = bottomRight.dy - topLeft.dy;
    if (width <= 0 || height <= 0) {
      throw StateError('narrow skill row has no measurable geometry');
    }
    checks['narrowWindowContentIntact'] = true;
    // Raw geometry only: the timeline scroll viewport reports a vertical extent,
    // so it cannot bound this row's width. Ellipsis, alignment and horizontal
    // overflow stay a human judgement on the recorded screenshot.
    observations['narrowRowGeometry'] = <String, Object?>{
      'topLeft': <String, Object?>{'dx': topLeft.dx, 'dy': topLeft.dy},
      'bottomRight': <String, Object?>{
        'dx': bottomRight.dx,
        'dy': bottomRight.dy,
      },
      'width': width,
      'height': height,
    };
    pendingEvidence.add('窄窗口省略号与对齐的视觉判定待人工（截图 long-name-narrow）');
    await capture('long-name-narrow');
    final restored = resizeOwnedWindow(
      guiPid: _guiPid!,
      width: _wideWidth,
      height: _wideHeight,
    );
    if (!restored.resized) {
      throw StateError(
        'native window could not be restored: ${restored.reason}',
      );
    }
    await driver.sendCommand(
      PointerHover(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 20),
      ),
    );
  }

  /// Proves the automatic threshold path on the reopened home.
  ///
  /// The Turn is bound by the canonical `inputId` of its own `userMessage` row
  /// instead of any Turn identity change, and it must really commit an automatic
  /// compaction that leaves the activation list empty. Re-accumulating a Skill is
  /// the last Turn's job, so this Turn answers with plain text.
  Future<void> _automaticCompactionTurn(TimelineObservation restored) async {
    const prompt = 'skill-activity-reopen-turn';
    final compactionsBefore = restored.ofKind('contextCompaction').length;
    await _submit(prompt, 'reopen');
    final admitted = await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        return timeline != null && _userMessages(timeline, prompt).length == 1;
      },
      'reopen_input_admitted',
      timeout: const Duration(seconds: 120),
    );
    final reopenInputId = _userMessages(_timeline(admitted), prompt).single.id;
    observations['reopenTurnInputId'] = reopenInputId;
    final settled = await waitFor(
      (snapshot) => _inputSettled(snapshot, reopenInputId),
      'reopen_settled',
      timeout: const Duration(seconds: 240),
    );
    final timeline = _timeline(settled);
    final compactionsAfter = timeline.ofKind('contextCompaction').length;
    if (compactionsAfter <= compactionsBefore) {
      throw StateError(
        'the one-token threshold did not commit an automatic compaction: '
        '$compactionsBefore -> $compactionsAfter',
      );
    }
    final skills = activeSkills(settled);
    if (skills.isNotEmpty) {
      throw StateError('the automatic compaction left active skills: $skills');
    }
    final issues = settled['recoveryIssues'];
    if (issues is! List || issues.isNotEmpty) {
      throw StateError(
        'the automatic compaction surfaced recovery issues: $issues',
      );
    }
    checks['automaticCompactionClearedRestoredActivation'] = true;
    checks['automaticCompactionCommittedItem'] = true;
    observations['automaticCompactionItems'] = compactionsAfter;
    await capture('auto-compaction');
    await writeObserved(
      timeline,
      threadId: workspaceOf(settled)?['threadId'] as String?,
    );
  }

  /// The canonical `userMessage` rows whose text is exactly [prompt].
  ///
  /// Every prompt in this journey is unique, so exactly one row ties a submission
  /// to the Turn `inputId` that answers it. The preview cap is far larger than
  /// these prompts, so equality is the whole text and not a truncated prefix.
  List<TimelineItemObservation> _userMessages(
    TimelineObservation timeline,
    String prompt,
  ) => [
    for (final item in timeline.ofKind('userMessage'))
      if (item.text == prompt) item,
  ];

  /// The `inputId` of the Turn the workspace exposes: the active Turn first, then
  /// the last finished Turn.
  String? _turnInputId(Map<String, dynamic> snapshot) {
    final workspace = workspaceOf(snapshot);
    for (final key in const ['turn', 'lastTurn']) {
      final turn = workspace?[key];
      if (turn is Map && turn['inputId'] is String) {
        return turn['inputId'] as String;
      }
    }
    return null;
  }

  /// Whether [inputId]'s Turn finished durably.
  ///
  /// A stop leaves the Thread `queued` behind the recovered input, so completion is
  /// bound to the Turn's own `inputId` plus both canonical persistence facts
  /// instead of the Thread's idle label.
  bool _inputSettled(Map<String, dynamic> snapshot, String inputId) {
    final workspace = workspaceOf(snapshot);
    final persistence = snapshot['persistence'];
    return workspace != null &&
        _turnInputId(snapshot) == inputId &&
        turnStatus(snapshot) == 'completed' &&
        workspace['isBusy'] == false &&
        workspace['syncState'] == 'ready' &&
        persistence is Map &&
        persistence['kind'] == 'ready' &&
        persistence['pendingCommits'] == 0;
  }

  Future<void> _openProject() async {
    await driver.waitFor(
      find.byValueKey('sidebar-open-project'),
      timeout: const Duration(seconds: 120),
    );
    await tap('sidebar-open-project');
    await tap('add-project-local');
    await tap('add-project-continue-ready');
    await tap('project-path-input');
    await driver.enterText(project);
    await tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 90),
    );
  }

  /// Waits for the GUI's own Skill discovery and requires the synthetic Skills
  /// that the harness seeded into the isolated home to be present without
  /// warnings.
  ///
  /// A missing seed fails here with the canonical discovery evidence instead of
  /// surfacing later as an unexplained failing `skill_view` row.
  Future<void> _requireSkillsDiscovered() async {
    await mark('skills_discovery');
    final snapshot = await waitFor(
      (snapshot) {
        final skills = _skillsDiagnostics(snapshot);
        return skills['status'] == 'ready' || skills['status'] == 'failed';
      },
      'skills_discovery',
      timeout: const Duration(seconds: 120),
    );
    final skills = _skillsDiagnostics(snapshot);
    observations['skillsDiscovery'] = skills;
    if (skills['status'] != 'ready') {
      throw StateError('Skill discovery did not become ready: $skills');
    }
    final warnings = skills['warnings'];
    if (warnings is! List || warnings.isNotEmpty) {
      throw StateError('Skill discovery reported warnings: $skills');
    }
    final discovered = skills['skills'];
    if (discovered is! List) {
      throw StateError('Skill discovery published no names: $skills');
    }
    final missing = [
      for (final name in const [
        'skill-activity-short',
        'skill-activity-long-name-for-narrow-window-layout-review',
      ])
        if (!discovered.contains(name)) name,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'the GUI did not discover the seeded Skill(s) $missing: $skills',
      );
    }
  }

  Map<String, Object?> _skillsDiagnostics(Map<String, dynamic> snapshot) {
    final diagnostics = snapshot['driverDiagnostics'];
    final skills = diagnostics is Map ? diagnostics['skills'] : null;
    if (skills is! Map) {
      throw StateError('driverDiagnostics.skills is missing: $diagnostics');
    }
    return skills.cast<String, Object?>();
  }

  /// Submits [prompt] through the real composer and returns the Turn identity
  /// that was current before the input, so the next Turn is a real new one.
  Future<String?> _submit(String prompt, String label) async {
    final before = await snapshot();
    await mark('${label}_submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
    await tap('composer-input');
    await driver.enterText(prompt);
    await tap('composer-submit');
    return turnId(before);
  }

  Future<Map<String, dynamic>> _awaitNewTurn(
    String? priorTurnId,
    String label,
  ) => waitFor(
    (snapshot) => turnId(snapshot) != priorTurnId,
    '${label}_running',
    timeout: const Duration(seconds: 60),
  );

  Future<Map<String, dynamic>> _awaitSettled(String turn, String label) =>
      waitFor(
        (snapshot) =>
            turnId(snapshot) == turn &&
            isDurableSettled(snapshot) &&
            turnStatus(snapshot) == 'completed',
        '${label}_settled',
        timeout: const Duration(seconds: 240),
        abort: (snapshot) =>
            turnId(snapshot) == turn &&
            ['failed', 'cancelled'].contains(turnStatus(snapshot)),
      );

  Future<Map<String, dynamic>> snapshot() => driver.readSnapshot();

  Future<Map<String, dynamic>> waitFor(
    bool Function(Map<String, dynamic>) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 120),
    bool Function(Map<String, dynamic>)? abort,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final current = await snapshot();
      last = current;
      if (predicate(current)) return current;
      if (abort != null && abort(current)) {
        throw StateError('$label aborted: ${_summarize(current)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      'timed out waiting for $label: '
      '${last == null ? '{}' : _summarize(last)}',
    );
  }

  TimelineObservation _timeline(Map<String, dynamic> snapshot) {
    final timeline = TimelineObservation.parse(snapshot);
    timeline.requireConsistentIds();
    return timeline;
  }

  /// The typed runtime activation list. It is a Driver-only read of the Client
  /// runtime read-model, never a parsed tool output or a Driver mirror.
  List<String> activeSkills(Map<String, dynamic> snapshot) {
    final diagnostics = snapshot['driverDiagnostics'];
    final runtime = diagnostics is Map ? diagnostics['runtime'] : null;
    if (runtime is! Map) {
      throw StateError('driverDiagnostics.runtime is missing: $diagnostics');
    }
    final raw = runtime['activeSkills'];
    if (raw is! List) {
      throw StateError(
        'driverDiagnostics.runtime.activeSkills is missing; the Driver-only '
        'runtime diagnostics must expose the typed active skill names '
        '(got $raw)',
      );
    }
    final names = <String>[];
    for (final value in raw) {
      if (value is! String) {
        throw StateError('activeSkills entry is not a string: $value');
      }
      names.add(value);
    }
    return names;
  }

  List<TimelineItemObservation> _skillItems(
    TimelineObservation timeline,
    _ExpectedSkill expected,
  ) {
    final items = _namedSkillItems(timeline, expected.name);
    if (items.length != expected.count) {
      throw StateError(
        'expected ${expected.count} Skill item(s) named ${expected.name}, '
        'observed ${[for (final item in items) item.id]}',
      );
    }
    return items;
  }

  /// Non-throwing lookup for polling predicates: an item that has not been
  /// committed yet is simply absent, never a failed observation.
  List<TimelineItemObservation> _namedSkillItems(
    TimelineObservation timeline,
    String name,
  ) => [
    for (final item in timeline.ofKind('skill'))
      if (item.text == name) item,
  ];

  /// The canonical items of the newest Turn, in canonical order.
  ///
  /// Turn-scoped assertions use this window so an earlier load of the same skill
  /// can never be counted as part of the current Turn.
  List<TimelineItemObservation> _latestTurnItems(TimelineObservation timeline) {
    var start = 0;
    for (var index = timeline.itemIds.length - 1; index >= 0; index--) {
      final item = timeline.item(timeline.itemIds[index]);
      if (item == null) {
        throw StateError(
          'canonical item ${timeline.itemIds[index]} is missing from items',
        );
      }
      if (item.kind == 'userMessage') {
        start = index;
        break;
      }
    }
    return [
      for (var index = start; index < timeline.itemIds.length; index++)
        timeline.item(timeline.itemIds[index])!,
    ];
  }

  List<TimelineItemObservation> _windowSkillItems(
    List<TimelineItemObservation> window,
    String name,
  ) => [
    for (final item in window)
      if (item.kind == 'skill' && item.text == name) item,
  ];

  List<TimelineItemObservation> _windowToolItems(
    List<TimelineItemObservation> window,
    String toolName,
  ) => [
    for (final item in window)
      if (item.kind == 'toolCall' && item.tool?.name == toolName) item,
  ];

  List<TimelineItemObservation> _windowSkillViewCalls(
    List<TimelineItemObservation> window,
  ) => _windowToolItems(window, 'skill_view');

  /// Requires exactly [count] items and reports their identities otherwise.
  List<TimelineItemObservation> _requireSkills(
    List<TimelineItemObservation> items,
    int count,
  ) {
    if (items.length != count) {
      throw StateError(
        'expected $count Skill item(s) in this Turn, observed '
        '${[for (final item in items) item.id]}',
      );
    }
    return items;
  }

  List<TimelineItemObservation> _skillViewCalls(TimelineObservation timeline) =>
      [
        for (final item in timeline.ofKind('toolCall'))
          if (item.tool?.name == 'skill_view') item,
      ];

  TimelineItemObservation? _execItem(TimelineObservation timeline) {
    for (final item in timeline.ofKind('toolCall')) {
      if (item.tool?.name == 'exec') return item;
    }
    return null;
  }

  TimelineItemObservation _single(List<TimelineItemObservation> items) {
    if (items.length != 1) {
      throw StateError(
        'expected exactly one canonical item, observed ${items.length}: '
        '${[for (final item in items) item.id]}',
      );
    }
    return items.single;
  }

  TimelinePresentationObservation _activityGroupFor(
    TimelineObservation timeline,
    String sourceId,
    String label,
  ) {
    final group = timeline.presentationFor(sourceId);
    if (group.kind != 'activity') {
      throw StateError(
        '$label presented $sourceId as ${group.kind} instead of an activity group',
      );
    }
    return group;
  }

  /// Returns the canonical `skill_view` call this activation took over.
  String _requirePairing(
    TimelineObservation timeline,
    TimelinePresentationObservation group,
    TimelineItemObservation skill,
    String label,
  ) {
    final paired = group.skillPairs[skill.id];
    if (paired == null) {
      throw StateError(
        '$label skill ${skill.id} has no paired skill_view call in group '
        '${group.id}: ${group.skillPairs}',
      );
    }
    final tool = timeline.item(paired);
    if (tool == null) {
      throw StateError(
        '$label paired call $paired is missing from the canonical items',
      );
    }
    if (tool.kind != 'toolCall' || tool.tool?.name != 'skill_view') {
      throw StateError(
        '$label paired call $paired is not a skill_view tool call',
      );
    }
    if (tool.status != 'succeeded') {
      throw StateError(
        '$label paired call $paired is ${tool.status}, not a successful load',
      );
    }
    if (!group.memberIds.contains(paired)) {
      throw StateError(
        '$label paired call $paired was removed from the canonical members',
      );
    }
    if (group.visibleMemberIds.contains(paired)) {
      throw StateError(
        '$label paired call $paired still owns a separate visible row',
      );
    }
    return paired;
  }

  ({int tools, int skills}) _visibleCounts(
    TimelineObservation timeline,
    TimelinePresentationObservation group,
    String label,
  ) {
    var tools = 0;
    var skills = 0;
    for (final id in group.visibleMemberIds) {
      final item = timeline.item(id);
      if (item == null) {
        throw StateError('$label visible member $id is not a canonical item');
      }
      switch (item.kind) {
        case 'skill':
          skills++;
        case 'toolCall':
          tools++;
      }
    }
    return (tools: tools, skills: skills);
  }

  Future<String> _activitySummary(TimelinePresentationObservation group) =>
      _labelText(find.byValueKey('timeline-activity-summary-${group.id}'));

  /// The label text a composed target really renders.
  ///
  /// Flutter Driver's `getText` only accepts widgets that own text data, while a
  /// group summary, a skill row and the compact entry are composed widgets
  /// (`TimelineActivityRow`, `TextButton.icon`). The label is read from that
  /// target's own `Text` descendant, so an overflow ellipsis stays a visual fact
  /// while the intact string remains assertable.
  Future<String> _labelText(SerializableFinder target) => driver.getText(
    find.descendant(
      of: target,
      matching: find.byType('Text'),
      firstMatchOnly: true,
    ),
  );

  /// Count-bearing `·` segments of a folded summary, in the order the product
  /// writes them: the tool phrase (its first number is the visible tool count)
  /// comes first, then the skill phrase from `statusSkillsCount`.
  ///
  /// The product's own wording is read here instead of a re-implemented locale
  /// table: separation is the documented `·` join, and the skill wording is
  /// cross-checked against a skills-only group below.
  List<String> _summaryCountSegments(String summary) {
    final segments = [
      for (final part in summary.split(' · '))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return [
      for (final segment in segments)
        if (RegExp(r'^\d+').hasMatch(segment)) segment,
    ];
  }

  /// A group with visible tools and skills must report the tool count first and
  /// the skill count second, each as the first number of its own phrase.
  void _requireToolThenSkillSummary(
    String summary,
    ({int tools, int skills}) counts,
    String label,
  ) {
    if (summary.trim().isEmpty) {
      throw StateError('$label folded summary is empty');
    }
    final segments = _summaryCountSegments(summary);
    if (segments.length != 2) {
      throw StateError(
        '$label folded summary $summary must carry one tool phrase and one '
        'skill phrase: $segments',
      );
    }
    final toolPhrase = segments.first;
    final skillPhrase = segments.last;
    if (!toolPhrase.startsWith('${counts.tools}')) {
      throw StateError(
        '$label folded summary $summary reports the tool phrase as '
        '"$toolPhrase" instead of ${counts.tools}',
      );
    }
    if (!skillPhrase.startsWith('${counts.skills}')) {
      throw StateError(
        '$label folded summary $summary reports the skill phrase as '
        '"$skillPhrase" instead of ${counts.skills}',
      );
    }
    if (toolPhrase == skillPhrase) {
      throw StateError(
        '$label folded summary $summary uses one phrase for both counts',
      );
    }
  }

  /// A group whose only visible activity is a single skill states exactly one
  /// skill and never a zero-tool phrase. Returns that skill wording.
  String _requireSingleSkillSummary(String summary, String label) {
    final segments = _summaryCountSegments(summary);
    if (segments.length != 1) {
      throw StateError(
        '$label folded summary $summary must state only the skill count: '
        '$segments',
      );
    }
    final phrase = segments.single;
    if (!phrase.startsWith('1')) {
      throw StateError(
        '$label folded summary $summary states "$phrase" instead of one skill',
      );
    }
    return phrase;
  }

  /// Cross-checks that the phrase in the second position of a tool+skill summary
  /// is the skill wording the product itself used for the skills-only group.
  void _requireSkillPhraseMatches(
    String summary,
    String skillsOnlyPhrase,
    String label,
  ) {
    final segments = _summaryCountSegments(summary);
    if (segments.length != 2 || segments.last != skillsOnlyPhrase) {
      throw StateError(
        '$label folded summary $summary does not reuse the skills-only wording '
        '"$skillsOnlyPhrase" in its second count position: $segments',
      );
    }
  }

  Future<void> _expandTimelineGroup(
    TimelinePresentationObservation group,
  ) async {
    if (group.expanded) return;
    final summary = find.byValueKey('timeline-activity-summary-${group.id}');
    await _tapHeader(summary, 'group ${group.id}');
    await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        if (timeline == null) return false;
        return timeline.presentationItems
            .singleWhere((item) => item.id == group.id)
            .expanded;
      },
      'group_${group.id}_expanded',
      timeout: const Duration(seconds: 20),
    );
  }

  Future<void> _collapseTimelineGroup(String sourceId) async {
    final timeline = _timeline(await snapshot());
    final group = timeline.presentationFor(sourceId);
    if (!group.expanded) return;
    final summary = find.byValueKey('timeline-activity-summary-${group.id}');
    await _tapHeader(summary, 'group ${group.id}');
    await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        if (timeline == null) return false;
        return !timeline.presentationFor(sourceId).expanded;
      },
      'group_${group.id}_collapsed',
      timeout: const Duration(seconds: 20),
    );
  }

  /// Expands the skill row through its real header.
  ///
  /// The keyed row is the `ExpansionTile` title, so the header is the row's
  /// `ListTile` ancestor; the expansion is proven by the paired `skill_view`
  /// result really becoming readable (`maintainState: false` builds the children
  /// only while expanded).
  Future<void> _expandSkillDetails(String skillId, String contentMarker) async {
    final row = find.byValueKey('timeline-skill-activation-$skillId');
    await driver.waitFor(row, timeout: const Duration(seconds: 20));
    final group = _timeline(await snapshot()).presentationFor(skillId);
    if (group.skillPairs[skillId] == null) {
      throw StateError(
        'skill $skillId has no paired skill_view call to read from its details',
      );
    }
    await _tapHeader(row, 'skill_${skillId}_details');
    await _waitForTree('skill_${skillId}_detail', contentMarker, present: true);
  }

  Future<void> _collapseSkillDetails(
    String skillId,
    String contentMarker,
  ) async {
    final row = find.byValueKey('timeline-skill-activation-$skillId');
    await _tapHeader(row, 'skill_${skillId}_details_collapsed');
    await _waitForTree(
      'skill_${skillId}_detail_collapsed',
      contentMarker,
      present: false,
    );
  }

  /// Waits, bounded, until the real widget tree does (not) contain [needle].
  Future<void> _waitForTree(
    String label,
    String needle, {
    required bool present,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final contains = (await driver.renderTree()).contains(needle);
      if (contains == present) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      '$label: detail content "$needle" stayed '
      '${present ? 'unreadable' : 'readable'}',
    );
  }

  /// The skill row must exist as one visible row that names the skill, while the
  /// call it took over owns no separate tool row.
  Future<void> _requireVisibleSkillRow(
    TimelineObservation timeline,
    TimelineItemObservation skill,
    String label,
  ) async {
    final group = timeline.presentationFor(skill.id);
    final paired = group.skillPairs[skill.id];
    await driver.waitFor(
      find.byValueKey('timeline-skill-activation-${skill.id}'),
      timeout: const Duration(seconds: 20),
    );
    final text = await _labelText(
      find.byValueKey('timeline-skill-activation-${skill.id}'),
    );
    if (!text.contains(skill.text)) {
      throw StateError('$label skill row $text does not name ${skill.text}');
    }
    if (paired != null) {
      await driver.waitForAbsent(
        find.byValueKey('timeline-tool-details:$paired'),
        timeout: const Duration(seconds: 15),
      );
    }
  }

  Future<void> _scrollRowIntoView(String itemId) async {
    // The row key belongs to the group summary, so scrolling targets the group
    // row that really exists instead of guessing a member row key.
    final timeline = _timeline(await snapshot());
    final group = timeline.presentationFor(itemId);
    try {
      await driver.scrollUntilVisible(
        find.byValueKey('timeline-scrollable'),
        find.byValueKey('timeline-row-${group.id}'),
        dyScroll: -80,
        timeout: const Duration(seconds: 20),
      );
    } on DriverError {
      // A short history keeps the row laid out; the following read still has to
      // find a real widget with a real geometry.
    }
    await driver.waitFor(
      find.byValueKey('timeline-skill-activation-$itemId'),
      timeout: const Duration(seconds: 20),
    );
  }

  /// Taps the real header `ListTile` of [child] (a group summary or a member row)
  /// after bringing it into the visible range of its own scrollable.
  Future<void> _tapHeader(SerializableFinder child, String label) async {
    final header = find.ancestor(
      of: child,
      matching: find.byType('ListTile'),
      firstMatchOnly: true,
    );
    await _scrollHeaderIntoView(header, label);
    await driver.rawTap(header, timeout: const Duration(seconds: 20));
    await mark('tapped_$label');
  }

  Future<void> _scrollHeaderIntoView(
    SerializableFinder header,
    String label,
  ) async {
    try {
      await driver.scrollUntilVisible(
        find.byValueKey('timeline-scrollable'),
        header,
        dyScroll: -80,
        timeout: const Duration(seconds: 15),
      );
    } on DriverError {
      // The outer list already shows the group; the member may still be clipped
      // inside the group's own bounded scrollable, handled next.
    }
    // A group with more than five visible members is a lazy list, a smaller one
    // is a bounded single-child scrollable: both are real inner scrollables.
    final inner = find.ancestor(
      of: header,
      matching: find.byType('Scrollable'),
      firstMatchOnly: true,
    );
    try {
      await driver.waitFor(inner, timeout: const Duration(seconds: 2));
    } on DriverError {
      return;
    }
    try {
      await driver.scrollUntilVisible(
        inner,
        header,
        dyScroll: -80,
        timeout: const Duration(seconds: 15),
      );
    } on DriverError {
      // Already fully visible inside the inner scrollable.
    }
    final top = await driver.getTopLeft(header);
    final bottom = await driver.getBottomRight(header);
    if (bottom.dy - top.dy <= 0) {
      throw StateError('header geometry is empty after scrolling: $label');
    }
  }

  Future<void> _openCompactDetail() async {
    await driver.sendCommand(
      PointerHover(
        find.byValueKey('context-usage'),
        timeout: const Duration(seconds: 20),
      ),
    );
    await driver.waitFor(
      find.byValueKey('studio-compact-context'),
      timeout: const Duration(seconds: 20),
    );
  }

  Future<void> _tapCompact() async {
    await mark('compact_tapped');
    await driver.rawTap(
      find.byValueKey('studio-compact-context'),
      timeout: const Duration(seconds: 20),
    );
  }

  /// The real compact entry label. [idleLabel] stays the observed idle wording,
  /// so the pending check never depends on the current locale.
  Future<String> _compactLabel() async {
    await _openCompactDetail();
    // The entry is a `TextButton.icon`: read its label `Text` child instead of
    // the button widget.
    return _labelText(find.byValueKey('studio-compact-context'));
  }

  /// Waits for the fixture to consume the compaction request and for the real
  /// compact entry to leave its pending label, without a fixed sleep.
  Future<void> _awaitCompactionHandled(
    _FixtureStatus before,
    String idleLabel,
    String label,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    var consumed = false;
    _FixtureStatus latest = before;
    while (DateTime.now().isBefore(deadline)) {
      latest = await _readStatus();
      if (!consumed) {
        if (latest.consumedSteps > before.consumedSteps) {
          consumed = true;
          await mark('${label.replaceAll(' ', '_')}_consumed');
        }
      }
      if (consumed && await _compactLabel() == idleLabel) {
        if (latest.rejected > before.rejected) {
          throw StateError(
            'the fixture rejected the $label request: ${latest.toJson()}',
          );
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      '$label did not settle: ${latest.toJson()} '
      '(the compact entry stayed pending or the fixture never consumed it)',
    );
  }

  Future<_FixtureStatus> _readStatus() async {
    final file = File(fixtureStatusPath);
    if (!file.existsSync()) {
      throw StateError('the fixture live status file is missing: ${file.path}');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw StateError('the fixture live status is not an object: $decoded');
    }
    return _FixtureStatus(
      accepted: (decoded['accepted'] as num?)?.toInt() ?? 0,
      rejected: (decoded['rejected'] as num?)?.toInt() ?? 0,
      total: (decoded['total'] as num?)?.toInt() ?? 0,
      consumedSteps: (decoded['consumed_steps'] as num?)?.toInt() ?? 0,
      expectedSteps: (decoded['expected_steps'] as num?)?.toInt() ?? 0,
      remainingOptional: _strictBool(decoded, 'remaining_optional'),
    );
  }

  /// Reads a required boolean from the fixture live status.
  ///
  /// The fixture always publishes it; a missing or non-boolean value is a fact
  /// mismatch and must fail instead of defaulting to `false`.
  bool _strictBool(Map<dynamic, dynamic> source, String key) {
    final value = source[key];
    if (value is! bool) {
      throw StateError(
        'the fixture live status has no boolean `$key`: $source',
      );
    }
    return value;
  }

  Future<void> _requireNames(
    List<String> observed,
    List<String> expected,
    String label,
  ) async {
    final sortedObserved = [...observed]..sort();
    final sortedExpected = [...expected]..sort();
    if (jsonEncode(sortedObserved) != jsonEncode(sortedExpected)) {
      throw StateError('$label: $sortedObserved != $sortedExpected');
    }
  }

  /// Records the expectations the reopened lifecycle compares against.
  ///
  /// The caller passes the entirely loaded history, so a bounded tail window can
  /// never masquerade as the whole Thread.
  Future<void> writeObserved(
    TimelineObservation timeline, {
    required String? threadId,
  }) async {
    final observed = <String, Object?>{
      'threadId': threadId,
      'skillNames': [for (final item in timeline.ofKind('skill')) item.text],
      'skillViewCalls': [for (final item in _skillViewCalls(timeline)) item.id],
      'contextCompactions': timeline.ofKind('contextCompaction').length,
      'fingerprint': _historyFingerprint(timeline),
      'longName': 'skill-activity-long-name-for-narrow-window-layout-review',
    };
    await File(observedFile.path).writeAsString(jsonEncode(observed));
  }

  Future<void> tap(String key) async {
    await mark('tap_$key');
    if (key.startsWith('timeline-activity-summary-')) {
      await _tapHeader(find.byValueKey(key), key);
      return;
    }
    await driver.rawTap(
      find.byValueKey(key),
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> mark(String value) async {
    stage = value;
    await stageFile.writeAsString(value);
  }

  Future<void> capture(String name, {bool tree = false}) async {
    await mark(name);
    final state = await snapshot();
    final record = <String, Object?>{
      'name': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      'summary': _summarize(state),
    };
    await File(
      '${output.path}/skill-activity-$name.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(state)}\n');
    try {
      await File('${output.path}/skill-activity-$name.png')
          .writeAsBytes(await driver.screenshot());
      record['screenshot'] = true;
    } catch (error) {
      record['screenshot'] = false;
      record['screenshotError'] = '$error';
      captures.add(record);
      throw StateError('required screenshot "$name" failed: $error');
    }
    if (tree) {
      try {
        await File('${output.path}/skill-activity-$name-tree.txt')
            .writeAsString(await driver.renderTree());
        record['tree'] = true;
      } catch (error) {
        record['tree'] = false;
        record['treeError'] = '$error';
      }
    }
    captures.add(record);
  }

  Future<void> captureFailure() async {
    try {
      await capture('failure', tree: true);
    } catch (_) {
      // Preserve the original failure if the window is no longer available.
    }
  }

  Future<void> shutdown() async {
    try {
      final reply = jsonDecode(
        await driver
            .requestData('shutdown', timeout: const Duration(seconds: 60))
            .timeout(const Duration(seconds: 65)),
      );
      if (reply is! Map || reply['shutdown'] != 'completed') {
        throw StateError('native GUI shutdown did not report completion');
      }
    } finally {
      try {
        await driver.close().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Normal shutdown can close the VM connection before its client.
      }
    }
  }

  Future<void> writeSummary({Object? failure}) async {
    final pending = [
      if (failure != null) 'journey: $failure',
      if (shutdownError != null) 'shutdown: $shutdownError',
    ];
    final summary = <String, Object?>{
      'scenario': 'skill-activity',
      'phase': phase,
      'verdict': 'pending',
      'status': failure == null && shutdownError == null
          ? 'complete'
          : 'failed',
      'stage': stage,
      'error': failure?.toString(),
      'shutdownError': shutdownError,
      'checks': checks,
      'failedChecks': [
        for (final entry in checks.entries)
          if (entry.value != true) entry.key,
      ],
      'observations': observations,
      'captures': captures,
      'pendingEvidence': pending,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      '${output.path}/skill-activity-$phase-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  }

  String _summarize(Map<String, dynamic> snapshot) {
    final timeline = TimelineObservation.optional(snapshot);
    final workspace = workspaceOf(snapshot);
    final skills = (() {
      try {
        return activeSkills(snapshot);
      } catch (error) {
        return '<unavailable: $error>';
      }
    })();
    return jsonEncode(<String, Object?>{
      'turnId': turnId(snapshot),
      'turnStatus': turnStatus(snapshot),
      'busy': workspace?['isBusy'],
      'threadStatus': workspace?['threadStatus'],
      'activeSkills': skills,
      'itemCount': timeline?.itemCount,
      'skillItems': timeline == null
          ? null
          : [
              for (final item in timeline.ofKind('skill'))
                <String, Object?>{'id': item.id, 'name': item.text},
            ],
      'contextCompactions': timeline?.ofKind('contextCompaction').length,
    });
  }
}

class _ExpectedSkill {
  const _ExpectedSkill(this.name, this.count);

  final String name;
  final int count;
}

class _FixtureStatus {
  const _FixtureStatus({
    required this.accepted,
    required this.rejected,
    required this.total,
    required this.consumedSteps,
    required this.expectedSteps,
    required this.remainingOptional,
  });

  final int accepted;
  final int rejected;
  final int total;
  final int consumedSteps;
  final int expectedSteps;

  /// Every script step still at the cursor is optional, i.e. the fixture already
  /// accepted every required step. The last required step is the delayed
  /// cancellation target, so this is the fact that proves the target request was
  /// really consumed.
  final bool remainingOptional;

  Map<String, Object?> toJson() => <String, Object?>{
    'accepted': accepted,
    'rejected': rejected,
    'total': total,
    'consumedSteps': consumedSteps,
    'expectedSteps': expectedSteps,
    'remainingOptional': remainingOptional,
  };
}
