import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import '../platform/public_artifact_platform.dart';

/// Local destination/open results are not publication, historySaved or Feishu
/// delivery. Only this AppGraph owns these bounded operations and their join.
enum PublicArtifactSaveOutcome {
  cancelled,
  retired,
  saved,
  savedNotOpened,
  handedToSystem,
  failed,
}

final class PublicArtifactSaveResult {
  const PublicArtifactSaveResult(this.outcome, {this.error});
  final PublicArtifactSaveOutcome outcome;
  final Object? error;
}

final class PublicArtifactSaveState {
  const PublicArtifactSaveState({this.running = false, this.result});
  final bool running;
  final PublicArtifactSaveResult? result;
}

typedef PublicArtifactActionKey = (
  String threadId,
  String itemId,
  int revision,
  String publicationId,
  String toolCallId,
  String displayName,
  ThreadArtifactResource resource,
  DateTime publishedAt,
);

final class PublicArtifactActions
    extends ReadModel<Map<PublicArtifactActionKey, PublicArtifactSaveState>> {
  PublicArtifactActions({required this.client, required this.platform})
    : super(const {});
  final AnyworkClient client;
  final PublicArtifactPlatform platform;
  final Set<Future<void>> _tasks = {};
  bool _closed = false;
  Future<void>? _closing;

  PublicArtifactActionKey keyOf(ThreadItemView item) {
    final artifact = item.state;
    if (artifact is! ThreadPublicArtifactItemStateView) {
      throw ArgumentError('Not a public artifact');
    }
    return (
      item.threadId,
      item.id,
      item.revision,
      artifact.publicationId,
      artifact.toolCallId,
      artifact.displayName,
      artifact.resource,
      artifact.publishedAt,
    );
  }

  Future<PublicArtifactSaveResult> save(
    ThreadItemView item, {
    required bool openAfterSave,
    required bool Function() isCurrent,
  }) {
    if (_closed || client.isClosed) {
      return Future.error(StateError('Artifact actions closed'));
    }
    // Freeze every identity/metadata/intent before invoking any platform await.
    final artifact = item.state;
    if (artifact is! ThreadPublicArtifactItemStateView) {
      return Future.error(ArgumentError('Not a public artifact'));
    }
    final key = keyOf(item);
    final threadId = item.threadId;
    final resource = artifact.resource;
    final name = artifact.displayName;
    final shouldOpen = openAfterSave;
    if (state[key]?.running == true) {
      return Future.error(StateError('Artifact action already running'));
    }
    if (!isCurrent()) {
      return Future.value(
        const PublicArtifactSaveResult(PublicArtifactSaveOutcome.retired),
      );
    }
    final permit = client.budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'public-artifact:${key.$1}:${key.$2}:${key.$3}',
    );
    final joined = Completer<void>();
    _tasks.add(joined.future);
    _publish(key, const PublicArtifactSaveState(running: true));
    return Future<PublicArtifactSaveResult>.sync(() async {
          var saved = false;
          try {
            final destination = await platform.chooseSavePath(name);
            if (destination == null) {
              return const PublicArtifactSaveResult(
                PublicArtifactSaveOutcome.cancelled,
              );
            }
            if (_closed || client.isClosed || !isCurrent()) {
              return const PublicArtifactSaveResult(
                PublicArtifactSaveOutcome.retired,
              );
            }
            // resource.id, never publicationId or displayName. Host checks exact
            // canonical publication metadata, Thread ownership, length and digest.
            final bytes = await client.readAttachmentBytes(
              threadId,
              resource.id,
            );
            if (bytes.length != resource.byteLen ||
                resource.byteLen < 0 ||
                resource.byteLen > 50 * 1024 * 1024) {
              throw const StudioFailure(
                code: StudioFailureCode.protocol,
                message: 'Public artifact length differs from its canonical resource',
                retryable: false,
                correlationId: 'client-artifact-length',
              );
            }
            // Reading/validation failed above cannot have truncated an old target.
            // Once I/O starts it is always joined, even if the display retires.
            await platform.writeBytes(destination, bytes);
            saved = true;
            if (!shouldOpen) {
              return const PublicArtifactSaveResult(
                PublicArtifactSaveOutcome.saved,
              );
            }
            if (_closed || !isCurrent()) {
              return const PublicArtifactSaveResult(
                PublicArtifactSaveOutcome.savedNotOpened,
              );
            }
            final opened = await platform.openFile(destination);
            return PublicArtifactSaveResult(
              opened
                  ? PublicArtifactSaveOutcome.handedToSystem
                  : PublicArtifactSaveOutcome.savedNotOpened,
            );
          } catch (error) {
            return PublicArtifactSaveResult(
              saved
                  ? PublicArtifactSaveOutcome.savedNotOpened
                  : PublicArtifactSaveOutcome.failed,
              error: error,
            );
          }
        })
        .then((result) {
          // No late result is published to a different display incarnation. The
          // returned result still belongs to its caller and user files are untouched.
          if (!_closed && isCurrent()) {
            _publish(key, PublicArtifactSaveState(result: result));
          } else if (!_closed) {
            final next =
                Map<PublicArtifactActionKey, PublicArtifactSaveState>.of(state)
                  ..remove(key);
            state = Map.unmodifiable(next);
          }
          return result;
        })
        .whenComplete(() {
          permit.release();
          _tasks.remove(joined.future);
          joined.complete();
        });
  }

  void _publish(PublicArtifactActionKey key, PublicArtifactSaveState value) {
    final next = Map<PublicArtifactActionKey, PublicArtifactSaveState>.of(state)
      ..remove(key);
    next[key] = value;
    for (final entry in List.of(next.entries)) {
      if (next.length <= 32) break;
      if (!entry.value.running) next.remove(entry.key);
    }
    state = Map.unmodifiable(next);
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    _closed =
        true; // Seal before joining a chooser/read/write/open in progress.
    final joined = _closing ??= Future.wait<void>(List.of(_tasks));
    try {
      if (deadline == null) {
        await joined;
      } else {
        final remaining = deadline.difference(DateTime.now());
        await joined.timeout(remaining.isNegative ? Duration.zero : remaining);
      }
      return CloseReport();
    } on TimeoutException catch (error) {
      // Keep actual task futures and their permits; a timeout is not an ACK.
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'public-artifact-actions',
            attemptId: const AttemptId(0),
            reason: error,
          ),
        ],
      );
    }
  }
}
