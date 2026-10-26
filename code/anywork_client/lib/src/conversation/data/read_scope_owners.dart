import 'dart:convert';

import '../../../resources.dart';
import '../domain/activity_read_values.dart';
import '../domain/interaction_values.dart';
import '../domain/read_scopes.dart';
import '../domain/thread_identity.dart';
import '../domain/thread_read_values.dart';
import '../domain/turn_values.dart';
import 'connection_owner.dart';
import 'read_connections.dart';

abstract class PinnedConversationScope<C extends ConversationReadConnection>
    implements ConversationReadScope {
  PinnedConversationScope(this.owner, this.origin, {this.expectedRevision});
  final ConversationConnectionOwner<C> owner;
  final ThreadFacetStamp origin;
  final int? expectedRevision;
  ReadScopeIdentity? _identity;
  ReadScopeIdentity? _pinnedIdentity;
  ReadScopeIdentity? get identity => _identity;

  void validateIdentity(ReadScopeIdentity scope) {
    if (scope.scopeId.isEmpty ||
        scope.runtimeEpoch != origin.runtimeEpoch ||
        scope.incarnation != origin.incarnation ||
        scope.sourceRevision < 0 ||
        (expectedRevision != null &&
            scope.sourceRevision != expectedRevision) ||
        (_pinnedIdentity != null && scope != _pinnedIdentity)) {
      throw readProtocol(
        'The immutable read scope does not match its original source.',
      );
    }
  }

  Future<T> readHeader<T>(
    Future<T> Function(C) read,
    ReadScopeIdentity Function(T) scope,
  ) => owner.call((connection) async {
    try {
      final value = await read(connection);
      final source = scope(value);
      validateIdentity(source);
      if (owner.isClosing) throw conversationCancelled;
      owner.expectFeedId(source.scopeId);
      _pinnedIdentity ??= source;
      _identity = source;
      return value;
    } catch (_) {
      _identity = null;
      rethrow;
    }
  });

  void arguments({int? offset, int? limit}) {
    if (owner.isClosing) throw conversationCancelled;
    if ((offset != null && offset < 0) ||
        (limit != null && (limit < 1 || limit > 100))) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Read offset must be nonnegative and page limit must be within 1..100.',
        retryable: false,
        correlationId: 'conversation-read-argument',
      );
    }
  }

  void page(
    ReadScopeIdentity scope,
    int requested,
    int limit,
    int offset,
    int total,
    int count,
    int? next,
  ) {
    if (identity == null || identity != scope)
      throw readProtocol(
        'A page requires its successfully validated original header.',
      );
    validateIdentity(scope);
    if (offset != requested ||
        total < 0 ||
        offset > total ||
        count > limit ||
        count < 0 ||
        offset + count > total ||
        (next == null
            ? offset + count != total
            : count == 0 || next != offset + count)) {
      throw readProtocol(
        'The typed page did not make continuous progress in its immutable scope.',
      );
    }
  }

  @override
  void requestClose() => owner.requestClose();
  @override
  Future<CloseReport> close({DateTime? deadline}) =>
      owner.close(deadline: deadline);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      owner.close(deadline: deadline, retry: true);
}

abstract class TextConversationScope<C extends ConversationTextReadConnection>
    extends PinnedConversationScope<C>
    implements ConversationTextReadScope {
  TextConversationScope(super.owner, super.origin, {super.expectedRevision});
  Future<void> ensureHeader();
  Future<T> readAfterHeader<T>(Future<T> Function(C) read) =>
      owner.call((connection) async {
        if (identity == null) await ensureHeader();
        if (owner.isClosing) throw conversationCancelled;
        if (identity == null)
          throw readProtocol('The original header has not been validated.');
        final value = await read(connection);
        if (identity == null)
          throw readProtocol('The original header validation was revoked.');
        return value;
      });
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) {
    arguments(offset: offset);
    if (fieldId < 0 || maxBytes < 4 || maxBytes > 262144) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message:
              'Text chunks must use a valid field and 4..262144 UTF-8 bytes.',
          retryable: false,
          correlationId: 'conversation-read-text',
        ),
      );
    }
    return readAfterHeader((connection) async {
      final chunk = await connection.text(
        fieldId,
        offset: offset,
        maxBytes: maxBytes,
      );
      final bytes = utf8.encode(chunk.text).length;
      if (chunk.fieldId != fieldId ||
          chunk.offset != offset ||
          bytes > maxBytes ||
          (chunk.nextOffset != null &&
              (bytes == 0 || chunk.nextOffset != offset + bytes))) {
        throw readProtocol(
          'The text chunk does not continue the requested UTF-8 prefix.',
        );
      }
      return chunk;
    });
  }
}

