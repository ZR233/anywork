import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'acp_command_notice.dart';

part 'acp_account_view_model.g.dart';

/// A local start is admitted only without a busy canonical operation. The first
/// matching busy observation witnesses its id; later operations cannot inherit
/// this Future's error, even when they use the same account and connection.
final class _AuthenticationAttempt {
  _AuthenticationAttempt(this.initial);

  final AcpAuthStateView initial;
  String? operationId;
  AcpAuthStateView? settled;

  bool observe(AcpAuthStateView auth) {
    final operation = auth.operationId;
    if (operation != null) {
      if (settled != null) return false;
      operationId ??= operation;
      return operationId == operation;
    }
    if (operationId == null) return auth == initial;
    settled ??= auth;
    return auth == settled;
  }
}

/// ACP display/intent ownership. It does not own configuration or synthesize
/// authentication/install success. Start and cancel have independent lanes.
@riverpod
class AcpAccountViewModel extends _$AcpAccountViewModel {
  late AcpService _service;
  late AccountsRepository _accounts;
  late AccountAcpKey _key;
  late AcpProviderView _provider;
  late AcpPreparationIntent _intent;
  AccountStrings _strings = const AccountStrings.empty();
  String? _selectedMethod;
  String? _error;
  AcpCommandNotice? _authNotice;
  int _sequence = 0;
  int? _preparing;
  _AuthenticationAttempt? _authenticating;
  ({int sequence, String operation})? _cancelInstall;
  ({int sequence, String operation})? _cancelAuth;
  bool _finished = false;
  String? _authOwnerEpoch;
  String? _installOwnerEpoch;
  bool _wasStale = false;
  void Function()? _cancelBaselineWait;

  @override
  FutureOr<AccountAcpViewState> build(AccountAcpKey key) {
    _key = key;
    _provider =
        AcpProviderView.fromWire(key.providerId) ??
        (throw StateError('Unknown ACP provider: ${key.providerId}'));
    _intent = AcpPreparationIntent(provider: _provider);
    _service = ref.read(acpServiceProvider);
    _accounts = ref.read(accountsRepositoryProvider);
    _authOwnerEpoch =
        _service.auth.value.stamp?.ownerEpoch ??
        _accounts.state.value.stamp?.ownerEpoch;
    _installOwnerEpoch =
        _service.install.value.stamp?.ownerEpoch ??
        _accounts.state.value.stamp?.ownerEpoch;
    _wasStale =
        _service.auth.value.stale ||
        _service.install.value.stale ||
        _accounts.state.value.stale;
    final authDemand = _service.observeAuth();
    final installDemand = _service.observeInstall();
    final observations = [
      _service.auth.watch((_) => _sourceChanged()),
      _service.install.watch((_) => _sourceChanged()),
      _service.templates.watch((_) => _publish()),
      _accounts.state.watch((_) => _sourceChanged()),
    ];
    ref.onDispose(() {
      _cancelBaselineWait?.call();
      releaseAccountDemand(authDemand);
      releaseAccountDemand(installDemand);
      for (final observation in observations) {
        observation.cancel();
      }
    });
    return _derive();
  }

  AcpAccountTemplateView? get _template =>
      _service.templates.value.template(_provider);
  String? documentationUrl(AcpAccountAction action) =>
      action == AcpAccountAction.openGuide
      ? _template?.installUrl
      : _template?.termsUrl;
  AcpInstallStateView get _install =>
      _service.install.value.value?.stateOf(_provider) ??
      const AcpInstallIdleState();
  AcpAuthStateView get _auth {
    if (_key.creating || _service.auth.value.stale) {
      return const AcpUncheckedState();
    }
    return _service.auth.value.value?.stateOf(
          _key.target.id,
          connectionRevision: _key.connectionRevision,
        ) ??
        const AcpUncheckedState();
  }

  bool get _preparedForEditor =>
      !_service.install.value.stale &&
      _intent.resolve(_install, provider: _provider) != null;

  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  void finish() {
    _finished = true;
    _intent = _intent.renewed();
    _cancelBaselineWait?.call();
  }

