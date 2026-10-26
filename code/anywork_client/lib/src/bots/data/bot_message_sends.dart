import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../domain/bot_message_values.dart';
import 'bot_message_requests.dart';
import 'bot_send_owner.dart';
import 'bots_port.dart';

/// Per-conversation write lanes, budgeted drafts, and a bounded result mirror.
/// Neither cleanup nor observation re-issues an external send.
final class BotMessageSends {
  BotMessageSends(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        BotSendsState(byOperationId: const {}),
        lifetime.budget,
        'bots:sends:observer',
      ) {
    lifetime.onSeal(() {
      source.seal();
      for (final draft in _drafts.values) {
        draft.permit.release();
      }
      _drafts.clear();
    });
  }

  final BotsPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final ResourceSource<BotSendsState> source;
  final Map<(String, String), _MessageDraft> _drafts = {};
  final Map<(String, String), Future<void>> _lanes = {};

  String messageDraft(String botId, String chatId) =>
      _drafts[(botId, chatId)]?.text ?? '';

  void updateMessageDraft(String botId, String chatId, String text) {
    lifetime.admit();
    final key = (botId, chatId);
    if (text.isEmpty) {
      _drafts.remove(key)?.permit.release();
      return;
    }
    var draft = _drafts[key];
    if (draft == null) {
      final ResourcePermit permit;
      try {
        permit = lifetime.budget.acquire(
          ResourceKind.draft,
          owner: 'bot-message:$botId:$chatId',
        );
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
      draft = _MessageDraft(permit);
      _drafts[key] = draft;
    }
    draft.text = text;
  }

  OperationTicket<BotSendResult> send({
    required String botId,
    required String chatId,
    required String text,
  }) {
    lifetime.admit();
    final key = (botId, chatId);
    // Reserve before begin() can synchronously notify/reenter. A newer intent
    // for this same bot/chat can never jump ahead of the original frozen send.
    final previous = _lanes[key] ?? Future<void>.value();
    final done = Completer<void>();
    _lanes[key] = done.future;
    void release() {
      if (identical(_lanes[key], done.future)) unawaited(_lanes.remove(key));
      if (!done.isCompleted) done.complete();
    }

    final OperationWriter<BotSendResult> writer;
    try {
      writer = operations.begin<BotSendResult>(
        target: 'bots:send:$botId:$chatId',
        requireIdentityObservation: true,
      );
    } catch (_) {
      // Even an unadmitted middle slot must not let its successor overtake
      // an older actual invocation still waiting for its transport result.
      unawaited(previous.then<void>((_) => release()));
      rethrow;
    }
    final request = SendBotMessageRequest(
      operationId: writer.ticket.id,
      botId: botId,
      chatId: chatId,
      text: text,
    );
    final owner = BotSendOwner(
      port: port,
      lifetime: lifetime,
      operations: operations,
      writer: writer,
      request: request,
      record: _record,
    );
    try {
      lifetime.register(owner);
      owner.start(previous, release);
    } catch (error, stack) {
      owner.notStarted(error, stack);
      unawaited(previous.then<void>((_) => release()));
    }
    return writer.ticket;
  }

  void _record(BotSendResult result) {
    final next = Map<OperationId, BotSendResult>.of(source.value.byOperationId);
    next[result.operationId] = result;
    while (next.length > 256) {
      next.remove(next.keys.first);
    }
    source.publish(BotSendsState(byOperationId: next));
  }

  void closeSource() => source.close();
}

final class _MessageDraft {
  _MessageDraft(this.permit);
  final ResourcePermit permit;
  String text = '';
}
