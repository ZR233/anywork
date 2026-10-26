import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/bot_message_values.dart';
import 'bots_port.dart';

typedef _QueryKey = (String, String, int?, int?, String?, int?);

/// Owns the real query until transport completion, even after a newer display
/// selection. The in-flight map is not a history cache or a retry queue.
final class BotMessageReads {
  BotMessageReads(this.port, this.lifetime)
    : source = ResourceSource(
        const BotMessagesState(),
        lifetime.budget,
        'bots:messages:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final BotsPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<BotMessagesState> source;
  final Map<_QueryKey, _MessageRead> _pending = {};
  int _generation = 0;

  Future<BotMessagePage> read(BotMessageQuery query) {
    lifetime.admit();
    final limit = query.limit;
    if (limit != null && (limit < 0 || limit > 0xffffffff)) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The bot message limit is outside the native u32 range.',
        retryable: false,
        correlationId: 'bots',
      );
    }
    final key = (
      query.botId,
      query.chatId,
      query.startTime,
      query.endTime,
      query.cursor,
      query.limit,
    );
    final pending = _pending[key];
    if (pending != null) {
      // Re-selecting a still-pending query is also the latest display intent.
      pending.generation = ++_generation;
      _loading(query);
      return pending.done.future;
    }
    final ResourcePermit permit;
    try {
      permit = lifetime.budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'bots:messages:${query.botId}:${query.chatId}',
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final read = _MessageRead(++_generation);
    _pending[key] = read;
    unawaited(
      Future<BotMessagePage>.sync(
        () => lifetime.run(
          'bots:messages:${query.botId}:${query.chatId}',
          () async {
            try {
              _loading(query);
              lifetime.admit();
              final page = await port.readMessages(query);
              if (page.botId != query.botId ||
                  page.chatId != query.chatId ||
                  page.messages.any(
                    (message) => message.chatId != query.chatId,
                  ) ||
                  query.cursor != null && page.nextCursor == query.cursor) {
                throw resourceProtocol(
                  'The bot message page changed its query identity or did not advance.',
                );
              }
              lifetime.admit();
              if (read.generation == _generation) {
                source.publish(
                  BotMessagesState(query: query, messagePage: page),
                );
              }
              return page;
            } finally {
              // Display replacement never releases this actual query's permit.
              permit.release();
            }
          },
        ),
      ).then<void>(
        (page) {
          if (identical(_pending[key], read)) _pending.remove(key);
          read.done.complete(page);
        },
        onError: (Object error, StackTrace stack) {
          permit.release();
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          if (identical(_pending[key], read)) _pending.remove(key);
          final failure = resourceFailure(error);
          if (!lifetime.sealed && read.generation == _generation) {
            source.publish(
              BotMessagesState(
                query: query,
                messagePage: source.value.messagePage,
                error: failure,
              ),
            );
          }
          read.done.completeError(failure, stack);
        },
      ),
    );
    return read.done.future;
  }

  void _loading(BotMessageQuery query) {
    final old = source.value;
    final previous = old.query;
    final sameTarget =
        previous != null &&
        previous.botId == query.botId &&
        previous.chatId == query.chatId &&
        previous.startTime == query.startTime &&
        previous.endTime == query.endTime;
    source.publish(
      BotMessagesState(
        query: query,
        messagePage: sameTarget ? old.messagePage : null,
        loading: true,
      ),
    );
  }

  void closeSource() {
    final old = source.value;
    source.publish(
      BotMessagesState(
        query: old.query,
        messagePage: old.messagePage,
        error: old.error,
        closed: true,
      ),
    );
    source.close();
  }
}

final class _MessageRead {
  _MessageRead(this.generation);
  int generation;
  final Completer<BotMessagePage> done = Completer<BotMessagePage>();
}
