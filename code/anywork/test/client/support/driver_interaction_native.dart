import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../anywork_client/test/support/profile_native_pin.dart';
import 'selector_conversation_port.dart';

enum DriverInteractionMaterialKind { question, plan, approval }

/// Declared immutable native material. Purpose is independent of question IDs;
/// no Driver projection, VM state or interaction reducer is implemented here.
final class DriverInteractionMaterial {
  const DriverInteractionMaterial({
    required this.entry,
    required this.id,
    required this.targetThreadId,
    required this.kind,
    required this.title,
    required this.body,
    this.revision = 1,
    this.questionId = 'q',
    this.deferredBody = false,
    this.optionsCount = 0,
    this.options = const [],
    this.optionPageSize = 32,
    this.deferredTexts = const {},
  });
  final int entry, revision;
  final String id, targetThreadId, title, body, questionId;
  final DriverInteractionMaterialKind kind;
  final bool deferredBody;
  final int? optionsCount;
  final List<OptionReadItem> options;
  final int optionPageSize;
  final Map<int, String> deferredTexts;
  InteractionReadRef get reference =>
      InteractionReadRef(entry: entry, revision: revision);
  InteractionBrief get brief => InteractionBrief(
    reference: reference,
    revision: revision,
    kind: kind == DriverInteractionMaterialKind.approval
        ? InteractionKind.toolApproval
        : InteractionKind.userInput,
    status: InteractionStatus.pending,
    createdAt: 1,
    updatedAt: revision,
  );
}

