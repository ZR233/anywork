import 'dart:async';

import '../../../anywork_client.dart' show ReadModel, ResourceKind;
import '../../../models.dart';
import '../../../studio_ports.dart';
import '../anywork_client.dart';
import '../stores/domain_sync.dart';
import 'command_lane.dart';

/// 只读会话/历史查询。独立 generation 与选择身份，迟到结果不得覆盖新选择。
class BotsQueries extends ReadModel<BotsQueryState> {
  BotsQueries(this._client) : super(const BotsQueryState());

  final AnyworkClient _client;
  _ConversationQuery? _conversations;
  _MessageQuery? _messages;
  final CommandLane _lane = CommandLane();
  int _requestSequence = 0;
  bool _closed = false;

  StudioTransport get _api => _client.transport;

  Future<void> listConversations(String botId, {String? cursor, int? limit}) {
    if (_closed || _client.isClosed) {
      return Future.error(StateError('Bot queries are closed'));
    }
    final identity = _ConversationIdentity(
      botId: botId,
      cursor: cursor,
      limit: limit,
    );
    final existing = _conversations;
    if (existing != null && existing.identity == identity) {
      return existing.future;
    }
    final permit = _client.budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'bots-conversations:${++_requestSequence}',
    );
    final generation = (existing?.generation ?? 0) + 1;
    existing?.invalidate();
    final operation = _ConversationQuery(
      identity: identity,
      generation: generation,
    );
    _conversations = operation;
    operation.completeWith(
      _lane.run(() async {
        try {
          _publishConversations(
            botId: botId,
            loading: true,
            error: null,
            keepPage: state.selectedConversationBotId == botId,
          );
          if (_closed) return;
          await _runConversations(operation, limit: limit);
        } finally {
          permit.release();
        }
      }),
    );
    return operation.future;
  }

  Future<void> readMessages(
    String botId,
    String chatId, {
    int? startTime,
    int? endTime,
    String? cursor,
    int? limit,
  }) {
    if (_closed || _client.isClosed) {
      return Future.error(StateError('Bot queries are closed'));
    }
    final identity = _MessageIdentity(
      botId: botId,
      chatId: chatId,
      startTime: startTime,
      endTime: endTime,
      cursor: cursor,
      limit: limit,
    );
    final existing = _messages;
    if (existing != null && existing.identity == identity) {
      return existing.future;
    }
    final permit = _client.budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'bots-messages:${++_requestSequence}',
    );
    final generation = (existing?.generation ?? 0) + 1;
    existing?.invalidate();
    final operation = _MessageQuery(identity: identity, generation: generation);
    _messages = operation;
    operation.completeWith(
      _lane.run(() async {
        try {
          _publishMessages(
            botId: botId,
            chatId: chatId,
            startTime: startTime,
            endTime: endTime,
            loading: true,
            error: null,
            keepPage:
                state.selectedMessageBotId == botId &&
                state.selectedChatId == chatId &&
                state.selectedStartTime == startTime &&
                state.selectedEndTime == endTime,
          );
          if (_closed) return;
          await _runMessages(operation, limit: limit);
        } finally {
          permit.release();
        }
      }),
    );
    return operation.future;
  }

  void forgetConversations() {
    _conversations?.invalidate();
    _conversations = null;
    if (state.selectedConversationBotId != null ||
        state.conversationsLoading ||
        state.conversationPage != null ||
        state.conversationError != null) {
      state = state.copyWith(
        selectedConversationBotId: null,
        conversationsLoading: false,
        conversationPage: null,
        conversationError: null,
        clearConversationPage: true,
        clearConversationError: true,
        clearConversationSelection: true,
      );
    }
  }

  void forgetMessages() {
    _messages?.invalidate();
    _messages = null;
    if (state.selectedMessageBotId != null ||
        state.messagesLoading ||
        state.messagePage != null ||
        state.messageError != null) {
      state = state.copyWith(
        selectedMessageBotId: null,
        selectedChatId: null,
        selectedStartTime: null,
        selectedEndTime: null,
        messagesLoading: false,
        messagePage: null,
        messageError: null,
        clearMessagePage: true,
        clearMessageError: true,
        clearTimeFilter: true,
        clearMessageSelection: true,
      );
    }
  }

  Future<void> close() {
    _closed = true;
    _lane.seal();
    _conversations?.invalidate();
    _messages?.invalidate();
    return _lane.join();
  }

  /// A binding reply is authoritative in its own revision domain. Invalidate
  /// older reads, while their actual transport work remains owned by the lane.
  void applyBinding(BotConversationThreadBinding binding) {
    if (_closed || _client.isClosed) return;
    final operation = _conversations;
    if (operation?.identity.botId == binding.botId) {
      operation?.invalidate();
      _conversations = null;
      state = state.copyWith(conversationsLoading: false);
    }
    final page = state.conversationPage;
    if (page == null || page.botId != binding.botId) return;
    state = state.copyWith(
      conversationsLoading: false,
      conversationPage: BotConversationPage(
        botId: page.botId,
        nextCursor: page.nextCursor,
        conversations: List.unmodifiable([
          for (final conversation in page.conversations)
            if (conversation.chatId == binding.chatId &&
                (conversation.threadBinding?.revision ?? -1) < binding.revision)
              BotConversation(
                chatId: conversation.chatId,
                kind: conversation.kind,
                source: conversation.source,
                name: conversation.name,
                lastObservedAt: conversation.lastObservedAt,
                threadBinding: binding,
              )
            else
              conversation,
        ]),
      ),
    );
  }

  Future<void> _runConversations(
    _ConversationQuery operation, {
    required int? limit,
  }) async {
    try {
      final page = await _api.listBotConversations(
        ListBotConversationsRequest(
          botId: operation.identity.botId,
          cursor: operation.identity.cursor,
          limit: limit,
        ),
      );
      if (!_acceptsConversations(operation)) return;
      if (page.botId != operation.identity.botId) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'Conversation response does not belong to this bot',
          retryable: false,
          correlationId: 'client-bots-conversations',
        );
      }
      _finishConversations(operation, page: page, error: null);
    } catch (error) {
      if (!_acceptsConversations(operation)) return;
      _finishConversations(operation, page: null, error: error);
      rethrow;
    }
  }

  Future<void> _runMessages(
    _MessageQuery operation, {
    required int? limit,
  }) async {
    try {
      final page = await _api.readBotMessages(
        ReadBotMessagesRequest(
          botId: operation.identity.botId,
          chatId: operation.identity.chatId,
          startTime: operation.identity.startTime,
          endTime: operation.identity.endTime,
          cursor: operation.identity.cursor,
          limit: limit,
        ),
      );
      if (!_acceptsMessages(operation)) return;
      if (page.botId != operation.identity.botId ||
          page.chatId != operation.identity.chatId) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'Message response does not belong to this conversation',
          retryable: false,
          correlationId: 'client-bots-messages',
        );
      }
      _finishMessages(operation, page: page, error: null);
    } catch (error) {
      if (!_acceptsMessages(operation)) return;
      _finishMessages(operation, page: null, error: error);
      rethrow;
    }
  }

  bool _acceptsConversations(_ConversationQuery operation) {
    return identical(_conversations, operation) &&
        !_closed &&
        !_client.isClosed;
  }

  bool _acceptsMessages(_MessageQuery operation) {
    return identical(_messages, operation) && !_closed && !_client.isClosed;
  }

  void _finishConversations(
    _ConversationQuery operation, {
    required BotConversationPage? page,
    required Object? error,
  }) {
    if (!identical(_conversations, operation)) return;
    _conversations = null;
    _publishConversations(
      botId: operation.identity.botId,
      loading: false,
      error: error,
      page: page,
      keepPage: false,
    );
  }

  void _finishMessages(
    _MessageQuery operation, {
    required BotMessagePage? page,
    required Object? error,
  }) {
    if (!identical(_messages, operation)) return;
    _messages = null;
    _publishMessages(
      botId: operation.identity.botId,
      chatId: operation.identity.chatId,
      startTime: operation.identity.startTime,
      endTime: operation.identity.endTime,
      loading: false,
      error: error,
      page: page,
      keepPage: false,
    );
  }

  void _publishConversations({
    required String botId,
    required bool loading,
    required Object? error,
    BotConversationPage? page,
    required bool keepPage,
  }) {
    final next = state.copyWith(
      selectedConversationBotId: botId,
      conversationsLoading: loading,
      conversationPage: page ?? (keepPage ? state.conversationPage : null),
      conversationError: error == null
          ? null
          : typedCommandFailure(
              error,
              correlationId: 'client-bots-conversations',
            ),
      clearConversationPage: page == null && !keepPage,
      clearConversationError: error == null,
    );
    if (next == state) return;
    state = next;
  }

  void _publishMessages({
    required String botId,
    required String chatId,
    required int? startTime,
    required int? endTime,
    required bool loading,
    required Object? error,
    BotMessagePage? page,
    required bool keepPage,
  }) {
    final next = state.copyWith(
      selectedMessageBotId: botId,
      selectedChatId: chatId,
      selectedStartTime: startTime,
      selectedEndTime: endTime,
      messagesLoading: loading,
      messagePage: page ?? (keepPage ? state.messagePage : null),
      messageError: error == null
          ? null
          : typedCommandFailure(error, correlationId: 'client-bots-messages'),
      clearMessagePage: page == null && !keepPage,
      clearMessageError: error == null,
      clearTimeFilter: true,
    );
    if (next == state) return;
    state = next;
  }
}

