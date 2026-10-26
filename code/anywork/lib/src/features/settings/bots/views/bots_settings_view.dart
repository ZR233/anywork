import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_readouts.dart';
import '../../widgets/settings_rows.dart';
import '../state/bots_settings_view_state.dart';
import '../widgets/bot_labels.dart';
import '../widgets/bot_message_view.dart';

/// The Bots settings page: overview, one bot's detail, and its platform tools.
///
/// Structure and order follow the established product page: a fixed header with
/// the back entry and the add action, then the registration attempt, the create
/// section, pending credential work, the bot list, and — on the detail route —
/// connection, model, recent chats and the secondary settings groups.
class BotsSettingsView extends StatelessWidget {
  const BotsSettingsView({
    required this.state,
    required this.bot,
    required this.platformOnly,
    required this.setupOpen,
    required this.canOpenFeishu,
    required this.status,
    required this.error,
    required this.registration,
    required this.setup,
    required this.model,
    required this.conversations,
    required this.conversationsEmpty,
    required this.detailErrors,
    required this.messageErrors,
    required this.accessSection,
    required this.onBack,
    required this.onAddBot,
    required this.onEditBot,
    required this.onOpenBot,
    required this.onOpenBotBrowser,
    required this.onEnabled,
    required this.onRetryConnection,
    required this.onTools,
    required this.onOpenConsole,
    required this.onRetryPending,
    required this.onTrustUser,
    required this.onClearPairing,
    required this.onTrustChat,
    required this.onSelectBot,
    required this.onMessagesRefresh,
    required this.onMessagesNext,
    required this.onMessageDraft,
    required this.onSend,
    required this.onRetrySend,
    super.key,
  });

  final BotsSettingsViewState state;

  /// The bot this route shows; null on the overview route.
  final BotSnapshot? bot;

  /// The platform tools route of [bot] (message history and manual send) is
  /// open, so the configuration groups of the detail route stay hidden.
  final bool platformOnly;

  final bool setupOpen;

  /// The system can hand AppLinks to the platform client; only this gates the
  /// client shortcut, and the browser entry stays available regardless.
  final bool canOpenFeishu;

  /// Compact source / degraded state line; null while the source is healthy.
  final Widget? status;

  /// Page-level failure, already localized by the Smart layer.
  final String? error;

  /// Canonical registration attempt, already placed by the Smart layer.
  final Widget? registration;

  /// Create section of the overview route.
  final Widget? setup;

  /// Model route panel of the detail route.
  final Widget model;

  /// Recent conversations panel of the detail route.
  final Widget conversations;

  /// The selected bot's conversation page is loaded, empty and has no
  /// continuation, so the first-message guidance applies.
  final bool conversationsEmpty;

  final List<String> detailErrors;
  final List<String> messageErrors;

  /// Inbound authorization block of the selected bot.
  final Widget accessSection;

  final VoidCallback onBack;
  final VoidCallback onAddBot;
  final VoidCallback onEditBot;
  final VoidCallback onOpenBot;
  final VoidCallback onOpenBotBrowser;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onRetryConnection;
  final ValueChanged<bool> onTools;
  final VoidCallback onOpenConsole;
  final ValueChanged<String> onRetryPending;
  final void Function(String openId, bool trusted) onTrustUser;
  final ValueChanged<String> onClearPairing;
  final void Function(String chatId, bool trusted) onTrustChat;
  final ValueChanged<String> onSelectBot;
  final VoidCallback onMessagesRefresh;
  final VoidCallback onMessagesNext;
  final ValueChanged<String> onMessageDraft;
  final VoidCallback onSend;

  /// Explicit retry entry after a partial or unknown send. It is never offered
  /// for a settled result and never replays on its own.
  final VoidCallback onRetrySend;

  bool get _addingAllowed =>
      state.editable && !state.registrationActive && !state.registrationPending;