  void selectMethod(String id) {
    if (_auth case AcpRequiredState(:final agentMethods)) {
      if (agentMethods.any((method) => method.id == id)) {
        _selectedMethod = id;
        _publish();
      }
    }
  }

  /// Only a user action (including explicitly selecting a template) calls this.
  Future<void> prepare() async {
    if (_preparing != null ||
        _finished ||
        _template?.automaticInstall.isAvailable != true) {
      return;
    }
    final known = _service.install.value;
    if (known.loaded && known.value?.stateOf(_provider).server != null) return;
    final attempt = ++_sequence;
    _preparing = attempt;
    _intent = _intent.renewed();
    final generation = _intent.generation;
    _error = null;
    _publish();
    try {
      if (!_ownsPrepare(attempt, generation)) return;
      final initial = _service.install.value;
      if (initial.failure case final failure?) throw failure;
      if (!initial.loaded || initial.value == null) {
        if (!await _waitForInstallBaseline(attempt, generation)) return;
      }
      if (!_ownsPrepare(attempt, generation)) return;
      final current = _service.install.value;
      if (!current.loaded || current.value == null) {
        _error = _strings['stale'];
        return;
      }
      // Shared Ready is a real, unclaimed installation. Starting another
      // operation merely to obtain a receipt would bypass explicit usePrepared.
      final installation = current.value!.stateOf(_provider);
      if (installation.server != null || installation.isBusy) return;
      final snapshot = await _service.prepare(_provider);
      if (!_ownsPrepare(attempt, generation)) return;
      final operation = snapshot.stateOf(_provider).operationId;
      if (operation != null) _intent = _intent.claim(operation);
    } catch (error) {
      if (_ownsPrepare(attempt, generation)) {
        _error = safeAccountError(error, _strings);
      }
    } finally {
      if (_ownsPrepare(attempt, generation)) {
        _preparing = null;
        _publish();
      }
    }
  }

  bool _ownsPrepare(int attempt, int generation) =>
      ref.mounted &&
      !_finished &&
      _preparing == attempt &&
      _intent.generation == generation;

  Future<bool> _waitForInstallBaseline(int attempt, int generation) {
    final completion = Completer<bool>();
    Observation? observation;
    Timer? deadline;
    late final void Function() cancel;
    void settle(bool ready, {Object? error}) {
      if (completion.isCompleted) return;
      observation?.cancel();
      deadline?.cancel();
      if (identical(_cancelBaselineWait, cancel)) _cancelBaselineWait = null;
      if (error != null) {
        completion.completeError(error);
      } else {
        completion.complete(ready);
      }
    }

    cancel = () => settle(false);
    _cancelBaselineWait = cancel;
    void inspect(AccountResource<AcpInstallSnapshotView> resource) {
      if (!_ownsPrepare(attempt, generation)) {
        settle(false);
        return;
      }
      if (resource.failure case final failure?) {
        settle(false, error: failure);
        return;
      }
      if (resource.loaded && resource.value != null) settle(true);
    }

    // Registration and its initial snapshot are one synchronous transaction.
    // Retire only this local wait on timeout/finish; the service keeps its owner.
    final registered = _service.install.watchLatest(inspect);
    observation = registered.observation;
    if (completion.isCompleted) {
      observation.cancel();
    } else {
      deadline = Timer(
        const Duration(seconds: 10),
        () => settle(
          false,
          error: TimeoutException('Install observation baseline'),
        ),
      );
      inspect(registered.value);
    }
    return completion.future;
  }

  void usePrepared() {
    if (_preparing != null || _finished || !_service.install.value.loaded) {
      return;
    }
    final operation = _install.operationId;
    if (_install.server == null || operation == null) return;
    _intent = _intent.renewed().claim(operation);
    _error = null;
    _publish();
  }

  Future<void> cancelPreparation() async {
    final operation = _install.operationId;
    if (_service.install.value.stale ||
        operation == null ||
        !_install.isBusy ||
        _cancelInstall?.operation == operation) {
      return;
    }
    final attempt = (sequence: ++_sequence, operation: operation);
    _cancelInstall = attempt;
    _publish();
    try {
      if (_finished ||
          _cancelInstall != attempt ||
          _install.operationId != operation) {
        return;
      }
      await _service.cancelPreparation(_provider);
    } catch (error) {
      if (ref.mounted &&
          !_finished &&
          _cancelInstall == attempt &&
          _install.operationId == operation) {
        _error = safeAccountError(error, _strings);
      }
    } finally {
      if (ref.mounted && _cancelInstall == attempt) {
        _cancelInstall = null;
        _publish();
      }
    }
  }

