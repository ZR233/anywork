import 'dart:async';

import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../state/ssh_editor_state.dart';
import 'ssh_operation_watch.dart';

part 'ssh_editor_view_model.g.dart';

@riverpod
class SshEditorViewModel extends _$SshEditorViewModel {
  late RemoteRepository _repository;
  final _operation = SshOperationWatch();
  bool _alive = true;
  bool _saving = false;
  int _lifetime = 0;
  int _intent = 0;
  void Function()? _releaseRetention;

  @override
  Future<SshEditorViewState> build(SshEditorKey target) async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(remoteRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    // Deferred, coalesced publication for the build-time registration.
    RemoteState? pendingSource;
    var sourceScheduled = false;
    void publishSource(RemoteState source) {
      if (!_owns(lifetime) || state.asData == null) return;
      pendingSource = source;
      if (sourceScheduled) return;
      sourceScheduled = true;
      scheduleMicrotask(() {
        sourceScheduled = false;
        final next = pendingSource;
        pendingSource = null;
        if (!_owns(lifetime) || next == null) return;
        final current = state.asData?.value;
        if (current == null) return;
        final canonical = next.servers
            ?.where((entry) => entry.profile.alias == target.alias)
            .firstOrNull;
        if (canonical != null) {
          state = AsyncData(current.copyWith(canonical: canonical));
        }
      });
    }

    final watch = _repository.state.watchLatest(publishSource);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      watch.observation.cancel();
      _operation.dispose();
      // Manual form: no save, secret rewrite or business cancellation here.
    });
    final existing = watch.value.servers
        ?.where((entry) => entry.profile.alias == target.alias)
        .firstOrNull;
    if (target.alias != null && existing == null) {
      throw StudioFailure(
        code: watch.value.servers == null
            ? StudioFailureCode.notInitialized
            : StudioFailureCode.notFound,
        message: 'The SSH entry is not currently available.',
        retryable: true,
        correlationId: 'ssh-editor-entry',
      );
    }
    final profile = existing?.profile;
    return SshEditorViewState(
      target: target,
      canonical: existing,
      alias: profile?.alias ?? '',
      host: profile?.hostName ?? '',
      port: '${profile?.port ?? 22}',
      username: profile?.username ?? '',
      identityFile: profile?.identityFile ?? '',
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;
  bool get _editable =>
      _alive &&
      !_saving &&
      state.asData != null &&
      !state.requireValue.readOnly &&
      !(state.requireValue.saveAction?.preventsResubmission ?? false);
  void endEditing() {
    _alive = false;
    _releaseRetention?.call();
    _releaseRetention = null;
  }

  void setField(SshEditorField field, String raw) {
    if (!_editable ||
        field == SshEditorField.alias && state.requireValue.editing) {
      return;
    }
    final current = state.requireValue;
    final next = switch (field) {
      SshEditorField.alias => current.copyWith(alias: raw),
      SshEditorField.host => current.copyWith(host: raw),
      SshEditorField.port => current.copyWith(port: raw),
      SshEditorField.username => current.copyWith(username: raw),
      SshEditorField.identityFile => current.copyWith(identityFile: raw),
    };
    if (next != current) {
      state = AsyncData(
        next.copyWith(
          dirty: true,
          draftRevision: current.draftRevision + 1,
          validation: {...current.validation}..remove(field),
        ),
      );
    }
  }

  void setPassword(String raw) {
    if (!_editable || state.requireValue.password == raw) return;
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        password: raw,
        dirty: true,
        draftRevision: current.draftRevision + 1,
        passwordIntent: raw.trim().isEmpty
            ? SshSecretIntent.preserve
            : SshSecretIntent.replace,
      ),
    );
  }

  void clearPassword() {
    if (!_editable) return;
    state = AsyncData(
      state.requireValue.copyWith(
        password: '',
        passwordIntent: SshSecretIntent.clear,
        dirty: true,
        draftRevision: state.requireValue.draftRevision + 1,
      ),
    );
  }

  void togglePasswordVisibility() {
    if (_alive && state.asData != null) {
      state = AsyncData(
        state.requireValue.copyWith(
          passwordVisible: !state.requireValue.passwordVisible,
        ),
      );
    }
  }

  static Map<SshEditorField, SshValidation> _validate(
    SshEditorViewState value,
  ) {
    final alias = value.alias.trim();
    final port = int.tryParse(value.port.trim());
    return {
      if (alias.isEmpty)
        SshEditorField.alias: SshValidation.required
      else if (alias.startsWith('-') ||
          alias.contains(RegExp("[\\s*?\\[\\]!#\"'\\\\]")))
        SshEditorField.alias: SshValidation.aliasInvalid,
      if (value.host.trim().isEmpty)
        SshEditorField.host: SshValidation.required,
      if (value.username.trim().isEmpty)
        SshEditorField.username: SshValidation.required,
      if (port == null || port <= 0 || port > 65535)
        SshEditorField.port: SshValidation.portInvalid,
    };
  }

  Future<SshServerRuntimeEntry?> save() async {
    if (!_editable) return null;
    _saving = true;
    try {
      final lifetime = _lifetime;
      final frozen = state.requireValue;
      final validation = _validate(frozen);
      state = AsyncData(frozen.copyWith(validation: validation));
      if (validation.isNotEmpty || !_owns(lifetime)) return null;
      final repository = _repository;
      final intent = ++_intent;
      final profile = SshServerProfile(
        alias: frozen.alias.trim(),
        hostName: frozen.host.trim(),
        port: int.parse(frozen.port.trim()),
        username: frozen.username.trim(),
        identityFile: frozen.identityFile.trim().isEmpty
            ? null
            : frozen.identityFile.trim(),
      );
      final password = switch (frozen.passwordIntent) {
        SshSecretIntent.preserve => const SshPasswordUpdate.preserve(),
        SshSecretIntent.replace => SshPasswordUpdate.replace(
          value: frozen.password,
        ),
        SshSecretIntent.clear => const SshPasswordUpdate.clear(),
      };
      state = AsyncData(
        state.requireValue.copyWith(
          saveAction: SettingsAction(intent: intent, pending: true),
        ),
      );
      bool owns() =>
          _owns(lifetime) && state.requireValue.saveAction?.intent == intent;
      if (!owns()) return null;
      final result = await _operation.run(
        intent: intent,
        admit: () => repository.save(profile, password),
        owns: owns,
        update: (action) =>
            state = AsyncData(state.requireValue.copyWith(saveAction: action)),
      );
      final saved = result.value;
      if (!owns() ||
          !result.action.succeeded ||
          saved == null ||
          state.requireValue.draftRevision != frozen.draftRevision) {
        return null;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          password: '',
          passwordIntent: SshSecretIntent.preserve,
          dirty: false,
        ),
      );
      return saved;
    } finally {
      _saving = false;
    }
  }
}
