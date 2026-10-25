import 'dart:async';

import 'package:anywork_client/bots.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_bindings.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/feishu_app_links.dart';
import '../../../../ui/overlays/confirmation_view.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_status_row.dart';
import '../state/bot_setup_state.dart';
import '../state/bots_settings_view_state.dart';
import '../view_models/bots_settings_view_model.dart';
import '../views/bots_conversations_view.dart';
import '../views/bots_settings_view.dart';
import '../widgets/bots_access_section.dart';
import 'bot_console_link.dart';
import 'bot_model_connector.dart';
import 'bot_pages.dart';
import 'bot_setup_connector.dart';
import 'bots_registration_connector.dart';

/// Smart entry of one Bots route.
///
/// Without [botId] it is the overview panel inside settings. With [botId] it is
/// the detail route, and with [chatId] as well the platform tools route: the
/// overview and the settings navigation stay behind, and the previous route
/// keeps its scroll position and filter.
class BotsSettingsConnector extends ConsumerStatefulWidget {
  const BotsSettingsConnector({this.botId, this.chatId, super.key});

  final String? botId;
  final String? chatId;

  @override
  ConsumerState<BotsSettingsConnector> createState() =>
      _BotsSettingsConnectorState();
}

class _BotsSettingsConnectorState extends ConsumerState<BotsSettingsConnector> {
  int _editorId = 0;

  /// The overview keeps one create session open at a time; "添加机器人" opens the
  /// in-page setup section and "关闭配置" collapses it again.
  int? _setupEditorId;

  /// Page-owned transient failure, for example a rejected AppLink. Business
  /// failures keep their typed per-target presentation.
  String? _error;

  /// The platform tools route applies its bot/chat to the page selection once,
  /// so the message history and manual send read that exact target.
  bool _routeApplied = false;

  /// Borrowed conversation read of the selected bot. It is page-local: closing
  /// the route releases it and never closes the Repository.
  BotConversationReadScope? _conversations;
  String? _conversationBotId;
  Observation? _conversationObservation;
  BotConversationsState? _conversationsState;
  String? _conversationError;
  int _conversationGeneration = 0;

  @override
  void initState() {
    super.initState();
    final botId = widget.botId;
    if (botId != null && widget.chatId == null) _openConversations(botId);
  }

