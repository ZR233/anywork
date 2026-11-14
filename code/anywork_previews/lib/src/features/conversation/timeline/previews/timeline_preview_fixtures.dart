import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';

/// Synthetic immutable presentation values. They exercise production widgets
/// only and do not model a repository, runtime, provider or native bridge.
abstract final class TimelinePreviewFixtures {
  static final longUserInput =
      '# 用户长输入\n\n'
      '**待发送与正式正文使用相同呈现。**\n\n'
      '- 可选择复制正文\n'
      '- 根据窗口宽度自然换行\n\n'
      '${'这是一段没有人为换行的中文用户输入，用于检查长正文在窄窗口中的完整呈现。' * 70}\n\n'
      '末尾内容保持可读。';

  static const userBodyReference = ContentRef(
    databaseId: 'preview',
    target: BodyContentTarget(
      owner: ItemContentOwner(itemId: 'preview-user-deferred'),
      key: 'body',
    ),
  );

  static final deferredUserInput = ChatItemPresentation.forUnit(
    TimelineDisplayUnit(
      block: DisplayBlock(
        id: 'preview-user-deferred',
        blockOrder: 1,
        body: SingleDisplayBlock(
          visibility: SingleVisibility.content,
          record: DisplayRecord(
            atom: ChatAtom(
              id: 'preview-user-deferred',
              completionItemId: 'preview-user-deferred',
              source: const InputChatSource(inputId: 'preview-input'),
              sourceOrder: 1,
              kind: ChatAtomKind.input,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const TerminalChatAtom(
                started: null,
                ended: null,
                outcome: ChatTerminalOutcome.completed,
              ),
              contents: const [
                ChatAtomContent(
                  role: ChatContentRole.body,
                  reference: userBodyReference,
                ),
              ],
              payload: const DeferredPayload(
                reference: ContentRef(
                  databaseId: 'preview',
                  target: ItemPayloadTarget(itemId: 'preview-user-deferred'),
                ),
                byteLength: 90000,
              ),
            ),
            contentSource: CompletedOriginal(
              completionId: 'preview-user-deferred',
            ),
          ),
        ),
      ),
    ),
  );

  static ComposerSubmission longUserSubmission(ComposerSubmissionPhase phase) =>
      ComposerSubmission(
        inputId: 'preview-input',
        text: longUserInput,
        attachments: const [
          AttachmentDraftView(
            id: 'preview-draft',
            modality: AttachmentModalityView.file,
            mediaType: 'text/plain',
            filename: '用户输入附件.txt',
            byteSize: 120,
          ),
        ],
        phase: phase,
      );

  static Map<String, Object?> body(String key, String text) => {
    'key': key,
    'byteLength': utf8.encode(text).length,
    'inline': utf8.encode(text),
  };

  static ChatItemPresentation item(
    String id,
    String type,
    Map<String, Object?> data, {
    List<Map<String, Object?>> bodies = const [],
    String contract = 'anywork.chat/1',
    int sealedAt = 1735689600,
  }) => ChatItemPresentation.decodePayload(
    id,
    _payload(
      type,
      data,
      bodies: bodies,
      contract: contract,
      sealedAt: sealedAt,
    ),
  );

