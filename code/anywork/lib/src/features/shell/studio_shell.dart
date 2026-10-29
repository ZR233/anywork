import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_split_view/multi_split_view.dart';

import '../../app/app_graph.dart';
import '../../app/routing/app_route.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/observe_client.dart';
import '../../presentation/providers/recovery_store.dart';

import '../../shared/studio_loading.dart';
import '../../shared/recovery_check_status.dart';
import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';

import '../../l10n/studio_l10n.dart';
import '../../platform/studio_platform.dart';
import '../../platform/host_app_icons.dart';
import '../../platform/local_file_dialogs.dart';
import '../../platform/terminal_launcher.dart';
import '../../platform/vscode_launcher.dart';
import '../../platform/zed_launcher.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/delegation_labels.dart';
import 'agent_switcher_menu.dart';
import '../../shared/studio_driver_state.dart';
import '../../presentation/providers/studio_update_controller.dart';
import '../settings/settings_common.dart';
import '../settings/settings_ssh_password_dialog.dart';
import '../settings/settings_ssh_server_dialog.dart';
import '../settings/settings_remote_directory_dialog.dart';
import '../conversation/composer/connectors/composer_dock_connector.dart';
import '../conversation/composer/view_models/composer_view_model.dart';
import '../status/thread_status_bar.dart';
import '../conversation/timeline/widgets/conversation_activity_bar.dart';
import '../conversation/timeline/connectors/timeline_connector.dart';
import '../conversation/timeline/connectors/plan_detail_connector.dart';
import '../conversation/timeline/view_models/timeline_view_model.dart';
import '../todo/todo_panel.dart';
import 'shell_view.dart';
import 'thread_preparation_card.dart';

part 'studio_sidebar.dart';
part 'add_project_dialog.dart';
part 'sidebar_entries.dart';
part 'sidebar_tiles.dart';
part 'sidebar_thread_status.dart';
part 'sidebar_detail_overlay.dart';
part 'sidebar_actions.dart';
part 'runtime_banners.dart';
part 'studio_shell_chrome.dart';
part 'studio_startup.dart';
part 'agent_workspace_pane.dart';

typedef ProjectDirectoryPicker = Future<String?> Function(BuildContext context);

final projectDirectoryPickerProvider = Provider<ProjectDirectoryPicker>((ref) {
  if (const bool.fromEnvironment('ANYWORK_DRIVER')) {
    return showDriverProjectPathDialog;
  }
  return (_) => pickLocalProjectDirectory();
});

Future<String?> showDriverProjectPathDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _DriverProjectPathDialog(),
  );
}

class StudioShell extends ConsumerStatefulWidget {
  const StudioShell({super.key});

