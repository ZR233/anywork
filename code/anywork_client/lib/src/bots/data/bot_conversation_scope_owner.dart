import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/bot_conversation_read_scope.dart';
import '../domain/bot_conversation_values.dart';
import '../domain/bots_state.dart';
import 'bots_commands_values.dart';
import 'bots_port.dart';

/// A private owner of one bot-bound query scope, registered with the Repository
/// before any native open. Its lifetime shares the application's real budget.
final class BotConversationScopeOwner
    implements BotConversationReadScope, ResourceOwner {
  BotConversationScopeOwner(this.port, this.parent, this.botId)
    : attempt = parent.nextAttempt(),
      lifetime = ResourceLifetime(parent.budget),
      source = ResourceSource(
        BotConversationsState(
          botId: botId,
          page: null,
          continuation: const CollectionContinuation.unknown(),
          loading: false,
          error: null,
          closed: false,
        ),
        parent.budget,
        'bots:conversations:$botId:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final BotsPort port;
  final ResourceLifetime parent;
  final ResourceLifetime lifetime;
  final ResourceSource<BotConversationsState> source;
  @override
  final String botId;
  @override
  final int attempt;
  @override
  String get owner => 'bots:conversations:$botId:$attempt';
  @override
  ReadonlyLatestValue<BotConversationsState> get state => source.readonly;
  PinnedReadOwner<BotConversationReadConnection>? _pin;
  final Map<({String? cursor, int? limit}), _BotPageRead> _pages = {};
  int _generation = 0;
  bool _released = false;
  CloseReport? _report;

  void start() {
    lifetime.admit();
    final registered = Completer<void>();
    final pin = PinnedReadOwner<BotConversationReadConnection>(
      lifetime: lifetime,
      owner: owner,
      open: () async {
        await registered.future;
        return port.openConversations(botId);
      },
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
    _pin = pin;
    registered.complete();
  }

  @override
  Future<BotConversationPage> page({String? cursor, int? limit}) {
    lifetime.admit();
    // Native owns its default/clamping policy. Zero is a valid u32 input; do
    // not silently replace it or trim/rebuild an opaque cursor.
    if (limit != null && (limit < 0 || limit > 0xffffffff)) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The bot conversation limit is outside the native u32 range.',
        retryable: false,
        correlationId: 'bots',
      );
    }
    final key = (cursor: cursor, limit: limit);
    final pending = _pages[key];
    if (pending != null) {
      // Re-selecting an earlier in-flight cursor joins that exact query but
      // still becomes the newest presentation intent; another cursor's late
      // result must not overwrite it merely because the query was coalesced.
      pending.generation = ++_generation;
      source.publish(source.value.copyWith(loading: true, error: null));
      return pending.done.future;
    }
    final read = _BotPageRead(++_generation);
    final done = read.done;
    _pages[key] = read;
    final request = ListBotConversationsRequest(
      botId: botId,
      cursor: cursor,
      limit: limit,
    );
    unawaited(
      Future<BotConversationPage>.sync(
        () => lifetime.run(owner, () async {
          source.publish(source.value.copyWith(loading: true, error: null));
          final pin = _pin;
          if (pin == null) throw resourceCancelled;
          final result = await pin.use((scope) async {
            if (scope.botId != botId) {
              throw resourceProtocol(
                'The bot conversation read opened another bot.',
              );
            }
            lifetime.admit();
            return scope.page(request);
          });
          if (result.botId != botId ||
              cursor != null && result.nextCursor == cursor) {
            throw resourceProtocol(
              'The bot conversation page changed its query or did not advance.',
            );
          }
          for (final conversation in result.conversations) {
            final binding = conversation.threadBinding;
            if (binding != null)
              validateBotBinding(binding, botId, conversation.chatId);
          }
          lifetime.admit();
          if (read.generation == _generation) {
            source.publish(
              source.value.copyWith(
                page: result,
                loading: false,
                continuation: result.nextCursor == null
                    ? const CollectionContinuation.end()
                    : CollectionContinuation.cursor(value: result.nextCursor!),
                error: null,
              ),
            );
          }
          return result;
        }),
      ).then<void>(
        (value) {
          _pages.remove(key);
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          parent.lastCause = error;
          parent.lastStack = stack;
          _pages.remove(key);
          if (!lifetime.sealed && read.generation == _generation) {
            source.publish(
              source.value.copyWith(
                loading: false,
                error: resourceFailure(error),
              ),
            );
          }
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  @override
  bool get released => _released;
  @override
  void requestClose() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);
  @override
  Future<void> cleanup({required bool retry}) async {
    await _close(null, retry);
  }

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    _report = report;
    if (report.complete && !_released) {
      _released = true;
      source.publish(source.value.copyWith(loading: false, closed: true));
      source.close();
    }
    return report;
  }

  @override
  List<FeedCloseIssue> get issues => _released
      ? const []
      : [
          for (final resource
              in (_report ?? lifetime.snapshotReport()).unresolved)
            ...resource.issues,
          if ((_report ?? lifetime.snapshotReport()).complete)
            resourcePendingIssue('botReadScopeOpen'),
        ];
}

final class _BotPageRead {
  _BotPageRead(this.generation);
  int generation;
  final Completer<BotConversationPage> done = Completer<BotConversationPage>();
}

void validateBotBinding(
  BotConversationThreadBinding binding,
  String botId,
  String chatId,
) {
  if (binding.botId != botId ||
      binding.chatId != chatId ||
      binding.revision < 0 ||
      binding.state == BotConversationThreadState.bound &&
          binding.threadId == null) {
    throw resourceProtocol(
      'A bot thread binding belongs to another conversation or has no bound Thread.',
    );
  }
}
