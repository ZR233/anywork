import 'package:anywork_client/src/conversation/data/activity_content_owner.dart';
import 'package:anywork_client/src/conversation/domain/activity_content.dart';
import 'package:anywork_client/src/models/thread_activity_models.dart';
import 'package:anywork_client/src/models/conversation_activity_models.dart';
import 'package:test/test.dart';

const region = ActivityRegion(ActivityRegionKind.response, 'item');
ActivityBegin begin({int revision = 1, int? base, int length = 3}) =>
    ActivityBegin(
      generation: 'gen',
      revision: revision,
      baseRevision: base,
      activity: null,
      reasoning: const [],
      response: [
        ActivityPartMetadata(
          itemId: 'item',
          complete: false,
          totalBytes: length,
        ),
      ],
      tools: const [],
      totalBytes: length,
    );
ActivityText text(int revision, ActivityTextOperation op) =>
    ActivityText(generation: 'gen', revision: revision, operations: [op]);
ActivityCommit commit(int revision) =>
    ActivityCommit(generation: 'gen', revision: revision);
void initial(ActivityContentOwner owner) {
  owner.accept(begin());
  owner.accept(text(1, const ActivityReplace(region, 'old')));
  owner.publish(owner.prepareCommit(commit(1)));
}

Matcher failure(ActivityRecoveryReason reason) => throwsA(
  isA<ActivitySnapshotRequired>().having((e) => e.reason, 'reason', reason),
);

