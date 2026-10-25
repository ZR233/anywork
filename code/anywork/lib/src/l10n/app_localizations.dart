import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @promptAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get promptAccepted;

  /// No description provided for @composerSendAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Send and continue'**
  String get composerSendAndContinue;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'anywork'**
  String get appTitle;

  /// No description provided for @trayShowWindow.
  ///
  /// In en, this message translates to:
  /// **'Show main window'**
  String get trayShowWindow;

  /// No description provided for @trayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExit;

  /// No description provided for @sidebarProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get sidebarProjects;

  /// No description provided for @sidebarSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sidebarSessions;

  /// No description provided for @sidebarLoadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more sessions…'**
  String get sidebarLoadingMore;

  /// No description provided for @sidebarLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load more sessions'**
  String get sidebarLoadError;

  /// No description provided for @shutdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Shutting down safely'**
  String get shutdownTitle;

  /// No description provided for @shutdownUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Installing update {version}'**
  String shutdownUpdateTitle(String version);

  /// No description provided for @shutdownUpdateSaving.
  ///
  /// In en, this message translates to:
  /// **'Stopping chats and saving data…'**
  String get shutdownUpdateSaving;

  /// No description provided for @shutdownUpdateRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Installation progress will appear after saving. The app will reopen automatically.'**
  String get shutdownUpdateRestartHint;

  /// No description provided for @shutdownUpdateExitHint.
  ///
  /// In en, this message translates to:
  /// **'Installation progress will appear after saving. The app will stay closed.'**
  String get shutdownUpdateExitHint;

  /// No description provided for @shutdownFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finishing up'**
  String get shutdownFinalizing;

  /// No description provided for @shutdownFinalizingHint.
  ///
  /// In en, this message translates to:
  /// **'Necessary diagnostics were recorded; the app will exit automatically.'**
  String get shutdownFinalizingHint;

  /// No description provided for @shutdownPhaseStoppingSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Stopping subscriptions'**
  String get shutdownPhaseStoppingSubscriptions;

  /// No description provided for @shutdownPhaseCancellingTurns.
  ///
  /// In en, this message translates to:
  /// **'Stopping active turns'**
  String get shutdownPhaseCancellingTurns;

  /// No description provided for @shutdownPhaseFlushingPersistence.
  ///
  /// In en, this message translates to:
  /// **'Saving sessions'**
  String get shutdownPhaseFlushingPersistence;

  /// No description provided for @shutdownPhaseStoppingAgents.
  ///
  /// In en, this message translates to:
  /// **'Stopping collaborative agents'**
  String get shutdownPhaseStoppingAgents;

  /// No description provided for @shutdownPhaseStoppingMcp.
  ///
  /// In en, this message translates to:
  /// **'Stopping MCP servers'**
  String get shutdownPhaseStoppingMcp;

  /// No description provided for @shutdownPhaseStoppingLsp.
  ///
  /// In en, this message translates to:
  /// **'Stopping language servers'**
  String get shutdownPhaseStoppingLsp;

  /// No description provided for @shutdownPhaseStopped.
  ///
  /// In en, this message translates to:
  /// **'Shutdown complete'**
  String get shutdownPhaseStopped;

  /// No description provided for @shutdownPendingCommits.
  ///
  /// In en, this message translates to:
  /// **'{count} commits pending'**
  String shutdownPendingCommits(int count);

  /// No description provided for @sidebarCloseProject.
  ///
  /// In en, this message translates to:
  /// **'Close project'**
  String get sidebarCloseProject;

  /// No description provided for @sidebarArchiveSession.
  ///
  /// In en, this message translates to:
  /// **'Archive session'**
  String get sidebarArchiveSession;

  /// No description provided for @sidebarArchiveSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not archive this session.'**
  String get sidebarArchiveSessionFailed;

  /// No description provided for @sidebarArchiveSessionBusy.
  ///
  /// In en, this message translates to:
  /// **'Could not archive this session. It may still be running.'**
  String get sidebarArchiveSessionBusy;

  /// No description provided for @sidebarArchiveSessionFailedReason.
  ///
  /// In en, this message translates to:
  /// **'Could not archive this session: {reason} (diagnostic ID: {correlationId})'**
  String sidebarArchiveSessionFailedReason(String reason, String correlationId);

  /// No description provided for @sidebarArchiveSessionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive session'**
  String get sidebarArchiveSessionConfirmTitle;

  /// No description provided for @sidebarArchiveSessionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Archiving ends any running work, deletes this session tree\'s worktree along with any uncommitted or unmerged content, then moves the session out of the list. Continue?'**
  String get sidebarArchiveSessionConfirmBody;

  /// No description provided for @sidebarArchiveSessionConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get sidebarArchiveSessionConfirmAction;

  /// No description provided for @sidebarRenameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get sidebarRenameSession;

  /// No description provided for @sidebarRenameSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get sidebarRenameSessionTitle;

  /// No description provided for @sidebarRenameSessionInput.
  ///
  /// In en, this message translates to:
  /// **'Session title'**
  String get sidebarRenameSessionInput;

  /// No description provided for @sidebarRenameSessionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a session title.'**
  String get sidebarRenameSessionEmpty;

  /// No description provided for @sidebarRenameSessionTooLong.
  ///
  /// In en, this message translates to:
  /// **'Session titles can be at most 80 characters.'**
  String get sidebarRenameSessionTooLong;

  /// No description provided for @sidebarRenameSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not rename this session.'**
  String get sidebarRenameSessionFailed;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @sidebarNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get sidebarNewSession;

  /// No description provided for @sidebarSessionWorktree.
  ///
  /// In en, this message translates to:
  /// **'Session worktree'**
  String get sidebarSessionWorktree;

  /// No description provided for @sidebarOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get sidebarOpenProject;

  /// No description provided for @sidebarSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get sidebarSettings;

  /// No description provided for @runtimeFatalTitle.
  ///
  /// In en, this message translates to:
  /// **'anywork could not start'**
  String get runtimeFatalTitle;

  /// No description provided for @runtimeFatalRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get runtimeFatalRetry;

  /// No description provided for @persistenceDegraded.
  ///
  /// In en, this message translates to:
  /// **'Saving is temporarily unavailable. {count} in-memory update(s) are waiting; you can continue the conversation.'**
  String persistenceDegraded(int count);

  /// No description provided for @persistenceRecovering.
  ///
  /// In en, this message translates to:
  /// **'Saving has recovered and is flushing {count} pending update(s). You can continue the conversation.'**
  String persistenceRecovering(int count);

  /// No description provided for @persistenceBlocked.
  ///
  /// In en, this message translates to:
  /// **'Saving is blocked with {count} pending update(s) and needs attention.'**
  String persistenceBlocked(int count);

  /// No description provided for @persistenceExecutionPaused.
  ///
  /// In en, this message translates to:
  /// **'Saving failed; execution is paused.'**
  String get persistenceExecutionPaused;

  /// No description provided for @persistenceSavingBackpressure.
  ///
  /// In en, this message translates to:
  /// **'Storage is under pressure; saving is waiting.'**
  String get persistenceSavingBackpressure;

  /// No description provided for @persistenceNewWorkPaused.
  ///
  /// In en, this message translates to:
  /// **'Saving failed; new work is paused while in-flight work winds down.'**
  String get persistenceNewWorkPaused;

  /// No description provided for @persistenceResumeReadyOtherSession.
  ///
  /// In en, this message translates to:
  /// **'Another session “{session}” is saved and waiting to resume.'**
  String persistenceResumeReadyOtherSession(String session);

  /// No description provided for @persistenceExecutionPausedOtherSession.
  ///
  /// In en, this message translates to:
  /// **'Another session “{session}” failed to save; its execution is paused.'**
  String persistenceExecutionPausedOtherSession(String session);

  /// No description provided for @persistenceNewWorkPausedOtherSession.
  ///
  /// In en, this message translates to:
  /// **'Another session “{session}” failed to save; its new work is paused while in-flight work winds down.'**
  String persistenceNewWorkPausedOtherSession(String session);

  /// No description provided for @persistenceRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry saving'**
  String get persistenceRetry;

  /// No description provided for @threadUnopenedTitle.
  ///
  /// In en, this message translates to:
  /// **'Session not opened yet'**
  String get threadUnopenedTitle;

  /// No description provided for @threadUnopenedBody.
  ///
  /// In en, this message translates to:
  /// **'This session is only selected. Open it to load its current state and history; nothing resumes until you send a message.'**
  String get threadUnopenedBody;

  /// No description provided for @threadOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open session'**
  String get threadOpenAction;

  /// No description provided for @timelineItemBodyLoad.
  ///
  /// In en, this message translates to:
  /// **'Load full content'**
  String get timelineItemBodyLoad;

  /// No description provided for @timelineItemBodyLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading full content…'**
  String get timelineItemBodyLoading;

  /// No description provided for @timelineItemBodyPending.
  ///
  /// In en, this message translates to:
  /// **'Full content is not durable yet; retry shortly.'**
  String get timelineItemBodyPending;

  /// No description provided for @timelineItemBodyRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get timelineItemBodyRetry;

  /// No description provided for @timelineItemBodyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Full content is unavailable from this data source.'**
  String get timelineItemBodyUnavailable;

  /// No description provided for @persistenceQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Persistence diagnostics'**
  String get persistenceQueueTitle;

  /// No description provided for @persistenceQueueUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Queue pressure is unavailable from this data source.'**
  String get persistenceQueueUnavailable;

  /// No description provided for @persistenceQueuePending.
  ///
  /// In en, this message translates to:
  /// **'Queued: {operations} operation(s), {bytes} byte(s)'**
  String persistenceQueuePending(int operations, int bytes);

  /// No description provided for @persistenceQueueInFlight.
  ///
  /// In en, this message translates to:
  /// **'Writing: {bytes} byte(s)'**
  String persistenceQueueInFlight(int bytes);

  /// No description provided for @persistenceQueueOldestAge.
  ///
  /// In en, this message translates to:
  /// **'Oldest unsaved: {millis} ms'**
  String persistenceQueueOldestAge(int millis);

  /// No description provided for @persistenceQueuePressurePaused.
  ///
  /// In en, this message translates to:
  /// **'New inference admission is paused under storage pressure.'**
  String get persistenceQueuePressurePaused;

  /// No description provided for @persistenceQueueError.
  ///
  /// In en, this message translates to:
  /// **'Last error: {message}'**
  String persistenceQueueError(String message);

  /// No description provided for @persistenceQueueRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh diagnostics'**
  String get persistenceQueueRefresh;

  /// No description provided for @persistenceQueueShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show diagnostics'**
  String get persistenceQueueShowDetails;

  /// No description provided for @persistenceQueueHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide diagnostics'**
  String get persistenceQueueHideDetails;

  /// No description provided for @persistenceHistoryPaused.
  ///
  /// In en, this message translates to:
  /// **'Session history saving is paused'**
  String get persistenceHistoryPaused;

  /// No description provided for @persistenceHistoryQueueFull.
  ///
  /// In en, this message translates to:
  /// **'History queue full'**
  String get persistenceHistoryQueueFull;

  /// No description provided for @persistenceHistoryWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'History save failed'**
  String get persistenceHistoryWriteFailed;

  /// No description provided for @persistenceHistoryRetrySave.
  ///
  /// In en, this message translates to:
  /// **'Retry saving'**
  String get persistenceHistoryRetrySave;

  /// No description provided for @persistenceHistoryResume.
  ///
  /// In en, this message translates to:
  /// **'Resume execution'**
  String get persistenceHistoryResume;

  /// No description provided for @persistenceHistoryResumeHint.
  ///
  /// In en, this message translates to:
  /// **'Retry saving to enable resume'**
  String get persistenceHistoryResumeHint;

  /// No description provided for @persistenceStatisticsGap.
  ///
  /// In en, this message translates to:
  /// **'Call statistics are incomplete; missing usage is unknown, not zero.'**
  String get persistenceStatisticsGap;

  /// No description provided for @recoveryGlobalWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} recovery issue(s) need attention'**
  String recoveryGlobalWarning(int count);

  /// No description provided for @recoveryArchiveNotice.
  ///
  /// In en, this message translates to:
  /// **'Migration could not continue. Previous data was archived and anywork started with default settings. Archive:'**
  String get recoveryArchiveNotice;

  /// No description provided for @recoveryArchiveDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss archive notice'**
  String get recoveryArchiveDismiss;

  /// No description provided for @sidebarNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get sidebarNew;

  /// No description provided for @sidebarOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get sidebarOpen;

  /// No description provided for @shellNoSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get shellNoSession;

  /// No description provided for @startPageWelcome.
  ///
  /// In en, this message translates to:
  /// **'What can I help you build?'**
  String get startPageWelcome;

  /// No description provided for @preparationTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing your session'**
  String get preparationTitle;

  /// No description provided for @preparationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your request will start once the workspace is ready.'**
  String get preparationSubtitle;

  /// No description provided for @preparationFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment setup incomplete'**
  String get preparationFailedTitle;

  /// No description provided for @preparationRetainedBody.
  ///
  /// In en, this message translates to:
  /// **'Your prompt and attachments are saved. Adjust the settings and send again.'**
  String get preparationRetainedBody;

  /// No description provided for @preparationUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Creation outcome unconfirmed'**
  String get preparationUnknownTitle;

  /// No description provided for @preparationUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'The connection ended before session creation was confirmed. Do not send again.'**
  String get preparationUnknownBody;

  /// No description provided for @preparationCheckProject.
  ///
  /// In en, this message translates to:
  /// **'Check project'**
  String get preparationCheckProject;

  /// No description provided for @preparationWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Prepare workspace'**
  String get preparationWorkspace;

  /// No description provided for @preparationInitializeSession.
  ///
  /// In en, this message translates to:
  /// **'Initialize session'**
  String get preparationInitializeSession;

  /// No description provided for @preparationSubmitPrompt.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get preparationSubmitPrompt;

  /// No description provided for @preparationWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting to begin…'**
  String get preparationWaiting;

  /// No description provided for @preparationCheckingProject.
  ///
  /// In en, this message translates to:
  /// **'Checking the project and session configuration…'**
  String get preparationCheckingProject;

  /// No description provided for @preparationPreparingWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Preparing the session workspace…'**
  String get preparationPreparingWorkspace;

  /// No description provided for @preparationResolvingRepository.
  ///
  /// In en, this message translates to:
  /// **'Checking the Git repository and base commit…'**
  String get preparationResolvingRepository;

  /// No description provided for @preparationCreatingWorktree.
  ///
  /// In en, this message translates to:
  /// **'Creating the worktree and checking out files…'**
  String get preparationCreatingWorktree;

  /// No description provided for @preparationInitializingSession.
  ///
  /// In en, this message translates to:
  /// **'Initializing the session environment…'**
  String get preparationInitializingSession;

  /// No description provided for @preparationSubmittingPrompt.
  ///
  /// In en, this message translates to:
  /// **'Submitting your first request…'**
  String get preparationSubmittingPrompt;

  /// No description provided for @preparationMoreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get preparationMoreDetails;

  /// No description provided for @preparationProjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get preparationProjectLabel;

  /// No description provided for @preparationRemoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Remote host'**
  String get preparationRemoteLabel;

  /// No description provided for @preparationPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace path'**
  String get preparationPathLabel;

  /// No description provided for @preparationBranchLabel.
  ///
  /// In en, this message translates to:
  /// **'Worktree branch'**
  String get preparationBranchLabel;

  /// No description provided for @preparationDiagnosticLabel.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic ID'**
  String get preparationDiagnosticLabel;

  /// No description provided for @preparationStepComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get preparationStepComplete;

  /// No description provided for @preparationStepPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get preparationStepPending;

  /// No description provided for @preparationStepRunning.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get preparationStepRunning;

  /// No description provided for @preparationStepFailed.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get preparationStepFailed;

  /// No description provided for @startPageProject.
  ///
  /// In en, this message translates to:
  /// **'Working in {project}'**
  String startPageProject(String project);

  /// No description provided for @startPageOpenProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Open a project to get started'**
  String get startPageOpenProjectTitle;

  /// No description provided for @startPageOpenProjectBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a project from the sidebar before sending your first message.'**
  String get startPageOpenProjectBody;

  /// No description provided for @shellSessionUpdated.
  ///
  /// In en, this message translates to:
  /// **'{mode} · updated {time}'**
  String shellSessionUpdated(String mode, String time);

  /// No description provided for @settingsBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBack;

  /// No description provided for @settingsBackToChat.
  ///
  /// In en, this message translates to:
  /// **'Back to chat'**
  String get settingsBackToChat;

  /// No description provided for @settingsWorkspaceGroup.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get settingsWorkspaceGroup;

  /// No description provided for @settingsSystemGroup.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystemGroup;

  /// No description provided for @settingsAccountsTab.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccountsTab;

  /// No description provided for @settingsInstructionsTab.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get settingsInstructionsTab;

  /// No description provided for @settingsSkillsTab.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get settingsSkillsTab;

  /// No description provided for @settingsAgentsTab.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get settingsAgentsTab;

  /// No description provided for @settingsMcpTab.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get settingsMcpTab;

  /// No description provided for @settingsLspTab.
  ///
  /// In en, this message translates to:
  /// **'LSP'**
  String get settingsLspTab;

  /// No description provided for @settingsStatisticsTab.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get settingsStatisticsTab;

  /// No description provided for @settingsSecurityTab.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurityTab;

  /// No description provided for @settingsGeneralTab.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralTab;

  /// No description provided for @settingsSshTab.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get settingsSshTab;

  /// No description provided for @settingsBotsTab.
  ///
  /// In en, this message translates to:
  /// **'Bots'**
  String get settingsBotsTab;

  /// No description provided for @settingsBotsTitle.
  ///
  /// In en, this message translates to:
  /// **'Feishu bots'**
  String get settingsBotsTitle;

  /// No description provided for @settingsBotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local configuration, live connection, and inbound authorization are three separate facts.'**
  String get settingsBotsSubtitle;

  /// No description provided for @settingsBotsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add bot'**
  String get settingsBotsAdd;

  /// No description provided for @settingsBotsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No bots yet'**
  String get settingsBotsEmptyTitle;

  /// No description provided for @settingsBotsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Scan to create a Feishu China app, or connect an existing app. Secrets stay in memory until you save.'**
  String get settingsBotsEmptyBody;

  /// No description provided for @settingsBotsSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Select a bot'**
  String get settingsBotsSelectTitle;

  /// No description provided for @settingsBotsSelectBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a bot to inspect configuration, connection, and authorization.'**
  String get settingsBotsSelectBody;

  /// No description provided for @settingsBotsSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'First-time setup'**
  String get settingsBotsSetupTitle;

  /// No description provided for @settingsBotsSetupClose.
  ///
  /// In en, this message translates to:
  /// **'Close setup'**
  String get settingsBotsSetupClose;

  /// No description provided for @settingsBotsRisk.
  ///
  /// In en, this message translates to:
  /// **'Remote messages can start this computer\'s agent tools. The current policy is full-access. Linking a project is not an OS sandbox.'**
  String get settingsBotsRisk;

  /// No description provided for @settingsBotsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Requested scopes (preset=false): im:message:send_as_bot, im:message.p2p_msg:readonly, im:message.group_at_msg:readonly, im:chat:readonly, im:message:readonly, im:resource, im:resource:upload, cardkit:card:write. Event: im.message.receive_v1. Image and file reception is retained; file delivery requires upload access and streaming cards require creation and update access. Existing apps need an administrator to grant missing permissions and publish the app. Declaring permissions does not mean they are approved.'**
  String get settingsBotsPermissions;

  /// No description provided for @settingsBotsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsBotsName;

  /// No description provided for @settingsBotsProject.
  ///
  /// In en, this message translates to:
  /// **'Linked project'**
  String get settingsBotsProject;

  /// No description provided for @settingsBotsRiskAck.
  ///
  /// In en, this message translates to:
  /// **'I understand remote messages can run local tools with full-access'**
  String get settingsBotsRiskAck;

  /// No description provided for @settingsBotsScan.
  ///
  /// In en, this message translates to:
  /// **'Create and connect Feishu app'**
  String get settingsBotsScan;

  /// No description provided for @settingsBotsManual.
  ///
  /// In en, this message translates to:
  /// **'Connect existing app'**
  String get settingsBotsManual;

  /// No description provided for @settingsBotsAppId.
  ///
  /// In en, this message translates to:
  /// **'App ID'**
  String get settingsBotsAppId;

  /// No description provided for @settingsBotsSecret.
  ///
  /// In en, this message translates to:
  /// **'App secret'**
  String get settingsBotsSecret;

  /// No description provided for @settingsBotsSave.
  ///
  /// In en, this message translates to:
  /// **'Save configuration'**
  String get settingsBotsSave;

  /// No description provided for @settingsBotsPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Unfinished local save'**
  String get settingsBotsPendingTitle;

  /// No description provided for @settingsBotsPendingPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing credentials'**
  String get settingsBotsPendingPreparing;

  /// No description provided for @settingsBotsPendingUncertain.
  ///
  /// In en, this message translates to:
  /// **'Save needs local verification'**
  String get settingsBotsPendingUncertain;

  /// No description provided for @settingsBotsPendingCleanup.
  ///
  /// In en, this message translates to:
  /// **'Cleanup pending'**
  String get settingsBotsPendingCleanup;

  /// No description provided for @settingsBotsPendingCleanupCommitted.
  ///
  /// In en, this message translates to:
  /// **'Config saved; cleanup still pending'**
  String get settingsBotsPendingCleanupCommitted;

  /// No description provided for @settingsBotsPendingIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get settingsBotsPendingIdle;

  /// No description provided for @settingsBotsVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify original operation'**
  String get settingsBotsVerify;

  /// No description provided for @settingsBotsFactConfig.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get settingsBotsFactConfig;

  /// No description provided for @settingsBotsFactConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsBotsFactConnection;

  /// No description provided for @settingsBotsFactAuth.
  ///
  /// In en, this message translates to:
  /// **'Authorization'**
  String get settingsBotsFactAuth;

  /// No description provided for @settingsBotsFactMissing.
  ///
  /// In en, this message translates to:
  /// **'No available configuration'**
  String get settingsBotsFactMissing;

  /// No description provided for @settingsBotsConnectionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsBotsConnectionConnected;

  /// No description provided for @settingsBotsConnectionConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get settingsBotsConnectionConnecting;

  /// No description provided for @settingsBotsConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsBotsConnectionFailed;

  /// No description provided for @settingsBotsConnectionIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get settingsBotsConnectionIdle;

  /// No description provided for @settingsBotsAuthGranted.
  ///
  /// In en, this message translates to:
  /// **'Local inbound grants exist'**
  String get settingsBotsAuthGranted;

  /// No description provided for @settingsBotsAuthPending.
  ///
  /// In en, this message translates to:
  /// **'Pairing pending'**
  String get settingsBotsAuthPending;

  /// No description provided for @settingsBotsAuthNone.
  ///
  /// In en, this message translates to:
  /// **'No inbound trust'**
  String get settingsBotsAuthNone;

  /// No description provided for @settingsBotsCredentialStored.
  ///
  /// In en, this message translates to:
  /// **'Stored'**
  String get settingsBotsCredentialStored;

  /// No description provided for @settingsBotsCredentialSession.
  ///
  /// In en, this message translates to:
  /// **'Session only'**
  String get settingsBotsCredentialSession;

  /// No description provided for @settingsBotsCredentialMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get settingsBotsCredentialMissing;

  /// No description provided for @settingsBotsCredentialUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsBotsCredentialUnavailable;

  /// No description provided for @settingsBotsRegistrationStatus.
  ///
  /// In en, this message translates to:
  /// **'Registration: {status}'**
  String settingsBotsRegistrationStatus(String status);

  /// No description provided for @settingsBotsOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Continue in browser'**
  String get settingsBotsOpenLink;

  /// No description provided for @settingsBotsOpenFeishu.
  ///
  /// In en, this message translates to:
  /// **'Continue in Feishu'**
  String get settingsBotsOpenFeishu;

  /// No description provided for @settingsBotsContinueHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm app creation in Feishu. This page will update automatically when registration completes.'**
  String get settingsBotsContinueHint;

  /// No description provided for @settingsBotsScanOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with Feishu on your phone and confirm app creation. This page will update automatically.'**
  String get settingsBotsScanOnlyHint;

  /// No description provided for @settingsBotsScanHint.
  ///
  /// In en, this message translates to:
  /// **'You can also scan with Feishu on your phone. If the client does not open, continue in your browser or scan the code.'**
  String get settingsBotsScanHint;

  /// No description provided for @settingsBotsOpenLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link. Scan the QR code to continue, or try the browser option.'**
  String get settingsBotsOpenLinkFailed;

  /// No description provided for @settingsBotsOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat in Feishu'**
  String get settingsBotsOpenChat;

  /// No description provided for @settingsBotsOpenChatBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open through browser'**
  String get settingsBotsOpenChatBrowser;

  /// No description provided for @settingsBotsPolicyDenied.
  ///
  /// In en, this message translates to:
  /// **'Feishu\'s access control policy denied this app\'s API request.'**
  String get settingsBotsPolicyDenied;

  /// No description provided for @settingsBotsPolicyDeniedHint.
  ///
  /// In en, this message translates to:
  /// **'Creating an app does not grant API access. Contact your organization\'s administrator to check the app\'s access policy, then retry once access is allowed.'**
  String get settingsBotsPolicyDeniedHint;

  /// No description provided for @settingsBotsPlatformCode.
  ///
  /// In en, this message translates to:
  /// **'Feishu error code: {code}'**
  String settingsBotsPlatformCode(String code);

  /// No description provided for @settingsBotsCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get settingsBotsCopyLink;

  /// No description provided for @settingsBotsRegistrationBusy.
  ///
  /// In en, this message translates to:
  /// **'Local save is committing. Cancel is busy and does not mean cancelled.'**
  String get settingsBotsRegistrationBusy;

  /// No description provided for @settingsBotsCancelRegistration.
  ///
  /// In en, this message translates to:
  /// **'Cancel registration'**
  String get settingsBotsCancelRegistration;

  /// No description provided for @settingsBotsRegIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get settingsBotsRegIdle;

  /// No description provided for @settingsBotsRegPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get settingsBotsRegPreparing;

  /// No description provided for @settingsBotsRegWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation in Feishu'**
  String get settingsBotsRegWaiting;

  /// No description provided for @settingsBotsRegSlowDown.
  ///
  /// In en, this message translates to:
  /// **'Slow down'**
  String get settingsBotsRegSlowDown;

  /// No description provided for @settingsBotsRegCommitting.
  ///
  /// In en, this message translates to:
  /// **'Committing'**
  String get settingsBotsRegCommitting;

  /// No description provided for @settingsBotsRegCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get settingsBotsRegCompleted;

  /// No description provided for @settingsBotsRegDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get settingsBotsRegDenied;

  /// No description provided for @settingsBotsRegExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get settingsBotsRegExpired;

  /// No description provided for @settingsBotsRegCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get settingsBotsRegCancelled;

  /// No description provided for @settingsBotsRegFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsBotsRegFailed;

  /// No description provided for @settingsBotsQrFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not encode the verification QR code. Use the local open or copy action for the current trusted link.'**
  String get settingsBotsQrFailed;

  /// No description provided for @settingsBotsAppIdLocked.
  ///
  /// In en, this message translates to:
  /// **'App ID cannot change after platform conversations or durable records exist.'**
  String get settingsBotsAppIdLocked;

  /// No description provided for @settingsBotsProjectLocked.
  ///
  /// In en, this message translates to:
  /// **'Project cannot change after Thread mapping or admitted input exists.'**
  String get settingsBotsProjectLocked;

  /// No description provided for @settingsBotsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable connection'**
  String get settingsBotsEnabled;

  /// No description provided for @settingsBotsRetryConnection.
  ///
  /// In en, this message translates to:
  /// **'Retry connection'**
  String get settingsBotsRetryConnection;

  /// No description provided for @settingsBotsTools.
  ///
  /// In en, this message translates to:
  /// **'Allow project tools'**
  String get settingsBotsTools;

  /// No description provided for @settingsBotsToolsHint.
  ///
  /// In en, this message translates to:
  /// **'Only the four tools on the linked project root Thread. Local owner query/send and original auto-replies are not gated by this switch.'**
  String get settingsBotsToolsHint;

  /// No description provided for @settingsBotsTrustedUsers.
  ///
  /// In en, this message translates to:
  /// **'Trusted users'**
  String get settingsBotsTrustedUsers;

  /// No description provided for @settingsBotsTrustedChats.
  ///
  /// In en, this message translates to:
  /// **'Trusted groups'**
  String get settingsBotsTrustedChats;

  /// No description provided for @settingsBotsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get settingsBotsRevoke;

  /// No description provided for @settingsBotsApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get settingsBotsApprove;

  /// No description provided for @settingsBotsPairingHint.
  ///
  /// In en, this message translates to:
  /// **'Unknown DMs do not run the model. After approval, ask the user to resend; old messages are not executed.'**
  String get settingsBotsPairingHint;

  /// No description provided for @settingsBotsClearPairing.
  ///
  /// In en, this message translates to:
  /// **'Clear request'**
  String get settingsBotsClearPairing;

  /// No description provided for @settingsBotsClearPairingHint.
  ///
  /// In en, this message translates to:
  /// **'Clears only this local pairing request. This user\'s current trust setting stays unchanged, and their old messages are not executed.'**
  String get settingsBotsClearPairingHint;

  /// No description provided for @settingsBotsNoTrustedUsers.
  ///
  /// In en, this message translates to:
  /// **'No trusted users yet. Manual apps start with an empty trust list.'**
  String get settingsBotsNoTrustedUsers;

  /// No description provided for @settingsBotsNoTrustedChats.
  ///
  /// In en, this message translates to:
  /// **'Groups are off by default. Authorize a group plus the real @mention of this bot.'**
  String get settingsBotsNoTrustedChats;

  /// No description provided for @settingsBotsConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get settingsBotsConversations;

  /// No description provided for @settingsBotsRefreshConversations.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsBotsRefreshConversations;

  /// No description provided for @settingsBotsNewThread.
  ///
  /// In en, this message translates to:
  /// **'Create local session'**
  String get settingsBotsNewThread;

  /// No description provided for @settingsBotsMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get settingsBotsMessages;

  /// No description provided for @settingsBotsSendHint.
  ///
  /// In en, this message translates to:
  /// **'Send as this bot'**
  String get settingsBotsSendHint;

  /// No description provided for @settingsBotsSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get settingsBotsSend;

  /// No description provided for @settingsBotsSendStatus.
  ///
  /// In en, this message translates to:
  /// **'Send status: {status}'**
  String settingsBotsSendStatus(String status);

  /// No description provided for @settingsBotsSourceGroup.
  ///
  /// In en, this message translates to:
  /// **'Group chat'**
  String get settingsBotsSourceGroup;

  /// No description provided for @settingsBotsSourceDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct chat'**
  String get settingsBotsSourceDirect;

  /// No description provided for @settingsBotsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit configuration'**
  String get settingsBotsEdit;

  /// No description provided for @settingsBotsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsBotsDismiss;

  /// No description provided for @settingsBotsPreserveSecret.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the existing secret. It is never displayed.'**
  String get settingsBotsPreserveSecret;

  /// No description provided for @settingsBotsClearSecret.
  ///
  /// In en, this message translates to:
  /// **'Remove the saved secret'**
  String get settingsBotsClearSecret;

  /// No description provided for @settingsBotsOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The operation could not finish. Check the current state and retry explicitly; an unknown send is not safe to replay.'**
  String get settingsBotsOperationFailed;

  /// No description provided for @settingsBotsModelReady.
  ///
  /// In en, this message translates to:
  /// **'The Simple mode model route and its credential are configured. This is not a live model connectivity check.'**
  String get settingsBotsModelReady;

  /// No description provided for @settingsBotsModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Configure an account and a complete Simple mode model route before expecting remote messages to run. Saving this app does not check model connectivity.'**
  String get settingsBotsModelMissing;

  /// No description provided for @settingsBotsManualGuide.
  ///
  /// In en, this message translates to:
  /// **'In the Feishu China developer console, enable the bot and long-connection event delivery, subscribe to im.message.receive_v1, request the scopes listed above, then publish the app and confirm its availability. Tenant administrators may need to approve permissions. Save here, then enable the connection.'**
  String get settingsBotsManualGuide;

  /// No description provided for @settingsBotsFirstMessageGuide.
  ///
  /// In en, this message translates to:
  /// **'After a real connection, send the bot a message in Feishu. An unknown sender only creates a pairing request: approve it locally and ask them to send again. Group execution needs local group authorization and a user\'s actual @mention of this bot; @all is not sufficient.'**
  String get settingsBotsFirstMessageGuide;

  /// No description provided for @settingsBotsNewThreadWarning.
  ///
  /// In en, this message translates to:
  /// **'Create a new local context for future messages? Existing history is retained. Already admitted messages and replies stay with their original context and are not moved.'**
  String get settingsBotsNewThreadWarning;

  /// No description provided for @settingsBotsApproveGroup.
  ///
  /// In en, this message translates to:
  /// **'Authorize this group'**
  String get settingsBotsApproveGroup;

  /// No description provided for @settingsBotsNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get settingsBotsNextPage;

  /// No description provided for @settingsBotsRefreshMessages.
  ///
  /// In en, this message translates to:
  /// **'Apply range / refresh messages'**
  String get settingsBotsRefreshMessages;

  /// No description provided for @settingsBotsStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time (Unix seconds; optional)'**
  String get settingsBotsStartTime;

  /// No description provided for @settingsBotsEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time (Unix seconds; optional)'**
  String get settingsBotsEndTime;

  /// No description provided for @settingsBotsHistoryPermissions.
  ///
  /// In en, this message translates to:
  /// **'Only permitted history is available. Group history may additionally require im:message.group_msg, granted separately in Feishu. This app never requests it automatically or switches to a user identity.'**
  String get settingsBotsHistoryPermissions;

  /// No description provided for @settingsBotsOpenConsole.
  ///
  /// In en, this message translates to:
  /// **'Open Feishu developer console'**
  String get settingsBotsOpenConsole;

  /// No description provided for @settingsBotsOpenConsoleHint.
  ///
  /// In en, this message translates to:
  /// **'Opens the official Feishu China developer console page. There, choose the app matching the current App ID and open its permission management; permissions still require administrator approval and the app must stay published with its availability. Nothing is requested or approved automatically here.'**
  String get settingsBotsOpenConsoleHint;

  /// No description provided for @settingsBotsOpenConsoleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the developer console. Please try again.'**
  String get settingsBotsOpenConsoleFailed;

  /// No description provided for @settingsBotsConnectionReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get settingsBotsConnectionReconnecting;

  /// No description provided for @settingsBotsSendOperation.
  ///
  /// In en, this message translates to:
  /// **'Send operation'**
  String get settingsBotsSendOperation;

  /// No description provided for @settingsBotsNoReplay.
  ///
  /// In en, this message translates to:
  /// **'Some messages may already have been delivered. This result is retained and will not be replayed automatically.'**
  String get settingsBotsNoReplay;

  /// No description provided for @settingsBotsSendSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get settingsBotsSendSucceeded;

  /// No description provided for @settingsBotsSendPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially delivered'**
  String get settingsBotsSendPartial;

  /// No description provided for @settingsBotsSendRejected.
  ///
  /// In en, this message translates to:
  /// **'Not delivered'**
  String get settingsBotsSendRejected;

  /// No description provided for @settingsBotsSendUnknown.
  ///
  /// In en, this message translates to:
  /// **'Outcome unknown'**
  String get settingsBotsSendUnknown;

  /// No description provided for @settingsBotsUploadStage.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get settingsBotsUploadStage;

  /// No description provided for @settingsBotsMessageStage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get settingsBotsMessageStage;

  /// No description provided for @settingsBotsStageNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get settingsBotsStageNotStarted;

  /// No description provided for @settingsBotsStageAccepted.
  ///
  /// In en, this message translates to:
  /// **'Platform accepted'**
  String get settingsBotsStageAccepted;

  /// No description provided for @settingsBotsStageRejected.
  ///
  /// In en, this message translates to:
  /// **'Platform rejected'**
  String get settingsBotsStageRejected;

  /// No description provided for @settingsBotsStopCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled locally'**
  String get settingsBotsStopCancelled;

  /// No description provided for @settingsBotsStopLocalFailure.
  ///
  /// In en, this message translates to:
  /// **'Local failure'**
  String get settingsBotsStopLocalFailure;

  /// No description provided for @settingsSshTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote development'**
  String get settingsSshTitle;

  /// No description provided for @settingsSshSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Servers come from your ~/.ssh/config; anywork manages only its own marked blocks.'**
  String get settingsSshSubtitle;

  /// No description provided for @settingsSshAdd.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get settingsSshAdd;

  /// No description provided for @settingsSshEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SSH servers yet.'**
  String get settingsSshEmpty;

  /// No description provided for @settingsSshManagedByCore.
  ///
  /// In en, this message translates to:
  /// **'OpenSSH and the minimal remote helper are managed locally.'**
  String get settingsSshManagedByCore;

  /// No description provided for @settingsSshTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get settingsSshTest;

  /// No description provided for @settingsSshReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get settingsSshReconnect;

  /// No description provided for @settingsSshReconnectHint.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to load the latest remote environment. Running remote commands will be interrupted.'**
  String get settingsSshReconnectHint;

  /// No description provided for @settingsSshOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get settingsSshOpenProject;

  /// No description provided for @settingsSshEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get settingsSshEdit;

  /// No description provided for @settingsSshDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsSshDelete;

  /// No description provided for @settingsSshReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get settingsSshReady;

  /// No description provided for @settingsSshDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete SSH server?'**
  String get settingsSshDeleteTitle;

  /// No description provided for @settingsSshDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? Projects using this server must be removed first.'**
  String settingsSshDeleteBody(String name);

  /// No description provided for @settingsSshAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias (Host)'**
  String get settingsSshAlias;

  /// No description provided for @settingsSshProjectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get settingsSshProjectName;

  /// No description provided for @settingsSshHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get settingsSshHost;

  /// No description provided for @settingsSshUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get settingsSshUsername;

  /// No description provided for @settingsSshPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get settingsSshPort;

  /// No description provided for @settingsSshIdentityFile.
  ///
  /// In en, this message translates to:
  /// **'Identity file (optional)'**
  String get settingsSshIdentityFile;

  /// No description provided for @settingsSshIdentityHelper.
  ///
  /// In en, this message translates to:
  /// **'Uses the ssh agent when left empty.'**
  String get settingsSshIdentityHelper;

  /// No description provided for @settingsSshEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit SSH server'**
  String get settingsSshEditTitle;

  /// No description provided for @settingsSshPassword.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get settingsSshPassword;

  /// No description provided for @settingsSshPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'Saved in your system credential store, never written to ~/.ssh/config. Leave empty to use a key or prompt on connect.'**
  String get settingsSshPasswordHelper;

  /// No description provided for @settingsSshPasswordSavedHint.
  ///
  /// In en, this message translates to:
  /// **'Password saved — leave empty to keep'**
  String get settingsSshPasswordSavedHint;

  /// No description provided for @settingsSshPasswordClear.
  ///
  /// In en, this message translates to:
  /// **'Clear saved password'**
  String get settingsSshPasswordClear;

  /// No description provided for @settingsSshPasswordClearedHint.
  ///
  /// In en, this message translates to:
  /// **'Saved password will be cleared on save'**
  String get settingsSshPasswordClearedHint;

  /// No description provided for @settingsSshPasswordBadge.
  ///
  /// In en, this message translates to:
  /// **'Password saved'**
  String get settingsSshPasswordBadge;

  /// No description provided for @settingsSshKeyBadge.
  ///
  /// In en, this message translates to:
  /// **'Key: {path}'**
  String settingsSshKeyBadge(String path);

  /// No description provided for @settingsSshAuthPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter SSH password'**
  String get settingsSshAuthPromptTitle;

  /// No description provided for @settingsSshAuthPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Password authentication is required to connect to {target}.'**
  String settingsSshAuthPromptSubtitle(String target);

  /// No description provided for @settingsSshAuthPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'SSH password'**
  String get settingsSshAuthPasswordLabel;

  /// No description provided for @settingsSshAuthPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the SSH password'**
  String get settingsSshAuthPasswordRequired;

  /// No description provided for @settingsSshAuthRememberPassword.
  ///
  /// In en, this message translates to:
  /// **'Save password in system credential store'**
  String get settingsSshAuthRememberPassword;

  /// No description provided for @settingsSshAuthConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get settingsSshAuthConnect;

  /// No description provided for @settingsSshPasswordAuthUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not offer password authentication. Configure an SSH key or start ssh-agent.'**
  String get settingsSshPasswordAuthUnavailable;

  /// No description provided for @settingsSshReadOnlyEntry.
  ///
  /// In en, this message translates to:
  /// **'Hand-written entry — edit it in ~/.ssh/config.'**
  String get settingsSshReadOnlyEntry;

  /// No description provided for @settingsSshSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSshSave;

  /// No description provided for @settingsSshAliasRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an alias'**
  String get settingsSshAliasRequired;

  /// No description provided for @settingsSshAliasInvalid.
  ///
  /// In en, this message translates to:
  /// **'Alias must be a single token without spaces or wildcards'**
  String get settingsSshAliasInvalid;

  /// No description provided for @settingsSshAliasHelper.
  ///
  /// In en, this message translates to:
  /// **'Stored as a Host entry in ~/.ssh/config; cannot be renamed later.'**
  String get settingsSshAliasHelper;

  /// No description provided for @settingsSshHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a host address'**
  String get settingsSshHostRequired;

  /// No description provided for @settingsSshUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a username'**
  String get settingsSshUsernameRequired;

  /// No description provided for @settingsSshPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Port must be a number from 1 to 65535'**
  String get settingsSshPortInvalid;

  /// No description provided for @settingsSshChooseDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose remote directory'**
  String get settingsSshChooseDirectory;

  /// No description provided for @settingsSshOpenThisDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open this directory'**
  String get settingsSshOpenThisDirectory;

  /// No description provided for @settingsSshGo.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get settingsSshGo;

  /// No description provided for @settingsSshDirectoryPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Remote path'**
  String get settingsSshDirectoryPathLabel;

  /// No description provided for @settingsSshDirectoryPathHint.
  ///
  /// In en, this message translates to:
  /// **'/home/user/project'**
  String get settingsSshDirectoryPathHint;

  /// No description provided for @settingsSshPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a remote directory path'**
  String get settingsSshPathRequired;

  /// No description provided for @settingsSshPathAbsolute.
  ///
  /// In en, this message translates to:
  /// **'Path must be an absolute POSIX path starting with /'**
  String get settingsSshPathAbsolute;

  /// No description provided for @settingsSshDirectoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'This directory is empty'**
  String get settingsSshDirectoryEmpty;

  /// No description provided for @settingsSshDirectoryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No subdirectories here — you can still open this directory.'**
  String get settingsSshDirectoryEmptyHint;

  /// No description provided for @settingsSshUp.
  ///
  /// In en, this message translates to:
  /// **'Parent directory'**
  String get settingsSshUp;

  /// No description provided for @settingsSshOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this directory. Check the server and try again.'**
  String get settingsSshOpenFailed;

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what you need...'**
  String get composerHint;

  /// No description provided for @composerSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get composerSend;

  /// No description provided for @composerStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get composerStop;

  /// No description provided for @compileModeSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get compileModeSimple;

  /// No description provided for @compileModeTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get compileModeTask;

  /// No description provided for @statusCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get statusCost;

  /// No description provided for @statusTotalTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Total tokens'**
  String get statusTotalTokensLabel;

  /// No description provided for @statusModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get statusModelLabel;

  /// No description provided for @statusCapabilitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Active capabilities'**
  String get statusCapabilitiesTitle;

  /// No description provided for @statusSessionMode.
  ///
  /// In en, this message translates to:
  /// **'Session mode'**
  String get statusSessionMode;

  /// No description provided for @statusSessionModeLocked.
  ///
  /// In en, this message translates to:
  /// **'Session mode cannot change while the session is running or a workflow is active'**
  String get statusSessionModeLocked;

  /// No description provided for @composerWorkspaceModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Session workspace'**
  String get composerWorkspaceModeLabel;

  /// No description provided for @composerWorkspaceModeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local directory'**
  String get composerWorkspaceModeLocal;

  /// No description provided for @composerWorkspaceModeWorktree.
  ///
  /// In en, this message translates to:
  /// **'New worktree'**
  String get composerWorkspaceModeWorktree;

  /// No description provided for @statusPlannerModel.
  ///
  /// In en, this message translates to:
  /// **'Main agent model'**
  String get statusPlannerModel;

  /// No description provided for @statusModelRouteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Current model unavailable; show reason'**
  String get statusModelRouteUnavailable;

  /// No description provided for @statusModelRouteUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'Current model unavailable: {reason}'**
  String statusModelRouteUnavailableDetail(String reason);

  /// No description provided for @statusModelRouteUnavailableFallback.
  ///
  /// In en, this message translates to:
  /// **'The current model route is unavailable. Check the account and model settings.'**
  String get statusModelRouteUnavailableFallback;

  /// No description provided for @statusModelSwitchWhileRunning.
  ///
  /// In en, this message translates to:
  /// **'This session is running or waiting for input, so the model cannot be changed yet. Stop the current run or wait for it to finish.'**
  String get statusModelSwitchWhileRunning;

  /// No description provided for @statusModelSwitchWhileInactive.
  ///
  /// In en, this message translates to:
  /// **'This session is closing, closed, or unavailable due to an error. Restore it before changing the model.'**
  String get statusModelSwitchWhileInactive;

  /// No description provided for @statusModelNoticeDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss model notice'**
  String get statusModelNoticeDismiss;

  /// No description provided for @statusExecutorModel.
  ///
  /// In en, this message translates to:
  /// **'Executor model'**
  String get statusExecutorModel;

  /// No description provided for @statusReasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get statusReasoningEffort;

  /// No description provided for @statusContextLabel.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get statusContextLabel;

  /// No description provided for @statusContextRemainingLabel.
  ///
  /// In en, this message translates to:
  /// **'To compact'**
  String get statusContextRemainingLabel;

  /// No description provided for @statusContextOverLimitValue.
  ///
  /// In en, this message translates to:
  /// **'{tokens} over'**
  String statusContextOverLimitValue(String tokens);

  /// No description provided for @statusModelMaxContextLabel.
  ///
  /// In en, this message translates to:
  /// **'Max context'**
  String get statusModelMaxContextLabel;

  /// No description provided for @statusModelEffectiveWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Effective window'**
  String get statusModelEffectiveWindowLabel;

  /// No description provided for @statusAutoCompactLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Compact at'**
  String get statusAutoCompactLimitLabel;

  /// No description provided for @statusSessionUsageSection.
  ///
  /// In en, this message translates to:
  /// **'Session usage'**
  String get statusSessionUsageSection;

  /// No description provided for @statusInputTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get statusInputTokensLabel;

  /// No description provided for @statusOutputTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get statusOutputTokensLabel;

  /// No description provided for @statusCostEstimateLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost'**
  String get statusCostEstimateLabel;

  /// No description provided for @statusUsageIncompleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get statusUsageIncompleteLabel;

  /// No description provided for @statusCacheLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache hit rate'**
  String get statusCacheLabel;

  /// No description provided for @statusCacheHitTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache read'**
  String get statusCacheHitTokensLabel;

  /// No description provided for @statusCacheMissTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache miss'**
  String get statusCacheMissTokensLabel;

  /// No description provided for @statusCacheWriteTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache write'**
  String get statusCacheWriteTokensLabel;

  /// No description provided for @statusReasoningTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning tokens'**
  String get statusReasoningTokensLabel;

  /// No description provided for @statusInferenceCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Inferences'**
  String get statusInferenceCountLabel;

  /// No description provided for @statusCacheSavingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache savings'**
  String get statusCacheSavingsLabel;

  /// No description provided for @statusUnpricedUsageLabel.
  ///
  /// In en, this message translates to:
  /// **'Unpriced'**
  String get statusUnpricedUsageLabel;

  /// No description provided for @sessionAllAgentsCostTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cost for all agents in this session'**
  String get sessionAllAgentsCostTooltip;

  /// No description provided for @sessionMoreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get sessionMoreActionsTooltip;

  /// No description provided for @sessionOpenWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get sessionOpenWorkspace;

  /// No description provided for @sessionOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open with'**
  String get sessionOpenWith;

  /// No description provided for @sessionOpenInVsCode.
  ///
  /// In en, this message translates to:
  /// **'Open in VS Code'**
  String get sessionOpenInVsCode;

  /// No description provided for @sessionOpenInZed.
  ///
  /// In en, this message translates to:
  /// **'Open in Zed'**
  String get sessionOpenInZed;

  /// No description provided for @sessionOpenInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in terminal'**
  String get sessionOpenInTerminal;

  /// No description provided for @sessionVsCodeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'VS Code was not found on this machine'**
  String get sessionVsCodeUnavailable;

  /// No description provided for @sessionZedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Zed was not found on this machine'**
  String get sessionZedUnavailable;

  /// No description provided for @sessionTerminalUnavailableWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows Terminal (wt.exe) was not found'**
  String get sessionTerminalUnavailableWindows;

  /// No description provided for @sessionTerminalUnavailableLinux.
  ///
  /// In en, this message translates to:
  /// **'xdg-terminal-exec or x-terminal-emulator was not found'**
  String get sessionTerminalUnavailableLinux;

  /// No description provided for @sessionTerminalUnavailableGeneric.
  ///
  /// In en, this message translates to:
  /// **'External terminals are unsupported on this platform'**
  String get sessionTerminalUnavailableGeneric;

  /// No description provided for @sessionVsCodeOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open VS Code'**
  String get sessionVsCodeOpenFailed;

  /// No description provided for @sessionZedOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open Zed'**
  String get sessionZedOpenFailed;

  /// No description provided for @sessionTerminalOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open terminal'**
  String get sessionTerminalOpenFailed;

  /// No description provided for @sessionOpenServerMissing.
  ///
  /// In en, this message translates to:
  /// **'The SSH alias for this project is no longer in ~/.ssh/config'**
  String get sessionOpenServerMissing;

  /// No description provided for @statusLastConfirmedAgentTokenSpeed.
  ///
  /// In en, this message translates to:
  /// **'Last confirmed output speed (includes the first-token wait)'**
  String get statusLastConfirmedAgentTokenSpeed;

  /// No description provided for @settingsStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get settingsStatisticsTitle;

  /// No description provided for @settingsStatisticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recent successful calls grouped by account and configured model, with an in-group effort breakdown.'**
  String get settingsStatisticsSubtitle;

  /// No description provided for @settingsStatisticsSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Model performance'**
  String get settingsStatisticsSummaryTitle;

  /// No description provided for @settingsStatisticsHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Call history'**
  String get settingsStatisticsHistoryTitle;

  /// No description provided for @settingsStatisticsAllModels.
  ///
  /// In en, this message translates to:
  /// **'All models'**
  String get settingsStatisticsAllModels;

  /// No description provided for @settingsStatisticsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No call history yet.'**
  String get settingsStatisticsEmpty;

  /// No description provided for @settingsStatisticsSummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No model performance summaries yet.'**
  String get settingsStatisticsSummaryEmpty;

  /// No description provided for @settingsStatisticsFilteredEmpty.
  ///
  /// In en, this message translates to:
  /// **'No calls match these filters.'**
  String get settingsStatisticsFilteredEmpty;

  /// No description provided for @settingsStatisticsGapTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics have gaps'**
  String get settingsStatisticsGapTitle;

  /// No description provided for @settingsStatisticsGapBody.
  ///
  /// In en, this message translates to:
  /// **'Some calls could not be recorded; summaries and history may be incomplete.'**
  String get settingsStatisticsGapBody;

  /// No description provided for @settingsStatisticsReadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not read statistics'**
  String get settingsStatisticsReadFailedTitle;

  /// No description provided for @settingsStatisticsReadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The displayed data may be unavailable or out of date.'**
  String get settingsStatisticsReadFailedBody;

  /// No description provided for @settingsStatisticsMismatchesOnly.
  ///
  /// In en, this message translates to:
  /// **'Mismatches only'**
  String get settingsStatisticsMismatchesOnly;

  /// No description provided for @settingsStatisticsMismatchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No model mismatches match these filters.'**
  String get settingsStatisticsMismatchEmpty;

  /// No description provided for @statisticsModel.
  ///
  /// In en, this message translates to:
  /// **'Account / model'**
  String get statisticsModel;

  /// No description provided for @statisticsHistoryModelHeader.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get statisticsHistoryModelHeader;

  /// No description provided for @statisticsConfiguredModel.
  ///
  /// In en, this message translates to:
  /// **'Configured model'**
  String get statisticsConfiguredModel;

  /// No description provided for @statisticsSentModel.
  ///
  /// In en, this message translates to:
  /// **'Sent model'**
  String get statisticsSentModel;

  /// No description provided for @statisticsReportedModel.
  ///
  /// In en, this message translates to:
  /// **'Reported model'**
  String get statisticsReportedModel;

  /// No description provided for @statisticsUpstreamReportedModel.
  ///
  /// In en, this message translates to:
  /// **'Upstream response model'**
  String get statisticsUpstreamReportedModel;

  /// No description provided for @statisticsModelMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get statisticsModelMatched;

  /// No description provided for @statisticsModelMismatched.
  ///
  /// In en, this message translates to:
  /// **'Mismatch'**
  String get statisticsModelMismatched;

  /// No description provided for @statisticsModelMismatchBadge.
  ///
  /// In en, this message translates to:
  /// **'Model mismatch'**
  String get statisticsModelMismatchBadge;

  /// No description provided for @statisticsModelUnreported.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get statisticsModelUnreported;

  /// No description provided for @statisticsModelLegacyUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not collected'**
  String get statisticsModelLegacyUnknown;

  /// No description provided for @statisticsMetricNotCollected.
  ///
  /// In en, this message translates to:
  /// **'Not collected'**
  String get statisticsMetricNotCollected;

  /// No description provided for @statisticsModelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get statisticsModelUnavailable;

  /// No description provided for @statisticsReasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get statisticsReasoningEffort;

  /// No description provided for @statisticsReasoningEffortUnspecified.
  ///
  /// In en, this message translates to:
  /// **'Unspecified / not recorded'**
  String get statisticsReasoningEffortUnspecified;

  /// No description provided for @statisticsSpeed.
  ///
  /// In en, this message translates to:
  /// **'Output TPS (incl. first token)'**
  String get statisticsSpeed;

  /// No description provided for @statisticsSamples.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get statisticsSamples;

  /// No description provided for @statisticsOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output tokens'**
  String get statisticsOutputTokens;

  /// No description provided for @statisticsAverageTtft.
  ///
  /// In en, this message translates to:
  /// **'Average first token'**
  String get statisticsAverageTtft;

  /// No description provided for @statisticsAverageResponse.
  ///
  /// In en, this message translates to:
  /// **'Average total response'**
  String get statisticsAverageResponse;

  /// No description provided for @statisticsCompletedAt.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statisticsCompletedAt;

  /// No description provided for @statisticsDecode.
  ///
  /// In en, this message translates to:
  /// **'After first token'**
  String get statisticsDecode;

  /// No description provided for @statisticsTotalResponse.
  ///
  /// In en, this message translates to:
  /// **'Total response'**
  String get statisticsTotalResponse;

  /// No description provided for @statisticsTtftSampleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} first-token samples'**
  String statisticsTtftSampleCount(int count);

  /// No description provided for @settingsStatisticsThroughputNote.
  ///
  /// In en, this message translates to:
  /// **'Output TPS = provider-confirmed output tokens × 1000 ÷ total response time (including the first-token wait). Total response runs from the request that produced the result to its normalized terminal event; failed retries, backoff, tool execution and post-terminal collection or saving are excluded. The first token is the first non-empty text, reasoning or tool-input increment, and output may include reasoning tokens without double counting. The after-first-token time is diagnostic, not hardware decode time. Samples from the previous statistics definition were discarded; raw calls and billing remain.'**
  String get settingsStatisticsThroughputNote;

  /// No description provided for @statusTurnQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusTurnQueued;

  /// No description provided for @statusTurnPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing context'**
  String get statusTurnPreparing;

  /// No description provided for @statusTurnResponding.
  ///
  /// In en, this message translates to:
  /// **'Responding'**
  String get statusTurnResponding;

  /// No description provided for @statusTurnPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get statusTurnPlanning;

  /// No description provided for @statusTurnRunningTool.
  ///
  /// In en, this message translates to:
  /// **'Running tool'**
  String get statusTurnRunningTool;

  /// No description provided for @statusTurnWaitingForApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for tool approval'**
  String get statusTurnWaitingForApproval;

  /// No description provided for @statusTurnWaitingForUserInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get statusTurnWaitingForUserInput;

  /// No description provided for @statusTurnPersisting.
  ///
  /// In en, this message translates to:
  /// **'Saving turn'**
  String get statusTurnPersisting;

  /// No description provided for @statusInteractionToolApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for tool approval'**
  String get statusInteractionToolApproval;

  /// No description provided for @statusInteractionUserInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get statusInteractionUserInput;

  /// No description provided for @statusSkillsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 skill} other{{count} skills}}'**
  String statusSkillsCount(int count);

  /// No description provided for @statusMcpCount.
  ///
  /// In en, this message translates to:
  /// **'{count} MCP'**
  String statusMcpCount(int count);

  /// No description provided for @statusLspCount.
  ///
  /// In en, this message translates to:
  /// **'{count} LSP'**
  String statusLspCount(int count);

  /// No description provided for @statusLspIndexing.
  ///
  /// In en, this message translates to:
  /// **'Indexing'**
  String get statusLspIndexing;

  /// No description provided for @statusLspBusy.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get statusLspBusy;

  /// No description provided for @statusLspActivityPercentage.
  ///
  /// In en, this message translates to:
  /// **'{percentage}%'**
  String statusLspActivityPercentage(int percentage);

  /// No description provided for @statusAgentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 agent} other{{count} agents}}'**
  String statusAgentsCount(int count);

  /// No description provided for @composerAgentRuntimeDriven.
  ///
  /// In en, this message translates to:
  /// **'This agent session is driven by the runtime'**
  String get composerAgentRuntimeDriven;

  /// No description provided for @statusSkillsSection.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get statusSkillsSection;

  /// No description provided for @statusMcpSection.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get statusMcpSection;

  /// No description provided for @statusLspSection.
  ///
  /// In en, this message translates to:
  /// **'LSP'**
  String get statusLspSection;

  /// No description provided for @agentDetailStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get agentDetailStatusQueued;

  /// No description provided for @agentDetailStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentDetailStatusRunning;

  /// No description provided for @agentDetailStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get agentDetailStatusCompleted;

  /// No description provided for @agentDetailStatusErrored.
  ///
  /// In en, this message translates to:
  /// **'Errored'**
  String get agentDetailStatusErrored;

  /// No description provided for @agentDetailStatusInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get agentDetailStatusInterrupted;

  /// No description provided for @agentDetailStatusShutdown.
  ///
  /// In en, this message translates to:
  /// **'Shutdown'**
  String get agentDetailStatusShutdown;

  /// No description provided for @agentDetailPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get agentDetailPathLabel;

  /// No description provided for @timelineEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get timelineEmptyTitle;

  /// No description provided for @timelineEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Open a project or start a session to begin.'**
  String get timelineEmptyMessage;

  /// No description provided for @timelineExternalLinkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open this link.'**
  String get timelineExternalLinkOpenFailed;

  /// No description provided for @timelineAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get timelineAttachment;

  /// No description provided for @timelineImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load this image.'**
  String get timelineImageLoadFailed;

  /// No description provided for @timelineImageRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get timelineImageRetry;

  /// No description provided for @timelineImageClose.
  ///
  /// In en, this message translates to:
  /// **'Close image preview'**
  String get timelineImageClose;

  /// No description provided for @timelineImageCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Image card'**
  String get timelineImageCardTitle;

  /// No description provided for @timelineImageCardEmpty.
  ///
  /// In en, this message translates to:
  /// **'This image is unavailable'**
  String get timelineImageCardEmpty;

  /// No description provided for @timelineRemoteImageSource.
  ///
  /// In en, this message translates to:
  /// **'External image from {host}'**
  String timelineRemoteImageSource(String host);

  /// No description provided for @timelineRemoteImageOpen.
  ///
  /// In en, this message translates to:
  /// **'Click to load and preview'**
  String get timelineRemoteImageOpen;

  /// No description provided for @timelineJumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get timelineJumpToLatest;

  /// No description provided for @timelineNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get timelineNew;

  /// No description provided for @timelineLoadEarlier.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get timelineLoadEarlier;

  /// No description provided for @timelineBackToLive.
  ///
  /// In en, this message translates to:
  /// **'Back to live'**
  String get timelineBackToLive;

  /// No description provided for @timelineDetailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This content is no longer available'**
  String get timelineDetailUnavailable;

  /// No description provided for @timelineReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting messages… Current content is preserved.'**
  String get timelineReconnecting;

  /// No description provided for @timelineConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to synchronize messages. Current content is preserved.'**
  String get timelineConnectionFailed;

  /// No description provided for @timelineReasoningFallback.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get timelineReasoningFallback;

  /// No description provided for @timelineReasoningActive.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get timelineReasoningActive;

  /// No description provided for @timelineReasoningEnded.
  ///
  /// In en, this message translates to:
  /// **'Thought ended'**
  String get timelineReasoningEnded;

  /// No description provided for @timelineReasoningFailed.
  ///
  /// In en, this message translates to:
  /// **'Thinking failed'**
  String get timelineReasoningFailed;

  /// No description provided for @timelineReasoningCancelled.
  ///
  /// In en, this message translates to:
  /// **'Thinking cancelled'**
  String get timelineReasoningCancelled;

  /// No description provided for @timelineReasoningElapsedUnderSecond.
  ///
  /// In en, this message translates to:
  /// **'Thought for less than 1s'**
  String get timelineReasoningElapsedUnderSecond;

  /// No description provided for @timelineReasoningElapsedSeconds.
  ///
  /// In en, this message translates to:
  /// **'Thought for {seconds}s'**
  String timelineReasoningElapsedSeconds(int seconds);

  /// No description provided for @timelineReasoningElapsedMinutes.
  ///
  /// In en, this message translates to:
  /// **'Thought for {minutes}m'**
  String timelineReasoningElapsedMinutes(int minutes);

  /// No description provided for @timelineReasoningElapsedMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'Thought for {minutes}m {seconds}s'**
  String timelineReasoningElapsedMinutesSeconds(int minutes, int seconds);

  /// No description provided for @timelineReasoningSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get timelineReasoningSummary;

  /// No description provided for @timelineReasoningContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get timelineReasoningContent;

  /// No description provided for @timelineReasoningBudgetLimited.
  ///
  /// In en, this message translates to:
  /// **'Reasoning budget reached'**
  String get timelineReasoningBudgetLimited;

  /// No description provided for @timelineToolFallback.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get timelineToolFallback;

  /// No description provided for @timelineToolGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool activity'**
  String get timelineToolGroupTitle;

  /// No description provided for @timelineToolGroupSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} tools'**
  String timelineToolGroupSummary(int count);

  /// No description provided for @timelineToolGroupSummaryRunning.
  ///
  /// In en, this message translates to:
  /// **'{count} tools, {runningCount} running'**
  String timelineToolGroupSummaryRunning(int count, int runningCount);

  /// No description provided for @timelineToolGroupSummaryIssues.
  ///
  /// In en, this message translates to:
  /// **'{count} tools, {issueCount} need attention'**
  String timelineToolGroupSummaryIssues(int count, int issueCount);

  /// No description provided for @timelineToolGroupSummaryRunningWithIssues.
  ///
  /// In en, this message translates to:
  /// **'{count} tools, {runningCount} running, {issueCount} need attention'**
  String timelineToolGroupSummaryRunningWithIssues(
    int count,
    int runningCount,
    int issueCount,
  );

  /// No description provided for @timelineSkillActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated skill · {name}'**
  String timelineSkillActivated(String name);

  /// No description provided for @timelineSkillAgentActivated.
  ///
  /// In en, this message translates to:
  /// **'Agent activated skill · {name}'**
  String timelineSkillAgentActivated(String name);

  /// No description provided for @timelineParentAgent.
  ///
  /// In en, this message translates to:
  /// **'Main agent'**
  String get timelineParentAgent;

  /// No description provided for @timelineSkillUserActivated.
  ///
  /// In en, this message translates to:
  /// **'User activated skill · {name}'**
  String timelineSkillUserActivated(String name);

  /// No description provided for @timelineAgentFallback.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get timelineAgentFallback;

  /// No description provided for @timelineViewImageRead.
  ///
  /// In en, this message translates to:
  /// **'Image read'**
  String get timelineViewImageRead;

  /// No description provided for @timelineImagesViewed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Viewed 1 image} other{Viewed {count} images}}'**
  String timelineImagesViewed(int count);

  /// No description provided for @timelineImagesProduced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 image} other{{count} images}}'**
  String timelineImagesProduced(int count);

  /// No description provided for @timelineViewImageReading.
  ///
  /// In en, this message translates to:
  /// **'Reading image'**
  String get timelineViewImageReading;

  /// No description provided for @timelineViewImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to read image'**
  String get timelineViewImageFailed;

  /// No description provided for @timelineReadFileCompleted.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get timelineReadFileCompleted;

  /// No description provided for @timelineReadFileReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get timelineReadFileReading;

  /// No description provided for @timelineReadFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read'**
  String get timelineReadFileFailed;

  /// No description provided for @timelineToolEditSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get timelineToolEditSucceeded;

  /// No description provided for @timelineToolEditRunning.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get timelineToolEditRunning;

  /// No description provided for @timelineToolEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t edit'**
  String get timelineToolEditFailed;

  /// No description provided for @timelineToolPatchFilesMore.
  ///
  /// In en, this message translates to:
  /// **'{first}, and {more} more'**
  String timelineToolPatchFilesMore(String first, int more);

  /// No description provided for @timelineSessionNoteName.
  ///
  /// In en, this message translates to:
  /// **'session note'**
  String get timelineSessionNoteName;

  /// No description provided for @timelineToolCommandSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Ran'**
  String get timelineToolCommandSucceeded;

  /// No description provided for @timelineToolCommandRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get timelineToolCommandRunning;

  /// No description provided for @timelineToolCommandFailed.
  ///
  /// In en, this message translates to:
  /// **'Command failed'**
  String get timelineToolCommandFailed;

  /// No description provided for @timelineToolStdinSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Wrote input'**
  String get timelineToolStdinSucceeded;

  /// No description provided for @timelineToolStdinRunning.
  ///
  /// In en, this message translates to:
  /// **'Writing input'**
  String get timelineToolStdinRunning;

  /// No description provided for @timelineToolStdinFailed.
  ///
  /// In en, this message translates to:
  /// **'Input not written'**
  String get timelineToolStdinFailed;

  /// No description provided for @timelineToolElapsedUnderSecond.
  ///
  /// In en, this message translates to:
  /// **'Took less than 1s'**
  String get timelineToolElapsedUnderSecond;

  /// No description provided for @timelineToolElapsedSeconds.
  ///
  /// In en, this message translates to:
  /// **'Took {seconds}s'**
  String timelineToolElapsedSeconds(int seconds);

  /// No description provided for @timelineToolElapsedMinutes.
  ///
  /// In en, this message translates to:
  /// **'Took {minutes}m'**
  String timelineToolElapsedMinutes(int minutes);

  /// No description provided for @timelineToolElapsedMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'Took {minutes}m {seconds}s'**
  String timelineToolElapsedMinutesSeconds(int minutes, int seconds);

  /// No description provided for @timelineToolSearchSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get timelineToolSearchSucceeded;

  /// No description provided for @timelineToolSearchRunning.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get timelineToolSearchRunning;

  /// No description provided for @timelineToolSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get timelineToolSearchFailed;

  /// No description provided for @timelineToolAgentSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Spawned subagent'**
  String get timelineToolAgentSucceeded;

  /// No description provided for @timelineToolAgentRunning.
  ///
  /// In en, this message translates to:
  /// **'Subagent running'**
  String get timelineToolAgentRunning;

  /// No description provided for @timelineToolAgentFailed.
  ///
  /// In en, this message translates to:
  /// **'Subagent failed'**
  String get timelineToolAgentFailed;

  /// No description provided for @timelineToolMessageSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Sent message'**
  String get timelineToolMessageSucceeded;

  /// No description provided for @timelineToolMessageRunning.
  ///
  /// In en, this message translates to:
  /// **'Sending message'**
  String get timelineToolMessageRunning;

  /// No description provided for @timelineToolMessageFailed.
  ///
  /// In en, this message translates to:
  /// **'Message not sent'**
  String get timelineToolMessageFailed;

  /// No description provided for @timelineToolCreateSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Created directory'**
  String get timelineToolCreateSucceeded;

  /// No description provided for @timelineToolCreateRunning.
  ///
  /// In en, this message translates to:
  /// **'Creating directory'**
  String get timelineToolCreateRunning;

  /// No description provided for @timelineToolCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Directory not created'**
  String get timelineToolCreateFailed;

  /// No description provided for @timelineToolDeleteSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get timelineToolDeleteSucceeded;

  /// No description provided for @timelineToolDeleteRunning.
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get timelineToolDeleteRunning;

  /// No description provided for @timelineToolDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Not deleted'**
  String get timelineToolDeleteFailed;

  /// No description provided for @timelineToolCopySucceeded.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get timelineToolCopySucceeded;

  /// No description provided for @timelineToolCopyRunning.
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get timelineToolCopyRunning;

  /// No description provided for @timelineToolCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Not copied'**
  String get timelineToolCopyFailed;

  /// No description provided for @timelineToolMoveSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get timelineToolMoveSucceeded;

  /// No description provided for @timelineToolMoveRunning.
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get timelineToolMoveRunning;

  /// No description provided for @timelineToolMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Not moved'**
  String get timelineToolMoveFailed;

  /// No description provided for @timelineToolFetchSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Fetched web page'**
  String get timelineToolFetchSucceeded;

  /// No description provided for @timelineToolFetchRunning.
  ///
  /// In en, this message translates to:
  /// **'Fetching web page'**
  String get timelineToolFetchRunning;

  /// No description provided for @timelineToolFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Web page not fetched'**
  String get timelineToolFetchFailed;

  /// No description provided for @timelineToolPlanSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Updated plan'**
  String get timelineToolPlanSucceeded;

  /// No description provided for @timelineToolPlanRunning.
  ///
  /// In en, this message translates to:
  /// **'Updating plan'**
  String get timelineToolPlanRunning;

  /// No description provided for @timelineToolPlanFailed.
  ///
  /// In en, this message translates to:
  /// **'Plan update failed'**
  String get timelineToolPlanFailed;

  /// No description provided for @timelineToolWorkflowSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Updated workflow'**
  String get timelineToolWorkflowSucceeded;

  /// No description provided for @timelineToolWorkflowRunning.
  ///
  /// In en, this message translates to:
  /// **'Updating workflow'**
  String get timelineToolWorkflowRunning;

  /// No description provided for @timelineToolWorkflowFailed.
  ///
  /// In en, this message translates to:
  /// **'Workflow update failed'**
  String get timelineToolWorkflowFailed;

  /// No description provided for @timelineToolLspSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Queried code'**
  String get timelineToolLspSucceeded;

  /// No description provided for @timelineToolLspRunning.
  ///
  /// In en, this message translates to:
  /// **'Querying code'**
  String get timelineToolLspRunning;

  /// No description provided for @timelineToolLspFailed.
  ///
  /// In en, this message translates to:
  /// **'Code query failed'**
  String get timelineToolLspFailed;

  /// No description provided for @timelineToolWaitSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Waited'**
  String get timelineToolWaitSucceeded;

  /// No description provided for @timelineToolWaitRunning.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get timelineToolWaitRunning;

  /// No description provided for @timelineToolWaitFailed.
  ///
  /// In en, this message translates to:
  /// **'Wait failed'**
  String get timelineToolWaitFailed;

  /// No description provided for @timelineToolCompleted.
  ///
  /// In en, this message translates to:
  /// **'{name} completed'**
  String timelineToolCompleted(String name);

  /// No description provided for @timelineToolFailed.
  ///
  /// In en, this message translates to:
  /// **'{name} failed'**
  String timelineToolFailed(String name);

  /// No description provided for @timelineToolDenied.
  ///
  /// In en, this message translates to:
  /// **'{name} denied'**
  String timelineToolDenied(String name);

  /// No description provided for @timelineToolCancelled.
  ///
  /// In en, this message translates to:
  /// **'{name} cancelled'**
  String timelineToolCancelled(String name);

  /// No description provided for @timelineToolAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'{name} awaiting approval'**
  String timelineToolAwaitingApproval(String name);

  /// No description provided for @timelineToolRunning.
  ///
  /// In en, this message translates to:
  /// **'{name} running'**
  String timelineToolRunning(String name);

  /// No description provided for @timelineToolExitCode.
  ///
  /// In en, this message translates to:
  /// **'exit code {code}'**
  String timelineToolExitCode(int code);

  /// No description provided for @timelineToolTimedOut.
  ///
  /// In en, this message translates to:
  /// **'timed out'**
  String get timelineToolTimedOut;

  /// No description provided for @agentDetailStatusClosing.
  ///
  /// In en, this message translates to:
  /// **'Closing'**
  String get agentDetailStatusClosing;

  /// No description provided for @timelineToolQueued.
  ///
  /// In en, this message translates to:
  /// **'{name} queued'**
  String timelineToolQueued(String name);

  /// No description provided for @timelineToolCancelling.
  ///
  /// In en, this message translates to:
  /// **'{name} cancelling'**
  String timelineToolCancelling(String name);

  /// No description provided for @timelineToolInterrupted.
  ///
  /// In en, this message translates to:
  /// **'{name} interrupted'**
  String timelineToolInterrupted(String name);

  /// No description provided for @timelineAgentSubagent.
  ///
  /// In en, this message translates to:
  /// **'Subagent'**
  String get timelineAgentSubagent;

  /// No description provided for @timelineAgentSubagentMessage.
  ///
  /// In en, this message translates to:
  /// **'Subagent message'**
  String get timelineAgentSubagentMessage;

  /// No description provided for @timelineAgentWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for subagents'**
  String get timelineAgentWaiting;

  /// No description provided for @timelineAgentClose.
  ///
  /// In en, this message translates to:
  /// **'Close subagent'**
  String get timelineAgentClose;

  /// No description provided for @timelineTodoListFallback.
  ///
  /// In en, this message translates to:
  /// **'Todo list'**
  String get timelineTodoListFallback;

  /// No description provided for @timelineTodoPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get timelineTodoPending;

  /// No description provided for @timelineTodoInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get timelineTodoInProgress;

  /// No description provided for @timelineTodoCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get timelineTodoCompleted;

  /// No description provided for @interactionQuestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'A few questions'**
  String get interactionQuestionsTitle;

  /// No description provided for @interactionLastQuestion.
  ///
  /// In en, this message translates to:
  /// **'Last question'**
  String get interactionLastQuestion;

  /// No description provided for @interactionContinueAfterAnswer.
  ///
  /// In en, this message translates to:
  /// **'Continue after answering'**
  String get interactionContinueAfterAnswer;

  /// No description provided for @timelineRolledBack.
  ///
  /// In en, this message translates to:
  /// **'Rolled back from active context'**
  String get timelineRolledBack;

  /// No description provided for @interactionSubmitEmptyAnswersHint.
  ///
  /// In en, this message translates to:
  /// **'Unanswered questions are submitted as empty arrays.'**
  String get interactionSubmitEmptyAnswersHint;

  /// No description provided for @interactionAnsweredPendingHint.
  ///
  /// In en, this message translates to:
  /// **'{answeredCount} answered · {pendingCount} pending'**
  String interactionAnsweredPendingHint(int answeredCount, int pendingCount);

  /// No description provided for @interactionPreviousQuestion.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get interactionPreviousQuestion;

  /// No description provided for @interactionNextQuestion.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get interactionNextQuestion;

  /// No description provided for @interactionSubmitAnswers.
  ///
  /// In en, this message translates to:
  /// **'Submit answers'**
  String get interactionSubmitAnswers;

  /// No description provided for @interactionNeedInputTitle.
  ///
  /// In en, this message translates to:
  /// **'Input needed'**
  String get interactionNeedInputTitle;

  /// No description provided for @interactionAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'anywork will use this answer to continue the current question.'**
  String get interactionAnswerHint;

  /// No description provided for @interactionAnswerButton.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get interactionAnswerButton;

  /// No description provided for @interactionAnswerLabel.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get interactionAnswerLabel;

  /// No description provided for @interactionQuestionProgress.
  ///
  /// In en, this message translates to:
  /// **'Question {current} / {total}'**
  String interactionQuestionProgress(int current, int total);

  /// No description provided for @interactionAnsweredCount.
  ///
  /// In en, this message translates to:
  /// **'{count} answered'**
  String interactionAnsweredCount(int count);

  /// No description provided for @interactionQuestionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Question {index}'**
  String interactionQuestionTooltip(int index);

  /// No description provided for @interactionQuestionFallback.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get interactionQuestionFallback;

  /// No description provided for @interactionOtherLabel.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get interactionOtherLabel;

  /// No description provided for @interactionSecretHint.
  ///
  /// In en, this message translates to:
  /// **'Enter secret answer'**
  String get interactionSecretHint;

  /// No description provided for @interactionTextHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your answer...'**
  String get interactionTextHint;

  /// No description provided for @interactionPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get interactionPermissionTitle;

  /// No description provided for @interactionPermissionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'anywork wants to run a tool call'**
  String get interactionPermissionSubtitle;

  /// No description provided for @interactionPermissionFooterHint.
  ///
  /// In en, this message translates to:
  /// **'The tool runs in the current working directory.'**
  String get interactionPermissionFooterHint;

  /// No description provided for @interactionReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get interactionReject;

  /// No description provided for @interactionApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get interactionApprove;

  /// No description provided for @interactionReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get interactionReasonLabel;

  /// No description provided for @interactionPlanConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm this plan?'**
  String get interactionPlanConfirmTitle;

  /// No description provided for @interactionPlanConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm it, or describe what should change.'**
  String get interactionPlanConfirmSubtitle;

  /// No description provided for @interactionPlanReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Implementation plan ready'**
  String get interactionPlanReadyTitle;

  /// No description provided for @interactionPlanAwaitingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation'**
  String get interactionPlanAwaitingConfirmation;

  /// No description provided for @interactionPlanApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get interactionPlanApproved;

  /// No description provided for @statusPlanEntry.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get statusPlanEntry;

  /// No description provided for @interactionPlanViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View full plan'**
  String get interactionPlanViewDetails;

  /// No description provided for @interactionPlanDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Implementation plan'**
  String get interactionPlanDetailsTitle;

  /// No description provided for @interactionPlanConfirmFooterHint.
  ///
  /// In en, this message translates to:
  /// **'Confirming starts the document-editing checkpoint in {mode} mode.'**
  String interactionPlanConfirmFooterHint(String mode);

  /// No description provided for @interactionPlanAdjust.
  ///
  /// In en, this message translates to:
  /// **'Tell anywork how to adjust'**
  String get interactionPlanAdjust;

  /// No description provided for @interactionPlanConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm and execute'**
  String get interactionPlanConfirmAction;

  /// No description provided for @interactionPlanAdjustHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what should change...'**
  String get interactionPlanAdjustHint;

  /// No description provided for @interactionPlanAdjustSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit changes'**
  String get interactionPlanAdjustSubmit;

  /// No description provided for @interactionPlanFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Enter submits · Shift+Enter adds a line'**
  String get interactionPlanFeedbackHint;

  /// No description provided for @planExpandReading.
  ///
  /// In en, this message translates to:
  /// **'Read full width'**
  String get planExpandReading;

  /// No description provided for @planRestoreSplit.
  ///
  /// In en, this message translates to:
  /// **'Restore side-by-side'**
  String get planRestoreSplit;

  /// No description provided for @planReceiptApproved.
  ///
  /// In en, this message translates to:
  /// **'Plan approved'**
  String get planReceiptApproved;

  /// No description provided for @planReceiptRevisionRequested.
  ///
  /// In en, this message translates to:
  /// **'Plan changes requested'**
  String get planReceiptRevisionRequested;

  /// No description provided for @planReceiptCancelled.
  ///
  /// In en, this message translates to:
  /// **'Plan confirmation cancelled'**
  String get planReceiptCancelled;

  /// No description provided for @planReceiptAnswered.
  ///
  /// In en, this message translates to:
  /// **'Plan confirmation answered'**
  String get planReceiptAnswered;

  /// No description provided for @planReceiptYourReply.
  ///
  /// In en, this message translates to:
  /// **'Your reply'**
  String get planReceiptYourReply;

  /// No description provided for @planReceiptYourFeedback.
  ///
  /// In en, this message translates to:
  /// **'Requested changes'**
  String get planReceiptYourFeedback;

  /// No description provided for @planReceiptApproveReply.
  ///
  /// In en, this message translates to:
  /// **'Approved this plan for execution'**
  String get planReceiptApproveReply;

  /// No description provided for @settingsAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccountsTitle;

  /// No description provided for @settingsAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts, credentials, models, and usage'**
  String get settingsAccountsSubtitle;

  /// No description provided for @settingsRefreshUsage.
  ///
  /// In en, this message translates to:
  /// **'Refresh usage'**
  String get settingsRefreshUsage;

  /// No description provided for @settingsAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get settingsAddAccount;

  /// No description provided for @settingsSearchAccounts.
  ///
  /// In en, this message translates to:
  /// **'Search accounts'**
  String get settingsSearchAccounts;

  /// No description provided for @settingsNoAccountsMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts match this filter'**
  String get settingsNoAccountsMatchTitle;

  /// No description provided for @settingsNoAccountsMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Clear the search to see all configured accounts.'**
  String get settingsNoAccountsMatchMessage;

  /// No description provided for @settingsNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts found'**
  String get settingsNoAccountsTitle;

  /// No description provided for @settingsNoAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add an account to configure credentials and models.'**
  String get settingsNoAccountsMessage;

  /// No description provided for @settingsDefaultAccount.
  ///
  /// In en, this message translates to:
  /// **'Default account'**
  String get settingsDefaultAccount;

  /// No description provided for @settingsSetAsDefaultAccount.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get settingsSetAsDefaultAccount;

  /// No description provided for @settingsOpenDetails.
  ///
  /// In en, this message translates to:
  /// **'Open details'**
  String get settingsOpenDetails;

  /// No description provided for @settingsAccountActions.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get settingsAccountActions;

  /// No description provided for @settingsEditAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get settingsEditAccount;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsNoAccountSelected.
  ///
  /// In en, this message translates to:
  /// **'No account selected'**
  String get settingsNoAccountSelected;

  /// No description provided for @settingsAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountTitle;

  /// No description provided for @settingsAccountModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsAccountModelsTitle;

  /// No description provided for @settingsAccountConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsAccountConnectionTitle;

  /// No description provided for @settingsAccountDefaultModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Default catalog (not yet synced)'**
  String get settingsAccountDefaultModelsTitle;

  /// No description provided for @settingsAccountCustomModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual models'**
  String get settingsAccountCustomModelsTitle;

  /// No description provided for @settingsAccountOnlineModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Online models'**
  String get settingsAccountOnlineModelsTitle;

  /// No description provided for @settingsNewAccount.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get settingsNewAccount;

  /// No description provided for @settingsAccountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get settingsAccountId;

  /// No description provided for @settingsAccountTemplate.
  ///
  /// In en, this message translates to:
  /// **'Account template'**
  String get settingsAccountTemplate;

  /// No description provided for @settingsCustomAccount.
  ///
  /// In en, this message translates to:
  /// **'Custom account'**
  String get settingsCustomAccount;

  /// No description provided for @settingsDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get settingsDefaultModel;

  /// No description provided for @settingsApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get settingsApiKey;

  /// No description provided for @settingsApiKeyKeepCurrent.
  ///
  /// In en, this message translates to:
  /// **'API key (leave blank to keep current)'**
  String get settingsApiKeyKeepCurrent;

  /// No description provided for @settingsConfigured.
  ///
  /// In en, this message translates to:
  /// **'configured'**
  String get settingsConfigured;

  /// No description provided for @settingsMissing.
  ///
  /// In en, this message translates to:
  /// **'missing'**
  String get settingsMissing;

  /// No description provided for @settingsDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get settingsDisplayName;

  /// No description provided for @settingsProtocolType.
  ///
  /// In en, this message translates to:
  /// **'Protocol type'**
  String get settingsProtocolType;

  /// No description provided for @settingsBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get settingsBaseUrl;

  /// No description provided for @settingsModelId.
  ///
  /// In en, this message translates to:
  /// **'Model model_id'**
  String get settingsModelId;

  /// No description provided for @settingsReasoningEfforts.
  ///
  /// In en, this message translates to:
  /// **'Reasoning efforts'**
  String get settingsReasoningEfforts;

  /// No description provided for @settingsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get settingsEdit;

  /// No description provided for @settingsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// No description provided for @settingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// No description provided for @settingsAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get settingsAddModel;

  /// No description provided for @settingsRemoveModel.
  ///
  /// In en, this message translates to:
  /// **'Remove model'**
  String get settingsRemoveModel;

  /// No description provided for @settingsNoCustomModels.
  ///
  /// In en, this message translates to:
  /// **'No manual models'**
  String get settingsNoCustomModels;

  /// No description provided for @settingsNoOnlineModels.
  ///
  /// In en, this message translates to:
  /// **'No online models'**
  String get settingsNoOnlineModels;

  /// No description provided for @settingsNoBundledModels.
  ///
  /// In en, this message translates to:
  /// **'No bundled models'**
  String get settingsNoBundledModels;

  /// No description provided for @settingsModelOriginOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get settingsModelOriginOnline;

  /// No description provided for @settingsModelOriginBundled.
  ///
  /// In en, this message translates to:
  /// **'Bundled'**
  String get settingsModelOriginBundled;

  /// No description provided for @settingsModelOriginManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get settingsModelOriginManual;

  /// No description provided for @settingsRemoveManualModelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this manual model?'**
  String get settingsRemoveManualModelConfirmTitle;

  /// No description provided for @settingsRemoveManualModelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. The model leaves the catalog, and its connection and compact overrides are cleared. History, bills, and session costs stay unchanged.'**
  String get settingsRemoveManualModelConfirmBody;

  /// No description provided for @settingsRemoveManualModelConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsRemoveManualModelConfirmAction;

  /// No description provided for @settingsRemoveManualModelFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete this manual model.'**
  String get settingsRemoveManualModelFailed;

  /// No description provided for @settingsManualModelIdConflict.
  ///
  /// In en, this message translates to:
  /// **'A model with this model_id already exists in the online or bundled catalog.'**
  String get settingsManualModelIdConflict;

  /// No description provided for @settingsBundledModels.
  ///
  /// In en, this message translates to:
  /// **'{count} bundled'**
  String settingsBundledModels(int count);

  /// No description provided for @settingsDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get settingsDefaultBadge;

  /// No description provided for @settingsReadyBadge.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get settingsReadyBadge;

  /// No description provided for @settingsSetupBadge.
  ///
  /// In en, this message translates to:
  /// **'setup'**
  String get settingsSetupBadge;

  /// No description provided for @settingsUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get settingsUsageTitle;

  /// No description provided for @settingsUsageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {updatedAt}'**
  String settingsUsageUpdated(String updatedAt);

  /// No description provided for @settingsUsageAvailableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available balance'**
  String get settingsUsageAvailableBalance;

  /// No description provided for @settingsUsageBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Balance unavailable'**
  String get settingsUsageBalanceUnavailable;

  /// No description provided for @settingsUsageBalanceSufficient.
  ///
  /// In en, this message translates to:
  /// **'Balance sufficient'**
  String get settingsUsageBalanceSufficient;

  /// No description provided for @settingsUsageBalanceInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get settingsUsageBalanceInsufficient;

  /// No description provided for @settingsUsageTotalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total available'**
  String get settingsUsageTotalBalance;

  /// No description provided for @settingsUsageGrantedBalance.
  ///
  /// In en, this message translates to:
  /// **'Granted balance'**
  String get settingsUsageGrantedBalance;

  /// No description provided for @settingsUsageToppedUpBalance.
  ///
  /// In en, this message translates to:
  /// **'Topped-up balance'**
  String get settingsUsageToppedUpBalance;

  /// No description provided for @settingsUsageGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted {amount}'**
  String settingsUsageGranted(String amount);

  /// No description provided for @settingsUsageToppedUp.
  ///
  /// In en, this message translates to:
  /// **'Topped up {amount}'**
  String settingsUsageToppedUp(String amount);

  /// No description provided for @settingsUsageRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing usage...'**
  String get settingsUsageRefreshing;

  /// No description provided for @settingsUsageChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking usage...'**
  String get settingsUsageChecking;

  /// No description provided for @settingsUsageCheckingShort.
  ///
  /// In en, this message translates to:
  /// **'Checking usage'**
  String get settingsUsageCheckingShort;

  /// No description provided for @settingsUsageNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Usage not loaded'**
  String get settingsUsageNotLoaded;

  /// No description provided for @settingsUsageUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get settingsUsageUnsupported;

  /// No description provided for @settingsUsageNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Usage not supported'**
  String get settingsUsageNotSupported;

  /// No description provided for @settingsUsageMissingKey.
  ///
  /// In en, this message translates to:
  /// **'Missing key'**
  String get settingsUsageMissingKey;

  /// No description provided for @settingsUsageFailed.
  ///
  /// In en, this message translates to:
  /// **'Usage failed'**
  String get settingsUsageFailed;

  /// No description provided for @settingsUsageQueryFailed.
  ///
  /// In en, this message translates to:
  /// **'Usage query failed'**
  String get settingsUsageQueryFailed;

  /// No description provided for @settingsUsageApiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Account API key is not configured'**
  String get settingsUsageApiKeyMissing;

  /// No description provided for @settingsUsageUnsupportedForAccount.
  ///
  /// In en, this message translates to:
  /// **'Usage is not supported for {accountName}'**
  String settingsUsageUnsupportedForAccount(String accountName);

  /// No description provided for @settingsUsageNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get settingsUsageNotChecked;

  /// No description provided for @settingsUsageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Usage is unavailable'**
  String get settingsUsageUnavailable;

  /// No description provided for @settingsUsageError.
  ///
  /// In en, this message translates to:
  /// **'Could not load usage'**
  String get settingsUsageError;

  /// No description provided for @settingsUsageNoQuota.
  ///
  /// In en, this message translates to:
  /// **'No quota details returned.'**
  String get settingsUsageNoQuota;

  /// No description provided for @settingsUsageTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingsUsageTools;

  /// No description provided for @settingsUsageToken.
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get settingsUsageToken;

  /// No description provided for @settingsUsageSpend.
  ///
  /// In en, this message translates to:
  /// **'Spend'**
  String get settingsUsageSpend;

  /// No description provided for @settingsUsageRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get settingsUsageRemaining;

  /// No description provided for @settingsUsageUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get settingsUsageUsed;

  /// No description provided for @settingsUsageFiveHourQuota.
  ///
  /// In en, this message translates to:
  /// **'5 hour quota'**
  String get settingsUsageFiveHourQuota;

  /// No description provided for @settingsUsageWeeklyQuota.
  ///
  /// In en, this message translates to:
  /// **'Weekly quota'**
  String get settingsUsageWeeklyQuota;

  /// No description provided for @settingsUsageMcpQuota.
  ///
  /// In en, this message translates to:
  /// **'MCP quota'**
  String get settingsUsageMcpQuota;

  /// No description provided for @settingsUsageQuota.
  ///
  /// In en, this message translates to:
  /// **'Quota'**
  String get settingsUsageQuota;

  /// No description provided for @settingsUsageQuotaRemaining.
  ///
  /// In en, this message translates to:
  /// **'{remaining} of {total} remaining'**
  String settingsUsageQuotaRemaining(String remaining, String total);

  /// No description provided for @settingsUsageQuotaUsed.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total} used'**
  String settingsUsageQuotaUsed(String current, String total);

  /// No description provided for @settingsUsagePercentRemaining.
  ///
  /// In en, this message translates to:
  /// **'{percent} remaining'**
  String settingsUsagePercentRemaining(String percent);

  /// No description provided for @settingsUsageReset.
  ///
  /// In en, this message translates to:
  /// **'Reset {time}'**
  String settingsUsageReset(String time);

  /// No description provided for @settingsInstructionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get settingsInstructionsTitle;

  /// No description provided for @settingsInstructionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Injected into each turn; changes save after typing stops.'**
  String get settingsInstructionsSubtitle;

  /// No description provided for @settingsBaseInstructions.
  ///
  /// In en, this message translates to:
  /// **'Base instructions'**
  String get settingsBaseInstructions;

  /// No description provided for @settingsDeveloperInstructions.
  ///
  /// In en, this message translates to:
  /// **'Developer instructions'**
  String get settingsDeveloperInstructions;

  /// No description provided for @settingsUserContext.
  ///
  /// In en, this message translates to:
  /// **'User context'**
  String get settingsUserContext;

  /// No description provided for @settingsInstructionHint.
  ///
  /// In en, this message translates to:
  /// **'Add project guidance here'**
  String get settingsInstructionHint;

  /// No description provided for @settingsSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get settingsSkillsTitle;

  /// No description provided for @settingsSkillsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disable noisy skills or discover project/user/system catalogs.'**
  String get settingsSkillsSubtitle;

  /// No description provided for @settingsDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get settingsDiscover;

  /// No description provided for @settingsDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Discovering'**
  String get settingsDiscovering;

  /// No description provided for @settingsFilterSkills.
  ///
  /// In en, this message translates to:
  /// **'Filter skills'**
  String get settingsFilterSkills;

  /// No description provided for @settingsOpenProjectToDiscoverSkills.
  ///
  /// In en, this message translates to:
  /// **'Open a project to discover skills'**
  String get settingsOpenProjectToDiscoverSkills;

  /// No description provided for @settingsNoSkillsMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No skills match this filter'**
  String get settingsNoSkillsMatchFilter;

  /// No description provided for @settingsSkillsDiscoverySources.
  ///
  /// In en, this message translates to:
  /// **'Skills are discovered from the selected workspace and configured user/system sources.'**
  String get settingsSkillsDiscoverySources;

  /// No description provided for @settingsClearSearchOrDiscoverAgain.
  ///
  /// In en, this message translates to:
  /// **'Clear the search or run discovery again.'**
  String get settingsClearSearchOrDiscoverAgain;

  /// No description provided for @settingsNoSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'No skills found'**
  String get settingsNoSkillsTitle;

  /// No description provided for @settingsNoSkillsMessage.
  ///
  /// In en, this message translates to:
  /// **'Try another filter or discover skills for this project.'**
  String get settingsNoSkillsMessage;

  /// No description provided for @settingsRoleExplorerDescription.
  ///
  /// In en, this message translates to:
  /// **'Explore code and collect context.'**
  String get settingsRoleExplorerDescription;

  /// No description provided for @settingsRolePlannerDescription.
  ///
  /// In en, this message translates to:
  /// **'Understand requests, plan work, coordinate subagents, integrate and verify results.'**
  String get settingsRolePlannerDescription;

  /// No description provided for @settingsRoleExecutorDescription.
  ///
  /// In en, this message translates to:
  /// **'Apply edits and run tools.'**
  String get settingsRoleExecutorDescription;

  /// No description provided for @settingsRoleWorktreeExecutorDescription.
  ///
  /// In en, this message translates to:
  /// **'Apply edits and run tools in an isolated Git worktree.'**
  String get settingsRoleWorktreeExecutorDescription;

  /// No description provided for @settingsRoleReviewerDescription.
  ///
  /// In en, this message translates to:
  /// **'Review results and verify risk.'**
  String get settingsRoleReviewerDescription;

  /// No description provided for @settingsRoleFallbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Studio role'**
  String get settingsRoleFallbackDescription;

  /// No description provided for @settingsModelField.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsModelField;

  /// No description provided for @settingsMcpTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get settingsMcpTitle;

  /// No description provided for @settingsMcpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Model Context Protocol servers and inline endpoints.'**
  String get settingsMcpSubtitle;

  /// No description provided for @settingsMcpRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsMcpRefresh;

  /// No description provided for @settingsMcpReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get settingsMcpReconnect;

  /// No description provided for @settingsMcpResetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset all'**
  String get settingsMcpResetAll;

  /// No description provided for @settingsMcpResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset all MCP servers?'**
  String get settingsMcpResetConfirmTitle;

  /// No description provided for @settingsMcpResetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every configured MCP connection will be rebuilt. Active turns keep their current leased generation.'**
  String get settingsMcpResetConfirmBody;

  /// No description provided for @settingsMcpResetConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Reset all'**
  String get settingsMcpResetConfirmAction;

  /// No description provided for @settingsEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get settingsEndpoint;

  /// No description provided for @settingsMcpEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers'**
  String get settingsMcpEmptyTitle;

  /// No description provided for @settingsMcpEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Configured MCP servers will appear here.'**
  String get settingsMcpEmptyMessage;

  /// No description provided for @settingsLspTitle.
  ///
  /// In en, this message translates to:
  /// **'Language servers'**
  String get settingsLspTitle;

  /// No description provided for @settingsLspSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last-known project language server status and explicit lifecycle commands.'**
  String get settingsLspSubtitle;

  /// No description provided for @settingsLspRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsLspRefresh;

  /// No description provided for @settingsLspProbe.
  ///
  /// In en, this message translates to:
  /// **'Probe'**
  String get settingsLspProbe;

  /// No description provided for @settingsLspRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get settingsLspRepair;

  /// No description provided for @settingsLspReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsLspReset;

  /// No description provided for @settingsLspResetWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Reset workspace'**
  String get settingsLspResetWorkspace;

  /// No description provided for @settingsLspActivityIndexing.
  ///
  /// In en, this message translates to:
  /// **'Indexing'**
  String get settingsLspActivityIndexing;

  /// No description provided for @settingsLspActivityBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get settingsLspActivityBusy;

  /// No description provided for @settingsLspEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No language servers'**
  String get settingsLspEmptyTitle;

  /// No description provided for @settingsLspEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Activate a supported project to create language server membership.'**
  String get settingsLspEmptyMessage;

  /// No description provided for @settingsSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurityTitle;

  /// No description provided for @settingsSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the default approval posture for this workspace.'**
  String get settingsSecuritySubtitle;

  /// No description provided for @settingsSecurityModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tool execution permission is fixed to full access; workspace and worktree boundaries are not relaxed.'**
  String get settingsSecurityModeSubtitle;

  /// No description provided for @settingsCurrentMode.
  ///
  /// In en, this message translates to:
  /// **'Current: {mode}'**
  String settingsCurrentMode(String mode);

  /// No description provided for @settingsWorkspaceBoundary.
  ///
  /// In en, this message translates to:
  /// **'Workspace boundary policy remains unchanged.'**
  String get settingsWorkspaceBoundary;

  /// No description provided for @settingsGeneralTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralTitle;

  /// No description provided for @settingsGeneralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interface preferences saved into the Studio store.'**
  String get settingsGeneralSubtitle;

  /// No description provided for @settingsFollowActiveTurn.
  ///
  /// In en, this message translates to:
  /// **'Follow active turn'**
  String get settingsFollowActiveTurn;

  /// No description provided for @settingsFollowActiveTurnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep new timeline output pinned to the latest turn.'**
  String get settingsFollowActiveTurnSubtitle;

  /// No description provided for @settingsCompactTimeline.
  ///
  /// In en, this message translates to:
  /// **'Compact timeline'**
  String get settingsCompactTimeline;

  /// No description provided for @settingsCompactTimelineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce message spacing for denser reading.'**
  String get settingsCompactTimelineSubtitle;

  /// No description provided for @settingsWebSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get settingsWebSearchTitle;

  /// No description provided for @settingsWebSearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search through an eligible OpenAI account. Changes apply from the next turn.'**
  String get settingsWebSearchSubtitle;

  /// No description provided for @settingsWebSearchConfiguredMode.
  ///
  /// In en, this message translates to:
  /// **'Configured mode'**
  String get settingsWebSearchConfiguredMode;

  /// No description provided for @settingsWebSearchEffectiveMode.
  ///
  /// In en, this message translates to:
  /// **'Effective mode'**
  String get settingsWebSearchEffectiveMode;

  /// No description provided for @settingsWebSearchAccount.
  ///
  /// In en, this message translates to:
  /// **'OpenAI account'**
  String get settingsWebSearchAccount;

  /// No description provided for @settingsWebSearchModel.
  ///
  /// In en, this message translates to:
  /// **'Search model'**
  String get settingsWebSearchModel;

  /// No description provided for @settingsWebSearchMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get settingsWebSearchMode;

  /// No description provided for @settingsWebSearchModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsWebSearchModeDisabled;

  /// No description provided for @settingsWebSearchModeCached.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get settingsWebSearchModeCached;

  /// No description provided for @settingsWebSearchModeIndexed.
  ///
  /// In en, this message translates to:
  /// **'Indexed'**
  String get settingsWebSearchModeIndexed;

  /// No description provided for @settingsWebSearchModeLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get settingsWebSearchModeLive;

  /// No description provided for @settingsWebSearchContextSize.
  ///
  /// In en, this message translates to:
  /// **'Context size'**
  String get settingsWebSearchContextSize;

  /// No description provided for @settingsWebSearchContextLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get settingsWebSearchContextLow;

  /// No description provided for @settingsWebSearchContextMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get settingsWebSearchContextMedium;

  /// No description provided for @settingsWebSearchContextHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get settingsWebSearchContextHigh;

  /// No description provided for @settingsServiceDefault.
  ///
  /// In en, this message translates to:
  /// **'Service default'**
  String get settingsServiceDefault;

  /// No description provided for @settingsWebSearchAllowedDomains.
  ///
  /// In en, this message translates to:
  /// **'Allowed domains'**
  String get settingsWebSearchAllowedDomains;

  /// No description provided for @settingsWebSearchDomainsHint.
  ///
  /// In en, this message translates to:
  /// **'example.com, docs.example.com'**
  String get settingsWebSearchDomainsHint;

  /// No description provided for @settingsWebSearchCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get settingsWebSearchCountry;

  /// No description provided for @settingsWebSearchRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get settingsWebSearchRegion;

  /// No description provided for @settingsWebSearchCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get settingsWebSearchCity;

  /// No description provided for @settingsWebSearchTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get settingsWebSearchTimezone;

  /// No description provided for @settingsWebSearchAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get settingsWebSearchAvailable;

  /// No description provided for @settingsWebSearchDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsWebSearchDisabled;

  /// No description provided for @settingsWebSearchMissingCredential.
  ///
  /// In en, this message translates to:
  /// **'Missing credential'**
  String get settingsWebSearchMissingCredential;

  /// No description provided for @settingsWebSearchUnsupportedAccount.
  ///
  /// In en, this message translates to:
  /// **'Unsupported account'**
  String get settingsWebSearchUnsupportedAccount;

  /// No description provided for @settingsWebSearchUnsupportedModel.
  ///
  /// In en, this message translates to:
  /// **'Unsupported model'**
  String get settingsWebSearchUnsupportedModel;

  /// No description provided for @settingsWebSearchMissingCredentialReason.
  ///
  /// In en, this message translates to:
  /// **'No credentialed account originating from the OpenAI template is available. Remote web search is fully disabled.'**
  String get settingsWebSearchMissingCredentialReason;

  /// No description provided for @settingsWebSearchUnsupportedAccountReason.
  ///
  /// In en, this message translates to:
  /// **'The current account does not expose this web search backend.'**
  String get settingsWebSearchUnsupportedAccountReason;

  /// No description provided for @settingsWebSearchUnsupportedModelReason.
  ///
  /// In en, this message translates to:
  /// **'The current route cannot expose either the function tool or hosted web search.'**
  String get settingsWebSearchUnsupportedModelReason;

  /// No description provided for @settingsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get settingsNotAvailable;

  /// No description provided for @settingsSaveWebSearch.
  ///
  /// In en, this message translates to:
  /// **'Save web search'**
  String get settingsSaveWebSearch;

  /// No description provided for @settingsWebSearchUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved search settings'**
  String get settingsWebSearchUnsaved;

  /// No description provided for @settingsDeepSeekWebSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek native web search'**
  String get settingsDeepSeekWebSearchTitle;

  /// No description provided for @settingsDeepSeekWebSearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Other available web search is tried first; DeepSeek web search is used only as a billed fallback when other search is unconfigured, unavailable, or fails. Search and fetch are billed per request.'**
  String get settingsDeepSeekWebSearchSubtitle;

  /// No description provided for @settingsDeepSeekWebSearchAccount.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek account'**
  String get settingsDeepSeekWebSearchAccount;

  /// No description provided for @settingsDeepSeekWebSearchConfigured.
  ///
  /// In en, this message translates to:
  /// **'Search configured'**
  String get settingsDeepSeekWebSearchConfigured;

  /// No description provided for @settingsDeepSeekWebSearchEffective.
  ///
  /// In en, this message translates to:
  /// **'Search effective'**
  String get settingsDeepSeekWebSearchEffective;

  /// No description provided for @settingsDeepSeekWebSearchEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsDeepSeekWebSearchEnabled;

  /// No description provided for @settingsDeepSeekWebSearchEnableLabel.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get settingsDeepSeekWebSearchEnableLabel;

  /// No description provided for @settingsDeepSeekWebFetchEnableLabel.
  ///
  /// In en, this message translates to:
  /// **'Page fetch'**
  String get settingsDeepSeekWebFetchEnableLabel;

  /// No description provided for @settingsDeepSeekWebFetchConfigured.
  ///
  /// In en, this message translates to:
  /// **'Fetch configured'**
  String get settingsDeepSeekWebFetchConfigured;

  /// No description provided for @settingsDeepSeekWebFetchEffective.
  ///
  /// In en, this message translates to:
  /// **'Fetch effective'**
  String get settingsDeepSeekWebFetchEffective;

  /// No description provided for @settingsStudioUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'anywork update'**
  String get settingsStudioUpdateTitle;

  /// No description provided for @settingsStudioUpdateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Version {version}. Automatic checks run only in Windows release builds.'**
  String settingsStudioUpdateDisabled(String version);

  /// No description provided for @settingsStudioUpdateCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current version: {version}'**
  String settingsStudioUpdateCurrent(String version);

  /// No description provided for @settingsStudioUpdateChecking.
  ///
  /// In en, this message translates to:
  /// **'Version {version}. Checking for updates...'**
  String settingsStudioUpdateChecking(String version);

  /// No description provided for @settingsStudioUpdateLatest.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is up to date.'**
  String settingsStudioUpdateLatest(String version);

  /// No description provided for @settingsStudioUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {current} is installed. Version {latest} is available.'**
  String settingsStudioUpdateAvailable(String current, String latest);

  /// No description provided for @settingsStudioUpdateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading version {version}: {progress}%'**
  String settingsStudioUpdateDownloading(String version, int progress);

  /// No description provided for @settingsStudioUpdateVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying version {version}...'**
  String settingsStudioUpdateVerifying(String version);

  /// No description provided for @settingsStudioUpdateInstallerLaunched.
  ///
  /// In en, this message translates to:
  /// **'Installer for version {version} started.'**
  String settingsStudioUpdateInstallerLaunched(String version);

  /// No description provided for @settingsStudioUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String settingsStudioUpdateFailed(String error);

  /// No description provided for @settingsStudioUpdatePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing update…'**
  String get settingsStudioUpdatePreparing;

  /// No description provided for @settingsStudioUpdateWhenReady.
  ///
  /// In en, this message translates to:
  /// **'Install and restart when ready'**
  String get settingsStudioUpdateWhenReady;

  /// No description provided for @settingsStudioUpdateCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling update…'**
  String get settingsStudioUpdateCancelling;

  /// No description provided for @settingsStudioUpdateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Update cancelled. You can retry anytime.'**
  String get settingsStudioUpdateCancelled;

  /// No description provided for @settingsStudioUpdateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsStudioUpdateCheck;

  /// No description provided for @settingsStudioUpdateInstall.
  ///
  /// In en, this message translates to:
  /// **'Download, install and restart'**
  String get settingsStudioUpdateInstall;

  /// No description provided for @settingsStudioUpdateRestart.
  ///
  /// In en, this message translates to:
  /// **'Install and restart'**
  String get settingsStudioUpdateRestart;

  /// No description provided for @settingsStudioUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is downloaded and will install when you close anywork.'**
  String settingsStudioUpdateReady(String version);

  /// No description provided for @settingsStudioUpdateReleaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get settingsStudioUpdateReleaseNotes;

  /// No description provided for @timelineWebSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get timelineWebSearchTitle;

  /// No description provided for @timelineWebSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching the web'**
  String get timelineWebSearchSearching;

  /// No description provided for @timelineWebSearchOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening a web page'**
  String get timelineWebSearchOpening;

  /// No description provided for @timelineWebSearchFinding.
  ///
  /// In en, this message translates to:
  /// **'Finding text on a page'**
  String get timelineWebSearchFinding;

  /// No description provided for @timelineWebSearchSearched.
  ///
  /// In en, this message translates to:
  /// **'Searched the web'**
  String get timelineWebSearchSearched;

  /// No description provided for @timelineWebSearchOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened a web page'**
  String get timelineWebSearchOpened;

  /// No description provided for @timelineWebSearchFound.
  ///
  /// In en, this message translates to:
  /// **'Searched page text'**
  String get timelineWebSearchFound;

  /// No description provided for @timelineWebSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Web search failed'**
  String get timelineWebSearchFailed;

  /// No description provided for @timelineWebSearchOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open a web page'**
  String get timelineWebSearchOpenFailed;

  /// No description provided for @timelineWebSearchFindFailed.
  ///
  /// In en, this message translates to:
  /// **'Page search failed'**
  String get timelineWebSearchFindFailed;

  /// No description provided for @timelineWebSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Result links'**
  String get timelineWebSearchResults;

  /// No description provided for @timelineLspQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'LSP query'**
  String get timelineLspQueryTitle;

  /// No description provided for @timelineLspQueryTitleWithDetail.
  ///
  /// In en, this message translates to:
  /// **'LSP query · {detail}'**
  String timelineLspQueryTitleWithDetail(String detail);

  /// No description provided for @timelineLspCapabilitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'LSP capabilities'**
  String get timelineLspCapabilitiesTitle;

  /// No description provided for @modalityText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get modalityText;

  /// No description provided for @modalityImage.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get modalityImage;

  /// No description provided for @modalityAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get modalityAudio;

  /// No description provided for @modalityVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get modalityVideo;

  /// No description provided for @modalityFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get modalityFile;

  /// No description provided for @composerAddUrlTitle.
  ///
  /// In en, this message translates to:
  /// **'Add URL'**
  String get composerAddUrlTitle;

  /// No description provided for @composerAddUrlConfirm.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get composerAddUrlConfirm;

  /// No description provided for @composerAttachmentAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get composerAttachmentAddTooltip;

  /// No description provided for @composerAttachmentHandlingHint.
  ///
  /// In en, this message translates to:
  /// **'Handled directly when supported by the model, otherwise as workspace files'**
  String get composerAttachmentHandlingHint;

  /// No description provided for @composerAttachmentPickLocal.
  ///
  /// In en, this message translates to:
  /// **'Choose local files'**
  String get composerAttachmentPickLocal;

  /// No description provided for @composerAttachmentRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get composerAttachmentRemoveTooltip;

  /// No description provided for @settingsModelOutputCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Outputs: {capabilities}'**
  String settingsModelOutputCapabilities(String capabilities);

  /// No description provided for @settingsAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent Profiles'**
  String get settingsAgentsTitle;

  /// No description provided for @settingsAgentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable and configure subagents by purpose; directory mode restricts built-in file writes, not OS access.'**
  String get settingsAgentsSubtitle;

  /// No description provided for @settingsAgentsAddUserProfile.
  ///
  /// In en, this message translates to:
  /// **'Add user profile'**
  String get settingsAgentsAddUserProfile;

  /// No description provided for @settingsAgentsEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get settingsAgentsEditTooltip;

  /// No description provided for @settingsAgentsRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get settingsAgentsRecoveryTitle;

  /// No description provided for @settingsWorktreeBase.
  ///
  /// In en, this message translates to:
  /// **'base {commit}'**
  String settingsWorktreeBase(String commit);

  /// No description provided for @settingsWorktreeHead.
  ///
  /// In en, this message translates to:
  /// **'head {commit}'**
  String settingsWorktreeHead(String commit);

  /// No description provided for @settingsWorktreeHeadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'head unavailable'**
  String get settingsWorktreeHeadUnavailable;

  /// No description provided for @settingsWorktreeChangedFiles.
  ///
  /// In en, this message translates to:
  /// **'Changed files: {files}'**
  String settingsWorktreeChangedFiles(String files);

  /// No description provided for @settingsWorktreeCleanup.
  ///
  /// In en, this message translates to:
  /// **'Clean up worktree and branch'**
  String get settingsWorktreeCleanup;

  /// No description provided for @settingsWorktreeOwnerSession.
  ///
  /// In en, this message translates to:
  /// **'Session worktree'**
  String get settingsWorktreeOwnerSession;

  /// No description provided for @settingsWorktreeOwnerChild.
  ///
  /// In en, this message translates to:
  /// **'Child agent worktree'**
  String get settingsWorktreeOwnerChild;

  /// No description provided for @settingsAgentProfileAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add user agent profile'**
  String get settingsAgentProfileAddTitle;

  /// No description provided for @settingsAgentProfileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit user agent profile'**
  String get settingsAgentProfileEditTitle;

  /// No description provided for @settingsAgentProfileIdField.
  ///
  /// In en, this message translates to:
  /// **'Agent ID'**
  String get settingsAgentProfileIdField;

  /// No description provided for @settingsAgentProfileDisplayNameField.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get settingsAgentProfileDisplayNameField;

  /// No description provided for @settingsAgentProfileDescriptionField.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get settingsAgentProfileDescriptionField;

  /// No description provided for @settingsAgentProfileWhenToUseField.
  ///
  /// In en, this message translates to:
  /// **'Best for'**
  String get settingsAgentProfileWhenToUseField;

  /// No description provided for @settingsAgentProfileInstructionsField.
  ///
  /// In en, this message translates to:
  /// **'System instructions'**
  String get settingsAgentProfileInstructionsField;

  /// No description provided for @settingsAgentProfileAccountField.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAgentProfileAccountField;

  /// No description provided for @settingsAgentProfileEffortDefault.
  ///
  /// In en, this message translates to:
  /// **'Use model default'**
  String get settingsAgentProfileEffortDefault;

  /// No description provided for @settingsAgentProfileWorkspaceModeField.
  ///
  /// In en, this message translates to:
  /// **'Workspace mode'**
  String get settingsAgentProfileWorkspaceModeField;

  /// No description provided for @settingsAgentWorkspaceModeUnrestricted.
  ///
  /// In en, this message translates to:
  /// **'Unrestricted'**
  String get settingsAgentWorkspaceModeUnrestricted;

  /// No description provided for @settingsAgentWorkspaceModeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get settingsAgentWorkspaceModeDirectory;

  /// No description provided for @settingsAgentWorkspaceModeWorktree.
  ///
  /// In en, this message translates to:
  /// **'Worktree'**
  String get settingsAgentWorkspaceModeWorktree;

  /// No description provided for @settingsAgentWorkspaceModeReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get settingsAgentWorkspaceModeReview;

  /// No description provided for @settingsAgentProfileWorkspaceDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'Directory mode limits built-in file writes to the project only; it is not an OS sandbox, and shell, Git, and MCP can still bypass it.'**
  String get settingsAgentProfileWorkspaceDirectoryHint;

  /// No description provided for @settingsAgentProfileWorkspaceReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Review mode requires the reviewed agent ID at dispatch time and adopts that agent\'s workspace and boundary; system instructions keep it review-only.'**
  String get settingsAgentProfileWorkspaceReviewHint;

  /// No description provided for @settingsAgentProfileEnabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsAgentProfileEnabledTitle;

  /// No description provided for @settingsAgentProfileEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disabled profiles keep their TOML file but no longer appear in the agent tool catalog.'**
  String get settingsAgentProfileEnabledSubtitle;

  /// No description provided for @settingsAgentProfileSave.
  ///
  /// In en, this message translates to:
  /// **'Save TOML atomically'**
  String get settingsAgentProfileSave;

  /// No description provided for @settingsAgentProfileRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get settingsAgentProfileRequired;

  /// No description provided for @settingsServiceCapabilitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Service capabilities'**
  String get settingsServiceCapabilitiesTitle;

  /// No description provided for @settingsCapabilitySourceField.
  ///
  /// In en, this message translates to:
  /// **'Capability source'**
  String get settingsCapabilitySourceField;

  /// No description provided for @settingsCapabilitySourceTemplate.
  ///
  /// In en, this message translates to:
  /// **'Follow template defaults'**
  String get settingsCapabilitySourceTemplate;

  /// No description provided for @settingsCapabilitySourceExplicit.
  ///
  /// In en, this message translates to:
  /// **'Explicit override'**
  String get settingsCapabilitySourceExplicit;

  /// No description provided for @settingsHostedWebSearchField.
  ///
  /// In en, this message translates to:
  /// **'Hosted Web Search'**
  String get settingsHostedWebSearchField;

  /// No description provided for @settingsHostedWebSearchDialectField.
  ///
  /// In en, this message translates to:
  /// **'Hosted Web Search dialect'**
  String get settingsHostedWebSearchDialectField;

  /// No description provided for @settingsStandaloneWebSearchField.
  ///
  /// In en, this message translates to:
  /// **'Standalone Web Search'**
  String get settingsStandaloneWebSearchField;

  /// No description provided for @settingsProgrammaticToolCallingField.
  ///
  /// In en, this message translates to:
  /// **'Programmatic Tool Calling'**
  String get settingsProgrammaticToolCallingField;

  /// No description provided for @settingsCapabilityEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsCapabilityEnabled;

  /// No description provided for @settingsCapabilityDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsCapabilityDisabled;

  /// No description provided for @settingsDefaultConnectionField.
  ///
  /// In en, this message translates to:
  /// **'Default connection'**
  String get settingsDefaultConnectionField;

  /// No description provided for @settingsCurrentConnectionField.
  ///
  /// In en, this message translates to:
  /// **'Current connection'**
  String get settingsCurrentConnectionField;

  /// No description provided for @settingsSupportedConnectionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Supported connections'**
  String get settingsSupportedConnectionsLabel;

  /// No description provided for @settingsAgentRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'System agent model routing'**
  String get settingsAgentRoutesTitle;

  /// No description provided for @settingsStateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get settingsStateChecking;

  /// No description provided for @settingsStateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get settingsStateAvailable;

  /// No description provided for @settingsStateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsStateUnavailable;

  /// No description provided for @settingsStateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsStateDisabled;

  /// No description provided for @settingsMcpStateMissingCredential.
  ///
  /// In en, this message translates to:
  /// **'Missing credential'**
  String get settingsMcpStateMissingCredential;

  /// No description provided for @settingsLspActivityIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get settingsLspActivityIdle;

  /// No description provided for @roleExplorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get roleExplorer;

  /// No description provided for @rolePlanner.
  ///
  /// In en, this message translates to:
  /// **'Main agent'**
  String get rolePlanner;

  /// No description provided for @roleExecutor.
  ///
  /// In en, this message translates to:
  /// **'Executor'**
  String get roleExecutor;

  /// No description provided for @roleWorktreeExecutor.
  ///
  /// In en, this message translates to:
  /// **'Worktree executor'**
  String get roleWorktreeExecutor;

  /// No description provided for @roleReviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get roleReviewer;

  /// No description provided for @roleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get roleEmpty;

  /// No description provided for @settingsPricingEnabled.
  ///
  /// In en, this message translates to:
  /// **'Estimate token cost'**
  String get settingsPricingEnabled;

  /// No description provided for @settingsPricingHelp.
  ///
  /// In en, this message translates to:
  /// **'Controls in-app cost estimates; token and cache statistics remain available. Plans default to off.'**
  String get settingsPricingHelp;

  /// No description provided for @settingsModelAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Optional model settings'**
  String get settingsModelAdvanced;

  /// No description provided for @settingsContextBudget.
  ///
  /// In en, this message translates to:
  /// **'Context budget (tokens)'**
  String get settingsContextBudget;

  /// No description provided for @settingsOutputBudget.
  ///
  /// In en, this message translates to:
  /// **'Maximum output (tokens)'**
  String get settingsOutputBudget;

  /// No description provided for @settingsModelAutoCompactTitle.
  ///
  /// In en, this message translates to:
  /// **'Context compaction threshold'**
  String get settingsModelAutoCompactTitle;

  /// No description provided for @settingsModelAutoCompactRestore.
  ///
  /// In en, this message translates to:
  /// **'Reset to automatic'**
  String get settingsModelAutoCompactRestore;

  /// No description provided for @settingsModelAutoCompactSaving.
  ///
  /// In en, this message translates to:
  /// **'Applying automatically…'**
  String get settingsModelAutoCompactSaving;

  /// No description provided for @settingsModelAutoCompactSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply. Your input is kept.'**
  String get settingsModelAutoCompactSaveFailed;

  /// No description provided for @settingsModelAutoCompactRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsModelAutoCompactRetry;

  /// No description provided for @settingsModelAutoCompactOverrideLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get settingsModelAutoCompactOverrideLabel;

  /// No description provided for @settingsModelAutoCompactEffectiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Effective'**
  String get settingsModelAutoCompactEffectiveLabel;

  /// No description provided for @settingsModelAutoCompactUsingDefault.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get settingsModelAutoCompactUsingDefault;

  /// No description provided for @settingsModelAutoCompactInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Threshold (tokens)'**
  String get settingsModelAutoCompactInputLabel;

  /// No description provided for @settingsModelAutoCompactInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive integer token count.'**
  String get settingsModelAutoCompactInvalid;

  /// No description provided for @settingsModelAutoCompactHelp.
  ///
  /// In en, this message translates to:
  /// **'The effective threshold is capped at 90% of the context window and reserves the maximum output budget.'**
  String get settingsModelAutoCompactHelp;

  /// No description provided for @settingsModelAutoCompactUnknownCapacity.
  ///
  /// In en, this message translates to:
  /// **'Context capacity is unknown, so an automatic compaction threshold cannot be calculated.'**
  String get settingsModelAutoCompactUnknownCapacity;

  /// No description provided for @settingsPriceInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get settingsPriceInput;

  /// No description provided for @settingsPriceOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get settingsPriceOutput;

  /// No description provided for @settingsPriceCacheRead.
  ///
  /// In en, this message translates to:
  /// **'Cache read'**
  String get settingsPriceCacheRead;

  /// No description provided for @settingsPriceCacheWrite.
  ///
  /// In en, this message translates to:
  /// **'Cache write'**
  String get settingsPriceCacheWrite;

  /// No description provided for @settingsSystemAgentsGroup.
  ///
  /// In en, this message translates to:
  /// **'System subagents'**
  String get settingsSystemAgentsGroup;

  /// No description provided for @settingsUserAgentsGroup.
  ///
  /// In en, this message translates to:
  /// **'User subagents'**
  String get settingsUserAgentsGroup;

  /// No description provided for @settingsAppearanceGroup.
  ///
  /// In en, this message translates to:
  /// **'Appearance & conversation'**
  String get settingsAppearanceGroup;

  /// No description provided for @settingsNetworkGroup.
  ///
  /// In en, this message translates to:
  /// **'Search & network'**
  String get settingsNetworkGroup;

  /// No description provided for @settingsUpdatesGroup.
  ///
  /// In en, this message translates to:
  /// **'Application updates'**
  String get settingsUpdatesGroup;

  /// No description provided for @settingsModelsGroup.
  ///
  /// In en, this message translates to:
  /// **'Models & agents'**
  String get settingsModelsGroup;

  /// No description provided for @settingsExtensionsGroup.
  ///
  /// In en, this message translates to:
  /// **'Tools & services'**
  String get settingsExtensionsGroup;

  /// No description provided for @settingsPreferencesGroup.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesGroup;

  /// No description provided for @settingsFilterAgents.
  ///
  /// In en, this message translates to:
  /// **'Filter agents'**
  String get settingsFilterAgents;

  /// No description provided for @timelineToolArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get timelineToolArguments;

  /// No description provided for @timelineToolOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get timelineToolOutput;

  /// No description provided for @costPurposeMain.
  ///
  /// In en, this message translates to:
  /// **'Main conversation'**
  String get costPurposeMain;

  /// No description provided for @costPurposeSummary.
  ///
  /// In en, this message translates to:
  /// **'Summarization'**
  String get costPurposeSummary;

  /// No description provided for @costPurposeReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get costPurposeReview;

  /// No description provided for @costPurposeTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get costPurposeTitle;

  /// No description provided for @costPurposeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown purpose'**
  String get costPurposeUnknown;

  /// No description provided for @timelineRawRecord.
  ///
  /// In en, this message translates to:
  /// **'Original history record'**
  String get timelineRawRecord;

  /// No description provided for @sidebarSearch.
  ///
  /// In en, this message translates to:
  /// **'Search projects and sessions'**
  String get sidebarSearch;

  /// No description provided for @sidebarAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get sidebarAll;

  /// No description provided for @sidebarRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get sidebarRunning;

  /// No description provided for @sidebarAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get sidebarAttention;

  /// No description provided for @sidebarAddProject.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get sidebarAddProject;

  /// No description provided for @sidebarLocalProject.
  ///
  /// In en, this message translates to:
  /// **'Local project'**
  String get sidebarLocalProject;

  /// No description provided for @sidebarLocalHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder on this computer'**
  String get sidebarLocalHint;

  /// No description provided for @sidebarRemoteProject.
  ///
  /// In en, this message translates to:
  /// **'Remote project'**
  String get sidebarRemoteProject;

  /// No description provided for @sidebarRemoteHint.
  ///
  /// In en, this message translates to:
  /// **'Connect to a remote folder over SSH'**
  String get sidebarRemoteHint;

  /// No description provided for @sidebarContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get sidebarContinue;

  /// No description provided for @sidebarBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get sidebarBack;

  /// No description provided for @sidebarConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect and choose folder'**
  String get sidebarConnect;

  /// No description provided for @sidebarSaveConnect.
  ///
  /// In en, this message translates to:
  /// **'Save and connect'**
  String get sidebarSaveConnect;

  /// No description provided for @sidebarSearchConnections.
  ///
  /// In en, this message translates to:
  /// **'Search configured connections'**
  String get sidebarSearchConnections;

  /// No description provided for @sidebarNoConnections.
  ///
  /// In en, this message translates to:
  /// **'No remote connections yet'**
  String get sidebarNoConnections;

  /// No description provided for @sidebarNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New remote connection'**
  String get sidebarNewConnection;

  /// No description provided for @sidebarNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching projects or sessions'**
  String get sidebarNoResults;

  /// No description provided for @sidebarEmptyProject.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet. Use + on this project to start'**
  String get sidebarEmptyProject;

  /// No description provided for @sidebarEarlier.
  ///
  /// In en, this message translates to:
  /// **'Show earlier sessions'**
  String get sidebarEarlier;

  /// No description provided for @sidebarArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get sidebarArchived;

  /// No description provided for @sidebarRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore session'**
  String get sidebarRestore;

  /// No description provided for @sidebarPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get sidebarPin;

  /// No description provided for @sidebarUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get sidebarUnpin;

  /// No description provided for @sidebarNavigation.
  ///
  /// In en, this message translates to:
  /// **'Project navigation'**
  String get sidebarNavigation;

  /// No description provided for @sidebarResize.
  ///
  /// In en, this message translates to:
  /// **'Resize sidebar; use arrows, Home to reset'**
  String get sidebarResize;

  /// No description provided for @planResize.
  ///
  /// In en, this message translates to:
  /// **'Resize plan details; use arrows, Home to reset'**
  String get planResize;

  /// No description provided for @sidebarLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get sidebarLocal;

  /// No description provided for @sidebarDetailUpdatedNow.
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get sidebarDetailUpdatedNow;

  /// No description provided for @sidebarDetailUpdatedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 minute ago} other{Updated {count} minutes ago}}'**
  String sidebarDetailUpdatedMinutesAgo(int count);

  /// No description provided for @sidebarDetailUpdatedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 hour ago} other{Updated {count} hours ago}}'**
  String sidebarDetailUpdatedHoursAgo(int count);

  /// No description provided for @sidebarDetailUpdatedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 day ago} other{Updated {count} days ago}}'**
  String sidebarDetailUpdatedDaysAgo(int count);

  /// No description provided for @sidebarNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get sidebarNotChecked;

  /// No description provided for @sidebarConnectionSaved.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved; connection failed. Edit or retry'**
  String get sidebarConnectionSaved;

  /// No description provided for @sidebarCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get sidebarCopyPath;

  /// No description provided for @sidebarRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get sidebarRetry;

  /// No description provided for @settingsSshRemoteHelper.
  ///
  /// In en, this message translates to:
  /// **'helper'**
  String get settingsSshRemoteHelper;

  /// No description provided for @statusThroughputValue.
  ///
  /// In en, this message translates to:
  /// **'{value} t/s'**
  String statusThroughputValue(String value);

  /// No description provided for @statusThroughputUnavailable.
  ///
  /// In en, this message translates to:
  /// **'- t/s'**
  String get statusThroughputUnavailable;

  /// No description provided for @workflowStatePlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get workflowStatePlanning;

  /// No description provided for @workflowStateEditingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Editing docs'**
  String get workflowStateEditingDocuments;

  /// No description provided for @workflowStateWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get workflowStateWorking;

  /// No description provided for @workflowStateIntegrating.
  ///
  /// In en, this message translates to:
  /// **'Integrating'**
  String get workflowStateIntegrating;

  /// No description provided for @workflowStateReviewing.
  ///
  /// In en, this message translates to:
  /// **'Reviewing'**
  String get workflowStateReviewing;

  /// No description provided for @workflowStateCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workflowStateCompleted;

  /// No description provided for @workflowStateStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get workflowStateStopped;

  /// No description provided for @workflowModeSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get workflowModeSimple;

  /// No description provided for @workflowModeTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get workflowModeTask;

  /// No description provided for @attachmentFallback.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachmentFallback;

  /// No description provided for @timelineAgentTimedOut.
  ///
  /// In en, this message translates to:
  /// **'timed out'**
  String get timelineAgentTimedOut;

  /// No description provided for @timelineToolUnknownStatus.
  ///
  /// In en, this message translates to:
  /// **'{name} · {status}'**
  String timelineToolUnknownStatus(String name, String status);

  /// No description provided for @timelineTodoStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get timelineTodoStatusUnknown;

  /// No description provided for @settingsApiKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'API key (optional)'**
  String get settingsApiKeyOptional;

  /// No description provided for @modelProtocolResponses.
  ///
  /// In en, this message translates to:
  /// **'Responses'**
  String get modelProtocolResponses;

  /// No description provided for @modelProtocolChatCompletions.
  ///
  /// In en, this message translates to:
  /// **'Chat Completions'**
  String get modelProtocolChatCompletions;

  /// No description provided for @modelConnectionWebSocket.
  ///
  /// In en, this message translates to:
  /// **'WS'**
  String get modelConnectionWebSocket;

  /// No description provided for @modelConnectionHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get modelConnectionHttp;

  /// No description provided for @settingsProtocolChatCompletionsHttp.
  ///
  /// In en, this message translates to:
  /// **'Chat Completions (HTTP)'**
  String get settingsProtocolChatCompletionsHttp;

  /// No description provided for @settingsProtocolResponsesHttp.
  ///
  /// In en, this message translates to:
  /// **'Responses (HTTP)'**
  String get settingsProtocolResponsesHttp;

  /// No description provided for @settingsAgentRouteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{route} (unavailable)'**
  String settingsAgentRouteUnavailable(String route);

  /// No description provided for @settingsPriceTierUnit.
  ///
  /// In en, this message translates to:
  /// **'{currency} per 1M tokens'**
  String settingsPriceTierUnit(String currency);

  /// No description provided for @threadStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get threadStatusIdle;

  /// No description provided for @threadStatusCancelling.
  ///
  /// In en, this message translates to:
  /// **'Stopping current execution'**
  String get threadStatusCancelling;

  /// No description provided for @threadStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get threadStatusClosed;

  /// No description provided for @toolStatusAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get toolStatusAwaitingApproval;

  /// No description provided for @toolStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get toolStatusFailed;

  /// No description provided for @toolStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get toolStatusDenied;

  /// No description provided for @toolStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get toolStatusCancelled;

  /// No description provided for @toolStatusCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get toolStatusCancelling;

  /// No description provided for @settingsAccountCatalogUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Account catalog is unavailable.'**
  String get settingsAccountCatalogUnavailable;

  /// No description provided for @settingsAccountTemplateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Account template is unavailable.'**
  String get settingsAccountTemplateUnavailable;

  /// No description provided for @settingsAccountMissingCredential.
  ///
  /// In en, this message translates to:
  /// **'Missing credential'**
  String get settingsAccountMissingCredential;

  /// No description provided for @settingsSshStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get settingsSshStateDisconnected;

  /// No description provided for @settingsSshStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get settingsSshStateConnecting;

  /// No description provided for @settingsSshStateWaitingForInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get settingsSshStateWaitingForInput;

  /// No description provided for @settingsSshStateReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get settingsSshStateReconnecting;

  /// No description provided for @settingsSshStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsSshStateFailed;

  /// No description provided for @settingsWorktreeStatePrepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared'**
  String get settingsWorktreeStatePrepared;

  /// No description provided for @settingsWorktreeStateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsWorktreeStateActive;

  /// No description provided for @settingsWorktreeStatePreserved.
  ///
  /// In en, this message translates to:
  /// **'Preserved'**
  String get settingsWorktreeStatePreserved;

  /// No description provided for @settingsWorktreeStateCleanupRequested.
  ///
  /// In en, this message translates to:
  /// **'Cleanup requested'**
  String get settingsWorktreeStateCleanupRequested;

  /// No description provided for @settingsWorktreeStateCleaned.
  ///
  /// In en, this message translates to:
  /// **'Cleaned'**
  String get settingsWorktreeStateCleaned;

  /// No description provided for @settingsWorktreeDirty.
  ///
  /// In en, this message translates to:
  /// **'dirty'**
  String get settingsWorktreeDirty;

  /// No description provided for @startupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing application…'**
  String get startupPreparing;

  /// No description provided for @startupStorage.
  ///
  /// In en, this message translates to:
  /// **'Opening local data…'**
  String get startupStorage;

  /// No description provided for @startupConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Loading configuration…'**
  String get startupConfiguration;

  /// No description provided for @startupProjects.
  ///
  /// In en, this message translates to:
  /// **'Loading projects…'**
  String get startupProjects;

  /// No description provided for @startupResources.
  ///
  /// In en, this message translates to:
  /// **'Preparing skill resources…'**
  String get startupResources;

  /// No description provided for @startupState.
  ///
  /// In en, this message translates to:
  /// **'Loading workspace…'**
  String get startupState;

  /// No description provided for @workspaceLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading conversation history…'**
  String get workspaceLoading;

  /// No description provided for @recoveryChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking conversation history and workspaces…'**
  String get recoveryChecking;

  /// No description provided for @recoveryCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversation and workspace check did not complete'**
  String get recoveryCheckFailed;

  /// No description provided for @agentRoleRetired.
  ///
  /// In en, this message translates to:
  /// **'This subagent role has been retired. History is read-only.'**
  String get agentRoleRetired;

  /// No description provided for @conversationActivityPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get conversationActivityPreparing;

  /// No description provided for @conversationActivityRunningTool.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get conversationActivityRunningTool;

  /// No description provided for @conversationActivitySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get conversationActivitySaveFailed;

  /// No description provided for @conversationActivitySavePaused.
  ///
  /// In en, this message translates to:
  /// **'Saving paused'**
  String get conversationActivitySavePaused;

  /// No description provided for @conversationActivityStoragePressure.
  ///
  /// In en, this message translates to:
  /// **'Storage pressure'**
  String get conversationActivityStoragePressure;

  /// No description provided for @conversationActivityResumeReady.
  ///
  /// In en, this message translates to:
  /// **'Saved, waiting to resume'**
  String get conversationActivityResumeReady;

  /// No description provided for @conversationActivityResumeRequired.
  ///
  /// In en, this message translates to:
  /// **'Waiting for save recovery'**
  String get conversationActivityResumeRequired;

  /// No description provided for @conversationActivityStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get conversationActivityStopping;

  /// No description provided for @startupWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for initialization steps…'**
  String get startupWaiting;

  /// No description provided for @startupClosing.
  ///
  /// In en, this message translates to:
  /// **'Closing local data…'**
  String get startupClosing;

  /// No description provided for @startupBackingUp.
  ///
  /// In en, this message translates to:
  /// **'Backing up unrecoverable data…'**
  String get startupBackingUp;

  /// No description provided for @startupResetting.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding initial settings…'**
  String get startupResetting;

  /// No description provided for @startupServices.
  ///
  /// In en, this message translates to:
  /// **'Starting services…'**
  String get startupServices;

  /// No description provided for @startupRecoveredNotice.
  ///
  /// In en, this message translates to:
  /// **'Unrecoverable data was backed up and initial settings restored. Backup location:'**
  String get startupRecoveredNotice;

  /// No description provided for @settingsModelCatalogDefault.
  ///
  /// In en, this message translates to:
  /// **'Bundled models'**
  String get settingsModelCatalogDefault;

  /// No description provided for @settingsModelCatalogCached.
  ///
  /// In en, this message translates to:
  /// **'Last successful model list'**
  String get settingsModelCatalogCached;

  /// No description provided for @settingsModelCatalogOnline.
  ///
  /// In en, this message translates to:
  /// **'Models from this account'**
  String get settingsModelCatalogOnline;

  /// No description provided for @settingsModelCatalogChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked'**
  String get settingsModelCatalogChecked;

  /// No description provided for @settingsModelCatalogFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup model sync failed. The current list is still available.'**
  String get settingsModelCatalogFailed;

  /// No description provided for @settingsModelCatalogCacheWarning.
  ///
  /// In en, this message translates to:
  /// **'The saved model list could not be loaded. Showing bundled models.'**
  String get settingsModelCatalogCacheWarning;

  /// No description provided for @settingsModelCatalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'This account has no models.'**
  String get settingsModelCatalogEmpty;

  /// No description provided for @settingsModelCatalogRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Restart the app to sync again.'**
  String get settingsModelCatalogRestartHint;

  /// No description provided for @timelineActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Thinking and tools'**
  String get timelineActivityTitle;

  /// No description provided for @timelineContextCompacted.
  ///
  /// In en, this message translates to:
  /// **'Context compacted'**
  String get timelineContextCompacted;

  /// No description provided for @timelineCompactionDetail.
  ///
  /// In en, this message translates to:
  /// **'Before: {before}; after: {after} tokens'**
  String timelineCompactionDetail(int before, int after);

  /// No description provided for @timelineUserInputAnswered.
  ///
  /// In en, this message translates to:
  /// **'You answered'**
  String get timelineUserInputAnswered;

  /// No description provided for @timelineUserInputAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Awaiting your answer'**
  String get timelineUserInputAwaiting;

  /// No description provided for @timelineUserInputCancelled.
  ///
  /// In en, this message translates to:
  /// **'Questions cancelled'**
  String get timelineUserInputCancelled;

  /// No description provided for @timelineUserInputQuestionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 question} other{{count} questions}}'**
  String timelineUserInputQuestionCount(int count);

  /// No description provided for @timelineUserInputYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get timelineUserInputYourAnswer;

  /// No description provided for @timelineUserInputNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer provided'**
  String get timelineUserInputNoAnswer;

  /// No description provided for @timelineUserInputSecretHidden.
  ///
  /// In en, this message translates to:
  /// **'Sensitive answer hidden'**
  String get timelineUserInputSecretHidden;

  /// No description provided for @settingsModelParametersUnknown.
  ///
  /// In en, this message translates to:
  /// **'Model parameters unknown'**
  String get settingsModelParametersUnknown;

  /// No description provided for @settingsModelPriceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Price unknown'**
  String get settingsModelPriceUnknown;

  /// No description provided for @modelTextFilterExcluded.
  ///
  /// In en, this message translates to:
  /// **'{model}: excluded from text models ({reasons})'**
  String modelTextFilterExcluded(String model, String reasons);

  /// No description provided for @modelTextInputUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Text input unsupported'**
  String get modelTextInputUnsupported;

  /// No description provided for @modelTextOutputUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Text output unsupported'**
  String get modelTextOutputUnsupported;

  /// No description provided for @modelContextWindowUnknown.
  ///
  /// In en, this message translates to:
  /// **'Context window unknown'**
  String get modelContextWindowUnknown;

  /// No description provided for @modelTextFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching text models. Check model parameters in account settings.'**
  String get modelTextFilterEmpty;

  /// No description provided for @modeEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Work modes'**
  String get modeEditorTitle;

  /// No description provided for @modeEditorNewMode.
  ///
  /// In en, this message translates to:
  /// **'New mode'**
  String get modeEditorNewMode;

  /// No description provided for @modeEditorImportJson.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get modeEditorImportJson;

  /// No description provided for @modeEditorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Find name or id'**
  String get modeEditorSearchHint;

  /// No description provided for @modeEditorBuiltInGroup.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get modeEditorBuiltInGroup;

  /// No description provided for @modeEditorMyModesGroup.
  ///
  /// In en, this message translates to:
  /// **'My modes'**
  String get modeEditorMyModesGroup;

  /// No description provided for @modeEditorNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching work modes.'**
  String get modeEditorNoMatches;

  /// No description provided for @modeEditorCatalogReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Built-in modes are read-only. Duplicate one to customize stages.'**
  String get modeEditorCatalogReadOnlyHint;

  /// No description provided for @modeEditorReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get modeEditorReadOnly;

  /// No description provided for @modeEditorUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get modeEditorUnsaved;

  /// No description provided for @modeEditorUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get modeEditorUndo;

  /// No description provided for @modeEditorRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get modeEditorRedo;

  /// No description provided for @modeEditorReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get modeEditorReload;

  /// No description provided for @modeEditorDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get modeEditorDuplicate;

  /// No description provided for @modeEditorDeleteMode.
  ///
  /// In en, this message translates to:
  /// **'Delete mode'**
  String get modeEditorDeleteMode;

  /// No description provided for @modeEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get modeEditorSave;

  /// No description provided for @modeEditorTabFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get modeEditorTabFlow;

  /// No description provided for @modeEditorTabJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get modeEditorTabJson;

  /// No description provided for @modeEditorTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get modeEditorTabSettings;

  /// No description provided for @modeEditorTabPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get modeEditorTabPreview;

  /// No description provided for @modeEditorDraftUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Draft unsaved'**
  String get modeEditorDraftUnsaved;

  /// No description provided for @modeEditorSelectOrCreate.
  ///
  /// In en, this message translates to:
  /// **'Select or create a work mode.'**
  String get modeEditorSelectOrCreate;

  /// No description provided for @modeEditorOpenNotice.
  ///
  /// In en, this message translates to:
  /// **'Opened {id}'**
  String modeEditorOpenNotice(String id);

  /// No description provided for @modeEditorSaveValidationIssues.
  ///
  /// In en, this message translates to:
  /// **'Validation found {count} issues before save.'**
  String modeEditorSaveValidationIssues(int count);

  /// No description provided for @modeEditorPreSaveValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Pre-save validation failed: {error}'**
  String modeEditorPreSaveValidationFailed(String error);

  /// No description provided for @modeEditorSaved.
  ///
  /// In en, this message translates to:
  /// **'Mode saved. Changes apply from the next turn.'**
  String get modeEditorSaved;

  /// No description provided for @modeEditorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed.'**
  String get modeEditorSaveFailed;

  /// No description provided for @modeEditorReloaded.
  ///
  /// In en, this message translates to:
  /// **'Mode definition reloaded.'**
  String get modeEditorReloaded;

  /// No description provided for @modeEditorReloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Reload failed.'**
  String get modeEditorReloadFailed;

  /// No description provided for @modeEditorDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed.'**
  String get modeEditorDeleteFailed;

  /// No description provided for @modeEditorDeleted.
  ///
  /// In en, this message translates to:
  /// **'Mode deleted; thread history is kept.'**
  String get modeEditorDeleted;

  /// No description provided for @modeEditorCopySuffix.
  ///
  /// In en, this message translates to:
  /// **'copy'**
  String get modeEditorCopySuffix;

  /// No description provided for @modeEditorCopyCreated.
  ///
  /// In en, this message translates to:
  /// **'Copy created as a draft; save to publish it.'**
  String get modeEditorCopyCreated;

  /// No description provided for @modeEditorDraftCreated.
  ///
  /// In en, this message translates to:
  /// **'Draft created. Save after validation.'**
  String get modeEditorDraftCreated;

  /// No description provided for @modeEditorImportReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read mode JSON: {error}'**
  String modeEditorImportReadFailed(String error);

  /// No description provided for @modeEditorImportObjectRequired.
  ///
  /// In en, this message translates to:
  /// **'Mode JSON must be an object.'**
  String get modeEditorImportObjectRequired;

  /// No description provided for @modeEditorInvalidModeId.
  ///
  /// In en, this message translates to:
  /// **'Mode id must look like mode.example.'**
  String get modeEditorInvalidModeId;

  /// No description provided for @modeEditorBuiltInCannotOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Built-in modes cannot be overwritten.'**
  String get modeEditorBuiltInCannotOverwrite;

  /// No description provided for @modeEditorImportedDraft.
  ///
  /// In en, this message translates to:
  /// **'Configuration loaded as a draft; save to publish it.'**
  String get modeEditorImportedDraft;

  /// No description provided for @modeEditorJsonCopied.
  ///
  /// In en, this message translates to:
  /// **'Mode JSON copied.'**
  String get modeEditorJsonCopied;

  /// No description provided for @modeEditorSchemaReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read schema: {error}'**
  String modeEditorSchemaReadFailed(String error);

  /// No description provided for @modeEditorValidationPassed.
  ///
  /// In en, this message translates to:
  /// **'Validation passed.'**
  String get modeEditorValidationPassed;

  /// No description provided for @modeEditorIssuesFound.
  ///
  /// In en, this message translates to:
  /// **'{count} issues found.'**
  String modeEditorIssuesFound(int count);

  /// No description provided for @modeEditorValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Validation failed: {error}'**
  String modeEditorValidationFailed(String error);

  /// No description provided for @modeEditorJsonApplied.
  ///
  /// In en, this message translates to:
  /// **'JSON applied to the draft.'**
  String get modeEditorJsonApplied;

  /// No description provided for @modeEditorJsonApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'JSON could not be applied.'**
  String get modeEditorJsonApplyFailed;

  /// No description provided for @modeEditorJsonApplyFix.
  ///
  /// In en, this message translates to:
  /// **'JSON could not be applied; fix the syntax or fields.'**
  String get modeEditorJsonApplyFix;

  /// No description provided for @modeEditorPreviewReasonDefault.
  ///
  /// In en, this message translates to:
  /// **'Manually confirm stage completion and guard'**
  String get modeEditorPreviewReasonDefault;

  /// No description provided for @modeEditorPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Preview failed: {error}'**
  String modeEditorPreviewFailed(String error);

  /// No description provided for @modeEditorMaxStates.
  ///
  /// In en, this message translates to:
  /// **'At most {count} states are supported.'**
  String modeEditorMaxStates(int count);

  /// No description provided for @modeEditorNewFinalState.
  ///
  /// In en, this message translates to:
  /// **'New final state'**
  String get modeEditorNewFinalState;

  /// No description provided for @modeEditorNewStage.
  ///
  /// In en, this message translates to:
  /// **'New work stage'**
  String get modeEditorNewStage;

  /// No description provided for @modeEditorFinalStateAdded.
  ///
  /// In en, this message translates to:
  /// **'Final state added. Add an incoming path.'**
  String get modeEditorFinalStateAdded;

  /// No description provided for @modeEditorStageAdded.
  ///
  /// In en, this message translates to:
  /// **'Stage added. Add incoming and outgoing transitions.'**
  String get modeEditorStageAdded;

  /// No description provided for @modeEditorContinueGuardPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Continue when the guard is satisfied.'**
  String get modeEditorContinueGuardPlaceholder;

  /// No description provided for @modeEditorTransitionAdded.
  ///
  /// In en, this message translates to:
  /// **'Transition added. Complete its guard.'**
  String get modeEditorTransitionAdded;

  /// No description provided for @modeEditorNeedTwoStates.
  ///
  /// In en, this message translates to:
  /// **'Add at least two states before creating a transition.'**
  String get modeEditorNeedTwoStates;

  /// No description provided for @modeEditorLayoutReset.
  ///
  /// In en, this message translates to:
  /// **'Layout reset. The workflow definition is unchanged.'**
  String get modeEditorLayoutReset;

  /// No description provided for @modeEditorWorkflowEnabled.
  ///
  /// In en, this message translates to:
  /// **'Workflow enabled.'**
  String get modeEditorWorkflowEnabled;

  /// No description provided for @modeEditorWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get modeEditorWorkflow;

  /// No description provided for @modeEditorWorkflowGoalText.
  ///
  /// In en, this message translates to:
  /// **'Complete the task in stages with a reviewable path.'**
  String get modeEditorWorkflowGoalText;

  /// No description provided for @modeEditorStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get modeEditorStart;

  /// No description provided for @modeEditorStageInstructionsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Describe the work for this stage.'**
  String get modeEditorStageInstructionsPlaceholder;

  /// No description provided for @modeEditorStageCriterionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'This stage goal is satisfied.'**
  String get modeEditorStageCriterionPlaceholder;

  /// No description provided for @modeEditorDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get modeEditorDone;

  /// No description provided for @modeEditorTransitionGuardPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'The result satisfies the goal.'**
  String get modeEditorTransitionGuardPlaceholder;

  /// No description provided for @modeEditorPromptDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe this mode responsibilities, sequence, and boundaries.'**
  String get modeEditorPromptDescription;

  /// No description provided for @modeEditorPortIn.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get modeEditorPortIn;

  /// No description provided for @modeEditorPortOut.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get modeEditorPortOut;

  /// No description provided for @modeEditorGuardRequiredShort.
  ///
  /// In en, this message translates to:
  /// **'Guard required'**
  String get modeEditorGuardRequiredShort;

  /// No description provided for @modeEditorDuplicateTransition.
  ///
  /// In en, this message translates to:
  /// **'A transition between those states already exists.'**
  String get modeEditorDuplicateTransition;

  /// No description provided for @modeEditorInitialBadge.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get modeEditorInitialBadge;

  /// No description provided for @modeEditorStageAction.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get modeEditorStageAction;

  /// No description provided for @modeEditorFinalLabel.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get modeEditorFinalLabel;

  /// No description provided for @modeEditorTransitionAction.
  ///
  /// In en, this message translates to:
  /// **'Transition'**
  String get modeEditorTransitionAction;

  /// No description provided for @modeEditorValidate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get modeEditorValidate;

  /// No description provided for @modeEditorAutoLayout.
  ///
  /// In en, this message translates to:
  /// **'Auto layout'**
  String get modeEditorAutoLayout;

  /// No description provided for @modeEditorZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get modeEditorZoomOut;

  /// No description provided for @modeEditorZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get modeEditorZoomIn;

  /// No description provided for @modeEditorFitView.
  ///
  /// In en, this message translates to:
  /// **'Fit view'**
  String get modeEditorFitView;

  /// No description provided for @modeEditorFlowInspector.
  ///
  /// In en, this message translates to:
  /// **'Flow inspector'**
  String get modeEditorFlowInspector;

  /// No description provided for @modeEditorNoWorkflow.
  ///
  /// In en, this message translates to:
  /// **'This mode has no workflow'**
  String get modeEditorNoWorkflow;

  /// No description provided for @modeEditorNoWorkflowReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Duplicate this mode to add stages and transitions.'**
  String get modeEditorNoWorkflowReadOnlyHint;

  /// No description provided for @modeEditorNoWorkflowEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Enabling a workflow adds a starting stage and a final state.'**
  String get modeEditorNoWorkflowEnableHint;

  /// No description provided for @modeEditorEnableWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Enable workflow'**
  String get modeEditorEnableWorkflow;

  /// No description provided for @modeEditorUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved draft'**
  String get modeEditorUnsavedTitle;

  /// No description provided for @modeEditorUnsavedBody.
  ///
  /// In en, this message translates to:
  /// **'Save the current changes before continuing, or discard this draft.'**
  String get modeEditorUnsavedBody;

  /// No description provided for @modeEditorCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get modeEditorCancel;

  /// No description provided for @modeEditorDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get modeEditorDiscard;

  /// No description provided for @modeEditorSaveAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get modeEditorSaveAndContinue;

  /// No description provided for @modeEditorNewWorkMode.
  ///
  /// In en, this message translates to:
  /// **'New work mode'**
  String get modeEditorNewWorkMode;

  /// No description provided for @modeEditorModeName.
  ///
  /// In en, this message translates to:
  /// **'Mode name'**
  String get modeEditorModeName;

  /// No description provided for @modeEditorModeNameHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Research'**
  String get modeEditorModeNameHint;

  /// No description provided for @modeEditorModeNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a mode name.'**
  String get modeEditorModeNameRequired;

  /// No description provided for @modeEditorModeId.
  ///
  /// In en, this message translates to:
  /// **'Mode id'**
  String get modeEditorModeId;

  /// No description provided for @modeEditorModeIdFormat.
  ///
  /// In en, this message translates to:
  /// **'Use the form mode.example with lowercase letters, digits, - and _.'**
  String get modeEditorModeIdFormat;

  /// No description provided for @modeEditorModeIdExists.
  ///
  /// In en, this message translates to:
  /// **'That mode id already exists.'**
  String get modeEditorModeIdExists;

  /// No description provided for @modeEditorStartingPoint.
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get modeEditorStartingPoint;

  /// No description provided for @modeEditorMinimalWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Minimal workflow'**
  String get modeEditorMinimalWorkflow;

  /// No description provided for @modeEditorNoWorkflowTemplate.
  ///
  /// In en, this message translates to:
  /// **'No workflow'**
  String get modeEditorNoWorkflowTemplate;

  /// No description provided for @modeEditorCreateMode.
  ///
  /// In en, this message translates to:
  /// **'Create mode'**
  String get modeEditorCreateMode;

  /// No description provided for @modeEditorImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import mode JSON'**
  String get modeEditorImportDialogTitle;

  /// No description provided for @modeEditorImportDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Paste mode JSON. Built-in modes stay read-only; an existing custom id opens as an unsaved draft.'**
  String get modeEditorImportDialogBody;

  /// No description provided for @modeEditorLoadAsDraft.
  ///
  /// In en, this message translates to:
  /// **'Load as draft'**
  String get modeEditorLoadAsDraft;

  /// No description provided for @modeEditorSchemaDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Mode JSON schema'**
  String get modeEditorSchemaDialogTitle;

  /// No description provided for @modeEditorClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get modeEditorClose;

  /// No description provided for @modeEditorDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this work mode?'**
  String get modeEditorDeleteDialogTitle;

  /// No description provided for @modeEditorDeleteDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Remove the \"{displayName}\" definition. Thread history is kept.'**
  String modeEditorDeleteDialogBody(String displayName);

  /// No description provided for @modeEditorConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get modeEditorConfirmDelete;

  /// No description provided for @modeEditorRemoveStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this state?'**
  String get modeEditorRemoveStateTitle;

  /// No description provided for @modeEditorRemoveStateBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and its {transitionCount} related transitions. Undo can restore it.'**
  String modeEditorRemoveStateBody(String title, int transitionCount);

  /// No description provided for @modeEditorDeleteState.
  ///
  /// In en, this message translates to:
  /// **'Delete state'**
  String get modeEditorDeleteState;

  /// No description provided for @modeEditorRemoveWorkflowTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove workflow?'**
  String get modeEditorRemoveWorkflowTitle;

  /// No description provided for @modeEditorRemoveWorkflowBody.
  ///
  /// In en, this message translates to:
  /// **'The mode can still chat, but stage graph and workflow tools are removed. Undo is available before saving.'**
  String get modeEditorRemoveWorkflowBody;

  /// No description provided for @modeEditorRemoveWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Remove workflow'**
  String get modeEditorRemoveWorkflow;

  /// No description provided for @modeEditorStateIdInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use lowercase letters, digits, - and _ only.'**
  String get modeEditorStateIdInvalid;

  /// No description provided for @modeEditorStateIdExists.
  ///
  /// In en, this message translates to:
  /// **'That state id exists.'**
  String get modeEditorStateIdExists;

  /// No description provided for @modeEditorRenameStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename state id'**
  String get modeEditorRenameStateTitle;

  /// No description provided for @modeEditorStateId.
  ///
  /// In en, this message translates to:
  /// **'State id'**
  String get modeEditorStateId;

  /// No description provided for @modeEditorApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get modeEditorApply;

  /// No description provided for @modeEditorAddTransition.
  ///
  /// In en, this message translates to:
  /// **'Add transition'**
  String get modeEditorAddTransition;

  /// No description provided for @modeEditorSourceState.
  ///
  /// In en, this message translates to:
  /// **'Source state'**
  String get modeEditorSourceState;

  /// No description provided for @modeEditorChooseSource.
  ///
  /// In en, this message translates to:
  /// **'Choose a source.'**
  String get modeEditorChooseSource;

  /// No description provided for @modeEditorTargetState.
  ///
  /// In en, this message translates to:
  /// **'Target state'**
  String get modeEditorTargetState;

  /// No description provided for @modeEditorChooseTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose a target.'**
  String get modeEditorChooseTarget;

  /// No description provided for @modeEditorTransitionGuard.
  ///
  /// In en, this message translates to:
  /// **'Transition guard'**
  String get modeEditorTransitionGuard;

  /// No description provided for @modeEditorTransitionGuardHint.
  ///
  /// In en, this message translates to:
  /// **'For example: after the user confirms scope'**
  String get modeEditorTransitionGuardHint;

  /// No description provided for @modeEditorGuardRequiredField.
  ///
  /// In en, this message translates to:
  /// **'Enter a guard.'**
  String get modeEditorGuardRequiredField;

  /// No description provided for @modeEditorCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get modeEditorCollapse;

  /// No description provided for @modeEditorNoWorkflowPeriod.
  ///
  /// In en, this message translates to:
  /// **'This mode has no workflow.'**
  String get modeEditorNoWorkflowPeriod;

  /// No description provided for @modeEditorInspectorSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select a stage or transition on the canvas to edit its fields.'**
  String get modeEditorInspectorSelectHint;

  /// No description provided for @modeEditorRenameId.
  ///
  /// In en, this message translates to:
  /// **'Rename id'**
  String get modeEditorRenameId;

  /// No description provided for @modeEditorStageTitle.
  ///
  /// In en, this message translates to:
  /// **'Stage title'**
  String get modeEditorStageTitle;

  /// No description provided for @modeEditorStageKind.
  ///
  /// In en, this message translates to:
  /// **'Stage kind'**
  String get modeEditorStageKind;

  /// No description provided for @modeEditorAtomicStage.
  ///
  /// In en, this message translates to:
  /// **'Atomic stage'**
  String get modeEditorAtomicStage;

  /// No description provided for @modeEditorFinalState.
  ///
  /// In en, this message translates to:
  /// **'Final state'**
  String get modeEditorFinalState;

  /// No description provided for @modeEditorInitialStateSwitch.
  ///
  /// In en, this message translates to:
  /// **'Initial state'**
  String get modeEditorInitialStateSwitch;

  /// No description provided for @modeEditorInitialStateLockedHint.
  ///
  /// In en, this message translates to:
  /// **'The workflow always keeps one initial state; enable another stage instead.'**
  String get modeEditorInitialStateLockedHint;

  /// No description provided for @modeEditorInitialStateHint.
  ///
  /// In en, this message translates to:
  /// **'A run starts from this stage.'**
  String get modeEditorInitialStateHint;

  /// No description provided for @modeEditorStageInstructions.
  ///
  /// In en, this message translates to:
  /// **'Stage instructions'**
  String get modeEditorStageInstructions;

  /// No description provided for @modeEditorCompletionCriteria.
  ///
  /// In en, this message translates to:
  /// **'Completion criteria (one per line)'**
  String get modeEditorCompletionCriteria;

  /// No description provided for @modeEditorAtomicCriteriaRequired.
  ///
  /// In en, this message translates to:
  /// **'An atomic stage needs at least one completion criterion; Rust validates on save.'**
  String get modeEditorAtomicCriteriaRequired;

  /// No description provided for @modeEditorOutgoingTransitions.
  ///
  /// In en, this message translates to:
  /// **'Outgoing transitions'**
  String get modeEditorOutgoingTransitions;

  /// No description provided for @modeEditorAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get modeEditorAdd;

  /// No description provided for @modeEditorNoOutgoing.
  ///
  /// In en, this message translates to:
  /// **'No outgoing transitions.'**
  String get modeEditorNoOutgoing;

  /// No description provided for @modeEditorDeleteTransition.
  ///
  /// In en, this message translates to:
  /// **'Delete transition'**
  String get modeEditorDeleteTransition;

  /// No description provided for @modeEditorStateTransition.
  ///
  /// In en, this message translates to:
  /// **'State transition'**
  String get modeEditorStateTransition;

  /// No description provided for @modeEditorTransitionRuleHint.
  ///
  /// In en, this message translates to:
  /// **'One transition per source/target pair; multiple successors, self loops and cycles are allowed.'**
  String get modeEditorTransitionRuleHint;

  /// No description provided for @modeEditorValidationIssuesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} issues'**
  String modeEditorValidationIssuesCount(int count);

  /// No description provided for @modeEditorNotValidated.
  ///
  /// In en, this message translates to:
  /// **'Not validated'**
  String get modeEditorNotValidated;

  /// No description provided for @modeEditorApplyJson.
  ///
  /// In en, this message translates to:
  /// **'Apply JSON'**
  String get modeEditorApplyJson;

  /// No description provided for @modeEditorCopyJson.
  ///
  /// In en, this message translates to:
  /// **'Copy JSON'**
  String get modeEditorCopyJson;

  /// No description provided for @modeEditorSchemaLabel.
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get modeEditorSchemaLabel;

  /// No description provided for @modeEditorReadOnlyCopyHint.
  ///
  /// In en, this message translates to:
  /// **'Read-only: copy or validate'**
  String get modeEditorReadOnlyCopyHint;

  /// No description provided for @modeEditorJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Mode JSON keeps the six top-level fields plus editor layout.'**
  String get modeEditorJsonHint;

  /// No description provided for @modeEditorModeSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Mode settings'**
  String get modeEditorModeSettingsTitle;

  /// No description provided for @modeEditorModeSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Execution definition and editor layout are stored separately; layout never changes workflow identity.'**
  String get modeEditorModeSettingsSubtitle;

  /// No description provided for @modeEditorDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get modeEditorDisplayName;

  /// No description provided for @modeEditorDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get modeEditorDescription;

  /// No description provided for @modeEditorOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get modeEditorOrder;

  /// No description provided for @modeEditorRawPrompt.
  ///
  /// In en, this message translates to:
  /// **'Raw prompt'**
  String get modeEditorRawPrompt;

  /// No description provided for @modeEditorRawPromptHelper.
  ///
  /// In en, this message translates to:
  /// **'This is the full mode prompt injected without GUI rewriting.'**
  String get modeEditorRawPromptHelper;

  /// No description provided for @modeEditorWorkflowTitle.
  ///
  /// In en, this message translates to:
  /// **'Workflow title'**
  String get modeEditorWorkflowTitle;

  /// No description provided for @modeEditorWorkflowGoal.
  ///
  /// In en, this message translates to:
  /// **'Workflow goal'**
  String get modeEditorWorkflowGoal;

  /// No description provided for @modeEditorInitialStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial state'**
  String get modeEditorInitialStateLabel;

  /// No description provided for @modeEditorWorkflowSummary.
  ///
  /// In en, this message translates to:
  /// **'{states} states · {transitions} transitions'**
  String modeEditorWorkflowSummary(int states, int transitions);

  /// No description provided for @modeEditorNoWorkflowToolHint.
  ///
  /// In en, this message translates to:
  /// **'Without a workflow there is no stage graph or workflow tools.'**
  String get modeEditorNoWorkflowToolHint;

  /// No description provided for @modeEditorPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This mode has no workflow to preview.'**
  String get modeEditorPreviewUnavailable;

  /// No description provided for @modeEditorRunPreview.
  ///
  /// In en, this message translates to:
  /// **'Run preview'**
  String get modeEditorRunPreview;

  /// No description provided for @modeEditorPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bounded replay uses the production Rust state machine; it never rewrites the configured initial state.'**
  String get modeEditorPreviewSubtitle;

  /// No description provided for @modeEditorStartPreview.
  ///
  /// In en, this message translates to:
  /// **'Start preview'**
  String get modeEditorStartPreview;

  /// No description provided for @modeEditorRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get modeEditorRestart;

  /// No description provided for @modeEditorTransitionReason.
  ///
  /// In en, this message translates to:
  /// **'Transition reason'**
  String get modeEditorTransitionReason;

  /// No description provided for @modeEditorTransitionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Manually confirm stage completion and guard'**
  String get modeEditorTransitionReasonHint;

  /// No description provided for @modeEditorTransitionReasonHelper.
  ///
  /// In en, this message translates to:
  /// **'Sent as the reason when advancing to a successor.'**
  String get modeEditorTransitionReasonHelper;

  /// No description provided for @modeEditorAllowedNextStates.
  ///
  /// In en, this message translates to:
  /// **'Allowed next states · {count}'**
  String modeEditorAllowedNextStates(int count);

  /// No description provided for @modeEditorTerminalReached.
  ///
  /// In en, this message translates to:
  /// **'Reached a final state. Restarting never rewrites the saved initial state.'**
  String get modeEditorTerminalReached;

  /// No description provided for @modeEditorPreviewIntroText.
  ///
  /// In en, this message translates to:
  /// **'Preview starts from the current JSON document. Each step follows one valid transition from the current state and keeps the path in this preview.'**
  String get modeEditorPreviewIntroText;

  /// No description provided for @modeEditorPreviewAccepted.
  ///
  /// In en, this message translates to:
  /// **'Preview accepted.'**
  String get modeEditorPreviewAccepted;

  /// No description provided for @modeEditorPreviewRejected.
  ///
  /// In en, this message translates to:
  /// **'Preview rejected.'**
  String get modeEditorPreviewRejected;

  /// No description provided for @modeEditorCurrentStage.
  ///
  /// In en, this message translates to:
  /// **'Current stage'**
  String get modeEditorCurrentStage;

  /// No description provided for @modeEditorPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get modeEditorPath;

  /// No description provided for @modeEditorAdvance.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get modeEditorAdvance;

  /// No description provided for @modeEditorPreviewHistory.
  ///
  /// In en, this message translates to:
  /// **'Preview history'**
  String get modeEditorPreviewHistory;

  /// No description provided for @modeDeletedUsingSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Deleted mode · using saved snapshot'**
  String get modeDeletedUsingSnapshot;

  /// No description provided for @modeDeletedChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'This mode was deleted. Choose another mode.'**
  String get modeDeletedChooseAnother;

  /// No description provided for @modeSnapshotBadge.
  ///
  /// In en, this message translates to:
  /// **'Snapshot'**
  String get modeSnapshotBadge;

  /// No description provided for @modeDeletedBadge.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get modeDeletedBadge;

  /// No description provided for @settingsAccountProtocol.
  ///
  /// In en, this message translates to:
  /// **'Account protocol'**
  String get settingsAccountProtocol;

  /// No description provided for @statisticsGroupTotal.
  ///
  /// In en, this message translates to:
  /// **'Group total'**
  String get statisticsGroupTotal;

  /// No description provided for @statisticsAllEfforts.
  ///
  /// In en, this message translates to:
  /// **'All effort levels'**
  String get statisticsAllEfforts;

  /// No description provided for @statisticsEffortBreakdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Effort breakdown'**
  String get statisticsEffortBreakdownTitle;

  /// No description provided for @accountProtocolOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI'**
  String get accountProtocolOpenAi;

  /// No description provided for @accountProtocolDeepSeek.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek'**
  String get accountProtocolDeepSeek;

  /// No description provided for @accountProtocolZhipu.
  ///
  /// In en, this message translates to:
  /// **'Zhipu'**
  String get accountProtocolZhipu;

  /// No description provided for @accountProtocolMiMo.
  ///
  /// In en, this message translates to:
  /// **'MiMo'**
  String get accountProtocolMiMo;

  /// No description provided for @accountProtocolXai.
  ///
  /// In en, this message translates to:
  /// **'xAI'**
  String get accountProtocolXai;

  /// No description provided for @accountProtocolCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom (OpenAI compatible)'**
  String get accountProtocolCustom;

  /// No description provided for @timelineWaitToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for tools'**
  String get timelineWaitToolsTitle;

  /// No description provided for @timelineWaitMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a subagent or new message'**
  String get timelineWaitMessagesTitle;

  /// No description provided for @timelineWaitTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get timelineWaitTimerTitle;

  /// No description provided for @timelineWaitTimerElapsed.
  ///
  /// In en, this message translates to:
  /// **'Timer elapsed'**
  String get timelineWaitTimerElapsed;

  /// No description provided for @timelineWaitReady.
  ///
  /// In en, this message translates to:
  /// **'A waited source is ready'**
  String get timelineWaitReady;

  /// No description provided for @timelineWaitMessagesReady.
  ///
  /// In en, this message translates to:
  /// **'A new message arrived'**
  String get timelineWaitMessagesReady;

  /// No description provided for @timelineWaitTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Wait timed out'**
  String get timelineWaitTimedOut;

  /// No description provided for @timelineWaitCancelled.
  ///
  /// In en, this message translates to:
  /// **'Wait cancelled'**
  String get timelineWaitCancelled;

  /// No description provided for @timelineWaitFailed.
  ///
  /// In en, this message translates to:
  /// **'Wait failed'**
  String get timelineWaitFailed;

  /// No description provided for @timelineWaitInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Wait interrupted'**
  String get timelineWaitInterrupted;

  /// No description provided for @timelineWaitTargetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String timelineWaitTargetCount(int count);

  /// No description provided for @timelineWaitMessageSource.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get timelineWaitMessageSource;

  /// No description provided for @timelineWaitMaxDuration.
  ///
  /// In en, this message translates to:
  /// **'up to {duration}'**
  String timelineWaitMaxDuration(String duration);

  /// No description provided for @timelineWaitTimerDuration.
  ///
  /// In en, this message translates to:
  /// **'{duration}'**
  String timelineWaitTimerDuration(String duration);

  /// No description provided for @timelineWaitMessagesMayWake.
  ///
  /// In en, this message translates to:
  /// **'A new message can wake this wait early'**
  String get timelineWaitMessagesMayWake;

  /// No description provided for @timelineWaitAnyReadyRule.
  ///
  /// In en, this message translates to:
  /// **'Returns when any selected task or a new message is ready'**
  String get timelineWaitAnyReadyRule;

  /// No description provided for @timelineWaitDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get timelineWaitDiagnostics;

  /// No description provided for @timelineWaitUnknownStatus.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get timelineWaitUnknownStatus;

  /// No description provided for @timelineWaitStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get timelineWaitStatusRunning;

  /// No description provided for @timelineWaitStatusSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get timelineWaitStatusSucceeded;

  /// No description provided for @timelineWaitStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get timelineWaitStatusFailed;

  /// No description provided for @timelineWaitStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get timelineWaitStatusCancelled;

  /// No description provided for @timelineWaitStatusInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get timelineWaitStatusInterrupted;

  /// No description provided for @conversationActivityWaitingTools.
  ///
  /// In en, this message translates to:
  /// **'Waiting for tools'**
  String get conversationActivityWaitingTools;

  /// No description provided for @conversationActivityWaitingMessages.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a subagent or new message'**
  String get conversationActivityWaitingMessages;

  /// No description provided for @conversationActivityWaitingTimer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get conversationActivityWaitingTimer;

  /// No description provided for @settingsModelAutoCompactAdjusted.
  ///
  /// In en, this message translates to:
  /// **'The effective limit was adjusted for context capacity and output reserve.'**
  String get settingsModelAutoCompactAdjusted;

  /// No description provided for @modelContextParametersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Inconsistent context parameters'**
  String get modelContextParametersInvalid;

  /// No description provided for @modelInputBudgetExhausted.
  ///
  /// In en, this message translates to:
  /// **'No input capacity after reserving output'**
  String get modelInputBudgetExhausted;

  /// No description provided for @statusCompactNow.
  ///
  /// In en, this message translates to:
  /// **'Compact now'**
  String get statusCompactNow;

  /// No description provided for @statusCompacting.
  ///
  /// In en, this message translates to:
  /// **'Compacting…'**
  String get statusCompacting;

  /// No description provided for @statusCompactionFailed.
  ///
  /// In en, this message translates to:
  /// **'Compaction failed. Try again.'**
  String get statusCompactionFailed;

  /// No description provided for @settingsModelAutoCompactCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsModelAutoCompactCustom;

  /// No description provided for @acpAccountPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get acpAccountPickerTitle;

  /// No description provided for @acpAccountPickerNativeGroup.
  ///
  /// In en, this message translates to:
  /// **'Model API account'**
  String get acpAccountPickerNativeGroup;

  /// No description provided for @acpAccountPickerAcpGroup.
  ///
  /// In en, this message translates to:
  /// **'Agent integration (ACP)'**
  String get acpAccountPickerAcpGroup;

  /// No description provided for @acpAccountNoApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'No API key needed — the official program handles sign-in.'**
  String get acpAccountNoApiKeyHint;

  /// No description provided for @acpAccountSaveAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Save and connect'**
  String get acpAccountSaveAndConnect;

  /// No description provided for @acpAccountSavedConnectIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Account saved. Connection not finished: {reason}'**
  String acpAccountSavedConnectIncomplete(String reason);

  /// No description provided for @acpAccountSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save this integration: {reason}'**
  String acpAccountSaveFailed(String reason);

  /// No description provided for @acpAccountProviderChip.
  ///
  /// In en, this message translates to:
  /// **'ACP'**
  String get acpAccountProviderChip;

  /// No description provided for @acpAccountScopeNotice.
  ///
  /// In en, this message translates to:
  /// **'This version only configures the account and sign-in. ACP chat and model selection are not available yet.'**
  String get acpAccountScopeNotice;

  /// No description provided for @acpAccountRemoveNotLogout.
  ///
  /// In en, this message translates to:
  /// **'Removing an integration does not sign out the official program.'**
  String get acpAccountRemoveNotLogout;

  /// No description provided for @acpAccountRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove this integration.'**
  String get acpAccountRemoveFailed;

  /// No description provided for @acpAuthUnchecked.
  ///
  /// In en, this message translates to:
  /// **'Connection not checked yet.'**
  String get acpAuthUnchecked;

  /// No description provided for @acpAuthChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking connection…'**
  String get acpAuthChecking;

  /// No description provided for @acpAuthRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get acpAuthRequiredTitle;

  /// No description provided for @acpAuthRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'The official program reported the sign-in methods below.'**
  String get acpAuthRequiredBody;

  /// No description provided for @acpAuthMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method'**
  String get acpAuthMethodLabel;

  /// No description provided for @acpAuthLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get acpAuthLogin;

  /// No description provided for @acpAuthAuthenticatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sign-in'**
  String get acpAuthAuthenticatingTitle;

  /// No description provided for @acpAuthAuthenticatingBody.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in inside the official sign-in window. This page keeps following the same attempt.'**
  String get acpAuthAuthenticatingBody;

  /// No description provided for @acpAuthVerifyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Verifying sign-in…'**
  String get acpAuthVerifyingTitle;

  /// No description provided for @acpAuthVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get acpAuthVerifiedTitle;

  /// No description provided for @acpAuthVerifiedAt.
  ///
  /// In en, this message translates to:
  /// **'Verified {time}'**
  String acpAuthVerifiedAt(String time);

  /// No description provided for @acpAuthRecheck.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get acpAuthRecheck;

  /// No description provided for @acpAuthCheck.
  ///
  /// In en, this message translates to:
  /// **'Check connection'**
  String get acpAuthCheck;

  /// No description provided for @acpAuthCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel sign-in'**
  String get acpAuthCancel;

  /// No description provided for @acpAuthCancelCheck.
  ///
  /// In en, this message translates to:
  /// **'Cancel check'**
  String get acpAuthCancelCheck;

  /// No description provided for @acpAuthCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get acpAuthCancelling;

  /// No description provided for @acpAuthCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get acpAuthCancelled;

  /// No description provided for @acpAuthFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get acpAuthFailedTitle;

  /// No description provided for @acpAuthTerminalOnly.
  ///
  /// In en, this message translates to:
  /// **'The server only offers terminal sign-in, which this version does not support.'**
  String get acpAuthTerminalOnly;

  /// No description provided for @acpAuthUnsupportedOnly.
  ///
  /// In en, this message translates to:
  /// **'The server only offers sign-in methods this version does not implement.'**
  String get acpAuthUnsupportedOnly;

  /// No description provided for @acpAuthClosingTitle.
  ///
  /// In en, this message translates to:
  /// **'Finishing cleanup'**
  String get acpAuthClosingTitle;

  /// No description provided for @acpAuthClosingBody.
  ///
  /// In en, this message translates to:
  /// **'The protocol exchange is over; the process and its pipes are still being joined. No new attempt starts until this settles.'**
  String get acpAuthClosingBody;

  /// No description provided for @acpAuthServerUnknown.
  ///
  /// In en, this message translates to:
  /// **'The server did not provide its identity.'**
  String get acpAuthServerUnknown;

  /// No description provided for @acpAuthMethodSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a sign-in method'**
  String get acpAuthMethodSelectHint;

  /// No description provided for @acpAuthMethodRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a sign-in method to continue.'**
  String get acpAuthMethodRequired;

  /// No description provided for @acpAuthRowClosing.
  ///
  /// In en, this message translates to:
  /// **'Cleaning up'**
  String get acpAuthRowClosing;

  /// No description provided for @acpAccountInstallOpen.
  ///
  /// In en, this message translates to:
  /// **'Open official guide'**
  String get acpAccountInstallOpen;

  /// No description provided for @acpAuthNoMethods.
  ///
  /// In en, this message translates to:
  /// **'The server did not offer a usable sign-in method.'**
  String get acpAuthNoMethods;

  /// No description provided for @acpAuthRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get acpAuthRetry;

  /// No description provided for @acpAuthEditConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit configuration'**
  String get acpAuthEditConfig;

  /// No description provided for @acpAuthDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get acpAuthDone;

  /// No description provided for @acpAuthDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get acpAuthDiagnostics;

  /// No description provided for @acpAuthStageLabel.
  ///
  /// In en, this message translates to:
  /// **'Stage: {stage}'**
  String acpAuthStageLabel(String stage);

  /// No description provided for @acpAuthCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason: {code}'**
  String acpAuthCodeLabel(String code);

  /// No description provided for @acpAuthRowUnchecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get acpAuthRowUnchecked;

  /// No description provided for @acpAuthRowChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get acpAuthRowChecking;

  /// No description provided for @acpAuthRowRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get acpAuthRowRequired;

  /// No description provided for @acpAuthRowAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get acpAuthRowAuthenticating;

  /// No description provided for @acpAuthRowVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying'**
  String get acpAuthRowVerifying;

  /// No description provided for @acpAuthRowVerified.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get acpAuthRowVerified;

  /// No description provided for @acpAuthRowCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get acpAuthRowCancelling;

  /// No description provided for @acpAuthRowCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get acpAuthRowCancelled;

  /// No description provided for @acpAuthRowFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get acpAuthRowFailed;

  /// No description provided for @acpAccountDetailsSummary.
  ///
  /// In en, this message translates to:
  /// **'Official ACP integration — no API key needed.'**
  String get acpAccountDetailsSummary;

  /// No description provided for @acpAccountConnectionInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection details'**
  String get acpAccountConnectionInfoTitle;

  /// No description provided for @acpAccountProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get acpAccountProviderLabel;

  /// No description provided for @acpAuthFailureSummary.
  ///
  /// In en, this message translates to:
  /// **'{reason} ({stage})'**
  String acpAuthFailureSummary(String reason, String stage);

  /// No description provided for @acpFailureCodeStartup.
  ///
  /// In en, this message translates to:
  /// **'Process start failed'**
  String get acpFailureCodeStartup;

  /// No description provided for @acpFailureCodeMissingExecutable.
  ///
  /// In en, this message translates to:
  /// **'Server program not found'**
  String get acpFailureCodeMissingExecutable;

  /// No description provided for @acpFailureCodeIo.
  ///
  /// In en, this message translates to:
  /// **'I/O error'**
  String get acpFailureCodeIo;

  /// No description provided for @acpFailureCodeUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'Unsupported protocol version'**
  String get acpFailureCodeUnsupportedVersion;

  /// No description provided for @acpFailureCodeUnsupportedMethod.
  ///
  /// In en, this message translates to:
  /// **'Unsupported sign-in method'**
  String get acpFailureCodeUnsupportedMethod;

  /// No description provided for @acpFailureCodeAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get acpFailureCodeAuthentication;

  /// No description provided for @acpFailureCodeProbe.
  ///
  /// In en, this message translates to:
  /// **'Connection check failed'**
  String get acpFailureCodeProbe;

  /// No description provided for @acpFailureCodeProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol error'**
  String get acpFailureCodeProtocol;

  /// No description provided for @acpFailureCodeTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport error'**
  String get acpFailureCodeTransport;

  /// No description provided for @acpFailureCodeTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get acpFailureCodeTimeout;

  /// No description provided for @acpFailureCodeResourceLimit.
  ///
  /// In en, this message translates to:
  /// **'Resource limit reached'**
  String get acpFailureCodeResourceLimit;

  /// No description provided for @acpFailureCodeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get acpFailureCodeCancelled;

  /// No description provided for @acpFailureCodeStaleOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation was superseded'**
  String get acpFailureCodeStaleOperation;

  /// No description provided for @acpFailureCodeConfigChanged.
  ///
  /// In en, this message translates to:
  /// **'Configuration changed'**
  String get acpFailureCodeConfigChanged;

  /// No description provided for @acpFailureCodeCleanup.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed'**
  String get acpFailureCodeCleanup;

  /// No description provided for @acpFailureCodeInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal error'**
  String get acpFailureCodeInternal;

  /// No description provided for @acpFailureStageProcess.
  ///
  /// In en, this message translates to:
  /// **'during process start'**
  String get acpFailureStageProcess;

  /// No description provided for @acpFailureStageConfig.
  ///
  /// In en, this message translates to:
  /// **'during configuration read'**
  String get acpFailureStageConfig;

  /// No description provided for @acpFailureStageInitialize.
  ///
  /// In en, this message translates to:
  /// **'during initialize'**
  String get acpFailureStageInitialize;

  /// No description provided for @acpFailureStageAuthenticate.
  ///
  /// In en, this message translates to:
  /// **'during sign-in'**
  String get acpFailureStageAuthenticate;

  /// No description provided for @acpFailureStageProbe.
  ///
  /// In en, this message translates to:
  /// **'during connection check'**
  String get acpFailureStageProbe;

  /// No description provided for @acpFailureStageClose.
  ///
  /// In en, this message translates to:
  /// **'during session close'**
  String get acpFailureStageClose;

  /// No description provided for @acpFailureStageCleanup.
  ///
  /// In en, this message translates to:
  /// **'during cleanup'**
  String get acpFailureStageCleanup;

  /// No description provided for @studioFailureCodeNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'Not initialized'**
  String get studioFailureCodeNotInitialized;

  /// No description provided for @studioFailureCodeRuntimeStopped.
  ///
  /// In en, this message translates to:
  /// **'Runtime stopped'**
  String get studioFailureCodeRuntimeStopped;

  /// No description provided for @studioFailureCodeInstanceBusy.
  ///
  /// In en, this message translates to:
  /// **'Another operation is running'**
  String get studioFailureCodeInstanceBusy;

  /// No description provided for @studioFailureCodeInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'Invalid request'**
  String get studioFailureCodeInvalidArgument;

  /// No description provided for @studioFailureCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get studioFailureCodeNotFound;

  /// No description provided for @studioFailureCodeBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get studioFailureCodeBusy;

  /// No description provided for @studioFailureCodeConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get studioFailureCodeConflict;

  /// No description provided for @studioFailureCodeStaleRevision.
  ///
  /// In en, this message translates to:
  /// **'Outdated revision'**
  String get studioFailureCodeStaleRevision;

  /// No description provided for @studioFailureCodePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get studioFailureCodePermissionDenied;

  /// No description provided for @studioFailureCodeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get studioFailureCodeCancelled;

  /// No description provided for @studioFailureCodeCancellationTooLate.
  ///
  /// In en, this message translates to:
  /// **'Too late to cancel'**
  String get studioFailureCodeCancellationTooLate;

  /// No description provided for @studioFailureCodeOverloaded.
  ///
  /// In en, this message translates to:
  /// **'Overloaded'**
  String get studioFailureCodeOverloaded;

  /// No description provided for @studioFailureCodeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get studioFailureCodeUnavailable;

  /// No description provided for @studioFailureCodeProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol error'**
  String get studioFailureCodeProtocol;

  /// No description provided for @studioFailureCodeStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage error'**
  String get studioFailureCodeStorage;

  /// No description provided for @studioFailureCodeUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update error'**
  String get studioFailureCodeUpdate;

  /// No description provided for @studioFailureCodeInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal error'**
  String get studioFailureCodeInternal;

  /// No description provided for @acpAuthCancellingBody.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the sign-in window and its process to finish.'**
  String get acpAuthCancellingBody;

  /// No description provided for @acpAuthCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'No attempt is running now. You can check or sign in again.'**
  String get acpAuthCancelledBody;

  /// No description provided for @acpAuthCommandFailure.
  ///
  /// In en, this message translates to:
  /// **'The request was not accepted. {reason}'**
  String acpAuthCommandFailure(String reason);

  /// No description provided for @acpAuthCommandUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The request could not be completed.'**
  String get acpAuthCommandUnavailable;

  /// No description provided for @botsOverviewHint.
  ///
  /// In en, this message translates to:
  /// **'Bring your sessions to Feishu to search, collaborate, and share files.'**
  String get botsOverviewHint;

  /// No description provided for @botsPlatformFeishu.
  ///
  /// In en, this message translates to:
  /// **'Feishu'**
  String get botsPlatformFeishu;

  /// No description provided for @botsModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Model and reasoning'**
  String get botsModelTitle;

  /// No description provided for @botsModelHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to all chats with this bot from the next turn.'**
  String get botsModelHint;

  /// No description provided for @botsAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'People and group access'**
  String get botsAccessTitle;

  /// No description provided for @botsAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Only approved people and groups can use this bot.'**
  String get botsAccessHint;

  /// No description provided for @botsConnectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection and settings'**
  String get botsConnectionSettings;

  /// No description provided for @botsWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Dedicated workspace'**
  String get botsWorkspace;

  /// No description provided for @botsPlatformTools.
  ///
  /// In en, this message translates to:
  /// **'Feishu messages and test sending'**
  String get botsPlatformTools;

  /// No description provided for @botsManagedModel.
  ///
  /// In en, this message translates to:
  /// **'Managed by bot settings'**
  String get botsManagedModel;

  /// No description provided for @settingsSshNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get settingsSshNextPage;

  /// No description provided for @acpInstallUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'No official managed build of {version} exists for this platform.'**
  String acpInstallUnsupportedPlatform(String version);

  /// No description provided for @acpFailureStagePrepare.
  ///
  /// In en, this message translates to:
  /// **'Preparing the managed server'**
  String get acpFailureStagePrepare;

  /// No description provided for @acpFailureCodePreparationRequired.
  ///
  /// In en, this message translates to:
  /// **'The managed server is not prepared yet'**
  String get acpFailureCodePreparationRequired;

  /// No description provided for @acpFailureCodeInstallationInvalid.
  ///
  /// In en, this message translates to:
  /// **'The prepared server is incomplete or damaged'**
  String get acpFailureCodeInstallationInvalid;

  /// No description provided for @acpFailureCodeUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'No official managed build for this platform'**
  String get acpFailureCodeUnsupportedPlatform;

  /// No description provided for @acpFailureCodeServerVersionMismatch.
  ///
  /// In en, this message translates to:
  /// **'The server version is not the supported one'**
  String get acpFailureCodeServerVersionMismatch;

  /// No description provided for @acpInstallFactVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get acpInstallFactVersion;

  /// No description provided for @acpInstallFactTarget.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get acpInstallFactTarget;

  /// No description provided for @acpInstallFactStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get acpInstallFactStage;

  /// No description provided for @acpInstallFactRetries.
  ///
  /// In en, this message translates to:
  /// **'Automatic retries'**
  String get acpInstallFactRetries;

  /// No description provided for @acpInstallRetryValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} other{{count} times}}'**
  String acpInstallRetryValue(int count);

  /// No description provided for @acpInstallProgressDownloaded.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} downloaded'**
  String acpInstallProgressDownloaded(String done, String total);

  /// No description provided for @acpInstallProgressUnknown.
  ///
  /// In en, this message translates to:
  /// **'{done} downloaded, total unknown'**
  String acpInstallProgressUnknown(String done);

  /// No description provided for @acpInstallProgressVerified.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} verified'**
  String acpInstallProgressVerified(String done, String total);

  /// No description provided for @acpInstallProgressVerifiedUnknown.
  ///
  /// In en, this message translates to:
  /// **'{done} verified, total unknown'**
  String acpInstallProgressVerifiedUnknown(String done);

  /// No description provided for @acpInstallProgressExtracted.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} extracted'**
  String acpInstallProgressExtracted(String done, String total);

  /// No description provided for @acpInstallProgressExtractedUnknown.
  ///
  /// In en, this message translates to:
  /// **'{done} extracted, total unknown'**
  String acpInstallProgressExtractedUnknown(String done);

  /// No description provided for @acpInstallProgressProcessed.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} processed'**
  String acpInstallProgressProcessed(String done, String total);

  /// No description provided for @acpInstallProgressProcessedUnknown.
  ///
  /// In en, this message translates to:
  /// **'{done} processed, total unknown'**
  String acpInstallProgressProcessedUnknown(String done);

  /// No description provided for @acpInstallProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String acpInstallProgressPercent(int percent);

  /// No description provided for @acpInstallSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String acpInstallSpeed(String speed);

  /// No description provided for @acpInstallStageResolve.
  ///
  /// In en, this message translates to:
  /// **'Reading the official manifest'**
  String get acpInstallStageResolve;

  /// No description provided for @acpInstallStageWaitForLock.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the install lock'**
  String get acpInstallStageWaitForLock;

  /// No description provided for @acpInstallStageDownload.
  ///
  /// In en, this message translates to:
  /// **'Downloading package'**
  String get acpInstallStageDownload;

  /// No description provided for @acpInstallStageVerify.
  ///
  /// In en, this message translates to:
  /// **'Verifying package'**
  String get acpInstallStageVerify;

  /// No description provided for @acpInstallStageExtract.
  ///
  /// In en, this message translates to:
  /// **'Extracting files'**
  String get acpInstallStageExtract;

  /// No description provided for @acpInstallStagePublish.
  ///
  /// In en, this message translates to:
  /// **'Publishing installation'**
  String get acpInstallStagePublish;

  /// No description provided for @acpInstallStageClose.
  ///
  /// In en, this message translates to:
  /// **'Closing download'**
  String get acpInstallStageClose;

  /// No description provided for @acpInstallStart.
  ///
  /// In en, this message translates to:
  /// **'Download and prepare'**
  String get acpInstallStart;

  /// No description provided for @acpInstallRestart.
  ///
  /// In en, this message translates to:
  /// **'Prepare again'**
  String get acpInstallRestart;

  /// No description provided for @acpInstallCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get acpInstallCancel;

  /// No description provided for @acpInstallCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get acpInstallCancelling;

  /// No description provided for @acpInstallCancelSharedHint.
  ///
  /// In en, this message translates to:
  /// **'Preparing is shared: cancelling stops this preparation and leaves saved accounts untouched.'**
  String get acpInstallCancelSharedHint;

  /// No description provided for @acpInstallUsePrepared.
  ///
  /// In en, this message translates to:
  /// **'Use prepared server'**
  String get acpInstallUsePrepared;

  /// No description provided for @acpInstallUsePreparedHint.
  ///
  /// In en, this message translates to:
  /// **'An existing prepared {version} ({target}) can be claimed for this account.'**
  String acpInstallUsePreparedHint(String version, String target);

  /// No description provided for @acpInstallReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Server ready'**
  String get acpInstallReadyTitle;

  /// No description provided for @acpInstallReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Preparing never saves an account or signs in.'**
  String get acpInstallReadyBody;

  /// No description provided for @acpInstallReusedBadge.
  ///
  /// In en, this message translates to:
  /// **'Reused existing installation'**
  String get acpInstallReusedBadge;

  /// No description provided for @acpInstallFailureRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry preparation'**
  String get acpInstallFailureRetry;

  /// No description provided for @acpInstallTrustOfficialHttps.
  ///
  /// In en, this message translates to:
  /// **'Trust boundary: official HTTPS source, no publisher checksum provided.'**
  String get acpInstallTrustOfficialHttps;

  /// No description provided for @acpInstallPendingAdmission.
  ///
  /// In en, this message translates to:
  /// **'Accepting the preparation request…'**
  String get acpInstallPendingAdmission;

  /// No description provided for @acpInstallCommandFailed.
  ///
  /// In en, this message translates to:
  /// **'The request was not accepted. {reason}'**
  String acpInstallCommandFailed(String reason);

  /// No description provided for @acpInstallFailureSummary.
  ///
  /// In en, this message translates to:
  /// **'{reason} ({stage})'**
  String acpInstallFailureSummary(String reason, String stage);

  /// No description provided for @acpInstallFailureCodeUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'This platform is not supported'**
  String get acpInstallFailureCodeUnsupportedPlatform;

  /// No description provided for @acpInstallFailureCodeSourceRejected.
  ///
  /// In en, this message translates to:
  /// **'Source rejected'**
  String get acpInstallFailureCodeSourceRejected;

  /// No description provided for @acpInstallFailureCodeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get acpInstallFailureCodeNetwork;

  /// No description provided for @acpInstallFailureCodeTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get acpInstallFailureCodeTimeout;

  /// No description provided for @acpInstallFailureCodeTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Package exceeds the limit'**
  String get acpInstallFailureCodeTooLarge;

  /// No description provided for @acpInstallFailureCodeChecksumMismatch.
  ///
  /// In en, this message translates to:
  /// **'Checksum mismatch'**
  String get acpInstallFailureCodeChecksumMismatch;

  /// No description provided for @acpInstallFailureCodeInvalidArchive.
  ///
  /// In en, this message translates to:
  /// **'Invalid package'**
  String get acpInstallFailureCodeInvalidArchive;

  /// No description provided for @acpInstallFailureCodeMissingExecutable.
  ///
  /// In en, this message translates to:
  /// **'Server program missing in package'**
  String get acpInstallFailureCodeMissingExecutable;

  /// No description provided for @acpInstallFailureCodeCacheCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Existing installation is corrupt'**
  String get acpInstallFailureCodeCacheCorrupt;

  /// No description provided for @acpInstallFailureCodeIo.
  ///
  /// In en, this message translates to:
  /// **'File system error'**
  String get acpInstallFailureCodeIo;

  /// No description provided for @acpInstallFailureCodeBusy.
  ///
  /// In en, this message translates to:
  /// **'Another preparation is running'**
  String get acpInstallFailureCodeBusy;

  /// No description provided for @acpInstallFailureCodeStaleOperation.
  ///
  /// In en, this message translates to:
  /// **'Preparation was superseded'**
  String get acpInstallFailureCodeStaleOperation;

  /// No description provided for @acpInstallFailureCodeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get acpInstallFailureCodeCancelled;

  /// No description provided for @acpInstallFailureCodeResourceClose.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed'**
  String get acpInstallFailureCodeResourceClose;

  /// No description provided for @acpAccountTermsOpen.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get acpAccountTermsOpen;

  /// No description provided for @acpAccountTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Official terms'**
  String get acpAccountTermsTitle;

  /// No description provided for @delegationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subagent delegation'**
  String get delegationSettingsTitle;

  /// No description provided for @delegationDefaultMode.
  ///
  /// In en, this message translates to:
  /// **'Default delegation mode'**
  String get delegationDefaultMode;

  /// No description provided for @delegationDefaultPreference.
  ///
  /// In en, this message translates to:
  /// **'Default automatic preference'**
  String get delegationDefaultPreference;

  /// No description provided for @delegationModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Delegation mode'**
  String get delegationModeLabel;

  /// No description provided for @delegationPreferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Automatic preference'**
  String get delegationPreferenceLabel;

  /// No description provided for @delegationProfile.
  ///
  /// In en, this message translates to:
  /// **'Fixed Profile'**
  String get delegationProfile;

  /// No description provided for @delegationAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic model selection'**
  String get delegationAutomatic;

  /// No description provided for @delegationEconomy.
  ///
  /// In en, this message translates to:
  /// **'Economy'**
  String get delegationEconomy;

  /// No description provided for @delegationBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get delegationBalanced;

  /// No description provided for @delegationFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get delegationFast;

  /// No description provided for @delegationOnlyAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Only applies to automatic model selection. The value is kept in fixed Profile mode.'**
  String get delegationOnlyAutomatic;

  /// No description provided for @delegationEconomyHint.
  ///
  /// In en, this message translates to:
  /// **'Prefer lower expected total cost while meeting task capability and quality needs. Unknown prices are not free.'**
  String get delegationEconomyHint;

  /// No description provided for @delegationBalancedHint.
  ///
  /// In en, this message translates to:
  /// **'Balance task fit, recent evaluations, cost, and completion time without lowering quality requirements.'**
  String get delegationBalancedHint;

  /// No description provided for @delegationFastHint.
  ///
  /// In en, this message translates to:
  /// **'Prefer shorter overall completion time while meeting capability, quality, and review requirements.'**
  String get delegationFastHint;

  /// No description provided for @delegationFollowDefault.
  ///
  /// In en, this message translates to:
  /// **'Follow default'**
  String get delegationFollowDefault;

  /// No description provided for @delegationSessionSettings.
  ///
  /// In en, this message translates to:
  /// **'Session settings'**
  String get delegationSessionSettings;

  /// No description provided for @delegationInherited.
  ///
  /// In en, this message translates to:
  /// **'Following the latest default until submission'**
  String get delegationInherited;

  /// No description provided for @delegationOverride.
  ///
  /// In en, this message translates to:
  /// **'Only this draft'**
  String get delegationOverride;

  /// No description provided for @delegationFrozen.
  ///
  /// In en, this message translates to:
  /// **'Saved at session creation · read-only'**
  String get delegationFrozen;

  /// No description provided for @delegationModelNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Model not recorded'**
  String get delegationModelNotRecorded;

  /// No description provided for @settingsModelEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsModelEnabled;

  /// No description provided for @settingsModelEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to all new model selections and subagent delegation. Running calls are not interrupted.'**
  String get settingsModelEnabledHint;

  /// No description provided for @settingsModelDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled for new selections'**
  String get settingsModelDisabled;

  /// No description provided for @settingsModelSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get settingsModelSaving;

  /// No description provided for @settingsModelSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Not saved. The switch shows the last confirmed value. Toggle again to retry.'**
  String get settingsModelSaveFailed;

  /// No description provided for @settingsBillingKind.
  ///
  /// In en, this message translates to:
  /// **'Billing category'**
  String get settingsBillingKind;

  /// No description provided for @settingsBillingAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic · no explicit override'**
  String get settingsBillingAutomatic;

  /// No description provided for @settingsBillingMetered.
  ///
  /// In en, this message translates to:
  /// **'Metered'**
  String get settingsBillingMetered;

  /// No description provided for @settingsBillingSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription / plan'**
  String get settingsBillingSubscription;

  /// No description provided for @settingsBillingUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settingsBillingUnknown;

  /// No description provided for @settingsBillingEffective.
  ///
  /// In en, this message translates to:
  /// **'Effective category'**
  String get settingsBillingEffective;

  /// No description provided for @settingsBillingOverride.
  ///
  /// In en, this message translates to:
  /// **'Explicit override'**
  String get settingsBillingOverride;

  /// No description provided for @settingsBillingHint.
  ///
  /// In en, this message translates to:
  /// **'Independent of cost estimates. A category does not confirm an active subscription or remaining quota.'**
  String get settingsBillingHint;

  /// No description provided for @settingsModelDetails.
  ///
  /// In en, this message translates to:
  /// **'Model details'**
  String get settingsModelDetails;

  /// No description provided for @modelDetailLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading model details…'**
  String get modelDetailLoading;

  /// No description provided for @modelDetailUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown / not verified'**
  String get modelDetailUnknown;

  /// No description provided for @modelDetailAvailable.
  ///
  /// In en, this message translates to:
  /// **'Locally eligible for new selections'**
  String get modelDetailAvailable;

  /// No description provided for @modelDetailAvailabilityHint.
  ///
  /// In en, this message translates to:
  /// **'Local eligibility does not guarantee provider health, subscription validity, or remaining quota.'**
  String get modelDetailAvailabilityHint;

  /// No description provided for @modelDetailSummary.
  ///
  /// In en, this message translates to:
  /// **'Description and task fit'**
  String get modelDetailSummary;

  /// No description provided for @modelDetailLimitations.
  ///
  /// In en, this message translates to:
  /// **'Limitations'**
  String get modelDetailLimitations;

  /// No description provided for @modelDetailCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities and limits'**
  String get modelDetailCapabilities;

  /// No description provided for @modelDetailEfforts.
  ///
  /// In en, this message translates to:
  /// **'Allowed reasoning efforts'**
  String get modelDetailEfforts;

  /// No description provided for @modelDetailNoEffort.
  ///
  /// In en, this message translates to:
  /// **'No reasoning effort parameter'**
  String get modelDetailNoEffort;

  /// No description provided for @modelDetailPricing.
  ///
  /// In en, this message translates to:
  /// **'Prices per million tokens'**
  String get modelDetailPricing;

  /// No description provided for @modelDetailPriceInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get modelDetailPriceInput;

  /// No description provided for @modelDetailPriceOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get modelDetailPriceOutput;

  /// No description provided for @modelDetailPriceCacheRead.
  ///
  /// In en, this message translates to:
  /// **'Cache read'**
  String get modelDetailPriceCacheRead;

  /// No description provided for @modelDetailPriceCacheWrite.
  ///
  /// In en, this message translates to:
  /// **'Cache write'**
  String get modelDetailPriceCacheWrite;

  /// No description provided for @modelDetailSources.
  ///
  /// In en, this message translates to:
  /// **'Sources and verification'**
  String get modelDetailSources;

  /// No description provided for @modelDetailOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official documentation'**
  String get modelDetailOfficial;

  /// No description provided for @modelDetailBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Independent benchmark'**
  String get modelDetailBenchmark;

  /// No description provided for @modelDetailCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community feedback'**
  String get modelDetailCommunity;

  /// No description provided for @modelDetailVerifiedAt.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get modelDetailVerifiedAt;

  /// No description provided for @modelDetailMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Measurement conditions'**
  String get modelDetailMeasurement;

  /// No description provided for @modelDetailPerformance.
  ///
  /// In en, this message translates to:
  /// **'Local call performance'**
  String get modelDetailPerformance;

  /// No description provided for @modelDetailThroughput.
  ///
  /// In en, this message translates to:
  /// **'Tokens/s (including first-token wait)'**
  String get modelDetailThroughput;

  /// No description provided for @modelDetailTtft.
  ///
  /// In en, this message translates to:
  /// **'Average time to first token (ms)'**
  String get modelDetailTtft;

  /// No description provided for @modelDetailSamples.
  ///
  /// In en, this message translates to:
  /// **'Call samples'**
  String get modelDetailSamples;

  /// No description provided for @modelDetailTtftSamples.
  ///
  /// In en, this message translates to:
  /// **'First-token samples'**
  String get modelDetailTtftSamples;

  /// No description provided for @modelDetailUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get modelDetailUpdatedAt;

  /// No description provided for @modelDetailPerformanceHint.
  ///
  /// In en, this message translates to:
  /// **'Observed locally; account, network, effort, and task affect these samples. This is not a provider guarantee or a task evaluation.'**
  String get modelDetailPerformanceHint;

  /// No description provided for @modelDetailEvaluations.
  ///
  /// In en, this message translates to:
  /// **'Recent final task evaluations (up to 10)'**
  String get modelDetailEvaluations;

  /// No description provided for @modelDetailEvaluationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No final task evaluations for this exact account and model yet.'**
  String get modelDetailEvaluationsEmpty;

  /// No description provided for @modelDetailEvaluationsHint.
  ///
  /// In en, this message translates to:
  /// **'Each child has one effective final evaluation. Small samples are not statistically conclusive; unrateable outcomes are not low scores.'**
  String get modelDetailEvaluationsHint;

  /// No description provided for @modelDetailEvaluationPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get modelDetailEvaluationPassed;

  /// No description provided for @modelDetailEvaluationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get modelDetailEvaluationFailed;

  /// No description provided for @modelDetailEvaluationNotRated.
  ///
  /// In en, this message translates to:
  /// **'Unable to assess'**
  String get modelDetailEvaluationNotRated;

  /// No description provided for @modelDetailQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get modelDetailQuality;

  /// No description provided for @modelDetailInstructionFollowing.
  ///
  /// In en, this message translates to:
  /// **'Instruction following'**
  String get modelDetailInstructionFollowing;

  /// No description provided for @modelDetailTaskReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get modelDetailTaskReasoning;

  /// No description provided for @modelDetailTaskCoding.
  ///
  /// In en, this message translates to:
  /// **'Coding'**
  String get modelDetailTaskCoding;

  /// No description provided for @modelDetailTaskTooling.
  ///
  /// In en, this message translates to:
  /// **'Tool use and orchestration'**
  String get modelDetailTaskTooling;

  /// No description provided for @modelDetailTaskLongContext.
  ///
  /// In en, this message translates to:
  /// **'Long context'**
  String get modelDetailTaskLongContext;

  /// No description provided for @modelDetailTaskMultimodal.
  ///
  /// In en, this message translates to:
  /// **'Multimodal'**
  String get modelDetailTaskMultimodal;

  /// No description provided for @modelDetailTaskGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get modelDetailTaskGeneral;

  /// No description provided for @modelDetailRetry.
  ///
  /// In en, this message translates to:
  /// **'Reload details'**
  String get modelDetailRetry;

  /// No description provided for @modelDetailClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get modelDetailClose;

  /// No description provided for @modelDetailStale.
  ///
  /// In en, this message translates to:
  /// **'This model\'s canonical identity changed. Reload its details.'**
  String get modelDetailStale;

  /// No description provided for @audienceTitle.
  ///
  /// In en, this message translates to:
  /// **'Feishu audience'**
  String get audienceTitle;

  /// No description provided for @audienceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Audience unavailable — synchronization cannot be verified'**
  String get audienceUnavailable;

  /// No description provided for @audienceGroup.
  ///
  /// In en, this message translates to:
  /// **'Group audience'**
  String get audienceGroup;

  /// No description provided for @audienceDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct chat'**
  String get audienceDirect;

  /// No description provided for @audienceReplaced.
  ///
  /// In en, this message translates to:
  /// **'Old binding replaced — no new delivery'**
  String get audienceReplaced;

  /// No description provided for @audiencePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing this conversation'**
  String get audiencePreparing;

  /// No description provided for @audienceUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Legacy conversation — create a new conversation to upgrade'**
  String get audienceUpgrade;

  /// No description provided for @audiencePendingStart.
  ///
  /// In en, this message translates to:
  /// **'Start saved; waiting for the authorization boundary'**
  String get audiencePendingStart;

  /// No description provided for @audienceActive.
  ///
  /// In en, this message translates to:
  /// **'Public replies and published artifacts synchronize automatically'**
  String get audienceActive;

  /// No description provided for @audiencePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused — eligible output will be delivered after resuming'**
  String get audiencePaused;

  /// No description provided for @audienceClosed.
  ///
  /// In en, this message translates to:
  /// **'Synchronization closed — enabling creates a new authorization'**
  String get audienceClosed;

  /// No description provided for @audiencePause.
  ///
  /// In en, this message translates to:
  /// **'Pause delivery'**
  String get audiencePause;

  /// No description provided for @audienceResume.
  ///
  /// In en, this message translates to:
  /// **'Resume and deliver pending output'**
  String get audienceResume;

  /// No description provided for @audienceClose.
  ///
  /// In en, this message translates to:
  /// **'Close synchronization'**
  String get audienceClose;

  /// No description provided for @audienceEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable from a new boundary'**
  String get audienceEnable;

  /// No description provided for @audienceNewThread.
  ///
  /// In en, this message translates to:
  /// **'Create upgraded conversation'**
  String get audienceNewThread;

  /// No description provided for @audienceHistory.
  ///
  /// In en, this message translates to:
  /// **'Authorization history'**
  String get audienceHistory;

  /// No description provided for @audienceCurrentContext.
  ///
  /// In en, this message translates to:
  /// **'Current or latest closed authorization'**
  String get audienceCurrentContext;

  /// No description provided for @audienceHistoryContext.
  ///
  /// In en, this message translates to:
  /// **'Selected historical authorization'**
  String get audienceHistoryContext;

  /// No description provided for @audienceMoreHistory.
  ///
  /// In en, this message translates to:
  /// **'Load earlier authorizations'**
  String get audienceMoreHistory;

  /// No description provided for @audiencePendingItems.
  ///
  /// In en, this message translates to:
  /// **'Pending items'**
  String get audiencePendingItems;

  /// No description provided for @audienceUnknownOperations.
  ///
  /// In en, this message translates to:
  /// **'Unknown operations'**
  String get audienceUnknownOperations;

  /// No description provided for @audienceIncompleteItems.
  ///
  /// In en, this message translates to:
  /// **'Incomplete items'**
  String get audienceIncompleteItems;

  /// No description provided for @audienceLegacyAttention.
  ///
  /// In en, this message translates to:
  /// **'Earlier finite replies still need attention'**
  String get audienceLegacyAttention;

  /// No description provided for @audienceCountsCapped.
  ///
  /// In en, this message translates to:
  /// **'Counts show at least this many, not an exact history total'**
  String get audienceCountsCapped;

  /// No description provided for @audiencePrivateInput.
  ///
  /// In en, this message translates to:
  /// **'Your GUI input and input files are not mirrored. Commentary may be visible to this audience.'**
  String get audiencePrivateInput;

  /// No description provided for @audienceOperationPending.
  ///
  /// In en, this message translates to:
  /// **'Control accepted; awaiting canonical observation or effect'**
  String get audienceOperationPending;

  /// No description provided for @audienceOperationUnknown.
  ///
  /// In en, this message translates to:
  /// **'Control result unknown — do not submit a new operation'**
  String get audienceOperationUnknown;

  /// No description provided for @audienceOperationSuperseded.
  ///
  /// In en, this message translates to:
  /// **'This control was superseded by a later action'**
  String get audienceOperationSuperseded;

  /// No description provided for @audienceReconcile.
  ///
  /// In en, this message translates to:
  /// **'Check the original operation'**
  String get audienceReconcile;

  /// No description provided for @audienceReadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Channel status unavailable; this does not mean never sent'**
  String get audienceReadUnavailable;

  /// No description provided for @audienceReading.
  ///
  /// In en, this message translates to:
  /// **'Reading channel status'**
  String get audienceReading;

  /// No description provided for @audienceNoRecord.
  ///
  /// In en, this message translates to:
  /// **'No record in this authorization; earlier delivery is not ruled out'**
  String get audienceNoRecord;

  /// No description provided for @audienceNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'Not eligible in this authorization'**
  String get audienceNotAuthorized;

  /// No description provided for @audienceRemoved.
  ///
  /// In en, this message translates to:
  /// **'Canonical item removed; previous platform receipts remain'**
  String get audienceRemoved;

  /// No description provided for @audienceSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Canonical source unavailable, not proven removed'**
  String get audienceSourceUnavailable;

  /// No description provided for @audienceObserved.
  ///
  /// In en, this message translates to:
  /// **'Observed revision'**
  String get audienceObserved;

  /// No description provided for @audienceProjected.
  ///
  /// In en, this message translates to:
  /// **'Projected revision'**
  String get audienceProjected;

  /// No description provided for @audienceAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted revision'**
  String get audienceAccepted;

  /// No description provided for @audienceCurrentAccepted.
  ///
  /// In en, this message translates to:
  /// **'Current revision accepted'**
  String get audienceCurrentAccepted;

  /// No description provided for @audienceHistoricalAccepted.
  ///
  /// In en, this message translates to:
  /// **'Earlier revision accepted; current revision not synchronized'**
  String get audienceHistoricalAccepted;

  /// No description provided for @audienceFull.
  ///
  /// In en, this message translates to:
  /// **'Full channel presentation'**
  String get audienceFull;

  /// No description provided for @audienceTruncated.
  ///
  /// In en, this message translates to:
  /// **'Feishu presentation truncated; local full text unchanged'**
  String get audienceTruncated;

  /// No description provided for @audienceNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get audienceNotStarted;

  /// No description provided for @audienceInFlight.
  ///
  /// In en, this message translates to:
  /// **'In flight'**
  String get audienceInFlight;

  /// No description provided for @audiencePlatformAccepted.
  ///
  /// In en, this message translates to:
  /// **'Platform accepted'**
  String get audiencePlatformAccepted;

  /// No description provided for @audiencePlatformRejected.
  ///
  /// In en, this message translates to:
  /// **'Platform rejected'**
  String get audiencePlatformRejected;

  /// No description provided for @audiencePlatformUnknown.
  ///
  /// In en, this message translates to:
  /// **'Platform result unknown'**
  String get audiencePlatformUnknown;

  /// No description provided for @audienceBlocked.
  ///
  /// In en, this message translates to:
  /// **'Locally blocked; no platform rejection'**
  String get audienceBlocked;

  /// No description provided for @audienceUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get audienceUpload;

  /// No description provided for @audienceMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get audienceMessage;

  /// No description provided for @audiencePartial.
  ///
  /// In en, this message translates to:
  /// **'Partial: upload and message have separate outcomes'**
  String get audiencePartial;

  /// No description provided for @artifactPublished.
  ///
  /// In en, this message translates to:
  /// **'Published artifact'**
  String get artifactPublished;

  /// No description provided for @artifactHistorySaved.
  ///
  /// In en, this message translates to:
  /// **'History saved'**
  String get artifactHistorySaved;

  /// No description provided for @artifactHistoryPending.
  ///
  /// In en, this message translates to:
  /// **'History save pending'**
  String get artifactHistoryPending;

  /// No description provided for @artifactSave.
  ///
  /// In en, this message translates to:
  /// **'Save…'**
  String get artifactSave;

  /// No description provided for @artifactSaveOpen.
  ///
  /// In en, this message translates to:
  /// **'Save and open…'**
  String get artifactSaveOpen;

  /// No description provided for @artifactTrustWarning.
  ///
  /// In en, this message translates to:
  /// **'Uses your system\'s associated application. Open only files you trust.'**
  String get artifactTrustWarning;

  /// No description provided for @artifactSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved on this machine'**
  String get artifactSaved;

  /// No description provided for @artifactSavedNotOpened.
  ///
  /// In en, this message translates to:
  /// **'Saved, but not opened'**
  String get artifactSavedNotOpened;

  /// No description provided for @artifactHandedToSystem.
  ///
  /// In en, this message translates to:
  /// **'Saved and handed to the system application'**
  String get artifactHandedToSystem;

  /// No description provided for @artifactSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the original artifact'**
  String get artifactSaveFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
