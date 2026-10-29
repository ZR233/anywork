import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/platform/external_url_launcher.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../client/support/conversation_fixtures.dart';

ConversationItem componentText(
  String id, {
  required int ordinal,
  String body = '正文',
  bool terminal = true,
  int? totalBytes,
  int revision = 1,
}) => conversationFixture(
  id: id,
  threadId: 'thread',
  ordinal: ordinal,
  revision: revision,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  lifecycle: terminal
      ? ConversationLifecycle.terminal
      : ConversationLifecycle.streaming,
  descriptor: ConversationTextDescriptor(
    channel: ThreadTextChannel.finalAnswer,
    attachments: const [],
    lifecycle: terminal
        ? CompletedThreadContentView(DateTime.utc(2026))
        : const StreamingThreadContentView(),
  ),
  fields: {const ThreadTextFieldView(): body},
  totalBytes: {const ThreadTextFieldView(): ?totalBytes},
);

ConversationItem componentTool(
  String id, {
  int ordinal = 1,
  String name = 'exec_command',
  required String arguments,
  String result = 'ok',
  int revision = 1,
  List<ThreadAttachmentView> attachments = const [],
  int? totalArgumentsBytes,
  int? totalResultBytes,
}) => conversationFixture(
  id: id,
  threadId: 'thread',
  ordinal: ordinal,
  revision: revision,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  descriptor: ConversationToolDescriptor(
    invocation: ConversationToolInvocation(
      toolCallId: id,
      callId: id,
      name: name,
    ),
    state: ConversationToolSucceeded(
      completedAt: DateTime.utc(2026),
      output: ConversationToolOutputDescriptor(attachments: attachments),
    ),
  ),
  fields: {
    const ThreadToolArgumentsFieldView(): arguments,
    const ThreadToolResultFieldView(): result,
  },
  totalBytes: {
    const ThreadToolArgumentsFieldView(): ?totalArgumentsBytes,
    const ThreadToolResultFieldView(): ?totalResultBytes,
  },
);

ConversationBaseline componentBaseline(
  List<ConversationItem> items, {
  String? before,
  bool hasOlder = false,
}) => ConversationBaseline(
  subscriptionId: 'fixture',
  version: 1,
  items: items,
  before: before,
  hasOlder: hasOlder,
);

/// Assemble the real pure View with production detail/media connectors. These
/// callbacks are test inputs, not a second implementation of scrolling, groups,
/// closing, query scopes or field reconciliation. Unexpected platform launching
/// fails closed; no test in this suite needs the external URL service.
Widget componentTimeline({
  required String threadId,
  required TimelineSessionViewState view,
  required TimelineDisplayLease lease,
  required Future<void> Function() onLoadOlder,
  required Future<void> Function() onRetryOlder,
  required Future<void> Function() onReturnLive,
  required VoidCallback onEnterHistory,
  required VoidCallback onRetryConnection,
}) => Builder(
  builder: (context) => TimelineView(
    key: lease.chatKey,
    threadId: threadId,
    view: view,
    controls: lease,
    onLoadOlder: onLoadOlder,
    onRetryOlder: onRetryOlder,
    onReturnLive: onReturnLive,
    onEnterHistory: onEnterHistory,
    onRetryConnection: onRetryConnection,
    onDetail: (itemId, field) => unawaited(
      openTimelineDetail(context, lease: lease, itemId: itemId, field: field),
    ),
    onLink: (url) => throw UnsupportedError('Unexpected external link: $url'),
    isSafeLink: (url) => safeExternalWebUrl(url) != null,
    imageBuilder: (_, message, index) => TimelineImageConnector(
      key: ValueKey((lease.generation, message.id)),
      message: message,
      index: index,
      item: timelineEntryOf(message)!.first,
      resources: lease.imageResources,
      readBytes: () => ProviderScope.containerOf(context, listen: false)
          .read(anyworkClientProvider)
          .readAttachmentBytes(
            threadId,
            (message.metadata!['attachment'] as ThreadAttachmentView).id,
          ),
      isActive: () => !lease.isRetired,
      onDetail: (itemId, field) => unawaited(
        openTimelineDetail(context, lease: lease, itemId: itemId, field: field),
      ),
    ),
    remoteImageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
    groupMediaBuilder: (item) => TimelineGroupMediaConnector(
      key: ValueKey(item.id),
      item: item,
      resources: lease.imageResources,
      readAttachment: (attachmentId) => ProviderScope.containerOf(
        context,
        listen: false,
      ).read(anyworkClientProvider).readAttachmentBytes(threadId, attachmentId),
      isActive: () => !lease.isRetired,
      onDetail: (itemId, field) => unawaited(
        openTimelineDetail(context, lease: lease, itemId: itemId, field: field),
      ),
    ),
  ),
);
