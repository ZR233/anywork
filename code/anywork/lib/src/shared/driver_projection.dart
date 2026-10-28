import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../app/app_graph.dart';
import '../diagnostics/contracts/timeline_diagnostics.dart';
import '../features/conversation/state/composer_view_state.dart';
import '../features/conversation/state/conversation_view_state.dart';
import '../features/conversation/state/editor_keys.dart';
import '../features/conversation/state/interaction_view_state.dart';
import '../features/conversation/state/plan_view_state.dart';
import '../features/conversation/state/thread_status_state.dart';
import '../features/workspace/state/sidebar_view_state.dart';
import '../features/workspace/state/workspace_view_state.dart';
import 'driver_snapshot.dart';

/// Borrow only values of already mounted presentation owners. A Driver request
/// must not instantiate a provider, create a draft, query a directory or open a
/// Session just to improve diagnostics.
final class DriverViewFacts {
  const DriverViewFacts({
    this.workspace,
    this.sidebar,
    this.startComposer,
    this.threadComposer,
    this.conversation,
    this.interactionEditors,
    this.status,
    this.plan,
    this.acpAccounts,
    this.templates,
  });
  final WorkspaceViewState? workspace;
  final SidebarViewState? sidebar;
  final ComposerViewState? startComposer;
  final ComposerViewState? threadComposer;
  final ConversationViewState? conversation;
  final List<InteractionViewState>? interactionEditors;
  final ThreadStatusViewState? status;
  final PlanViewState? plan;

  /// ACP 接入目录的 canonical 读取结果；`null` 表示设置页还没有读到该事实。
  ///
  /// 传具体 domain 值而不传 feature 私有的 ViewState：`shared` 诊断只消费
  /// `anywork_client` 的领域值，不反向依赖 feature 的私有呈现状态。
  final AcpAccountDirectory? acpAccounts;

  /// Native 账号模板目录；`null` 表示还没有读到。
  final AccountTemplatesValue? templates;
}

