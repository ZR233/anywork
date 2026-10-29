part of 'skill_activity_journey.dart';

const _dynamicPrompt = 'skill-activity-dynamic';
const _dynamicViewedName = 'skill-activity-dynamic-view';
const _dynamicListedName = 'skill-activity-dynamic-list';
const _dynamicBodyMarker = 'skill-activity-dynamic-body-gamma';
const _dynamicCallIds = [
  'skill-dynamic-before-call',
  'skill-dynamic-create-view-call',
  'skill-dynamic-view-new-call',
  'skill-dynamic-create-list-call',
  'skill-dynamic-added-call',
  'skill-dynamic-delete-call',
  'skill-dynamic-invalidate-call',
  'skill-dynamic-empty-call',
  'skill-dynamic-view-deleted-call',
  'skill-dynamic-view-invalid-call',
];
const _dynamicBackgroundCallIds = [
  'skill-dynamic-before-call',
  'skill-dynamic-create-view-call',
  'skill-dynamic-create-list-call',
  'skill-dynamic-added-call',
  'skill-dynamic-delete-call',
  'skill-dynamic-invalidate-call',
  'skill-dynamic-empty-call',
];

bool _isDynamicWaitCallId(String id) =>
    _dynamicBackgroundCallIds.any((callId) => id == '$callId-wait-call');

/// Same-Turn native observation, not a model assertion or a mirror catalog.
/// The fixture only supplies calls. Production file tools mutate the isolated
/// project; canonical list/view results and their actual expanded UI decide
/// whether discovery refreshed. No new input is submitted between those calls.
final class _DynamicSkillActivity {
  _DynamicSkillActivity(this.journey);

  final SkillActivityJourney journey;
  late final String inputId;
  late final String turn;
  late final List<TimelineItemObservation> window;
  late final TimelineObservation timeline;

