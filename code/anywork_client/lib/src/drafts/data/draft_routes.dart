part of 'drafts_repository.dart';

ReadyStartRouteRead _readyStartRoute(_DraftsRepository repo, StartDraftState frozen) {
  final prepared = frozen.routePreparation;
  if (prepared is! ReadyStartRoutePreparation ||
      prepared.result.sources != _routeSources(repo) ||
      prepared.result.intent != _routeIntent(repo, frozen.mode)) {
    throw _draftFailure(
      StudioFailureCode.unavailable,
      'Explicitly prepare the current Start route before submitting.',
    );
  }
  return prepared.result;
}

ConfigurationRoleReadTarget? _routeSources(_DraftsRepository repo) {
  final projection = repo.configuration.state.value.projection;
  final pair = projection.header?.roleRead;
  if (projection.sync.phase != ResourceSyncPhase.ready ||
      projection.stamp == null ||
      pair == null ||
      pair.stamp.closing ||
      pair.configuration.origin != projection.stamp!.origin ||
      pair.configuration.reference != projection.header?.reference)
    return null;
  return pair;
}

StartRouteIntent _routeIntent(_DraftsRepository repo, ThreadModeId mode) {
  final value = repo.preferences.readonly.value;
  final model = value.models[mode.id];
  return StartRouteIntent(
    mode: mode,
    model: model == null
        ? null
        : AccountModelKey(accountId: model.accountId, modelId: model.modelId),
    effort: value.efforts[mode.id],
  );
}

StartRouteRead? _lastRoute(StartRoutePreparation value) => switch (value) {
  ReadyStartRoutePreparation(:final result) => result,
  UnavailableStartRoutePreparation(:final result) => result,
  UnreadStartRoutePreparation(:final lastKnown) ||
  LoadingStartRoutePreparation(:final lastKnown) ||
  FailedStartRoutePreparation(:final lastKnown) => lastKnown,
};

void _invalidateStartRoute(_Start handle) {
  if (handle.disposed) return;
  handle._routeToken++;
  handle._prepareKey = null;
  handle.record.routePreparation(
    StartRoutePreparation.unread(
      intent: _routeIntent(handle.repo, handle.state.value.mode),
      lastKnown: _lastRoute(handle.state.value.routePreparation),
    ),
  );
}

void _invalidateSources(_DraftsRepository repo) {
  if (repo._sealed) return;
  final sources = _routeSources(repo);
  for (final handle in List.of(repo._starts.values)) {
    final state = handle.state.value.routePreparation;
    final prior = switch (state) {
      ReadyStartRoutePreparation(:final result) => result.sources,
      UnavailableStartRoutePreparation(:final result) => result.sources,
      LoadingStartRoutePreparation(:final sources) ||
      FailedStartRoutePreparation(:final sources) => sources,
      UnreadStartRoutePreparation() => sources,
    };
    // A demand that explicitly loads its first sources may bind the resulting
    // pair itself. Replacements of an already captured pair still invalidate.
    if (prior != sources &&
        !(state is LoadingStartRoutePreparation && state.sources == null)) {
      handle.invalidateRoute();
    }
  }
}

void _setStartModel(
  _DraftsRepository repo,
  ThreadModeId mode,
  String accountId,
  String modelId,
) {
  repo.ensureOpen();
  final selected = AccountModelKey(accountId: accountId, modelId: modelId);
  final previous = _routeIntent(repo, mode);
  if (previous.model == selected) return;
  final revision = (repo._routeRevisions[mode.id] ?? 0) + 1;
  final query = SelectModelStartRouteQuery(
    intent: previous,
    selected: selected,
  );
  repo._routeRevisions[mode.id] = revision;
  repo._selections[mode.id] = (revision: revision, query: query);
  final old = repo.preferences.readonly.value;
  // Publish the new intent first: submit validates the prepared intent against
  // this value, so old ready states cannot be consumed by reentrant observers.
  repo.preferences.publish(
    old.copyWith(
      models: {
        ...old.models,
        mode.id: StartModelIntent(accountId: accountId, modelId: modelId),
      },
    ),
  );
  bool current() => !repo._sealed && repo._routeRevisions[mode.id] == revision;
  for (final handle in List.of(repo._starts.values)) {
    if (!current()) return;
    if (handle.state.value.mode != mode) continue;
    handle.record.routeIntentChanged();
    if (!current()) return;
    handle.invalidateRoute();
  }
  for (final handle in List.of(repo._starts.values)) {
    if (!current()) return;
    if (handle.state.value.mode == mode) handle.prepareRoute().ignore();
  }
}

void _setStartEffort(_DraftsRepository repo, ThreadModeId mode, String effort) {
  repo.ensureOpen();
  final old = repo.preferences.readonly.value;
  if (old.efforts[mode.id] == effort) return;
  final revision = (repo._routeRevisions[mode.id] ?? 0) + 1;
  repo._routeRevisions[mode.id] = revision;
  repo._selections.remove(mode.id);
  repo.preferences.publish(
    old.copyWith(efforts: {...old.efforts, mode.id: effort}),
  );
  for (final handle in List.of(repo._starts.values)) {
    if (repo._sealed || repo._routeRevisions[mode.id] != revision) return;
    if (handle.state.value.mode != mode) continue;
    handle.record.routeIntentChanged();
    if (repo._sealed || repo._routeRevisions[mode.id] != revision) return;
    handle.invalidateRoute();
  }
}

