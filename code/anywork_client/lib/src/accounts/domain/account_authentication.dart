import '../../contracts/stamps.dart';

/// The authentication mechanism selected for a native OpenAI account.
enum AccountAuthenticationMethod { apiKey, chatGpt }

/// Public identity metadata returned after validating a ChatGPT registration.
/// Tokens and other OAuth material are deliberately absent from the Client.
final class ChatGptAccountInfo {
  const ChatGptAccountInfo({
    required this.issuer,
    required this.subject,
    required this.clientId,
    required this.planUsageEnabled,
    this.email,
  });

  final String issuer;
  final String subject;
  final String clientId;
  final String? email;
  final bool planUsageEnabled;
}

sealed class AccountAuthenticationIntent {
  const AccountAuthenticationIntent();
  const factory AccountAuthenticationIntent.keep() = KeepAccountAuthentication;
  const factory AccountAuthenticationIntent.apiKey() =
      SelectApiKeyAuthentication;
  const factory AccountAuthenticationIntent.chatGpt({
    required String loginId,
    required String editorId,
  }) = SelectChatGptAuthentication;
}

final class KeepAccountAuthentication extends AccountAuthenticationIntent {
  const KeepAccountAuthentication();
}

final class SelectApiKeyAuthentication extends AccountAuthenticationIntent {
  const SelectApiKeyAuthentication();
}

final class SelectChatGptAuthentication extends AccountAuthenticationIntent {
  const SelectChatGptAuthentication({
    required this.loginId,
    required this.editorId,
  });

  final String loginId;
  final String editorId;
}

enum ChatGptLoginPhase {
  preparing,
  awaitingBrowser,
  exchangingCode,
  succeeded,
  cancelled,
  failed,
}

enum ChatGptLoginFailureCode {
  network,
  authorizationDenied,
  invalidCallback,
  invalidIdentity,
  missingPlanPermission,
  expired,
  storage,
  taskFailed,
}

final class ChatGptLoginFailure {
  const ChatGptLoginFailure({required this.code, required this.retryable});

  final ChatGptLoginFailureCode code;
  final bool retryable;
}

/// Canonical, token-free observation of one editor-bound login operation.
final class ChatGptLoginSnapshot {
  const ChatGptLoginSnapshot({
    required this.loginId,
    required this.editorId,
    required this.accountId,
    required this.revision,
    required this.phase,
    this.authorizationUrl,
    this.expiresAt,
    this.account,
    this.failure,
  });

  final String loginId;
  final String editorId;
  final String accountId;
  final int revision;
  final ChatGptLoginPhase phase;

  /// Present only while browser authorization is pending. Never log or expose
  /// this value in notifications, diagnostics, or screenshots.
  final String? authorizationUrl;
  final int? expiresAt;
  final ChatGptAccountInfo? account;
  final ChatGptLoginFailure? failure;

  bool get isTerminal => switch (phase) {
    ChatGptLoginPhase.succeeded ||
    ChatGptLoginPhase.cancelled ||
    ChatGptLoginPhase.failed => true,
    _ => false,
  };
}

/// Command acknowledgment routed through the account-domain frame reducer.
final class ChatGptLoginCommandReply {
  const ChatGptLoginCommandReply({required this.stamp, required this.snapshot});

  final ResourceStamp stamp;
  final ChatGptLoginSnapshot snapshot;
}