class BotsQueryState {
  const BotsQueryState({
    this.selectedConversationBotId,
    this.conversationsLoading = false,
    this.conversationPage,
    this.conversationError,
    this.selectedMessageBotId,
    this.selectedChatId,
    this.selectedStartTime,
    this.selectedEndTime,
    this.messagesLoading = false,
    this.messagePage,
    this.messageError,
  });

  final String? selectedConversationBotId;
  final bool conversationsLoading;
  final BotConversationPage? conversationPage;
  final StudioFailure? conversationError;
  final String? selectedMessageBotId;
  final String? selectedChatId;
  final int? selectedStartTime;
  final int? selectedEndTime;
  final bool messagesLoading;
  final BotMessagePage? messagePage;
  final StudioFailure? messageError;

  BotsQueryState copyWith({
    String? selectedConversationBotId,
    bool? conversationsLoading,
    BotConversationPage? conversationPage,
    StudioFailure? conversationError,
    String? selectedMessageBotId,
    String? selectedChatId,
    int? selectedStartTime,
    int? selectedEndTime,
    bool? messagesLoading,
    BotMessagePage? messagePage,
    StudioFailure? messageError,
    bool clearConversationPage = false,
    bool clearConversationError = false,
    bool clearMessagePage = false,
    bool clearMessageError = false,
    bool clearTimeFilter = false,
    bool clearConversationSelection = false,
    bool clearMessageSelection = false,
  }) {
    return BotsQueryState(
      selectedConversationBotId: clearConversationSelection
          ? null
          : selectedConversationBotId ?? this.selectedConversationBotId,
      conversationsLoading: conversationsLoading ?? this.conversationsLoading,
      conversationPage: clearConversationPage
          ? conversationPage
          : conversationPage ?? this.conversationPage,
      conversationError: clearConversationError
          ? conversationError
          : conversationError ?? this.conversationError,
      selectedMessageBotId: clearMessageSelection
          ? null
          : selectedMessageBotId ?? this.selectedMessageBotId,
      selectedChatId: clearMessageSelection
          ? null
          : selectedChatId ?? this.selectedChatId,
      selectedStartTime: clearTimeFilter
          ? selectedStartTime
          : selectedStartTime ?? this.selectedStartTime,
      selectedEndTime: clearTimeFilter
          ? selectedEndTime
          : selectedEndTime ?? this.selectedEndTime,
      messagesLoading: messagesLoading ?? this.messagesLoading,
      messagePage: clearMessagePage
          ? messagePage
          : messagePage ?? this.messagePage,
      messageError: clearMessageError
          ? messageError
          : messageError ?? this.messageError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotsQueryState &&
          selectedConversationBotId == other.selectedConversationBotId &&
          conversationsLoading == other.conversationsLoading &&
          conversationPage == other.conversationPage &&
          conversationError == other.conversationError &&
          selectedMessageBotId == other.selectedMessageBotId &&
          selectedChatId == other.selectedChatId &&
          selectedStartTime == other.selectedStartTime &&
          selectedEndTime == other.selectedEndTime &&
          messagesLoading == other.messagesLoading &&
          messagePage == other.messagePage &&
          messageError == other.messageError;

  @override
  int get hashCode => Object.hash(
    selectedConversationBotId,
    conversationsLoading,
    conversationPage,
    conversationError,
    selectedMessageBotId,
    selectedChatId,
    selectedStartTime,
    selectedEndTime,
    messagesLoading,
    messagePage,
    messageError,
  );
}

class _ConversationIdentity {
  const _ConversationIdentity({required this.botId, this.cursor, this.limit});

  final String botId;
  final String? cursor;
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is _ConversationIdentity &&
      botId == other.botId &&
      cursor == other.cursor &&
      limit == other.limit;

  @override
  int get hashCode => Object.hash(botId, cursor, limit);
}

class _MessageIdentity {
  const _MessageIdentity({
    required this.botId,
    required this.chatId,
    this.startTime,
    this.endTime,
    this.cursor,
    this.limit,
  });

  final String botId;
  final String chatId;
  final int? startTime;
  final int? endTime;
  final String? cursor;
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is _MessageIdentity &&
      botId == other.botId &&
      chatId == other.chatId &&
      startTime == other.startTime &&
      endTime == other.endTime &&
      cursor == other.cursor &&
      limit == other.limit;

  @override
  int get hashCode =>
      Object.hash(botId, chatId, startTime, endTime, cursor, limit);
}

class _ConversationQuery {
  _ConversationQuery({required this.identity, required this.generation});

  final _ConversationIdentity identity;
  final int generation;
  final Completer<void> _completer = Completer<void>();
  bool _invalidated = false;

  Future<void> get future => _completer.future;

  void invalidate() {
    _invalidated = true;
    if (!_completer.isCompleted) _completer.complete();
  }

  void completeWith(Future<void> work) {
    unawaited(
      work.then<void>(
        (_) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.completeError(error, stackTrace);
          }
        },
      ),
    );
  }
}

class _MessageQuery {
  _MessageQuery({required this.identity, required this.generation});

  final _MessageIdentity identity;
  final int generation;
  final Completer<void> _completer = Completer<void>();
  bool _invalidated = false;

  Future<void> get future => _completer.future;

  void invalidate() {
    _invalidated = true;
    if (!_completer.isCompleted) _completer.complete();
  }

  void completeWith(Future<void> work) {
    unawaited(
      work.then<void>(
        (_) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.completeError(error, stackTrace);
          }
        },
      ),
    );
  }
}
