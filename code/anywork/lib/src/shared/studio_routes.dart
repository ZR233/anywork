import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Product destinations only. GoRouter owns the page stack and return values.
abstract final class StudioRoutes {
  static const studio = 'studio';
  static const settings = 'settings';
  static const botDetails = 'bot-details';
  static const botConversation = 'bot-conversation';
  static const botPlatformTools = 'bot-platform-tools';

  static Future<void> openBotDetails(BuildContext context, String botId) =>
      _open(context, botDetails, {'botId': botId});

  static Future<void> openBotConversation(
    BuildContext context, {
    required String botId,
    required String chatId,
    required String threadId,
  }) => _open(context, botConversation, {
    'botId': botId,
    'chatId': chatId,
    'threadId': threadId,
  });

  static Future<void> openBotPlatformTools(
    BuildContext context, {
    required String botId,
    required String chatId,
  }) => _open(context, botPlatformTools, {'botId': botId, 'chatId': chatId});

  static Future<void> _open(
    BuildContext context,
    String name,
    Map<String, String> parameters,
  ) async {
    final router = GoRouter.of(context);
    final current = router.routerDelegate.state;
    if (current.name == name && mapEquals(current.pathParameters, parameters)) {
      return;
    }
    await router.pushNamed<void>(name, pathParameters: parameters);
  }
}