/// Synchronous request-local capture of this graph's canonical mirrors.
/// AppGraph is only the composition input; none of its owners escape in values.
DriverSnapshot captureDriverSnapshot(
  AppGraph graph, {
  required DriverViewFacts visible,
  required DriverBotsObservation bots,
}) {
  final selection = graph.workspace.state.value.selection;
  final configurationState = graph.configuration.state.value;
  final selected = selection.threadId;
  final active = graph.conversation.active.value;
  final session = !selection.needsOpen && active?.threadId == selected
      ? active
      : null;
  final execution = session?.execution.value;
  final interactions = session?.interactions.value;
  final conversation =
      session != null &&
          visible.conversation?.threadId == selected &&
          visible.conversation?.execution?.stamp == execution?.stamp
      ? visible.conversation
      : null;
  final metadata = visible.workspace?.selectedMetadata;
  final thread = metadata?.projection.sync.phase == ResourceSyncPhase.ready
      ? currentDriverRead(metadata?.value, metadata?.projection.stamp?.origin)
      : null;
  final currentThread = thread?.id == selected ? thread : null;
  final project = visible.workspace?.selectedProject;
  final agentDirectory = graph.workspace.agents.value;
  String? root;
  List<AgentDirectoryEntry>? agents;
  StudioFailure? directoryError;
  if (selected != null) {
    try {
      root = AgentDirectoryQueries.rootThreadId(
        threadId: selected,
        directory: agentDirectory,
      );
      if (root != null) {
        agents = AgentDirectoryQueries.forRoot(
          rootThreadId: root,
          directory: agentDirectory,
        );
      }
    } on StudioFailure catch (error) {
      // An incomplete/stale directory is Unknown, never a reconstructed tree
      // from Thread windows or hot Sessions. Preserve the typed failure.
      directoryError = error;
    }
  }
  final page = visible.sidebar?.pages[selection.projectId]?.directory;
  final display = graph.timelineDiagnostics.capture();
  final displayMatches =
      selected != null &&
      !selection.needsOpen &&
      session != null &&
      display.timeline?.threadId == selected;
  return DriverSnapshot(
    selection: selection,
    project: project?.id == selection.projectId ? project : null,
    thread: currentThread,
    rootThreadId: root,
    directory: page?.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(page!.threads, page.projection.stamp?.origin)
        : null,
    directoryHasMore: page?.projection.sync.phase == ResourceSyncPhase.ready
        ? page?.projection.header?.hasMore
        : null,
    agents: agents,
    agentDirectoryError: directoryError,
    execution: execution,
    metrics: session?.metrics.value,
    context: session?.context.value,
    threadConfiguration: session?.configuration.value,
    authoring: session?.authoring.value,
    interactions: interactions,
    startDraft:
        selection.projectId != null &&
            visible.startComposer?.key ==
                ComposerKey.start(projectId: selection.projectId!)
        ? visible.startComposer?.startDraft
        : null,
    composer:
        session != null &&
            visible.threadComposer?.key ==
                ComposerKey.thread(threadId: session.threadId)
        ? visible.threadComposer?.draft
        : null,
    configuration: configurationState,
    models: graph.models.state.value,
    operations: graph.operations.records.value,
    persistence: graph.persistence.state.value,
    recovery: graph.recovery.state.value,
    updates: graph.updates.state.value,
    startup: graph.startup.state.value,
    display: displayMatches
        ? display
        : const TimelineDiagnosticsSnapshot(
            timeline: null,
            timelineScroll: null,
          ),
    conversation: conversation,
    interactionEditors: _currentInteractionEditors(
      visible.interactionEditors,
      hostThreadId: session?.threadId,
      conversation: conversation,
      execution: execution,
      interactions: interactions,
    ),
    status:
        session != null &&
            visible.status?.threadId == selected &&
            visible.status?.execution?.stamp == session.execution.value.stamp
        ? visible.status
        : null,
    plan:
        session != null &&
            visible.plan?.threadId == selected &&
            visible.plan?.origin == session.authoring.value.stamp
        ? visible.plan
        : null,
    bots: bots,
    // ACP 事实借自已装配的 owner 的 canonical 镜像：`ReadonlyLatestValue.value`
    // 是同步读取，不注册观察者、不占预算 permit、不触发 `synchronize()`，因此
    // Driver 请求不会改变业务 demand，也不会让未加载的领域变成“已加载空集合”。
    acpAuth: graph.acpAuth.state.value.canonical,
    acpInstall: graph.acpInstall.state.value.canonical,
    // ACP 账号与 Native 模板只能来自设置页既有的有界读取结果：这两项不在
    // ConfigurationState 里，Driver 借用调用方已取得的当前值，不新建 demand。
    // 借用来的目录必须仍是**当前** Settings 快照的读取结果：来源 owner、材料引用
    // 与业务版本三键一致才算 current，否则宁可 null，也不输出上一次 refresh 的
    // last-good 目录。
    acpAccounts: currentAcpAccounts(visible.acpAccounts, configurationState),
    templates: visible.templates,
  );
}

