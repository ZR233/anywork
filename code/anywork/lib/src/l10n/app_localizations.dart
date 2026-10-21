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

  /// No description provided for @settingsStatisticsPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics pending write'**
  String get settingsStatisticsPendingTitle;

  /// No description provided for @settingsStatisticsPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Recent calls are still being written to statistics and may not appear yet.'**
  String get settingsStatisticsPendingBody;

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

  /// No description provided for @composerAttachmentUnsupportedTooltip.
  ///
  /// In en, this message translates to:
  /// **'The current model does not support attachments'**
  String get composerAttachmentUnsupportedTooltip;

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

  /// No description provided for @composerClipboardImageUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The current model does not support pasted images.'**
  String get composerClipboardImageUnsupported;

  /// No description provided for @composerClipboardReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the clipboard image.'**
  String get composerClipboardReadFailed;

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
