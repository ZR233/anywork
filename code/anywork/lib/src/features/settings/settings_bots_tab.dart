import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../platform/feishu_app_links.dart';
import '../../presentation/providers/client_provider.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/model_route_selector.dart';
import '../shell/studio_shell.dart';
import 'settings_agent_routes.dart';

import 'package:anywork_client/studio_client.dart';

import 'settings_common.dart';
import 'settings_scope.dart';
import 'settings_views.dart';

part 'settings_bots_editor.dart';
part 'settings_bots_detail.dart';
part 'settings_bots_registration.dart';

/// 飞书中国版开发者后台固定入口；仅本机点击打开，不携带凭据或票据。
const _feishuDeveloperConsoleUrl = 'https://open.feishu.cn/app';

class BotsTab extends ConsumerStatefulWidget {
  const BotsTab({super.key, required this.tabIndex, this.botId, this.chatId});

  final String? botId;
  final String? chatId;

  final int tabIndex;

  @override
  ConsumerState<BotsTab> createState() => _BotsTabState();
}

class _BotsTabState extends ConsumerState<BotsTab> {
  String? _selectedBotId;
  final _filter = TextEditingController();
  bool _setupOpen = false;
  bool _manualSetup = false;
  bool _busy = false;
  String? _error;
  late final TextEditingController _name;
  late final TextEditingController _appId;
  late final TextEditingController _secret;
  late final TextEditingController _sendText;
  String? _selectedChatId;

  late final AnyworkClient _client;

