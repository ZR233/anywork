import 'dart:convert';

import 'package:anywork_client/models.dart';

import 'chat_item_presentation.dart';
import 'tool_presentation.dart';

Map<String, Object?> chatObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$field 必须是对象');
}

String chatString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 必须是字符串');
}

String? chatOptionalString(Object? value, String field) =>
    value == null ? null : chatString(value, field);
int chatInteger(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field 必须是整数');
}

DateTime? chatTimestamp(Object? value) {
  if (value == null) return null;
  final seconds = chatInteger(value, '时间');
  if (seconds < -8640000000000 || seconds > 8640000000000) {
    throw const FormatException('时间超出可表示范围');
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

T chatEnum<T extends Enum>(Iterable<T> values, Object? value, String field) {
  final name = chatString(value, field);
  final matched = values.where((v) => v.name == name).firstOrNull;
  if (matched != null) return matched;
  throw FormatException('未知 $field: $name');
}

List<ThreadAttachmentView> chatAttachments(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('attachments 必须是数组');
  return List.unmodifiable(
    value.map((entry) {
      final item = chatObject(entry, 'attachment');
      return ThreadAttachmentView(
        id: chatString(item['id'], 'attachment.id'),
        modality: chatEnum(
          AttachmentModalityView.values,
          item['modality'],
          'attachment.modality',
        ),
        mediaType: chatString(item['mediaType'], 'attachment.mediaType'),
        byteSize: chatInteger(item['byteSize'], 'attachment.byteSize'),
        filename: chatOptionalString(item['filename'], 'attachment.filename'),
        width: item['width'] == null
            ? null
            : chatInteger(item['width'], 'attachment.width'),
        height: item['height'] == null
            ? null
            : chatInteger(item['height'], 'attachment.height'),
      );
    }),
  );
}

sealed class ToolCardReading {
  const ToolCardReading();
}

final class DecodedToolCard extends ToolCardReading {
  const DecodedToolCard(this.value);
  final TimelineToolPresentation value;
}

final class UnavailableToolCard extends ToolCardReading {
  const UnavailableToolCard(
    this.reason, {
    this.kind = ToolCardUnavailableKind.unknownContract,
  });
  final String reason;
  final ToolCardUnavailableKind kind;
}

enum ToolCardUnavailableKind { unknownContract, malformed, deferred }

ToolCardReading readToolCard(ChatItemPresentation item) {
  final marker = item.presentationContract;
  if (marker != 'generic@1' && !specializedToolContracts.contains(marker)) {
    return UnavailableToolCard(
      marker == null
          ? '未提供 presentationContract'
          : '不支持的 presentationContract：$marker',
    );
  }
  try {
    final invocation = chatObject(item.data['invocation'], 'invocation');
    final state = chatObject(item.data['state'], 'state');
    final status = chatString(state['kind'], 'state.kind');
    if (!const {
      'backgroundStarted',
      'interrupted',
      'succeeded',
      'failed',
      'denied',
      'cancelled',
    }.contains(status)) {
      throw FormatException('未知工具终态: $status');
    }
    final argumentsBody = item.body('tool.arguments');
    if (argumentsBody == null) {
      throw const FormatException('缺少 tool.arguments 正文');
    }
    if (argumentsBody.reference != null) {
      return const UnavailableToolCard(
        '参数按需读取，尚未取得完整业务内容',
        kind: ToolCardUnavailableKind.deferred,
      );
    }
    final arguments = item.inlineText('tool.arguments');
    if (arguments == null) {
      throw const FormatException('缺少 tool.arguments 内联内容');
    }
    // generic@1 and the freeform patch tool have no structured argument parser.
    if (marker != 'generic@1' && marker != 'builtin.apply_patch@1') {
      chatObject(jsonDecode(arguments), '工具参数');
    }
    final output = state['output'] == null
        ? null
        : chatObject(state['output'], 'state.output');
    final failure = state['failure'] == null
        ? null
        : chatObject(state['failure'], 'state.failure');
    final ended = switch (status) {
      'succeeded' => state['completedAt'],
      'failed' => state['failedAt'],
      'denied' => state['deniedAt'],
      'cancelled' => state['cancelledAt'],
      'interrupted' => state['interruptedAt'],
      'backgroundStarted' => null,
      _ => null,
    };
    final artifacts = item.inlineText('tool.output-artifacts');
    return DecodedToolCard(
      TimelineToolPresentation(
        id: item.id,
        toolCallId: chatString(
          invocation['toolCallId'],
          'invocation.toolCallId',
        ),
        name: chatString(invocation['name'], 'invocation.name'),
        presentationContract: marker!,
        statusString: status,
        frozenObservation:
            item.displayRecord?.contentSource is FrozenObservation,
        executionPresent: item.displayRecord?.contentSource is CurrentAtom,
        arguments: arguments,
        output: item.inlineText('tool.result') ?? '',
        // No start timestamp is present in the canonical invocation. Keep unknown.
        completedAt: chatTimestamp(ended),
        error: failure == null
            ? chatOptionalString(state['reason'], 'state.reason')
            : chatOptionalString(failure['message'], 'state.failure.message'),
        taskId: chatOptionalString(invocation['taskId'], 'invocation.taskId'),
        workingDirectory: chatOptionalString(
          invocation['workingDirectory'],
          'invocation.workingDirectory',
        ),
        exitCode: output?['exitCode'] == null
            ? null
            : chatInteger(output!['exitCode'], 'output.exitCode'),
        timedOut: failure?['kind'] == 'timedOut',
        attachments: chatAttachments(output?['attachments']),
        outputArtifacts: artifacts == null ? const [] : [artifacts],
        wait:
            (marker == 'builtin.wait@1' || marker == 'builtin.sleep@1') &&
                item.data['wait'] != null
            ? _wait(item.data['wait'])
            : null,
      ),
    );
  } on FormatException catch (error) {
    return UnavailableToolCard(
      '当前工具内容无法解析：${error.message}',
      kind: ToolCardUnavailableKind.malformed,
    );
  } on TypeError catch (error) {
    return UnavailableToolCard(
      '当前工具内容无法解析：$error',
      kind: ToolCardUnavailableKind.malformed,
    );
  }
}

ThreadWaitPresentationView _wait(Object? value) {
  final wait = chatObject(value, 'wait');
  final intent = chatObject(wait['intent'], 'wait.intent');
  final data = chatObject(intent['data'], 'wait.intent.data');
  return ThreadWaitPresentationView(
    state: chatEnum(ThreadWaitStateView.values, wait['state'], 'wait.state'),
    messagesReady: wait['messagesReady'] as bool?,
    intent: switch (intent['kind']) {
      'timer' => ThreadWaitTimerIntentView(
        durationMs: chatInteger(data['durationMs'], 'durationMs'),
      ),
      'events' => ThreadWaitEventsIntentView(
        timeoutMs: chatInteger(data['timeoutMs'], 'timeoutMs'),
        targets: [
          for (final entry in data['targets'] as List)
            _waitTarget(chatObject(entry, 'wait.target')),
        ],
      ),
      _ => throw const FormatException('未知 wait.intent'),
    },
  );
}

ThreadWaitTargetView _waitTarget(Map<String, Object?> value) =>
    ThreadWaitTargetView(
      taskId: chatString(value['taskId'], 'taskId'),
      toolName: chatOptionalString(value['toolName'], 'toolName'),
      summary: chatOptionalString(value['summary'], 'summary'),
      summaryTruncated: value['summaryTruncated'] as bool? ?? false,
      status: value['status'] == null
          ? null
          : chatEnum(
              ThreadWaitTargetStatusView.values,
              value['status'],
              'target.status',
            ),
    );
