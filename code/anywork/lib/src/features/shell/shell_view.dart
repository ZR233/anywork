/// Public Shell presentation surface. Applications keep their existing route,
/// Workspace selection/preference VM and Conversation Screen as the owners of
/// navigation, directory commands, drafts and Stop. Only compose their widgets
/// and callbacks here; no legacy facade or mutable canonical store is exported.
library;

export 'sidebar_entries.dart' show ShellNavigationView;
export 'state/shell_chrome_state.dart' show ShellBotsEntry;
export 'studio_shell.dart' show AppShell, ShellDrawerScope;
export 'views/thread_status_indicator.dart' show ShellThreadStatusIndicator;
