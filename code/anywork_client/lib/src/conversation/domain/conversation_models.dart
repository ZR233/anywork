import 'dart:convert';

import '../../../models.dart';

/// Completion position actually accepted by the presentation owner.
final class ConversationCompletionCursor {
  const ConversationCompletionCursor({
    required this.timelineEpoch,
    required this.appendSeq,
  });
  final String timelineEpoch;
  final int appendSeq;
  @override
  bool operator ==(Object other) =>
      other is ConversationCompletionCursor &&
      other.timelineEpoch == timelineEpoch &&
      other.appendSeq == appendSeq;
  @override
  int get hashCode => Object.hash(timelineEpoch, appendSeq);
}

/// A token produced by the history service; clients do not decode it.
final class ConversationQueryCursor {
  const ConversationQueryCursor(this.token);
  final String token;
  @override
  bool operator ==(Object other) =>
      other is ConversationQueryCursor && other.token == token;
  @override
  int get hashCode => token.hashCode;
}

sealed class ConversationItemSource {
  const ConversationItemSource();
}

final class ConversationContentSource extends ConversationItemSource {
  const ConversationContentSource();
}

final class ConversationRecoverySource extends ConversationItemSource {
  const ConversationRecoverySource(this.notice);
  final ConversationRecoveryNotice notice;
}

enum ConversationRecoveryNotice { retry, result }

final class ConversationItemHeader {
  const ConversationItemHeader({
    required this.id,
    required this.threadId,
    this.turnId,
    required this.appendSeq,
    this.sourceEffectSeq,
    this.sealedAt,
  });
  final String id;
  final String threadId;
  final String? turnId;
  final int appendSeq;
  final int? sourceEffectSeq;
  final int? sealedAt;
}

final class ConversationFieldPreview {
  const ConversationFieldPreview({
    required this.field,
    required this.text,
    required this.totalBytes,
  });
  final ThreadContentFieldView field;
  final String text;
  final int totalBytes;
  int get previewBytes => utf8.encode(text).length;
  int get omittedBytes => totalBytes - previewBytes;
}

final class ConversationDetailRef {
  const ConversationDetailRef({
    required this.field,
    required this.totalBytes,
    required this.previewBytes,
  });
  final ThreadContentFieldView field;
  final int totalBytes;
  final int previewBytes;
  bool get truncated => previewBytes < totalBytes;
}

final class ConversationItem {
  ConversationItem({
    required this.header,
    required this.descriptor,
    required this.source,
    required List<ConversationFieldPreview> fields,
  }) : fields = List.unmodifiable(fields);
  final ConversationItemHeader header;
  final ConversationDescriptor descriptor;
  final ConversationItemSource source;
  final List<ConversationFieldPreview> fields;
  String get id => header.id;
  int get omittedBytes => fields.fold(0, (n, field) => n + field.omittedBytes);
  Iterable<ConversationDetailRef> get details => fields.map(
    (field) => ConversationDetailRef(
      field: field.field,
      totalBytes: field.totalBytes,
      previewBytes: field.previewBytes,
    ),
  );
  ConversationFieldPreview? fieldFor(ThreadContentFieldView field) {
    for (final value in fields) {
      if (value.field == field) return value;
    }
    return null;
  }

  ConversationDetailRef? detailFor(ThreadContentFieldView field) {
    final value = fieldFor(field);
    return value == null
        ? null
        : ConversationDetailRef(
            field: field,
            totalBytes: value.totalBytes,
            previewBytes: value.previewBytes,
          );
  }
}

final class ConversationBaseline {
  ConversationBaseline({
    required this.subscriptionId,
    required this.timelineEpoch,
    required List<ConversationItem> items,
    required this.before,
    required this.hasOlder,
    required this.completedCursor,
  }) : items = List.unmodifiable(items);
  final String subscriptionId;
  final String timelineEpoch;
  final List<ConversationItem> items;
  final ConversationQueryCursor? before;
  final bool hasOlder;
  final ConversationCompletionCursor completedCursor;
}

final class ConversationPage {
  ConversationPage({
    required this.threadId,
    required this.timelineEpoch,
    required List<ConversationItem> items,
    required this.before,
    required this.hasOlder,
  }) : items = List.unmodifiable(items);
  final String threadId;
  final String timelineEpoch;
  final List<ConversationItem> items;
  final ConversationQueryCursor? before;
  final bool hasOlder;
}

sealed class ConversationUpdate {
  const ConversationUpdate();
}

final class ConversationBatch extends ConversationUpdate {
  ConversationBatch({
    required this.subscriptionId,
    required this.timelineEpoch,
    required this.fromSeq,
    required this.throughSeq,
    required List<ConversationItem> items,
  }) : items = List.unmodifiable(items);
  final String subscriptionId;
  final String timelineEpoch;
  final int fromSeq;
  final int throughSeq;
  final List<ConversationItem> items;
}

final class ConversationReset extends ConversationUpdate {
  const ConversationReset(this.baseline);
  final ConversationBaseline baseline;
}

final class ConversationDetailQuery {
  const ConversationDetailQuery({
    required this.timelineEpoch,
    required this.field,
    this.continuation,
    this.maxBytes,
  });
  final String timelineEpoch;
  final ThreadContentFieldView field;
  final ConversationQueryCursor? continuation;
  final int? maxBytes;
}

final class ConversationDetailChunk {
  const ConversationDetailChunk({
    required this.threadId,
    required this.timelineEpoch,
    required this.itemId,
    required this.field,
    required this.text,
    required this.totalBytes,
    this.continuation,
  });
  final String threadId;
  final String timelineEpoch;
  final String itemId;
  final ThreadContentFieldView field;
  final String text;
  final int totalBytes;
  final ConversationQueryCursor? continuation;
  bool get isLast => continuation == null;
}