  static InlinePayload _payload(
    String type,
    Map<String, Object?> data, {
    List<Map<String, Object?>> bodies = const [],
    String contract = 'anywork.chat/1',
    int sealedAt = 1735689600,
  }) => InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': contract,
        'type': type,
        'data': data,
        'bodies': bodies,
        'sealedAt': sealedAt,
      }),
    ),
  );

  static final user = item(
    'preview-user',
    'text',
    const {'channel': 'user', 'attachments': []},
    bodies: [body('body', '请核对时间线的历史呈现，并保留窄窗口下的完整阅读能力。')],
  );

  static final assistant = item(
    'preview-assistant',
    'text',
    const {'channel': 'final', 'attachments': []},
    bodies: [
      body(
        'part.text.0',
        '历史正文保持文档式阅读，不装进重复卡片。\n\n'
            '- 每个完成 item 保留唯一消息身份；\n'
            '- 长中文、`inline code` 与链接在有限宽度内自然换行；\n'
            '- [安全链接](https://example.com/docs) 仍由上层动作决定是否打开。',
      ),
    ],
  );

  static final reasoning = item(
    'preview-reasoning',
    'thinking',
    const {},
    bodies: _reasoningBodies,
  );
  static final _reasoningBodies = [
    body('part.summaryText.0', '核对展示边界与资源所有权'),
    body('part.reasoningText.0', '先确认纯组件只消费不可变呈现值，再检查 Connector 是否仍持有读取资格。'),
  ];

  static final tool = item('preview-tool', 'tool', {
    'invocation': {
      'toolCallId': 'preview-call',
      'name': 'exec',
      'presentationContract': 'builtin.exec@2',
      'workingDirectory': 'code/anywork',
    },
    'state': {
      'kind': 'succeeded',
      'completedAt': 1735689601,
      'output': {'exitCode': 0, 'attachments': []},
    },
  }, bodies: _commandBodies);
  static final _commandBodies = [
    body('tool.arguments', '{"command":"cargo flutter test test/ui"}'),
    body('tool.result', '00:04 +12: All tests passed!'),
  ];

  /// 紧凑多文件补丁：新增、带移动的更新（@@ 定位、缩进、空行、EOF）、删除。
  static final applyPatchText = r'''*** Begin Patch
*** Environment ID: preview-env
*** Add File: lib/example/greeter.dart
+class Greeter {
+  final String name;
+
+  Greeter(this.name);
+
+  String greet() => '你好，' + name;
+}
*** Update File: lib/example/legacy.dart
*** Move to: lib/example/renamed.dart
@@ class Greeter {
-  String greet() => throw UnimplementedError();
+  String greet() => '你好，' + name;
@@
+
+  @override
+  String toString() => 'Greeter(' + name + ')';
 }
*** End of File
*** Delete File: docs/legacy-notes.md
*** End Patch''';

  static const _applyPatchChangedFiles = [
    'lib/example/greeter.dart',
    'lib/example/renamed.dart',
    'docs/legacy-notes.md',
  ];

  static final applyPatchTool = item(
    'preview-apply-patch',
    'tool',
    {
      'invocation': {
        'toolCallId': 'preview-apply-patch-call',
        'name': 'apply_patch',
        'presentationContract': 'builtin.apply_patch@1',
      },
      'state': {
        'kind': 'succeeded',
        'completedAt': 1735689602,
        'output': {'changedFiles': _applyPatchChangedFiles},
      },
    },
    bodies: [
      body('tool.arguments', applyPatchText),
      body(
        'tool.result',
        jsonEncode({'changedFiles': _applyPatchChangedFiles}),
      ),
    ],
  );

  // All member identities, lifecycle facts and group summaries below are
  // explicitly projected synthetic inputs, not a grouping fixture engine.
  static const groupSource = ForegroundTurnChatSource(turnId: 'preview-turn');
  static const groupStartedAt = 1735689600;
  static const commandFinishedAt = 1735689601;
  static final completedReasoning = ChatAtom(
    id: 'preview-reasoning',
    source: groupSource,
    sourceOrder: 1,
    kind: ChatAtomKind.reasoning,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-turn',
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 1, suborder: 0),
      ended: ChatFactPosition(effectSeq: 2, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: groupStartedAt,
    finishedAt: groupStartedAt,
    contents: const [],
    payload: _payload('thinking', const {}, bodies: _reasoningBodies),
  );
  static final completedCommand = ChatAtom(
    id: 'preview-tool',
    source: groupSource,
    sourceOrder: 2,
    kind: ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-turn',
    tool: const ChatToolIdentity(callId: 'preview-call', name: 'exec'),
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 3, suborder: 0),
      ended: ChatFactPosition(effectSeq: 4, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: groupStartedAt,
    finishedAt: commandFinishedAt,
    contents: const [],
    payload: _payload(
      'tool',
      tool.data,
      bodies: _commandBodies,
      sealedAt: commandFinishedAt,
    ),
  );
  static final secondCompletedReasoning = ChatAtom(
    id: 'preview-second-reasoning',
    source: groupSource,
    sourceOrder: 4,
    kind: ChatAtomKind.reasoning,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-turn',
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 7, suborder: 0),
      ended: ChatFactPosition(effectSeq: 8, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: 1735689603,
    finishedAt: 1735689603,
    contents: const [],
    payload: _payload(
      'thinking',
      const {},
      bodies: _reasoningBodies,
      sealedAt: 1735689603,
    ),
  );

  // Wall-clock start is deliberately unknown: a static preview must not turn a
  // fixed synthetic date into a year-long locally running elapsed timer.
  static final activeReasoning = ChatAtom(
    id: 'preview-active-reasoning',
    source: groupSource,
    sourceOrder: 1,
    kind: ChatAtomKind.reasoning,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-turn',
    lifecycle: const ActiveChatAtom(
      started: ChatFactPosition(effectSeq: 1, suborder: 0),
      status: ChatActiveStatus.running,
    ),
    contentPresent: true,
    contents: const [
      ChatAtomContent(
        role: ChatContentRole.body,
        reference: ContentRef(
          databaseId: 'preview',
          target: BodyContentTarget(
            owner: CurrentContentOwner(
              domain: 'reasoning',
              id: 'preview-active-reasoning',
              revision: 1,
            ),
            key: 'body',
          ),
        ),
      ),
    ],
  );
  static final activeReasoningWindow = ContentWindow(
    offset: 0,
    bytes: utf8.encode('R 的思考尚未结束，已接纳的片段保持可读；后继正文不会使它伪造终态。'),
    generation: 'preview-active-reasoning-window',
    availableThrough: utf8.encode('R 的思考尚未结束，已接纳的片段保持可读；后继正文不会使它伪造终态。').length,
    sealed: false,
  );

  static final overlapTextAtom = ChatAtom(
    id: 'preview-overlap-T',
    source: groupSource,
    sourceOrder: 2,
    kind: ChatAtomKind.text,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-turn',
    textChannel: ThreadTextChannel.finalAnswer,
    contentPresent: true,
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 3, suborder: 0),
      ended: ChatFactPosition(effectSeq: 4, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: 1735689601,
    finishedAt: 1735689602,
    contents: const [],
    payload: _payload(
      'text',
      const {'channel': 'final', 'attachments': []},
      bodies: [
        body(
          'part.text.0',
          'T 的正文已经完整结束，但仍在同一个 current 中。\n\nR 尚未结束不应阻止这段回复进入历史。',
        ),
      ],
      sealedAt: 1735689602,
    ),
  );
  static final overlapText = CompletedEntry(
    recordId: 'preview-overlap-T',
    completionSeq: 1,

    atom: overlapTextAtom,
  );
  static final overlapActivity = ActivitySnapshot(
    revision: 1,
    completedThrough: 1,
    executionPresent: true,
    entries: [
      ActivityEntry(
        identity: ModelPartActivityIdentity(atomId: activeReasoning.id),
        atom: activeReasoning,
      ),
    ],
  );

  static const mediaSource = ForegroundTurnChatSource(
    turnId: 'preview-media-turn',
  );
  static final mediaTool = ChatAtom(
    id: 'preview-media-tool',
    source: mediaSource,
    sourceOrder: 1,
    kind: ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-media-turn',
    tool: const ChatToolIdentity(
      callId: 'preview-media-call',
      name: 'view_image',
    ),
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 1, suborder: 0),
      ended: ChatFactPosition(effectSeq: 2, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: 1735689600,
    finishedAt: 1735689602,
    contentPresent: true,
    contents: const [],
    payload: _payload(
      'tool',
      {
        'invocation': {
          'toolCallId': 'preview-media-call',
          'name': 'view_image',
          'presentationContract': 'builtin.view_image@1',
        },
        'state': {
          'kind': 'succeeded',
          'completedAt': 1735689602,
          'output': {
            'attachments': [
              _imageMetadata('preview-tool-image-1'),
              _imageMetadata('preview-tool-image-2'),
              _imageMetadata('preview-tool-image-3'),
            ],
          },
        },
      },
      bodies: [
        body('tool.arguments', '{"path":"synthetic-landscape-triptych.png"}'),
        body('tool.result', '同一个工具成员返回三张合成图片与这段文字；图片和结果不另拆工作组。'),
      ],
      sealedAt: 1735689602,
    ),
  );
  static final failedImageTool = ChatAtom(
    id: 'preview-failed-image-tool',
    source: mediaSource,
    sourceOrder: 2,
    kind: ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-media-turn',
    tool: const ChatToolIdentity(
      callId: 'preview-failed-image-call',
      name: 'view_image',
    ),
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 3, suborder: 0),
      ended: ChatFactPosition(effectSeq: 4, suborder: 0),
      outcome: ChatTerminalOutcome.failed,
    ),
    startedAt: 1735689602,
    finishedAt: 1735689604,
    contents: const [],
    payload: _payload(
      'tool',
      const {
        'invocation': {
          'toolCallId': 'preview-failed-image-call',
          'name': 'view_image',
          'presentationContract': 'builtin.view_image@1',
        },
        'state': {
          'kind': 'failed',
          'failedAt': 1735689604,
          'failure': {'kind': 'failed', 'message': '合成工具失败：源文件不可读取'},
        },
      },
      bodies: [body('tool.arguments', '{"path":"synthetic-unreadable.png"}')],
      sealedAt: 1735689604,
    ),
  );
  static final resourceErrorTool = ChatAtom(
    id: 'preview-resource-error-tool',
    source: mediaSource,
    sourceOrder: 3,
    kind: ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    turnId: 'preview-media-turn',
    tool: const ChatToolIdentity(
      callId: 'preview-resource-error-call',
      name: 'view_image',
    ),
    lifecycle: const TerminalChatAtom(
      started: ChatFactPosition(effectSeq: 5, suborder: 0),
      ended: ChatFactPosition(effectSeq: 6, suborder: 0),
      outcome: ChatTerminalOutcome.completed,
    ),
    startedAt: 1735689604,
    finishedAt: 1735689606,
    contentPresent: true,
    contents: const [],
    payload: _payload(
      'tool',
      {
        'invocation': {
          'toolCallId': 'preview-resource-error-call',
          'name': 'view_image',
          'presentationContract': 'builtin.view_image@1',
        },
        'state': {
          'kind': 'succeeded',
          'completedAt': 1735689606,
          'output': {
            'attachments': [_imageMetadata('preview-resource-error-image')],
          },
        },
      },
      bodies: [
        body('tool.arguments', '{"path":"synthetic-resource-error.png"}'),
        body('tool.result', '工具业务已成功；下方媒体资源错误不改变本成员的 completed 终态。'),
      ],
      sealedAt: 1735689606,
    ),
  );
  static final mediaGroup = runEntry('preview-media-group', 3, count: 3);

  static CompletedEntry runEntry(String id, int seq, {int count = 1}) =>
      CompletedEntry(
        recordId: id,
        completionSeq: seq,

        atom: ChatAtom(
          id: id,
          completionItemId: id,
          completionSeq: seq,
          source: groupSource,
          sourceOrder: null,
          kind: ChatAtomKind.toolCall,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: const [],
          payload: DeferredPayload(
            reference: ContentRef(
              databaseId: 'preview',
              target: ItemPayloadTarget(itemId: id),
            ),
            byteLength: 100,
          ),
        ),
      );
  static TimelineDisplayUnit runUnit(CompletedEntry entry) =>
      TimelineDisplayUnit(
        block: DisplayBlock(
          id: entry.recordId,
          blockOrder: entry.completionSeq,
          body: WorkDisplayBlock(
            timing: workTiming(),
            members: DisplayBlockRef(
              databaseId: 'preview',
              blockId: entry.recordId,
            ),
          ),
        ),
      );

  static WorkTiming workTiming() => WorkTiming(startedAt: 100, finishedAt: 225);

  static Map<String, Object?> _imageMetadata(String id) => {
    'id': id,
    'modality': 'image',
    'mediaType': 'image/png',
    'byteSize': imageBytes.length,
    'filename': '$id.png',
    'width': imageWidth,
    'height': imageHeight,
  };

  static final webSearch = item(
    'preview-web-search',
    'tool',
    const {
      'invocation': {
        'toolCallId': 'preview-search-call',
        'name': 'web_search',
        'presentationContract': 'builtin.web_search@1',
      },
      'state': {
        'kind': 'succeeded',
        'output': {'attachments': []},
      },
    },
    bodies: [
      body(
        'tool.arguments',
        '{"search_query":[{"q":"Flutter ExpansionTile"}]}',
      ),
      body('tool.result', '合成搜索结果：https://api.flutter.dev/'),
    ],
  );

  static final waiting = item(
    'preview-wait',
    'tool',
    {
      'invocation': {
        'toolCallId': 'preview-wait-call',
        'name': 'wait',
        'presentationContract': 'builtin.wait@1',
      },
      'state': {
        'kind': 'succeeded',
        'completedAt': 1735689602,
        'output': {'attachments': []},
      },
      'wait': {
        'state': 'ready',
        'messagesReady': false,
        'intent': {
          'kind': 'events',
          'data': {
            'timeoutMs': 30000,
            'targets': [
              {
                'taskId': 'task:preview',
                'toolName': 'exec',
                'summary': '定向 Flutter 组件测试',
                'summaryTruncated': false,
                'status': 'succeeded',
              },
            ],
          },
        },
      },
    },
    bodies: [
      body('tool.arguments', '{"taskIds":["task:preview"]}'),
      body('tool.result', '{"ready":true}'),
    ],
  );

  static final questionReceipt = item(
    'preview-question',
    'tool',
    {
      'invocation': {
        'toolCallId': 'preview-question-call',
        'name': 'request_user_input',
        'presentationContract': 'generic@1',
      },
      'state': {
        'kind': 'succeeded',
        'completedAt': 1735689603,
        'output': {'attachments': []},
      },
      'userInput': {
        'interactionId': 'preview-interaction',
        'questions': [
          {'id': 'layout', 'isSecret': false, 'optionCount': 2},
          {'id': 'credential', 'isSecret': true, 'optionCount': 0},
        ],
        'state': {
          'kind': 'resolved',
          'answers': [
            {'questionId': 'credential', 'answerCount': 1, 'redacted': true},
            {'questionId': 'layout', 'answerCount': 1, 'redacted': false},
          ],
        },
      },
    },
    bodies: [
      body('tool.arguments', '{}'),
      body('tool.user-input.question.0.header', '历史呈现密度'),
      body('tool.user-input.question.0.body', '选择紧凑还是舒展？'),
      body('tool.user-input.question.0.option.0.label', '紧凑'),
      body('tool.user-input.question.0.option.0.description', '保留清晰的过程导轨与最小行高'),
      body('tool.user-input.question.0.option.1.label', '舒展'),
      body('tool.user-input.question.0.option.1.description', '增加段落留白'),
      body('tool.user-input.answer.0.0', '紧凑'),
      body('tool.user-input.question.1.header', '不会公开的凭据'),
      body('tool.user-input.answer.1.0', 'preview-secret-must-stay-hidden'),
    ],
  );

  static final planReceipt = item(
    'preview-plan',
    'plan',
    const {
      'interactionId': 'preview-plan-interaction',
      'decision': 'revisionRequested',
      'documentVersion': 7,
    },
    bodies: [
      body('plan.document', '# 实施计划\n\n1. 拆分纯呈现与资源 Connector。\n2. 复用生产组件预览。'),
      body('plan.feedback', '补充敏感字段遮蔽证明。'),
    ],
  );

  static final fallback = item(
    'preview-fallback',
    'tool',
    const {
      'invocation': {
        'toolCallId': 'preview-unknown',
        'name': 'future_tool',
        'presentationContract': 'builtin.future_tool@9',
      },
      'state': {
        'kind': 'succeeded',
        'output': {'attachments': []},
      },
    },
    bodies: [body('tool.arguments', '{"future":true}')],
  );

  static const contentReference = ContentRef(
    databaseId: 'preview-database',
    target: ItemPayloadTarget(itemId: 'preview-deferred'),
  );

  static final contentWindow = ContentWindow(
    offset: 0,
    bytes: utf8.encode('这是合成且已接纳的有界正文窗口。Preview 不会发起查询或 Clipboard IO。'),
    generation: 'preview-generation',
    availableThrough: 196608,
    sealed: true,
  );

  // Original synthetic landscape: flat sky, orange sun and two mountain ridges.
  // A 989-byte RGB PNG, not a screenshot, remote image or business attachment.
  static const imageWidth = 320;
  static const imageHeight = 180;
  static final imageBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAUAAAAC0CAIAAABqhmJGAAADpElEQVR42u3cvU0eYRSE0enCBbgC1+CMFiy5Aeogd4Loi5SAEsgc'
      'E5BYRP740zv3HulpYK72RKvdPD79lVRanEACWBLAkgCWAJYEsCSAJQEsASwJYEkASwBLAlgSwJIAlgCWBLAkgCUBLAEsCWBJAEsA'
      'S9N6uvv9PwEsVdKtZgyw0C1mDLDQLWYMsOgtNgyw6C02DLDoLTYMsOgtNgyw6C02DLAABlgarfdYwwALYICl6XrPNAywAAZYWqD3'
      'QMMAC2CAJYABlgAGWAADLAEMsAQwwBLAAAtggCWAAZYABlgAAywBDLDkaySAJYABFsP+yCEBDLBUbvjM+QALYICl0YaP3Q7wBV3d'
      '3DrCQsMnDwf4Ar0vOcUqw4evBvgyvQyvMnz+ZIAv1svwEsMVewF+i16GZzMuWgrwW+hiPJVx3UaA36WX4TGMS9cB/F69DAvgbr0M'
      'C+BiuhgL4Al6GRbA3XoZFsDdehkWwN16GRbAxXQx/tS+/7p2hNWAv0wvw5+h9yWnWAr4i/Uy/OF0/w1gehlu1ctw6GW4Wu9yw0EX'
      '42q6yxmHXoZn6N1pOPQyPEbvQsOhl+ExdBcyDroYz9O7x3DoZXik3iWGQy/DI+kuYRx6GZ6td7bh0MvweL2DDQddjMfTHcw49DK8'
      'R+88w6GX4VV6hxkOvQyvojuMcdDFeKfeGYZDL8Nr9Q4wHHoZXkt3AOPQyzC9vYZDL8P09hoOuhij28s49DJMb6/h0Mswvb2GQy/D'
      '6PYyDroY09trOPQyTG+v4dDLMLq9jEMvw/T2Gg69DNPbazjoYoxuL+PQyzC9vYZDL8P09hoOvQyj28s46GJMb6/h0Mswvb2GQy/D'
      '6PYyDr0M09trOPQyTG+v4aCLMbq9jEMvw/T2Gg69DNPbazj0MsxYL+PQuzy0qg0HXXrVazj0oqtexqGXXvUaDr30qtdw0EVXvYxD'
      'L73qNRx66VWv4dCLrnoZh1561Ws46NKrXsOhF131Mg699KrXcOilV72Ggy666mUceulVr+HQS696DYdedNXLOPTSq17DQZde9RoO'
      'veiql3HopVe9hV56VQwYDHQFsOgVwKJXAKMrgEWvABa9AhhdCWB6BbDoFcBCVwDTK4BFrwAWugKYXglgegWw0NW5gL/9+CmpNIAl'
      'gCUBLAlgCWBJAEsCWBLAEsCSWgH/uX/QqzxGAhhgCWCABTDAAAtggCWAAZa8RpIAlgSwJIAlgF1BAlgSwJIAlgCWdHbP21FJVztt'
      'sg8AAAAASUVORK5CYII=',
    ),
  ).asUnmodifiableView();

  static final imageAttachment = ThreadAttachmentView(
    id: 'preview-image',
    modality: AttachmentModalityView.image,
    mediaType: 'image/png',
    byteSize: imageBytes.length,
    filename: 'synthetic-landscape-320x180.png',
    width: imageWidth,
    height: imageHeight,
  );

  static List<Message> commandMessages() => [
    for (var index = 0; index < 3; index++)
      _message(
        item(
          'spacing-command-$index',
          'tool',
          tool.data,
          bodies: _commandBodies,
        ),
      ),
  ];

  /// 同作者相邻消息、跨时间消息和工作组使用同一个生产时间线。
  static List<Message> spacingMessages() => [
    _message(
      item(
        'spacing-intro',
        'text',
        const {'channel': 'commentary'},
        bodies: [
          body('part.text.0', '已完成本地验证，接下来检查布局与工作记录。正文保持自然高度，工具详情按需展开。'),
        ],
      ),
    ),
    _message(
      item(
        'spacing-plain',
        'text',
        const {'channel': 'commentary'},
        bodies: [body('part.text.0', '同一作者的连续段落采用一致的间隔。')],
      ),
    ),
    for (var index = 0; index < 2; index++) ...[
      _message(
        ChatItemPresentation.forUnit(
          runUnit(runEntry('spacing-group-$index', index * 4 + 3, count: 3)),
        ),
      ),
      _message(
        item(
          'spacing-result-$index',
          'text',
          const {'channel': 'commentary'},
          sealedAt: 1735690200 + index * 600,
          bodies: [
            body(
              'part.text.0',
              index == 0
                  ? '两组检查已经完成，`cargo flutter analyze` 与界面测试均已结束。工作摘要、正文和下一组记录沿同一阅读列排列。'
                  : '布局检查完成。窄窗口下正文自然换行，放大字体后摘要统计可以换行，展开工具后仍由主时间线统一滚动。',
            ),
          ],
        ),
      ),
    ],
  ];

  static Message _message(ChatItemPresentation value) => Message.custom(
    id: value.id,
    authorId: value.authorId,
    createdAt: value.createdAt,
    metadata: {chatItemPresentationKey: value},
  );

  static List<Message> messages() => [
    for (final value in [
      user,
      assistant,
      reasoning,
      tool,
      waiting,
      questionReceipt,
      planReceipt,
      fallback,
    ])
      Message.custom(
        id: value.id,
        authorId: value.authorId,
        createdAt: value.createdAt,
        metadata: {chatItemPresentationKey: value},
      ),
  ];
}
