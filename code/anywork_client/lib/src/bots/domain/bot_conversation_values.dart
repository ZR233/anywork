import 'package:freezed_annotation/freezed_annotation.dart';

import 'bot_values.dart';

part 'bot_conversation_values.freezed.dart';

enum BotConversationSource { remoteGroup, observedDirect }

enum BotConversationKind { group, direct }

enum BotConversationThreadState { creating, bound, needsAttention }

@Freezed(toStringOverride: false)
abstract class BotConversationThreadBinding
    with _$BotConversationThreadBinding {
  const factory BotConversationThreadBinding({
    required String botId,
    required String chatId,
    required String projectId,
    required String? threadId,
    required int revision,
    required BotConversationThreadState state,
    required BotDiagnostic? diagnostic,
  }) = _BotConversationThreadBinding;
}

@Freezed(toStringOverride: false)
abstract class BotConversation with _$BotConversation {
  const factory BotConversation({
    required String chatId,
    required BotConversationKind kind,
    required BotConversationSource source,
    required String? name,
    required int? lastObservedAt,
    required BotConversationThreadBinding? threadBinding,
  }) = _BotConversation;
}

/// Page order and cursor are the native query's, not a locally sorted index.
@Freezed(toStringOverride: false)
final class BotConversationPage with _$BotConversationPage {
  BotConversationPage({
    required this.botId,
    required List<BotConversation> conversations,
    required this.nextCursor,
  }) : conversations = List.unmodifiable(conversations);

  final String botId;
  final List<BotConversation> conversations;
  final String? nextCursor;
}
