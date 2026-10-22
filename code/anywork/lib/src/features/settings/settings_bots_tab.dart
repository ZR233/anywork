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
  const BotsTab({super.key, required this.tabIndex});

  final int tabIndex;

  @override
  ConsumerState<BotsTab> createState() => _BotsTabState();
}

class _BotsTabState extends ConsumerState<BotsTab> {
  String? _selectedBotId;
  bool _setupOpen = false;
  bool _manualSetup = false;
  bool _busy = false;
  String? _error;
  late final TextEditingController _name;
  late final TextEditingController _appId;
  late final TextEditingController _secret;
  late final TextEditingController _sendText;
  final _startTime = TextEditingController();
  final _endTime = TextEditingController();
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
    final queries = _client.botsQueries.state;
    _selectedBotId =
        queries.selectedMessageBotId ?? queries.selectedConversationBotId;
    _selectedChatId = queries.selectedChatId;
    _sendText = TextEditingController(
      text: _client.botsCommands.messageDraft(
        _selectedBotId ?? '',
        _selectedChatId ?? '',
      ),
    );
    _startTime.text = queries.selectedStartTime?.toString() ?? '';
    _endTime.text = queries.selectedEndTime?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _appId.dispose();
    _secret.dispose();
    _sendText.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _client.botsCommands.clearSecret();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
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
      header: SettingsHeader(
        title: context.l10n.settingsBotsTitle,
        subtitle: context.l10n.settingsBotsSubtitle,
        trailing: FilledButton.tonalIcon(
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
        _FactsStrip(snapshot: snapshot),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: error),
        ],
        const SizedBox(height: 16),
        if (registration != null && (registering || !_setupOpen))
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
        if (_setupOpen && !registering) _buildSetup(context, view),
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
        else if (snapshot.bots.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final list = _BotList(
                bots: snapshot.bots,
                selectedId: selected?.id,
                onSelect: (id) => setState(() {
                  if (selected?.id == id) return;
                  _selectedBotId = id;
                  _setupOpen = false;
                  _selectedChatId = null;
                  _sendText.clear();
                  _client.botsQueries.forgetConversations();
                  _client.botsQueries.forgetMessages();
                }),
              );
              final detail = selected == null
                  ? SettingsEmptyMessage(
                      icon: Icons.tune_outlined,
                      title: context.l10n.settingsBotsSelectTitle,
                      body: context.l10n.settingsBotsSelectBody,
                    )
                  : _BotDetail(
                      bot: selected,
                      view: view,
                      canOpenFeishu: canOpenFeishu,
                      selectedChatId: _selectedChatId,
                      sendController: _sendText,
                      busy: _busy,
                      startTime: _startTime,
                      endTime: _endTime,
                      onEdit: () => _editBot(selected, view),
                      onDraftChanged: (value) {
                        try {
                          _client.botsCommands.updateMessageDraft(
                            selected.id,
                            _selectedChatId!,
                            value,
                          );
                        } catch (_) {
                          setState(
                            () => _error =
                                context.l10n.settingsBotsOperationFailed,
                          );
                        }
                      },
                      onSelectChat: (id) {
                        setState(() {
                          _selectedChatId = id;
                          _sendText.text = _client.botsCommands.messageDraft(
                            selected.id,
                            id,
                          );
                        });
                        _readMessages(selected.id, id);
                      },
                      onEnabled: (enabled) => _run(
                        () => _client.botsCommands.setEnabled(
                          botId: selected.id,
                          expectedConfigRevision: selected.configRevision,
                          enabled: enabled,
                        ),
                      ),
                      onRetry: () => _run(
                        () => _client.botsCommands.retryConnection(
                          botId: selected.id,
                        ),
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
                      onLoadMessages: (cursor) => _readMessages(
                        selected.id,
                        _selectedChatId!,
                        cursor: cursor,
                      ),
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
                      onOpenBot: () =>
                          _openBotLink(feishuBotAppLink(selected.appId)),
                      onOpenBotBrowser: () => _openBotLink(
                        feishuBotAppLink(selected.appId, browser: true),
                      ),
                    );
              if (stacked) {
                return Column(
                  children: [list, const SizedBox(height: 16), detail],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 280, child: list),
                  const SizedBox(width: 16),
                  Expanded(child: detail),
                ],
              );
            },
          ),
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
        DropdownButtonFormField<String>(
          key: StudioDriverKeys.botsProject,
          initialValue: _selectedProjectId(view),
          items: [
            for (final project in view.projects)
              DropdownMenuItem(
                value: project.id,
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  _syncDraft(view, projectId: value);
                  setState(() {});
                },
          decoration: InputDecoration(
            labelText: context.l10n.settingsBotsProject,
          ),
        ),
        const SizedBox(height: 12),
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
    final id = _selectedBotId ?? snapshot.registration?.completedBotId;
    for (final bot in snapshot.bots) {
      if (bot.id == id) return bot;
    }
    return snapshot.bots.first;
  }

  String? _selectedProjectId(SettingsBotsView view) {
    final current = _client.botsCommands.setupDraft.projectId;
    if (view.projects.any((project) => project.id == current)) return current;
    return view.projects.firstOrNull?.id;
  }

  void _syncDraft(SettingsBotsView view, {String? projectId}) {
    _client.botsCommands.updateSetupDraft(
      _client.botsCommands.setupDraft.copyWith(
        name: _name.text,
        projectId: projectId ?? _selectedProjectId(view) ?? '',
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
    _secret.clear();
    return _run(
      () => _client.botsCommands.saveBot(
        expectedConfigRevision: 0,
        name: draft.name,
        projectId: draft.projectId,
        appId: draft.appId,
        secret: secret,
      ),
    );
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
      _runQuery(botId, () {
        int? seconds(String value) {
          if (value.isEmpty) return null;
          final parsed = int.tryParse(value);
          if (parsed == null) throw StateError('Invalid Unix seconds');
          return parsed;
        }

        final query = _client.botsQueries.state;
        return _client.botsQueries.readMessages(
          botId,
          chatId,
          startTime: cursor == null
              ? seconds(_startTime.text)
              : query.selectedStartTime,
          endTime: cursor == null
              ? seconds(_endTime.text)
              : query.selectedEndTime,
          cursor: cursor,
        );
      }),
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

  Future<void> _editBot(BotSnapshot bot, SettingsBotsView view) async {
    final edits = await showDialog<_BotEdits>(
      context: context,
      builder: (_) => _BotEditor(bot: bot, projects: view.projects),
    );
    if (edits == null || !mounted) return;
    await _run(
      () => _client.botsCommands.saveBot(
        botId: bot.id,
        expectedConfigRevision: bot.configRevision,
        name: edits.name,
        projectId: edits.projectId,
        appId: edits.appId,
        secret: edits.secret,
        enabled: bot.enabled,
        toolsEnabled: bot.toolsEnabled,
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

class _FactsStrip extends StatelessWidget {
  const _FactsStrip({required this.snapshot});

  final BotsStateSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FactChip(
          key: StudioDriverKeys.botsFactConfig,
          label: context.l10n.settingsBotsFactConfig,
          value: snapshot.bots.isEmpty
              ? context.l10n.settingsBotsFactMissing
              : '${snapshot.bots.length}',
        ),
        _FactChip(
          key: StudioDriverKeys.botsFactConnection,
          label: context.l10n.settingsBotsFactConnection,
          value: _connectionSummary(context, snapshot),
        ),
        _FactChip(
          key: StudioDriverKeys.botsFactAuth,
          label: context.l10n.settingsBotsFactAuth,
          value: _authSummary(context, snapshot),
        ),
      ],
    );
  }

  String _connectionSummary(BuildContext context, BotsStateSnapshot snapshot) {
    if (snapshot.bots.any((bot) => bot.connection is BotConnectionConnected)) {
      return context.l10n.settingsBotsConnectionConnected;
    }
    if (snapshot.bots.any((bot) => bot.connection is BotConnectionConnecting)) {
      return context.l10n.settingsBotsConnectionConnecting;
    }
    if (snapshot.bots.any((bot) => bot.connection is BotConnectionFailed)) {
      return context.l10n.settingsBotsConnectionFailed;
    }
    return context.l10n.settingsBotsConnectionIdle;
  }

  String _authSummary(BuildContext context, BotsStateSnapshot snapshot) {
    if (snapshot.bots.any(
      (bot) => bot.trustedOpenIds.isNotEmpty || bot.trustedChatIds.isNotEmpty,
    )) {
      return context.l10n.settingsBotsAuthGranted;
    }
    if (snapshot.bots.any((bot) => bot.pairing.isNotEmpty)) {
      return context.l10n.settingsBotsAuthPending;
    }
    return context.l10n.settingsBotsAuthNone;
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: context.text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
            selected: bot.id == selectedId,
            title: Text(bot.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${bot.appId} · ${_credentialLabel(context, bot.credential)}',
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelect(bot.id),
          ),
      ],
    );
  }

  String _credentialLabel(
    BuildContext context,
    BotCredentialAvailability availability,
  ) {
    return switch (availability) {
      BotCredentialAvailability.stored =>
        context.l10n.settingsBotsCredentialStored,
      BotCredentialAvailability.sessionOnly =>
        context.l10n.settingsBotsCredentialSession,
      BotCredentialAvailability.missing =>
        context.l10n.settingsBotsCredentialMissing,
      BotCredentialAvailability.unavailable =>
        context.l10n.settingsBotsCredentialUnavailable,
    };
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
