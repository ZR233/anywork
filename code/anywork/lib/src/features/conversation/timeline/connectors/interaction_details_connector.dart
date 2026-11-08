import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../state/content_reference_identity.dart';
import '../state/chat_payload_reading.dart';
import '../../interactions/widgets/interaction_widgets.dart';
import '../../interactions/widgets/question_step.dart';

/// Read-only, bounded details of the State-owned interactions reference.
/// Actionable interactions remain exclusively in the original State model.
class InteractionDetailsConnector extends StatefulWidget {
  const InteractionDetailsConnector({
    required this.content,
    required this.reference,
    required this.isCurrent,
    super.key,
  });
  final ConversationContent content;
  final CurrentCollectionRef reference;
  final bool Function() isCurrent;
  @override
  State<InteractionDetailsConnector> createState() =>
      _InteractionDetailsState();
}

class _InteractionDetailsState extends State<InteractionDetailsConnector> {
  bool _expanded = false;
  Object _generation = Object();
  VoidCallback? _retire;
  @override
  Widget build(BuildContext context) {
    final reference = widget.reference;
    final content = widget.content;
    final generation = _generation;
    // The composer footer paints above Scaffold's Material. Give the outer and
    // deferred ExpansionTiles a shared ink surface above that opaque decoration.
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        title: const Text('交互详情'),
        maintainState: false,
        onExpansionChanged: (value) {
          if (!value) {
            _retire?.call();
            _generation = Object();
          }
          setState(() => _expanded = value);
        },
        children: [
          if (_expanded)
            _InteractionPageReader(
              key: ValueKey((
                generation,
                content,
                content.currentAttemptId,
                currentCollectionIdentity(reference),
              )),
              content: widget.content,
              reference: widget.reference,
              isCurrent: () =>
                  _expanded &&
                  identical(_generation, generation) &&
                  identical(widget.content, content) &&
                  widget.reference == reference &&
                  widget.isCurrent(),
              registerRetirement: (retire) => _retire = retire,
            ),
        ],
      ),
    );
  }
}

class _InteractionPageReader extends StatefulWidget {
  const _InteractionPageReader({
    required this.content,
    required this.reference,
    required this.isCurrent,
    required this.registerRetirement,
    super.key,
  });
  final ConversationContent content;
  final CurrentCollectionRef reference;
  final bool Function() isCurrent;
  final ValueChanged<VoidCallback> registerRetirement;
  @override
  State<_InteractionPageReader> createState() => _InteractionPageState();
}

