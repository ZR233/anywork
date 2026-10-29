import 'dart:convert';

import '../../models/thread_activity_models.dart';
import '../../models/thread_wait_models.dart';
import '../../observation/latest_value.dart';
import '../domain/activity_content.dart';

const activityTextFrameBytes = 64 * 1024;
const activityFrameBytes = 256 * 1024;

/// Single writer for current activity. Its byte budget is independent of resource permits.
/// Begin and Text return only after staging accepts the frame; this is the point at which
/// the feed owner may mark those frames ready. Commit is prepared and published separately
/// so the feed owner can first obtain presentation acceptance for a same-frame completion.
final class ActivityContentOwner {
  ActivityContentOwner({required this.maxContentBytes}) {
    if (maxContentBytes <= 0)
      throw ArgumentError.value(maxContentBytes, 'maxContentBytes');
  }
  final int maxContentBytes;
  final LatestValue<CurrentActivity?> _source = LatestValue(null);
  ValueObservation<CurrentActivity?> get source => _source;
  CurrentActivity? get current => _source.value;
  _Stage? _stage;
  bool get hasStaging => _stage != null;

  /// Discard only in-flight content; already published current state remains intact.
  void cancelStaging() {
    _stage = null;
  }

  /// Domain reset clears both staging and the committed activity.
  void reset() {
    _stage = null;
    _source.publish(null);
  }

  /// Accept one Begin or Text. Any invalid frame discards staging and requests a snapshot.
  void accept(ActivityContentFrame frame) {
    try {
      switch (frame) {
        case ActivityBegin():
          _begin(frame);
        case ActivityText():
          _text(frame);
        case ActivityCommit():
          throw ArgumentError('Use prepareCommit for a commit frame');
      }
    } on ActivitySnapshotRequired {
      _stage = null;
      rethrow;
    }
  }

  void _begin(ActivityBegin frame) {
    if (_stage != null ||
        frame.generation.isEmpty ||
        frame.revision < 0 ||
        frame.totalBytes < 0) {
      _fail(
        ActivityRecoveryReason.invalidFrame,
        'invalid or overlapping begin',
      );
    }
    final previous = current;
    if (previous != null &&
        previous.generation == frame.generation &&
        frame.revision < previous.revision) {
      _fail(ActivityRecoveryReason.continuity, 'revision did not advance');
    }
    if (frame.baseRevision != null &&
        (previous == null ||
            previous.generation != frame.generation ||
            previous.revision != frame.baseRevision ||
            frame.revision <= frame.baseRevision!)) {
      _fail(
        ActivityRecoveryReason.continuity,
        'generation or base revision mismatch',
      );
    }
    final expected = <ActivityRegion, int>{};
    void add(ActivityRegion region, int length) {
      if (region.id.isEmpty || length < 0 || expected.containsKey(region)) {
        _fail(
          ActivityRecoveryReason.invalidFrame,
          'invalid or duplicate region',
        );
      }
      expected[region] = length;
    }

    for (final p in frame.reasoning) {
      add(ActivityRegion(ActivityRegionKind.reasoning, p.itemId), p.totalBytes);
    }
    for (final p in frame.response) {
      add(ActivityRegion(ActivityRegionKind.response, p.itemId), p.totalBytes);
    }
    final toolIds = <String>{};
    for (final t in frame.tools) {
      if (t.callId.isEmpty || !toolIds.add(t.callId))
        _fail(ActivityRecoveryReason.invalidFrame, 'invalid or duplicate tool');
      if (t.argumentsBytes != null)
        add(
          ActivityRegion(ActivityRegionKind.toolArguments, t.callId),
          t.argumentsBytes!,
        );
      if (t.outputBytes == null && t.outputParts.isNotEmpty) {
        _fail(ActivityRecoveryReason.invalidFrame, 'parts without output fact');
      }
      var outputTotal = 0;
      for (final part in t.outputParts) {
        if (part.partId.isEmpty || part.totalBytes < 0) {
          _fail(ActivityRecoveryReason.invalidFrame, 'invalid output part');
        }
        add(
          ActivityRegion.toolOutput(callId: t.callId, partId: part.partId),
          part.totalBytes,
        );
        outputTotal += part.totalBytes;
      }
      if (t.outputBytes != null && t.outputBytes != outputTotal) {
        _fail(
          ActivityRecoveryReason.lengthMismatch,
          'tool output total mismatch',
        );
      }
    }
    if (expected.values.fold<int>(0, (a, b) => a + b) != frame.totalBytes) {
      _fail(ActivityRecoveryReason.lengthMismatch, 'metadata total mismatch');
    }
    final metadataBytes = _metadataCost(frame);
    if (metadataBytes > activityFrameBytes ||
        metadataBytes + frame.totalBytes > maxContentBytes) {
      _fail(
        ActivityRecoveryReason.budgetExceeded,
        'metadata or content exceeds budget',
      );
    }
    final values = <ActivityRegion, String>{};
    if (frame.baseRevision != null) {
      for (final p in previous!.reasoning) {
        values[ActivityRegion(ActivityRegionKind.reasoning, p.itemId)] = p.text;
      }
      for (final p in previous.response) {
        values[ActivityRegion(ActivityRegionKind.response, p.itemId)] = p.text;
      }
      for (final t in previous.tools) {
        if (t.arguments != null)
          values[ActivityRegion(ActivityRegionKind.toolArguments, t.callId)] =
              t.arguments!;
        for (final part
            in t.outputParts ?? const <ThreadActivityToolOutputPart>[]) {
          values[ActivityRegion.toolOutput(
                callId: t.callId,
                partId: part.partId,
              )] =
              part.text;
        }
      }
    }
    final stage = _Stage(frame, expected, values, metadataBytes);
    _checkBudget(stage);
    _stage = stage;
  }

