import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/timeline_commands.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import 'timeline_view_model.dart';

typedef PlanDetailReadout = ({
  PlanRuntimeView? plan,
  bool Function() isCurrent,
});

typedef _PlanHead = ({int revision, PlanRuntimePhase state, int updatedAt});

const _planWindowBytes = 64 * 1024;

final planDocumentProvider = FutureProvider.autoDispose
    .family<PlanDetailReadout?, String>((ref, threadId) async {
      final conversations = ref.watch(anyworkClientProvider).conversations;
      final owner = ref.watch(timelineSessionOwnerProvider);
      final presentation = ref.watch(
        timelineViewModelProvider(threadId).select((state) {
          final view = state.asData?.value;
          return (
            display: view?.connection == TimelineConnectionPhase.ready
                ? owner.lease(threadId)
                : null,
            error: view?.connectionError ?? state.asError?.error,
          );
        }),
      );
      final stamp = ref.watch(
        threadSessionStoreProvider(threadId)
            .select((state) => _stampOf(state.meta)),
      );
      final display = presentation.display;
      final session = conversations.existingSession(threadId);
      if (presentation.error case final error?) throw error;
      if (display == null || session == null || stamp == null) return null;

      var observed = true;
      ref.onCancel(() => observed = false);
      ref.onResume(ref.invalidateSelf);

      bool isCurrent() =>
          observed &&
          ref.mounted &&
          session.isActive &&
          conversations.visibleThreadId.value == threadId &&
          identical(conversations.existingSession(threadId), session) &&
          identical(owner.lease(threadId), display) &&
          display.canRead &&
          _stampOf(session.state.meta) == stamp;

      final plan = await _readPlan(session, stamp.ownerEpoch, isCurrent);
      if (!isCurrent() || _headOf(plan) != stamp.head) {
        throw StateError('The Plan changed during the detail read');
      }
      return (plan: plan, isCurrent: isCurrent);
    }, retry: (_, _) => null);

({String ownerEpoch, _PlanHead? head})? _stampOf(SessionMetaSnapshot? meta) =>
    meta == null
    ? null
    : (ownerEpoch: meta.ownerEpoch, head: _headOf(meta.plan));

_PlanHead? _headOf(PlanRuntimeView? plan) => plan == null
    ? null
    : (
        revision: plan.revision,
        state: plan.state,
        updatedAt:
            plan.updatedAt.millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond,
      );

Future<PlanRuntimeView?> _readPlan(
  ConversationSession session,
  String ownerEpoch,
  bool Function() isCurrent,
) async {
  final bytes = BytesBuilder(copy: false);
  (int, int)? snapshot;
  do {
    if (!isCurrent()) throw ThreadStateResyncCancelled(session.threadId);
    final offset = bytes.length;
    final window = await session.readSessionDetail(
      kind: SessionDetailKind.plan,
      offset: offset,
      maxBytes: _planWindowBytes,
    );
    if (!isCurrent()) throw ThreadStateResyncCancelled(session.threadId);
    final next = (window.revision, window.totalBytes);
    if (window.ownerEpoch != ownerEpoch ||
        (snapshot != null && next != snapshot)) {
      throw StateError(
        'The session snapshot changed during the Plan detail read',
      );
    }
    snapshot = next;
    if (window.offset != offset ||
        window.bytes.isEmpty ||
        window.bytes.length > _planWindowBytes ||
        window.bytes.length > window.totalBytes - offset) {
      throw const FormatException('Invalid Plan detail window');
    }
    bytes.add(window.bytes);
  } while (bytes.length < snapshot.$2);
  return _decodePlan(jsonDecode(utf8.decode(bytes.takeBytes())));
}

PlanRuntimeView? _decodePlan(Object? json) {
  if (json == null) return null;
  if (json
      case final Map<String, Object?> envelope &&
          {
            'revision': final int revision,
            'state': final String state,
            'updatedAt': final int updatedAt,
          }
      when revision >= 0 &&
          updatedAt >= -8640000000000 &&
          updatedAt <= 8640000000000) {
    final phase = PlanRuntimePhase.values.asNameMap()[state];
    if (phase == null) throw const FormatException('Invalid Plan detail state');
    final document = switch (envelope['document']) {
      null => null,
      {
        'version': final int version,
        'markdown': final String markdown,
        'contentHash': final String contentHash,
      }
          when version >= 0 =>
        PlanDocumentView(
          version: version,
          markdown: markdown,
          contentHash: contentHash,
        ),
      _ => throw const FormatException('Invalid Plan detail document'),
    };
    return PlanRuntimeView(
      revision: revision,
      state: phase,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedAt * Duration.millisecondsPerSecond,
      ),
      document: document,
    );
  }
  throw const FormatException('Invalid Plan detail');
}