class _InteractionPageState extends State<_InteractionPageReader> {
  late final ConversationQueryScope _scope = widget.content.openScope(
    generation: 1,
  );
  CurrentCollectionPage? _page;
  Object? _error;
  bool _loading = false;
  bool _retired = false;
  int _request = 0;
  Future<CloseReport>? _closing;
  final Set<VoidCallback> _resourceRetirements = {};
  bool get _active =>
      mounted && !_retired && _scope.isActive && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    widget.registerRetirement(_retire);
    unawaited(_load(null));
  }

  Future<void> _load(String? continuation) async {
    if (!_active || _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _scope.pageCurrent(
        reference: widget.reference,
        continuation: continuation,
        demand: const ReadDemand(maxItems: 20, maxBytes: 64 * 1024),
      );
      if (!_active || request != _request) return;
      if (value.revision != widget.reference.revision) {
        throw const ConversationContinuityError(
          'Interaction page changed its State reference',
        );
      }
      setState(() => _page = value);
    } catch (error) {
      if (_active && request == _request) setState(() => _error = error);
    } finally {
      if (_active && request == _request) setState(() => _loading = false);
    }
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _request++;
    for (final retire in _resourceRetirements.toList()) {
      retire();
    }
    _scope.retire();
    _closing ??= _scope.close();
    unawaited(_closing);
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  Widget _summary(String id, List<int> bytes) {
    if (bytes.length > _interactionByteBudget) {
      return const Text('详情资源超出读取预算');
    }
    try {
      final payload = _requestPayload(
        jsonDecode(utf8.decode(bytes)),
        id: id,
        threadId: widget.content.threadId,
      );
      return _ReadOnlyInteractionDetails(
        key: ValueKey(id),
        id: id,
        payload: payload,
      );
    } catch (_) {
      // Parser diagnostics may contain input bytes. Never print an interaction
      // envelope, lifecycle resolution, continuation or secret field here.
      return const Text('交互详情格式无效');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error case final error?) Text(error.toString()),
      if (_loading) const LinearProgressIndicator(),
      for (final entry in _page?.entries ?? const <CurrentCollectionEntry>[])
        switch (entry.payload) {
          InlinePayload(:final bytes) => _summary(entry.id, bytes),
          DeferredPayload(:final reference, :final byteLength) =>
            _DeferredInteractionDetails(
              key: ValueKey((
                _request,
                entry.id,
                contentReferenceIdentity(reference),
              )),
              id: entry.id,
              content: widget.content,
              reference: reference,
              byteLength: byteLength,
              isCurrent: () => _active,
              registerRetirement: (retire) {
                _resourceRetirements.add(retire);
                return () => _resourceRetirements.remove(retire);
              },
            ),
        },
      if (!_loading && _error != null)
        TextButton(onPressed: () => _load(null), child: const Text('重试详情')),
      if (!_loading && _error == null && _page?.continuation != null)
        TextButton(
          onPressed: () => _load(_page!.continuation),
          child: const Text('下一页交互详情'),
        ),
    ],
  );
}

const _interactionByteBudget = 1024 * 1024;
const _interactionWindowBytes = 64 * 1024;

/// A structured request is decoded once, not once per text window. This widget
/// deliberately has no raw byte, clipboard or download presentation path.
class _DeferredInteractionDetails extends StatefulWidget {
  const _DeferredInteractionDetails({
    required this.id,
    required this.content,
    required this.reference,
    required this.byteLength,
    required this.isCurrent,
    required this.registerRetirement,
    super.key,
  });
  final String id;
  final ConversationContent content;
  final ContentRef reference;
  final int byteLength;
  final bool Function() isCurrent;
  final VoidCallback Function(VoidCallback) registerRetirement;
  @override
  State<_DeferredInteractionDetails> createState() =>
      _DeferredInteractionState();
}

class _InteractionReadFailure implements Exception {
  const _InteractionReadFailure(this.message);
  final String message;
}

class _DeferredInteractionState extends State<_DeferredInteractionDetails> {
  late final VoidCallback _unregister;
  ConversationQueryScope? _scope;
  bool _expanded = false;
  bool _loading = false;
  bool _retired = false;
  int _epoch = 0;
  InteractionPayload? _payload;
  String? _error;

  @override
  void initState() {
    super.initState();
    _unregister = widget.registerRetirement(_retire);
  }

  void _stopRead() {
    _epoch++;
    _payload = null;
    _loading = false;
    final scope = _scope;
    _scope = null;
    scope?.retire();
    // Closing joins the actual pending query; failed close responsibility stays
    // with the original SDK content owner, never with a detached byte snapshot.
    if (scope != null) unawaited(scope.close());
  }

  void _retire() {
    _retired = true;
    _stopRead();
  }

  bool _eligible(ConversationQueryScope scope, int epoch) =>
      mounted &&
      !_retired &&
      _expanded &&
      widget.isCurrent() &&
      epoch == _epoch &&
      identical(scope, _scope) &&
      scope.isActive;