  void _text(ActivityText frame) {
    final stage = _matching(frame);
    if (stage.prepared)
      _fail(ActivityRecoveryReason.invalidFrame, 'commit already prepared');
    var textBytes = 0;
    var frameBytes = 64 + _bytes(frame.generation);
    for (final op in frame.operations) {
      frameBytes += 64 + _bytes(op.region.id) + _bytes(op.region.partId ?? '');
      final text = switch (op) {
        ActivityAppend(:final text) || ActivityReplace(:final text) => text,
        ActivityRemove() => '',
      };
      final size = _bytes(text);
      textBytes += size;
      frameBytes += _bytes(jsonEncode(text));
    }
    if (textBytes > activityTextFrameBytes || frameBytes > activityFrameBytes)
      _fail(ActivityRecoveryReason.budgetExceeded, 'text frame exceeds budget');
    for (final op in frame.operations) {
      switch (op) {
        case ActivityAppend(:final region, :final text):
          if (!stage.expected.containsKey(region))
            _fail(
              ActivityRecoveryReason.invalidFrame,
              'append to unknown region',
            );
          final size = _bytes(text);
          stage.setLength(region, (stage.lengths[region] ?? 0) + size);
          _checkBudget(stage);
          stage.values[region] = (stage.values[region] ?? '') + text;
        case ActivityReplace(:final region, :final text):
          if (!stage.expected.containsKey(region))
            _fail(
              ActivityRecoveryReason.invalidFrame,
              'replace of unknown region',
            );
          stage.setLength(region, _bytes(text));
          _checkBudget(stage);
          stage.values[region] = text;
        case ActivityRemove(:final region):
          if (!stage.values.containsKey(region) ||
              stage.expected.containsKey(region))
            _fail(ActivityRecoveryReason.invalidFrame, 'invalid remove');
          stage.values.remove(region);
          stage.removeLength(region);
      }
    }
  }