  @override
  Widget build(BuildContext context) {
    final selected = bot;
    final bots = state.bots ?? const <BotSnapshot>[];
    final pending = state.pendingCredentialOperations;
    final registration = this.registration;
    final setup = selected == null && setupOpen && !state.registrationActive
        ? this.setup
        : null;
    return SettingsHeaderPane(
      maxWidth: selected == null ? 1040 : 920,
      header: SettingsHeader(
        title: platformOnly
            ? context.l10n.botsPlatformTools
            : selected?.name ?? context.l10n.settingsBotsTitle,
        subtitle: selected == null
            ? context.l10n.botsOverviewHint
            : context.l10n.botsPlatformFeishu,
        leading: selected == null
            ? null
            : IconButton(
                key: StudioDriverKeys.botsBack,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        trailing: selected != null
            ? null
            : FilledButton.tonalIcon(
                key: StudioDriverKeys.botsAdd,
                onPressed: _addingAllowed ? onAddBot : null,
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.l10n.settingsBotsAdd),
              ),
      ),
      children: [
        ?status,
        const SizedBox(height: 12),
        if (error case final message?) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: message),
        ],
        const SizedBox(height: 16),
        ?registration,
        ?setup,
        if (pending.isNotEmpty)
          SettingsSectionPanel(
            title: context.l10n.settingsBotsPendingTitle,
            children: [
              for (final operation in pending)
                ListTile(
                  key: StudioDriverKeys.botsPending(operation.botId),
                  title: Text(_pendingLabel(context, operation)),
                  subtitle: Text(
                    operation.diagnostic?.message ?? operation.botId,
                  ),
                  trailing: TextButton(
                    onPressed: state.editable
                        ? () => onRetryPending(operation.botId)
                        : null,
                    child: Text(context.l10n.settingsBotsVerify),
                  ),
                ),
            ],
          ),
        if (bots.isEmpty && !setupOpen && registration == null)
          SettingsEmptyMessage(
            icon: Icons.smart_toy_outlined,
            title: context.l10n.settingsBotsEmptyTitle,
            body: context.l10n.settingsBotsEmptyBody,
          )
        else if (selected != null)
          ..._detail(context, selected)
        else if (bots.isNotEmpty)
          BotsListSection(bots: bots, onSelect: onSelectBot),
      ],
    );
  }

  List<Widget> _detail(BuildContext context, BotSnapshot bot) {
    final busy = state.botActions[bot.id]?.preventsResubmission ?? false;
    final available = state.editable && !busy;
    return [
      if (!platformOnly) ...[
        _connection(context, bot, available),
        const SizedBox(height: 8),
        _openChat(context, available),
        const SizedBox(height: 20),
        model,
        const SizedBox(height: 20),
        conversations,
        accessSection,
        _connectionSettings(context, bot, available),
      ],
      if (platformOnly) _messages(context, bot, available),
    ];
  }

  Widget _connection(BuildContext context, BotSnapshot bot, bool available) {
    final connected = bot.connection is BotConnectionConnected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              connected ? Icons.check_circle_outline : Icons.circle_outlined,
              size: 18,
              color: connected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(botConnectionLabel(context, bot.connection))),
            Switch(
              key: StudioDriverKeys.botsEnabled,
              value: bot.enabled,
              onChanged: available ? onEnabled : null,
            ),
          ],
        ),
        if (bot.connection case BotConnectionFailed(
          :final message,
          :final platformCode,
        )) ...[
          SettingsInlineError(
            message: platformCode == '21001'
                ? context.l10n.settingsBotsPolicyDenied
                : message,
          ),
          if (platformCode != null)
            Text(context.l10n.settingsBotsPlatformCode(platformCode)),
          if (platformCode == '21001') ...[
            const SizedBox(height: 8),
            Text(context.l10n.settingsBotsPolicyDeniedHint),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenConsole,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(context.l10n.settingsBotsOpenConsole),
              ),
            ),
          ],
        ],
        // Published safety diagnostics (for example an unfinished pairing
        // cleanup) stay visible next to the connection facts instead of being
        // folded into them.
        if (bot.diagnostic case final diagnostic?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SettingsInlineError(
              key: StudioDriverKeys.botsDiagnostic(bot.id),
              message: diagnostic.message,
            ),
          ),
        for (final message in detailErrors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SettingsInlineError(message: message),
          ),
        if (conversationsEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.l10n.settingsBotsFirstMessageGuide),
          ),
      ],
    );
  }

  Widget _openChat(BuildContext context, bool available) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (canOpenFeishu)
        FilledButton.tonalIcon(
          key: StudioDriverKeys.botsOpenChat,
          onPressed: available ? onOpenBot : null,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(context.l10n.settingsBotsOpenChat),
        ),
      TextButton(
        key: StudioDriverKeys.botsOpenChatBrowser,
        onPressed: available ? onOpenBotBrowser : null,
        child: Text(context.l10n.settingsBotsOpenChatBrowser),
      ),
    ],
  );

  Widget _connectionSettings(
    BuildContext context,
    BotSnapshot bot,
    bool available,
  ) => ExpansionTile(
    key: const PageStorageKey<String>('bot-connection-settings'),
    leading: const Icon(Icons.settings_outlined),
    title: Text(context.l10n.botsConnectionSettings),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
            key: StudioDriverKeys.botsEdit,
            onPressed: available ? onEditBot : null,
            icon: const Icon(Icons.key_outlined),
            label: Text(context.l10n.settingsBotsEdit),
          ),
          TextButton(
            key: StudioDriverKeys.botsRetry,
            onPressed: available ? onRetryConnection : null,
            child: Text(context.l10n.settingsBotsRetryConnection),
          ),
          TextButton.icon(
            onPressed: onOpenConsole,
            icon: const Icon(Icons.open_in_new),
            label: Text(context.l10n.settingsBotsOpenConsole),
          ),
        ],
      ),
      SettingsToggleRow(
        icon: Icons.build_outlined,
        title: context.l10n.settingsBotsTools,
        subtitle: context.l10n.settingsBotsToolsHint,
        value: bot.toolsEnabled,
        onChanged: available ? onTools : (_) {},
      ),
      SettingsReadout(label: context.l10n.settingsBotsAppId, value: bot.appId),
      SettingsReadout(
        label: context.l10n.botsWorkspace,
        value: bot.workspacePath,
      ),
    ],
  );

  Widget _messages(BuildContext context, BotSnapshot bot, bool available) {
    final page = state.messagePage;
    final result = state.latestSend;
    return SettingsSectionPanel(
      title: context.l10n.settingsBotsMessages,
      children: [
        Text(context.l10n.settingsBotsHistoryPermissions),
        const SizedBox(height: 8),
        Text(
          context.l10n.settingsBotsOpenConsoleHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: StudioDriverKeys.botsOpenConsole,
            onPressed: onOpenConsole,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(context.l10n.settingsBotsOpenConsole),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: StudioDriverKeys.botsRefreshMessages,
          onPressed: available ? onMessagesRefresh : null,
          child: Text(context.l10n.settingsBotsRefreshMessages),
        ),
        for (final message in messageErrors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SettingsInlineError(message: message),
          ),
        if (state.messagesPending) const LinearProgressIndicator(),
        for (final message in page?.messages ?? const <BotMessage>[])
          BotMessageView(message: message),
        if (page?.nextCursor != null)
          TextButton(
            key: StudioDriverKeys.botsNextMessages,
            onPressed: available && !state.messagesPending
                ? onMessagesNext
                : null,
            child: Text(context.l10n.settingsBotsNextPage),
          ),
        SettingsFormField(
          value: state.messageDraft,
          label: context.l10n.settingsBotsSendHint,
          enabled: available,
          onChanged: onMessageDraft,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: StudioDriverKeys.botsSend,
            onPressed: available && state.canSend ? onSend : null,
            child: Text(context.l10n.settingsBotsSend),
          ),
        ),
        if (state.sendRetry != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('bots-message-retry'),
              onPressed: available ? onRetrySend : null,
              icon: const Icon(Icons.replay),
              label: Text(context.l10n.runtimeFatalRetry),
            ),
          ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.settingsBotsSendStatus(
                botSendStatusLabel(context, result.status),
              ),
            ),
          ),
        if (result != null) ...[
          SelectableText(
            '${context.l10n.settingsBotsSendOperation}: '
            '${result.operationId.value}',
          ),
          if (result.status == BotSendStatus.partial ||
              result.status == BotSendStatus.unknown)
            Text(context.l10n.settingsBotsNoReplay),
          for (final segment in result.segments)
            Text(
              '${segment.index + 1}: '
              '${botSendStatusLabel(context, segment.status)}'
              '${segment.diagnostic == null ? '' : ' · ${segment.diagnostic!.message}'}',
            ),
        ],
      ],
    );
  }

  String _pendingLabel(
    BuildContext context,
    BotPendingCredentialOperation pending,
  ) => switch (pending.credentialOperation) {
    BotCredentialOperationPreparing() =>
      context.l10n.settingsBotsPendingPreparing,
    BotCredentialOperationCommitUncertain() =>
      context.l10n.settingsBotsPendingUncertain,
    BotCredentialOperationCleanupPending(:final configCommitted) =>
      configCommitted
          ? context.l10n.settingsBotsPendingCleanupCommitted
          : context.l10n.settingsBotsPendingCleanup,
    BotCredentialOperationIdle() => context.l10n.settingsBotsPendingIdle,
  };
}

/// Overview list: local name filter over the canonical rows, in the established
/// order. The query is UI-only state and never selects or reorders by itself.
class BotsListSection extends StatefulWidget {
  const BotsListSection({
    required this.bots,
    required this.onSelect,
    super.key,
  });

  final List<BotSnapshot> bots;
  final ValueChanged<String> onSelect;

  @override
  State<BotsListSection> createState() => _BotsListSectionState();
}

class _BotsListSectionState extends State<BotsListSection> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _filter.text.trim().toLowerCase();
    final visible = widget.bots
        .where((bot) => bot.name.toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: StudioDriverKeys.botsFilter,
          controller: _filter,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: context.l10n.settingsBotsName,
          ),
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            for (final bot in visible)
              ListTile(
                key: StudioDriverKeys.botsRow(bot.id),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                title: Text(bot.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${context.l10n.botsPlatformFeishu} · '
                  '${botConnectionLabel(context, bot.connection)}'
                  '${bot.lastActivityAt == null ? '' : ' · ${botActivityLabel(context, bot.lastActivityAt!)}'}',
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onSelect(bot.id),
              ),
          ],
        ),
      ],
    );
  }
}