/// Holds the original native response after its actual query has entered.
/// It neither starts a read nor advances any production reader state.
final class DriverNativeResponseBarrier {
  final entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> wait() {
    if (!entered.isCompleted) entered.complete();
    return _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

final class DriverInteractionNative {
  DriverInteractionNative(this.port) {
    port.facets.interactionIndexOpen = (host, reference, origin) async {
      final pin = _DriverIndex(
        host: host,
        reference: reference,
        origin: origin,
        values: List.of(_current),
        ordinal: ++_ordinal,
      );
      pins.add(pin);
      return pin;
    };
    port.facets.interactionResolve = (host, id, revision, origin) async {
      resolutions.add((host: host, id: id, revision: revision, origin: origin));
      return _materials.values
          .singleWhere((value) => value.id == id && value.revision == revision)
          .reference;
    };
    port.facets.interactionOpen = (host, reference, origin) async {
      reads.add((host: host, reference: reference, origin: origin));
      final pin = _DriverInteractionPin(
        this,
        host,
        _materials[(reference.entry, reference.revision)]!,
        origin,
        ++_ordinal,
      );
      pins.add(pin);
      return pin;
    };
  }
  final SelectorConversationPort port;
  final _materials = <(int, int), DriverInteractionMaterial>{};
  List<DriverInteractionMaterial> _current = const [];
  int _ordinal = 0;
  final reads =
      <
        ({String host, InteractionReadRef reference, ThreadFacetStamp origin})
      >[];
  final resolutions =
      <({String host, String id, int revision, ThreadFacetStamp origin})>[];
  final headers = <({String host, InteractionReadRef reference})>[];
  final failures = <(int, int)>{};
  final pins = <ProfileNativePin>[];
  final questionReads =
      <({String host, InteractionReadRef reference, int offset})>[];
  final optionReads =
      <
        ({
          String host,
          InteractionReadRef reference,
          int questionIndex,
          int offset,
          int limit,
        })
      >[];
  final textReads =
      <({String host, InteractionReadRef reference, int field, int offset})>[];
  final _optionHolds = <(int, int, int, int), DriverNativeResponseBarrier>{};
  final _textHolds = <(int, int, int, int), DriverNativeResponseBarrier>{};
  Object get activity => (
    reads.length,
    resolutions.length,
    headers.length,
    questionReads.length,
    optionReads.length,
    textReads.length,
    _ordinal,
  );

  DriverNativeResponseBarrier holdOptions(
    InteractionReadRef reference, {
    int questionIndex = 0,
    int offset = 0,
  }) => _optionHolds.putIfAbsent((
    reference.entry,
    reference.revision,
    questionIndex,
    offset,
  ), DriverNativeResponseBarrier.new);

  DriverNativeResponseBarrier holdText(
    InteractionReadRef reference,
    int fieldId, {
    int offset = 0,
  }) => _textHolds.putIfAbsent((
    reference.entry,
    reference.revision,
    fieldId,
    offset,
  ), DriverNativeResponseBarrier.new);

  void releaseHeldResponses() {
    for (final barrier in [..._optionHolds.values, ..._textHolds.values]) {
      barrier.release();
    }
  }

  Future<void> publish(List<DriverInteractionMaterial> values) async {
    for (final value in values) {
      _materials[(value.entry, value.revision)] = value;
    }
    _current = List.unmodifiable(values);
    await port.publishInteractionIndex([
      for (final value in values) value.brief,
    ]);
  }
}

final class _DriverIndex extends ProfileNativePin
    implements InteractionIndexReadConnection {
  _DriverIndex({
    required String host,
    required this.reference,
    required this.origin,
    required this.values,
    required int ordinal,
  }) : super('driver-index-$host-$ordinal');
  final InteractionIndexRef reference;
  final ThreadFacetStamp origin;
  final List<DriverInteractionMaterial> values;
  ReadScopeIdentity get scope => ReadScopeIdentity(
    scopeId: id,
    runtimeEpoch: origin.runtimeEpoch,
    incarnation: origin.incarnation,
    sourceRevision: reference.revision,
  );
  @override
  Future<InteractionIndexReadHeader> header() async =>
      InteractionIndexReadHeader(
        scope: scope,
        total: values.length,
        pending: values.length,
      );
  @override
  Future<InteractionBriefPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => InteractionBriefPage(
    scope: scope,
    offset: offset,
    total: values.length,
    items: [for (final value in values.skip(offset).take(limit)) value.brief],
    nextOffset: null,
  );
}

final class _DriverInteractionPin extends ProfileNativePin
    implements InteractionReadConnection {
  _DriverInteractionPin(
    this.native,
    this.host,
    this.value,
    this.origin,
    int ordinal,
  ) : super('driver-material-$host-${value.entry}-${value.revision}-$ordinal');
  final DriverInteractionNative native;
  final String host;
  final DriverInteractionMaterial value;
  final ThreadFacetStamp origin;
  ReadScopeIdentity get scope => ReadScopeIdentity(
    scopeId: id,
    runtimeEpoch: origin.runtimeEpoch,
    incarnation: origin.incarnation,
    sourceRevision: value.revision,
  );
  ReadText get body => value.deferredBody
      ? ReadText.deferred(
          fieldId: 42,
          utf8Bytes: utf8.encode(value.body).length,
        )
      : ReadText.inline(text: value.body);
  @override
  Future<InteractionReadHeader> header() async {
    admit();
    native.headers.add((host: host, reference: value.reference));
    if (native.failures.contains((value.entry, value.revision))) {
      throw const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The original Driver test material failed to read',
        retryable: true,
        correlationId: 'driver-material-read',
      );
    }
    return InteractionReadHeader(
      scope: scope,
      interactionId: ReadText.inline(text: value.id),
      threadId: ReadText.inline(text: value.targetThreadId),
      turnId: ReadText.inline(text: 'turn-${value.id}'),
      itemId: null,
      toolId: null,
      agentPath: value.targetThreadId == host
          ? null
          : const ReadText.inline(text: 'root/reviewer'),
      revision: value.revision,
      purpose: value.kind == DriverInteractionMaterialKind.plan
          ? const InteractionPurposeRead.planConfirmation(
              expectedRevision: 7,
              operationId: ReadText.inline(text: 'native-plan-op'),
              argumentHash: ReadText.inline(text: 'args-hash'),
              planHash: ReadText.inline(text: 'plan-hash'),
            )
          : const InteractionPurposeRead.general(),
      continuation: null,
      createdAt: 1,
      updatedAt: value.revision,
      content: value.kind == DriverInteractionMaterialKind.approval
          ? InteractionContentRead.toolApproval(
              name: ReadText.inline(text: value.title),
              arguments: body,
              workingDirectory: const ReadText.inline(text: '/workspace'),
              parentAgentId: ReadText.inline(text: host),
            )
          : const InteractionContentRead.userInput(questionCount: 1),
      state: InteractionStateRead.pending(
        operationId: ReadText.inline(text: 'native-${value.id}'),
      ),
    );
  }

  @override
  Future<QuestionPage> questions({int offset = 0, int limit = 32}) async {
    admit();
    native.questionReads.add((
      host: host,
      reference: value.reference,
      offset: offset,
    ));
    return QuestionPage(
      scope: scope,
      offset: offset,
      total: 1,
      nextOffset: null,
      items: [
        QuestionReadItem(
          index: 0,
          id: ReadText.inline(text: value.questionId),
          header: ReadText.inline(text: value.title),
          question: body,
          isOther: value.kind != DriverInteractionMaterialKind.plan,
          isSecret: false,
          optionsCount: value.optionsCount,
        ),
      ],
    );
  }

  @override
  Future<OptionPage> options(
    int questionIndex, {
    int offset = 0,
    int limit = 32,
  }) {
    admit();
    final count = value.optionsCount;
    if (questionIndex != 0 || count == null) {
      throw StateError('Unscripted Driver native options');
    }
    native.optionReads.add((
      host: host,
      reference: value.reference,
      questionIndex: questionIndex,
      offset: offset,
      limit: limit,
    ));
    return reply(() async {
      await native
          ._optionHolds[(value.entry, value.revision, questionIndex, offset)]
          ?.wait();
      final items = value.options
          .skip(offset)
          .take(math.min(limit, value.optionPageSize))
          .toList();
      final end = offset + items.length;
      return OptionPage(
        scope: scope,
        offset: offset,
        total: count,
        items: items,
        nextOffset: end == count ? null : end,
      );
    }());
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) {
    admit();
    final text = fieldId == 42 && value.deferredBody
        ? value.body
        : value.deferredTexts[fieldId];
    if (text == null) throw StateError('Unscripted Driver native text field');
    native.textReads.add((
      host: host,
      reference: value.reference,
      field: fieldId,
      offset: offset,
    ));
    return reply(() async {
      await native._textHolds[(value.entry, value.revision, fieldId, offset)]
          ?.wait();
      final bytes = utf8.encode(text);
      // Declared synthetic texts are ASCII. A short chunk exposes the actual
      // reader's prefix without treating it as a fully materialized field.
      final end = math.min<int>(
        bytes.length,
        offset + math.min<int>(maxBytes, 8),
      );
      return TextChunk(
        fieldId: fieldId,
        offset: offset,
        text: utf8.decode(bytes.sublist(offset, end)),
        nextOffset: end == bytes.length ? null : end,
      );
    }());
  }
}