  bool get _currentConnection {
    final summary = _accounts.state.value.account(
      AcpAccountIdentity(_key.target.id),
    );
    if (!_accounts.state.value.loaded ||
        summary == null ||
        summary.acpConnectionRevision != _key.connectionRevision) {
      return false;
    }
    // This VM exists only alongside an explicit target detail/editor demand.
    final resource = _accounts
        .details(AcpAccountIdentity(_key.target.id))
        .value;
    final detail = resource.value;
    return resource.loaded &&
        detail is AcpAccountDetails &&
        detail.account.connectionRevision == _key.connectionRevision;
  }

  AcpAccountSettingsView? get _account {
    if (_key.creating) return null;
    final detail = _accounts
        .details(AcpAccountIdentity(_key.target.id))
        .value
        .value;
    return detail is AcpAccountDetails ? detail.account : null;
  }

  AcpCommandNotice _notice(Object error, {required String? operation}) =>
      AcpCommandNotice(
        kind: AcpCommandNoticeKind.authentication,
        summary: safeAccountError(error, _strings),
        accountId: _key.target.id,
        connectionRevision: _key.connectionRevision,
        operationId: operation,
      );

  Future<void> authenticate({bool login = false}) async {
    if (_service.auth.value.stale ||
        _authenticating != null ||
        _auth.isBusy ||
        !_currentConnection) {
      return;
    }
    final methods = _auth is AcpRequiredState
        ? (_auth as AcpRequiredState).agentMethods
        : const <AcpAuthMethodView>[];
    final method =
        methods
            .where((method) => method.id == _selectedMethod)
            .firstOrNull
            ?.id ??
        methods.firstOrNull?.id;
    if (login && method == null) return;
    final attempt = _AuthenticationAttempt(_auth);
    _authenticating = attempt;
    _error = null;
    _authNotice = null;
    _publish();
    try {
      if (!_ownsAuthentication(attempt)) return;
      if (login) {
        await _service.login(
          AcpAccountIdentity(_key.target.id),
          methodId: method!,
        );
      } else {
        await _service.check(AcpAccountIdentity(_key.target.id));
      }
    } catch (error) {
      if (_ownsAuthentication(attempt)) {
        if (!isAcpAuthDuplicateWhileInFlight(
          error: error,
          accountId: _key.target.id,
          requestConnectionRevision: _key.connectionRevision,
          account: _account,
          auth: _auth,
        )) {
          _authNotice = _notice(error, operation: attempt.operationId);
        }
      }
    } finally {
      if (ref.mounted && identical(_authenticating, attempt)) {
        _authenticating = null;
        _publish();
      }
    }
  }

  bool _ownsAuthentication(_AuthenticationAttempt attempt) =>
      ref.mounted &&
      !_finished &&
      identical(_authenticating, attempt) &&
      _currentConnection;

  Future<void> cancelAuthentication() async {
    final operation = _auth.operationId;
    if (_service.auth.value.stale ||
        operation == null ||
        !_auth.isBusy ||
        _cancelAuth?.operation == operation ||
        !_currentConnection) {
      return;
    }
    final attempt = (sequence: ++_sequence, operation: operation);
    _cancelAuth = attempt;
    _publish();
    try {
      if (_finished ||
          _cancelAuth != attempt ||
          _auth.operationId != operation ||
          !_currentConnection) {
        return;
      }
      await _service.cancelAuth(AcpAccountIdentity(_key.target.id));
    } catch (error) {
      if (ref.mounted &&
          !_finished &&
          _cancelAuth == attempt &&
          _auth.operationId == operation &&
          _currentConnection) {
        _authNotice = _notice(error, operation: operation);
      }
    } finally {
      if (ref.mounted && _cancelAuth == attempt) {
        _cancelAuth = null;
        _publish();
      }
    }
  }