  @override
  void initState() {
    super.initState();
    _client = ref.read(anyworkClientProvider);
    final draft = _client.botsCommands.setupDraft;
    _name = TextEditingController(text: draft.name);
    _appId = TextEditingController(text: draft.appId);
    _secret = TextEditingController();
    _selectedBotId = widget.botId;
    _selectedChatId = widget.chatId;
    if (widget.botId case final id?) {
      Future<void>.microtask(
        () => _runQuery(id, () => _client.botsQueries.listConversations(id)),
      );
    }
    _sendText = TextEditingController(
      text: _client.botsCommands.messageDraft(
        _selectedBotId ?? '',
        _selectedChatId ?? '',
      ),
    );
    if (widget.chatId != null && widget.botId != null) {
      Future<void>.microtask(
        () => _readMessages(widget.botId!, widget.chatId!),
      );
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    _name.dispose();
    _appId.dispose();
    _secret.dispose();
    _sendText.dispose();
    _client.botsCommands.clearSecret();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.botId != null ||
        ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
    watchSettingsScope(
      ref,
      visible: visible,
      kind: BridgeSettingsScopeKind.bots,
    );
    final view = ref.watch(settingsBotsViewProvider);
    final canOpenFeishu =
        ref.watch(feishuClientAvailableProvider).asData?.value == true;
    final snapshot = view.snapshot ?? const BotsStateSnapshot.empty();
    final selected = _selectedBot(snapshot);
    final registration = snapshot.registration;
    final registering = switch (registration?.status) {
      BotRegistrationPreparing() ||
      BotRegistrationWaiting() ||
      BotRegistrationSlowDown() ||
      BotRegistrationCommitting() => true,
      _ => false,
    };
    return SettingsPane(
      maxWidth: selected == null ? 1040 : 920,
      header: SettingsHeader(
        title: widget.chatId != null
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
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              ),
        trailing: selected != null
            ? null
            : FilledButton.tonalIcon(
                key: StudioDriverKeys.botsAdd,
                onPressed: _busy || registering
                    ? null
                    : () => setState(() => _setupOpen = true),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.l10n.settingsBotsAdd),
              ),
      ),
      children: [
        if (visible) const SettingsTopicStatus(topic: BotsTopic()),
        const SizedBox(height: 12),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: error),
        ],
        const SizedBox(height: 16),
        if (selected == null &&
            registration != null &&
            (registering || !_setupOpen))
          SettingsSectionPanel(
            title: registration.name,
            children: [
              _RegistrationPanel(
                attempt: registration,
                busy: _busy,
                canOpenFeishu: canOpenFeishu,
                onOpenFeishu: (url) =>
                    _openBotLink(feishuRegistrationAppLink(url)),
                onOpenLink: (url) => _openBotLink(safeExternalWebUrl(url)),
                onCopyLink: (url) =>
                    _run(() => Clipboard.setData(ClipboardData(text: url))),
                onCancel: () => _run(
                  () => _client.botsCommands.cancelRegistration(
                    attemptId: registration.attemptId,
                  ),
                ),
              ),
            ],
          ),
        if (selected == null && _setupOpen && !registering)
          _buildSetup(context, view),
        if (snapshot.pendingCredentialOperations.isNotEmpty) ...[
          SettingsSectionPanel(
            title: context.l10n.settingsBotsPendingTitle,
            children: [
              for (final pending in snapshot.pendingCredentialOperations)
                _PendingCredentialTile(
                  pending: pending,
                  onRetry: _busy
                      ? null
                      : () => _run(
                          () => _client.botsCommands.retryConnection(
                            botId: pending.botId,
                          ),
                        ),
                ),
            ],
          ),
        ],
        if (snapshot.bots.isEmpty && !_setupOpen && registration == null)
          SettingsEmptyMessage(
            icon: Icons.smart_toy_outlined,
            title: context.l10n.settingsBotsEmptyTitle,
            body: context.l10n.settingsBotsEmptyBody,
          )
        else if (selected != null)
          _BotDetail(
            bot: selected,
            platformOnly: widget.chatId != null,
            view: view,
            canOpenFeishu: canOpenFeishu,
            selectedChatId: _selectedChatId,
            sendController: _sendText,
            busy: _busy,
            model: _buildModel(selected),
            onOpenConversation: (conversation) =>
                _openConversation(selected, conversation),
            onEdit: () => _editBot(selected),
            onDraftChanged: (value) {
              try {
                _client.botsCommands.updateMessageDraft(
                  selected.id,
                  _selectedChatId!,
                  value,
                );
              } catch (_) {
                setState(
                  () => _error = context.l10n.settingsBotsOperationFailed,
                );
              }
            },
            onSelectChat: (id) => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => BotDetailsPage(botId: selected.id, chatId: id),
              ),
            ),
            onEnabled: (enabled) => _run(
              () => _client.botsCommands.setEnabled(
                botId: selected.id,
                expectedConfigRevision: selected.configRevision,
                enabled: enabled,
              ),
            ),
            onRetry: () => _run(
              () => _client.botsCommands.retryConnection(botId: selected.id),
            ),
            onTools: (enabled) => _run(
              () => _client.botsCommands.saveBot(
                botId: selected.id,
                expectedConfigRevision: selected.configRevision,
                name: selected.name,
                projectId: selected.projectId,
                appId: selected.appId,
                secret: const BotSecretPreserve(),
                enabled: selected.enabled,
                toolsEnabled: enabled,
              ),
            ),
            onTrustUser: (openId, trusted) => _run(
              () => _client.botsCommands.setTrustedUser(
                botId: selected.id,
                expectedConfigRevision: selected.configRevision,
                openId: openId,
                trusted: trusted,
              ),
            ),
            // 清理配对请求复用同一信任写入命令，只把当前信任值原样
            // 写回。信任值与配置 revision 取自同一次构建的同一个
            // canonical 快照，不会用旧值搭配新 revision 意外授权。
            onClearPairingRequest: (openId) => _run(
              () => _client.botsCommands.setTrustedUser(
                botId: selected.id,
                expectedConfigRevision: selected.configRevision,
                openId: openId,
                trusted: selected.trustedOpenIds.contains(openId),
              ),
            ),
            onTrustChat: (chatId, trusted) => _run(
              () => _client.botsCommands.setTrustedChat(
                botId: selected.id,
                expectedConfigRevision: selected.configRevision,
                chatId: chatId,
                trusted: trusted,
              ),
            ),
            onLoadConversations: (cursor) => _runQuery(
              selected.id,
              () => _client.botsQueries.listConversations(
                selected.id,
                cursor: cursor,
              ),
            ),
            onLoadMessages: (cursor) =>
                _readMessages(selected.id, _selectedChatId!, cursor: cursor),
            onCreateThread: (conversation) =>
                _createThread(selected, conversation),
            onSend: () => _run(() {
              final chatId = _selectedChatId;
              if (chatId == null) {
                throw StateError('No conversation selected');
              }
              return _client.botsCommands.sendMessage(
                botId: selected.id,
                chatId: chatId,
                text: _sendText.text,
              );
            }),
            onOpenConsole: _openDeveloperConsole,
            onOpenBot: () => _openBotLink(feishuBotAppLink(selected.appId)),
            onOpenBotBrowser: () =>
                _openBotLink(feishuBotAppLink(selected.appId, browser: true)),
          ),
        if (selected == null && snapshot.bots.isNotEmpty) ...[
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
          _BotList(
            bots: snapshot.bots
                .where(
                  (bot) => bot.name.toLowerCase().contains(
                    _filter.text.trim().toLowerCase(),
                  ),
                )
                .toList(),
            selectedId: null,
            onSelect: (id) {
              Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => BotDetailsPage(botId: id)),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSetup(BuildContext context, SettingsBotsView view) {
    return SettingsSectionPanel(
      title: context.l10n.settingsBotsSetupTitle,
      trailing: TextButton(
        onPressed: _busy ? null : () => setState(() => _setupOpen = false),
        child: Text(context.l10n.settingsBotsSetupClose),
      ),
      children: [
        Text(
          context.l10n.settingsBotsRisk,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.settingsBotsPermissions,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          view.modelConfigured
              ? context.l10n.settingsBotsModelReady
              : context.l10n.settingsBotsModelMissing,
        ),
        const SizedBox(height: 12),
        TextField(
          key: StudioDriverKeys.botsName,
          controller: _name,
          enabled: !_busy,
          decoration: InputDecoration(labelText: context.l10n.settingsBotsName),
          onChanged: (_) => _syncDraft(view),
        ),
        const SizedBox(height: 10),
        SettingsToggleRow(
          key: StudioDriverKeys.botsRiskAck,
          icon: Icons.warning_amber_outlined,
          title: context.l10n.settingsBotsRiskAck,
          value: _client.botsCommands.setupDraft.riskAcknowledged,
          onChanged: (value) {
            _client.botsCommands.updateSetupDraft(
              _client.botsCommands.setupDraft.copyWith(riskAcknowledged: value),
            );
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: StudioDriverKeys.botsScan,
              onPressed:
                  _busy || !_client.botsCommands.setupDraft.riskAcknowledged
                  ? null
                  : () => _startScan(view),
              child: Text(context.l10n.settingsBotsScan),
            ),
            OutlinedButton(
              key: StudioDriverKeys.botsManual,
              onPressed: _busy
                  ? null
                  : () => setState(() => _manualSetup = true),
              child: Text(context.l10n.settingsBotsManual),
            ),
          ],
        ),
        if (_manualSetup) ...[
          const SizedBox(height: 16),
          Text(context.l10n.settingsBotsManualGuide),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsBotsOpenConsoleHint,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: StudioDriverKeys.botsOpenConsoleManual,
              onPressed: _openDeveloperConsole,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(context.l10n.settingsBotsOpenConsole),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: StudioDriverKeys.botsAppId,
            decoration: InputDecoration(
              labelText: context.l10n.settingsBotsAppId,
            ),
            controller: _appId,
            enabled: !_busy,
            onChanged: (_) => _syncDraft(view),
          ),
          const SizedBox(height: 10),
          TextField(
            key: StudioDriverKeys.botsSecret,
            decoration: InputDecoration(
              labelText: context.l10n.settingsBotsSecret,
            ),
            controller: _secret,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: StudioDriverKeys.botsSave,
              onPressed:
                  _busy || !_client.botsCommands.setupDraft.riskAcknowledged
                  ? null
                  : () => _saveManual(view),
              child: Text(context.l10n.settingsBotsSave),
            ),
          ),
        ],
      ],
    );
  }

  BotSnapshot? _selectedBot(BotsStateSnapshot snapshot) {
    if (snapshot.bots.isEmpty) return null;
    final id = _selectedBotId;
    for (final bot in snapshot.bots) {
      if (bot.id == id) return bot;
    }
    return null;
  }

  void _syncDraft(SettingsBotsView view) {
    _client.botsCommands.updateSetupDraft(
      _client.botsCommands.setupDraft.copyWith(
        name: _name.text,
        projectId: '',
        appId: _appId.text,
      ),
    );
  }

  Future<void> _startScan(SettingsBotsView view) {
    _syncDraft(view);
    final draft = _client.botsCommands.setupDraft;
    return _run(() async {
      await _client.botsCommands.startRegistration(
        name: draft.name,
        projectId: draft.projectId,
      );
      if (!mounted) return;
      setState(() {
        _setupOpen = false;
        _selectedBotId = null;
      });
    });
  }

  Future<void> _saveManual(SettingsBotsView view) {
    _syncDraft(view);
    final draft = _client.botsCommands.setupDraft;
    final secret = BotSecretReplace(_secret.text);
    return _run(() async {
      final saved = await _client.botsCommands.saveBot(
        expectedConfigRevision: 0,
        name: draft.name,
        projectId: draft.projectId,
        appId: draft.appId,
        secret: secret,
      );
      _secret.clear();
      if (!mounted) return;
      setState(() => _setupOpen = false);
      final created = saved.bots
          .where((bot) => bot.appId == draft.appId)
          .firstOrNull;
      if (created != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => BotDetailsPage(botId: created.id)),
        );
      }
    });
  }

  Future<void> _runQuery(String botId, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted ||
          _selectedBot(
                _client.bots.state.value ?? const BotsStateSnapshot.empty(),
              )?.id !=
              botId) {
        return;
      }
      setState(
        () => _error = error is StudioFailure
            ? error.message
            : context.l10n.settingsBotsOperationFailed,
      );
    }
  }

  void _readMessages(String botId, String chatId, {String? cursor}) {
    unawaited(
      _runQuery(
        botId,
        () => _client.botsQueries.readMessages(botId, chatId, cursor: cursor),
      ),
    );
  }

  Future<void> _createThread(
    BotSnapshot bot,
    BotConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsBotsNewThread),
        content: Text(context.l10n.settingsBotsNewThreadWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.settingsBotsDismiss),
          ),
          FilledButton(
            key: StudioDriverKeys.botsConfirmNewThread,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.settingsBotsNewThread),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _client.botsCommands.createConversationThread(
        botId: bot.id,
        chatId: conversation.chatId,
        expectedConfigRevision: bot.configRevision,
        expectedBindingRevision: conversation.threadBinding?.revision ?? 0,
      ),
    );
  }

  Widget _buildModel(BotSnapshot bot) {
    final accounts = ref.watch(settingsAgentsViewProvider).accounts;
    final options = buildModelSelectionOptions(accounts, type: ModelType.text);
    final route = bot.modelRoute;
    final selected = options
        .where(
          (option) =>
              option.accountId == route?.accountId &&
              option.modelId == route?.modelId,
        )
        .firstOrNull;
    Future<void> save(BotModelRoute next) => _run(
      () => _client.botsCommands.saveBot(
        botId: bot.id,
        expectedConfigRevision: bot.configRevision,
        name: bot.name,
        projectId: bot.projectId,
        appId: bot.appId,
        secret: const BotSecretPreserve(),
        enabled: bot.enabled,
        toolsEnabled: bot.toolsEnabled,
        modelRoute: next,
      ),
    );
    return SettingsSectionPanel(
      title: context.l10n.botsModelTitle,
      children: [
        AgentRouteView(
          role: 'bot-${bot.id}',
          selectedAccountId: route?.accountId ?? '',
          selectedModel: route?.modelId ?? '',
          selectedEffort: route?.effort,
          options: options,
          efforts: selected?.reasoningEfforts ?? const [],
          unresolvedLabel: selected == null
              ? context.l10n.statusModelRouteUnavailable
              : null,
          pending: _busy,
          onModelChanged: (option) => save(
            BotModelRoute(
              accountId: option.accountId,
              modelId: option.modelId,
              effort: ModelRouteQueries.effortAfterModelSelection(
                option.descriptor,
                route?.effort,
              ),
            ),
          ),
          onEffortChanged: (effort) => save(
            BotModelRoute(
              accountId: route!.accountId,
              modelId: route.modelId,
              effort: effort,
            ),
          ),
        ),
        Text(
          context.l10n.botsModelHint,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _openConversation(
    BotSnapshot bot,
    BotConversation conversation,
  ) async {
    final threadId = conversation.threadBinding?.threadId;
    if (threadId == null) {
      await _openBotLink(
        feishuChatAppLink(
          conversation.chatId,
          browser:
              ref.read(feishuClientAvailableProvider).asData?.value != true,
        ),
      );
      return;
    }
    await _run(() async {
      await _client.directoryCommands.selectThread(threadId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              leading: BackButton(key: StudioDriverKeys.botsChatBack),
              title: Text(
                conversation.name ?? bot.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: context.l10n.settingsBotsOpenChat,
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _openBotLink(
                    feishuChatAppLink(
                      conversation.chatId,
                      browser:
                          ref
                              .read(feishuClientAvailableProvider)
                              .asData
                              ?.value !=
                          true,
                    ),
                  ),
                ),
                IconButton(
                  key: StudioDriverKeys.botsPlatformTools,
                  tooltip: context.l10n.botsPlatformTools,
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => BotDetailsPage(
                          botId: bot.id,
                          chatId: conversation.chatId,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: const AgentWorkspacePane(),
          ),
        ),
      );
    });
  }

  Future<void> _editBot(BotSnapshot bot) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BotEditor(
        bot: bot,
        onSave: (edits) => _client.botsCommands.saveBot(
          botId: bot.id,
          expectedConfigRevision: bot.configRevision,
          name: edits.name,
          projectId: edits.projectId,
          appId: edits.appId,
          secret: edits.secret,
          enabled: bot.enabled,
          toolsEnabled: bot.toolsEnabled,
        ),
      ),
    );
  }

  /// 打开固定官方后台页面。失败只呈现可重试的本地化提示，不把底层
  /// 异常（可能包含 URL 或系统路径）抛进 UI 状态或日志。
  Future<void> _openDeveloperConsole() async {
    final safe = safeExternalWebUrl(_feishuDeveloperConsoleUrl);
    if (safe == null) {
      if (!mounted) return;
      setState(() => _error = context.l10n.settingsBotsOpenConsoleFailed);
      return;
    }
    try {
      await ref.read(externalUrlLauncherProvider)(safe);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.settingsBotsOpenConsoleFailed);
    }
  }

  /// Dispatching an AppLink does not change registration or connection facts.
  Future<void> _openBotLink(String? url) async {
    if (url == null) {
      setState(() => _error = context.l10n.settingsBotsOpenLinkFailed);
      return;
    }
    try {
      await ref.read(externalUrlLauncherProvider)(url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.settingsBotsOpenLinkFailed);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StudioFailure
            ? error.message
            : context.l10n.settingsBotsOperationFailed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BotList extends StatelessWidget {
  const _BotList({
    required this.bots,
    required this.selectedId,
    required this.onSelect,
  });

  final List<BotSnapshot> bots;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        for (final bot in bots)
          ListTile(
            key: StudioDriverKeys.botsRow(bot.id),
            leading: CircleAvatar(
              backgroundColor: context.colors.secondaryContainer,
              child: Icon(
                Icons.smart_toy_outlined,
                color: context.colors.onSecondaryContainer,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            selected: bot.id == selectedId,
            title: Text(bot.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${context.l10n.botsPlatformFeishu} · ${_botConnectionLabel(context, bot.connection)}${bot.lastActivityAt == null ? '' : ' · ${_botActivityLabel(context, bot.lastActivityAt!)}'}',
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelect(bot.id),
          ),
      ],
    );
  }
}

class _PendingCredentialTile extends StatelessWidget {
  const _PendingCredentialTile({required this.pending, required this.onRetry});

  final BotPendingCredentialOperation pending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final kind = switch (pending.credentialOperation) {
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
    return ListTile(
      key: StudioDriverKeys.botsPending(pending.botId),
      title: Text(kind),
      subtitle: Text(pending.diagnostic?.message ?? pending.botId),
      trailing: TextButton(
        onPressed: onRetry,
        child: Text(context.l10n.settingsBotsVerify),
      ),
    );
  }
}

/// A route preserves the overview's scroll/filter state and gives details the entire window.
class BotDetailsPage extends StatelessWidget {
  const BotDetailsPage({super.key, required this.botId, this.chatId});
  final String botId;
  final String? chatId;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: BotsTab(tabIndex: -1, botId: botId, chatId: chatId),
    ),
  );
}

String _botConnectionLabel(
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

String _botActivityLabel(BuildContext context, int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  final labels = MaterialLocalizations.of(context);
  return DateUtils.isSameDay(date, DateTime.now())
      ? labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))
      : labels.formatShortDate(date);
}