void main() {
  test('multiple staged frames are accepted without publication until prepared commit is published', () {
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    final observed = <CurrentActivity?>[];
    owner.source.watch(observed.add);
    owner.accept(begin(length: 6));
    owner.accept(text(1, const ActivityReplace(region, 'a')));
    owner.accept(text(1, const ActivityAppend(region, 'b')));
    owner.accept(text(1, const ActivityAppend(region, 'c')));
    owner.accept(text(1, const ActivityAppend(region, 'dé')));
    expect(owner.current, isNull);
    expect(observed, isEmpty);
    final prepared = owner.prepareCommit(commit(1));
    expect(owner.current, isNull);
    expect(prepared.value.response.single.text, 'abcdé');
    owner.publish(prepared);
    expect(owner.current!.response.single.text, 'abcdé');
    expect(observed, hasLength(1));
  });

  test('wrong base and wrong generation demand snapshot without changing committed state', () {
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    initial(owner);
    final old = owner.current;
    expect(
      () => owner.accept(begin(revision: 2, base: 0)),
      failure(ActivityRecoveryReason.continuity),
    );
    expect(owner.current, same(old));
    owner.accept(begin(revision: 2, base: 1));
    expect(
      () => owner.accept(
        ActivityText(generation: 'other', revision: 2, operations: const []),
      ),
      failure(ActivityRecoveryReason.continuity),
    );
    expect(owner.hasStaging, isFalse);
    expect(owner.current, same(old));
  });

  test('incorrect final byte length rejects commit without publishing', () {
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    initial(owner);
    final old = owner.current;
    owner.accept(begin(revision: 2, base: 1, length: 4));
    owner.accept(text(2, const ActivityAppend(region, 'é')));
    expect(
      () => owner.prepareCommit(commit(2)),
      failure(ActivityRecoveryReason.lengthMismatch),
    );
    expect(owner.current, same(old));
    expect(owner.hasStaging, isFalse);
  });

  test('budget rejection preserves committed value and clears staging', () {
    final owner = ActivityContentOwner(maxContentBytes: 512);
    initial(owner);
    final old = owner.current;
    expect(
      () => owner.accept(begin(revision: 2, base: 1, length: 500)),
      failure(ActivityRecoveryReason.budgetExceeded),
    );
    expect(owner.current, same(old));
    expect(owner.hasStaging, isFalse);
  });

  test('cancel invalidates prepared commit and reset clears current', () {
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    initial(owner);
    owner.accept(begin(revision: 2, base: 1));
    final prepared = owner.prepareCommit(commit(2));
    owner.cancelStaging();
    expect(() => owner.publish(prepared), throwsStateError);
    expect(owner.current!.response.single.text, 'old');
    owner.reset();
    expect(owner.current, isNull);
    expect(owner.hasStaging, isFalse);
  });

  test('text frame byte cap rejects without changing committed value', () {
    final owner = ActivityContentOwner(maxContentBytes: 200000);
    initial(owner);
    owner.accept(begin(revision: 2, base: 1, length: 70000));
    final old = owner.current;
    expect(
      () => owner.accept(text(2, ActivityReplace(region, 'x' * 65537))),
      failure(ActivityRecoveryReason.budgetExceeded),
    );
    expect(owner.current, same(old));
  });

  test('same generation equal snapshot is idempotent but lower or delta replay fails', () {
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    initial(owner);
    final old = owner.current;
    expect(
      () => owner.accept(begin(revision: 0)),
      failure(ActivityRecoveryReason.continuity),
    );
    expect(
      () => owner.accept(begin(revision: 1, base: 1)),
      failure(ActivityRecoveryReason.continuity),
    );
    final notifications = <CurrentActivity?>[];
    owner.source.watch(notifications.add);
    owner.accept(begin(revision: 1));
    owner.accept(text(1, const ActivityReplace(region, 'old')));
    owner.publish(owner.prepareCommit(commit(1)));
    expect(owner.current, same(old));
    expect(notifications, isEmpty);
    owner.accept(begin(revision: 1));
    owner.accept(text(1, const ActivityReplace(region, 'bad')));
    expect(
      () => owner.prepareCommit(commit(1)),
      failure(ActivityRecoveryReason.continuity),
    );
    expect(owner.current, same(old));
    final other = ActivityBegin(
      generation: 'new',
      revision: 0,
      baseRevision: 1,
      activity: null,
      reasoning: const [],
      response: const [],
      tools: const [],
      totalBytes: 0,
    );
    expect(
      () => owner.accept(other),
      failure(ActivityRecoveryReason.continuity),
    );
    owner.accept(
      ActivityBegin(
        generation: 'new',
        revision: 0,
        baseRevision: null,
        activity: null,
        reasoning: const [],
        response: const [],
        tools: const [],
        totalBytes: 0,
      ),
    );
    owner.publish(
      owner.prepareCommit(const ActivityCommit(generation: 'new', revision: 0)),
    );
    expect(owner.current!.generation, 'new');
    expect(owner.current!.revision, 0);
  });

  test('replace and append charge only the current UTF-8 byte difference', () {
    final owner = ActivityContentOwner(maxContentBytes: 300);
    owner.accept(begin(length: 25));
    owner.accept(text(1, ActivityReplace(region, 'x' * 25)));
    owner.publish(owner.prepareCommit(commit(1)));
    owner.accept(begin(revision: 2, base: 1, length: 20));
    owner.accept(text(2, const ActivityReplace(region, 'é')));
    owner.accept(text(2, ActivityAppend(region, 'x' * 18)));
    owner.publish(owner.prepareCommit(commit(2)));
    final old = owner.current;
    expect(old!.response.single.text, 'é${'x' * 18}');
    owner.accept(begin(revision: 3, base: 2, length: 20));
    expect(
      () => owner.accept(text(3, ActivityAppend(region, 'x' * 20))),
      failure(ActivityRecoveryReason.budgetExceeded),
    );
    expect(owner.current, same(old));
  });

  test('removing an old region releases its staging charge', () {
    final owner = ActivityContentOwner(maxContentBytes: 340);
    owner.accept(begin(length: 30));
    owner.accept(text(1, ActivityReplace(region, 'x' * 30)));
    owner.publish(owner.prepareCommit(commit(1)));
    const replacement = ActivityRegion(ActivityRegionKind.response, 'new');
    owner.accept(
      ActivityBegin(
        generation: 'gen',
        revision: 2,
        baseRevision: 1,
        activity: null,
        reasoning: const [],
        response: const [
          ActivityPartMetadata(itemId: 'new', complete: true, totalBytes: 30),
        ],
        tools: const [],
        totalBytes: 30,
      ),
    );
    owner.accept(text(2, const ActivityRemove(region)));
    owner.accept(text(2, ActivityReplace(replacement, 'y' * 30)));
    owner.publish(owner.prepareCommit(commit(2)));
    expect(owner.current!.response.single.text, 'y' * 30);
  });

  test('frame payload lists are copied and unmodifiable', () {
    final operations = <ActivityTextOperation>[
      const ActivityReplace(region, 'a'),
    ];
    final frame = ActivityText(
      generation: 'gen',
      revision: 1,
      operations: operations,
    );
    operations.clear();
    expect(frame.operations, hasLength(1));
    expect(() => frame.operations.clear(), throwsUnsupportedError);
    final parts = <ActivityPartMetadata>[
      const ActivityPartMetadata(
        itemId: 'item',
        complete: false,
        totalBytes: 1,
      ),
    ];
    final start = ActivityBegin(
      generation: 'gen',
      revision: 1,
      baseRevision: null,
      activity: null,
      reasoning: const [],
      response: parts,
      tools: const [],
      totalBytes: 1,
    );
    parts.clear();
    expect(start.response, hasLength(1));
    expect(() => start.response.clear(), throwsUnsupportedError);
  });

  test(
    'segmented output stays ordered and isolated across snapshot and delta',
    () {
      final owner = ActivityContentOwner(maxContentBytes: 8192);
      ActivityToolMetadata tool(
        String call,
        int? bytes,
        List<ActivityToolOutputMetadata> parts,
      ) => ActivityToolMetadata(
        callId: call,
        name: 'exec',
        state: ThreadActivityToolState.running,
        outputBytes: bytes,
        outputParts: parts,
      );
      ActivityBegin frame(
        int rev,
        int? base,
        List<ActivityToolMetadata> tools,
        int bytes,
      ) => ActivityBegin(
        generation: 'gen',
        revision: rev,
        baseRevision: base,
        activity: null,
        reasoning: const [],
        response: const [],
        tools: tools,
        totalBytes: bytes,
      );
      const a = ActivityRegion.toolOutput(callId: 'a', partId: 'same');
      const b = ActivityRegion.toolOutput(callId: 'a', partId: 'second');
      const c = ActivityRegion.toolOutput(callId: 'b', partId: 'same');
      const empty = ActivityRegion.toolOutput(callId: 'a', partId: 'empty');
      owner.accept(
        frame(1, null, [
          tool('a', 5, const [
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 3),
            ActivityToolOutputMetadata(partId: 'second', totalBytes: 2),
            ActivityToolOutputMetadata(partId: 'empty', totalBytes: 0),
          ]),
          tool('b', 1, const [
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 1),
          ]),
          tool('unknown', null, const []),
          tool('observed', 0, const []),
        ], 6),
      );
      owner.accept(text(1, const ActivityReplace(a, 'a')));
      owner.accept(text(1, const ActivityAppend(a, 'bc')));
      owner.accept(text(1, const ActivityReplace(b, '中')));
      owner.accept(text(1, const ActivityReplace(c, 'z')));
      owner.accept(text(1, const ActivityReplace(empty, '')));
      expect(
        () => owner.prepareCommit(commit(1)),
        failure(ActivityRecoveryReason.lengthMismatch),
      );
      owner.accept(
        frame(1, null, [
          tool('a', 6, const [
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 3),
            ActivityToolOutputMetadata(partId: 'second', totalBytes: 3),
            ActivityToolOutputMetadata(partId: 'empty', totalBytes: 0),
          ]),
          tool('b', 1, const [
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 1),
          ]),
          tool('unknown', null, const []),
          tool('observed', 0, const []),
        ], 7),
      );
      owner.accept(text(1, const ActivityReplace(a, 'abc')));
      owner.accept(text(1, const ActivityReplace(b, '中')));
      owner.accept(text(1, const ActivityReplace(c, 'z')));
      owner.accept(text(1, const ActivityReplace(empty, '')));
      final prepared = owner.prepareCommit(commit(1));
      expect(owner.current, isNull);
      owner.publish(prepared);
      expect(
        owner.current!.tools[0].outputParts!.map((p) => (p.partId, p.text)),
        [('same', 'abc'), ('second', '中'), ('empty', '')],
      );
      expect(owner.current!.tools[1].outputParts!.single.text, 'z');
      expect(owner.current!.tools[2].outputParts, isNull);
      expect(owner.current!.tools[3].outputParts, isEmpty);
      owner.accept(
        frame(2, 1, [
          tool('a', 5, const [
            ActivityToolOutputMetadata(partId: 'second', totalBytes: 1),
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 4),
          ]),
          tool('b', 1, const [
            ActivityToolOutputMetadata(partId: 'same', totalBytes: 1),
          ]),
        ], 6),
      );
      owner.accept(text(2, const ActivityRemove(empty)));
      owner.accept(text(2, const ActivityReplace(b, 'q')));
      owner.accept(text(2, const ActivityAppend(a, '!')));
      owner.publish(owner.prepareCommit(commit(2)));
      expect(
        owner.current!.tools[0].outputParts!.map((p) => (p.partId, p.text)),
        [('second', 'q'), ('same', 'abc!')],
      );
      expect(owner.current!.tools[1].outputParts!.single.text, 'z');
      expect(
        () => owner.current!.tools[0].outputParts!.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'invalid output metadata requests snapshot and preserves previous value',
    () {
      final owner = ActivityContentOwner(maxContentBytes: 8192);
      initial(owner);
      final previous = owner.current;
      ActivityBegin withParts(
        int? total,
        List<ActivityToolOutputMetadata> parts,
      ) => ActivityBegin(
        generation: 'gen',
        revision: 2,
        baseRevision: 1,
        activity: null,
        reasoning: const [],
        response: const [],
        tools: [
          ActivityToolMetadata(
            callId: 'call',
            name: 'exec',
            state: ThreadActivityToolState.running,
            outputBytes: total,
            outputParts: parts,
          ),
        ],
        totalBytes: parts.fold(0, (n, p) => n + p.totalBytes),
      );
      expect(
        () => owner.accept(
          withParts(2, const [
            ActivityToolOutputMetadata(partId: 'x', totalBytes: 1),
            ActivityToolOutputMetadata(partId: 'x', totalBytes: 1),
          ]),
        ),
        failure(ActivityRecoveryReason.invalidFrame),
      );
      expect(
        () => owner.accept(
          withParts(2, const [
            ActivityToolOutputMetadata(partId: 'x', totalBytes: 1),
          ]),
        ),
        failure(ActivityRecoveryReason.lengthMismatch),
      );
      expect(
        () => owner.accept(
          withParts(null, const [
            ActivityToolOutputMetadata(partId: 'x', totalBytes: 1),
          ]),
        ),
        failure(ActivityRecoveryReason.invalidFrame),
      );
      expect(owner.current, same(previous));
      owner.accept(begin(revision: 2, base: 1));
      owner.publish(owner.prepareCommit(commit(2)));
      expect(owner.current!.response.single.text, 'old');
    },
  );

  test('pre-Turn activity preserves absent turn and execution identity', () {
    final owner = ActivityContentOwner(maxContentBytes: 8192);
    const activity = ThreadActivityView(
      threadId: 'thread',
      identity: 'opaque',
      revision: 1,
      turnId: null,
      executionId: 'execution',
      kind: ThreadActivityKind.preparing,
      summary: '',
    );
    owner.accept(
      ActivityBegin(
        generation: 'gen',
        revision: 1,
        baseRevision: null,
        activity: activity,
        reasoning: const [],
        response: const [],
        tools: const [],
        totalBytes: 0,
      ),
    );
    owner.publish(owner.prepareCommit(commit(1)));
    expect(owner.current!.activity!.turnId, isNull);
    expect(owner.current!.activity!.executionId, 'execution');
  });

  test('active tool list stays frozen after Begin and Commit', () {
    const entry = ThreadActivityToolEntry(
      callId: 'call',
      name: 'exec',
      summary: 'original',
      arguments: ThreadActivityArgumentsKind.commandLine,
      state: ThreadActivityToolState.running,
    );
    final source = [entry];
    final activity = ThreadActivityView(
      threadId: 'thread',
      identity: 'activity',
      revision: 1,
      turnId: null,
      kind: ThreadActivityKind.runningTool,
      summary: 'running',
      tools: ThreadActivityTools(count: 1, active: source),
    );
    final owner = ActivityContentOwner(maxContentBytes: 2048);
    owner.accept(
      ActivityBegin(
        generation: 'gen',
        revision: 1,
        baseRevision: null,
        activity: activity,
        reasoning: const [],
        response: const [],
        tools: const [],
        totalBytes: 0,
      ),
    );
    source.add(
      ThreadActivityToolEntry(
        callId: 'large',
        name: 'exec',
        summary: 'x' * (256 * 1024),
        arguments: ThreadActivityArgumentsKind.opaque,
        state: ThreadActivityToolState.running,
      ),
    );
    expect(owner.current, isNull);
    final prepared = owner.prepareCommit(commit(1));
    owner.publish(prepared);
    source.clear();
    final current = owner.current!;
    expect(current.activity!.tools.count, 1);
    expect(current.activity!.tools.active.single.summary, 'original');
    expect(
      () => current.activity!.tools.active.clear(),
      throwsUnsupportedError,
    );
    final projection = projectConversationActivity(current: current)!;
    expect(projection.activeToolCount, 1);
    expect(projection.activeTools.single.callId, 'call');
    expect(() => projection.activeTools.clear(), throwsUnsupportedError);
  });

  test(
    'equal-version snapshot rejects changed summary or tool output parts',
    () {
      final owner = ActivityContentOwner(maxContentBytes: 4096);
      ActivityBegin frame(String summary) => ActivityBegin(
        generation: 'gen',
        revision: 1,
        baseRevision: null,
        activity: ThreadActivityView(
          threadId: 'thread',
          identity: 'id',
          revision: 1,
          turnId: null,
          kind: ThreadActivityKind.runningTool,
          summary: summary,
        ),
        reasoning: const [],
        response: const [],
        tools: [
          ActivityToolMetadata(
            callId: 'call',
            name: 'exec',
            state: ThreadActivityToolState.running,
            outputBytes: 1,
            outputParts: const [
              ActivityToolOutputMetadata(partId: 'part', totalBytes: 1),
            ],
          ),
        ],
        totalBytes: 1,
      );
      const output = ActivityRegion.toolOutput(callId: 'call', partId: 'part');
      void stage(String summary, String body) {
        owner.accept(frame(summary));
        owner.accept(text(1, ActivityReplace(output, body)));
      }

      stage('original', 'a');
      owner.publish(owner.prepareCommit(commit(1)));
      final old = owner.current;
      stage('changed', 'a');
      expect(
        () => owner.prepareCommit(commit(1)),
        failure(ActivityRecoveryReason.continuity),
      );
      expect(owner.current, same(old));
      stage('original', 'b');
      expect(
        () => owner.prepareCommit(commit(1)),
        failure(ActivityRecoveryReason.continuity),
      );
      expect(owner.current, same(old));
      stage('original', 'a');
      owner.publish(owner.prepareCommit(commit(1)));
      expect(owner.current, same(old));
    },
  );

  test('output part identity and metadata count towards bounded admission', () {
    final owner = ActivityContentOwner(maxContentBytes: 512);
    final start = ActivityBegin(
      generation: 'gen',
      revision: 1,
      baseRevision: null,
      activity: null,
      reasoning: const [],
      response: const [],
      tools: [
        ActivityToolMetadata(
          callId: 'call',
          name: 'exec',
          state: ThreadActivityToolState.running,
          outputBytes: 0,
          outputParts: [
            ActivityToolOutputMetadata(partId: 'p' * 300, totalBytes: 0),
          ],
        ),
      ],
      totalBytes: 0,
    );
    expect(
      () => owner.accept(start),
      failure(ActivityRecoveryReason.budgetExceeded),
    );
    expect(owner.current, isNull);
    expect(owner.hasStaging, isFalse);
  });

  test('a part operation cannot be applied to a different call', () {
    final owner = ActivityContentOwner(maxContentBytes: 4096);
    owner.accept(
      ActivityBegin(
        generation: 'gen',
        revision: 1,
        baseRevision: null,
        activity: null,
        reasoning: const [],
        response: const [],
        tools: [
          ActivityToolMetadata(
            callId: 'first',
            name: 'exec',
            state: ThreadActivityToolState.running,
            outputBytes: 1,
            outputParts: const [
              ActivityToolOutputMetadata(partId: 'part', totalBytes: 1),
            ],
          ),
        ],
        totalBytes: 1,
      ),
    );
    expect(
      () => owner.accept(
        text(
          1,
          const ActivityReplace(
            ActivityRegion.toolOutput(callId: 'other', partId: 'part'),
            'x',
          ),
        ),
      ),
      failure(ActivityRecoveryReason.invalidFrame),
    );
    expect(owner.hasStaging, isFalse);
    expect(owner.current, isNull);
  });
}
