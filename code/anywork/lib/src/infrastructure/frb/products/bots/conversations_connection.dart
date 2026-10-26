import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/bot_conversations.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/resource_owner.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import 'command_inputs.dart';
import 'conversation_values.dart';

/// A transport/query lifetime only. Closing joins opening and all admitted queries; it never
/// disables a bot, cancels registration, creates a thread or synthesizes a continuation.
final class FrbBotConversationsConnection
    implements BotConversationReadConnection {
  FrbBotConversationsConnection(this._botId) {
    _owner = AdapterResourceOwner(
      resource: 'bots-conversations-read',
      mapFailure: bridgeFailure,
      requestNativeClose: () => _opening.handle?.requestClose(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      expectedIdentity: () => _scopeId ?? '',
    );
    _opening.start(
      _owner,
      () => native.openBotConversations(botId: _botId),
      (handle) => handle.requestClose(),
      attached: _rememberScope,
    );
  }

  final String _botId;
  final _opening =
      ProductNativeOpening<native.BridgeBotConversationsReadConnection>();
  late final AdapterResourceOwner _owner;
  ProductReadScopeIdentity? _scope;
  String? _scopeId;
  String? _nativeBotId;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberScope(native.BridgeBotConversationsReadConnection handle) {
    final raw = handle.identity().scopeId;
    if (raw.isEmpty || _scopeId != null && raw != _scopeId) {
      throw adapterProtocol('bots-conversations-scope');
    }
    _scopeId ??= raw;
    final actualBot = handle.botId();
    if (actualBot.isEmpty ||
        actualBot != _botId ||
        _nativeBotId != null && actualBot != _nativeBotId) {
      throw adapterProtocol('bots-conversations-bot');
    }
    _nativeBotId ??= actualBot;
  }

  void _checkIdentity(native.BridgeBotConversationsReadConnection handle) {
    _rememberScope(handle);
    final scope = productScopeFromBridge(handle.identity());
    if (handle.botId() != _botId ||
        _botId.isEmpty ||
        scope.scopeId != _scopeId ||
        scope.ownerEpoch.isEmpty ||
        scope.incarnation < 1 ||
        scope.version is! ProductValueReadVersion) {
      throw adapterProtocol('bots-conversations-origin');
    }
    final previous = _scope;
    if (previous != null && scope != previous) {
      throw adapterProtocol('bots-conversations-origin');
    }
    _scope ??= scope;
  }

  @override
  String get botId {
    try {
      final captured = _nativeBotId;
      if (captured != null) return captured;
      final handle = _opening.handle;
      if (handle == null) throw adapterProtocol('bots-conversations-opening');
      _checkIdentity(handle);
      return _nativeBotId!;
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.failure(error, stack, source: 'bot-identity'),
        stack,
      );
    }
  }

  @override
  Future<BotConversationPage> page(
    ListBotConversationsRequest request,
  ) => _owner.query(() async {
    if (request.botId != _botId) {
      throw adapterProtocol('bots-conversations-request');
    }
    final input = listBotConversationsToBridge(request);
    final handle = await _opening.ready;
    _owner.ensureOpen();
    _checkIdentity(handle);
    final page = botConversationPageFromBridge(
      await handle.page(request: input),
    );
    _checkIdentity(handle);
    if (page.botId != _botId) throw adapterProtocol('bots-conversations-page');
    for (final conversation in page.conversations) {
      final binding = conversation.threadBinding;
      if (binding != null &&
          (binding.botId != _botId || binding.chatId != conversation.chatId)) {
        throw adapterProtocol('bots-conversations-binding');
      }
    }
    // The exact nextCursor is already copied by the typed converter. It is never decoded,
    // cached as a local index, changed on empty pages, or inferred from the page length.
    return page;
  });

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (_scopeId == null) {
      try {
        _rememberScope(handle);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    // Independent native close still runs when identity conversion or a query failed. Only
    // the original owner's usable close report can authorize disposal.
    return feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
  }

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
