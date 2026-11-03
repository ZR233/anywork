import 'dart:convert';
import 'dart:developer' as developer;

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_code_block.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/chat_item_presentation.dart';
import '../state/chat_payload_reading.dart';
import 'content_layout_witness.dart';
import 'timeline_activity_row.dart';
import 'timeline_plain_text.dart';
import 'timeline_tool_blocks.dart';
import 'timeline_wait_blocks.dart';
import 'timeline_display_unit_view.dart';
import 'timeline_content_range_view.dart';

typedef ChatContentRangeBuilder = Widget Function(
  String itemId,
  String contentKey,
  String label,
  ContentRef reference,
  Widget Function(String text, Widget child) witness,
);

/// Renders one admitted item or display unit. Grouping belongs to the sole
/// presentation owner; this view owns only disclosure and decoded presentation.
class ChatItemView extends StatefulWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.bodyBuilder,
    this.contentRangeBuilder,
    this.attachmentBuilder,
    this.monotonicMicros,
    this.onContentLayout,
    this.isDisplayActive,
    this.onLoadEarlierGroup,
  });
  final ChatItemPresentation item;
  final Widget Function(String id, String text)? bodyBuilder;
  final ChatContentRangeBuilder? contentRangeBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final int Function()? monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros)?
  onContentLayout;
  final bool Function()? isDisplayActive;
  final Future<void> Function()? onLoadEarlierGroup;
  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  ChatItemPresentation get item => widget.item;
  Set<int> get _sensitiveQuestions {
    final input = item.data['userInput'];
    if (item.type != 'tool' || input is! Map<String, Object?>) return const {};
    final questions = input['questions'];
    if (questions is! List) return const {};
    final state = input['state'];
    final answers = state is Map<String, Object?> ? state['answers'] : null;
    return {
      for (var i = 0; i < questions.length; i++)
        if (questions[i] case final Map<String, Object?> question)
          if (question['isSecret'] == true ||
              (answers is List &&
                  answers.any(
                    (answer) =>
                        answer is Map<String, Object?> &&
                        answer['questionId'] == question['id'] &&
                        answer['redacted'] == true,
                  )))
            i,
    };
  }

  Iterable<ChatBodyPresentation> get _publicBodies {
    final sensitive = _sensitiveQuestions;
    return item.bodies.where((body) {
      final index = RegExp(r'^tool\.user-input\.(?:question|answer)\.(\d+)\.')
          .firstMatch(body.key)
          ?.group(1);
      return index == null || !sensitive.contains(int.parse(index));
    });
  }

  Widget _publicEnvelope() => _sensitiveQuestions.isEmpty
      ? SelectableText(item.raw ?? '')
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('敏感字段已隐藏，仅展示公开 metadata'),
            _metadata({
              'type': item.type,
              if (item.data['userInput']
                  case final Map<String, Object?> userInput)
                'userInput': {
                  'interactionId': userInput['interactionId'],
                  'questionCount': userInput['questions'] is List
                      ? (userInput['questions'] as List).length
                      : 0,
                  if (userInput['state'] case final Map<String, Object?> state)
                    'state': {'kind': state['kind']},
                },
            }),
          ],
        );
  @override
  Widget build(BuildContext context) {
    if (item.isKnownEmptyText) return const SizedBox.shrink();
    if (item.displayUnit case final unit?) {
      return KeyedSubtree(
        key: ValueKey('chat-item:${unit.id}'),
        child: TimelineDisplayUnitView(
          key: ValueKey(unit.id),
          unit: unit,
          onLoadEarlier: widget.onLoadEarlierGroup,
          memberBuilder: (atom) => atom.payload == null
              ? const Text('内容状态未知')
              : ChatItemView(
                  key: ValueKey(atom.id),
                  item: ChatItemPresentation.decode(atom),
                  bodyBuilder: widget.bodyBuilder,
                  contentRangeBuilder: widget.contentRangeBuilder,
                  attachmentBuilder: widget.attachmentBuilder,
                  isDisplayActive: widget.isDisplayActive,
                  monotonicMicros: widget.monotonicMicros,
                  onContentLayout: widget.onContentLayout,
                ),
        ),
      );
    }
    developer.Timeline.instantSync(
      'conversation.row.build',
      arguments: {'itemId': item.id},
    );
    if (item.reference case final reference?) {
      return widget.contentRangeBuilder?.call(
            item.id,
            'payload',
            '按需查看原文 · ${item.byteLength} 字节',
            reference,
            _contentWitness,
          ) ??
          const Text('内容读取尚未就绪');
    }
    if (item.compatibility != ChatItemCompatibility.current) {
      return _unavailable(
        item.compatibility == ChatItemCompatibility.unknown
            ? '未知内容格式'
            : '内容格式错误',
        item.diagnostic,
      );
    }
    Widget content;
    try {
      content = _content(context);
    } on FormatException catch (error) {
      content = _unavailable('内容格式错误', error.message);
    }
    return ConstrainedBox(
      key: ValueKey('chat-item:${item.id}'),
      constraints: const BoxConstraints(minHeight: 28),
      child: Material(type: MaterialType.transparency, child: content),
    );
  }

  Widget _content(BuildContext context) => switch (item.type) {
    'text' => _text(context),
    'thinking' => _thinking(context),
    'tool' => _tool(context),
    'turn' => _turn(context),
    'plan' => _plan(context),
    'skill' => _record(
      Icons.auto_awesome_outlined,
      chatString(
        chatObject(item.data['activation'], 'skill.activation')['name'],
        'skill.activation.name',
      ),
      item.data,
    ),
    'file' => _record(
      Icons.description_outlined,
      chatString(item.data['path'], 'file.path'),
      item.data,
    ),
    'agent' => _agent(context),
    'inference' => _inference(context),
    'contextCompaction' => TimelineActivityRow(
      icon: Icons.compress_outlined,
      label: context.l10n.timelineContextCompacted,
      expandable: false,
    ),
    'raw' => _raw(context),
    _ => _unavailable('未知内容类别：${item.type}', null),
  };
  Widget _text(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (item.data['channel'] == 'parentAgent')
        Text(
          context.l10n.timelineParentAgent,
          key: StudioDriverKeys.parentAgentLabel(item.id),
          style: context.text.bodySmall,
        ),
      for (final body in item.bodies) _body(body),
      _media(),
      // The independent Turn receipt owns terminal reasons. Accepted partial
      // text stays readable without repeating its failure/stop diagnostics.
    ],
  );
  Widget _thinking(BuildContext context) {
    final outcome = item.data['outcome'];
    final state = outcome is Map<String, Object?> ? outcome['kind'] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineActivityRow(
          icon: state == 'cancelled'
              ? Icons.stop_circle_outlined
              : Icons.psychology_alt_outlined,
          isIssue: state == 'failed' || state == 'budgetLimited',
          label: switch (state) {
            'failed' => '思考失败',
            'cancelled' => '思考已停止',
            _ => context.l10n.timelineReasoningEnded,
          },
          expandable: false,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: TimelineActivityRow.contentIndent,
          ),
          child: TimelineBodyReadIntent(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final body in item.bodies) _body(body),
                _outcomeNotice(item.data['outcome']),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tool(BuildContext context) {
    final input = item.data['userInput'];
    if (input != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _questionReceipt(context, chatObject(input, 'userInput')),
          _media(),
        ],
      );
    }
    final reading = item.toolCard;
    final Widget card;
    if (reading is DecodedToolCard) {
      final tool = reading.value;
      final identity = item.atom?.tool;
      if (identity != null && identity.callId != tool.toolCallId) {
        return _unavailable('工具内容身份不一致', '声明的调用身份与完成载荷不同');
      }
      final contents = item.atom?.contents
          .where(
            (content) =>
                content.role == ChatContentRole.toolArguments ||
                content.role == ChatContentRole.toolOutput,
          )
          .toList();
      final details = TimelineToolDetails(
        item: tool,
        declaredContents: contents == null || contents.isEmpty
            ? null
            : [
                for (final content in contents)
                  widget.contentRangeBuilder?.call(
                        item.id,
                        content.role.name,
                        content.role == ChatContentRole.toolArguments
                            ? '工具参数'
                            : '工具输出',
                        content.reference,
                        _contentWitness,
                      ) ??
                      const Text('内容读取尚未就绪'),
                if (tool.error != null) Text(tool.error!),
              ],
      );
      card = TimelineActivityTileTheme(
        child: tool.wait != null
            ? TimelineWaitPanel(
                identity: item.id,
                presentation: tool.wait!,
                diagnostics: details,
              )
            : timelineIsWebSearch(tool) &&
                  (contents == null || contents.isEmpty)
            ? TimelineWebSearchToolCard(item: tool)
            : details,
      );
    } else {
      final unavailable = reading as UnavailableToolCard;
      final invocation = item.data['invocation'];
      final name =
          invocation is Map<String, Object?> && invocation['name'] is String
          ? invocation['name'] as String
          : '工具调用';
      final label = switch (unavailable.kind) {
        ToolCardUnavailableKind.unknownContract => '$name · 未知展示格式',
        ToolCardUnavailableKind.malformed => '$name · 内容格式错误',
        ToolCardUnavailableKind.deferred => '$name · 正文按需读取',
      };
      card = _unavailable(label, unavailable.reason);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        _media(),
        // References are explicit producer entries; no private receipt or arbitrary
        // JSON-field search is used to discover a body.
      ],
    );
  }

  Widget _turn(BuildContext context) {
    final outcome = chatObject(item.data['outcome'], 'turn.outcome');
    final state = chatString(outcome['kind'], 'turn.outcome.kind');
    final title = switch (state) {
      'completed' => '轮次已完成',
      'failed' => '轮次失败',
      'cancelled' || 'interrupted' => context.l10n.timelineTurnStopped,
      'budgetLimited' => '轮次达到预算上限',
      _ => '轮次 · $state',
    };
    return _disclosure(
      state == 'cancelled' || state == 'interrupted'
          ? Icons.stop_circle_outlined
          : Icons.account_tree_outlined,
      title,
      [_outcomeNotice(outcome), _rawRecord()],
      issue: state == 'failed' || state == 'budgetLimited',
    );
  }

  Widget _plan(BuildContext context) {
    final decision = chatString(item.data['decision'], 'plan.decision');
    final label = switch (decision) {
      'approved' => context.l10n.planReceiptApproved,
      'revisionRequested' => context.l10n.planReceiptRevisionRequested,
      'cancelled' => context.l10n.planReceiptCancelled,
      'resolved' => context.l10n.planReceiptAnswered,
      _ => '计划 · $decision',
    };
    final version = item.data['documentVersion'];
    final summary = version is int ? '$label · v$version' : label;
    return KeyedSubtree(
      key: StudioDriverKeys.timelinePlanReceipt(item.id),
      child: _disclosure(Icons.checklist_rtl, summary, [
        for (final body in item.bodies) _body(body),
        _rawRecord(),
      ]),
    );
  }

  Widget _questionReceipt(BuildContext context, Map<String, Object?> input) {
    final state = chatObject(input['state'], 'userInput.state');
    final questions = input['questions'];
    if (questions is! List) throw const FormatException('questions 必须是数组');
    final answers = state['answers'] is List
        ? state['answers'] as List
        : const [];
    final title = state['kind'] == 'cancelled'
        ? context.l10n.timelineUserInputCancelled
        : context.l10n.timelineUserInputAnswered;
    return KeyedSubtree(
      key: StudioDriverKeys.timelineUserInput(item.id),
      child: _disclosure(
        Icons.question_answer_outlined,
        '$title · ${questions.length} 个问题',
        [
          for (var index = 0; index < questions.length; index++)
            _question(
              context,
              chatObject(questions[index], 'question'),
              index,
              answers,
            ),
          _rawRecord(),
        ],
      ),
    );
  }

  Widget _question(
    BuildContext context,
    Map<String, Object?> question,
    int index,
    List answers,
  ) {
    final id = chatString(question['id'], 'question.id');
    final answer = answers
        .where(
          (value) => value is Map<String, Object?> && value['questionId'] == id,
        )
        .firstOrNull;
    final redacted =
        question['isSecret'] == true ||
        (answer is Map<String, Object?> && answer['redacted'] == true);
    if (redacted) {
      return const Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('敏感内容已隐藏'),
      );
    }
    // The producer uses null for an absent option list, distinct from an
    // explicitly empty list. Neither has option bodies to display.
    final optionCount = question['optionCount'] == null
        ? 0
        : chatInteger(question['optionCount'], 'question.optionCount');
    final answerCount = answer == null
        ? 0
        : chatInteger(answer['answerCount'], 'answer.answerCount');
    if (optionCount < 0 || answerCount < 0) {
      throw const FormatException('问题选项和回答数量不能为负数');
    }
    // Every declared option/answer has a body entry, including empty text.
    // Reject impossible counts before constructing widgets from metadata.
    if (optionCount > item.bodies.length || answerCount > item.bodies.length) {
      throw const FormatException('问题选项和回答数量超出正文清单');
    }
    final questionKey = 'tool.user-input.question.$index';
    Iterable<ChatBodyPresentation> field(String key) =>
        item.bodies.where((body) => body.key == key);
    final labelStyle = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('问题 ${index + 1}', style: context.text.titleSmall),
          for (final key in ['$questionKey.header', '$questionKey.body'])
            for (final body in field(key)) _body(body),
          if (optionCount > 0) ...[
            const SizedBox(height: 6),
            Text('可选项', style: labelStyle),
            for (var option = 0; option < optionCount; option++)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${option + 1}. ', style: labelStyle),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final key in [
                            '$questionKey.option.$option.label',
                            '$questionKey.option.$option.description',
                          ])
                            for (final body in field(key)) _body(body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (answer != null) ...[
            const SizedBox(height: 6),
            Text('实际回答', style: labelStyle),
            for (var value = 0; value < answerCount; value++)
              for (final body in field('tool.user-input.answer.$index.$value'))
                _body(body),
          ],
        ],
      ),
    );
  }

  Widget _agent(BuildContext context) {
    final identity = chatObject(item.data['identity'], 'agent.identity');
    final outcome = chatObject(item.data['outcome'], 'agent.outcome');
    return _disclosure(
      Icons.smart_toy_outlined,
      '${identity['role'] ?? '智能体'} · ${outcome['kind'] ?? '未知状态'}',
      [_metadata(identity), _outcomeNotice(outcome), _rawRecord()],
      issue: outcome['kind'] == 'failed' || outcome['kind'] == 'denied',
    );
  }

  Widget _inference(BuildContext context) {
    final model = chatString(item.data['model'], 'inference.model');
    final outcome = chatObject(item.data['outcome'], 'inference.outcome');
    return _disclosure(
      Icons.model_training_outlined,
      '$model · ${outcome['kind'] ?? '未知状态'}',
      [_metadata(item.data), _outcomeNotice(outcome), _rawRecord()],
      issue: outcome['kind'] == 'failed',
    );
  }

  Widget _raw(BuildContext context) {
    if (item.data['origin'] == 'runtimeControl') {
      // This typed producer origin never held user input. Do not infer it from
      // notice text/payload shape or offer its envelope as historical content.
      return TimelineActivityRow(
        icon: Icons.info_outline,
        label: context.l10n.timelineRuntimeNotice,
        tooltip: context.l10n.timelineRuntimeNoticeDetail,
        expandable: false,
      );
    }
    return _disclosure(
      Icons.data_object_outlined,
      item.data['notice'] is String ? item.data['notice'] as String : '原始内容',
      [for (final body in item.bodies) _body(body, code: true), _rawRecord()],
    );
  }

  Widget _record(IconData icon, String title, Map<String, Object?> data) =>
      _disclosure(icon, title, [
        _metadata(data),
        for (final body in item.bodies) _body(body),
        _rawRecord(),
      ]);
  Widget _metadata(Object? value) => StudioCodeBlock(
    text: const JsonEncoder.withIndent('  ').convert(value),
    maxHeight: 240,
  );
  Widget _outcomeNotice(Object? value) {
    if (value == null) return const SizedBox.shrink();
    final outcome = chatObject(value, 'outcome');
    final kind = outcome['kind'];
    final data = outcome['data'];
    if (kind == 'completed' || kind == 'succeeded') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${kind ?? '未知状态'}', style: context.text.bodySmall),
          if (data != null) _metadata(data),
        ],
      ),
    );
  }

  Widget _media() =>
      widget.attachmentBuilder?.call(item) ?? const SizedBox.shrink();

  Widget _rawRecord() => Material(
    type: MaterialType.transparency,
    child: TimelineActivityTileTheme(
      child: TimelineActivityDisclosure(
        titleBuilder: (context, expanded) => TimelineActivityRow(
          icon: Icons.data_object_outlined,
          label: '公开原始记录',
          expanded: expanded,
        ),
        children: [
          for (final body in _publicBodies) _body(body, code: true),
          _publicEnvelope(),
        ],
      ),
    ),
  );
  Widget _unavailable(String title, String? diagnostic) => _disclosure(
    Icons.info_outline,
    title,
    [
      if (diagnostic != null) Text(diagnostic),
      for (final body in _publicBodies) _body(body, code: item.type == 'tool'),
      _publicEnvelope(),
    ],
  );
  Widget _disclosure(
    IconData icon,
    String title,
    List<Widget> children, {
    bool issue = false,
  }) => TimelineActivityTileTheme(
    child: TimelineActivityDisclosure(
      key: ValueKey(('item-disclosure', item.id)),
      titleBuilder: (context, expanded) => TimelineActivityRow(
        icon: icon,
        label: title,
        isIssue: issue,
        expanded: expanded,
      ),
      children: children,
    ),
  );
  Widget _body(ChatBodyPresentation body, {bool code = false}) {
    if (body.reference case final reference?) {
      return widget.contentRangeBuilder?.call(
            item.id,
            body.key,
            '${body.key} · ${body.byteLength} 字节',
            reference,
            _contentWitness,
          ) ??
          Text('${body.key} · 内容读取尚未就绪');
    }
    final bytes = body.inline;
    if (bytes == null) return Text('${body.key} · 未提供内容或引用');
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (error) {
      return Text('${body.key} · ${error.message}');
    }
    final id = '${item.id}:${body.key}';
    final child = code
        ? StudioCodeBlock(text: text, maxHeight: 280)
        : widget.bodyBuilder?.call(id, text) ??
              TimelinePlainText(id: id, text: text);
    return _contentWitness(text, child);
  }

  Widget _contentWitness(String text, Widget child) {
    final clock = widget.monotonicMicros;
    final onLayout = widget.onContentLayout;
    if (text.trim().isEmpty || clock == null || onLayout == null) return child;
    return ContentLayoutWitness(
      itemId: item.id,
      monotonicMicros: clock,
      onContentLayout: onLayout,
      isDisplayActive: widget.isDisplayActive,
      child: child,
    );
  }
}