/// Borrow only the current host's mounted material, in the Conversation VM's
/// editor order. Full key equality includes sourceGeneration and hosted refs;
/// matching an interaction ID alone must never revive a retired editor.
List<InteractionViewState>? _currentInteractionEditors(
  List<InteractionViewState>? editors, {
  required String? hostThreadId,
  required ConversationViewState? conversation,
  required ThreadExecutionState? execution,
  required InteractionIndexReadState? interactions,
}) {
  final origin = execution?.stamp;
  final index = conversation?.interactions;
  final current = interactions?.current;
  if (editors == null ||
      conversation == null ||
      hostThreadId == null ||
      execution?.sync.phase != FacetSyncPhase.ready ||
      execution?.value == null ||
      origin == null ||
      origin.facet != ThreadFacet.execution ||
      conversation.indexError != null ||
      index?.error != null ||
      interactions?.error != null ||
      current == null ||
      index?.current?.origin != current.origin ||
      index?.current?.index.reference != current.index.reference ||
      current.origin.runtimeEpoch != origin.runtimeEpoch ||
      current.origin.incarnation != origin.incarnation ||
      current.index.reference != execution?.value?.interactions.reference) {
    return null;
  }
  final values = <InteractionViewState>[];
  for (final key in conversation.currentEditors) {
    final matches = editors.where((editor) => editor.key == key).toList();
    if (matches.length != 1) continue;
    final editor = matches.single;
    final header = editor.header;
    final scope = editor.scope;
    if (key.threadId != hostThreadId ||
        key.runtimeEpoch != origin.runtimeEpoch ||
        key.incarnation != origin.incarnation ||
        !editor.sourceCurrent ||
        editor.closing ||
        editor.readIssues.isNotEmpty ||
        editor.texts.values.any((text) => text.error != null) ||
        editor.questions.values.any(
          (question) => question.optionsError != null,
        ) ||
        header == null ||
        scope == null ||
        scope != header.scope ||
        scope.runtimeEpoch != origin.runtimeEpoch ||
        scope.incarnation != origin.incarnation ||
        scope.sourceRevision != key.revision ||
        header.revision != key.revision ||
        editor.textOf(header.interactionId) != key.interactionId ||
        // The header belongs to the actual target; its scope still belongs to
        // the host index owner, including for hosted child interactions.
        editor.textOf(header.threadId) != key.target ||
        header.state is! PendingInteractionRead ||
        (key.isHosted &&
            (key.hostedReference?.revision != key.revision ||
                key.hostedOrigin?.facet != ThreadFacet.execution ||
                key.hostedOrigin?.runtimeEpoch != origin.runtimeEpoch ||
                key.hostedOrigin?.incarnation != origin.incarnation ||
                header.purpose is PlanConfirmationPurposeRead))) {
      continue;
    }
    values.add(editor);
  }
  // An unopened, failed or stale editor is Unknown, not an empty interaction
  // collection. A nonempty result may be only the mounted part of the index.
  if (values.isEmpty &&
      (conversation.currentEditors.isNotEmpty || !current.complete)) {
    return null;
  }
  return values;
}

/// ACP 接入目录只有在仍属于**当前** Settings 快照时才允许作为 current 事实。
///
/// 三键必须同时成立：读取来源 owner（[AcpAccountDirectory.origin]，ownerEpoch +
/// incarnation）、材料引用（[AcpAccountDirectory.reference]）与 Settings 业务版本
/// （[ConfigurationHeader.configurationRevision]）。任一缺失或不一致都返回 null：
/// 不能把上一次成功读取的 last-good 目录当成当前事实，也不为未加载的领域伪造
/// 空目录。与 [currentDriverRead] 同一判定风格，只在这里定义一次，不复制第二套算法。
AcpAccountDirectory? currentAcpAccounts(
  AcpAccountDirectory? directory,
  ConfigurationState configuration,
) {
  if (directory == null) return null;
  final projection = configuration.projection;
  if (projection.sync.phase != ResourceSyncPhase.ready) return null;
  final origin = projection.stamp?.origin;
  final header = projection.header;
  if (origin == null || header == null) return null;
  if (directory.origin != origin) return null;
  final reference = header.reference;
  if (reference == null || directory.reference != reference) return null;
  final revision = header.configurationRevision;
  if (revision == null || directory.revision != revision) return null;
  return directory;
}

/// Never promote `previous` material to current evidence. Callers additionally
/// validate the owning projection/reference when a header provides one.
T? currentDriverRead<T, R>(
  ReadValue<T, R>? value,
  ProductReadOrigin? origin, {
  R? reference,
}) => switch (value) {
  ReadyReadValue<T, R>(:final current)
      when origin != null &&
          current.origin == origin &&
          (reference == null || current.reference == reference) =>
    current.value,
  _ => null,
};

/// A current partial page remains partial; unavailable/incomplete rows are not
/// converted to a successful empty page. There is no last-known fallback.
List<T>? currentDriverRows<T>(
  CollectionMirror<T> mirror,
  ProductReadOrigin? origin,
) {
  if (mirror is! CurrentCollectionMirror<T> ||
      origin == null ||
      mirror.window.origin != origin) {
    return null;
  }
  final window = mirror.window;
  final rows = <T>[];
  for (final reference in window.entries) {
    final row = window.rows[reference.entry];
    if (row is! ReadyReadValue<T, ProductEntityRef> ||
        row.current.origin != origin ||
        row.current.reference != reference) {
      return null;
    }
    rows.add(row.current.value);
  }
  return List.unmodifiable(rows);
}
