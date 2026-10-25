import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

/// Localized labels for the published Bots facts. These mappings only name a
/// value the domain already decided; they never infer a state.
String botConnectionLabel(
  BuildContext context,
  BotConnectionState connection,
) => switch (connection) {
  BotConnectionConnected() => context.l10n.settingsBotsConnectionConnected,
  BotConnectionConnecting() => context.l10n.settingsBotsConnectionConnecting,
  BotConnectionReconnecting() =>
    context.l10n.settingsBotsConnectionReconnecting,
  BotConnectionFailed() => context.l10n.settingsBotsConnectionFailed,
  BotConnectionDisabled() => context.l10n.settingsBotsConnectionIdle,
};

/// Last observed activity in the platform's own clock, in local time.
String botActivityLabel(BuildContext context, int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  final labels = MaterialLocalizations.of(context);
  return DateUtils.isSameDay(date, DateTime.now())
      ? labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))
      : labels.formatShortDate(date);
}

String botConversationSourceLabel(
  BuildContext context,
  BotConversation conversation,
) => switch (conversation.source) {
  BotConversationSource.remoteGroup => context.l10n.settingsBotsSourceGroup,
  BotConversationSource.observedDirect => context.l10n.settingsBotsSourceDirect,
};

String botSendStatusLabel(BuildContext context, BotSendStatus status) =>
    switch (status) {
      BotSendStatus.succeeded => context.l10n.settingsBotsSendSucceeded,
      BotSendStatus.partial => context.l10n.settingsBotsSendPartial,
      BotSendStatus.rejected => context.l10n.settingsBotsSendRejected,
      BotSendStatus.unknown => context.l10n.settingsBotsSendUnknown,
    };

/// Every message body is a typed domain value; an unsupported body is ordinary
/// readable history with its platform notice, never a decode attempt here.
String botMessageText(BotMessage message) => switch (message.body) {
  BotTextMessageBody(:final text) => text,
  BotPostMessageBody(:final text) => text,
  BotUnsupportedMessageBody(:final notice) => notice,
};