  Future<void> run() async {
    await journey._submit(_dynamicPrompt, 'dynamic');
    final admitted = await journey.waitFor((snapshot) {
      final current = TimelineObservation.optional(snapshot);
      return current != null &&
          journey._userMessages(current, _dynamicPrompt).length == 1;
    }, 'dynamic_input_admitted');
    inputId = journey
        ._userMessages(journey._timeline(admitted), _dynamicPrompt)
        .single
        .id;
    final settled = await journey.waitFor(
      (snapshot) => journey._inputSettled(snapshot, inputId),
      'dynamic_settled',
      timeout: const Duration(seconds: 240),
      abort: (snapshot) =>
          journey._turnInputId(snapshot) == inputId &&
          ['failed', 'cancelled'].contains(turnStatus(snapshot)),
    );
    turn = turnId(settled)!;
    timeline = journey._timeline(settled);
    final start = timeline.itemIds.indexOf(inputId);
    if (start < 0) throw StateError('dynamic input $inputId is not canonical');
    window = [
      for (final id in timeline.itemIds.skip(start)) timeline.item(id)!,
    ];
    if (window.where((item) => item.kind == 'userMessage').length != 1) {
      throw StateError('dynamic calls crossed an input/Turn boundary');
    }
    final calls = [
      for (final item in window)
        if (item.tool != null) item,
    ];
    final callIds = [
      for (final item in calls)
        if (_dynamicCallIds.contains(item.tool!.callId)) item.tool!.callId,
    ];
    if (jsonEncode(callIds) != jsonEncode(_dynamicCallIds)) {
      throw StateError(
        'dynamic Turn reordered, omitted or added calls: $callIds',
      );
    }
    if (calls.any((item) => !timeline.itemIds.contains(item.id))) {
      throw StateError('dynamic calls are missing canonical completion atoms');
    }
    final waits = _requireWaitHandoffs(calls);
    journey.checks['dynamicSameTurnCallIdentities'] = true;
    journey.checks['dynamicCallsAreCanonicalCompletionAtoms'] = true;

    _requireList('skill-dynamic-before-call', const []);
    _requireWrite(
      'skill-dynamic-create-view-call',
      _dynamicViewedName,
      'create',
    );
    final view = _call(
      'skill-dynamic-view-new-call',
      'skill_view',
      'succeeded',
    );
    _requireTarget(view, _dynamicViewedName);
    if (!view.tool!.result!.contains(_dynamicBodyMarker)) {
      throw StateError('the new Skill view did not return its real document');
    }
    // There is no intervening list after this write: this view itself must
    // discover the new Skill. The second write then invalidates the view's own
    // discovery snapshot, so the later list must independently rediscover too.
    journey.checks['dynamicViewDiscoversBeforeList'] = true;
    _requireWrite(
      'skill-dynamic-create-list-call',
      _dynamicListedName,
      'create',
    );
    _requireList('skill-dynamic-added-call', const [
      _dynamicListedName,
      _dynamicViewedName,
    ]);
    journey.checks['dynamicListDiscoversNewSkill'] = true;
    final deleted = _call(
      'skill-dynamic-delete-call',
      'delete_path',
      'succeeded',
    );
    final deleteArgs = _arguments(deleted);
    if (deleteArgs['path'] != '.agents/skills/$_dynamicViewedName' ||
        deleteArgs['mode'] != 'recursiveDirectory') {
      throw StateError('dynamic deletion did not target its owned Skill');
    }
    _requireWrite(
      'skill-dynamic-invalidate-call',
      _dynamicListedName,
      'overwrite',
    );
    _requireList('skill-dynamic-empty-call', const []);
    for (final (callId, name) in const [
      ('skill-dynamic-view-deleted-call', _dynamicViewedName),
      ('skill-dynamic-view-invalid-call', _dynamicListedName),
    ]) {
      final failed = _call(callId, 'skill_view', 'failed');
      _requireTarget(failed, name);
      if (failed.tool!.result?.contains(_dynamicBodyMarker) == true) {
        throw StateError('$callId returned an unrelated or stale view result');
      }
    }
    journey.checks['dynamicDeletionAndInvalidityVisible'] = true;

    final skill = journey._single(
      journey._windowSkillItems(window, _dynamicViewedName),
    );
    final group = journey._activityGroupFor(timeline, skill.id, 'dynamic Turn');
    final paired = journey._requirePairing(
      timeline,
      group,
      skill,
      'dynamic Turn',
    );
    if (paired != view.id ||
        journey._windowSkillItems(window, _dynamicListedName).isNotEmpty) {
      throw StateError('dynamic activation paired with an unrelated load');
    }
    await journey._requireNames(journey.activeSkills(settled), const [
      'skill-activity-short',
      'skill-activity-long-name-for-narrow-window-layout-review',
      _dynamicViewedName,
    ], 'deleted Skill remains a historical activation until compaction');
    journey.checks['dynamicDeletedActivationRetained'] = true;
    journey.observations['dynamicTurn'] = <String, Object?>{
      'inputId': inputId,
      'turnId': turn,
      'callIds': callIds,
      'waits': waits,
      'skillItemId': skill.id,
      'pairedToolItemId': paired,
      'activeSkillsAfterDeletion': journey.activeSkills(settled),
      'lists': <String, Object?>{
        'before': const <String>[],
        'added': const [_dynamicListedName, _dynamicViewedName],
        'afterDeletionAndInvalidation': const <String>[],
      },
    };

    await journey._expandTimelineGroup(group);
    await _captureDetail(view, 'dynamic-view-new', skill: skill);
    await _captureDetail(
      _call('skill-dynamic-added-call', 'skills_list', 'succeeded'),
      'dynamic-list-added',
    );
    await _captureDetail(
      _call('skill-dynamic-empty-call', 'skills_list', 'succeeded'),
      'dynamic-list-empty',
    );
    await _captureDetail(
      _call('skill-dynamic-view-deleted-call', 'skill_view', 'failed'),
      'dynamic-view-deleted',
    );
    journey.checks['dynamicCanonicalDetailsReadable'] = true;
    await journey._collapseTimelineGroup(skill.id);
    await journey._returnToLiveEdge();
  }

  TimelineItemObservation _call(String callId, String name, String status) {
    final item = journey._single([
      for (final item in window)
        if (item.tool?.callId == callId) item,
    ]);
    if (item.tool?.name != name ||
        item.status != status ||
        item.tool?.status != status ||
        (status == 'succeeded' && item.tool?.result?.isNotEmpty != true)) {
      throw StateError('$callId is not a real $name/$status result');
    }
    return item;
  }