Future<void> _prepareStartRoute(_Start handle) {
  final repo = handle.repo;
  repo.ensureOpen();
  final mode = handle.state.value.mode;
  final revision = repo._routeRevisions[mode.id] ?? 0;
  final intent = _routeIntent(repo, mode);
  final query =
      repo._selections[mode.id]?.query ??
      StartRouteQuery.resolve(intent: intent);
  final key = (sources: _routeSources(repo), query: query, revision: revision);
  if (handle._prepareKey == key && handle._preparing != null)
    return handle._preparing!;
  final token = ++handle._routeToken;
  handle._prepareKey = key;
  final last = _lastRoute(handle.state.value.routePreparation);
  final done = Completer<void>();
  handle._preparing = done.future;
  handle._routeWork.add(done.future);
  done.future.ignore();
  bool current() =>
      !repo._sealed &&
      !handle.disposed &&
      handle._routeToken == token &&
      handle.state.value.mode == mode &&
      (repo._routeRevisions[mode.id] ?? 0) == revision;
  ConfigurationRoleReadTarget? sources = key.sources;
  final work = repo.lifetime.run('drafts:prepare-route', () async {
    await Future<void>.value();
    try {
      if (!current())
        throw _draftFailure(
          StudioFailureCode.superseded,
          'The original route demand changed.',
        );
      if (sources == null) {
        await repo.configuration.loadSourceStatus();
        if (!current()) throw resourceCancelled;
        sources = _routeSources(repo);
      }
      final target = sources;
      if (target == null)
        throw _draftFailure(
          StudioFailureCode.unavailable,
          'The original Start route sources are not ready.',
        );
      if (target != _routeSources(repo))
        throw _draftFailure(
          StudioFailureCode.superseded,
          'The Start route sources changed.',
        );
      handle.record.routePreparation(
        StartRoutePreparation.loading(
          sources: target,
          query: query,
          intent: intent,
          lastKnown: last,
        ),
      );
      final read = await repo.configuration.readStartRoute(
        sources: target,
        query: query,
      );
      if (!current() || _routeSources(repo) != target)
        throw _draftFailure(
          StudioFailureCode.superseded,
          'The prepared route belongs to an older draft intent.',
        );
      if (read.sources != target || read.query != query)
        throw resourceProtocol(
          'The Start route reply changed its original sources or query.',
        );
      if (query is SelectModelStartRouteQuery) {
        final pending = repo._selections[mode.id];
        if (pending?.revision != revision || pending?.query != query)
          throw resourceCancelled;
        final normalized = read.intent;
        if (normalized.mode != mode || normalized.model != query.selected) {
          throw resourceProtocol(
            'A model suggestion changed its original selection.',
          );
        }
        repo._selections.remove(mode.id);
        final old = repo.preferences.readonly.value;
        final efforts = Map<String, String>.of(old.efforts);
        final effort = normalized.effort;
        if (effort == null || effort.isEmpty)
          efforts.remove(mode.id);
        else
          efforts[mode.id] = effort;
        final nextRevision = revision + 1;
        repo._routeRevisions[mode.id] = nextRevision;
        repo.preferences.publish(old.copyWith(efforts: efforts));
        // One normalized global per-mode intent; each original matching draft
        // owns its own immutable preparation, not a global route-result store.
        for (final other in List.of(repo._starts.values)) {
          if (repo._sealed ||
              repo._routeRevisions[mode.id] != nextRevision ||
              _routeSources(repo) != target)
            return;
          if (!other.disposed &&
              other.state.value.mode == mode &&
              _routeIntent(repo, mode) == normalized) {
            other.invalidateRoute();
            if (repo._sealed ||
                repo._routeRevisions[mode.id] != nextRevision ||
                _routeSources(repo) != target)
              return;
            _publishRoute(other, read);
          }
        }
      } else {
        if (read.intent != intent)
          throw resourceProtocol(
            'A resolve reply rewrote the raw editing intent.',
          );
        _publishRoute(handle, read);
      }
    } catch (error, stack) {
      repo.remember(error, stack);
      if (current())
        handle.record.routePreparation(
          StartRoutePreparation.failure(
            sources: sources,
            query: query,
            intent: intent,
            error: resourceFailure(error),
            lastKnown: last,
          ),
        );
      rethrow;
    }
  });
  handle.record.routePreparation(
    StartRoutePreparation.loading(
      sources: sources,
      query: query,
      intent: intent,
      lastKnown: last,
    ),
  );
  unawaited(
    work.then<void>(
      (_) {
        handle._routeWork.remove(done.future);
        if (identical(handle._preparing, done.future)) handle._preparing = null;
        done.complete();
      },
      onError: (Object error, StackTrace stack) {
        handle._routeWork.remove(done.future);
        if (identical(handle._preparing, done.future)) handle._preparing = null;
        done.completeError(error, stack);
      },
    ),
  );
  return done.future;
}

void _publishRoute(_Start handle, StartRouteRead read) =>
    handle.record.routePreparation(switch (read) {
      ReadyStartRouteRead() => StartRoutePreparation.ready(result: read),
      UnavailableStartRouteRead() => StartRoutePreparation.unavailable(
        result: read,
      ),
    });
