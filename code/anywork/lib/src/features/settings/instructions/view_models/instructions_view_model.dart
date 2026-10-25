import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../../../app/lifecycle/exit_participant.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/instructions_state.dart';

part 'instructions_view_model.g.dart';

@Riverpod(keepAlive: true)
class InstructionsViewModel extends _$InstructionsViewModel
    implements ApplicationEditProducer {
  final _timers = <InstructionSection, Timer>{};
  final _operationWatches = <InstructionSection, Observation>{};
  late ConfigurationRepository _repository;
  ApplicationEditRegistration? _registration;
  bool _alive = true;
  bool _sealed = false;
  int _lifetime = 0;
  bool _visible = true;
  late VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)>
  _contentRead;
  late VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)>
  _sourceRead;

  @override
  Future<InstructionsViewState> build() async {
    _alive = true;
    _sealed = false;
    final lifetime = ++_lifetime;
    _repository = ref.watch(configurationRepositoryProvider);
    _contentRead = VisibleReadDemand(
      read: (target) async {
        final source = _repository.state.value;
        if (source.projection.stamp?.origin != target.$1 ||
            source.projection.header?.reference != target.$2) {
          return;
        }
        await _repository.loadInstructions();
      },
      changed: (target, error, current) =>
          _readChanged(InstructionsReadField.content, error, current),
    );
    _sourceRead = VisibleReadDemand(
      read: (target) async {
        final source = _repository.state.value;
        if (source.projection.stamp?.origin != target.$1 ||
            source.projection.header?.source.status != target.$2) {
          return;
        }
        await _repository.loadSourceStatus();
      },
      changed: (target, error, current) =>
          _readChanged(InstructionsReadField.sourceStatus, error, current),
    );
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.instructions,
          SettingsTabLifecycle(visibility: setVisible, handoff: leave),
        );
    _visible = tab.visible;
    final watch = _repository.state.watchLatest((source) {
      if (!_alive || lifetime != _lifetime) return;
      final previous = state.asData?.value;
      if (previous == null) return;
      final canonical = displayReadValue(source.instructions);
      final current = isCurrentRead(
        source.instructions,
        source.projection.header?.reference,
        source.projection.stamp?.origin,
      );
      state = AsyncData(
        previous.copyWith(
          source: source,
          canonical: canonical ?? previous.canonical,
          base: _adopt(previous.base, canonical?.baseOverride, current),
          developer: _adopt(previous.developer, canonical?.developer, current),
          user: _adopt(previous.user, canonical?.user, current),
        ),
      );
      _refreshReads();
    });
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final observation in _operationWatches.values) {
        observation.cancel();
      }
      _operationWatches.clear();
      watch.observation.cancel();
      _registration?.unregister();
      _registration = null;
      tab.unregister();
      _contentRead.dispose();
      _sourceRead.dispose();
      // No business writes or Repository close from observer disposal.
    });
    try {
      if (_visible) {
        _registration = ref
            .read(applicationEditProducerRegistryProvider)
            .register(this);
      }
    } on StudioFailure {
      watch.observation.cancel();
      rethrow;
    }
    await _repository.loadInstructions();
    final source = _repository.state.value;
    final value = displayReadValue(source.instructions);
    if (value == null) throw settingsUnavailable('instructions');
    Future<void>(() {
      if (_alive && lifetime == _lifetime) _refreshReads();
    });
    return InstructionsViewState(
      source: source,
      canonical: value,
      base: InstructionDraft(raw: value.baseOverride),
      developer: InstructionDraft(raw: value.developer),
      user: InstructionDraft(raw: value.user),
    );
  }

  void setVisible(bool visible) {
    if (!_alive || _sealed) return;
    _visible = visible;
    if (visible) {
      _registration ??= ref
          .read(applicationEditProducerRegistryProvider)
          .register(this);
    }
    _refreshReads();
  }

  void retryRead() {
    _contentRead.retry();
    _sourceRead.retry();
  }

  void _refreshReads() {
    if (!_alive || state.asData == null) return;
    final source = _repository.state.value;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.reference;
    final status = source.projection.header?.source.status;
    _contentRead.visible(false);
    _sourceRead.visible(false);
    _contentRead.target(
      origin == null || reference == null ? null : (origin, reference),
      needed: !isCurrentRead(source.instructions, reference, origin),
    );
    _sourceRead.target(
      origin == null || status == null ? null : (origin, status),
      needed: !isCurrentRead(source.sourceStatus, status, origin),
    );
    _contentRead.visible(_visible && !_sealed);
    _sourceRead.visible(_visible && !_sealed);
  }

  void _readChanged(
    InstructionsReadField field,
    StudioFailure? error,
    bool current,
  ) {
    if (!_alive || state.asData == null) return;
    final value = state.requireValue;
    final issues = {...value.readIssues};
    final reading = field == InstructionsReadField.content
        ? _contentRead.reading
        : _sourceRead.reading;
    if (current && !reading) {
      if (error == null) {
        issues.remove(field);
      } else {
        issues[field] = error;
      }
    } else if (current && error != null) {
      issues[field] = error;
    }
    state = AsyncData(
      value.copyWith(
        readIssues: issues,
        readPending: _contentRead.reading || _sourceRead.reading,
      ),
    );
  }

  InstructionDraft _adopt(
    InstructionDraft draft,
    String? canonical,
    bool current,
  ) {
    if (canonical == null) return draft;
    if (!draft.dirty) return draft.copyWith(raw: canonical);
    if (current &&
        (draft.action?.succeeded ?? false) &&
        draft.action!.intent == draft.revision &&
        draft.raw == canonical) {
      return draft.copyWith(dirty: false);
    }
    return draft;
  }

  void setSection(InstructionSection section) {
    if (!_alive || _sealed) return;
    state = AsyncData(state.requireValue.copyWith(section: section));
  }

  void edit(InstructionSection section, String raw) {
    if (!_alive || _sealed) return;
    _registration ??= ref
        .read(applicationEditProducerRegistryProvider)
        .register(this);
    final current = _draft(section);
    if (current.raw == raw) return;
    _replace(
      section,
      current.copyWith(raw: raw, revision: current.revision + 1, dirty: true),
    );
    _timers.remove(section)?.cancel();
    _timers[section] = Timer(const Duration(milliseconds: 650), () {
      _timers.remove(section);
      _dispatch(section);
    });
  }

  /// Explicit navigation boundary: synchronously transfer already-formed
  /// intents, then release only this producer registration.
  void leave() {
    if (!_alive) return;
    _visible = false;
    _contentRead.visible(false);
    _sourceRead.visible(false);
    _handoff();
    _registration?.unregister();
    _registration = null;
  }

  @override
  void sealAndHandoff() {
    if (_sealed) return;
    _sealed = true;
    _visible = false;
    _contentRead.visible(false);
    _sourceRead.visible(false);
    _handoff();
  }

  void _handoff() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (state.asData == null) return;
    // Each admission is independent. A synchronous failure must not prevent
    // the remaining fields from handing off their already valid intent.
    for (final section in InstructionSection.values) {
      _dispatch(section);
    }
  }

  void _dispatch(InstructionSection section) {
    if (!_alive || state.asData == null) return;
    final frozen = _draft(section);
    if (!frozen.dirty) return;
    final previous = frozen.action;
    if (previous != null && previous.intent == frozen.revision) return;
    final update = switch (section) {
      InstructionSection.base => SettingsFieldUpdate.instructionBaseOverride(
        value: frozen.raw,
      ),
      InstructionSection.developer => SettingsFieldUpdate.instructionDeveloper(
        value: frozen.raw,
      ),
      InstructionSection.user => SettingsFieldUpdate.instructionUser(
        value: frozen.raw,
      ),
    };
    final lifetime = _lifetime;
    _replace(
      section,
      frozen.copyWith(
        action: SettingsAction(intent: frozen.revision, pending: true),
      ),
    );
    OperationTicket<Unit> ticket;
    try {
      ticket = _repository.applyField(update);
    } on StudioFailure catch (error) {
      if (!_owns(section, frozen.revision, lifetime)) return;
      _replace(
        section,
        _draft(section).copyWith(
          action: SettingsAction(
            intent: frozen.revision,
            outcome: SettingsActionOutcome.rejected,
            error: error,
          ),
        ),
      );
      return;
    }
    if (!_owns(section, frozen.revision, lifetime)) {
      unawaited(_settle(section, frozen, ticket, lifetime));
      return;
    }
    _operationWatches.remove(section)?.cancel();
    StudioFailure? observationError;
    try {
      final watch = ticket.state.watchLatest((operation) {
        if (!_owns(section, frozen.revision, lifetime)) return;
        final draft = _draft(section);
        _replace(
          section,
          draft.copyWith(action: draft.action?.copyWith(operation: operation)),
        );
      });
      _operationWatches[section] = watch.observation;
    } on StudioFailure catch (error) {
      observationError = error; // Does not undo an already-admitted command.
    }
    _replace(
      section,
      _draft(section).copyWith(
        action: SettingsAction(
          intent: frozen.revision,
          pending: true,
          operation: ticket.state.value,
          observationError: observationError,
        ),
      ),
    );
    unawaited(_settle(section, frozen, ticket, lifetime));
  }

  Future<void> _settle(
    InstructionSection section,
    InstructionDraft frozen,
    OperationTicket<Unit> ticket,
    int lifetime,
  ) async {
    final result = await ticket.result;
    if (!_owns(section, frozen.revision, lifetime)) return;
    final current = _draft(section);
    final action = settledSettingsAction(
      frozen.revision,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: current.action?.observationError);
    final source = _repository.state.value;
    final canonical = displayReadValue(source.instructions);
    final text = switch (section) {
      InstructionSection.base => canonical?.baseOverride,
      InstructionSection.developer => canonical?.developer,
      InstructionSection.user => canonical?.user,
    };
    _replace(
      section,
      _adopt(
        current.copyWith(action: action),
        text,
        isCurrentRead(
          source.instructions,
          source.projection.header?.reference,
          source.projection.stamp?.origin,
        ),
      ),
    );
    // A newer raw value may have arrived while the old operation was pending.
    // It has its own intent; do not discard it or reuse the old payload.
    if (action.succeeded &&
        _draft(section).dirty &&
        !_sealed &&
        !_timers.containsKey(section)) {
      _dispatch(section);
    }
  }

  bool _owns(InstructionSection section, int intent, int lifetime) =>
      _alive &&
      lifetime == _lifetime &&
      state.asData != null &&
      _draft(section).action?.intent == intent;

  InstructionDraft _draft(InstructionSection section) {
    final current = state.requireValue;
    return switch (section) {
      InstructionSection.base => current.base,
      InstructionSection.developer => current.developer,
      InstructionSection.user => current.user,
    };
  }

  void _replace(InstructionSection section, InstructionDraft draft) {
    final current = state.requireValue;
    state = AsyncData(switch (section) {
      InstructionSection.base => current.copyWith(base: draft),
      InstructionSection.developer => current.copyWith(developer: draft),
      InstructionSection.user => current.copyWith(user: draft),
    });
  }
}