  /// Does not publish: discard or publish this exact token after the other owner accepts.
  PreparedActivityCommit prepareCommit(ActivityCommit frame) {
    try {
      final stage = _matching(frame);
      if (stage.prepared)
        _fail(ActivityRecoveryReason.invalidFrame, 'commit already prepared');
      if (stage.values.length != stage.expected.length)
        _fail(ActivityRecoveryReason.lengthMismatch, 'region set mismatch');
      for (final entry in stage.expected.entries) {
        final value = stage.values[entry.key];
        if (value == null || _bytes(value) != entry.value)
          _fail(
            ActivityRecoveryReason.lengthMismatch,
            'region length mismatch',
          );
      }
      final b = stage.begin;
      String value(ActivityRegionKind kind, String id) =>
          stage.values[ActivityRegion(kind, id)]!;
      final result = CurrentActivity(
        generation: b.generation,
        revision: b.revision,
        activity: b.activity,
        reasoning: [
          for (final p in b.reasoning)
            ThreadActivityContentPart(
              itemId: p.itemId,
              complete: p.complete,
              text: value(ActivityRegionKind.reasoning, p.itemId),
            ),
        ],
        response: [
          for (final p in b.response)
            ThreadActivityContentPart(
              itemId: p.itemId,
              complete: p.complete,
              text: value(ActivityRegionKind.response, p.itemId),
            ),
        ],
        tools: [
          for (final t in b.tools)
            ThreadActivityToolDetail(
              callId: t.callId,
              taskId: t.taskId,
              name: t.name,
              state: t.state,
              startedAt: t.startedAt,
              ordinal: t.sourceOrder,
              wait: t.wait,
              arguments: t.argumentsBytes == null
                  ? null
                  : value(ActivityRegionKind.toolArguments, t.callId),
              outputParts: t.outputBytes == null
                  ? null
                  : [
                      for (final part in t.outputParts)
                        ThreadActivityToolOutputPart(
                          partId: part.partId,
                          text:
                              stage.values[ActivityRegion.toolOutput(
                                callId: t.callId,
                                partId: part.partId,
                              )]!,
                        ),
                    ],
            ),
        ],
      );
      final previous = current;
      final replay =
          b.baseRevision == null &&
          previous != null &&
          previous.generation == b.generation &&
          previous.revision == b.revision;
      if (replay && !_sameActivity(previous, result)) {
        _fail(
          ActivityRecoveryReason.continuity,
          'snapshot revision content mismatch',
        );
      }
      stage.prepared = true;
      return PreparedActivityCommit._(stage, replay ? previous : result);
    } on ActivitySnapshotRequired {
      _stage = null;
      rethrow;
    }
  }

  void publish(PreparedActivityCommit prepared) {
    if (!identical(_stage, prepared._stage))
      throw StateError('Activity commit is no longer current');
    _stage = null;
    if (!identical(_source.value, prepared.value))
      _source.publish(prepared.value);
  }

  _Stage _matching(ActivityContentFrame frame) {
    final stage = _stage;
    if (stage == null ||
        stage.begin.generation != frame.generation ||
        stage.begin.revision != frame.revision)
      _fail(
        ActivityRecoveryReason.continuity,
        'frame does not match staged begin',
      );
    return stage;
  }

  void _checkBudget(_Stage stage) {
    if (stage.chargedBytes > maxContentBytes)
      _fail(ActivityRecoveryReason.budgetExceeded, 'staging exceeds budget');
  }
}