  Future<void> _read() async {
    if (_retired || !_expanded || !widget.isCurrent() || _loading) return;
    _stopRead();
    _error = null;
    final length = widget.byteLength;
    if (length > _interactionByteBudget) {
      setState(() => _error = '详情资源超出读取预算');
      return;
    }
    if (length <= 0) {
      setState(() => _error = '详情资源长度无效');
      return;
    }
    final scope = widget.content.openScope(generation: _epoch);
    _scope = scope;
    final epoch = _epoch;
    setState(() => _loading = true);
    try {
      final bytes = BytesBuilder(copy: false);
      String? generation;
      var offset = 0;
      while (offset < length) {
        if (!_eligible(scope, epoch)) return;
        final remaining = length - offset;
        final limit = remaining < _interactionWindowBytes
            ? remaining
            : _interactionWindowBytes;
        final window = await scope.readContent(
          reference: widget.reference,
          range: ContentRange(offset: offset, maxBytes: limit),
        );
        if (!_eligible(scope, epoch)) return;
        if (window.availableThrough > _interactionByteBudget ||
            bytes.length + window.bytes.length > _interactionByteBudget) {
          throw const _InteractionReadFailure('详情资源超出读取预算');
        }
        if (window.offset != offset ||
            window.bytes.length > limit ||
            window.availableThrough != length ||
            !window.sealed ||
            (generation != null && window.generation != generation)) {
          throw const _InteractionReadFailure('详情资源窗口不连续');
        }
        if (window.bytes.isEmpty) {
          throw const _InteractionReadFailure('详情资源读取未取得进展');
        }
        generation ??= window.generation;
        bytes.add(window.bytes);
        offset += window.bytes.length;
      }
      final payload = _requestPayload(
        jsonDecode(utf8.decode(bytes.takeBytes())),
        id: widget.id,
        threadId: widget.content.threadId,
      );
      if (_eligible(scope, epoch)) setState(() => _payload = payload);
    } catch (error) {
      if (_eligible(scope, epoch)) {
        setState(
          () => _error = switch (error) {
            _InteractionReadFailure(:final message) => message,
            FormatException() => '交互详情格式无效',
            _ => '详情资源读取失败',
          },
        );
      }
    } finally {
      if (_eligible(scope, epoch)) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _unregister();
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('查看完整交互详情'),
    maintainState: false,
    onExpansionChanged: (expanded) {
      setState(() {
        _expanded = expanded;
        if (!expanded) {
          _stopRead();
          _error = null;
        }
      });
      if (expanded) unawaited(_read());
    },
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error case final error?) Text(error),
      if (_expanded)
        if (_payload case final payload?)
          _ReadOnlyInteractionDetails(id: widget.id, payload: payload),
    ],
  );
}

/// Read only the canonical InteractionRequest shape. Lifecycle and continuation
/// are not decision authority: the State-owned dock remains the sole operator.
InteractionPayload _requestPayload(
  Object? value, {
  required String id,
  required String threadId,
}) {
  final request = chatObject(value, 'InteractionRequest');
  final scope = chatObject(request['scope'], 'scope');
  if (chatString(request['interactionId'], 'interactionId') != id ||
      chatString(scope['threadId'], 'scope.threadId') != threadId ||
      chatInteger(request['revision'], 'revision') < 0) {
    throw const FormatException('Interaction identity mismatch');
  }
  chatString(scope['turnId'], 'scope.turnId');
  chatInteger(request['createdAt'], 'createdAt');
  chatInteger(request['updatedAt'], 'updatedAt');
  final content = chatObject(request['content'], 'content');
  final data = chatObject(content['data'], 'content.data');
  final state = chatObject(data['state'], 'content.data.state');
  if (!const {
    'pending',
    'resolved',
    'cancelled',
    'expired',
  }.contains(state['kind'])) {
    throw const FormatException('Invalid interaction lifecycle');
  }
  return switch (content['kind']) {
    'userInput' => UserInputInteractionPayload(
      questions: [
        for (final raw in _requestList(data['questions']))
          _requestQuestion(raw),
      ],
    ),
    'toolApproval' => _requestApproval(data['request']),
    _ => throw const FormatException('Unknown interaction content'),
  };
}

