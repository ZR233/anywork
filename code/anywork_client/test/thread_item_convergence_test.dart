import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:test/test.dart';

/// 尾部 `Add` 携带权威整条预览，不保证该身份从未被页查询加载，也不保证随后补发
/// `UpdateItem`；已加载身份必须在同 revision 上原位收敛（design/26 §26.7）。
///
/// 整体省略量由**持有逐字段详情引用、已核实支配关系与预算的调用方**传入，这个 helper
/// 只做字段收敛与事实非回退，不自行猜测账目（design/26 §26.8）。
void main() {
  const createdAt = 1767225600; // 2026-01-01 UTC, Unix seconds.
  ThreadItemView text({
    required String id,
    required int revision,
    int ordinal = 6,
    String body = '正文',
    bool saved = false,
    bool terminal = false,
    int omitted = 0,
    String? turnId,
  }) => ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: turnId ?? 'turn-a',
    ordinal: ordinal,
    revision: revision,
    createdAt: createdAt,
    updatedAt: createdAt,
    bodyOmittedUnits: omitted,
    executionTerminal: terminal,
    saved: saved,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: body,
      attachments: const [],
      lifecycle: terminal
          ? const CompletedThreadContentView(createdAt)
          : const StreamingThreadContentView(),
    ),
  );

  StudioTimelineItem timelineItem(
    int revision, {
    required String id,
    String body = '正文',
    List<StudioTimelineDetailRef> details = const [],
  }) => StudioTimelineItem(
    item: text(id: id, revision: revision, body: body),
    saved: false,
    lifecycle: StudioTimelineLifecycle.streaming,
    omittedBytes: 0,
    details: details,
  );

  test('同 revision 的权威整条取更完整正文并采用调用方给定的账目', () {
    final loaded = text(id: 'stable', revision: 4, body: 'abcd', omitted: 8);
    final incoming = text(
      id: 'stable',
      revision: 4,
      body: 'abcdefgh',
      omitted: 0,
      saved: true,
      terminal: true,
      turnId: 'turn-b',
    );
    final merged = loaded.convergeWith(incoming, omittedBytes: 0)!;
    final state = merged.state as ThreadTextItemStateView;
    expect(state.text, 'abcdefgh');
    expect(merged.saved, isTrue);
    expect(merged.executionTerminal, isTrue);
    expect(merged.bodyOmittedUnits, 0, reason: '省略量来自调用方已核实的合成账目，不取两份输入的最小值');
    expect(merged.turnId, 'turn-b', reason: 'Turn 关联允许随权威事实更新');
    expect(merged.id, 'stable');
    expect(merged.ordinal, 6);
    expect(merged.revision, 4);
  });

  test('更短的同 revision 预览不回退已交付正文与事实', () {
    final loaded = text(
      id: 'stable',
      revision: 4,
      body: 'abcdefgh',
      saved: true,
      terminal: true,
    );
    final incoming = text(id: 'stable', revision: 4, body: 'abcd', omitted: 4);
    final merged = loaded.convergeWith(incoming, omittedBytes: 0)!;
    final state = merged.state as ThreadTextItemStateView;
    expect(state.text, 'abcdefgh');
    expect(merged.saved, isTrue);
    expect(merged.executionTerminal, isTrue);
    expect(merged.bodyOmittedUnits, 0, reason: '已交付正文更完整，调用方按已核账目传入 0');
  });

  test('负数省略量被拒绝：helper 不猜账目也不接受非法值', () {
    final loaded = text(id: 'stable', revision: 4);
    expect(
      () => loaded.convergeWith(
        text(id: 'stable', revision: 4, body: 'abcd'),
        omittedBytes: -1,
      ),
      throwsArgumentError,
    );
  });

  test('同 revision 却不是同一正文时不能造默默连续', () {
    final loaded = text(id: 'stable', revision: 4, body: 'abcd');
    final incoming = text(id: 'stable', revision: 4, body: '完全不同');
    expect(loaded.convergeWith(incoming, omittedBytes: 0), isNull);
  });

  test('身份或顺序不稳定、或 revision 不同都不归这里处理', () {
    final loaded = text(id: 'stable', revision: 4);
    expect(
      loaded.convergeWith(text(id: 'stable', revision: 5), omittedBytes: 0),
      isNull,
    );
    expect(
      loaded.convergeWith(
        text(id: 'stable', revision: 4, ordinal: 9),
        omittedBytes: 0,
      ),
      isNull,
      reason: 'ordinal 是稳定顺序身份，权威副本不得改写它',
    );
    expect(
      loaded.convergeWith(text(id: 'other', revision: 4), omittedBytes: 0),
      isNull,
    );
  });

  test('工具身份不同的同 revision 事实不可收敛，同身份则合并更完整参数', () {
    ThreadItemView tool({
      required String toolCallId,
      required String arguments,
      String output = '',
    }) => ThreadItemView(
      id: 'tool',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 2,
      createdAt: createdAt,
      updatedAt: createdAt,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: toolCallId,
          name: 'shell',
          arguments: arguments,
        ),
        lifecycle: RunningThreadToolView(output),
      ),
    );

    final loaded = tool(
      toolCallId: 'call-1',
      arguments: '{"cmd":',
      output: 'a',
    );
    final other = tool(toolCallId: 'call-2', arguments: '{"cmd":"ls"}');
    expect(loaded.convergeWith(other, omittedBytes: 0), isNull);

    final fuller = tool(
      toolCallId: 'call-1',
      arguments: '{"cmd":"ls"}',
      output: 'abc',
    );
    final merged = loaded.convergeWith(fuller, omittedBytes: 0)!;
    final state = merged.state as ThreadToolItemStateView;
    expect(state.invocation.arguments, '{"cmd":"ls"}');
    expect(
      (state.lifecycle as RunningThreadToolView).streamedOutput,
      'abc',
      reason: '同一调用阶段的流式正文取更完整者',
    );
  });

  test('终态工具生命周期的更高阶段不被更旧阶段覆盖', () {
    ThreadItemView tool(ThreadToolLifecycleView lifecycle) => ThreadItemView(
      id: 'tool',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 2,
      createdAt: createdAt,
      updatedAt: createdAt,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: 'call-1',
          name: 'shell',
          arguments: '{}',
        ),
        lifecycle: lifecycle,
      ),
    );

    final succeeded = tool(
      SucceededThreadToolView(
        createdAt,
        ThreadToolOutput(result: 'done', attachments: [], outputArtifacts: []),
      ),
    );
    final running = tool(const RunningThreadToolView('done'));
    final merged = succeeded.convergeWith(running, omittedBytes: 0)!;
    expect(
      (merged.state as ThreadToolItemStateView).lifecycle,
      isA<SucceededThreadToolView>(),
      reason: '同 revision 不得把工具阶段退回 running',
    );
  });

  test('开放 artifact 只按 typed opaque 值随真实工具收敛，保原字符串与顺序而不解码', () {
    ThreadItemView withArtifacts(List<OpaqueArtifactJson> artifacts) =>
        text(
          id: 'artifact-tool',
          revision: 2,
          saved: true,
          terminal: true,
        ).copyWith(
          state: ThreadToolItemStateView(
            invocation: const ThreadToolInvocationView(
              toolCallId: 'artifact-call',
              name: 'artifact-tool',
              arguments: '{}',
            ),
            lifecycle: SucceededThreadToolView(
              createdAt,
              ThreadToolOutput(
                result: 'done',
                attachments: const [],
                outputArtifacts: artifacts,
              ),
            ),
          ),
        );
    final raw = <OpaqueArtifactJson>[
      const OpaqueArtifactJson(json: ' {"link":"https://fixture.example/"} '),
      const OpaqueArtifactJson(
        json: 'deliberately-not-json-at-the-SDK-boundary',
      ),
    ];
    final loaded = withArtifacts(const []);
    final incoming = withArtifacts(raw);
    raw.clear();
    final merged = loaded.convergeWith(incoming, omittedBytes: 0);
    expect(
      merged,
      isNotNull,
      reason: 'SDK reducers carry opaque native values without a JSON interpretation policy',
    );
    expect(merged!.tool!.outputArtifacts.map((artifact) => artifact.json), [
      ' {"link":"https://fixture.example/"} ',
      'deliberately-not-json-at-the-SDK-boundary',
    ]);
  });

  test('同事实重复交付不要求同一 Dart 实例，但必须保留全部权威元数据变化', () {
    final loaded = text(id: 'stable', revision: 4, body: 'abcd');
    final sameContent = ThreadItemView(
      id: loaded.id,
      threadId: loaded.threadId,
      turnId: 'turn-b',
      ordinal: loaded.ordinal,
      revision: loaded.revision,
      createdAt: loaded.createdAt,
      updatedAt: 1798761600,
      contextDisposition: ThreadContextDisposition.rolledBack,
      bodyOmittedUnits: loaded.bodyOmittedUnits,
      executionTerminal: loaded.executionTerminal,
      saved: loaded.saved,
      state: loaded.state,
    );
    final merged = loaded.convergeWith(sameContent, omittedBytes: 0)!;
    final state = merged.state as ThreadTextItemStateView;
    expect(state.text, 'abcd');
    expect(merged.turnId, 'turn-b', reason: 'Turn 关联由权威副本决定');
    expect(merged.updatedAt, 1798761600);
    expect(
      merged.contextDisposition,
      ThreadContextDisposition.rolledBack,
      reason: '上下文处置不能被“正文相同”吞掉',
    );
  });

  test('同长度附件换成另一份同样生效', () {
    ThreadItemView withAttachment(String id) => ThreadItemView(
      id: 'stable',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 6,
      revision: 4,
      createdAt: createdAt,
      updatedAt: createdAt,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'abcd',
        attachments: [
          ThreadAttachmentView(
            id: id,
            modality: AttachmentModality.image,
            mediaType: 'image/png',
            byteSize: 12,
            filename: '$id.png',
          ),
        ],
        lifecycle: const StreamingThreadContentView(),
      ),
    );

    final merged = withAttachment('a')
        .convergeWith(withAttachment('b'), omittedBytes: 0)!;
    final state = merged.state as ThreadTextItemStateView;
    expect(state.attachments.single.id, 'b');
    expect(state.text, 'abcd');
  });

  test('字段与问答子字段的身份是值语义，独立构造的同值实例可查详情', () {
    // 真实解码路径每帧都是新实例：这里显式用非 const 构造制造不同实例。
    final contentIndex = 3;
    final questionIndex = 1;
    final answerIndex = 2;
    final item = timelineItem(
      7,
      id: 'reasoning',
      details: [
        StudioTimelineDetailRef(
          field: ThreadThinkingContentFieldView(contentIndex),
          revision: 7,
          totalBytes: 4096,
          previewBytes: 128,
        ),
        StudioTimelineDetailRef(
          field: ThreadToolUserInputFieldView(
            questionIndex: questionIndex,
            part: ThreadUserInputAnswerFieldPartView(answerIndex),
          ),
          revision: 7,
          totalBytes: 64,
          previewBytes: 64,
        ),
      ],
    );

    final sameThinking = ThreadThinkingContentFieldView(contentIndex);
    final sameAnswer = ThreadToolUserInputFieldView(
      questionIndex: questionIndex,
      part: ThreadUserInputAnswerFieldPartView(answerIndex),
    );
    expect(
      sameThinking == ThreadThinkingContentFieldView(contentIndex),
      isTrue,
    );
    expect(
      sameThinking.hashCode,
      ThreadThinkingContentFieldView(contentIndex).hashCode,
    );
    expect(
      sameAnswer ==
          ThreadToolUserInputFieldView(
            questionIndex: questionIndex,
            part: ThreadUserInputAnswerFieldPartView(answerIndex),
          ),
      isTrue,
    );
    expect(
      sameAnswer ==
          ThreadToolUserInputFieldView(
            questionIndex: questionIndex,
            part: ThreadUserInputAnswerFieldPartView(9),
          ),
      isFalse,
    );
    expect(
      item.detailFor(sameThinking)!.totalBytes,
      4096,
      reason: 'detailFor 必须按值语义命中，而不是按对象恒等',
    );
    expect(item.detailFor(sameAnswer)!.previewBytes, 64);
    expect(item.detailFor(ThreadThinkingContentFieldView(4)), isNull);

    // Map 以字段为键时，同值实例必须落到同一个槽（详情引用不会随帧增长）。
    final byField = <ThreadContentFieldView, int>{sameThinking: 1};
    byField[ThreadThinkingContentFieldView(contentIndex)] = 2;
    expect(byField.length, 1);
    expect(byField.values.single, 2);
  });

  test('预览值与条目事实分开携带时，未变化的字段引用保持原样', () {
    final item = timelineItem(
      4,
      id: 'stable',
      body: 'abcd',
      details: const [
        StudioTimelineDetailRef(
          field: ThreadTextFieldView(),
          revision: 4,
          totalBytes: 8,
          previewBytes: 4,
        ),
      ],
    );
    expect(item.detailFor(const ThreadTextFieldView())!.truncated, isTrue);
  });
}
