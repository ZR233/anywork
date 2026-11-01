import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_code_block.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/chat_item_presentation.dart';
import '../state/chat_payload_reading.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_diagnostics.dart';
import 'reasoning_summary.dart';
import 'content_layout_witness.dart';
import 'timeline_activity_row.dart';
import 'timeline_plain_text.dart';
import 'timeline_tool_blocks.dart';
import 'timeline_wait_blocks.dart';

typedef ChatContentRead = Future<ContentWindow> Function(
  ContentRef reference,
  ContentRange range,
);

/// One immutable producer item, one custom Message. Disclosures and decoded
/// presentation stay on this row; no cross-item grouping or historical cache.
class ChatItemView extends StatefulWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.bodyBuilder,
    this.readContent,
    this.childrenBuilder,
    this.attachmentBuilder,
    this.monotonicMicros,
    this.onContentLayout,
    this.isDisplayActive,
    this.registerWindowDisplay,
  });
  final ChatItemPresentation item;
  final Widget Function(String id, String text)? bodyBuilder;
  final ChatContentRead? readContent;
  final Widget Function(String parentId)? childrenBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final int Function()? monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros)?
  onContentLayout;
  final bool Function()? isDisplayActive;

  /// Borrows the actual expanded range view; registering does not read or retain another window.
  final VoidCallback Function(TimelineCurrentWindowDisplay display)?
  registerWindowDisplay;
  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  bool _expanded = false;
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
            _metadata(item.data),
          ],
        );
  @override
  void didUpdateWidget(covariant ChatItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != item.id) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (item.reference case final reference?) {
      return _ContentRangeView(
        key: ValueKey('deferred:${item.id}'),
        itemId: item.id,
        contentKey: 'payload',
        label: '按需查看原文 · ${item.byteLength} 字节',
        reference: reference,
        read: widget.readContent,
        isDisplayActive: widget.isDisplayActive,
        witness: _contentWitness,
        registerDisplay: widget.registerWindowDisplay,
      );
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
      constraints: const BoxConstraints(minHeight: 40),
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
    'contextCompaction' => _record(
      Icons.compress_outlined,
      '上下文压缩 · ${item.data['beforeTokens'] ?? '?'} → ${item.data['afterTokens'] ?? '?'} tokens',
      item.data,
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
      _outcomeNotice(item.data['outcome']),
    ],
  );
  Widget _thinking(BuildContext context) {
    final summaries = [
      for (final body in item.bodies)
        if (RegExp(r'^part\.summaryText\.\d+$').hasMatch(body.key) &&
            body.inline != null)
          utf8.decode(body.inline!),
    ];
    final summary = summaries.lastOrNull;
    final label = summary == null
        ? context.l10n.timelineReasoningEnded
        : plainReasoningSummary(summary) ??
              inlineReasoningSummaryMarkdown(summary) ??
              context.l10n.timelineReasoningEnded;
    return _disclosure(Icons.psychology_alt_outlined, label, [
      for (final body in item.bodies) _body(body),
      _outcomeNotice(item.data['outcome']),
      _rawRecord(),
    ]);
  }

  Widget _tool(BuildContext context) {
    final reading = item.toolCard;
    final Widget card;
    if (reading is DecodedToolCard) {
      final tool = reading.value;
      card = TimelineActivityTileTheme(
        child: tool.wait != null
            ? TimelineWaitPanel(
                identity: item.id,
                presentation: tool.wait!,
                diagnostics: TimelineToolDetails(item: tool),
              )
            : timelineIsWebSearch(tool)
            ? TimelineWebSearchToolCard(item: tool)
            : TimelineToolDetails(item: tool),
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
    final input = item.data['userInput'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        if (input != null)
          _questionReceipt(context, chatObject(input, 'userInput')),
        _media(),
        // References are explicit producer entries; no private receipt or arbitrary
        // JSON-field search is used to discover a body.
        if (reading is DecodedToolCard) ...[
          for (final body in _publicBodies)
            if (body.reference != null) _body(body),
          _rawRecord(),
        ],
      ],
    );
  }

  Widget _turn(BuildContext context) {
    final outcome = chatObject(item.data['outcome'], 'turn.outcome');
    final state = chatString(outcome['kind'], 'turn.outcome.kind');
    final title = switch (state) {
      'completed' => '轮次已完成',
      'failed' => '轮次失败',
      'cancelled' => context.l10n.timelineTurnStopped,
      'budgetLimited' => '轮次达到预算上限',
      _ => '轮次 · $state',
    };
    return _disclosure(Icons.account_tree_outlined, title, [
      _outcomeNotice(outcome),
      if (item.childrenParentId case final parent?)
        if (widget.childrenBuilder case final builder?)
          builder(parent)
        else
          const Text('子内容读取尚未就绪'),
      _rawRecord(),
    ], issue: state == 'failed' || state == 'budgetLimited');
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
    return Card(
      key: StudioDriverKeys.timelinePlanReceipt(item.id),
      elevation: 0,
      color: context.colors.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: context.text.titleSmall),
            for (final body in item.bodies) _body(body),
            _rawRecord(),
          ],
        ),
      ),
    );
  }

  Widget _questionReceipt(BuildContext context, Map<String, Object?> input) {
    final state = chatObject(input['state'], 'userInput.state');
    final questions = input['questions'];
    if (questions is! List) throw const FormatException('questions 必须是数组');
    final answers = state['answers'] is List
        ? state['answers'] as List
        : const [];
    return Card(
      key: StudioDriverKeys.timelineUserInput(item.id),
      elevation: 0,
      color: context.colors.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              state['kind'] == 'cancelled'
                  ? context.l10n.timelineUserInputCancelled
                  : context.l10n.timelineUserInputAnswered,
              style: context.text.titleSmall,
            ),
            for (var index = 0; index < questions.length; index++)
              _question(
                context,
                chatObject(questions[index], 'question'),
                index,
                answers,
              ),
          ],
        ),
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
    if (redacted) return const Text('敏感内容已隐藏');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final body in item.bodies)
            if (body.key.startsWith('tool.user-input.question.$index.') ||
                body.key.startsWith('tool.user-input.answer.$index.'))
              _body(body),
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

  Widget _media() {
    final builder = widget.attachmentBuilder;
    if (builder != null) return builder(item);
    // Preview hosts can show public attachment metadata without platform IO.
    try {
      return Column(
        children: [
          for (final attachment in item.attachments)
            ListTile(
              title: Text(attachment.filename ?? attachment.id),
              subtitle: Text(
                '${attachment.mediaType} · ${attachment.byteSize} B',
              ),
            ),
        ],
      );
    } on FormatException catch (error) {
      return Text('附件字段无法解析：${error.message}');
    }
  }

  Widget _rawRecord() => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      title: const Text('公开原始记录'),
      children: [
        for (final body in _publicBodies) _body(body, code: true),
        _publicEnvelope(),
      ],
    ),
  );
  Widget _unavailable(String title, String? diagnostic) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: TimelineActivityRow(label: title, expanded: _expanded),
        ),
        if (_expanded) ...[
          if (diagnostic != null) Text(diagnostic),
          for (final body in _publicBodies)
            _body(body, code: item.type == 'tool'),
          _publicEnvelope(),
        ],
      ],
    ),
  );
  Widget _disclosure(
    IconData icon,
    String title,
    List<Widget> children, {
    bool issue = false,
  }) => TimelineActivityTileTheme(
    child: ExpansionTile(
      initiallyExpanded: _expanded,
      maintainState: false,
      showTrailingIcon: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsetsDirectional.only(start: 28),
      minTileHeight: 28,
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (value) => setState(() => _expanded = value),
      title: TimelineActivityRow(
        icon: icon,
        label: title,
        isIssue: issue,
        expanded: _expanded,
      ),
      children: children,
    ),
  );
  Widget _body(ChatBodyPresentation body, {bool code = false}) {
    if (body.reference case final reference?) {
      return _ContentRangeView(
        key: ValueKey('body:${item.id}:${body.key}'),
        itemId: item.id,
        contentKey: body.key,
        label: '${body.key} · ${body.byteLength} 字节',
        reference: reference,
        read: widget.readContent,
        isDisplayActive: widget.isDisplayActive,
        witness: _contentWitness,
        registerDisplay: widget.registerWindowDisplay,
      );
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

class _ContentRangeView extends StatefulWidget {
  const _ContentRangeView({
    super.key,
    required this.label,
    required this.reference,
    required this.read,
    required this.itemId,
    required this.contentKey,
    required this.witness,
    required this.isDisplayActive,
    this.registerDisplay,
  });
  final String label;
  final ContentRef reference;
  final ChatContentRead? read;
  final String itemId;
  final String contentKey;
  final Widget Function(String text, Widget child) witness;
  final bool Function()? isDisplayActive;
  final VoidCallback Function(TimelineCurrentWindowDisplay display)?
  registerDisplay;
  @override
  State<_ContentRangeView> createState() => _ContentRangeViewState();
}

class _ContentRangeViewState extends State<_ContentRangeView>
    implements TimelineCurrentWindowDisplay {
  ContentWindow? _window;
  Object? _error;
  bool _loading = false;
  bool _expanded = false;
  int _request = 0;
  VoidCallback? _unregisterDisplay;

  bool get _displayActive =>
      mounted && _expanded && (widget.isDisplayActive?.call() ?? true);
  @override
  String get id => widget.itemId;
  @override
  ContentRef get reference => widget.reference;
  @override
  int get offset => _window?.offset ?? 0;
  @override
  ContentWindow? get window => _displayActive ? _window : null;
  @override
  Object? get error => _displayActive ? _error : null;

  void _unregister() {
    final unregister = _unregisterDisplay;
    _unregisterDisplay = null;
    unregister?.call();
  }

  @override
  void didUpdateWidget(covariant _ContentRangeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (contentReferenceIdentity(oldWidget.reference) !=
        contentReferenceIdentity(widget.reference)) {
      _unregister();
      _request++;
      _window = null;
      _error = null;
      _loading = false;
      _expanded = false;
    } else if (oldWidget.registerDisplay != widget.registerDisplay) {
      _unregister();
      if (_displayActive) {
        _unregisterDisplay = widget.registerDisplay?.call(this);
      }
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  Future<void> _load(int offset) async {
    final read = widget.read;
    if (read == null || _loading || !(widget.isDisplayActive?.call() ?? true)) {
      return;
    }
    final request = ++_request;
    final reference = widget.reference;
    final isActive = widget.isDisplayActive;
    bool eligible() =>
        mounted &&
        request == _request &&
        (isActive?.call() ?? true) &&
        (widget.isDisplayActive?.call() ?? true) &&
        contentReferenceIdentity(widget.reference) ==
            contentReferenceIdentity(reference);
    setState(() {
      _expanded = true;
      _loading = true;
      _error = null;
    });
    _unregisterDisplay ??= widget.registerDisplay?.call(this);
    try {
      final value = await read(
        reference,
        ContentRange(offset: offset, maxBytes: 64 * 1024),
      );
      if (!eligible()) return;
      setState(() => _window = value);
    } catch (error) {
      if (!eligible()) return;
      // Missing content, stale identity and real DB failures stay diagnostics.
      setState(() => _error = error);
    } finally {
      if (eligible()) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final end = window == null ? 0 : window.offset + window.bytes.length;
    final text = window == null
        ? ''
        : utf8.decode(window.bytes, allowMalformed: true);
    final active = widget.isDisplayActive?.call() ?? true;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: TextButton(
              key: StudioDriverKeys.timelineContentOpen(
                widget.itemId,
                widget.contentKey,
              ),
              onPressed: _loading || !active
                  ? null
                  : () {
                      if (_expanded) {
                        _unregister();
                        setState(() => _expanded = false);
                      } else {
                        unawaited(_load(_window?.offset ?? 0));
                      }
                    },
              child: Text(widget.label),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (widget.read == null) const Text('内容读取尚未就绪'),
          if (_expanded && _error != null) Text(_error.toString()),
          if (_expanded && window != null) ...[
            Text('字节 ${window.offset}–$end / ${window.availableThrough}'),
            // A bounded window may end inside a UTF-8 code point. This is a raw
            // byte-range viewer, not a business payload decoder.
            widget.witness(
              text,
              Text(
                text,
                key: StudioDriverKeys.timelineContentWindow(
                  widget.itemId,
                  widget.contentKey,
                ),
              ),
            ),
            TextButton(
              key: StudioDriverKeys.timelineContentCopyWindow(
                widget.itemId,
                widget.contentKey,
              ),
              onPressed: !active || _loading
                  ? null
                  : () {
                      if (!(widget.isDisplayActive?.call() ?? true) ||
                          !_expanded ||
                          !identical(_window, window)) {
                        return;
                      }
                      unawaited(Clipboard.setData(ClipboardData(text: text)));
                    },
              child: const Text('复制当前段'),
            ),
            if (window.bytes.isNotEmpty && end < window.availableThrough)
              TextButton(
                key: StudioDriverKeys.timelineContentNextWindow(
                  widget.itemId,
                  widget.contentKey,
                ),
                onPressed: _loading || !active
                    ? null
                    : () {
                        if (!identical(_window, window) ||
                            !_expanded ||
                            !(widget.isDisplayActive?.call() ?? true)) {
                          return;
                        }
                        unawaited(_load(end));
                      },
                child: const Text('下一段'),
              ),
          ],
        ],
      ),
    );
  }
}
