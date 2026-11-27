import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';

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

  static final longUserInputItem = chatItemPresentationOf(
    timelineFeedMessage(
      TimelineUserMessage(
        id: 'preview-user-deferred',
        seq: 1,
        channel: 'user',
        text: longUserInput,
        attachments: const [],
      ),
    ),
  )!;

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
  }) => ChatItemPresentation.decodePayloadJson(
    id,
    _payload(
      type,
      data,
      bodies: bodies,
      contract: contract,
      sealedAt: sealedAt,
    ),
  );

  static String _payload(
    String type,
    Map<String, Object?> data, {
    List<Map<String, Object?>> bodies = const [],
    String contract = 'anywork.chat/1',
    int sealedAt = 1735689600,
  }) => jsonEncode({
    'contract': contract,
    'type': type,
    'data': data,
    'bodies': bodies,
    'sealedAt': sealedAt,
  });

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
    body(
      'tool.output-artifacts',
      jsonEncode([
        {
          'toolData': {
            'stdout': '00:04 +12: All tests passed!',
            'stderr': '',
            'exitCode': 0,
          },
        },
      ]),
    ),
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
  static const groupStartedAt = 1735689600;
  static const commandFinishedAt = 1735689601;
  static const workSummaryKey = 'part.summaryText.0';
  static final workSummaryBytes = utf8.encode(
    '### 核对 **工作组成员** 与 `WorkGroup` 的读取边界\n'
    '确认过长的思考概要在窄窗口中不会挤占命令、修改和其他成员的展示空间。',
  );
  static final completedReasoning = WorkGroupReasoning(
    id: 'preview-reasoning',
    seq: 1,
    text: '先确认纯组件只消费不可变呈现值，再检查 Connector 是否仍持有读取资格。',
    summary: utf8.decode(workSummaryBytes),
    outcome: 'completed',
    startedAtMs: groupStartedAt * 1000,
    finishedAtMs: groupStartedAt * 1000,
  );
  static final completedCommand = WorkGroupToolCall(
    id: 'preview-tool',
    seq: 2,
    callId: 'preview-call',
    toolName: 'exec',
    presentationContract: 'builtin.exec@2',
    status: 'succeeded',
    summary: 'cargo flutter test test/ui',
    payloadJson: _payload(
      'tool',
      tool.data,
      bodies: _commandBodies,
      sealedAt: commandFinishedAt,
    ),
    bodies: const [],
    startedAtMs: groupStartedAt * 1000,
    finishedAtMs: commandFinishedAt * 1000,
  );
  static const secondCompletedReasoning = WorkGroupReasoning(
    id: 'preview-second-reasoning',
    seq: 4,
    text: '先确认纯组件只消费不可变呈现值，再检查 Connector 是否仍持有读取资格。',
    summary: '核对展示边界与资源所有权',
    outcome: 'completed',
    startedAtMs: 1735689603000,
    finishedAtMs: 1735689603000,
  );

  // Unknown wall-clock start avoids a synthetic year-long running timer.
  static const activeReasoning = WorkGroupReasoning(
    id: 'preview-active-reasoning',
    seq: 1,
    outcome: 'running',
    summary: '思考尚未结束',
    text: 'R 的思考尚未结束，已接纳的片段保持可读；后继正文不会使它伪造终态。',
  );
  static final activeReasoningWindow = BodyWindow(
    offset: 0,
    text: activeReasoning.text,
    totalBytes: utf8.encode(activeReasoning.text).length,
    eof: false,
  );

  static const overlapTextAtom = TimelineAssistantText(
    id: 'preview-overlap-T',
    seq: 2,
    turnId: 'preview-turn',
    channel: 'final',
    text: 'T 的正文已经完整结束，但仍在同一个会话中。\n\nR 尚未结束不应阻止这段回复进入历史。',
    isFinalTurnDelivery: true,
    outcome: 'completed',
    occurredAtMs: 1735689602000,
  );
  static final mediaTool = WorkGroupToolCall(
    id: 'preview-media-tool',
    seq: 1,
    callId: 'preview-media-call',
    toolName: 'view_image',
    presentationContract: 'builtin.view_image@1',
    status: 'succeeded',
    summary: '合成媒体读取',
    bodies: const [],
    startedAtMs: 1735689600000,
    finishedAtMs: 1735689602000,
    payloadJson: _payload(
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
  static final failedImageTool = WorkGroupToolCall(
    id: 'preview-failed-image-tool',
    seq: 2,
    callId: 'preview-failed-image-call',
    toolName: 'view_image',
    presentationContract: 'builtin.view_image@1',
    status: 'failed',
    summary: '合成媒体读取',
    bodies: const [],
    startedAtMs: 1735689602000,
    finishedAtMs: 1735689604000,
    payloadJson: _payload(
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
  static final resourceErrorTool = WorkGroupToolCall(
    id: 'preview-resource-error-tool',
    seq: 3,
    callId: 'preview-resource-error-call',
    toolName: 'view_image',
    presentationContract: 'builtin.view_image@1',
    status: 'succeeded',
    summary: '合成媒体读取',
    bodies: const [],
    startedAtMs: 1735689604000,
    finishedAtMs: 1735689606000,
    payloadJson: _payload(
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

  static TimelineWorkGroup runEntry(
    String id,
    int seq, {
    int count = 1,
    bool active = false,
    int? startedAtMs = 100_000,
    int? finishedAtMs = 225_000,
    String summary = '',
  }) => TimelineWorkGroup(
    id: id,
    firstSeq: seq,
    lastSeq: seq + count - 1,
    memberCount: count,
    summary: summary,
    status: active ? WorkGroupStatus.active : WorkGroupStatus.completed,
    startedAtMs: startedAtMs,
    finishedAtMs: active ? null : finishedAtMs,
  );
  static TimelineDisplayUnit runUnit(TimelineWorkGroup entry) =>
      chatItemPresentationOf(timelineFeedMessage(entry))!.displayUnit!;

  static WorkTiming workTiming() =>
      const WorkTiming(startedAtMillis: 100_000, finishedAtMillis: 225_000);

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

  static final failedTurnOverloaded = item(
    'preview-turn-failed-overloaded',
    'turn',
    const {
      'outcome': {
        'kind': 'failed',
        'data': {
          'startedAt': 1795483393,
          'completedAt': 1795483527,
          'failure': {
            'category': 'provider',
            'providerKind': 'unknown',
            'code': 'overloaded',
            'message': '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]',
            'retry': {'kind': 'permanent'},
          },
        },
      },
    },
  );

  static final failedTurnRetryable503 = item(
    'preview-turn-failed-503',
    'turn',
    const {
      'outcome': {
        'kind': 'failed',
        'data': {
          'startedAt': 1795484000,
          'completedAt': 1795484008,
          'failure': {
            'category': 'providerCapacity',
            'providerKind': 'transport',
            'code': 'service_unavailable',
            'httpStatus': 503,
            'message': 'Upstream model gateway returned 503 Service Unavailable while streaming response.',
            'retry': {'kind': 'retryable', 'retryAfterMs': '5000'},
          },
        },
      },
    },
  );

  static final budgetLimitedTurn = item(
    'preview-turn-budget-limited',
    'turn',
    const {
      'outcome': {
        'kind': 'budgetLimited',
        'data': {
          'startedAt': 1795485000,
          'completedAt': 1795485145,
          'limit': {
            'kind': 'modelStep',
            'usage': {
              'modelSteps': 24,
              'toolCalls': 41,
              'waitCalls': 2,
              'elapsedMs': 145000,
            },
          },
          'rollover': {'kind': 'succeeded'},
        },
      },
    },
  );

  static final cancelledTurn = item('preview-turn-cancelled', 'turn', const {
    'outcome': {
      'kind': 'cancelled',
      'data': {
        'startedAt': 1795486000,
        'requestedAt': 1795486012,
        'completedAt': 1795486013,
        'cause': {'kind': 'userRequested'},
      },
    },
  });

  static const contentWindow = BodyWindow(
    offset: 0,
    text: '这是合成且已接纳的有界正文窗口。Preview 不会发起查询或 Clipboard IO。',
    totalBytes: 196608,
    eof: false,
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

  static const _copyBodies = {
    'preview-copy-event-1': '排查连接池获取超时后未及时释放句柄的问题，并补齐取消安全测试。',
    'preview-copy-event-2': '已定位到忙碌重试循环没有及时响应取消信号，正在验证超时后的资源释放。',
    'preview-copy-event-4': '已修复连接池取消后未及时释放句柄的问题。超时和取消两条路径均已通过回归测试。',
  };

  static List<Message> copyActionMessages() => [
    _copyActionMessage(1, ThreadTextChannel.user),
    _copyActionMessage(2, ThreadTextChannel.commentary),
    timelineFeedMessage(runEntry('copy-work', 3, count: 3)),
    _copyActionMessage(4, ThreadTextChannel.finalAnswer),
  ];

  // Explicit accepted presentation values preserve the stored-body copy scene.
  // All loading, disclosure and Clipboard behavior belongs to production widgets.
  static Message _copyActionMessage(int order, ThreadTextChannel channel) {
    final id = 'preview-copy-event-$order';
    final byteLength = utf8.encode(_copyBodies[id]!).length;
    return _message(
      ChatItemPresentation(
        id: id,
        compatibility: ChatItemCompatibility.current,
        type: 'text',
        authorId: channel == ThreadTextChannel.user ? 'user' : 'assistant',
        finalTurnDelivery: channel == ThreadTextChannel.finalAnswer,
        data: const {},
        bodies: [
          ChatBodyPresentation(
            key: 'body',
            byteLength: byteLength,
            feedReference: BodyRef(
              databaseId: 'preview',
              bodyId: id,
              ownerEventId: id,
              bodyKey: 'body',
              role: 'body',
              byteLength: byteLength,
            ),
          ),
        ],
      ),
    );
  }

  static Future<BodyWindow> readCopyBodyWindow(
    BodyRef reference, {
    required int offset,
    required int maxBytes,
  }) async {
    final text = _copyBodies[reference.bodyId];
    if (reference.databaseId != 'preview' ||
        reference.bodyKey != 'body' ||
        text == null) {
      throw StateError('Unexpected preview copy body: ${reference.bodyId}');
    }
    final bytes = utf8.encode(text);
    final end = (offset + maxBytes).clamp(0, bytes.length);
    return BodyWindow(
      offset: offset,
      bytesBase64: base64Encode(bytes.sublist(offset, end)),
      totalBytes: bytes.length,
      eof: end == bytes.length,
    );
  }

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
        chatItemPresentationOf(
          timelineFeedMessage(
            runEntry('spacing-group-$index', index * 4 + 3, count: 3),
          ),
        )!,
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

  static ChatItemPresentation _parentMessage(
    String id,
    int order,
    String text,
  ) => chatItemPresentationOf(
    timelineFeedMessage(
      TimelineUserMessage(
        id: id,
        seq: order,
        channel: 'parentAgent',
        text: text,
        attachments: const [],
      ),
    ),
  )!;

  static List<Message> parentAgentMessages() => [
    _message(
      _parentMessage(
        'preview-parent-task',
        1,
        '请检查时间线中上级消息的展示，确认文字、间距和窄窗口换行与用户消息保持一致。',
      ),
    ),
    _message(
      item(
        'preview-child-progress',
        'text',
        const {'channel': 'commentary', 'attachments': []},
        bodies: [body('body', '已核对消息来源与展示路径，正在检查长文本和窄窗口效果。')],
      ),
    ),
    _message(
      _parentMessage('preview-parent-followup', 3, '请继续验证完整的前端测试，并在完成后报告结果。'),
    ),
  ];

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
