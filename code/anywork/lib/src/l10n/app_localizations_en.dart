// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountsModelModalityCapabilities =>
      'Input/output modalities and capabilities';

  @override
  String get accountsModelContextThreshold =>
      'Context and compaction threshold';

  @override
  String get accountsModelProtocolOrigin => 'Protocol and model origin';

  @override
  String get accountsSupportedConnections => 'Supported connections';

  @override
  String accountsVisibleCount(int count) {
    return 'Showing $count accounts';
  }

  @override
  String get accountsTemplateProtocol => 'Protocol';

  @override
  String get accountsTemplateDefaultEndpoint => 'Default endpoint';

  @override
  String get accountsTemplateDefaultBilling => 'Template default billing';

  @override
  String get accountsTemplateCapabilities => 'Catalog and usage capabilities';

  @override
  String get accountsTemplateDiscoverySupported =>
      'Online model catalog sync supported';

  @override
  String get accountsTemplateDiscoveryUnsupported =>
      'Online model catalog sync not supported';

  @override
  String get accountsTemplateUsageSupported => 'Usage queries supported';

  @override
  String get accountsTemplateUsageUnsupported => 'Usage queries not supported';

  @override
  String get accountsTemplateUsageUnknown =>
      'Usage query capability not provided';

  @override
  String get accountsSetDefaultOnCreate => 'Set as default after creation';

  @override
  String get accountsSetDefaultOnCreateHint =>
      'Update the default model for new chats in Simple mode. Other modes and existing chats are unchanged.';

  @override
  String get accountsCreatedDefaultIncomplete =>
      'Account created; setting the default did not complete';

  @override
  String get accountsUnconfirmedSaveDiscardWarning =>
      'Save outcome is not confirmed. Discarding only clears local edits; it does not cancel the submitted save, and the saved state may still change.';

  @override
  String get accountsConnectionBillingTitle =>
      'Connection, credentials & billing';

  @override
  String get accountsTemplatesHint =>
      'Search for a template, then review its connection settings. Changing templates is handled before replacing your edits.';

  @override
  String get accountsListHint =>
      'Manage model services and integrations, and review current balances and quotas.';

  @override
  String get accountsTemplateNativeGroup => 'Model APIs';

  @override
  String get accountsTemplateAcpGroup => 'Managed integrations';

  @override
  String accountsBackToAccount(String accountName) {
    return 'Back to $accountName';
  }

  @override
  String get accountsStateStale =>
      'The connection changed. Showing previous data until the current account is observed. Your input is kept.';

  @override
  String get accountsSavePending =>
      'The change was accepted. Waiting for this account to be observed and saved.';

  @override
  String get accountsUnknownSaveOutcome =>
      'The save result is unknown. Your input is kept; do not submit a replacement request blindly.';

  @override
  String get accountsRequiredField => 'Enter a non-empty value.';

  @override
  String get accountsDuplicateModel =>
      'Each manual model must have a unique ID.';

  @override
  String get accountsOutputBudget =>
      'The output budget must not exceed the context window.';

  @override
  String get accountsOutputModalities => 'Output modalities';

  @override
  String get accountsSavedConnectionFailed =>
      'The account was saved, but the connection request failed.';

  @override
  String get accountsTargetMissing => 'This account no longer exists.';

  @override
  String get accountsStatusColumn => 'Billing & status';

  @override
  String get accountsBalanceColumn => 'Balance & quota';

  @override
  String get accountsSettingsSection => 'Account settings';

  @override
  String get accountsAdvancedSection => 'Advanced information';

  @override
  String get accountsSyncModels => 'Sync models';

  @override
  String get accountsSyncUnsupported =>
      'This account does not support model discovery.';

  @override
  String get accountsSyncingModels => 'Syncing models…';

  @override
  String get accountsQueryIdle => 'Usage has not been checked yet.';

  @override
  String get accountsQueryUnsupported =>
      'Usage queries are not supported by this account.';

  @override
  String get accountsQueryFailed => 'Could not refresh usage.';

  @override
  String get accountsUsageLastGood => 'Showing the last successful data.';

  @override
  String get accountsLoading => 'Loading accounts…';

  @override
  String get accountsRetry => 'Retry';

  @override
  String get accountsAutomatic => 'Automatic';

  @override
  String get accountsOverride => 'Override';

  @override
  String get accountsBillingDisclaimer =>
      'Billing settings only control this app’s cost estimates. No charge does not mean the provider is free. A subscription does not guarantee quota or exclude additional charges.';

  @override
  String get accountsSource => 'Source';

  @override
  String get accountsVerifySignIn => 'Verify sign-in';

  @override
  String get accountsLowQuota => 'Low remaining quota';

  @override
  String get accountsRemaining => 'Remaining';

  @override
  String get accountsPriceTiers => 'Tiered prices';

  @override
  String get accountsPerformance => 'Performance samples';

  @override
  String get accountsEvaluations => 'Recent evaluations (up to 10)';

  @override
  String get accountsReadout => 'Load performance & evaluations';

  @override
  String get accountsModelDetails => 'Details & evaluations';

  @override
  String get accountsSpecsTab => 'Specifications & performance';

  @override
  String get accountsPriceMissing =>
      'No verified tiered prices for this model.';

  @override
  String get accountsPerformanceMissing => 'No local performance samples yet.';

  @override
  String get accountsEvaluationWindow =>
      'Summary of the latest 10 evaluations only; unrated outcomes are excluded from score averages.';

  @override
  String get accountsFilterAll => 'All outcomes';

  @override
  String get accountsFilterCategory => 'All categories';

  @override
  String get accountsFilterScore => 'Any quality score';

  @override
  String get accountsFilterEmpty => 'No evaluations match these filters.';

  @override
  String get accountsSortNewest => 'Newest first';

  @override
  String get accountsSortHighest => 'Highest quality first';

  @override
  String get accountsSortLowest => 'Lowest quality first';

  @override
  String get accountsCompactAdjusted =>
      'The model applies a safety limit. Your requested value is preserved; the effective value below is authoritative.';

  @override
  String get accountsConnection => 'Connection';

  @override
  String get accountsHttp => 'HTTP';

  @override
  String get accountsWebSocket => 'WebSocket';

  @override
  String get accountsUnsavedTitle => 'Save account changes?';

  @override
  String get accountsUnsavedBody =>
      'Save before leaving, discard your changes, or keep editing. If saving fails, your input stays here.';

  @override
  String get accountsDiscard => 'Discard changes';

  @override
  String get accountsKeepEditing => 'Keep editing';

  @override
  String get accountsDirty => 'Unsaved changes';

  @override
  String get accountsTemplatePickerHint =>
      'Choose a model API account or an official ACP integration.';

  @override
  String get accountsDeleteTitle => 'Delete this account?';

  @override
  String get accountsDeleteBody =>
      'Only remove the selected account after checking references. History and bills are kept. Removing an ACP integration does not sign out the official program.';

  @override
  String get accountsBack => 'Back to accounts';

  @override
  String get accountsClearSearch => 'Clear search';

  @override
  String get accountsShowCredential => 'Show credential';

  @override
  String get accountsHideCredential => 'Hide credential';

  @override
  String get promptAccepted => 'Accepted';

  @override
  String get composerSendAndContinue => 'Send and continue';

  @override
  String get appTitle => 'anywork';

  @override
  String get trayShowWindow => 'Show main window';

  @override
  String get trayExit => 'Exit';

  @override
  String get sidebarProjects => 'Projects';

  @override
  String get sidebarSessions => 'Sessions';

  @override
  String get sidebarLoadingMore => 'Loading more sessions…';

  @override
  String get sidebarLoadError => 'Failed to load more sessions';

  @override
  String get shutdownTitle => 'Shutting down safely';

  @override
  String shutdownUpdateTitle(String version) {
    return 'Installing update $version';
  }

  @override
  String get shutdownUpdateSaving => 'Stopping chats and saving data…';

  @override
  String get shutdownUpdateRestartHint =>
      'Installation progress will appear after saving. The app will reopen automatically.';

  @override
  String get shutdownUpdateExitHint =>
      'Installation progress will appear after saving. The app will stay closed.';

  @override
  String get shutdownFinalizing => 'Finishing up';

  @override
  String get shutdownFinalizingHint =>
      'Necessary diagnostics were recorded; the app will exit automatically.';

  @override
  String get shutdownPhaseStoppingSubscriptions => 'Stopping subscriptions';

  @override
  String get shutdownPhaseCancellingTurns => 'Stopping active turns';

  @override
  String get shutdownPhaseFlushingPersistence => 'Saving sessions';

  @override
  String get shutdownPhaseStoppingAgents => 'Stopping collaborative agents';

  @override
  String get shutdownPhaseStoppingMcp => 'Stopping MCP servers';

  @override
  String get shutdownPhaseStoppingLsp => 'Stopping language servers';

  @override
  String get shutdownPhaseStopped => 'Shutdown complete';

  @override
  String shutdownPendingCommits(int count) {
    return '$count commits pending';
  }

  @override
  String get sidebarCloseProject => 'Close project';

  @override
  String get sidebarArchiveSession => 'Archive session';

  @override
  String get sidebarArchiveSessionFailed => 'Could not archive this session.';

  @override
  String get sidebarArchiveSessionBusy =>
      'Could not archive this session. It may still be running.';

  @override
  String sidebarArchiveSessionFailedReason(
    String reason,
    String correlationId,
  ) {
    return 'Could not archive this session: $reason (diagnostic ID: $correlationId)';
  }

  @override
  String get sidebarArchiveSessionConfirmTitle => 'Archive session';

  @override
  String get sidebarArchiveSessionConfirmBody =>
      'Archiving stops active work in this session and its child sessions, then moves them to the archived list. Session history, workspaces, branches, and uncommitted content are kept. Continue?';

  @override
  String get sidebarArchiveSessionConfirmAction => 'Archive';

  @override
  String get sidebarRenameSession => 'Rename session';

  @override
  String get sidebarRenameSessionTitle => 'Rename session';

  @override
  String get sidebarRenameSessionInput => 'Session title';

  @override
  String get sidebarRenameSessionEmpty => 'Enter a session title.';

  @override
  String get sidebarRenameSessionTooLong =>
      'Session titles can be at most 80 characters.';

  @override
  String get sidebarRenameSessionFailed => 'Could not rename this session.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get sidebarNewSession => 'New session';

  @override
  String get sidebarSessionWorktree => 'Session worktree';

  @override
  String get sidebarOpenProject => 'Open project';

  @override
  String get sidebarSettings => 'Settings';

  @override
  String get runtimeFatalTitle => 'anywork could not start';

  @override
  String get runtimeFatalRetry => 'Retry';

  @override
  String persistenceDegraded(int count) {
    return 'Saving is temporarily unavailable. $count in-memory update(s) are waiting; you can continue the conversation.';
  }

  @override
  String persistenceRecovering(int count) {
    return 'Saving has recovered and is flushing $count pending update(s). You can continue the conversation.';
  }

  @override
  String persistenceBlocked(int count) {
    return 'Saving is blocked with $count pending update(s) and needs attention.';
  }

  @override
  String get persistenceExecutionPaused =>
      'Saving failed; execution is paused.';

  @override
  String get persistenceSavingBackpressure =>
      'Storage is under pressure; saving is waiting.';

  @override
  String get persistenceNewWorkPaused =>
      'Saving failed; new work is paused while in-flight work winds down.';

  @override
  String persistenceResumeReadyOtherSession(String session) {
    return 'Another session “$session” is saved and waiting to resume.';
  }

  @override
  String persistenceExecutionPausedOtherSession(String session) {
    return 'Another session “$session” failed to save; its execution is paused.';
  }

  @override
  String persistenceNewWorkPausedOtherSession(String session) {
    return 'Another session “$session” failed to save; its new work is paused while in-flight work winds down.';
  }

  @override
  String get persistenceRetry => 'Retry saving';

  @override
  String get threadUnopenedTitle => 'Session not opened yet';

  @override
  String get threadUnopenedBody =>
      'This session is only selected. Open it to load its current state and history; nothing resumes until you send a message.';

  @override
  String get threadOpenAction => 'Open session';

  @override
  String get timelineItemBodyLoad => 'Load full content';

  @override
  String get timelineItemBodyLoading => 'Loading full content…';

  @override
  String get timelineItemBodyPending =>
      'Full content is not durable yet; retry shortly.';

  @override
  String get timelineItemBodyRetry => 'Retry';

  @override
  String get timelineItemBodyUnavailable =>
      'Full content is unavailable from this data source.';

  @override
  String get persistenceQueueTitle => 'Persistence diagnostics';

  @override
  String get persistenceQueueUnavailable =>
      'Queue pressure is unavailable from this data source.';

  @override
  String persistenceQueuePending(int operations, int bytes) {
    return 'Queued: $operations operation(s), $bytes byte(s)';
  }

  @override
  String persistenceQueueInFlight(int bytes) {
    return 'Writing: $bytes byte(s)';
  }

  @override
  String persistenceQueueOldestAge(int millis) {
    return 'Oldest unsaved: $millis ms';
  }

  @override
  String get persistenceQueuePressurePaused =>
      'New inference admission is paused under storage pressure.';

  @override
  String persistenceQueueError(String message) {
    return 'Last error: $message';
  }

  @override
  String get persistenceQueueRefresh => 'Refresh diagnostics';

  @override
  String get persistenceQueueShowDetails => 'Show diagnostics';

  @override
  String get persistenceQueueHideDetails => 'Hide diagnostics';

  @override
  String get persistenceHistoryPaused => 'Session history saving is paused';

  @override
  String get persistenceHistoryQueueFull => 'History queue full';

  @override
  String get persistenceHistoryWriteFailed => 'History save failed';

  @override
  String get persistenceHistoryRetrySave => 'Retry saving';

  @override
  String get persistenceHistoryResume => 'Resume execution';

  @override
  String get persistenceHistoryResumeHint => 'Retry saving to enable resume';

  @override
  String get persistenceStatisticsGap =>
      'Call statistics are incomplete; missing usage is unknown, not zero.';

  @override
  String recoveryGlobalWarning(int count) {
    return '$count recovery issue(s) need attention';
  }

  @override
  String get recoveryArchiveNotice =>
      'Migration could not continue. Previous data was archived and anywork started with default settings. Archive:';

  @override
  String get recoveryArchiveDismiss => 'Dismiss archive notice';

  @override
  String get sidebarNew => 'New';

  @override
  String get sidebarOpen => 'Open';

  @override
  String get shellNoSession => 'New session';

  @override
  String get startPageWelcome => 'What can I help you build?';

  @override
  String get preparationTitle => 'Preparing your session';

  @override
  String get preparationSubtitle =>
      'Your request will start once the workspace is ready.';

  @override
  String get preparationFailedTitle => 'Environment setup incomplete';

  @override
  String get preparationRetainedBody =>
      'Your prompt and attachments are saved. Adjust the settings and send again.';

  @override
  String get preparationUnknownTitle => 'Creation outcome unconfirmed';

  @override
  String get preparationUnknownBody =>
      'The connection ended before session creation was confirmed. Do not send again.';

  @override
  String get preparationCheckProject => 'Check project';

  @override
  String get preparationWorkspace => 'Prepare workspace';

  @override
  String get preparationInitializeSession => 'Initialize session';

  @override
  String get preparationSubmitPrompt => 'Submit request';

  @override
  String get preparationWaiting => 'Waiting to begin…';

  @override
  String get preparationCheckingProject =>
      'Checking the project and session configuration…';

  @override
  String get preparationPreparingWorkspace =>
      'Preparing the session workspace…';

  @override
  String get preparationResolvingRepository =>
      'Checking the Git repository and base commit…';

  @override
  String get preparationCreatingWorktree =>
      'Creating the worktree and checking out files…';

  @override
  String get preparationInitializingSession =>
      'Initializing the session environment…';

  @override
  String get preparationSubmittingPrompt => 'Submitting your first request…';

  @override
  String get preparationMoreDetails => 'More details';

  @override
  String get preparationProjectLabel => 'Project';

  @override
  String get preparationRemoteLabel => 'Remote host';

  @override
  String get preparationPathLabel => 'Workspace path';

  @override
  String get preparationBranchLabel => 'Worktree branch';

  @override
  String get preparationDiagnosticLabel => 'Diagnostic ID';

  @override
  String get preparationStepComplete => 'Complete';

  @override
  String get preparationStepPending => 'Pending';

  @override
  String get preparationStepRunning => 'In progress';

  @override
  String get preparationStepFailed => 'Incomplete';

  @override
  String startPageProject(String project) {
    return 'Working in $project';
  }

  @override
  String get startPageStandaloneBody =>
      'No project needed. Files are saved in your Documents/anywork folder.';

  @override
  String get startPageOpenProjectTitle => 'Open a project to get started';

  @override
  String get startPageOpenProjectBody =>
      'Choose a project from the sidebar before sending your first message.';

  @override
  String shellSessionUpdated(String mode, String time) {
    return '$mode · updated $time';
  }

  @override
  String get settingsBack => 'Back';

  @override
  String get settingsBackToChat => 'Back to chat';

  @override
  String get settingsWorkspaceGroup => 'Workspace';

  @override
  String get settingsSystemGroup => 'System';

  @override
  String get settingsAccountsTab => 'Accounts';

  @override
  String get settingsInstructionsTab => 'Instructions';

  @override
  String get settingsSkillsTab => 'Skills';

  @override
  String get settingsAgentsTab => 'Agents';

  @override
  String get settingsMcpTab => 'MCP';

  @override
  String get settingsLspTab => 'LSP';

  @override
  String get settingsStatisticsTab => 'Statistics';

  @override
  String get settingsSecurityTab => 'Security';

  @override
  String get settingsGeneralTab => 'General';

  @override
  String get settingsSshTab => 'SSH';

  @override
  String get settingsBotsTab => 'Bots';

  @override
  String get settingsBotsTitle => 'Feishu bots';

  @override
  String get settingsBotsSubtitle =>
      'Local configuration, live connection, and inbound authorization are three separate facts.';

  @override
  String get settingsBotsAdd => 'Add bot';

  @override
  String get settingsBotsEmptyTitle => 'No bots yet';

  @override
  String get settingsBotsEmptyBody =>
      'Scan to create a Feishu China app, or connect an existing app. Secrets stay in memory until you save.';

  @override
  String get settingsBotsSelectTitle => 'Select a bot';

  @override
  String get settingsBotsSelectBody =>
      'Choose a bot to inspect configuration, connection, and authorization.';

  @override
  String get settingsBotsSetupTitle => 'First-time setup';

  @override
  String get settingsBotsSetupClose => 'Close setup';

  @override
  String get settingsBotsRisk =>
      'Remote messages can start this computer\'s agent tools. The current policy is full-access. Linking a project is not an OS sandbox.';

  @override
  String get settingsBotsPermissions =>
      'Requested scopes (preset=false): im:message:send_as_bot, im:message.p2p_msg:readonly, im:message.group_at_msg:readonly, im:chat:readonly, im:message:readonly, im:resource, cardkit:card:write. Event: im.message.receive_v1. Image and file reception is retained; streaming cards add creation and update access. Existing apps need an administrator to grant card access and publish the app. Declaring permissions does not mean they are approved.';

  @override
  String get settingsBotsName => 'Name';

  @override
  String get settingsBotsProject => 'Linked project';

  @override
  String get settingsBotsRiskAck =>
      'I understand remote messages can run local tools with full-access';

  @override
  String get settingsBotsScan => 'Create and connect Feishu app';

  @override
  String get settingsBotsManual => 'Connect existing app';

  @override
  String get settingsBotsAppId => 'App ID';

  @override
  String get settingsBotsSecret => 'App secret';

  @override
  String get settingsBotsSave => 'Save configuration';

  @override
  String get settingsBotsPendingTitle => 'Unfinished local save';

  @override
  String get settingsBotsPendingPreparing => 'Preparing credentials';

  @override
  String get settingsBotsPendingUncertain => 'Save needs local verification';

  @override
  String get settingsBotsPendingCleanup => 'Cleanup pending';

  @override
  String get settingsBotsPendingCleanupCommitted =>
      'Config saved; cleanup still pending';

  @override
  String get settingsBotsPendingIdle => 'Idle';

  @override
  String get settingsBotsVerify => 'Verify original operation';

  @override
  String get settingsBotsFactConfig => 'Configuration';

  @override
  String get settingsBotsFactConnection => 'Connection';

  @override
  String get settingsBotsFactAuth => 'Authorization';

  @override
  String get settingsBotsFactMissing => 'No available configuration';

  @override
  String get settingsBotsConnectionConnected => 'Connected';

  @override
  String get settingsBotsConnectionConnecting => 'Connecting';

  @override
  String get settingsBotsConnectionFailed => 'Failed';

  @override
  String get settingsBotsConnectionIdle => 'Not connected';

  @override
  String get settingsBotsAuthGranted => 'Local inbound grants exist';

  @override
  String get settingsBotsAuthPending => 'Pairing pending';

  @override
  String get settingsBotsAuthNone => 'No inbound trust';

  @override
  String get settingsBotsCredentialStored => 'Stored';

  @override
  String get settingsBotsCredentialSession => 'Session only';

  @override
  String get settingsBotsCredentialMissing => 'Missing';

  @override
  String get settingsBotsCredentialUnavailable => 'Unavailable';

  @override
  String settingsBotsRegistrationStatus(String status) {
    return 'Registration: $status';
  }

  @override
  String get settingsBotsOpenLink => 'Continue in browser';

  @override
  String get settingsBotsOpenFeishu => 'Continue in Feishu';

  @override
  String get settingsBotsContinueHint =>
      'Confirm app creation in Feishu. This page will update automatically when registration completes.';

  @override
  String get settingsBotsScanOnlyHint =>
      'Scan the QR code with Feishu on your phone and confirm app creation. This page will update automatically.';

  @override
  String get settingsBotsScanHint =>
      'You can also scan with Feishu on your phone. If the client does not open, continue in your browser or scan the code.';

  @override
  String get settingsBotsOpenLinkFailed =>
      'Could not open the link. Scan the QR code to continue, or try the browser option.';

  @override
  String get settingsBotsOpenChat => 'Open chat in Feishu';

  @override
  String get settingsBotsOpenChatBrowser => 'Open through browser';

  @override
  String get settingsBotsPolicyDenied =>
      'Feishu\'s access control policy denied this app\'s API request.';

  @override
  String get settingsBotsPolicyDeniedHint =>
      'Creating an app does not grant API access. Contact your organization\'s administrator to check the app\'s access policy, then retry once access is allowed.';

  @override
  String settingsBotsPlatformCode(String code) {
    return 'Feishu error code: $code';
  }

  @override
  String get settingsBotsCopyLink => 'Copy link';

  @override
  String get settingsBotsRegistrationBusy =>
      'Local save is committing. Cancel is busy and does not mean cancelled.';

  @override
  String get settingsBotsCancelRegistration => 'Cancel registration';

  @override
  String get settingsBotsRegIdle => 'Idle';

  @override
  String get settingsBotsRegPreparing => 'Preparing';

  @override
  String get settingsBotsRegWaiting => 'Waiting for confirmation in Feishu';

  @override
  String get settingsBotsRegSlowDown => 'Slow down';

  @override
  String get settingsBotsRegCommitting => 'Committing';

  @override
  String get settingsBotsRegCompleted => 'Completed';

  @override
  String get settingsBotsRegDenied => 'Denied';

  @override
  String get settingsBotsRegExpired => 'Expired';

  @override
  String get settingsBotsRegCancelled => 'Cancelled';

  @override
  String get settingsBotsRegFailed => 'Failed';

  @override
  String get settingsBotsQrFailed =>
      'Could not encode the verification QR code. Use the local open or copy action for the current trusted link.';

  @override
  String get settingsBotsAppIdLocked =>
      'App ID cannot change after platform conversations or durable records exist.';

  @override
  String get settingsBotsProjectLocked =>
      'Project cannot change after Thread mapping or admitted input exists.';

  @override
  String get settingsBotsEnabled => 'Enable connection';

  @override
  String get settingsBotsRetryConnection => 'Retry connection';

  @override
  String get settingsBotsTools => 'Allow project tools';

  @override
  String get settingsBotsToolsHint =>
      'Only the four tools on the linked project root Thread. Local owner query/send and original auto-replies are not gated by this switch.';

  @override
  String get settingsBotsTrustedUsers => 'Trusted users';

  @override
  String get settingsBotsTrustedChats => 'Trusted groups';

  @override
  String get settingsBotsRevoke => 'Revoke';

  @override
  String get settingsBotsApprove => 'Approve';

  @override
  String get settingsBotsPairingHint =>
      'Unknown DMs do not run the model. After approval, ask the user to resend; old messages are not executed.';

  @override
  String get settingsBotsClearPairing => 'Clear request';

  @override
  String get settingsBotsClearPairingHint =>
      'Clears only this local pairing request. This user\'s current trust setting stays unchanged, and their old messages are not executed.';

  @override
  String get settingsBotsNoTrustedUsers =>
      'No trusted users yet. Manual apps start with an empty trust list.';

  @override
  String get settingsBotsNoTrustedChats =>
      'Groups are off by default. Authorize a group plus the real @mention of this bot.';

  @override
  String get settingsBotsConversations => 'Conversations';

  @override
  String get settingsBotsRefreshConversations => 'Refresh';

  @override
  String get settingsBotsNewThread => 'Create local session';

  @override
  String get settingsBotsMessages => 'Messages';

  @override
  String get settingsBotsSendHint => 'Send as this bot';

  @override
  String get settingsBotsSend => 'Send';

  @override
  String settingsBotsSendStatus(String status) {
    return 'Send status: $status';
  }

  @override
  String get settingsBotsSourceGroup => 'Group chat';

  @override
  String get settingsBotsSourceDirect => 'Direct chat';

  @override
  String get settingsBotsEdit => 'Edit configuration';

  @override
  String get settingsBotsDismiss => 'Cancel';

  @override
  String get settingsBotsPreserveSecret =>
      'Leave blank to keep the existing secret. It is never displayed.';

  @override
  String get settingsBotsClearSecret => 'Remove the saved secret';

  @override
  String get settingsBotsOperationFailed =>
      'The operation could not finish. Check the current state and retry explicitly; an unknown send is not safe to replay.';

  @override
  String get settingsBotsModelReady =>
      'The Simple mode model route and its credential are configured. This is not a live model connectivity check.';

  @override
  String get settingsBotsModelMissing =>
      'Configure an account and a complete Simple mode model route before expecting remote messages to run. Saving this app does not check model connectivity.';

  @override
  String get settingsBotsManualGuide =>
      'In the Feishu China developer console, enable the bot and long-connection event delivery, subscribe to im.message.receive_v1, request the scopes listed above, then publish the app and confirm its availability. Tenant administrators may need to approve permissions. Save here, then enable the connection.';

  @override
  String get settingsBotsFirstMessageGuide =>
      'After a real connection, send the bot a message in Feishu. An unknown sender only creates a pairing request: approve it locally and ask them to send again. Group execution needs local group authorization and a user\'s actual @mention of this bot; @all is not sufficient.';

  @override
  String get settingsBotsNewThreadWarning =>
      'Create a new local context for future messages? Existing history is retained. Already admitted messages and replies stay with their original context and are not moved.';

  @override
  String get settingsBotsApproveGroup => 'Authorize this group';

  @override
  String get settingsBotsNextPage => 'Next page';

  @override
  String get settingsBotsRefreshMessages => 'Apply range / refresh messages';

  @override
  String get settingsBotsStartTime => 'Start time (Unix seconds; optional)';

  @override
  String get settingsBotsEndTime => 'End time (Unix seconds; optional)';

  @override
  String get settingsBotsHistoryPermissions =>
      'Only permitted history is available. Group history may additionally require im:message.group_msg, granted separately in Feishu. This app never requests it automatically or switches to a user identity.';

  @override
  String get settingsBotsOpenConsole => 'Open Feishu developer console';

  @override
  String get settingsBotsOpenConsoleHint =>
      'Opens the official Feishu China developer console page. There, choose the app matching the current App ID and open its permission management; permissions still require administrator approval and the app must stay published with its availability. Nothing is requested or approved automatically here.';

  @override
  String get settingsBotsOpenConsoleFailed =>
      'Could not open the developer console. Please try again.';

  @override
  String get settingsBotsConnectionReconnecting => 'Reconnecting';

  @override
  String get settingsBotsSendOperation => 'Send operation';

  @override
  String get settingsBotsNoReplay =>
      'Some messages may already have been delivered. This result is retained and will not be replayed automatically.';

  @override
  String get settingsBotsSendSucceeded => 'Delivered';

  @override
  String get settingsBotsSendPartial => 'Partially delivered';

  @override
  String get settingsBotsSendRejected => 'Rejected';

  @override
  String get settingsBotsSendUnknown => 'Outcome unknown';

  @override
  String get settingsSshTitle => 'Remote development';

  @override
  String get settingsSshSubtitle =>
      'Servers come from your ~/.ssh/config; anywork manages only its own marked blocks.';

  @override
  String get settingsSshAdd => 'Add server';

  @override
  String get settingsSshEmpty => 'No SSH servers yet.';

  @override
  String get settingsSshManagedByCore =>
      'OpenSSH and the minimal remote helper are managed locally.';

  @override
  String get settingsSshTest => 'Test connection';

  @override
  String get settingsSshReconnect => 'Reconnect';

  @override
  String get settingsSshReconnectHint =>
      'Reconnect to load the latest remote environment. Running remote commands will be interrupted.';

  @override
  String get settingsSshOpenProject => 'Open project';

  @override
  String get settingsSshEdit => 'Edit';

  @override
  String get settingsSshDelete => 'Delete';

  @override
  String get settingsSshReady => 'Ready';

  @override
  String get settingsSshDeleteTitle => 'Delete SSH server?';

  @override
  String settingsSshDeleteBody(String name) {
    return 'Delete $name? Projects using this server must be removed first.';
  }

  @override
  String get settingsSshAlias => 'Alias (Host)';

  @override
  String get settingsSshProjectName => 'Project name';

  @override
  String get settingsSshHost => 'Host';

  @override
  String get settingsSshUsername => 'Username';

  @override
  String get settingsSshPort => 'Port';

  @override
  String get settingsSshIdentityFile => 'Identity file (optional)';

  @override
  String get settingsSshIdentityHelper => 'Uses the ssh agent when left empty.';

  @override
  String get settingsSshEditTitle => 'Edit SSH server';

  @override
  String get settingsSshPassword => 'Password (optional)';

  @override
  String get settingsSshPasswordHelper =>
      'Saved in your system credential store, never written to ~/.ssh/config. Leave empty to use a key or prompt on connect.';

  @override
  String get settingsSshPasswordSavedHint =>
      'Password saved — leave empty to keep';

  @override
  String get settingsSshPasswordClear => 'Clear saved password';

  @override
  String get settingsSshPasswordClearedHint =>
      'Saved password will be cleared on save';

  @override
  String get settingsSshPasswordBadge => 'Password saved';

  @override
  String settingsSshKeyBadge(String path) {
    return 'Key: $path';
  }

  @override
  String get settingsSshAuthPromptTitle => 'Enter SSH password';

  @override
  String settingsSshAuthPromptSubtitle(String target) {
    return 'Password authentication is required to connect to $target.';
  }

  @override
  String get settingsSshAuthPasswordLabel => 'SSH password';

  @override
  String get settingsSshAuthPasswordRequired => 'Enter the SSH password';

  @override
  String get settingsSshAuthRememberPassword =>
      'Save password in system credential store';

  @override
  String get settingsSshAuthConnect => 'Connect';

  @override
  String get settingsSshPasswordAuthUnavailable =>
      'This server does not offer password authentication. Configure an SSH key or start ssh-agent.';

  @override
  String get settingsSshReadOnlyEntry =>
      'Hand-written entry — edit it in ~/.ssh/config.';

  @override
  String get settingsSshSave => 'Save';

  @override
  String get settingsSshAliasRequired => 'Enter an alias';

  @override
  String get settingsSshAliasInvalid =>
      'Alias must be a single token without spaces or wildcards';

  @override
  String get settingsSshAliasHelper =>
      'Stored as a Host entry in ~/.ssh/config; cannot be renamed later.';

  @override
  String get settingsSshHostRequired => 'Enter a host address';

  @override
  String get settingsSshUsernameRequired => 'Enter a username';

  @override
  String get settingsSshPortInvalid => 'Port must be a number from 1 to 65535';

  @override
  String get settingsSshChooseDirectory => 'Choose remote directory';

  @override
  String get settingsSshOpenThisDirectory => 'Open this directory';

  @override
  String get settingsSshGo => 'Go';

  @override
  String get settingsSshDirectoryPathLabel => 'Remote path';

  @override
  String get settingsSshDirectoryPathHint => '/home/user/project';

  @override
  String get settingsSshPathRequired => 'Enter a remote directory path';

  @override
  String get settingsSshPathAbsolute =>
      'Path must be an absolute POSIX path starting with /';

  @override
  String get settingsSshDirectoryEmpty => 'This directory is empty';

  @override
  String get settingsSshDirectoryEmptyHint =>
      'No subdirectories here — you can still open this directory.';

  @override
  String get settingsSshUp => 'Parent directory';

  @override
  String get settingsSshOpenFailed =>
      'Couldn\'t open this directory. Check the server and try again.';

  @override
  String get composerHint => 'Describe what you need...';

  @override
  String get composerSend => 'Send';

  @override
  String get composerStop => 'Stop';

  @override
  String get compileModeSimple => 'Simple';

  @override
  String get compileModeTask => 'Task';

  @override
  String get statusCost => 'Cost';

  @override
  String get statusTotalTokensLabel => 'Total tokens';

  @override
  String get statusModelLabel => 'Model';

  @override
  String get statusCapabilitiesTitle => 'Active capabilities';

  @override
  String get statusSessionMode => 'Session mode';

  @override
  String get statusSessionModeLocked =>
      'Session mode cannot change while the session is running or a workflow is active';

  @override
  String get statusSelectorsNotReady =>
      'Session settings are not ready yet, or a submission is in flight; the selection is unavailable for now.';

  @override
  String get statusModeNeedsProject =>
      'Choose a project before setting the session mode.';

  @override
  String get composerWorkspaceModeLabel => 'Session workspace';

  @override
  String get composerWorkspaceModeLocal => 'Local directory';

  @override
  String get composerWorkspaceModeWorktree => 'New worktree';

  @override
  String get statusPlannerModel => 'Main agent model';

  @override
  String get statusModelRouteUnavailable =>
      'Current model unavailable; show reason';

  @override
  String statusModelRouteUnavailableDetail(String reason) {
    return 'Current model unavailable: $reason';
  }

  @override
  String get statusModelRouteUnavailableFallback =>
      'The current model route is unavailable. Check the account and model settings.';

  @override
  String get statusModelSwitchWhileRunning =>
      'This session is running or waiting for input, so the model cannot be changed yet. Stop the current run or wait for it to finish.';

  @override
  String get statusModelSwitchWhileInactive =>
      'This session is closing, closed, or unavailable due to an error. Restore it before changing the model.';

  @override
  String get statusModelNoticeDismiss => 'Dismiss model notice';

  @override
  String get statusExecutorModel => 'Executor model';

  @override
  String get statusReasoningEffort => 'Reasoning effort';

  @override
  String get statusContextLabel => 'Context';

  @override
  String get statusContextRemainingLabel => 'To compact';

  @override
  String statusContextOverLimitValue(String tokens) {
    return '$tokens over';
  }

  @override
  String get statusModelMaxContextLabel => 'Max context';

  @override
  String get statusModelEffectiveWindowLabel => 'Effective window';

  @override
  String get statusAutoCompactLimitLabel => 'Compact at';

  @override
  String get statusSessionUsageSection => 'Session usage';

  @override
  String get statusInputTokensLabel => 'Input';

  @override
  String get statusOutputTokensLabel => 'Output';

  @override
  String get statusCostEstimateLabel => 'Estimated cost';

  @override
  String get statusUsageIncompleteLabel => 'Incomplete';

  @override
  String get statusCacheLabel => 'Cache hit rate';

  @override
  String get statusCacheHitTokensLabel => 'Cache read';

  @override
  String get statusCacheMissTokensLabel => 'Cache miss';

  @override
  String get statusCacheWriteTokensLabel => 'Cache write';

  @override
  String get statusReasoningTokensLabel => 'Reasoning tokens';

  @override
  String get statusInferenceCountLabel => 'Inferences';

  @override
  String get statusCacheSavingsLabel => 'Cache savings';

  @override
  String get statusUnpricedUsageLabel => 'Unpriced';

  @override
  String get sessionAllAgentsCostTooltip =>
      'Cost for all agents in this session';

  @override
  String get sessionMoreActionsTooltip => 'More actions';

  @override
  String get sessionOpenWorkspace => 'Open workspace';

  @override
  String get sessionOpenWith => 'Open with';

  @override
  String get sessionOpenInVsCode => 'Open in VS Code';

  @override
  String get sessionOpenInZed => 'Open in Zed';

  @override
  String get sessionOpenInTerminal => 'Open in terminal';

  @override
  String get sessionVsCodeUnavailable =>
      'VS Code was not found on this machine';

  @override
  String get sessionZedUnavailable => 'Zed was not found on this machine';

  @override
  String get sessionTerminalUnavailableWindows =>
      'Windows Terminal (wt.exe) was not found';

  @override
  String get sessionTerminalUnavailableLinux =>
      'xdg-terminal-exec or x-terminal-emulator was not found';

  @override
  String get sessionTerminalUnavailableGeneric =>
      'External terminals are unsupported on this platform';

  @override
  String get sessionVsCodeOpenFailed => 'Failed to open VS Code';

  @override
  String get sessionZedOpenFailed => 'Failed to open Zed';

  @override
  String get sessionTerminalOpenFailed => 'Failed to open terminal';

  @override
  String get sessionOpenServerMissing =>
      'The SSH alias for this project is no longer in ~/.ssh/config';

  @override
  String get statusLastConfirmedAgentTokenSpeed =>
      'Last confirmed output speed (includes the first-token wait)';

  @override
  String get settingsStatisticsTitle => 'Statistics';

  @override
  String get settingsStatisticsSubtitle =>
      'Recent successful calls grouped by account and configured model, with an in-group effort breakdown.';

  @override
  String get settingsStatisticsSummaryTitle => 'Model performance';

  @override
  String get settingsStatisticsHistoryTitle => 'Call history';

  @override
  String get settingsStatisticsAllModels => 'All models';

  @override
  String get settingsStatisticsEmpty => 'No call history yet.';

  @override
  String get settingsStatisticsSummaryEmpty =>
      'No model performance summaries yet.';

  @override
  String get settingsStatisticsFilteredEmpty => 'No calls match these filters.';

  @override
  String get settingsStatisticsGapTitle => 'Statistics have gaps';

  @override
  String get settingsStatisticsGapBody =>
      'Some calls could not be recorded; summaries and history may be incomplete.';

  @override
  String get settingsStatisticsReadFailedTitle => 'Could not read statistics';

  @override
  String get settingsStatisticsReadFailedBody =>
      'The displayed data may be unavailable or out of date.';

  @override
  String get settingsStatisticsMismatchesOnly => 'Mismatches only';

  @override
  String get settingsStatisticsMismatchEmpty =>
      'No model mismatches match these filters.';

  @override
  String get statisticsModel => 'Account / model';

  @override
  String get statisticsHistoryModelHeader => 'Model';

  @override
  String get statisticsConfiguredModel => 'Configured model';

  @override
  String get statisticsSentModel => 'Sent model';

  @override
  String get statisticsReportedModel => 'Reported model';

  @override
  String get statisticsUpstreamReportedModel => 'Upstream response model';

  @override
  String get statisticsModelMatched => 'Matched';

  @override
  String get statisticsModelMismatched => 'Mismatch';

  @override
  String get statisticsModelMismatchBadge => 'Model mismatch';

  @override
  String get statisticsModelUnreported => 'Not reported';

  @override
  String get statisticsModelLegacyUnknown => 'Not collected';

  @override
  String get statisticsMetricNotCollected => 'Not collected';

  @override
  String get statisticsModelUnavailable => 'Unavailable';

  @override
  String get statisticsReasoningEffort => 'Reasoning effort';

  @override
  String get statisticsReasoningEffortUnspecified =>
      'Unspecified / not recorded';

  @override
  String get statisticsSpeed => 'Output TPS (incl. first token)';

  @override
  String get statisticsSamples => 'Samples';

  @override
  String get statisticsOutputTokens => 'Output tokens';

  @override
  String get statisticsAverageTtft => 'Average first token';

  @override
  String get statisticsAverageResponse => 'Average total response';

  @override
  String get statisticsCompletedAt => 'Completed';

  @override
  String get statisticsDecode => 'After first token';

  @override
  String get statisticsTotalResponse => 'Total response';

  @override
  String statisticsTtftSampleCount(int count) {
    return '$count first-token samples';
  }

  @override
  String get settingsStatisticsThroughputNote =>
      'Output TPS = provider-confirmed output tokens × 1000 ÷ total response time (including the first-token wait). Total response runs from the request that produced the result to its normalized terminal event; failed retries, backoff, tool execution and post-terminal collection or saving are excluded. The first token is the first non-empty text, reasoning or tool-input increment, and output may include reasoning tokens without double counting. The after-first-token time is diagnostic, not hardware decode time. Samples from the previous statistics definition were discarded; raw calls and billing remain.';

  @override
  String get statusTurnQueued => 'Queued';

  @override
  String get statusTurnPreparing => 'Preparing context';

  @override
  String get statusTurnResponding => 'Responding';

  @override
  String get statusTurnPlanning => 'Planning';

  @override
  String get statusTurnRunningTool => 'Running tool';

  @override
  String get statusTurnWaitingForApproval => 'Waiting for tool approval';

  @override
  String get statusTurnWaitingForUserInput => 'Waiting for input';

  @override
  String get statusTurnPersisting => 'Saving turn';

  @override
  String get statusInteractionToolApproval => 'Waiting for tool approval';

  @override
  String get statusInteractionUserInput => 'Waiting for input';

  @override
  String statusSkillsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skills',
      one: '1 skill',
    );
    return '$_temp0';
  }

  @override
  String statusMcpCount(int count) {
    return '$count MCP';
  }

  @override
  String statusLspCount(int count) {
    return '$count LSP';
  }

  @override
  String get statusLspIndexing => 'Indexing';

  @override
  String get statusLspBusy => 'Working';

  @override
  String statusLspActivityPercentage(int percentage) {
    return '$percentage%';
  }

  @override
  String statusAgentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count agents',
      one: '1 agent',
    );
    return '$_temp0';
  }

  @override
  String get statusSkillsSection => 'Skills';

  @override
  String get statusMcpSection => 'MCP';

  @override
  String get statusLspSection => 'LSP';

  @override
  String get agentDetailStatusQueued => 'Queued';

  @override
  String get agentDetailStatusRunning => 'Running';

  @override
  String get agentDetailStatusCompleted => 'Completed';

  @override
  String get agentDetailStatusErrored => 'Errored';

  @override
  String get agentDetailStatusInterrupted => 'Interrupted';

  @override
  String get agentDetailStatusShutdown => 'Shutdown';

  @override
  String get agentDetailPathLabel => 'Path';

  @override
  String get timelineEmptyTitle => 'No messages yet';

  @override
  String get timelineEmptyMessage =>
      'Open a project or start a session to begin.';

  @override
  String get timelineExternalLinkOpenFailed => 'Unable to open this link.';

  @override
  String get timelineAttachment => 'Attachment';

  @override
  String get timelineImageLoadFailed => 'Unable to load this image.';

  @override
  String get timelineImageRetry => 'Retry';

  @override
  String get timelineImageClose => 'Close image preview';

  @override
  String get timelineImageCardTitle => 'Image card';

  @override
  String get timelineImageCardEmpty => 'This image is unavailable';

  @override
  String timelineRemoteImageSource(String host) {
    return 'External image from $host';
  }

  @override
  String get timelineRemoteImageOpen => 'Click to load and preview';

  @override
  String get timelineJumpToLatest => 'Jump to latest';

  @override
  String get timelineNew => 'New';

  @override
  String get timelineLoadEarlier => 'Load earlier messages';

  @override
  String get timelineBackToLive => 'Back to live';

  @override
  String get timelineDetailUnavailable => 'This content is no longer available';

  @override
  String get timelineReconnecting =>
      'Reconnecting messages… Current content is preserved.';

  @override
  String get timelineConnectionFailed =>
      'Unable to synchronize messages. Current content is preserved.';

  @override
  String get timelineReasoningFallback => 'Thinking';

  @override
  String get timelineReasoningActive => 'Thinking';

  @override
  String get timelineReasoningEnded => 'Thought ended';

  @override
  String get timelineReasoningFailed => 'Thinking failed';

  @override
  String get timelineReasoningCancelled => 'Thinking cancelled';

  @override
  String get timelineReasoningElapsedUnderSecond => 'Thought for less than 1s';

  @override
  String timelineReasoningElapsedSeconds(int seconds) {
    return 'Thought for ${seconds}s';
  }

  @override
  String timelineReasoningElapsedMinutes(int minutes) {
    return 'Thought for ${minutes}m';
  }

  @override
  String timelineReasoningElapsedMinutesSeconds(int minutes, int seconds) {
    return 'Thought for ${minutes}m ${seconds}s';
  }

  @override
  String get timelineGroupWorkedUnderSecond => 'Worked for less than 1s';

  @override
  String timelineGroupWorkedSeconds(int seconds) {
    return 'Worked for ${seconds}s';
  }

  @override
  String timelineGroupWorkedMinutes(int minutes) {
    return 'Worked for ${minutes}m';
  }

  @override
  String timelineGroupWorkedMinutesSeconds(int minutes, int seconds) {
    return 'Worked for ${minutes}m ${seconds}s';
  }

  @override
  String get timelineReasoningSummary => 'Summary';

  @override
  String get timelineReasoningContent => 'Content';

  @override
  String get timelineReasoningBudgetLimited => 'Reasoning budget reached';

  @override
  String get timelineToolFallback => 'Tool';

  @override
  String get timelineToolGroupTitle => 'Tool activity';

  @override
  String timelineToolGroupSummary(int count) {
    return '$count tools';
  }

  @override
  String timelineToolGroupSummaryRunning(int count, int runningCount) {
    return '$count tools, $runningCount running';
  }

  @override
  String timelineToolGroupSummaryIssues(int count, int issueCount) {
    return '$count tools, $issueCount need attention';
  }

  @override
  String timelineToolGroupSummaryRunningWithIssues(
    int count,
    int runningCount,
    int issueCount,
  ) {
    return '$count tools, $runningCount running, $issueCount need attention';
  }

  @override
  String timelineSkillActivated(String name) {
    return 'Activated skill · $name';
  }

  @override
  String timelineSkillAgentActivated(String name) {
    return 'Agent activated skill · $name';
  }

  @override
  String get timelineParentAgent => 'Main agent';

  @override
  String timelineSkillUserActivated(String name) {
    return 'User activated skill · $name';
  }

  @override
  String get timelineAgentFallback => 'Agent';

  @override
  String get timelineViewImageRead => 'Image read';

  @override
  String timelineImagesViewed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Viewed $count images',
      one: 'Viewed 1 image',
    );
    return '$_temp0';
  }

  @override
  String timelineImagesProduced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get timelineViewImageReading => 'Reading image';

  @override
  String get timelineViewImageFailed => 'Failed to read image';

  @override
  String get timelineViewImageStopped => 'Stopped reading image';

  @override
  String get timelineToolReadCompleted => 'Read';

  @override
  String get timelineToolReadReading => 'Reading';

  @override
  String get timelineToolReadFailed => 'Unable to read';

  @override
  String get timelineToolEditSucceeded => 'Edited';

  @override
  String get timelineToolEditRunning => 'Editing';

  @override
  String get timelineToolEditFailed => 'Couldn\'t edit';

  @override
  String timelineToolPatchFilesMore(String first, int more) {
    return '$first, and $more more';
  }

  @override
  String get timelineSessionNoteName => 'session note';

  @override
  String get timelineToolCommandSucceeded => 'Ran';

  @override
  String get timelineToolCommandRunning => 'Running';

  @override
  String get timelineToolCommandFailed => 'Command failed';

  @override
  String get timelineToolStdinSucceeded => 'Wrote input';

  @override
  String get timelineToolStdinRunning => 'Writing input';

  @override
  String get timelineToolStdinFailed => 'Input not written';

  @override
  String get timelineToolElapsedUnderSecond => 'Took less than 1s';

  @override
  String timelineToolElapsedSeconds(int seconds) {
    return 'Took ${seconds}s';
  }

  @override
  String timelineToolElapsedMinutes(int minutes) {
    return 'Took ${minutes}m';
  }

  @override
  String timelineToolElapsedMinutesSeconds(int minutes, int seconds) {
    return 'Took ${minutes}m ${seconds}s';
  }

  @override
  String get timelineToolSearchSucceeded => 'Searched';

  @override
  String get timelineToolSearchRunning => 'Searching';

  @override
  String get timelineToolSearchFailed => 'Search failed';

  @override
  String get timelineToolAgentSucceeded => 'Spawned subagent';

  @override
  String get timelineToolAgentRunning => 'Subagent running';

  @override
  String get timelineToolAgentFailed => 'Subagent failed';

  @override
  String get timelineToolMessageSucceeded => 'Sent message';

  @override
  String get timelineToolMessageRunning => 'Sending message';

  @override
  String get timelineToolMessageFailed => 'Message not sent';

  @override
  String get timelineToolCreateSucceeded => 'Created directory';

  @override
  String get timelineToolCreateRunning => 'Creating directory';

  @override
  String get timelineToolCreateFailed => 'Directory not created';

  @override
  String get timelineToolDeleteSucceeded => 'Deleted';

  @override
  String get timelineToolDeleteRunning => 'Deleting';

  @override
  String get timelineToolDeleteFailed => 'Not deleted';

  @override
  String get timelineToolCopySucceeded => 'Copied';

  @override
  String get timelineToolCopyRunning => 'Copying';

  @override
  String get timelineToolCopyFailed => 'Not copied';

  @override
  String get timelineToolMoveSucceeded => 'Moved';

  @override
  String get timelineToolMoveRunning => 'Moving';

  @override
  String get timelineToolMoveFailed => 'Not moved';

  @override
  String get timelineToolFetchSucceeded => 'Fetched web page';

  @override
  String get timelineToolFetchRunning => 'Fetching web page';

  @override
  String get timelineToolFetchFailed => 'Web page not fetched';

  @override
  String get timelineToolPlanSucceeded => 'Updated plan';

  @override
  String get timelineToolPlanRunning => 'Updating plan';

  @override
  String get timelineToolPlanFailed => 'Plan update failed';

  @override
  String get timelineToolWorkflowSucceeded => 'Updated workflow';

  @override
  String get timelineToolWorkflowRunning => 'Updating workflow';

  @override
  String get timelineToolWorkflowFailed => 'Workflow update failed';

  @override
  String get timelineToolLspSucceeded => 'Queried code';

  @override
  String get timelineToolLspRunning => 'Querying code';

  @override
  String get timelineToolLspFailed => 'Code query failed';

  @override
  String get timelineToolWaitSucceeded => 'Waited';

  @override
  String get timelineToolWaitRunning => 'Waiting';

  @override
  String get timelineToolWaitFailed => 'Wait failed';

  @override
  String get timelineTurnStopped => 'Turn stopped';

  @override
  String get timelineTurnCancelled => 'Turn cancelled';

  @override
  String get timelineTurnRuntimeShutdown => 'Runtime shut down; turn stopped';

  @override
  String get timelineTurnAgentClosed => 'Agent closed; turn stopped';

  @override
  String get timelineTurnRecoveryStopped => 'Turn stopped during recovery';

  @override
  String get timelineTurnCoalesced => 'Turn merged into a later turn';

  @override
  String timelineToolCompleted(String name) {
    return '$name completed';
  }

  @override
  String timelineToolFailed(String name) {
    return '$name failed';
  }

  @override
  String timelineToolDenied(String name) {
    return '$name denied';
  }

  @override
  String timelineToolCancelled(String name) {
    return '$name cancelled';
  }

  @override
  String timelineToolAwaitingApproval(String name) {
    return '$name awaiting approval';
  }

  @override
  String timelineToolRunning(String name) {
    return '$name running';
  }

  @override
  String timelineToolExitCode(int code) {
    return 'exit code $code';
  }

  @override
  String get timelineToolTimedOut => 'timed out';

  @override
  String get agentDetailStatusClosing => 'Closing';

  @override
  String timelineToolQueued(String name) {
    return '$name queued';
  }

  @override
  String timelineToolCancelling(String name) {
    return '$name cancelling';
  }

  @override
  String timelineToolInterrupted(String name) {
    return '$name stopped';
  }

  @override
  String get timelineAgentSubagent => 'Subagent';

  @override
  String get timelineAgentSubagentMessage => 'Subagent message';

  @override
  String get timelineAgentWaiting => 'Waiting for subagents';

  @override
  String get timelineAgentClose => 'Close subagent';

  @override
  String get timelineTodoListFallback => 'Todo list';

  @override
  String get timelineTodoPending => 'Pending';

  @override
  String get timelineTodoInProgress => 'In progress';

  @override
  String get timelineTodoCompleted => 'Completed';

  @override
  String get interactionQuestionsTitle => 'A few questions';

  @override
  String get interactionLastQuestion => 'Last question';

  @override
  String get interactionContinueAfterAnswer => 'Continue after answering';

  @override
  String get timelineRolledBack => 'Rolled back from active context';

  @override
  String get interactionSubmitEmptyAnswersHint =>
      'Unanswered questions are submitted as empty arrays.';

  @override
  String interactionAnsweredPendingHint(int answeredCount, int pendingCount) {
    return '$answeredCount answered · $pendingCount pending';
  }

  @override
  String get interactionPreviousQuestion => 'Previous';

  @override
  String get interactionNextQuestion => 'Next';

  @override
  String get interactionSubmitAnswers => 'Submit answers';

  @override
  String get interactionNeedInputTitle => 'Input needed';

  @override
  String get interactionAnswerHint =>
      'anywork will use this answer to continue the current question.';

  @override
  String get interactionAnswerButton => 'Answer';

  @override
  String get interactionAnswerLabel => 'Answer';

  @override
  String interactionQuestionProgress(int current, int total) {
    return 'Question $current / $total';
  }

  @override
  String interactionAnsweredCount(int count) {
    return '$count answered';
  }

  @override
  String interactionQuestionTooltip(int index) {
    return 'Question $index';
  }

  @override
  String get interactionQuestionFallback => 'Question';

  @override
  String get interactionOtherLabel => 'Other';

  @override
  String get interactionSecretHint => 'Enter secret answer';

  @override
  String get interactionTextHint => 'Enter your answer...';

  @override
  String get interactionPermissionTitle => 'Permission needed';

  @override
  String get interactionPermissionSubtitle =>
      'anywork wants to run a tool call';

  @override
  String get interactionPermissionFooterHint =>
      'The tool runs in the current working directory.';

  @override
  String get interactionReject => 'Reject';

  @override
  String get interactionApprove => 'Approve';

  @override
  String get interactionReasonLabel => 'Reason';

  @override
  String get interactionPlanConfirmTitle => 'Confirm this plan?';

  @override
  String get interactionPlanConfirmSubtitle =>
      'Confirm it, or describe what should change.';

  @override
  String get interactionPlanReadyTitle => 'Implementation plan ready';

  @override
  String get interactionPlanAwaitingConfirmation => 'Awaiting confirmation';

  @override
  String get interactionPlanApproved => 'Approved';

  @override
  String get statusPlanEntry => 'Plan';

  @override
  String get interactionPlanViewDetails => 'View full plan';

  @override
  String get interactionPlanDetailsTitle => 'Implementation plan';

  @override
  String interactionPlanConfirmFooterHint(String mode) {
    return 'Confirming starts the document-editing checkpoint in $mode mode.';
  }

  @override
  String get interactionPlanAdjust => 'Tell anywork how to adjust';

  @override
  String get interactionPlanConfirmAction => 'Confirm and execute';

  @override
  String get interactionPlanAdjustHint => 'Describe what should change...';

  @override
  String get interactionPlanAdjustSubmit => 'Submit changes';

  @override
  String get interactionPlanFeedbackHint =>
      'Enter submits · Shift+Enter adds a line';

  @override
  String get planExpandReading => 'Read full width';

  @override
  String get planRestoreSplit => 'Restore side-by-side';

  @override
  String get planReceiptApproved => 'Plan approved';

  @override
  String get planReceiptRevisionRequested => 'Plan changes requested';

  @override
  String get planReceiptCancelled => 'Plan confirmation cancelled';

  @override
  String get planReceiptAnswered => 'Plan confirmation answered';

  @override
  String get planReceiptYourReply => 'Your reply';

  @override
  String get planReceiptYourFeedback => 'Requested changes';

  @override
  String get planReceiptApproveReply => 'Approved this plan for execution';

  @override
  String get settingsAccountsTitle => 'Accounts';

  @override
  String get settingsAccountsSubtitle =>
      'Accounts, credentials, models, and usage';

  @override
  String get settingsRefreshUsage => 'Refresh usage';

  @override
  String get settingsAddAccount => 'Add account';

  @override
  String get settingsSearchAccounts => 'Search accounts';

  @override
  String get settingsNoAccountsMatchTitle => 'No accounts match this filter';

  @override
  String get settingsNoAccountsMatchMessage =>
      'Clear the search to see all configured accounts.';

  @override
  String get settingsNoAccountsTitle => 'No accounts found';

  @override
  String get settingsNoAccountsMessage =>
      'Add an account to configure credentials and models.';

  @override
  String get settingsDefaultAccount => 'Default account';

  @override
  String get settingsSetAsDefaultAccount => 'Set as default';

  @override
  String get settingsOpenDetails => 'Open details';

  @override
  String get settingsAccountActions => 'Account actions';

  @override
  String get settingsEditAccount => 'Edit account';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsNoAccountSelected => 'No account selected';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsAccountModelsTitle => 'Models';

  @override
  String get settingsAccountConnectionTitle => 'Connection';

  @override
  String get settingsAccountDefaultModelsTitle =>
      'Default catalog (not yet synced)';

  @override
  String get settingsAccountCustomModelsTitle => 'Manual models';

  @override
  String get settingsAccountOnlineModelsTitle => 'Online models';

  @override
  String get settingsNewAccount => 'New account';

  @override
  String get settingsAccountId => 'Account ID';

  @override
  String get settingsAccountTemplate => 'Account template';

  @override
  String get settingsCustomAccount => 'Custom account';

  @override
  String get settingsDefaultModel => 'Default model';

  @override
  String get settingsApiKey => 'API key';

  @override
  String get settingsApiKeyKeepCurrent =>
      'API key (leave blank to keep current)';

  @override
  String get settingsConfigured => 'configured';

  @override
  String get settingsMissing => 'missing';

  @override
  String get settingsDisplayName => 'Display name';

  @override
  String get settingsProtocolType => 'Protocol type';

  @override
  String get settingsBaseUrl => 'Base URL';

  @override
  String get settingsModelId => 'Model model_id';

  @override
  String get settingsReasoningEfforts => 'Reasoning efforts';

  @override
  String get settingsEdit => 'Edit';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsAddModel => 'Add model';

  @override
  String get settingsRemoveModel => 'Remove model';

  @override
  String get settingsNoCustomModels => 'No manual models';

  @override
  String get settingsNoOnlineModels => 'No online models';

  @override
  String get settingsNoBundledModels => 'No bundled models';

  @override
  String get settingsModelOriginOnline => 'Online';

  @override
  String get settingsModelOriginBundled => 'Bundled';

  @override
  String get settingsModelOriginManual => 'Manual';

  @override
  String get settingsRemoveManualModelConfirmTitle =>
      'Delete this manual model?';

  @override
  String get settingsRemoveManualModelConfirmBody =>
      'This cannot be undone. The model leaves the catalog, and its connection and compact overrides are cleared. History, bills, and session costs stay unchanged.';

  @override
  String get settingsRemoveManualModelConfirmAction => 'Delete';

  @override
  String get settingsRemoveManualModelFailed =>
      'Could not delete this manual model.';

  @override
  String get settingsManualModelIdConflict =>
      'A model with this model_id already exists in the online or bundled catalog.';

  @override
  String settingsBundledModels(int count) {
    return '$count bundled';
  }

  @override
  String get settingsDefaultBadge => 'default';

  @override
  String get settingsReadyBadge => 'ready';

  @override
  String get settingsSetupBadge => 'setup';

  @override
  String get settingsUsageTitle => 'Usage';

  @override
  String settingsUsageUpdated(String updatedAt) {
    return 'Updated $updatedAt';
  }

  @override
  String get settingsUsageAvailableBalance => 'Available balance';

  @override
  String get settingsUsageBalanceUnavailable => 'Balance unavailable';

  @override
  String get settingsUsageBalanceSufficient => 'Balance sufficient';

  @override
  String get settingsUsageBalanceInsufficient => 'Insufficient balance';

  @override
  String get settingsUsageTotalBalance => 'Total available';

  @override
  String get settingsUsageGrantedBalance => 'Granted balance';

  @override
  String get settingsUsageToppedUpBalance => 'Topped-up balance';

  @override
  String settingsUsageGranted(String amount) {
    return 'Granted $amount';
  }

  @override
  String settingsUsageToppedUp(String amount) {
    return 'Topped up $amount';
  }

  @override
  String get settingsUsageRefreshing => 'Refreshing usage...';

  @override
  String get settingsUsageChecking => 'Checking usage...';

  @override
  String get settingsUsageCheckingShort => 'Checking usage';

  @override
  String get settingsUsageNotLoaded => 'Usage not loaded';

  @override
  String get settingsUsageUnsupported => 'Unsupported';

  @override
  String get settingsUsageNotSupported => 'Usage not supported';

  @override
  String get settingsUsageMissingKey => 'Missing key';

  @override
  String get settingsUsageFailed => 'Usage failed';

  @override
  String get settingsUsageQueryFailed => 'Usage query failed';

  @override
  String get settingsUsageApiKeyMissing => 'Account API key is not configured';

  @override
  String settingsUsageUnsupportedForAccount(String accountName) {
    return 'Usage is not supported for $accountName';
  }

  @override
  String get settingsUsageNotChecked => 'Not checked';

  @override
  String get settingsUsageUnavailable => 'Usage is unavailable';

  @override
  String get settingsUsageError => 'Could not load usage';

  @override
  String get settingsUsageNoQuota => 'No quota details returned.';

  @override
  String get settingsUsageTools => 'Tools';

  @override
  String get settingsUsageToken => 'Token usage';

  @override
  String get settingsUsageSpend => 'Spend';

  @override
  String get settingsUsageRemaining => 'Remaining';

  @override
  String get settingsUsageUsed => 'Used';

  @override
  String get settingsUsageFiveHourQuota => '5 hour quota';

  @override
  String get settingsUsageWeeklyQuota => 'Weekly quota';

  @override
  String get settingsUsageMcpQuota => 'MCP quota';

  @override
  String get settingsUsageQuota => 'Quota';

  @override
  String settingsUsageQuotaRemaining(String remaining, String total) {
    return '$remaining of $total remaining';
  }

  @override
  String settingsUsageQuotaUsed(String current, String total) {
    return '$current of $total used';
  }

  @override
  String settingsUsagePercentRemaining(String percent) {
    return '$percent remaining';
  }

  @override
  String settingsUsageReset(String time) {
    return 'Reset $time';
  }

  @override
  String get settingsInstructionsTitle => 'Instructions';

  @override
  String get settingsInstructionsSubtitle =>
      'Injected into each turn; changes save after typing stops.';

  @override
  String get settingsBaseInstructions => 'Base instructions';

  @override
  String get settingsDeveloperInstructions => 'Developer instructions';

  @override
  String get settingsUserContext => 'User context';

  @override
  String get settingsInstructionHint => 'Add project guidance here';

  @override
  String get settingsSkillsTitle => 'Skills';

  @override
  String get settingsSkillsSubtitle =>
      'Disable noisy skills or discover project/user/system catalogs.';

  @override
  String get settingsDiscover => 'Discover';

  @override
  String get settingsDiscovering => 'Discovering';

  @override
  String get settingsFilterSkills => 'Filter skills';

  @override
  String get settingsOpenProjectToDiscoverSkills =>
      'Open a project to discover skills';

  @override
  String get settingsNoSkillsMatchFilter => 'No skills match this filter';

  @override
  String get settingsSkillsDiscoverySources =>
      'Skills are discovered from the selected workspace and configured user/system sources.';

  @override
  String get settingsClearSearchOrDiscoverAgain =>
      'Clear the search or run discovery again.';

  @override
  String get settingsNoSkillsTitle => 'No skills found';

  @override
  String get settingsNoSkillsMessage =>
      'Try another filter or discover skills for this project.';

  @override
  String get settingsRoleExplorerDescription =>
      'Explore code and collect context.';

  @override
  String get settingsRolePlannerDescription =>
      'Understand requests, plan work, coordinate subagents, integrate and verify results.';

  @override
  String get settingsRoleExecutorDescription => 'Apply edits and run tools.';

  @override
  String get settingsRoleWorktreeExecutorDescription =>
      'Apply edits and run tools in an isolated Git worktree.';

  @override
  String get settingsRoleReviewerDescription =>
      'Review results and verify risk.';

  @override
  String get settingsRoleFallbackDescription => 'Studio role';

  @override
  String get settingsModelField => 'Model';

  @override
  String get settingsMcpTitle => 'MCP';

  @override
  String get settingsMcpSubtitle =>
      'Model Context Protocol servers and inline endpoints.';

  @override
  String get settingsMcpRefresh => 'Refresh';

  @override
  String get settingsMcpReconnect => 'Reconnect';

  @override
  String get settingsMcpResetAll => 'Reset all';

  @override
  String get settingsMcpResetConfirmTitle => 'Reset all MCP servers?';

  @override
  String get settingsMcpResetConfirmBody =>
      'Every configured MCP connection will be rebuilt. Active turns keep their current leased generation.';

  @override
  String get settingsMcpResetConfirmAction => 'Reset all';

  @override
  String get settingsEndpoint => 'Endpoint';

  @override
  String get settingsMcpEmptyTitle => 'No MCP servers';

  @override
  String get settingsMcpEmptyMessage =>
      'Configured MCP servers will appear here.';

  @override
  String get settingsLspTitle => 'Language servers';

  @override
  String get settingsLspSubtitle =>
      'Last-known project language server status and explicit lifecycle commands.';

  @override
  String get settingsLspRefresh => 'Refresh';

  @override
  String get settingsLspProbe => 'Probe';

  @override
  String get settingsLspRepair => 'Repair';

  @override
  String get settingsLspReset => 'Reset';

  @override
  String get settingsLspResetWorkspace => 'Reset workspace';

  @override
  String get settingsLspActivityIndexing => 'Indexing';

  @override
  String get settingsLspActivityBusy => 'Busy';

  @override
  String get settingsLspEmptyTitle => 'No language servers';

  @override
  String get settingsLspEmptyMessage =>
      'Activate a supported project to create language server membership.';

  @override
  String get settingsSecurityTitle => 'Security';

  @override
  String get settingsSecuritySubtitle =>
      'Choose the default approval posture for this workspace.';

  @override
  String get settingsSecurityModeSubtitle =>
      'Tool execution permission is fixed to full access; workspace and worktree boundaries are not relaxed.';

  @override
  String settingsCurrentMode(String mode) {
    return 'Current: $mode';
  }

  @override
  String get settingsWorkspaceBoundary =>
      'Workspace boundary policy remains unchanged.';

  @override
  String get settingsGeneralTitle => 'General';

  @override
  String get settingsGeneralSubtitle =>
      'Interface preferences saved into the Studio store.';

  @override
  String get settingsFollowActiveTurn => 'Follow active turn';

  @override
  String get settingsFollowActiveTurnSubtitle =>
      'Keep new timeline output pinned to the latest turn.';

  @override
  String get settingsInterfaceLanguage => 'Interface language';

  @override
  String get settingsInterfaceLanguageSubtitle =>
      'Change the interface language without changing conversation content.';

  @override
  String get settingsLanguageSystem => 'Follow system';

  @override
  String get settingsCompactTimeline => 'Compact timeline';

  @override
  String get settingsCompactTimelineSubtitle =>
      'Reduce message spacing for denser reading.';

  @override
  String get settingsWebSearchTitle => 'Web search';

  @override
  String get settingsWebSearchSubtitle =>
      'Search through an eligible OpenAI account. Changes apply from the next turn.';

  @override
  String get settingsWebSearchConfiguredMode => 'Configured mode';

  @override
  String get settingsWebSearchEffectiveMode => 'Effective mode';

  @override
  String get settingsWebSearchAccount => 'OpenAI account';

  @override
  String get settingsWebSearchModel => 'Search model';

  @override
  String get settingsWebSearchMode => 'Mode';

  @override
  String get settingsWebSearchModeDisabled => 'Disabled';

  @override
  String get settingsWebSearchModeCached => 'Cached';

  @override
  String get settingsWebSearchModeIndexed => 'Indexed';

  @override
  String get settingsWebSearchModeLive => 'Live';

  @override
  String get settingsWebSearchContextSize => 'Context size';

  @override
  String get settingsWebSearchContextLow => 'Low';

  @override
  String get settingsWebSearchContextMedium => 'Medium';

  @override
  String get settingsWebSearchContextHigh => 'High';

  @override
  String get settingsServiceDefault => 'Service default';

  @override
  String get settingsWebSearchAllowedDomains => 'Allowed domains';

  @override
  String get settingsWebSearchDomainsHint => 'example.com, docs.example.com';

  @override
  String get settingsWebSearchCountry => 'Country';

  @override
  String get settingsWebSearchRegion => 'Region';

  @override
  String get settingsWebSearchCity => 'City';

  @override
  String get settingsWebSearchTimezone => 'Timezone';

  @override
  String get settingsWebSearchAvailable => 'Available';

  @override
  String get settingsWebSearchDisabled => 'Disabled';

  @override
  String get settingsWebSearchMissingCredential => 'Missing credential';

  @override
  String get settingsWebSearchUnsupportedAccount => 'Unsupported account';

  @override
  String get settingsWebSearchUnsupportedModel => 'Unsupported model';

  @override
  String get settingsWebSearchMissingCredentialReason =>
      'No credentialed account originating from the OpenAI template is available. Remote web search is fully disabled.';

  @override
  String get settingsWebSearchUnsupportedAccountReason =>
      'The current account does not expose this web search backend.';

  @override
  String get settingsWebSearchUnsupportedModelReason =>
      'The current route cannot expose either the function tool or hosted web search.';

  @override
  String get settingsNotAvailable => 'Not available';

  @override
  String get settingsSaveWebSearch => 'Save web search';

  @override
  String get settingsWebSearchUnsaved => 'Unsaved search settings';

  @override
  String get settingsDeepSeekWebSearchTitle => 'DeepSeek native web search';

  @override
  String get settingsDeepSeekWebSearchSubtitle =>
      'Other available web search is tried first; DeepSeek web search is used only as a billed fallback when other search is unconfigured, unavailable, or fails. Search and fetch are billed per request.';

  @override
  String get settingsDeepSeekWebSearchAccount => 'DeepSeek account';

  @override
  String get settingsDeepSeekWebSearchConfigured => 'Search configured';

  @override
  String get settingsDeepSeekWebSearchEffective => 'Search effective';

  @override
  String get settingsDeepSeekWebSearchEnabled => 'Enabled';

  @override
  String get settingsDeepSeekWebSearchEnableLabel => 'Web search';

  @override
  String get settingsDeepSeekWebFetchEnableLabel => 'Page fetch';

  @override
  String get settingsDeepSeekWebFetchConfigured => 'Fetch configured';

  @override
  String get settingsDeepSeekWebFetchEffective => 'Fetch effective';

  @override
  String get settingsStudioUpdateTitle => 'anywork update';

  @override
  String settingsStudioUpdateDisabled(String version) {
    return 'Version $version. Automatic checks run only in Windows release builds.';
  }

  @override
  String settingsStudioUpdateCurrent(String version) {
    return 'Current version: $version';
  }

  @override
  String settingsStudioUpdateChecking(String version) {
    return 'Version $version. Checking for updates...';
  }

  @override
  String settingsStudioUpdateLatest(String version) {
    return 'Version $version is up to date.';
  }

  @override
  String settingsStudioUpdateAvailable(String current, String latest) {
    return 'Version $current is installed. Version $latest is available.';
  }

  @override
  String settingsStudioUpdateDownloading(String version, int progress) {
    return 'Downloading version $version: $progress%';
  }

  @override
  String settingsStudioUpdateVerifying(String version) {
    return 'Verifying version $version...';
  }

  @override
  String settingsStudioUpdateInstallerLaunched(String version) {
    return 'Installer for version $version started.';
  }

  @override
  String settingsStudioUpdateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get settingsStudioUpdatePreparing => 'Preparing update…';

  @override
  String get settingsStudioUpdateWhenReady => 'Install and restart when ready';

  @override
  String get settingsStudioUpdateCancelling => 'Cancelling update…';

  @override
  String get settingsStudioUpdateCancelled =>
      'Update cancelled. You can retry anytime.';

  @override
  String get settingsStudioUpdateCheck => 'Check for updates';

  @override
  String get settingsStudioUpdateInstall => 'Download, install and restart';

  @override
  String get settingsStudioUpdateRestart => 'Install and restart';

  @override
  String settingsStudioUpdateReady(String version) {
    return 'Version $version is downloaded and will install when you close anywork.';
  }

  @override
  String get settingsStudioUpdateReleaseNotes => 'Release notes';

  @override
  String get timelineWebSearchTitle => 'Web search';

  @override
  String get timelineWebSearchSearching => 'Searching the web';

  @override
  String get timelineWebSearchOpening => 'Opening a web page';

  @override
  String get timelineWebSearchFinding => 'Finding text on a page';

  @override
  String get timelineWebSearchSearched => 'Searched the web';

  @override
  String get timelineWebSearchOpened => 'Opened a web page';

  @override
  String get timelineWebSearchFound => 'Searched page text';

  @override
  String get timelineWebSearchFailed => 'Web search failed';

  @override
  String get timelineWebSearchOpenFailed => 'Couldn\'t open a web page';

  @override
  String get timelineWebSearchFindFailed => 'Page search failed';

  @override
  String get timelineWebSearchResults => 'Result links';

  @override
  String get timelineLspQueryTitle => 'LSP query';

  @override
  String timelineLspQueryTitleWithDetail(String detail) {
    return 'LSP query · $detail';
  }

  @override
  String get timelineLspCapabilitiesTitle => 'LSP capabilities';

  @override
  String get modalityText => 'Text';

  @override
  String get modalityImage => 'Vision';

  @override
  String get modalityAudio => 'Audio';

  @override
  String get modalityVideo => 'Video';

  @override
  String get modalityFile => 'File';

  @override
  String get composerAddUrlTitle => 'Add URL';

  @override
  String get composerAddUrlConfirm => 'Add';

  @override
  String get composerAttachmentAddTooltip => 'Add attachment';

  @override
  String get composerAttachmentUnsupportedTooltip =>
      'The current model does not support attachments';

  @override
  String get composerAttachmentPickLocal => 'Choose local files';

  @override
  String get composerAttachmentRemoveTooltip => 'Remove';

  @override
  String get composerClipboardImageUnsupported =>
      'The current model does not support pasted images.';

  @override
  String get composerClipboardReadFailed =>
      'Unable to read the clipboard image.';

  @override
  String settingsModelOutputCapabilities(String capabilities) {
    return 'Outputs: $capabilities';
  }

  @override
  String get settingsAgentsTitle => 'Agent Profiles';

  @override
  String get settingsAgentsSubtitle =>
      'Enable and configure subagents by purpose; directory mode restricts built-in file writes, not OS access.';

  @override
  String get settingsAgentsAddUserProfile => 'Add user profile';

  @override
  String get settingsAgentsEditTooltip => 'Edit';

  @override
  String get settingsAgentsRecoveryTitle => 'Recovery';

  @override
  String settingsWorktreeBase(String commit) {
    return 'base $commit';
  }

  @override
  String settingsWorktreeHead(String commit) {
    return 'head $commit';
  }

  @override
  String get settingsWorktreeHeadUnavailable => 'head unavailable';

  @override
  String settingsWorktreeChangedFiles(String files) {
    return 'Changed files: $files';
  }

  @override
  String get settingsWorktreeCleanup => 'Remove worktree (keep branch)';

  @override
  String get settingsWorktreeOwnerSession => 'Session worktree';

  @override
  String get settingsWorktreeOwnerChild => 'Child agent worktree';

  @override
  String get settingsAgentProfileAddTitle => 'Add user agent profile';

  @override
  String get settingsAgentProfileEditTitle => 'Edit user agent profile';

  @override
  String get settingsAgentProfileIdField => 'Agent ID';

  @override
  String get settingsAgentProfileDisplayNameField => 'Display name';

  @override
  String get settingsAgentProfileDescriptionField => 'Description';

  @override
  String get settingsAgentProfileWhenToUseField => 'Best for';

  @override
  String get settingsAgentProfileInstructionsField => 'System instructions';

  @override
  String get settingsAgentProfileAccountField => 'Account';

  @override
  String get settingsAgentProfileEffortDefault => 'Use model default';

  @override
  String get settingsAgentProfileWorkspaceModeField => 'Workspace mode';

  @override
  String get settingsAgentWorkspaceModeUnrestricted => 'Unrestricted';

  @override
  String get settingsAgentWorkspaceModeDirectory => 'Directory';

  @override
  String get settingsAgentWorkspaceModeWorktree => 'Worktree';

  @override
  String get settingsAgentWorkspaceModeReview => 'Review';

  @override
  String get settingsAgentProfileWorkspaceDirectoryHint =>
      'Directory mode limits built-in file writes to the project only; it is not an OS sandbox, and shell, Git, and MCP can still bypass it.';

  @override
  String get settingsAgentProfileWorkspaceReviewHint =>
      'Review mode requires the reviewed agent ID at dispatch time and adopts that agent\'s workspace and boundary; system instructions keep it review-only.';

  @override
  String get settingsAgentProfileEnabledTitle => 'Enabled';

  @override
  String get settingsAgentProfileEnabledSubtitle =>
      'Disabled profiles keep their TOML file but no longer appear in the agent tool catalog.';

  @override
  String get settingsAgentProfileSave => 'Save TOML atomically';

  @override
  String get settingsAgentProfileRequired => 'Required';

  @override
  String get settingsServiceCapabilitiesTitle => 'Service capabilities';

  @override
  String get settingsCapabilitySourceField => 'Capability source';

  @override
  String get settingsCapabilitySourceTemplate => 'Follow template defaults';

  @override
  String get settingsCapabilitySourceExplicit => 'Explicit override';

  @override
  String get settingsHostedWebSearchField => 'Hosted Web Search';

  @override
  String get settingsHostedWebSearchDialectField => 'Hosted Web Search dialect';

  @override
  String get settingsStandaloneWebSearchField => 'Standalone Web Search';

  @override
  String get settingsProgrammaticToolCallingField =>
      'Programmatic Tool Calling';

  @override
  String get settingsCapabilityEnabled => 'Enabled';

  @override
  String get settingsCapabilityDisabled => 'Disabled';

  @override
  String get settingsDefaultConnectionField => 'Default connection';

  @override
  String get settingsCurrentConnectionField => 'Current connection';

  @override
  String get settingsSupportedConnectionsLabel => 'Supported connections';

  @override
  String get settingsAgentRoutesTitle => 'System agent model routing';

  @override
  String get settingsStateChecking => 'Checking';

  @override
  String get settingsStateAvailable => 'Available';

  @override
  String get settingsStateUnavailable => 'Unavailable';

  @override
  String get settingsStateDisabled => 'Disabled';

  @override
  String get settingsMcpStateMissingCredential => 'Missing credential';

  @override
  String get settingsLspActivityIdle => 'Idle';

  @override
  String get roleExplorer => 'Explorer';

  @override
  String get rolePlanner => 'Main agent';

  @override
  String get roleExecutor => 'Executor';

  @override
  String get roleWorktreeExecutor => 'Worktree executor';

  @override
  String get roleReviewer => 'Reviewer';

  @override
  String get roleEmpty => 'Agent';

  @override
  String get settingsNoCharge => 'No charge';

  @override
  String get settingsNoChargeHelp =>
      'On: declare future model calls on this account as not charged. Off: clear the billing override and restore automatic classification. Token, cache and performance statistics and model reference prices are preserved. Other categories estimate costs when prices and usage are available.';

  @override
  String get settingsModelAdvanced => 'Optional model settings';

  @override
  String get settingsContextBudget => 'Context budget (tokens)';

  @override
  String get settingsOutputBudget => 'Maximum output (tokens)';

  @override
  String get settingsModelAutoCompactTitle => 'Context compaction threshold';

  @override
  String get settingsModelAutoCompactRestore => 'Reset to automatic';

  @override
  String get settingsModelAutoCompactSaving => 'Applying automatically…';

  @override
  String get settingsModelAutoCompactSaveFailed =>
      'Could not apply. Your input is kept.';

  @override
  String get settingsModelAutoCompactRetry => 'Retry';

  @override
  String get settingsModelAutoCompactOverrideLabel => 'Mode';

  @override
  String get settingsModelAutoCompactEffectiveLabel => 'Effective';

  @override
  String get settingsModelAutoCompactUsingDefault => 'Automatic';

  @override
  String get settingsModelAutoCompactInputLabel => 'Threshold (tokens)';

  @override
  String get settingsModelAutoCompactInvalid =>
      'Enter a positive integer token count.';

  @override
  String get settingsModelAutoCompactHelp =>
      'The effective threshold is capped at 90% of the context window and reserves the maximum output budget.';

  @override
  String get settingsModelAutoCompactUnknownCapacity =>
      'Context capacity is unknown, so an automatic compaction threshold cannot be calculated.';

  @override
  String get settingsPriceInput => 'Input';

  @override
  String get settingsPriceOutput => 'Output';

  @override
  String get settingsPriceCacheRead => 'Cache read';

  @override
  String get settingsPriceCacheWrite => 'Cache write';

  @override
  String get settingsSystemAgentsGroup => 'System subagents';

  @override
  String get settingsUserAgentsGroup => 'User subagents';

  @override
  String get settingsAppearanceGroup => 'Appearance & conversation';

  @override
  String get settingsNetworkGroup => 'Search & network';

  @override
  String get settingsUpdatesGroup => 'Application updates';

  @override
  String get settingsModelsGroup => 'Models & agents';

  @override
  String get settingsExtensionsGroup => 'Tools & services';

  @override
  String get settingsPreferencesGroup => 'Preferences';

  @override
  String get settingsFilterAgents => 'Filter agents';

  @override
  String get timelineToolArguments => 'Arguments';

  @override
  String get timelineToolOutput => 'Output';

  @override
  String get costPurposeMain => 'Main conversation';

  @override
  String get costPurposeSummary => 'Summarization';

  @override
  String get costPurposeReview => 'Review';

  @override
  String get costPurposeTitle => 'Title';

  @override
  String get costPurposeUnknown => 'Unknown purpose';

  @override
  String get timelineRawRecord => 'Original history record';

  @override
  String get timelineRuntimeNotice => 'Runtime notice';

  @override
  String get timelineRuntimeNoticeDetail =>
      'This session continued after it was stopped. This entry is a runtime notice and carries no user input.';

  @override
  String get sidebarSearch => 'Search projects and sessions';

  @override
  String get sidebarAll => 'All';

  @override
  String get sidebarRunning => 'Running';

  @override
  String get sidebarAttention => 'Needs attention';

  @override
  String get sidebarAddProject => 'Add project';

  @override
  String get sidebarLocalProject => 'Local project';

  @override
  String get sidebarLocalHint => 'Choose a folder on this computer';

  @override
  String get sidebarRemoteProject => 'Remote project';

  @override
  String get sidebarRemoteHint => 'Connect to a remote folder over SSH';

  @override
  String get sidebarContinue => 'Continue';

  @override
  String get sidebarBack => 'Back';

  @override
  String get sidebarConnect => 'Connect and choose folder';

  @override
  String get sidebarSaveConnect => 'Save and connect';

  @override
  String get sidebarSearchConnections => 'Search configured connections';

  @override
  String get sidebarNoConnections => 'No remote connections yet';

  @override
  String get sidebarNewConnection => 'New remote connection';

  @override
  String get sidebarNoResults => 'No matching projects or sessions';

  @override
  String get sidebarEmptyProject =>
      'No sessions yet. Use + on this project to start';

  @override
  String get sidebarStandaloneSessions => 'Non-project sessions';

  @override
  String get sidebarStandaloneEmpty => 'No non-project sessions yet.';

  @override
  String sidebarStandalonePrepareFailed(String error) {
    return 'Couldn\'t prepare a workspace: $error. Select New session to retry.';
  }

  @override
  String get sidebarEarlier => 'Show earlier sessions';

  @override
  String get sidebarArchived => 'Archived';

  @override
  String get sidebarRestore => 'Unarchive session';

  @override
  String get sidebarPin => 'Pin';

  @override
  String get sidebarUnpin => 'Unpin';

  @override
  String get sidebarNavigation => 'Project navigation';

  @override
  String get sidebarResize => 'Resize sidebar; use arrows, Home to reset';

  @override
  String get planResize => 'Resize plan details; use arrows, Home to reset';

  @override
  String get sidebarLocal => 'Local';

  @override
  String get sidebarDetailUpdatedNow => 'Updated just now';

  @override
  String sidebarDetailUpdatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count minutes ago',
      one: 'Updated 1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String sidebarDetailUpdatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count hours ago',
      one: 'Updated 1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String sidebarDetailUpdatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count days ago',
      one: 'Updated 1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get sidebarNotChecked => 'Not checked';

  @override
  String get sidebarConnectionSaved =>
      'Configuration saved; connection failed. Edit or retry';

  @override
  String get sidebarCopyPath => 'Copy path';

  @override
  String get sidebarRetry => 'Retry';

  @override
  String get settingsSshRemoteHelper => 'helper';

  @override
  String statusThroughputValue(String value) {
    return '$value t/s';
  }

  @override
  String get statusThroughputUnavailable => '- t/s';

  @override
  String get workflowStatePlanning => 'Planning';

  @override
  String get workflowStateEditingDocuments => 'Editing docs';

  @override
  String get workflowStateWorking => 'Working';

  @override
  String get workflowStateIntegrating => 'Integrating';

  @override
  String get workflowStateReviewing => 'Reviewing';

  @override
  String get workflowStateCompleted => 'Completed';

  @override
  String get workflowStateStopped => 'Stopped';

  @override
  String get workflowModeSimple => 'Simple';

  @override
  String get workflowModeTask => 'Task';

  @override
  String get attachmentFallback => 'Attachment';

  @override
  String get timelineAgentTimedOut => 'timed out';

  @override
  String timelineToolUnknownStatus(String name, String status) {
    return '$name · $status';
  }

  @override
  String get timelineTodoStatusUnknown => 'Unknown';

  @override
  String get settingsApiKeyOptional => 'API key (optional)';

  @override
  String get modelProtocolResponses => 'Responses';

  @override
  String get modelProtocolChatCompletions => 'Chat Completions';

  @override
  String get modelConnectionWebSocket => 'WS';

  @override
  String get modelConnectionHttp => 'HTTP';

  @override
  String get settingsProtocolChatCompletionsHttp => 'Chat Completions (HTTP)';

  @override
  String get settingsProtocolResponsesHttp => 'Responses (HTTP)';

  @override
  String settingsAgentRouteUnavailable(String route) {
    return '$route (unavailable)';
  }

  @override
  String settingsPriceTierUnit(String currency) {
    return '$currency per 1M tokens';
  }

  @override
  String get threadStatusIdle => 'Idle';

  @override
  String get threadStatusCancelling => 'Stopping current execution';

  @override
  String get threadStatusClosed => 'Closed';

  @override
  String get toolStatusAwaitingApproval => 'Awaiting approval';

  @override
  String get toolStatusFailed => 'Failed';

  @override
  String get toolStatusDenied => 'Denied';

  @override
  String get toolStatusCancelled => 'Cancelled';

  @override
  String get toolStatusCancelling => 'Cancelling';

  @override
  String get settingsAccountCatalogUnavailable =>
      'Account catalog is unavailable.';

  @override
  String get settingsAccountTemplateUnavailable =>
      'Account template is unavailable.';

  @override
  String get settingsAccountMissingCredential => 'Missing credential';

  @override
  String get settingsSshStateDisconnected => 'Disconnected';

  @override
  String get settingsSshStateConnecting => 'Connecting';

  @override
  String get settingsSshStateWaitingForInput => 'Waiting for input';

  @override
  String get settingsSshStateReconnecting => 'Reconnecting';

  @override
  String get settingsSshStateFailed => 'Failed';

  @override
  String get settingsWorktreeStatePrepared => 'Prepared';

  @override
  String get settingsWorktreeStateActive => 'Active';

  @override
  String get settingsWorktreeStatePreserved => 'Preserved';

  @override
  String get settingsWorktreeStateCleanupRequested => 'Cleanup requested';

  @override
  String get settingsWorktreeStateCleaned => 'Cleaned';

  @override
  String get settingsWorktreeDirty => 'dirty';

  @override
  String get settingsWorktreeClean => 'No uncommitted changes';

  @override
  String get settingsWorktreeDirtyUnknown => 'Change status unknown';

  @override
  String get settingsWorktreeChangedFilesUnknown =>
      'Changed files are not yet known. Retry the inspection.';

  @override
  String get settingsWorktreeInspectionAvailable => 'Worktree verified';

  @override
  String get settingsWorktreeInspectionMissing => 'Worktree missing';

  @override
  String get settingsWorktreeInspectionIdentityMismatch =>
      'Worktree identity mismatch';

  @override
  String get settingsWorktreeInspectionUnavailable => 'Inspection unavailable';

  @override
  String get settingsWorktreeDetached =>
      'Verified detached HEAD (no current branch)';

  @override
  String get settingsWorktreeBranchUnknown => 'Current branch unknown';

  @override
  String get settingsWorktreeRetry => 'Retry inspection';

  @override
  String get startupPreparing => 'Preparing application…';

  @override
  String get startupStorage => 'Opening local data…';

  @override
  String get startupConfiguration => 'Loading configuration…';

  @override
  String get startupProjects => 'Loading projects…';

  @override
  String get startupResources => 'Preparing skill resources…';

  @override
  String get startupState => 'Loading workspace…';

  @override
  String get workspaceLoading => 'Loading conversation history…';

  @override
  String get recoveryChecking =>
      'Checking conversation history and workspaces…';

  @override
  String get recoveryCheckFailed =>
      'Conversation and workspace check did not complete';

  @override
  String get agentRoleRetired =>
      'This subagent role has been retired. History is read-only.';

  @override
  String get conversationActivityPreparing => 'Preparing';

  @override
  String get conversationActivityCompacting => 'Compacting';

  @override
  String get conversationActivityRunningTool => 'Running';

  @override
  String get conversationActivitySaveFailed => 'Save failed';

  @override
  String get conversationActivitySavePaused => 'Saving paused';

  @override
  String get conversationActivityStoragePressure => 'Storage pressure';

  @override
  String get conversationActivityResumeReady => 'Saved, waiting to resume';

  @override
  String get conversationActivityResumeRequired => 'Waiting for save recovery';

  @override
  String get conversationActivityStopping => 'Stopping';

  @override
  String get startupWaiting => 'Waiting for initialization steps…';

  @override
  String get startupClosing => 'Closing local data…';

  @override
  String get startupBackingUp => 'Backing up unrecoverable data…';

  @override
  String get startupResetting => 'Rebuilding initial settings…';

  @override
  String get startupServices => 'Starting services…';

  @override
  String get startupRecoveredNotice =>
      'Unrecoverable data was backed up and initial settings restored. Backup location:';

  @override
  String get settingsModelCatalogDefault => 'Bundled models';

  @override
  String get settingsModelCatalogCached => 'Last successful model list';

  @override
  String get settingsModelCatalogOnline => 'Models from this account';

  @override
  String get settingsModelCatalogChecked => 'Last checked';

  @override
  String get settingsModelCatalogFailed =>
      'Model sync failed. The current list is still available.';

  @override
  String get settingsModelCatalogCacheWarning =>
      'The saved model list could not be loaded. Showing bundled models.';

  @override
  String get settingsModelCatalogEmpty => 'This account has no models.';

  @override
  String get settingsModelCatalogRestartHint =>
      'Restart the app to sync again.';

  @override
  String get timelineActivityTitle => 'Thinking and tools';

  @override
  String get timelineContextCompacted => 'Context compacted';

  @override
  String timelineCompactionDetail(int before, int after) {
    return 'Before: $before; after: $after tokens';
  }

  @override
  String get timelineUserInputAnswered => 'You answered';

  @override
  String get timelineUserInputAwaiting => 'Awaiting your answer';

  @override
  String get timelineUserInputCancelled => 'Questions cancelled';

  @override
  String timelineUserInputQuestionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions',
      one: '1 question',
    );
    return '$_temp0';
  }

  @override
  String get timelineUserInputYourAnswer => 'Your answer';

  @override
  String get timelineUserInputNoAnswer => 'No answer provided';

  @override
  String get timelineUserInputSecretHidden => 'Sensitive answer hidden';

  @override
  String get settingsModelParametersUnknown => 'Model parameters unknown';

  @override
  String get settingsModelPriceUnknown => 'Price unknown';

  @override
  String modelTextFilterExcluded(String model, String reasons) {
    return '$model: excluded from text models ($reasons)';
  }

  @override
  String get modelTextInputUnsupported => 'Text input unsupported';

  @override
  String get modelTextOutputUnsupported => 'Text output unsupported';

  @override
  String get modelContextWindowUnknown => 'Context window unknown';

  @override
  String get modelTextFilterEmpty =>
      'No matching text models. Check model parameters in account settings.';

  @override
  String get modeEditorTitle => 'Work modes';

  @override
  String get modeEditorNewMode => 'New mode';

  @override
  String get modeEditorImportJson => 'Import JSON';

  @override
  String get modeEditorSearchHint => 'Find name or id';

  @override
  String get modeEditorBuiltInGroup => 'Built-in';

  @override
  String get modeEditorMyModesGroup => 'My modes';

  @override
  String get modeEditorNoMatches => 'No matching work modes.';

  @override
  String get modeEditorCatalogReadOnlyHint =>
      'Built-in modes are read-only. Duplicate one to customize stages.';

  @override
  String get modeEditorReadOnly => 'Read-only';

  @override
  String get modeEditorUnsaved => 'Unsaved';

  @override
  String get modeEditorUndo => 'Undo';

  @override
  String get modeEditorRedo => 'Redo';

  @override
  String get modeEditorReload => 'Reload';

  @override
  String get modeEditorDuplicate => 'Duplicate';

  @override
  String get modeEditorDeleteMode => 'Delete mode';

  @override
  String get modeEditorSave => 'Save';

  @override
  String get modeEditorTabFlow => 'Flow';

  @override
  String get modeEditorTabJson => 'JSON';

  @override
  String get modeEditorTabSettings => 'Settings';

  @override
  String get modeEditorTabPreview => 'Preview';

  @override
  String get modeEditorDraftUnsaved => 'Draft unsaved';

  @override
  String get modeEditorSelectOrCreate => 'Select or create a work mode.';

  @override
  String modeEditorOpenNotice(String id) {
    return 'Opened $id';
  }

  @override
  String modeEditorSaveValidationIssues(int count) {
    return 'Validation found $count issues before save.';
  }

  @override
  String modeEditorPreSaveValidationFailed(String error) {
    return 'Pre-save validation failed: $error';
  }

  @override
  String get modeEditorSaved => 'Mode saved. Changes apply from the next turn.';

  @override
  String get modeEditorSaveFailed => 'Save failed.';

  @override
  String get modeEditorReloaded => 'Mode definition reloaded.';

  @override
  String get modeEditorReloadFailed => 'Reload failed.';

  @override
  String get modeEditorDeleteFailed => 'Delete failed.';

  @override
  String get modeEditorDeleted => 'Mode deleted; thread history is kept.';

  @override
  String get modeEditorCopySuffix => 'copy';

  @override
  String get modeEditorCopyCreated =>
      'Copy created as a draft; save to publish it.';

  @override
  String get modeEditorDraftCreated => 'Draft created. Save after validation.';

  @override
  String modeEditorImportReadFailed(String error) {
    return 'Could not read mode JSON: $error';
  }

  @override
  String get modeEditorImportObjectRequired => 'Mode JSON must be an object.';

  @override
  String get modeEditorInvalidModeId => 'Mode id must look like mode.example.';

  @override
  String get modeEditorBuiltInCannotOverwrite =>
      'Built-in modes cannot be overwritten.';

  @override
  String get modeEditorImportedDraft =>
      'Configuration loaded as a draft; save to publish it.';

  @override
  String get modeEditorJsonCopied => 'Mode JSON copied.';

  @override
  String modeEditorSchemaReadFailed(String error) {
    return 'Could not read schema: $error';
  }

  @override
  String get modeEditorValidationPassed => 'Validation passed.';

  @override
  String modeEditorIssuesFound(int count) {
    return '$count issues found.';
  }

  @override
  String modeEditorValidationFailed(String error) {
    return 'Validation failed: $error';
  }

  @override
  String get modeEditorJsonApplied => 'JSON applied to the draft.';

  @override
  String get modeEditorJsonApplyFailed => 'JSON could not be applied.';

  @override
  String get modeEditorJsonApplyFix =>
      'JSON could not be applied; fix the syntax or fields.';

  @override
  String get modeEditorPreviewReasonDefault =>
      'Manually confirm stage completion and guard';

  @override
  String modeEditorPreviewFailed(String error) {
    return 'Preview failed: $error';
  }

  @override
  String modeEditorMaxStates(int count) {
    return 'At most $count states are supported.';
  }

  @override
  String get modeEditorNewFinalState => 'New final state';

  @override
  String get modeEditorNewStage => 'New work stage';

  @override
  String get modeEditorFinalStateAdded =>
      'Final state added. Add an incoming path.';

  @override
  String get modeEditorStageAdded =>
      'Stage added. Add incoming and outgoing transitions.';

  @override
  String get modeEditorContinueGuardPlaceholder =>
      'Continue when the guard is satisfied.';

  @override
  String get modeEditorTransitionAdded =>
      'Transition added. Complete its guard.';

  @override
  String get modeEditorNeedTwoStates =>
      'Add at least two states before creating a transition.';

  @override
  String get modeEditorLayoutReset =>
      'Layout reset. The workflow definition is unchanged.';

  @override
  String get modeEditorWorkflowEnabled => 'Workflow enabled.';

  @override
  String get modeEditorWorkflow => 'Workflow';

  @override
  String get modeEditorWorkflowGoalText =>
      'Complete the task in stages with a reviewable path.';

  @override
  String get modeEditorStart => 'Start';

  @override
  String get modeEditorStageInstructionsPlaceholder =>
      'Describe the work for this stage.';

  @override
  String get modeEditorStageCriterionPlaceholder =>
      'This stage goal is satisfied.';

  @override
  String get modeEditorDone => 'Done';

  @override
  String get modeEditorTransitionGuardPlaceholder =>
      'The result satisfies the goal.';

  @override
  String get modeEditorPromptDescription =>
      'Describe this mode responsibilities, sequence, and boundaries.';

  @override
  String get modeEditorPortIn => 'In';

  @override
  String get modeEditorPortOut => 'Out';

  @override
  String get modeEditorGuardRequiredShort => 'Guard required';

  @override
  String get modeEditorDuplicateTransition =>
      'A transition between those states already exists.';

  @override
  String get modeEditorInitialBadge => 'Start';

  @override
  String get modeEditorStageAction => 'Stage';

  @override
  String get modeEditorFinalLabel => 'Final';

  @override
  String get modeEditorTransitionAction => 'Transition';

  @override
  String get modeEditorValidate => 'Validate';

  @override
  String get modeEditorAutoLayout => 'Auto layout';

  @override
  String get modeEditorZoomOut => 'Zoom out';

  @override
  String get modeEditorZoomIn => 'Zoom in';

  @override
  String get modeEditorFitView => 'Fit view';

  @override
  String get modeEditorFlowInspector => 'Flow inspector';

  @override
  String get modeEditorNoWorkflow => 'This mode has no workflow';

  @override
  String get modeEditorNoWorkflowReadOnlyHint =>
      'Duplicate this mode to add stages and transitions.';

  @override
  String get modeEditorNoWorkflowEnableHint =>
      'Enabling a workflow adds a starting stage and a final state.';

  @override
  String get modeEditorEnableWorkflow => 'Enable workflow';

  @override
  String get modeEditorUnsavedTitle => 'Unsaved draft';

  @override
  String get modeEditorUnsavedBody =>
      'Save the current changes before continuing, or discard this draft.';

  @override
  String get modeEditorCancel => 'Cancel';

  @override
  String get modeEditorDiscard => 'Discard';

  @override
  String get modeEditorSaveAndContinue => 'Save and continue';

  @override
  String get modeEditorNewWorkMode => 'New work mode';

  @override
  String get modeEditorModeName => 'Mode name';

  @override
  String get modeEditorModeNameHint => 'For example: Research';

  @override
  String get modeEditorModeNameRequired => 'Enter a mode name.';

  @override
  String get modeEditorModeId => 'Mode id';

  @override
  String get modeEditorModeIdFormat =>
      'Use the form mode.example with lowercase letters, digits, - and _.';

  @override
  String get modeEditorModeIdExists => 'That mode id already exists.';

  @override
  String get modeEditorStartingPoint => 'Starting point';

  @override
  String get modeEditorMinimalWorkflow => 'Minimal workflow';

  @override
  String get modeEditorNoWorkflowTemplate => 'No workflow';

  @override
  String get modeEditorCreateMode => 'Create mode';

  @override
  String get modeEditorImportDialogTitle => 'Import mode JSON';

  @override
  String get modeEditorImportDialogBody =>
      'Paste mode JSON. Built-in modes stay read-only; an existing custom id opens as an unsaved draft.';

  @override
  String get modeEditorLoadAsDraft => 'Load as draft';

  @override
  String get modeEditorSchemaDialogTitle => 'Mode JSON schema';

  @override
  String get modeEditorClose => 'Close';

  @override
  String get modeEditorDeleteDialogTitle => 'Delete this work mode?';

  @override
  String modeEditorDeleteDialogBody(String displayName) {
    return 'Remove the \"$displayName\" definition. Thread history is kept.';
  }

  @override
  String get modeEditorConfirmDelete => 'Delete';

  @override
  String get modeEditorRemoveStateTitle => 'Delete this state?';

  @override
  String modeEditorRemoveStateBody(String title, int transitionCount) {
    return 'Delete \"$title\" and its $transitionCount related transitions. Undo can restore it.';
  }

  @override
  String get modeEditorDeleteState => 'Delete state';

  @override
  String get modeEditorRemoveWorkflowTitle => 'Remove workflow?';

  @override
  String get modeEditorRemoveWorkflowBody =>
      'The mode can still chat, but stage graph and workflow tools are removed. Undo is available before saving.';

  @override
  String get modeEditorRemoveWorkflow => 'Remove workflow';

  @override
  String get modeEditorStateIdInvalid =>
      'Use lowercase letters, digits, - and _ only.';

  @override
  String get modeEditorStateIdExists => 'That state id exists.';

  @override
  String get modeEditorRenameStateTitle => 'Rename state id';

  @override
  String get modeEditorStateId => 'State id';

  @override
  String get modeEditorApply => 'Apply';

  @override
  String get modeEditorAddTransition => 'Add transition';

  @override
  String get modeEditorSourceState => 'Source state';

  @override
  String get modeEditorChooseSource => 'Choose a source.';

  @override
  String get modeEditorTargetState => 'Target state';

  @override
  String get modeEditorChooseTarget => 'Choose a target.';

  @override
  String get modeEditorTransitionGuard => 'Transition guard';

  @override
  String get modeEditorTransitionGuardHint =>
      'For example: after the user confirms scope';

  @override
  String get modeEditorGuardRequiredField => 'Enter a guard.';

  @override
  String get modeEditorCollapse => 'Collapse';

  @override
  String get modeEditorDetailStage => 'Stage details';

  @override
  String get modeEditorDetailTransition => 'Transition details';

  @override
  String get modeEditorFocusAll => 'All';

  @override
  String get modeEditorFocusSelected => 'Focused';

  @override
  String modeEditorDimmedEdges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dimmed $count unrelated transitions',
    );
    return '$_temp0';
  }

  @override
  String get modeEditorViewStage => 'View stage';

  @override
  String get modeEditorNoWorkflowPeriod => 'This mode has no workflow.';

  @override
  String get modeEditorInspectorSelectHint =>
      'Select a stage or transition on the canvas to edit its fields.';

  @override
  String get modeEditorRenameId => 'Rename id';

  @override
  String get modeEditorStageTitle => 'Stage title';

  @override
  String get modeEditorStageKind => 'Stage kind';

  @override
  String get modeEditorAtomicStage => 'Atomic stage';

  @override
  String get modeEditorFinalState => 'Final state';

  @override
  String get modeEditorInitialStateSwitch => 'Initial state';

  @override
  String get modeEditorInitialStateLockedHint =>
      'The workflow always keeps one initial state; enable another stage instead.';

  @override
  String get modeEditorInitialStateHint => 'A run starts from this stage.';

  @override
  String get modeEditorStageInstructions => 'Stage instructions';

  @override
  String get modeEditorCompletionCriteriaTitle => 'Completion criteria';

  @override
  String get modeEditorCompletionCriteria =>
      'Completion criteria (one per line)';

  @override
  String get modeEditorAtomicCriteriaRequired =>
      'An atomic stage needs at least one completion criterion; Rust validates on save.';

  @override
  String get modeEditorOutgoingTransitions => 'Outgoing transitions';

  @override
  String get modeEditorAdd => 'Add';

  @override
  String get modeEditorNoOutgoing => 'No outgoing transitions.';

  @override
  String get modeEditorDeleteTransition => 'Delete transition';

  @override
  String get modeEditorStateTransition => 'State transition';

  @override
  String get modeEditorTransitionRuleHint =>
      'One transition per source/target pair; multiple successors, self loops and cycles are allowed.';

  @override
  String modeEditorValidationIssuesCount(int count) {
    return '$count issues';
  }

  @override
  String get modeEditorNotValidated => 'Not validated';

  @override
  String get modeEditorApplyJson => 'Apply JSON';

  @override
  String get modeEditorCopyJson => 'Copy JSON';

  @override
  String get modeEditorSchemaLabel => 'Schema';

  @override
  String get modeEditorReadOnlyCopyHint => 'Read-only: copy or validate';

  @override
  String get modeEditorJsonHint =>
      'Mode JSON keeps the six top-level fields plus editor layout.';

  @override
  String get modeEditorModeSettingsTitle => 'Mode settings';

  @override
  String get modeEditorModeSettingsSubtitle =>
      'Execution definition and editor layout are stored separately; layout never changes workflow identity.';

  @override
  String get modeEditorDisplayName => 'Display name';

  @override
  String get modeEditorDescription => 'Description';

  @override
  String get modeEditorOrder => 'Order';

  @override
  String get modeEditorRawPrompt => 'Raw prompt';

  @override
  String get modeEditorRawPromptHelper =>
      'This is the full mode prompt injected without GUI rewriting.';

  @override
  String get modeEditorWorkflowTitle => 'Workflow title';

  @override
  String get modeEditorWorkflowGoal => 'Workflow goal';

  @override
  String get modeEditorInitialStateLabel => 'Initial state';

  @override
  String modeEditorWorkflowSummary(int states, int transitions) {
    return '$states states · $transitions transitions';
  }

  @override
  String get modeEditorNoWorkflowToolHint =>
      'Without a workflow there is no stage graph or workflow tools.';

  @override
  String get modeEditorPreviewUnavailable =>
      'This mode has no workflow to preview.';

  @override
  String get modeEditorRunPreview => 'Run preview';

  @override
  String get modeEditorPreviewSubtitle =>
      'Bounded replay uses the production Rust state machine; it never rewrites the configured initial state.';

  @override
  String get modeEditorStartPreview => 'Start preview';

  @override
  String get modeEditorRestart => 'Restart';

  @override
  String get modeEditorTransitionReason => 'Transition reason';

  @override
  String get modeEditorTransitionReasonHint =>
      'Manually confirm stage completion and guard';

  @override
  String get modeEditorTransitionReasonHelper =>
      'Sent as the reason when advancing to a successor.';

  @override
  String modeEditorAllowedNextStates(int count) {
    return 'Allowed next states · $count';
  }

  @override
  String get modeEditorTerminalReached =>
      'Reached a final state. Restarting never rewrites the saved initial state.';

  @override
  String get modeEditorPreviewIntroText =>
      'Preview starts from the current JSON document. Each step follows one valid transition from the current state and keeps the path in this preview.';

  @override
  String get modeEditorPreviewAccepted => 'Preview accepted.';

  @override
  String get modeEditorPreviewRejected => 'Preview rejected.';

  @override
  String get modeEditorCurrentStage => 'Current stage';

  @override
  String get modeEditorPath => 'Path';

  @override
  String get modeEditorAdvance => 'Advance';

  @override
  String get modeEditorPreviewHistory => 'Preview history';

  @override
  String get modeDeletedUsingSnapshot => 'Deleted mode · using saved snapshot';

  @override
  String get modeDeletedChooseAnother =>
      'This mode was deleted. Choose another mode.';

  @override
  String get modeSnapshotBadge => 'Snapshot';

  @override
  String get modeDeletedBadge => 'Deleted';

  @override
  String get settingsAccountProtocol => 'Account protocol';

  @override
  String get statisticsGroupTotal => 'Group total';

  @override
  String get statisticsAllEfforts => 'All effort levels';

  @override
  String get statisticsEffortBreakdownTitle => 'Effort breakdown';

  @override
  String get accountProtocolOpenAi => 'OpenAI';

  @override
  String get accountProtocolDeepSeek => 'DeepSeek';

  @override
  String get accountProtocolZhipu => 'Zhipu';

  @override
  String get accountProtocolMiMo => 'MiMo';

  @override
  String get accountProtocolXai => 'xAI';

  @override
  String get accountProtocolCustom => 'Custom (OpenAI compatible)';

  @override
  String get timelineWaitToolsTitle => 'Waiting for tools';

  @override
  String get timelineWaitMessagesTitle =>
      'Waiting for a subagent or new message';

  @override
  String get timelineWaitTimerTitle => 'Timer';

  @override
  String get timelineWaitTimerElapsed => 'Timer elapsed';

  @override
  String get timelineWaitReady => 'A waited source is ready';

  @override
  String get timelineWaitMessagesReady => 'A new message arrived';

  @override
  String get timelineWaitTimedOut => 'Wait timed out';

  @override
  String get timelineWaitCancelled => 'Wait cancelled';

  @override
  String get timelineWaitFailed => 'Wait failed';

  @override
  String get timelineWaitInterrupted => 'Wait stopped';

  @override
  String timelineWaitTargetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get timelineWaitMessageSource => 'New messages';

  @override
  String timelineWaitMaxDuration(String duration) {
    return 'up to $duration';
  }

  @override
  String timelineWaitTimerDuration(String duration) {
    return '$duration';
  }

  @override
  String get timelineWaitMessagesMayWake =>
      'A new message can wake this wait early';

  @override
  String get timelineWaitAnyReadyRule =>
      'Returns when any selected task or a new message is ready';

  @override
  String get timelineWaitDiagnostics => 'Diagnostics';

  @override
  String get timelineWaitUnknownStatus => 'Unknown';

  @override
  String get timelineWaitStatusRunning => 'Running';

  @override
  String get timelineWaitStatusSucceeded => 'Succeeded';

  @override
  String get timelineWaitStatusFailed => 'Failed';

  @override
  String get timelineWaitStatusCancelled => 'Cancelled';

  @override
  String get timelineWaitStatusInterrupted => 'Stopped';

  @override
  String get conversationActivityWaitingTools => 'Waiting for tools';

  @override
  String get conversationActivityWaitingMessages =>
      'Waiting for a subagent or new message';

  @override
  String get conversationActivityWaitingTimer => 'Timer';

  @override
  String get settingsModelAutoCompactAdjusted =>
      'The effective limit was adjusted for context capacity and output reserve.';

  @override
  String get modelContextParametersInvalid => 'Inconsistent context parameters';

  @override
  String get modelInputBudgetExhausted =>
      'No input capacity after reserving output';

  @override
  String get statusCompactNow => 'Compact now';

  @override
  String get statusCompacting => 'Compacting…';

  @override
  String get statusCompactionFailed => 'Compaction failed. Try again.';

  @override
  String get settingsModelAutoCompactCustom => 'Custom';

  @override
  String get acpAccountPickerTitle => 'Add account';

  @override
  String get acpAccountPickerNativeGroup => 'Model API account';

  @override
  String get acpAccountPickerAcpGroup => 'Agent integration (ACP)';

  @override
  String get acpAccountNoApiKeyHint =>
      'No API key needed — the official program handles sign-in.';

  @override
  String get acpAccountSaveAndConnect => 'Save and connect';

  @override
  String acpAccountSavedConnectIncomplete(String reason) {
    return 'Account saved. Connection not finished: $reason';
  }

  @override
  String acpAccountSaveFailed(String reason) {
    return 'Could not save this integration: $reason';
  }

  @override
  String get acpAccountProviderChip => 'ACP';

  @override
  String get acpAccountScopeNotice =>
      'This version only configures the account and sign-in. ACP chat and model selection are not available yet.';

  @override
  String get acpAccountRemoveNotLogout =>
      'Removing an integration does not sign out the official program.';

  @override
  String get acpAccountRemoveFailed => 'Could not remove this integration.';

  @override
  String get acpAuthUnchecked => 'Connection not checked yet.';

  @override
  String get acpAuthChecking => 'Checking connection…';

  @override
  String get acpAuthRequiredTitle => 'Sign-in required';

  @override
  String get acpAuthRequiredBody =>
      'The official program reported the sign-in methods below.';

  @override
  String get acpAuthMethodLabel => 'Sign-in method';

  @override
  String get acpAuthLogin => 'Sign in';

  @override
  String get acpAuthAuthenticatingTitle => 'Waiting for sign-in';

  @override
  String get acpAuthAuthenticatingBody =>
      'Finish signing in inside the official sign-in window. This page keeps following the same attempt.';

  @override
  String get acpAuthVerifyingTitle => 'Verifying sign-in…';

  @override
  String get acpAuthVerifiedTitle => 'Connected';

  @override
  String acpAuthVerifiedAt(String time) {
    return 'Verified $time';
  }

  @override
  String get acpAuthRecheck => 'Check again';

  @override
  String get acpAuthCheck => 'Check connection';

  @override
  String get acpAuthCancel => 'Cancel sign-in';

  @override
  String get acpAuthCancelCheck => 'Cancel check';

  @override
  String get acpAuthCancelling => 'Cancelling…';

  @override
  String get acpAuthCancelled => 'Cancelled.';

  @override
  String get acpAuthFailedTitle => 'Connection failed';

  @override
  String get acpAuthTerminalOnly =>
      'The server only offers terminal sign-in, which this version does not support.';

  @override
  String get acpAuthUnsupportedOnly =>
      'The server only offers sign-in methods this version does not implement.';

  @override
  String get acpAuthClosingTitle => 'Finishing cleanup';

  @override
  String get acpAuthClosingBody =>
      'The protocol exchange is over; the process and its pipes are still being joined. No new attempt starts until this settles.';

  @override
  String get acpAuthServerUnknown => 'The server did not provide its identity.';

  @override
  String get acpAuthMethodSelectHint => 'Choose a sign-in method';

  @override
  String get acpAuthMethodRequired => 'Select a sign-in method to continue.';

  @override
  String get acpAuthRowClosing => 'Cleaning up';

  @override
  String get acpAccountInstallOpen => 'Open official guide';

  @override
  String get acpAuthNoMethods =>
      'The server did not offer a usable sign-in method.';

  @override
  String get acpAuthRetry => 'Retry';

  @override
  String get acpAuthEditConfig => 'Edit configuration';

  @override
  String get acpAuthDone => 'Done';

  @override
  String get acpAuthDiagnostics => 'Technical details';

  @override
  String acpAuthStageLabel(String stage) {
    return 'Stage: $stage';
  }

  @override
  String acpAuthCodeLabel(String code) {
    return 'Reason: $code';
  }

  @override
  String get acpAuthRowUnchecked => 'Not checked';

  @override
  String get acpAuthRowChecking => 'Checking';

  @override
  String get acpAuthRowRequired => 'Sign-in required';

  @override
  String get acpAuthRowAuthenticating => 'Signing in';

  @override
  String get acpAuthRowVerifying => 'Verifying';

  @override
  String get acpAuthRowVerified => 'Connected';

  @override
  String get acpAuthRowCancelling => 'Cancelling';

  @override
  String get acpAuthRowCancelled => 'Cancelled';

  @override
  String get acpAuthRowFailed => 'Connection failed';

  @override
  String get acpAccountDetailsSummary =>
      'Official ACP integration — no API key needed.';

  @override
  String get acpAccountConnectionInfoTitle => 'Connection details';

  @override
  String get acpAccountProviderLabel => 'Provider';

  @override
  String acpAuthFailureSummary(String reason, String stage) {
    return '$reason ($stage)';
  }

  @override
  String get acpFailureCodeStartup => 'Process start failed';

  @override
  String get acpFailureCodeMissingExecutable => 'Server program not found';

  @override
  String get acpFailureCodeIo => 'I/O error';

  @override
  String get acpFailureCodeUnsupportedVersion => 'Unsupported protocol version';

  @override
  String get acpFailureCodeUnsupportedMethod => 'Unsupported sign-in method';

  @override
  String get acpFailureCodeAuthentication => 'Sign-in failed';

  @override
  String get acpFailureCodeProbe => 'Connection check failed';

  @override
  String get acpFailureCodeProtocol => 'Protocol error';

  @override
  String get acpFailureCodeTransport => 'Transport error';

  @override
  String get acpFailureCodeTimeout => 'Timed out';

  @override
  String get acpFailureCodeResourceLimit => 'Resource limit reached';

  @override
  String get acpFailureCodeCancelled => 'Cancelled';

  @override
  String get acpFailureCodeStaleOperation => 'Operation was superseded';

  @override
  String get acpFailureCodeConfigChanged => 'Configuration changed';

  @override
  String get acpFailureCodeCleanup => 'Cleanup failed';

  @override
  String get acpFailureCodeInternal => 'Internal error';

  @override
  String get acpFailureStageProcess => 'during process start';

  @override
  String get acpFailureStageConfig => 'during configuration read';

  @override
  String get acpFailureStageInitialize => 'during initialize';

  @override
  String get acpFailureStageAuthenticate => 'during sign-in';

  @override
  String get acpFailureStageProbe => 'during connection check';

  @override
  String get acpFailureStageClose => 'during session close';

  @override
  String get acpFailureStageCleanup => 'during cleanup';

  @override
  String get studioFailureCodeNotInitialized => 'Not initialized';

  @override
  String get studioFailureCodeRuntimeStopped => 'Runtime stopped';

  @override
  String get studioFailureCodeInstanceBusy => 'Another operation is running';

  @override
  String get studioFailureCodeInvalidArgument => 'Invalid request';

  @override
  String get studioFailureCodeNotFound => 'Not found';

  @override
  String get studioFailureCodeBusy => 'Busy';

  @override
  String get studioFailureCodeConflict => 'Conflict';

  @override
  String get studioFailureCodeStaleRevision => 'Outdated revision';

  @override
  String get studioFailureCodePermissionDenied => 'Permission denied';

  @override
  String get studioFailureCodeCancelled => 'Cancelled';

  @override
  String get studioFailureCodeCancellationTooLate => 'Too late to cancel';

  @override
  String get studioFailureCodeOverloaded => 'Overloaded';

  @override
  String get studioFailureCodeUnavailable => 'Unavailable';

  @override
  String get studioFailureCodeProtocol => 'Protocol error';

  @override
  String get studioFailureCodeStorage => 'Storage error';

  @override
  String get studioFailureCodeUpdate => 'Update error';

  @override
  String get studioFailureCodeInternal => 'Internal error';

  @override
  String get acpAuthCancellingBody =>
      'Waiting for the sign-in window and its process to finish.';

  @override
  String get acpAuthCancelledBody =>
      'No attempt is running now. You can check or sign in again.';

  @override
  String acpAuthCommandFailure(String reason) {
    return 'The request was not accepted. $reason';
  }

  @override
  String get acpAuthCommandUnavailable => 'The request could not be completed.';

  @override
  String get botsOverviewHint =>
      'Bring your sessions to Feishu to search, collaborate, and share files.';

  @override
  String get botsPlatformFeishu => 'Feishu';

  @override
  String get botsModelTitle => 'Model and reasoning';

  @override
  String get botsModelHint =>
      'Applies to all chats with this bot from the next turn.';

  @override
  String get botsAccessTitle => 'People and group access';

  @override
  String get botsAccessHint =>
      'Only approved people and groups can use this bot.';

  @override
  String get botsConnectionSettings => 'Connection and settings';

  @override
  String get botsWorkspace => 'Dedicated workspace';

  @override
  String get botsPlatformTools => 'Feishu messages and test sending';

  @override
  String get botsManagedModel => 'Managed by bot settings';

  @override
  String get settingsSshNextPage => 'Next page';

  @override
  String acpInstallUnsupportedPlatform(String version) {
    return 'No official managed build of $version exists for this platform.';
  }

  @override
  String get acpFailureStagePrepare => 'Preparing the managed server';

  @override
  String get acpFailureCodePreparationRequired =>
      'The managed server is not prepared yet';

  @override
  String get acpFailureCodeInstallationInvalid =>
      'The prepared server is incomplete or damaged';

  @override
  String get acpFailureCodeUnsupportedPlatform =>
      'No official managed build for this platform';

  @override
  String get acpFailureCodeServerVersionMismatch =>
      'The server version is not the supported one';

  @override
  String get acpInstallFactVersion => 'Version';

  @override
  String get acpInstallFactTarget => 'Platform';

  @override
  String get acpInstallFactStage => 'Stage';

  @override
  String get acpInstallFactRetries => 'Automatic retries';

  @override
  String acpInstallRetryValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String acpInstallProgressDownloaded(String done, String total) {
    return '$done of $total downloaded';
  }

  @override
  String acpInstallProgressUnknown(String done) {
    return '$done downloaded, total unknown';
  }

  @override
  String acpInstallProgressVerified(String done, String total) {
    return '$done of $total verified';
  }

  @override
  String acpInstallProgressVerifiedUnknown(String done) {
    return '$done verified, total unknown';
  }

  @override
  String acpInstallProgressExtracted(String done, String total) {
    return '$done of $total extracted';
  }

  @override
  String acpInstallProgressExtractedUnknown(String done) {
    return '$done extracted, total unknown';
  }

  @override
  String acpInstallProgressProcessed(String done, String total) {
    return '$done of $total processed';
  }

  @override
  String acpInstallProgressProcessedUnknown(String done) {
    return '$done processed, total unknown';
  }

  @override
  String acpInstallProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String acpInstallSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String get acpInstallStageResolve => 'Reading the official manifest';

  @override
  String get acpInstallStageWaitForLock => 'Waiting for the install lock';

  @override
  String get acpInstallStageDownload => 'Downloading package';

  @override
  String get acpInstallStageVerify => 'Verifying package';

  @override
  String get acpInstallStageExtract => 'Extracting files';

  @override
  String get acpInstallStagePublish => 'Publishing installation';

  @override
  String get acpInstallStageClose => 'Closing download';

  @override
  String get acpInstallStart => 'Download and prepare';

  @override
  String get acpInstallRestart => 'Prepare again';

  @override
  String get acpInstallCancel => 'Cancel download';

  @override
  String get acpInstallCancelling => 'Cancelling…';

  @override
  String get acpInstallCancelSharedHint =>
      'Preparing is shared: cancelling stops this preparation and leaves saved accounts untouched.';

  @override
  String get acpInstallUsePrepared => 'Use prepared server';

  @override
  String acpInstallUsePreparedHint(String version, String target) {
    return 'An existing prepared $version ($target) can be claimed for this account.';
  }

  @override
  String get acpInstallReadyTitle => 'Server ready';

  @override
  String get acpInstallReadyBody =>
      'Preparing never saves an account or signs in.';

  @override
  String get acpInstallReusedBadge => 'Reused existing installation';

  @override
  String get acpInstallFailureRetry => 'Retry preparation';

  @override
  String get acpInstallTrustOfficialHttps =>
      'Trust boundary: official HTTPS source, no publisher checksum provided.';

  @override
  String get acpInstallPendingAdmission => 'Accepting the preparation request…';

  @override
  String acpInstallCommandFailed(String reason) {
    return 'The request was not accepted. $reason';
  }

  @override
  String acpInstallFailureSummary(String reason, String stage) {
    return '$reason ($stage)';
  }

  @override
  String get acpInstallFailureCodeUnsupportedPlatform =>
      'This platform is not supported';

  @override
  String get acpInstallFailureCodeSourceRejected => 'Source rejected';

  @override
  String get acpInstallFailureCodeNetwork => 'Network error';

  @override
  String get acpInstallFailureCodeTimeout => 'Timed out';

  @override
  String get acpInstallFailureCodeTooLarge => 'Package exceeds the limit';

  @override
  String get acpInstallFailureCodeChecksumMismatch => 'Checksum mismatch';

  @override
  String get acpInstallFailureCodeInvalidArchive => 'Invalid package';

  @override
  String get acpInstallFailureCodeMissingExecutable =>
      'Server program missing in package';

  @override
  String get acpInstallFailureCodeCacheCorrupt =>
      'Existing installation is corrupt';

  @override
  String get acpInstallFailureCodeIo => 'File system error';

  @override
  String get acpInstallFailureCodeBusy => 'Another preparation is running';

  @override
  String get acpInstallFailureCodeStaleOperation =>
      'Preparation was superseded';

  @override
  String get acpInstallFailureCodeCancelled => 'Cancelled';

  @override
  String get acpInstallFailureCodeResourceClose => 'Cleanup failed';

  @override
  String get acpAccountTermsOpen => 'Terms of service';

  @override
  String get acpAccountTermsTitle => 'Official terms';

  @override
  String get delegationSettingsTitle => 'Subagent delegation';

  @override
  String get delegationDefaultMode => 'Default delegation mode';

  @override
  String get delegationDefaultPreference => 'Default automatic preference';

  @override
  String get delegationModeLabel => 'Delegation mode';

  @override
  String get delegationPreferenceLabel => 'Automatic preference';

  @override
  String get delegationProfile => 'Fixed Profile';

  @override
  String get delegationAutomatic => 'Automatic model selection';

  @override
  String get delegationEconomy => 'Economy';

  @override
  String get delegationBalanced => 'Balanced';

  @override
  String get delegationFast => 'Fast';

  @override
  String get delegationOnlyAutomatic =>
      'Only applies to automatic model selection. The value is kept in fixed Profile mode.';

  @override
  String get delegationEconomyHint =>
      'Prefer lower expected total cost while meeting task capability and quality needs. Unknown prices are not free.';

  @override
  String get delegationBalancedHint =>
      'Balance task fit, recent evaluations, cost, and completion time without lowering quality requirements.';

  @override
  String get delegationFastHint =>
      'Prefer shorter overall completion time while meeting capability, quality, and review requirements.';

  @override
  String get delegationFollowDefault => 'Follow default';

  @override
  String get delegationSessionSettings => 'Session settings';

  @override
  String get delegationInherited =>
      'Following the latest default until submission';

  @override
  String get delegationOverride => 'Only this draft';

  @override
  String get delegationFrozen => 'Saved at session creation · read-only';

  @override
  String get delegationModelNotRecorded => 'Model not recorded';

  @override
  String get settingsModelEnabled => 'Enabled';

  @override
  String get settingsModelEnabledHint =>
      'Applies to all new model selections and subagent delegation. Running calls are not interrupted. Bundled models absent from the online list can be enabled manually; the server determines actual availability.';

  @override
  String get settingsModelDisabled => 'Disabled for new selections';

  @override
  String get settingsModelSaving => 'Saving…';

  @override
  String get settingsModelSaveFailed =>
      'Not saved. The switch shows the last confirmed value. Toggle again to retry.';

  @override
  String get settingsBillingKind => 'Billing category';

  @override
  String get settingsBillingAutomatic => 'Automatic · no explicit override';

  @override
  String get settingsBillingMetered => 'Metered';

  @override
  String get settingsBillingSubscription => 'Subscription / plan';

  @override
  String get settingsBillingUnknown => 'Unknown';

  @override
  String get settingsBillingEffective => 'Effective category';

  @override
  String get settingsBillingOverride => 'Explicit override';

  @override
  String get settingsBillingHint =>
      'No charge applies only to future calls; other categories estimate costs from available prices and usage. Subscription does not confirm an active plan, remaining quota or zero cost. Model reference prices are preserved.';

  @override
  String get settingsModelDetails => 'Model details';

  @override
  String get modelDetailLoading => 'Loading model details…';

  @override
  String get modelDetailUnknown => 'Unknown / not verified';

  @override
  String get modelDetailAvailable => 'Locally eligible for new selections';

  @override
  String get modelDetailAvailabilityHint =>
      'Local eligibility does not guarantee provider health, subscription validity, or remaining quota.';

  @override
  String get modelDetailSummary => 'Description and task fit';

  @override
  String get modelDetailLimitations => 'Limitations';

  @override
  String get modelDetailCapabilities => 'Capabilities and limits';

  @override
  String get modelDetailEfforts => 'Allowed reasoning efforts';

  @override
  String get modelDetailNoEffort => 'No reasoning effort parameter';

  @override
  String get modelDetailPricing => 'Prices per million tokens';

  @override
  String get modelDetailPriceInput => 'Input';

  @override
  String get modelDetailPriceOutput => 'Output';

  @override
  String get modelDetailPriceCacheRead => 'Cache read';

  @override
  String get modelDetailPriceCacheWrite => 'Cache write';

  @override
  String get modelDetailSources => 'Sources and verification';

  @override
  String get modelDetailOfficial => 'Official documentation';

  @override
  String get modelDetailBenchmark => 'Independent benchmark';

  @override
  String get modelDetailCommunity => 'Community feedback';

  @override
  String get modelDetailVerifiedAt => 'Verified';

  @override
  String get modelDetailMeasurement => 'Measurement conditions';

  @override
  String get modelDetailPerformance => 'Local call performance';

  @override
  String get modelDetailThroughput => 'Tokens/s (including first-token wait)';

  @override
  String get modelDetailTtft => 'Average time to first token (ms)';

  @override
  String get modelDetailSamples => 'Call samples';

  @override
  String get modelDetailTtftSamples => 'First-token samples';

  @override
  String get modelDetailUpdatedAt => 'Updated';

  @override
  String get modelDetailPerformanceHint =>
      'Observed locally; account, network, effort, and task affect these samples. This is not a provider guarantee or a task evaluation.';

  @override
  String get modelDetailEvaluations =>
      'Recent final task evaluations (up to 10)';

  @override
  String get modelDetailEvaluationsEmpty =>
      'No final task evaluations for this exact account and model yet.';

  @override
  String get modelDetailEvaluationsHint =>
      'Each child has one effective final evaluation. Small samples are not statistically conclusive; unrateable outcomes are not low scores.';

  @override
  String get modelDetailEvaluationPassed => 'Passed';

  @override
  String get modelDetailEvaluationFailed => 'Failed';

  @override
  String get modelDetailEvaluationNotRated => 'Unable to assess';

  @override
  String get modelDetailQuality => 'Quality';

  @override
  String get modelDetailInstructionFollowing => 'Instruction following';

  @override
  String get modelDetailTaskReasoning => 'Reasoning';

  @override
  String get modelDetailTaskCoding => 'Coding';

  @override
  String get modelDetailTaskTooling => 'Tool use and orchestration';

  @override
  String get modelDetailTaskLongContext => 'Long context';

  @override
  String get modelDetailTaskMultimodal => 'Multimodal';

  @override
  String get modelDetailTaskGeneral => 'General';

  @override
  String get modelDetailRetry => 'Reload details';

  @override
  String get modelDetailClose => 'Close';

  @override
  String get modelDetailStale =>
      'This model\'s canonical identity changed. Reload its details.';

  @override
  String get composerContinue => 'Continue';

  @override
  String get composerContinueTooltip =>
      'Continue the interrupted work without new input';

  @override
  String get composerStopping => 'Stopping';

  @override
  String get composerContinuing => 'Continuing';

  @override
  String get composerContinueReasonUserStop => 'Stopped by the user';

  @override
  String get composerContinueReasonHostShutdown =>
      'The app exited while this session was still running';

  @override
  String get composerContinueReasonProcessInterrupted =>
      'The process was interrupted';

  @override
  String get composerContinueReasonStepLimit => 'The step budget ran out';

  @override
  String get composerContinueReasonExecutionFailed => 'Execution failed';

  @override
  String get composerContinueReasonUnknown => 'Execution was interrupted';

  @override
  String get composerBlockedStorage =>
      'Saving has not finished yet, so continuing is unavailable.';

  @override
  String get composerBlockedModel =>
      'The current model is unavailable, so continuing is unavailable.';

  @override
  String get composerBlockedWorkspace =>
      'The session workspace is unavailable, so continuing is unavailable.';

  @override
  String get composerBlockedArchived =>
      'This session is archived, so continuing is unavailable.';

  @override
  String get composerBlockerUnknown =>
      'The last action could not be confirmed. Check the session state before retrying.';

  @override
  String get composerFailureChildRequiresParentScheduling =>
      'A child agent is scheduled by the main agent.';

  @override
  String get composerFailureContinuationUnavailable =>
      'There is no interrupted work left to continue.';

  @override
  String get composerFailureContinuationClaimed =>
      'The continuation was already accepted and is being prepared.';

  @override
  String get composerFailureStaleContinuation =>
      'The observed continuation point is out of date.';

  @override
  String get composerFailureStaleExecution =>
      'The observed execution already ended or was replaced.';

  @override
  String get composerFailureExecutionInProgress =>
      'The session is still executing or settling.';

  @override
  String get composerFailureInteractionNotHosted =>
      'This interaction is decided in the main session.';

  @override
  String get composerFailureStaleInteraction =>
      'This interaction was already updated. Open it again.';

  @override
  String agentStopSemantics(String name) {
    return 'Stop member $name';
  }

  @override
  String get agentStopping => 'Stopping';

  @override
  String get agentStopWaitingScheduling =>
      'Stopped, waiting for the main agent to schedule';

  @override
  String agentStopFailed(String message) {
    return 'Stop was not accepted: $message';
  }

  @override
  String get composerAgentReadOnlyTitle => 'Child session (read-only)';

  @override
  String get composerAgentReadOnlyWaiting =>
      'Waiting for the main agent to schedule this member.';

  @override
  String get composerAgentReadOnlyScope =>
      'History, progress, model and workspace are shown for review only. Ask the main agent when this member should continue.';

  @override
  String get composerAgentReadOnlyPending =>
      'A pending question or permission request is decided in the main session.';

  @override
  String childInteractionFrom(String agent) {
    return 'From $agent';
  }

  @override
  String childInteractionRevision(int revision) {
    return 'Revision $revision';
  }

  @override
  String get childInteractionAnswerSaved =>
      'The answer is saved. The main agent decides whether this member continues.';

  @override
  String get childInteractionApprovalResolved =>
      'The original permission wait is decided. The original call may continue when it was approved, and is not executed when it was denied.';

  @override
  String childInteractionDecideFailed(String message) {
    return 'The decision was not accepted: $message';
  }

  @override
  String childInteractionLoadFailed(String message) {
    return 'Child interactions could not be read: $message';
  }

  @override
  String get childInteractionRetry => 'Reload';

  @override
  String get childInteractionDecisionAccepted =>
      'The decision was accepted. Waiting for the session to confirm it.';

  @override
  String recoveryDiagnostic(
    String id,
    String owner,
    String impact,
    String detail,
    String actions,
  ) {
    return 'Recovery issue $id\n$owner · $impact\n$detail\nAvailable recovery actions: $actions';
  }

  @override
  String get recoveryOwnerApplication => 'Application';

  @override
  String recoveryOwnerProject(String projectId) {
    return 'Project $projectId';
  }

  @override
  String recoveryOwnerThread(String threadId, String projectId) {
    return 'Session $threadId · project $projectId';
  }

  @override
  String get accountsAuthApiKey => 'API key';

  @override
  String get accountsAuthChatGpt => 'ChatGPT subscription';

  @override
  String get accountsChatGptConnectionHint =>
      'Connect ChatGPT through OpenAI\'s official browser sign-in.';

  @override
  String get accountsChatGptLogin => 'Sign in with ChatGPT';

  @override
  String get accountsChatGptNotConnected => 'ChatGPT is not connected.';

  @override
  String get accountsChatGptPreparing => 'Preparing secure sign-in…';

  @override
  String get accountsChatGptWaitingBrowser =>
      'Complete OpenAI authorization in your browser.';

  @override
  String get accountsChatGptChecking => 'Verifying the ChatGPT connection…';

  @override
  String get accountsChatGptConnected =>
      'ChatGPT is connected and ready to save.';

  @override
  String get accountsChatGptPermissionMissing =>
      'The account is verified, but direct API access was not granted. Sign in again and approve access.';

  @override
  String get accountsChatGptCancelled => 'Sign-in was cancelled.';

  @override
  String get accountsChatGptAuthorizationDenied =>
      'OpenAI did not authorize this connection. Retry and approve access.';

  @override
  String get accountsChatGptExpired => 'The sign-in link expired. Start again.';

  @override
  String get accountsChatGptFailed =>
      'ChatGPT sign-in could not be completed. Retry.';

  @override
  String get accountsChatGptOpenBrowser => 'Reopen browser';

  @override
  String get accountsChatGptCancel => 'Cancel sign-in';

  @override
  String get accountsChatGptUsage => 'View ChatGPT usage';

  @override
  String get accountsChatGptApiKeyRequired =>
      'Enter a new API key when switching to API key authentication.';

  @override
  String get accountsChatGptOpenLinkFailed =>
      'Could not open the OpenAI sign-in page. Try opening it again.';

  @override
  String get accountsChatGptOpenUsageFailed =>
      'Could not open ChatGPT usage settings.';

  @override
  String get recoveryUnknownOwner => 'Not recorded';

  @override
  String get recoveryImpactAdvisory =>
      'Attention required; access and execution remain available';

  @override
  String get recoveryImpactExecutionBlocked =>
      'Execution is blocked; safe history remains readable';

  @override
  String get recoveryImpactAccessBlocked => 'Access and execution are blocked';

  @override
  String get recoveryNoAvailableActions => 'None currently available';
}