final class TurnScopeOwner extends TextConversationScope<TurnReadConnection>
    implements TurnReadScope {
  TurnScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
    required this.expectedThreadId,
  });
  final String expectedThreadId;
  @override
  Future<TurnReadHeader> header() => readHeader((c) async {
    final h = await c.header();
    validateIdentity(h.scope);
    if (h.revision != expectedRevision)
      throw readProtocol('The Turn header replaced its requested revision.');
    if (await readPinnedIdentity(owner, c, h.threadId) != expectedThreadId)
      throw readProtocol('The Turn header belongs to another Thread.');
    return h;
  }, (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }
}

final class InteractionScopeOwner
    extends TextConversationScope<InteractionReadConnection>
    implements InteractionReadScope {
  InteractionScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
    required this.expectedThreadId,
    this.expectedInteractionId,
    this.expectedTargetThreadId,
    this.allowHostedTarget = false,
  });
  final String expectedThreadId;
  final String? expectedInteractionId;
  final String? expectedTargetThreadId;
  final bool allowHostedTarget;
  @override
  Future<InteractionReadHeader> header() => readHeader((c) async {
    final h = await c.header();
    validateIdentity(h.scope);
    if (h.revision != expectedRevision)
      throw readProtocol(
        'The Interaction header replaced its requested revision.',
      );
    if ((!allowHostedTarget && await readPinnedIdentity(owner, c, h.threadId) != expectedThreadId) ||
        (expectedTargetThreadId != null &&
            await readPinnedIdentity(owner, c, h.threadId) != expectedTargetThreadId) ||
        (expectedInteractionId != null &&
            await readPinnedIdentity(owner, c, h.interactionId) !=
                expectedInteractionId)) {
      throw readProtocol(
        'The Interaction header belongs to another frozen wire identity.',
      );
    }
    return h;
  }, (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  @override
  Future<QuestionPage> questions({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.questions(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<OptionPage> options(
    int questionIndex, {
    int offset = 0,
    int limit = 32,
  }) {
    arguments(offset: questionIndex, limit: limit);
    arguments(offset: offset);
    return readAfterHeader((c) async {
      final p = await c.options(questionIndex, offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<AnswerEntryPage> answerEntries({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.answerEntries(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<AnswerValuePage> answerValues(
    int entryIndex, {
    int offset = 0,
    int limit = 32,
  }) {
    arguments(offset: entryIndex, limit: limit);
    arguments(offset: offset);
    return readAfterHeader((c) async {
      final p = await c.answerValues(entryIndex, offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class InteractionIndexScopeOwner
    extends TextConversationScope<InteractionIndexReadConnection> {
  InteractionIndexScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
  });
  Future<InteractionIndexReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  Future<InteractionBriefPage> entries({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.entries(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class ActivityScopeOwner
    extends TextConversationScope<ActivityReadConnection>
    implements ActivityReadScope {
  ActivityScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
    required this.expectedThreadId,
  });
  final String expectedThreadId;
  @override
  Future<ActivityReadHeader> header() => readHeader((c) async {
    final h = await c.header();
    validateIdentity(h.scope);
    if (h.revision != expectedRevision)
      throw readProtocol(
        'The Activity header replaced its requested revision.',
      );
    if (await readPinnedIdentity(owner, c, h.threadId) != expectedThreadId)
      throw readProtocol('The Activity header belongs to another Thread.');
    return h;
  }, (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  @override
  Future<ActivityToolPage> tools({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.tools(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<WaitTargetPage> waitTargets(
    int toolIndex, {
    int offset = 0,
    int limit = 32,
  }) {
    arguments(offset: toolIndex, limit: limit);
    arguments(offset: offset);
    return readAfterHeader((c) async {
      final p = await c.waitTargets(toolIndex, offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<WaitTargetPage> latestWaitTargets({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.latestWaitTargets(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class StorageScopeOwner
    extends TextConversationScope<StorageReadConnection>
    implements StorageReadScope {
  StorageScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
  });
  @override
  Future<StorageReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }
}

final class MetricsIdentityScopeOwner
    extends TextConversationScope<MetricsIdentityReadConnection>
    implements MetricsIdentityReadScope {
  MetricsIdentityScopeOwner(super.owner, super.origin);
  @override
  Future<MetricsIdentityReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }
}

final class ContextScopeOwner
    extends TextConversationScope<ContextReadConnection>
    implements ContextReadScope {
  ContextScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
  });
  @override
  Future<ContextReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  @override
  Future<CostPage> costs({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.costs(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }

  @override
  Future<CostPage> cacheSavings({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.cacheSavings(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class ConfigurationScopeOwner
    extends TextConversationScope<ThreadConfigurationReadConnection>
    implements ThreadConfigurationReadScope {
  ConfigurationScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
  });
  @override
  Future<ThreadConfigurationReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  @override
  Future<SkillNamePage> activeSkills({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.activeSkills(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class TodoScopeOwner extends TextConversationScope<TodoReadConnection>
    implements TodoReadScope {
  TodoScopeOwner(super.owner, super.origin, {required super.expectedRevision});
  @override
  Future<TodoReadHeader> header() =>
      readHeader((c) => c.header(), (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }

  @override
  Future<TodoItemPage> items({int offset = 0, int limit = 32}) {
    arguments(offset: offset, limit: limit);
    return readAfterHeader((c) async {
      final p = await c.items(offset: offset, limit: limit);
      page(
        p.scope,
        offset,
        limit,
        p.offset,
        p.total,
        p.items.length,
        p.nextOffset,
      );
      return p;
    });
  }
}

final class WorkflowScopeOwner
    extends TextConversationScope<WorkflowReadConnection>
    implements WorkflowReadScope {
  WorkflowScopeOwner(
    super.owner,
    super.origin, {
    required super.expectedRevision,
  });
  @override
  Future<WorkflowReadHeader> header() => readHeader((c) async {
    final h = await c.header();
    if (h.revision != expectedRevision)
      throw readProtocol(
        'The Workflow header replaced its requested revision.',
      );
    return h;
  }, (h) => h.scope);
  @override
  Future<void> ensureHeader() async {
    await header();
  }
}

final class PlanDocumentScopeOwner
    extends PinnedConversationScope<PlanDocumentReadConnection>
    implements PlanDocumentReadScope {
  PlanDocumentScopeOwner(
    super.owner,
    super.origin,
    this.version,
    this.contentHash,
  );
  final int version;
  final String contentHash;
  @override
  Future<PlanDocumentReadHeader> header() => readHeader((c) async {
    final h = await c.header();
    if (h.version != version || h.contentHash != contentHash)
      throw readProtocol('The Plan document identity changed.');
    return h;
  }, (h) => h.scope);
  @override
  Future<PlanDocumentValue> document() => readHeader((c) async {
    final d = await c.document();
    if (d.version != version || d.contentHash != contentHash)
      throw readProtocol('The Plan document identity changed.');
    return d;
  }, (d) => d.scope);
}

StudioFailure readProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'conversation-read-protocol',
);

Future<String> readPinnedIdentity<C extends ConversationTextReadConnection>(
  ConversationConnectionOwner<C> owner,
  C connection,
  ReadText value,
) async {
  if (value is InlineReadText) return value.text;
  final field = value as DeferredReadText;
  var offset = 0;
  final text = StringBuffer();
  while (offset < field.utf8Bytes) {
    if (owner.isClosing) throw conversationCancelled;
    final chunk = await connection.text(
      field.fieldId,
      offset: offset,
      maxBytes: 65536,
    );
    final bytes = utf8.encode(chunk.text).length;
    if (chunk.fieldId != field.fieldId ||
        chunk.offset != offset ||
        bytes == 0 ||
        bytes > 65536 ||
        offset + bytes > field.utf8Bytes ||
        (chunk.nextOffset == null
            ? offset + bytes != field.utf8Bytes
            : chunk.nextOffset != offset + bytes)) {
      throw readProtocol(
        'The original scope identity text did not make exact UTF-8 progress.',
      );
    }
    text.write(chunk.text);
    offset += bytes;
  }
  return text.toString();
}