List<Object?> _requestList(Object? value) {
  if (value is List) return value;
  throw const FormatException('Expected interaction list');
}

bool _requestFlag(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  throw const FormatException('Expected interaction flag');
}

UserQuestionView _requestQuestion(Object? value) {
  final question = chatObject(value, 'question');
  return UserQuestionView(
    id: chatString(question['id'], 'question.id'),
    header: chatString(question['header'], 'question.header'),
    question: chatString(question['question'], 'question.question'),
    isOther: _requestFlag(question['isOther']),
    isSecret: _requestFlag(question['isSecret']),
    options: [
      for (final raw
          in question['options'] == null
              ? const []
              : _requestList(question['options']))
        (() {
          final option = chatObject(raw, 'option');
          return UserQuestionOptionView(
            label: chatString(option['label'], 'option.label'),
            description: chatString(
              option['description'],
              'option.description',
            ),
          );
        })(),
    ],
  );
}

ToolApprovalInteractionPayload _requestApproval(Object? value) {
  final request = chatObject(value, 'toolApproval.request');
  if (!request.containsKey('arguments')) {
    throw const FormatException('Missing tool arguments');
  }
  return ToolApprovalInteractionPayload(
    toolName: chatString(request['name'], 'request.name'),
    arguments: request['arguments'],
    workingDirectory:
        chatOptionalString(request['workingDirectory'], 'workingDirectory') ??
        '',
    parentAgentId: chatOptionalString(
      request['parentAgentId'],
      'parentAgentId',
    ),
  );
}

class _ReadOnlyInteractionDetails extends StatefulWidget {
  const _ReadOnlyInteractionDetails({
    required this.id,
    required this.payload,
    super.key,
  });
  final String id;
  final InteractionPayload payload;
  @override
  State<_ReadOnlyInteractionDetails> createState() =>
      _ReadOnlyInteractionDetailsState();
}

class _ReadOnlyInteractionDetailsState
    extends State<_ReadOnlyInteractionDetails> {
  final _controllers = <String, TextEditingController>{};
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.payload) {
    UserInputInteractionPayload(:final questions) => InteractionDockShell(
      kind: InteractionDockKind.question,
      title: '问答详情（只读）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (questions.any(
            (question) => !question.isSecret && question.question.isNotEmpty,
          ))
            SelectableText(
              questions
                  .where((question) => !question.isSecret)
                  .map((question) => question.question)
                  .where((text) => text.isNotEmpty)
                  .join('\n'),
            ),
          for (final question in questions)
            if (question.isSecret)
              const Text('敏感问题内容已隐藏')
            else
              QuestionStep(
                // The selectable public prompt above owns this text. Reuse the
                // existing option/field layout without duplicating the prompt.
                question: UserQuestionView(
                  id: question.id,
                  header: question.header,
                  question: '',
                  isOther: question.isOther,
                  isSecret: false,
                  options: question.options,
                ),
                questionKey: 'details:${widget.id}:${question.id}',
                isFirstQuestion: false,
                firstOptionKey: GlobalKey(),
                controller: _controllers.putIfAbsent(
                  question.id,
                  TextEditingController.new,
                ),
                selected: const {},
                onOptionChanged: (_, _) {},
                onTextChanged: (_) {},
                enabled: false,
              ),
        ],
      ),
    ),
    ToolApprovalInteractionPayload(
      :final toolName,
      :final arguments,
      :final workingDirectory,
    ) =>
      InteractionDockShell(
        kind: InteractionDockKind.permission,
        title: '审批详情（只读）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoChip(icon: Icons.build_outlined, label: toolName),
            if (workingDirectory.isNotEmpty)
              InfoChip(icon: Icons.folder_outlined, label: workingDirectory),
            InteractionCodeBlock(
              text: const JsonEncoder.withIndent('  ').convert(arguments),
            ),
          ],
        ),
      ),
    UnknownInteractionPayload() => const Text('交互详情格式无效'),
  };
}