  @override
  ConsumerState<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends ConsumerState<StudioShell> {
  static const _sidebarDividerWidth = 5.0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sidebarKey = GlobalKey<_SidebarState>();
  final _startupClock = Stopwatch()..start();
  final _sidebarResizeFocus = FocusNode(debugLabel: 'Sidebar resize');

  bool _reportedReady = false;
  double? _sidebarWidth;
  bool _sidebarHidden = false;
  bool _sidebarResizeFocused = false;
  bool _sidebarDragging = false;
  GeneralSettingsView _general = const GeneralSettingsView();
  int _sidebarDraftVersion = 0;
  // KeyUp and focus loss share this edit's save; the Client orders distinct edits.
  (int, Future<void>)? _sidebarSave;

  Future<void> _persistWidth() {
    final submitted = _sidebarWidth;
    if (submitted == null) return Future.value();
    final version = _sidebarDraftVersion;
    final pending = _sidebarSave;
    if (pending != null && pending.$1 == version) return pending.$2;
    late final Future<void> completion;
    completion = _saveSidebarWidth(submitted, version).whenComplete(() {
      if (identical(_sidebarSave?.$2, completion)) _sidebarSave = null;
    });
    _sidebarSave = (version, completion);
    return completion;
  }

  Future<void> _saveSidebarWidth(double submitted, int version) async {
    try {
      await _saveSidebarPreferences(
        ref,
        general: _general,
        width: submitted.round(),
      );
      if (mounted && _sidebarDraftVersion == version) {
        setState(() => _sidebarWidth = null);
      }
    } catch (error) {
      if (mounted && _sidebarDraftVersion == version) {
        setState(() => _sidebarWidth = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _setSidebarWidth(double? width) {
    setState(() {
      _sidebarDraftVersion++;
      _sidebarWidth = width;
    });
  }

  void _adjustSidebarWidth(double delta, double width, double maximumWidth) {
    _setSidebarWidth(
      ((_sidebarWidth ?? width).clamp(300.0, maximumWidth) + delta).clamp(
        300.0,
        maximumWidth,
      ),
    );
  }

  KeyEventResult _handleSidebarKey(
    KeyEvent event,
    double width,
    double maximumWidth,
  ) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyUpEvent &&
        (keyboard.isControlPressed ||
            keyboard.isAltPressed ||
            keyboard.isMetaPressed)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.home) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      if (_sidebarWidth != null) unawaited(_persistWidth());
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.home) {
        _setSidebarWidth(336);
      } else {
        _adjustSidebarWidth(
          key == LogicalKeyboardKey.arrowRight ? 16 : -16,
          width,
          maximumWidth,
        );
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _sidebarResizeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(shellStartupViewProvider);
    _general = ref.watch(shellGeneralProvider);
    final savedWidth = _general.sidebarWidth;
    final desiredWidth = _sidebarWidth ?? savedWidth.toDouble();
    return Builder(
      builder: (context) {
        // 初次无数据才使用启动页；已有 chrome 时后续刷新/重连不整页替换已显示内容。
        if (!startup.ready) {
          return startup.error != null
              ? _StudioFatalError(error: startup.error!)
              : const _StudioStartup();
        }
        final selection = ref.watch(shellSelectionProvider);
        final chrome = ref.watch(shellChromeViewProvider);
        final sidebar = ref.watch(sidebarViewProvider);
        final header = ref.watch(headerViewProvider);
        if (!_reportedReady) {
          _reportedReady = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              debugPrint(
                'startup_stage=first_usable_frame elapsed_ms=${_startupClock.elapsedMilliseconds}',
              );
              final client = ref.read(anyworkClientProvider);
              final selection = client.selection.state;
              if (selection.selectedProjectId == null &&
                  selection.selectedThreadId == null) {
                unawaited(
                  client.directoryCommands.beginStandaloneThread().catchError(
                    (Object _) {},
                  ),
                );
              } else {
                unawaited(client.directoryCommands.openSelectedThread());
              }
            }
          });
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < StudioLayout.compactBreakpoint ||
                MediaQuery.textScalerOf(context).scale(14) >= 21;
            final overlay = compact || _sidebarHidden;
            final maximumWidth =
                (constraints.maxWidth - 600 - _sidebarDividerWidth).clamp(
                  300.0,
                  440.0,
                );
            final width = desiredWidth.clamp(300.0, maximumWidth);
            return Scaffold(
              key: _scaffoldKey,
              drawer: overlay
                  ? Drawer(
                      width: (constraints.maxWidth - 24).clamp(0.0, 360.0),
                      child: _Sidebar(
                        key: _sidebarKey,
                        state: sidebar,
                        onNavigate: () =>
                            _scaffoldKey.currentState?.closeDrawer(),
                      ),
                    )
                  : null,
              backgroundColor: context.colors.surface,
              body: KeyedSubtree(
                key: StudioDriverKeys.shell,
                child: Row(
                  children: [
                    if (!overlay) ...[
                      SizedBox(
                        width: width,
                        child: _Sidebar(key: _sidebarKey, state: sidebar),
                      ),
                      Focus(
                        focusNode: _sidebarResizeFocus,
                        onFocusChange: (focused) {
                          setState(() => _sidebarResizeFocused = focused);
                          if (!focused &&
                              !_sidebarDragging &&
                              _sidebarWidth != null) {
                            unawaited(_persistWidth());
                          }
                        },
                        onKeyEvent: (_, event) =>
                            _handleSidebarKey(event, width, maximumWidth),
                        child: Semantics(
                          key: StudioDriverKeys.sidebarResize,
                          label: context.l10n.sidebarResize,
                          slider: true,
                          value: '${width.round()}',
                          increasedValue:
                              '${(width + 16).clamp(300, maximumWidth).round()}',
                          decreasedValue:
                              '${(width - 16).clamp(300, maximumWidth).round()}',
                          onIncrease: () {
                            _adjustSidebarWidth(16, width, maximumWidth);
                            unawaited(_persistWidth());
                          },
                          onDecrease: () {
                            _adjustSidebarWidth(-16, width, maximumWidth);
                            unawaited(_persistWidth());
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: Listener(
                              // EditableText unfocuses on down; take focus afterwards.
                              onPointerUp: (_) =>
                                  _sidebarResizeFocus.requestFocus(),
                              child: GestureDetector(
                                dragStartBehavior: DragStartBehavior.down,
                                onHorizontalDragStart: (_) {
                                  _sidebarDragging = true;
                                  _sidebarResizeFocus.requestFocus();
                                },
                                onHorizontalDragUpdate: (event) =>
                                    _adjustSidebarWidth(
                                      event.delta.dx,
                                      width,
                                      maximumWidth,
                                    ),
                                onHorizontalDragEnd: (_) {
                                  _sidebarDragging = false;
                                  unawaited(_persistWidth());
                                },
                                onHorizontalDragCancel: () {
                                  if (_sidebarDragging) {
                                    _sidebarDragging = false;
                                    _setSidebarWidth(null);
                                  }
                                },
                                onDoubleTap: () {
                                  _setSidebarWidth(336);
                                  unawaited(_persistWidth());
                                },
                                child: Container(
                                  width: _sidebarDividerWidth,
                                  color: _sidebarResizeFocused
                                      ? context.colors.primary
                                      : context.colors.outlineVariant
                                            .withValues(alpha: .5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  key: const ValueKey('sidebar-toggle'),
                                  tooltip: context.l10n.sidebarNavigation,
                                  onPressed: () {
                                    if (overlay) {
                                      _scaffoldKey.currentState?.openDrawer();
                                    } else {
                                      setState(() => _sidebarHidden = true);
                                    }
                                  },
                                  icon: Icon(
                                    overlay ? Icons.menu : Icons.chevron_left,
                                  ),
                                ),
                                if (_sidebarHidden && !compact)
                                  IconButton(
                                    tooltip: context.l10n.sidebarNavigation,
                                    onPressed: () =>
                                        setState(() => _sidebarHidden = false),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                Expanded(child: _Header(state: header)),
                              ],
                            ),
                            if (startup.directoryError case final error?)
                              MaterialBanner(
                                key: const ValueKey(
                                  'project-directory-failure',
                                ),
                                leading: const Icon(Icons.sync_problem),
                                content: Text(error),
                                actions: [
                                  TextButton(
                                    key: const ValueKey(
                                      'project-directory-retry',
                                    ),
                                    onPressed: () => ref
                                        .read(anyworkClientProvider)
                                        .retryResource(
                                          const ProjectDirectoryTopic(),
                                        ),
                                    child: Text(context.l10n.runtimeFatalRetry),
                                  ),
                                ],
                              ),
                            const _PersistenceStatusPanel(),
                            const _StartupRecoveryBanner(),
                            if (chrome.applicationRecoveryIssues.isNotEmpty)
                              _ApplicationRecoveryBanner(
                                issues: chrome.applicationRecoveryIssues,
                              ),
                            const RecoveryCheckStatus(showChecking: false),
                            const Divider(height: 1),
                            Expanded(
                              child: AgentWorkspacePane(
                                threadId: selection.selectedThreadId,
                                needsOpen: selection.needsOpen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