  AccountAcpViewState _derive() {
    final install = _install;
    final auth = _auth;
    final preparing = install.isBusy || _preparing != null;
    final requiresPreparation =
        auth is AcpFailedState &&
        (auth.failure.code == AcpAuthFailureCodeView.preparationRequired ||
            auth.failure.code == AcpAuthFailureCodeView.installationInvalid);
    final showInstall =
        _key.creating ||
        preparing ||
        (requiresPreparation && !_preparedForEditor);
    final methods = auth is AcpRequiredState
        ? auth.agentMethods
        : const <AcpAuthMethodView>[];
    final selected = methods.any((method) => method.id == _selectedMethod)
        ? _selectedMethod
        : methods.firstOrNull?.id;
    final phase = showInstall
        ? preparing
              ? AcpPresentationPhase.preparing
              : install is AcpInstallFailedState
              ? AcpPresentationPhase.failed
              : install.isReady
              ? AcpPresentationPhase.ready
              : AcpPresentationPhase.idle
        : switch (auth) {
            AcpCheckingState() => AcpPresentationPhase.checking,
            AcpRequiredState() => AcpPresentationPhase.needsLogin,
            AcpAuthenticatingState() => AcpPresentationPhase.authenticating,
            AcpVerifyingState() => AcpPresentationPhase.verifying,
            AcpVerifiedState() => AcpPresentationPhase.connected,
            AcpCancellingState() => AcpPresentationPhase.cancelling,
            AcpClosingState() => AcpPresentationPhase.closing,
            AcpFailedState() => AcpPresentationPhase.failed,
            _ => AcpPresentationPhase.idle,
          };
    final actions = <AcpAccountAction>[
      if (showInstall && !_service.install.value.stale) ...[
        if (install.isBusy && _cancelInstall?.operation != install.operationId)
          AcpAccountAction.cancelPreparation,
        if (!preparing && !_preparedForEditor && install.server != null)
          AcpAccountAction.usePrepared,
        if (!preparing &&
            !install.isReady &&
            _template?.automaticInstall.isAvailable == true)
          AcpAccountAction.prepare,
      ] else if (!showInstall) ...[
        if (auth.isBusy && _cancelAuth?.operation != auth.operationId)
          AcpAccountAction.cancelAuthentication,
        if (!auth.isBusy &&
            _authenticating == null &&
            !_service.auth.value.stale) ...[
          if (methods.isNotEmpty) AcpAccountAction.login,
          AcpAccountAction.check,
          if (auth is AcpFailedState && auth.failure.retryable)
            AcpAccountAction.retry,
        ],
      ],
      if (showInstall &&
          auth.isBusy &&
          _cancelAuth?.operation != auth.operationId)
        AcpAccountAction.cancelAuthentication,
      if (_template?.installUrl.isNotEmpty == true) AcpAccountAction.openGuide,
      if (_template?.termsUrl.isNotEmpty == true) AcpAccountAction.openTerms,
    ];
    final primary = [
      AcpAccountAction.usePrepared,
      AcpAccountAction.prepare,
      AcpAccountAction.login,
      AcpAccountAction.retry,
      AcpAccountAction.check,
    ].where(actions.contains).firstOrNull;
    final progress = install.progress;
    final server = switch (auth) {
      AcpRequiredState(:final server) ||
      AcpVerifiedState(:final server) => server,
      _ => null,
    };
    final account = _account;
    final notice = account == null
        ? null
        : visibleAcpCommandNotice(_authNotice, account, auth);
    final localError =
        _error ??
        notice?.summary ??
        _service.auth.value.failure?.message ??
        _service.install.value.failure?.message;
    final canonicalError = showInstall && install is AcpInstallFailedState
        ? install.failure.message
        : auth is AcpFailedState
        ? auth.failure.message
        : null;
    final error = _service.install.value.stale || _service.auth.value.stale
        ? _strings['stale']
        : localError ?? canonicalError;
    return AccountAcpViewState(
      preparedForEditor: _preparedForEditor,
      claimedOperationId: _intent.operationId,
      preparationGeneration: _intent.generation,
      panel: AcpAccountPresentation(
        phase: phase,
        status: _preparing != null && !install.isBusy
            ? _strings['pendingPreparation']
            : showInstall && install.stage != null
            ? _strings['stage.${install.stage!.name}']
            : auth is AcpCancelledState ||
                  (showInstall && install is AcpInstallCancelledState)
            ? _strings['acp.cancelled']
            : _strings['acp.${phase.name}'],
        message: _template?.automaticInstall.isAvailable == false && showInstall
            ? _strings['unsupportedPlatform']
            : preparing
            ? _strings['sharedPreparation']
            : auth is AcpRequiredState && auth.agentMethods.isEmpty
            ? (auth.terminalOnly
                  ? _strings['terminalAuth']
                  : _strings['noAuthMethods'])
            : null,
        error: error,
        progress: progress?.fraction,
        progressLabel: progress == null
            ? null
            : '${progress.completedBytes}${progress.totalBytes == null ? '' : ' / ${progress.totalBytes}'} B',
        facts: [
          if (install is AcpDownloadingState)
            AccountDisplayFact(
              label: _strings['retries'],
              value: _strings.retryValue(install.retryCount),
            ),
          if (install.server?.reused == true)
            AccountDisplayFact(
              label: _strings['installation'],
              value: _strings['reused'],
            ),
          if (install.release case final release?)
            AccountDisplayFact(
              label: _strings['source'],
              value: release.hasPublisherChecksum
                  ? 'SHA-256 ${release.sha256}'
                  : _strings['officialHttps'],
            ),
          if (install.stage case final stage?)
            AccountDisplayFact(
              label: _strings['stage'],
              value: _strings['stage.${stage.name}'],
            ),
          if (_template?.supportedVersion.isNotEmpty == true)
            AccountDisplayFact(
              label: _strings['version'],
              value: _template!.supportedVersion,
            ),
          if (install.release case final release?)
            AccountDisplayFact(
              label: _strings['platform'],
              value: release.target,
            ),
          if (install.server case final installed?)
            AccountDisplayFact(
              label: _strings['program'],
              value: installed.program,
            ),
          if (server != null)
            AccountDisplayFact(
              label: _strings['server'],
              value: '${server.displayName} ${server.version}',
            ),
        ],
        availableActions: actions,
        primaryAction: primary,
        loginMethods: [
          for (final method in methods)
            AcpLoginMethodPresentation(id: method.id, label: method.name),
        ],
        selectedLoginMethod: selected,
        canSelectLoginMethod:
            methods.length > 1 && !auth.isBusy && _authenticating == null,
      ),
    );
  }