  /// Business order is unchanged. Only one solo wait on the immediately
  /// preceding business call's real task receipt may be interleaved, and its
  /// returned canonical task view must already report that exact task succeeded.
  List<Map<String, Object?>> _requireWaitHandoffs(
    List<TimelineItemObservation> calls,
  ) {
    TimelineItemObservation? previous;
    final waited = <String>{};
    final observations = <Map<String, Object?>>[];
    for (final call in calls) {
      final id = call.tool!.callId;
      if (_dynamicCallIds.contains(id)) {
        previous = call;
        continue;
      }
      final parent = previous?.tool;
      if (parent == null ||
          !_dynamicBackgroundCallIds.contains(parent.callId) ||
          id != '${parent.callId}-wait-call' ||
          !waited.add(parent.callId) ||
          call.tool!.name != 'wait' ||
          call.status != 'succeeded' ||
          call.tool!.status != 'succeeded') {
        throw StateError(
          'unexpected, duplicated or reordered dynamic wait $id',
        );
      }
      final args = _arguments(call);
      final timeout = args['timeoutMs'];
      if (args.length != 2 ||
          jsonEncode(args['taskIds']) !=
              jsonEncode(['task:${parent.callId}']) ||
          timeout is! int ||
          timeout <= 0 ||
          timeout > 300000) {
        throw StateError('$id did not wait on the exact bounded task receipt');
      }
      final result = jsonDecode(call.tool!.result!) as Map;
      final tasks = result['tasks'];
      if (result['timedOut'] != false || tasks is! List || tasks.length != 1) {
        throw StateError('$id returned no single terminal task view: $result');
      }
      final task = tasks.single as Map;
      if (task['taskId'] != 'task:${parent.callId}' ||
          task['toolId'] != parent.name ||
          task['status'] != 'succeeded' ||
          task['cancelRequested'] != false) {
        throw StateError('$id accepted a nonterminal or unrelated task: $task');
      }
      observations.add(<String, Object?>{
        'callId': id,
        'taskId': task['taskId'],
        'toolId': task['toolId'],
        'status': task['status'],
      });
    }
    return observations;
  }

  Map<String, dynamic> _arguments(TimelineItemObservation item) =>
      (jsonDecode(item.tool!.arguments) as Map).cast<String, dynamic>();

  void _requireTarget(TimelineItemObservation item, String name) {
    final args = _arguments(item);
    if (args.length != 1 || args['name'] != name) {
      throw StateError(
        '${item.tool!.callId} is not an exact main-document view',
      );
    }
  }

  void _requireList(String callId, List<String> names) {
    final call = _call(callId, 'skills_list', 'succeeded');
    final args = _arguments(call);
    final tool = call.tool!;
    final raw = tool.result!;
    final notice =
        'Task task:${tool.callId} for tool ${tool.name} finished: Succeeded.';
    final payload = raw.startsWith(notice) ? raw.substring(notice.length) : raw;
    final result = jsonDecode(payload) as Map;
    final skills = result['skills'];
    if (args.length != 1 ||
        args['category'] != _dynamicPrompt ||
        result['success'] != true ||
        result['count'] != names.length ||
        result['truncated'] != false ||
        skills is! List ||
        jsonEncode([for (final skill in skills) (skill as Map)['name']]) !=
            jsonEncode(names) ||
        skills.any(
          (skill) =>
              skill['description'] != 'Synthetic same-Turn discovery skill.',
        )) {
      throw StateError(
        '$callId did not return the complete expected catalog: $result',
      );
    }
  }

  void _requireWrite(String callId, String name, String mode) {
    final call = _call(callId, 'write_file', 'succeeded');
    final args = _arguments(call);
    final content = args['content'];
    if (args['path'] != '.agents/skills/$name/SKILL.md' ||
        args['mode'] != mode ||
        content is! String ||
        !content.contains('name: $name\n') ||
        (mode == 'overwrite' &&
            !content.contains('disable-model-invocation: not-a-boolean'))) {
      throw StateError(
        '$callId did not persist the expected synthetic document',
      );
    }
  }