  @override
  void didUpdateWidget(covariant BotsSettingsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.botId == widget.botId && oldWidget.chatId == widget.chatId) {
      return;
    }
    _routeApplied = false;
    final botId = widget.botId;
    if (botId == null || widget.chatId != null) {
      _closeConversations();
    } else {
      _openConversations(botId);
    }
  }

  @override
  void dispose() {
    _closeConversations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(botsSettingsViewModelProvider)
      .when(
        loading: () => SettingsHeaderPane(
          header: SettingsHeader(
            title: context.l10n.settingsBotsTitle,
            subtitle: context.l10n.botsOverviewHint,
          ),
          children: const [
            SizedBox(height: 24),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, stack) {
          if (error is! StudioFailure) {
            Error.throwWithStackTrace(error, stack);
          }
          return SettingsHeaderPane(
            header: SettingsHeader(
              title: context.l10n.settingsBotsTitle,
              subtitle: context.l10n.botsOverviewHint,
            ),
            children: [
              SelectableText(settingsFailureText(error)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(botsSettingsViewModelProvider),
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
              ),
            ],
          );
        },
        data: (state) => _page(context, state),
      );

  Widget _page(BuildContext context, BotsSettingsViewState state) {
    final vm = ref.read(botsSettingsViewModelProvider.notifier);
    final bot = _bot(state);
    final platformOnly = bot != null && widget.chatId != null;
    final busy = bot == null
        ? false
        : state.botActions[bot.id]?.preventsResubmission ?? false;
    final available = state.editable && !busy;
    if (bot != null) _applyRoute(vm, bot);
    final conversationPage = _conversationsState?.page;
    return BotsSettingsView(
      state: state,
      bot: bot,
      platformOnly: platformOnly,
      setupOpen: _setupEditorId != null,
      canOpenFeishu:
          ref.watch(feishuClientAvailableProvider).asData?.value == true,
      status: _status(state, vm),
      error: _error,
      registration: _registration(state),
      setup: _setup(state, vm),
      model: bot == null
          ? const SizedBox.shrink()
          : BotModelConnector(bot: bot),
      conversations: bot == null || platformOnly
          ? const SizedBox.shrink()
          : BotsConversationsView(
              page: conversationPage,
              loading: _conversationsState?.loading == true,
              error:
                  _conversationError ??
                  (_conversationsState?.error == null
                      ? null
                      : settingsFailureText(_conversationsState!.error!)),
              busy: busy,
              trustedChatIds: bot.trustedChatIds,
              selectedChatId: null,
              onRefresh: () => unawaited(_loadConversations()),
              onNext: () => unawaited(
                _loadConversations(cursor: conversationPage?.nextCursor),
              ),
              onOpenConversation: (conversation) =>
                  unawaited(_openConversation(bot, conversation)),
              onOpenPlatformTools: (chatId) =>
                  unawaited(openBotPlatformTools(context, bot.id, chatId)),
              onTrustChat: (chatId, trusted) =>
                  unawaited(vm.setTrustedChat(bot.id, chatId, trusted)),
              onCreateThread: (conversation) =>
                  unawaited(_createThread(context, vm, bot, conversation)),
            ),
      conversationsEmpty:
          conversationPage != null &&
          conversationPage.conversations.isEmpty &&
          conversationPage.nextCursor == null,
      detailErrors: _errors(state.botActions[bot?.id]),
      messageErrors: [
        if (state.messageIssue case final error?) settingsFailureText(error),
        if (state.messagesMatch && state.messages.error != state.messageIssue)
          if (state.messages.error case final error?)
            settingsFailureText(error),
        if (state.draftIssue case final error?) settingsFailureText(error),
        ..._errors(state.submission?.action),
      ],
      accessSection: bot == null || platformOnly
          ? const SizedBox.shrink()
          : BotsAccessSection(
              bot: bot,
              editable: available,
              onTrustUser: (openId, trusted) =>
                  unawaited(vm.setTrustedUser(bot.id, openId, trusted)),
              onClearPairing: (openId) =>
                  unawaited(vm.clearPairingRequest(bot.id, openId)),
              onTrustChat: (chatId, trusted) =>
                  unawaited(vm.setTrustedChat(bot.id, chatId, trusted)),
            ),
      onBack: () {
        if (ModalRoute.of(context)?.isCurrent != true) return;
        Navigator.of(context).pop();
      },
      onAddBot: _openSetup,
      onEditBot: () => unawaited(_openEditor(bot!.id)),
      onOpenBot: () => unawaited(_openBot(bot!, browser: false)),
      onOpenBotBrowser: () => unawaited(_openBot(bot!, browser: true)),
      onEnabled: (enabled) => unawaited(vm.setEnabled(bot!.id, enabled)),
      onRetryConnection: () => unawaited(vm.retryConnection(bot!.id)),
      onTools: (enabled) => unawaited(vm.setToolsEnabled(bot!.id, enabled)),
      onOpenConsole: () => unawaited(openBotDeveloperConsole(context, ref)),
      onRetryPending: (id) => unawaited(vm.retryConnection(id)),
      onTrustUser: (openId, trusted) =>
          unawaited(vm.setTrustedUser(bot!.id, openId, trusted)),
      onClearPairing: (openId) =>
          unawaited(vm.clearPairingRequest(bot!.id, openId)),
      onTrustChat: (chatId, trusted) =>
          unawaited(vm.setTrustedChat(bot!.id, chatId, trusted)),
      onSelectBot: (id) => unawaited(openBotDetails(context, id)),
      onMessagesRefresh: () => unawaited(vm.readMessages()),
      onMessagesNext: () => unawaited(vm.readMessages(nextPage: true)),
      onMessageDraft: vm.editMessage,
      onSend: () => unawaited(vm.sendMessage()),
      onRetrySend: () => unawaited(_retrySend(context, vm, state.sendRetry)),
    );
  }

  BotSnapshot? _bot(BotsSettingsViewState state) {
    final id = widget.botId;
    if (id == null) return null;
    return state.bots?.where((bot) => bot.id == id).firstOrNull;
  }

  /// The platform tools route reads the selected conversation: it selects the
  /// route's bot and chat, then loads that exact history once.
  void _applyRoute(BotsSettingsViewModel vm, BotSnapshot bot) {
    final chatId = widget.chatId;
    if (chatId == null || _routeApplied) return;
    _routeApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      vm.selectBot(bot.id);
      vm.setChatId(chatId);
      unawaited(vm.readMessages());
    });
  }

  Widget? _status(BotsSettingsViewState state, BotsSettingsViewModel vm) {
    final failure =
        state.syncIssue ??
        state.statusIssue ??
        state.observationIssue ??
        state.source.projection.sync.error;
    if (failure != null) {
      return SettingsStatusRow(
        failed: true,
        message: settingsFailureText(failure),
        onRetry: () => unawaited(vm.retrySource()),
      );
    }
    if (state.snapshotCurrent) return null;
    final brief = state.source.projection.header?.source.brief;
    return SettingsStatusRow(
      failed: false,
      message: switch (brief) {
        null => context.l10n.resourceSourceUninitialized,
        UninitializedObservedBrief() =>
          context.l10n.resourceSourceUninitialized,
        LoadingObservedBrief() => context.l10n.resourceSourceLoading,
        RefreshingObservedBrief() => context.l10n.resourceSourceRefreshing,
        StaleObservedBrief() => context.l10n.resourceSourceStale,
        DegradedObservedBrief() => context.l10n.resourceSourceDegraded,
        FailedObservedBrief() => context.l10n.toolStatusFailed,
        StoppedObservedBrief() => context.l10n.workflowStateStopped,
        ReadyObservedBrief() => context.l10n.resourceSourceLastKnown,
      },
    );
  }

  /// A canonical registration attempt stays at the top of the overview, even
  /// while the create section is closed.
  Widget? _registration(BotsSettingsViewState state) {
    if (widget.botId != null) return null;
    final attempt = state.registration;
    if (attempt == null && !state.registrationPending) return null;
    if (_setupEditorId != null && !state.registrationActive) return null;
    return SettingsSectionPanel(
      title: attempt?.name ?? context.l10n.settingsBotsSetupTitle,
      children: const [BotsRegistrationConnector()],
    );
  }

  Widget? _setup(BotsSettingsViewState state, BotsSettingsViewModel vm) {
    final editorId = _setupEditorId;
    if (editorId == null || state.registrationActive) return null;
    return BotSetupConnector(
      target: BotSetupKey(editorId: editorId),
      onClose: (saved) {
        if (!mounted || _setupEditorId != editorId) return;
        setState(() => _setupEditorId = null);
      },
      onStartRegistration: (name) =>
          unawaited(vm.startRegistration(name: name)),
    );
  }

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  ];

  void _openSetup() => setState(() => _setupEditorId = ++_editorId);

  /// Opens one edit session. The dialog owns nothing durable: an admitted save
  /// survives closing it, and reopening reads canonical again.
  Future<void> _openEditor(String botId) async {
    final target = BotSetupKey(editorId: ++_editorId, botId: botId);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final route = ModalRoute.of(dialogContext);
        return BotSetupConnector(
          target: target,
          onClose: (saved) {
            if (route?.isActive ?? false) Navigator.of(dialogContext).pop();
          },
          onStartRegistration: (name) => unawaited(
            ref
                .read(botsSettingsViewModelProvider.notifier)
                .startRegistration(name: name),
          ),
        );
      },
    );
  }

  Future<void> _openBot(BotSnapshot bot, {required bool browser}) =>
      _openLink(feishuBotAppLink(bot.appId, browser: browser));

  /// Dispatching an AppLink does not change registration or connection facts.
  Future<void> _openLink(String? url) async {
    final opened = await openBotAppLink(ref, url);
    if (!mounted || opened) return;
    setState(() => _error = context.l10n.settingsBotsOpenLinkFailed);
  }

  /// A bound conversation opens the local chat; an unbound one can only be
  /// opened in the platform client.
  Future<void> _openConversation(
    BotSnapshot bot,
    BotConversation conversation,
  ) async {
    final threadId = conversation.threadBinding?.threadId;
    if (threadId == null) {
      await _openLink(
        feishuChatAppLink(
          conversation.chatId,
          browser:
              ref.read(feishuClientAvailableProvider).asData?.value != true,
        ),
      );
      return;
    }
    StudioFailure? failure;
    try {
      final result = await ref
          .read(workspaceRepositoryProvider)
          .selectThread(threadId)
          .result;
      failure = switch (result) {
        RejectedCommandResult(:final error) => error,
        UnknownOutcomeCommandResult(:final error) => error,
        SyncFailedCommandResult(:final error) => error,
        AcknowledgedSyncFailedCommandResult(:final error) => error,
        _ => null,
      };
    } on StudioFailure catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = settingsFailureText(failure!));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BotChatPage(
          botId: bot.id,
          chatId: conversation.chatId,
          threadId: threadId,
          title: conversation.name ?? bot.name,
        ),
      ),
    );
  }

  /// Creating the local session context is an explicit, confirmed action: old
  /// history stays, and accepted inputs are never moved into the new context.
  Future<void> _createThread(
    BuildContext context,
    BotsSettingsViewModel vm,
    BotSnapshot bot,
    BotConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationView(
        title: context.l10n.settingsBotsNewThread,
        body: context.l10n.settingsBotsNewThreadWarning,
        confirmLabel: context.l10n.settingsBotsNewThread,
        cancelLabel: context.l10n.settingsBotsDismiss,
        confirmKey: StudioDriverKeys.botsConfirmNewThread,
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.createConversationThread(
      bot.id,
      chatId: conversation.chatId,
      expectedBindingRevision: conversation.threadBinding?.revision ?? 0,
    );
    if (mounted) unawaited(_loadConversations());
  }

  /// Retrying an unknown or partial send is an explicit, confirmed decision:
  /// the original operation identity is reused, never a silent replay.
  Future<void> _retrySend(
    BuildContext context,
    BotsSettingsViewModel vm,
    BotsSendRetry? retry,
  ) async {
    if (retry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationView(
        title: context.l10n.settingsBotsSendUnknown,
        body: '${context.l10n.settingsBotsNoReplay}\n\n${retry.text}',
        confirmLabel: context.l10n.runtimeFatalRetry,
        cancelLabel: context.l10n.settingsCancel,
        confirmKey: const ValueKey<String>('bots-send-retry-confirm'),
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );
    if (confirmed == true && context.mounted) await vm.retrySend(retry);
  }

  void _openConversations(String botId) {
    if (_conversationBotId == botId && _conversations != null) return;
    _closeConversations();
    _conversationBotId = botId;
    final BotConversationReadScope scope;
    try {
      scope = ref.read(botsRepositoryProvider).conversations(botId);
    } on StudioFailure catch (error) {
      _conversationError = settingsFailureText(error);
      return;
    }
    _conversations = scope;
    _conversationsState = scope.state.value;
    _conversationObservation = scope.state.watchLatest((value) {
      if (!mounted || !identical(_conversations, scope)) return;
      setState(() => _conversationsState = value);
    }).observation;
    unawaited(_loadConversations());
  }

  /// One bounded page per demand; the native cursor is passed back unchanged.
  Future<void> _loadConversations({String? cursor}) async {
    final scope = _conversations;
    if (scope == null) return;
    final generation = ++_conversationGeneration;
    StudioFailure? failure;
    try {
      await scope.page(cursor: cursor);
    } on StudioFailure catch (error) {
      failure = error;
    }
    if (!mounted ||
        generation != _conversationGeneration ||
        !identical(_conversations, scope)) {
      return;
    }
    final message = failure == null ? null : settingsFailureText(failure);
    setState(() => _conversationError = message);
  }

  void _closeConversations() {
    _conversationGeneration++;
    _conversationObservation?.cancel();
    _conversationObservation = null;
    final scope = _conversations;
    _conversations = null;
    _conversationBotId = null;
    _conversationsState = null;
    _conversationError = null;
    if (scope == null) return;
    scope.requestClose();
    unawaited(
      scope.close().then<void>((_) {}, onError: _conversationCloseError),
    );
  }

  void _conversationCloseError(Object error, StackTrace stack) =>
      Zone.current.handleUncaughtError(error, stack);
}