  void _publish() {
    if (ref.mounted && !_finished) state = AsyncData(_derive());
  }

  void _sourceChanged() {
    final authEpoch = _service.auth.value.stamp?.ownerEpoch;
    final installEpoch = _service.install.value.stamp?.ownerEpoch;
    final stale =
        _service.auth.value.stale ||
        _service.install.value.stale ||
        _accounts.state.value.stale;
    if ((stale && !_wasStale) ||
        (authEpoch != null &&
            _authOwnerEpoch != null &&
            authEpoch != _authOwnerEpoch) ||
        (installEpoch != null &&
            _installOwnerEpoch != null &&
            installEpoch != _installOwnerEpoch)) {
      _intent = _intent.renewed();
      _preparing = null;
      _cancelBaselineWait?.call();
      _authenticating = null;
      _cancelInstall = null;
      _cancelAuth = null;
      _error = null;
      _authNotice = null;
    }
    _authOwnerEpoch = authEpoch ?? _authOwnerEpoch;
    _installOwnerEpoch = installEpoch ?? _installOwnerEpoch;
    _wasStale = stale;
    final attempt = _authenticating;
    if (!_key.creating && !_currentConnection) {
      _authenticating = null;
      _cancelAuth = null;
      _authNotice = null;
    } else if (attempt != null && !attempt.observe(_auth)) {
      _authenticating = null;
      if (_authNotice?.operationId == attempt.operationId) {
        _authNotice = null;
      }
    }
    final account = _account;
    if (account == null ||
        visibleAcpCommandNotice(_authNotice, account, _auth) == null) {
      _authNotice = null;
    }
    _publish();
  }
}
