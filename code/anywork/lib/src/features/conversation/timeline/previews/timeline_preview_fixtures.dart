import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';

/// Synthetic immutable presentation values. They exercise production widgets
/// only and do not model a repository, runtime, provider or native bridge.
abstract final class TimelinePreviewFixtures {
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
  }) => ChatItemPresentation.decodePayload(
    id,
    InlinePayload(
      bytes: utf8.encode(
        jsonEncode({
          'contract': contract,
          'type': type,
          'data': data,
          'bodies': bodies,
          'sealedAt': 1735689600,
        }),
      ),
    ),
  );

  static final user = item(
    'preview-user',
    'text',
    const {'channel': 'user', 'attachments': []},
    bodies: [body('part.text.0', '请核对时间线的历史呈现，并保留窄窗口下的完整阅读能力。')],
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
    bodies: [
      body('part.summaryText.0', '核对展示边界与资源所有权'),
      body('part.reasoningText.0', '先确认纯组件只消费不可变呈现值，再检查 Connector 是否仍持有读取资格。'),
    ],
  );

  static final tool = item(
    'preview-tool',
    'tool',
    {
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
    },
    bodies: [
      body('tool.arguments', '{"command":"cargo flutter test test/ui"}'),
      body('tool.result', '00:04 +12: All tests passed!'),
    ],
  );

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
