import 'dart:convert';
import 'dart:developer' as developer;

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_code_block.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../connectors/timeline_owned_body_connector.dart';
import '../state/chat_item_presentation.dart';
import '../state/chat_payload_reading.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_unit.dart';
import '../state/tool_presentation.dart';
import '../tools/tool_item_registry.dart';
import '../tools/tool_item_view.dart';
import '../views/plan_receipt_view.dart';
import 'timeline_content_range_view.dart';
import 'content_layout_witness.dart';
import 'timeline_activity_row.dart';
import 'timeline_plain_text.dart';
import 'timeline_reasoning_view.dart';
import 'timeline_display_unit_view.dart';

/// Renders one admitted item or display unit. Grouping belongs to the sole
/// presentation owner; this view owns only disclosure and decoded presentation.
class ChatItemView extends StatefulWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.bodyBuilder,
    this.attachmentBuilder,
    this.monotonicMicros,
    this.onContentLayout,
    this.onCurrentContentLayout,
    this.onCurrentContentUnmounted,
    this.isDisplayActive,
    this.groupMembersBuilder,
    this.onExpansionChanged,
    this.initiallyExpanded = false,
    this.promptBubble = false,
  });
  final ChatItemPresentation item;
  final Widget Function(String id, String text)? bodyBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final int Function()? monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros)?
  onContentLayout;
  final void Function(String itemId, int layoutCompletedMicros)?
  onCurrentContentLayout;
  final void Function(String itemId)? onCurrentContentUnmounted;
  final bool Function()? isDisplayActive;
  final Widget Function(TimelineDisplayUnit unit)? groupMembersBuilder;
  final ValueChanged<bool>? onExpansionChanged;
  final bool initiallyExpanded;
  final bool promptBubble;
  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  final Object _unitVisibility = Object();
  TimelineExpansionIntent? _visibleUnitExpansion;

  ChatItemPresentation get item => widget.item;
  @override
  void initState() {
    super.initState();
    _syncUnitVisibility();
  }

  @override
  void didUpdateWidget(covariant ChatItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncUnitVisibility();
  }

  void _syncUnitVisibility() {
    final unit = item.displayUnit;
    final next = unit?.body is SingleDisplayBlock ? unit!.expansion : null;
    if (identical(next, _visibleUnitExpansion)) return;
    _visibleUnitExpansion?.setBodyVisible(_unitVisibility, false);
    _visibleUnitExpansion = next;
    next?.setBodyVisible(_unitVisibility, true);
  }

  @override
  void dispose() {
    _visibleUnitExpansion?.setBodyVisible(_unitVisibility, false);
    super.dispose();
  }

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

  Iterable<ChatBodyPresentation> get _textBodies {
    final atom = item.atom;
    if (atom == null) {
      // Payload-only known Input/parent text is also used by official previews.
      // Its canonical text field is body, not every retained content domain.
      return switch (item.data['channel']) {
        'user' ||
        'parentAgent' => item.bodies.where((body) => body.key == 'body'),
        _ => item.bodies,
      };
    }
    if (atom.source is! InputChatSource &&
        atom.source is! InboxMessageChatSource) {
      // Model text can use part.outputText.N. Do not reinterpret its manifest.
      return item.bodies;
    }
    if (item.historyEventId != null) {
      return item.bodies.where((body) => body.key == 'body');
    }
    final keys = {
      for (final content in item.currentContents)
        if (content.role == ChatContentRole.body) content.reference.contentKey,
    };
    return item.bodies.where((body) => keys.contains(body.key));
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
    var content = _buildContent(context);
    final unit = item.displayUnit;
    if (unit?.body is SingleDisplayBlock) {
      content = TimelineGroupBodyIntent(
        intent: unit!.expansion,
        child: content,
      );
    }
    return widget.promptBubble ? content : _withParentLabel(content);
  }

  Widget _withParentLabel(Widget content) {
    if (item.authorId != 'parentAgent') return content;
    // Identity is independent of payload availability. Keep the same read
    // widgets below it when metadata or body ranges have not arrived yet.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.timelineParentAgent,
          key: StudioDriverKeys.parentAgentLabel(item.id),
          style: context.text.bodySmall,
        ),
        content,
      ],
    );
  }

  Widget _promptBubble(Widget content) {
    if (!widget.promptBubble) return content;
    return DecoratedBox(
      key: ValueKey('timeline-prompt-bubble:${item.id}'),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(16),
          topEnd: Radius.circular(16),
          bottomStart: Radius.circular(16),
          bottomEnd: Radius.circular(4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: _withParentLabel(content),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (item.observationUnavailable) {
      final record = item.displayRecord!;
      return _promptBubble(
        Text(
          record.startFact != null && record.endFact == null
              ? '旧边界观察不可用 · 封存时尚未结束'
              : '旧边界观察不可用',
        ),
      );
    }
    if (item.hasPublicInputBody) {
      // This branch and its Body positions remain the same while metadata is
      // pending, restricted, or resolved. Metadata never replaces the read owner.
      return _textLayout(
        item.publicInputBodyIndices,
        (index, frame) => _declaredContent(item.atom!, index, frameBody: frame),
        trailing: _publicInputMedia(),
      );
    }
    if (item.finalEmptyAfterContent) {
      return _promptBubble(const Text('该输出的最终内容为空'));
    }
    if (item.isKnownEmptyText) return const SizedBox.shrink();
    final unit = item.displayUnit;
    if (unit != null && item.type == 'displayUnit') {
      if (unit.body is SingleDisplayBlock) {
        final atom = unit.atom!;
        return _textLayout(
          [
            for (var index = 0; index < item.currentContents.length; index++)
              index,
          ],
          (index, frame) => _declaredContent(atom, index, frameBody: frame),
          leading: item.currentContents.isEmpty ? const Text('内容状态未知') : null,
        );
      }
      return KeyedSubtree(
        key: ValueKey('chat-item:${unit.id}'),
        child: TimelineDisplayUnitView(
          key: ValueKey(unit.id),
          unit: unit,
          childBuilder: (_) =>
              widget.groupMembersBuilder?.call(unit) ?? const Text('成员读取尚未就绪'),
        ),
      );
    }
    developer.Timeline.instantSync(
      'conversation.row.build',
      arguments: {'itemId': item.id},
    );
    if (item.compatibility != ChatItemCompatibility.current) {
      return _promptBubble(
        _unavailable(
          item.compatibility == ChatItemCompatibility.unknown
              ? '未知内容格式'
              : '内容格式错误',
          item.diagnostic,
        ),
      );
    }
    Widget content;
    try {
      content = _content(context);
      if (item.type != 'text') content = _promptBubble(content);
    } on FormatException catch (error) {
      content = _promptBubble(_unavailable('内容格式错误', error.message));
    }
    return Material(
      key: ValueKey('chat-item:${item.id}'),
      type: MaterialType.transparency,
      child: content,
    );
  }

  Widget _publicInputMedia() {
    if (item.compatibility != ChatItemCompatibility.current) {
      return const SizedBox.shrink();
    }
    try {
      if (item.type != 'text') {
        throw const FormatException('Input metadata must be text');
      }
      return _media();
    } on FormatException {
      // A malformed metadata domain cannot take the independently declared
      // public Body down with it, or expose the original envelope as a fallback.
      return const Text('完成内容格式无法解析');
    }
  }

  Widget _content(BuildContext context) => switch (item.type) {
    'text' => _text(),
    'thinking' => _thinking(context),
    'tool' => item.presentsFiles ? _media() : _tool(context),
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
  Widget _text() => _textLayout(
    _textBodies.toList(growable: false),
    (body, frame) => _body(
      body,
      disclosed: true,
      showCopy: _showTextCopy(frame),
      frameBody: frame,
    ),
    leading: switch (item.atom?.source) {
      InboxMessageChatSource(:final sourceId)
          when item.authorId != 'parentAgent' =>
        Text('来源 · $sourceId'),
      _ => null,
    },
    trailing: _media(),
  );

  /// An input's single Body owns its footer. Frame the content and attachments
  /// together, allowing the same reader to lay out its actions below the frame.
  Widget _textLayout<T>(
    List<T> bodies,
    Widget Function(T body, Widget Function(Widget)? frame) buildBody, {
    Widget? leading,
    Widget? trailing,
  }) {
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?leading, ...children, ?trailing],
    );
    if (widget.promptBubble && bodies.length == 1) {
      return buildBody(bodies.single, (body) => _promptBubble(column([body])));
    }
    return _promptBubble(
      column([for (final body in bodies) buildBody(body, null)]),
    );
  }

  bool _showTextCopy(Widget Function(Widget)? frame) =>
      item.showsTextCopy && (!widget.promptBubble || frame != null);

  Widget _thinking(BuildContext context) {
    final outcome = item.data['outcome'];
    final state = outcome is Map<String, Object?> ? outcome['kind'] : null;
    final nonemptyBodies = item.bodies.where(
      (body) =>
          body.byteLength > 0 &&
          (body.text?.trim().isNotEmpty ?? body.hasReference),
    );
    final summaries = nonemptyBodies
        .where((body) => body.key.startsWith('part.summaryText.'))
        .toList();
    final bodies = nonemptyBodies
        .where((body) => !body.key.startsWith('part.summaryText.'))
        .toList();
    final inlineSummary = summaries.every((body) => body.hasInline);
    final summary = inlineSummary
        ? summaries.map((body) => body.text!).join(' ')
        : null;
    final atom = item.atom;
    return TimelineReasoningView(
      summary: summary,
      summaryBuilder: inlineSummary
          ? null
          : (fallback) => Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                for (final body in summaries)
                  Flexible(child: _reasoningSummary(body, fallback)),
              ],
            ),
      startedAt: item.displayRecord == null
          ? atom?.startedAt
          : item.displayRecord!.displayStartedAt,
      finishedAt: item.displayRecord == null
          ? atom?.finishedAt
          : item.displayRecord!.displayObservedThrough,
      outcome:
          (state is String ? state : null) ??
          switch (atom?.lifecycle) {
            TerminalChatAtom(:final outcome) => outcome.name,
            _ => null,
          },
      diagnostic: state == null || state == 'completed'
          ? null
          : const JsonEncoder.withIndent('  ').convert(outcome),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      body: bodies.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final body in bodies)
                  _body(body, disclosed: true, showCopy: false),
                _outcomeNotice(outcome),
              ],
            ),
    );
  }

  Widget _reasoningSummary(ChatBodyPresentation body, String fallback) {
    if (body.text case final text?) {
      return TimelineReasoningSummary(text: text);
    }
    return TimelineBodyReadIntent(
      key: ValueKey(body.key),
      summary: true,
      child: TimelineOwnedBodyConnector(
        itemId: item.id,
        contentKey: body.key,
        label: fallback,
        historyReference: body.historyReference,
        currentReference: body.currentReference,
        witness: _contentWitness,
      ),
    );
  }

  Widget _tool(BuildContext context, {String? arguments}) {
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
    final argumentBody = item.body('tool.arguments');
    // A mounted historical tool needs its small semantic input to build the
    // same card as Current. Large inputs keep their explicit bounded reader.
    // The existing body owner revokes this read with the enclosing Work.
    if (arguments == null &&
        argumentBody?.historyReference != null &&
        argumentBody!.byteLength <= 64 * 1024 &&
        argumentBody.byteLength == argumentBody.historyReference!.byteLength) {
      return TimelineOwnedBodyConnector(
        itemId: item.id,
        contentKey: argumentBody.key,
        label: context.l10n.timelineToolArguments,
        historyReference: argumentBody.historyReference,
        disclosed: true,
        witness: (_, child) => child,
        bodyBuilder: (text) =>
            utf8.encode(text).length == argumentBody.byteLength
            ? _tool(context, arguments: text)
            : _unavailable(
                context.l10n.timelineToolArgumentsIncompleteTitle,
                context.l10n.timelineToolArgumentsIncompleteDetail,
              ),
      );
    }
    final reading = arguments == null
        ? item.toolCard
        : readToolCard(item, arguments: arguments);
    final Widget card;
    if (reading is DecodedToolCard) {
      final tool = reading.value;
      final identity = item.atom?.tool;
      if (identity != null && identity.callId != tool.toolCallId) {
        return _unavailable(
          context.l10n.timelineToolIdentityMismatchTitle,
          context.l10n.timelineToolIdentityMismatchDetail,
        );
      }
      final declaredContents = [
        for (final content in item.currentContents)
          if (content.role == ChatContentRole.toolArguments ||
              content.role == ChatContentRole.toolOutput)
            (
              role: content.role,
              key: content.reference.contentKey,
              current: content.reference,
              history: null as HistoryEventBodyRef?,
            ),
        for (final body in item.bodies)
          if (body.historyReference != null &&
              (body.key == 'tool.arguments' || body.key == 'tool.result'))
            (
              role: body.key == 'tool.arguments'
                  ? ChatContentRole.toolArguments
                  : ChatContentRole.toolOutput,
              key: body.key,
              current: null as CurrentContentRef?,
              history: body.historyReference,
            ),
      ];
      final hasDeclaredBodies = declaredContents.isNotEmpty;
      final wait = item.atom?.wait ?? tool.wait;
      final effectiveTool = wait == null || tool.wait != null
          ? tool
          : TimelineToolPresentation(
              id: tool.id,
              toolCallId: tool.toolCallId,
              name: tool.name,
              presentationContract: tool.presentationContract,
              statusString: tool.statusString,
              arguments: tool.arguments,
              output: tool.output,
              createdAt: tool.createdAt,
              completedAt: tool.completedAt,
              error: tool.error,
              taskId: tool.taskId,
              workingDirectory: tool.workingDirectory,
              exitCode: tool.exitCode,
              timedOut: tool.timedOut,
              attachments: tool.attachments,
              outputArtifacts: tool.outputArtifacts,
              wait: wait,
              executionPresent: tool.executionPresent,
              frozenObservation: tool.frozenObservation,
            );
      final adapter = timelineToolItemRegistry.resolveForPresentation(
        effectiveTool,
      );
      final outputReference = declaredContents
          .where((content) => content.role == ChatContentRole.toolOutput)
          .firstOrNull;
      // 只有补丁／文件内容读取输入窗口，查询等纯语义输入已在内联参数中。
      final contents = declaredContents
          .where(
            (content) => switch (content.role) {
              ChatContentRole.toolArguments =>
                adapter.bodyPolicy.readsArgumentsWindow,
              ChatContentRole.toolOutput => adapter.readsOutput(
                effectiveTool.statusString,
                output: effectiveTool.output,
              ),
              _ => false,
            },
          )
          .toList();
      card = TimelineToolItemView(
        item: effectiveTool,
        initiallyExpanded: widget.initiallyExpanded,
        staticObservation:
            item.displayRecord?.contentSource is FrozenObservation,
        onExpansionChanged: widget.onExpansionChanged,
        markdownBuilder: widget.bodyBuilder,
        additionalContentBuilder: item.attachments.isEmpty
            ? null
            : (_) => _media(),
        declaredContentIdentity: hasDeclaredBodies
            ? (
                outputReference == null
                    ? null
                    : outputReference.current != null
                    ? currentContentIdentity(outputReference.current!)
                    : historyBodyIdentity(outputReference.history!),
                hasDeclaredBodies,
              )
            : null,
        declaredContentBuilder: !hasDeclaredBodies
            ? null
            : (onOutputRead, acceptance) => [
                for (final content in contents)
                  TimelineBodyReadIntent(
                    scrollable: true,
                    onRead: content.role == ChatContentRole.toolOutput
                        ? onOutputRead
                        : null,
                    bodyBuilder: (text) => timelineToolWindowBody(
                      context,
                      effectiveTool,
                      text,
                      input: content.role == ChatContentRole.toolArguments,
                      markdownBuilder: widget.bodyBuilder,
                      acceptance: acceptance,
                    ),
                    child: TimelineOwnedBodyConnector(
                      itemId: item.id,
                      contentKey: content.key,
                      label: content.role == ChatContentRole.toolArguments
                          ? context.l10n.timelineToolArguments
                          : context.l10n.timelineToolOutput,
                      currentReference: content.current,
                      historyReference: content.history,
                      witness: _contentWitness,
                    ),
                  ),
              ],
      );
    } else {
      final unavailable = reading as UnavailableToolCard;
      final invocation = item.data['invocation'];
      final name =
          invocation is Map<String, Object?> && invocation['name'] is String
          ? invocation['name'] as String
          : context.l10n.timelineToolCallFallback;
      final label = switch (unavailable.kind) {
        ToolCardUnavailableKind.malformed =>
          context.l10n.timelineToolMalformedLabel(name),
        ToolCardUnavailableKind.deferred =>
          context.l10n.timelineToolDeferredLabel(name),
      };
      final detail = switch (unavailable.kind) {
        ToolCardUnavailableKind.deferred =>
          context.l10n.timelineToolDeferredReason,
        ToolCardUnavailableKind.malformed =>
          unavailable.detail != null
              ? context.l10n.timelineToolParseFailed(unavailable.detail!)
              : unavailable.reason,
      };
      card = _unavailable(label, detail);
    }
    return card;
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
      _ => '${context.l10n.statusPlanEntry} · $decision',
    };
    final icon = switch (decision) {
      'approved' => Icons.check,
      'revisionRequested' => Icons.edit_outlined,
      'cancelled' => Icons.close,
      _ => Icons.description_outlined,
    };
    final version = item.data['documentVersion'];
    return PlanReceiptView(
      key: StudioDriverKeys.timelinePlanReceipt(item.id),
      label: label,
      icon: icon,
      documentVersion: version is int ? version : null,
      children: [
        for (final body in item.bodies) _body(body, disclosed: true),
        _rawRecord(),
      ],
    );
  }

  Widget _questionReceipt(BuildContext context, Map<String, Object?> input) {
    final state = chatObject(input['state'], 'userInput.state');
    final questions = input['questions'];
    if (questions is! List) throw const FormatException('questions 必须是数组');
    final answers = state['answers'] is List
        ? state['answers'] as List
        : const [];
    final title = switch (state['kind']) {
      'pending' => '等待用户回答',
      'cancelled' => context.l10n.timelineUserInputCancelled,
      _ => context.l10n.timelineUserInputAnswered,
    };
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
            for (final body in field(key)) _body(body, disclosed: true),
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
                            for (final body in field(key))
                              _body(body, disclosed: true),
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
                _body(body, disclosed: true),
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
    horizontalScroll: false,
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
      if (item.type == 'tool') Builder(builder: (_) => _media()),
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
      initiallyExpanded: item.type == 'tool' && widget.initiallyExpanded,
      onExpansionChanged: item.type == 'tool'
          ? widget.onExpansionChanged
          : null,
      titleBuilder: (context, expanded) => TimelineActivityRow(
        icon: icon,
        label: title,
        isIssue: issue,
        expanded: expanded,
      ),
      children: children,
    ),
  );
  Widget _declaredContent(
    ChatAtom atom,
    int index, {
    Widget Function(Widget)? frameBody,
  }) {
    final id = '${item.id}:content-$index';
    final content = index < item.currentContents.length
        ? item.currentContents[index]
        : null;
    if (content == null) {
      const missing = Text('内容引用缺失');
      return frameBody?.call(missing) ?? missing;
    }
    final isTextBody =
        content.role == ChatContentRole.body &&
        (atom.kind == ChatAtomKind.text || atom.kind == ChatAtomKind.input);
    final range = TimelineOwnedBodyConnector(
      itemId: item.id,
      contentKey: content.reference.contentKey,
      label: '查看内容',
      currentReference: content.reference,
      disclosed: isTextBody,
      showCopy: !isTextBody || _showTextCopy(frameBody),
      frameBody: frameBody,
      witness: _contentWitness,
    );
    return isTextBody
        ? TimelineBodyReadIntent(
            bodyBuilder: (text) =>
                widget.bodyBuilder?.call(id, text) ??
                TimelinePlainText(id: id, text: text),
            child: range,
          )
        : range;
  }

  Widget _body(
    ChatBodyPresentation body, {
    bool code = false,
    bool disclosed = false,
    bool showCopy = true,
    Widget Function(Widget)? frameBody,
  }) {
    final id = '${item.id}:${body.key}';
    Widget render(String text) => code
        ? StudioCodeBlock(text: text, horizontalScroll: false)
        : widget.bodyBuilder?.call(id, text) ??
              TimelinePlainText(id: id, text: text);
    if (!body.hasInline &&
        (body.historyReference != null || body.currentReference != null)) {
      return TimelineOwnedBodyConnector(
        itemId: item.id,
        contentKey: body.key,
        label: '${body.key} · ${body.byteLength} 字节',
        historyReference: body.historyReference,
        currentReference: body.currentReference,
        disclosed: disclosed,
        showCopy: showCopy,
        frameBody: frameBody,
        witness: (text, child) => _contentWitness(text, render(text)),
      );
    }
    Widget inline;
    final decoded = body.inlineText;
    if (decoded != null) {
      inline = _contentWitness(decoded, render(decoded));
    } else {
      final bytes = body.inline;
      if (bytes == null) {
        inline = Text('${body.key} · 未提供内容或引用');
      } else {
        try {
          final text = utf8.decode(bytes);
          inline = _contentWitness(text, render(text));
        } on FormatException catch (error) {
          inline = Text('${body.key} · ${error.message}');
        }
      }
    }
    return frameBody?.call(inline) ?? inline;
  }

  Widget _contentWitness(String text, Widget child) {
    final clock = widget.monotonicMicros;
    final onLayout = widget.onContentLayout;
    final onCurrentLayout = widget.onCurrentContentLayout;
    final onCurrentUnmounted = widget.onCurrentContentUnmounted;
    final currentItemId = item.displayRecord?.atom.id ?? item.id;
    if (text.trim().isEmpty ||
        clock == null ||
        (onLayout == null && onCurrentLayout == null)) {
      return child;
    }
    return ContentLayoutWitness(
      itemId: item.id,
      monotonicMicros: clock,
      onContentLayout: (itemId, micros) {
        onLayout?.call(itemId, micros);
        if (item.displayRecord?.contentSource is CurrentAtomSource) {
          onCurrentLayout?.call(currentItemId, micros);
        }
      },
      onContentUnmounted: item.displayRecord?.contentSource is CurrentAtomSource
          ? (_) => onCurrentUnmounted?.call(currentItemId)
          : null,
      isDisplayActive: widget.isDisplayActive,
      child: child,
    );
  }
}
