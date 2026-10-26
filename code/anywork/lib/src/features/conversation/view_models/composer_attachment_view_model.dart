import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../presentation/model_route_presentation.dart';
import '../state/composer_view_state.dart';
import '../state/editor_keys.dart';
import 'composer_view_model.dart';
import 'thread_status_view_model.dart';

part 'composer_attachment_view_model.g.dart';

typedef _AttachmentTarget = ({
  ComposerKey key,
  Object draft,
  ConversationSession? session,
  Object routeSource,
  ModelSelection selection,
  ModelsRepository models,
  ProductProjection<ModelCatalogHeader> catalog,
});

/// Borrows the already-owned draft and route reader. Only a current exact-model
/// read can enable an entry; neither a last-known route nor a catalog page can.
@riverpod
class ComposerAttachmentViewModel extends _$ComposerAttachmentViewModel {
  late ModelsRepository _models;
  late DraftsRepository _drafts;
  late ConversationRepository _conversations;
  Object? _lifetime;
  _AttachmentTarget? _target;
  int _generation = 0;
  bool _scheduled = false;

  @override
  FutureOr<ComposerAttachmentState> build(ComposerKey target) {
    final lifetime = Object();
    _lifetime = lifetime;
    _target = null;
    _scheduled = false;
    _models = ref.watch(modelsRepositoryProvider);
    _drafts = ref.watch(draftsRepositoryProvider);
    _conversations = ref.watch(conversationRepositoryProvider);
    Observation? models;
    Observation? active;
    void Function()? endRouteDemand;
    ref.onDispose(() {
      if (identical(_lifetime, lifetime)) _lifetime = null;
      models?.cancel();
      active?.cancel();
      endRouteDemand?.call();
      // The original repositories/read owner retain in-flight query cleanup.
    });
    ref.listen(
      composerViewModelProvider(target),
      (_, _) => _schedule(lifetime),
    );
    if (target case ThreadComposerKey(:final threadId)) {
      ref.listen(
        threadStatusViewModelProvider(threadId),
        (_, _) => _schedule(lifetime),
      );
      active = _conversations.active
          .watchLatest((_) => _schedule(lifetime))
          .observation;
      scheduleMicrotask(() {
        if (!_owns(lifetime)) return;
        // Uses the same reader/demand as the visible model selector. No second
        // Session configuration scope or route lookup is opened here.
        endRouteDemand = ref
            .read(threadStatusViewModelProvider(threadId).notifier)
            .beginModelRouteDemand();
        _schedule(lifetime);
      });
    }
    models = _models.state.watchLatest((_) => _schedule(lifetime)).observation;
    _schedule(lifetime);
    return const ComposerAttachmentState();
  }

  bool _owns(Object lifetime) => ref.mounted && identical(_lifetime, lifetime);

  void _schedule(Object lifetime) {
    if (!_owns(lifetime) || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      if (!_owns(lifetime)) return;
      _scheduled = false;
      if (!state.hasValue) return;
      final next = _capture();
      if (next != null && next == _target) return;
      _target = next;
      final generation = ++_generation;
      state = AsyncData(
        ComposerAttachmentState(
          error: next == null
              ? _models.state.value.projection.sync.error
              : null,
        ),
      );
      if (next != null) unawaited(_read(next, lifetime, generation));
    });
  }

  _AttachmentTarget? _capture() {
    final composer = ref.read(composerViewModelProvider(target)).value;
    if (composer == null || composer.closing) return null;
    final Object draft;
    final ConversationSession? session;
    final Object routeSource;
    final ModelSelection selection;
    switch (target) {
      case StartComposerKey(:final projectId):
        final preparation = composer.startDraft?.routePreparation;
        if (preparation is! ReadyStartRoutePreparation) return null;
        final start = _drafts.start(projectId);
        final original = start.state.value;
        if (original.stamp.draftId != composer.startDraft?.stamp.draftId ||
            original.routePreparation != preparation) {
          return null;
        }
        draft = start;
        session = null;
        routeSource = preparation.result;
        selection = preparation.result.route;
      case ThreadComposerKey(:final threadId):
        if (composer.draft == null) return null;
        session = _conversations.existingSession(threadId);
        final status = ref.read(threadStatusViewModelProvider(threadId)).value;
        if (session == null ||
            status == null ||
            session.configuration.value != status.configuration) {
          return null;
        }
        final route = currentModelRoute(status);
        if (route == null || !route.available) return null;
        final original = _drafts.composer(threadId);
        if (original.state.value.stamp.draftId !=
            composer.draft!.stamp.draftId) {
          return null;
        }
        draft = original;
        routeSource = (
          status.configuration?.stamp,
          status.configuration?.value?.details,
          status.configurationRead.header?.scope,
          route,
        );
        selection = ModelSelection(
          model: AccountModelKey(
            accountId: route.accountId,
            modelId: route.modelId,
          ),
          effort: route.effort,
        );
    }
    final catalog = _models.state.value.projection;
    // A first exact read may bootstrap an idle catalog. Reconnect/failure is
    // owned by the repository, not a loop of UI-triggered retrying model reads.
    if (catalog.sync.phase != ResourceSyncPhase.idle &&
        catalog.sync.phase != ResourceSyncPhase.ready) {
      return null;
    }
    if (catalog.sync.phase == ResourceSyncPhase.ready &&
        (catalog.stamp == null || catalog.header?.reference == null)) {
      return null;
    }
    return (
      key: target,
      draft: draft,
      session: session,
      routeSource: routeSource,
      selection: selection,
      models: _models,
      catalog: catalog,
    );
  }

  bool _current(_AttachmentTarget frozen, Object lifetime, int generation) =>
      _owns(lifetime) &&
      state.hasValue &&
      generation == _generation &&
      _target == frozen &&
      _capture() == frozen;

  Future<void> _read(
    _AttachmentTarget frozen,
    Object lifetime,
    int generation,
  ) async {
    // Freeze concrete draft/Session, complete route/source/version, catalog
    // projection and generation before the repository's first await. These two
    // domains are not claimed to be a cross-domain atomic snapshot.
    try {
      final model = await frozen.models.loadModel(
        frozen.selection.model.accountId,
        frozen.selection.model.modelId,
      );
      if (!_current(frozen, lifetime, generation)) return;
      final input = model.capabilities.input.where(
        (capability) => capability.modality != ModelModality.text,
      );
      state = AsyncData(
        ComposerAttachmentState(
          local: input
              .where(
                (capability) =>
                    capability.sources.contains(ModelInputSource.local),
              )
              .toList(growable: false),
          remote: input
              .where(
                (capability) =>
                    capability.sources.contains(ModelInputSource.remoteUrl),
              )
              .toList(growable: false),
        ),
      );
    } on StudioFailure catch (error) {
      if (_current(frozen, lifetime, generation)) {
        state = AsyncData(ComposerAttachmentState(error: error));
      }
    }
  }

  /// A callback belongs to the snapshot actually rendered, not a newer result
  /// with coincidentally equal modalities that arrived before the next frame.
  bool allowsLocal(ComposerAttachmentState? shown) =>
      ref.mounted &&
      _lifetime != null &&
      identical(state.value, shown) &&
      state.value?.local.isNotEmpty == true &&
      _capture() == _target;
  bool allowsRemote(ComposerAttachmentState? shown) =>
      ref.mounted &&
      _lifetime != null &&
      identical(state.value, shown) &&
      state.value?.remote.isNotEmpty == true &&
      _capture() == _target;
}