bool _sameActivity(CurrentActivity a, CurrentActivity b) {
  bool parts(
    List<ThreadActivityContentPart> left,
    List<ThreadActivityContentPart> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      final x = left[i], y = right[i];
      if (x.itemId != y.itemId ||
          x.revision != y.revision ||
          x.complete != y.complete ||
          x.text != y.text)
        return false;
    }
    return true;
  }

  bool outputs(
    List<ThreadActivityToolOutputPart>? left,
    List<ThreadActivityToolOutputPart>? right,
  ) {
    if (left == null || right == null) return left == null && right == null;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].partId != right[i].partId || left[i].text != right[i].text)
        return false;
    }
    return true;
  }

  if (a.activity != b.activity ||
      !parts(a.reasoning, b.reasoning) ||
      !parts(a.response, b.response) ||
      a.tools.length != b.tools.length)
    return false;
  for (var i = 0; i < a.tools.length; i++) {
    final x = a.tools[i], y = b.tools[i];
    if (x.callId != y.callId ||
        x.taskId != y.taskId ||
        x.name != y.name ||
        x.state != y.state ||
        x.arguments != y.arguments ||
        x.ordinal != y.ordinal ||
        x.startedAt != y.startedAt ||
        x.wait != y.wait ||
        !outputs(x.outputParts, y.outputParts))
      return false;
  }
  return true;
}

final class PreparedActivityCommit {
  PreparedActivityCommit._(this._stage, this.value);
  final _Stage _stage;
  final CurrentActivity value;
}

final class _Stage {
  _Stage(this.begin, this.expected, this.values, int metadataBytes)
    : chargedBytes = metadataBytes {
    for (final entry in values.entries) {
      setLength(entry.key, _bytes(entry.value));
    }
  }
  final ActivityBegin begin;
  final Map<ActivityRegion, int> expected;
  final Map<ActivityRegion, String> values;
  final Map<ActivityRegion, int> lengths = {};
  int chargedBytes;
  bool prepared = false;

  void setLength(ActivityRegion region, int length) {
    final previous = lengths[region];
    chargedBytes += length - (previous ?? 0);
    if (previous == null)
      chargedBytes += _bytes(region.id) + _bytes(region.partId ?? '') + 64;
    lengths[region] = length;
  }

  void removeLength(ActivityRegion region) {
    chargedBytes -=
        lengths.remove(region)! +
        _bytes(region.id) +
        _bytes(region.partId ?? '') +
        64;
  }
}

int _bytes(String value) => utf8.encode(value).length;
Never _fail(ActivityRecoveryReason reason, String message) =>
    throw ActivitySnapshotRequired(reason, message);

int _waitCost(ThreadWaitPresentationView? wait) {
  if (wait == null) return 0;
  var n = 64;
  final intent = wait.intent;
  if (intent is ThreadWaitEventsIntentView) {
    for (final target in intent.targets) {
      n +=
          64 +
          _bytes(target.taskId) +
          _bytes(target.toolName ?? '') +
          _bytes(target.summary ?? '');
    }
  }
  return n;
}

// Conservative structural accounting, including nested activity and wait metadata.
int _metadataCost(ActivityBegin b) {
  var n = 128 + _bytes(b.generation);
  for (final p in [...b.reasoning, ...b.response]) {
    n += 64 + _bytes(p.itemId);
  }
  for (final t in b.tools) {
    n += 128 + _bytes(t.callId) + _bytes(t.name) + _bytes(t.taskId ?? '');
    for (final part in t.outputParts) {
      n += 64 + _bytes(part.partId);
    }
    n += _waitCost(t.wait);
  }
  final a = b.activity;
  if (a != null) {
    n +=
        256 +
        _bytes(a.threadId) +
        _bytes(a.identity) +
        _bytes(a.turnId ?? '') +
        _bytes(a.executionId ?? '') +
        _bytes(a.inputId ?? '') +
        _bytes(a.attemptId ?? '') +
        _bytes(a.summary) +
        _bytes(a.thinkingSummary ?? '');
    for (final t in a.tools.active) {
      n +=
          128 +
          _bytes(t.callId) +
          _bytes(t.taskId ?? '') +
          _bytes(t.name) +
          _bytes(t.summary) +
          _waitCost(t.wait);
    }
    final latest = a.tools.latestStarted;
    if (latest != null)
      n +=
          128 +
          _bytes(latest.callId) +
          _bytes(latest.taskId ?? '') +
          _bytes(latest.name) +
          _bytes(latest.summary) +
          _waitCost(latest.wait);
  }
  return n;
}