  /// Opens exactly this canonical tool's real detail and reads its scoped
  /// EditableText descendant. A global body marker, an old load or the final
  /// model answer cannot satisfy this check. ToolProbe reads the framework's
  /// public expansion controller; a previously open row is never toggled shut.
  Future<void> _captureDetail(
    TimelineItemObservation call,
    String label, {
    TimelineItemObservation? skill,
  }) async {
    // Optional waits can take this activity past the lazy-list threshold. Find
    // the group's own scrollable first, without requiring the target member to
    // be mounted before a real scroll can reveal it.
    final group = journey
        ._timeline(await journey.snapshot())
        .presentationFor(call.id);
    await journey._expandTimelineGroup(group);
    await journey._scrollHeaderIntoView(
      find.byValueKey('timeline-activity-summary-${group.id}'),
      label,
    );
    final header = skill == null
        ? find.descendant(
            of: find.byValueKey('timeline-tool-details:${call.id}'),
            matching: find.byType('TimelineActivityRow'),
            firstMatchOnly: true,
          )
        : find.byValueKey('timeline-skill-activation-${skill.id}');
    final tile = skill == null
        ? find.byValueKey('timeline-tool-details:${call.id}')
        : find.ancestor(
            of: header,
            matching: find.byType('ExpansionTile'),
            firstMatchOnly: true,
          );
    await journey.driver.scrollUntilVisible(
      find.descendant(
        of: find.byValueKey('timeline-row-${group.id}'),
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      header,
      dyScroll: -80,
      timeout: const Duration(seconds: 20),
    );
    await journey._scrollHeaderIntoView(header, label);
    final before = await journey.driver.sendCommand(ToolProbe(tile, 'observe'));
    final sample = (before['samples'] as List).last as Map;
    if (sample['expanded'] is! bool) {
      throw StateError('$label has no real expansion state');
    }
    if (sample['expanded'] != true) {
      await journey._tapHeader(header, label);
    }
    final rawResult = call.tool!.result;
    final String rendered;
    if (call.status == 'failed' && (rawResult == null || rawResult.isEmpty)) {
      rendered = await _failureText(tile, _arguments(call)['name'] as String);
    } else {
      rendered = (() {
        try {
          return const JsonEncoder.withIndent('  ')
              .convert(jsonDecode(rawResult!));
        } on FormatException {
          return rawResult!;
        }
      })();
    }
    if (call.status == 'failed' &&
        (!rendered.contains(_arguments(call)['name'] as String) ||
            rendered.contains(_dynamicBodyMarker))) {
      throw StateError('$label rendered an unrelated or stale error');
    }
    final resultFinder = find.descendant(
      of: tile,
      matching: find.text(rendered),
    );
    await journey.driver.waitFor(
      resultFinder,
      timeout: const Duration(seconds: 20),
    );
    if (await journey.driver.getText(resultFinder) != rendered) {
      throw StateError(
        '$label UI output does not match its canonical tool result',
      );
    }
    // Use the actual activity viewport, not a guessed screen coordinate, to
    // bring this result into the screenshot after expanding the tool header.
    await journey.driver.scrollUntilVisible(
      find.ancestor(
        of: header,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      resultFinder,
      dyScroll: -80,
      timeout: const Duration(seconds: 20),
    );
    await journey._parkPointerForCleanCapture(label);
    final current = await journey.snapshot();
    final currentCall = journey._timeline(current).item(call.id);
    final after = await journey.driver.sendCommand(ToolProbe(tile, 'observe'));
    if (journey._turnInputId(current) != inputId ||
        turnId(current) != turn ||
        currentCall?.tool?.callId != call.tool!.callId ||
        currentCall?.tool?.result != rawResult ||
        (after['samples'] as List).last['expanded'] != true) {
      throw StateError('$label changed identity or expansion before capture');
    }
    await journey.capture(
      label,
      evidence: <String, Object?>{
        'scenario': 'skill-activity',
        'phase': 'dynamic',
        'threadId': timeline.threadId,
        'turnId': turn,
        'inputId': inputId,
        'itemId': call.id,
        'callId': call.tool!.callId,
        'toolName': call.tool!.name,
        'status': call.status,
        'arguments': _arguments(call),
        'result': _sanitizedResult(rendered),
        if (call.status == 'failed')
          'failure': rendered.replaceAll(journey.project, '<project>'),
        'expanded': true,
        'uiMatchesCanonicalResult': true,
        'activeSkills': journey.activeSkills(current),
      },
    );
    await journey._tapHeader(header, '${label}_collapse');
  }

  /// Failure-only rows have no result EditableText. Their real typed failure is
  /// rendered as an ordinary Text in this exact tile, separate from the
  /// SelectableText that displays arguments. Wait for that actual error child,
  /// not for an assumed expansion duration or a global matching string.
  Future<String> _failureText(SerializableFinder tile, String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final detail = await journey.driver.sendCommand(
        ToolProbe(tile, 'readText'),
      );
      final texts = (detail['samples'] as List).single['texts'] as List;
      final errors = texts
          .whereType<String>()
          .where((text) => text.contains(name))
          .toList();
      if (errors.length == 1) return errors.single;
      if (errors.length > 1) {
        throw StateError('ambiguous failure text for $name: $texts');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      'the expanded tool never rendered its typed failure for $name',
    );
  }

  /// Minimal synthetic evidence only: no configuration, filesystem locator,
  /// provider endpoint, VM URL or unrelated historical input is published.
  Object _sanitizedResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['skills'] is List) {
        return <String, Object?>{
          for (final key in const ['success', 'count', 'truncated', 'skills'])
            key: decoded[key],
        };
      }
    } on FormatException {
      // Views use readable skill text, failures use the real tool error.
    }
    return <String, Object?>{
      'mentionsViewedSkill': raw.contains(_dynamicViewedName),
      'containsActualBody': raw.contains(_dynamicBodyMarker),
    };
  }
}
