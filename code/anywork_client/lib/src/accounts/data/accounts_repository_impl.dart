import 'dart:async';

import '../../../accounts_ports.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/delegation_models.dart';
import '../../models/failure_models.dart';
import '../../observation/latest_value.dart';
import '../../models/account_models.dart'
    show AccountCatalogView, AccountModelView;
import '../../models_domain/domain/immutable_model.dart';
import '../domain/account_identity.dart';
import '../domain/account_authentication.dart';
import '../domain/account_intents.dart';
import '../domain/account_values.dart';
import '../domain/accounts_repository.dart';
import 'account_observations.dart';
import 'account_settings_mutations.dart';

final class AccountsRepositoryImpl implements AccountsRepository {
  AccountsRepositoryImpl({
    required this.port,
    required this.observations,
    required this.mutations,
  });
  final AccountConfigurationPort port;
  final AccountObservations observations;
  final AccountSettingsMutations mutations;
  final LatestValue<AccountsState> _state = LatestValue(AccountsState());
  int? _summaryGeneration;
  final Map<AccountIdentity, LatestValue<AccountResource<AccountDetails>>>
  _details = {};
  Future<void>? _templates;
  final Map<String, LatestValue<AccountResource<ChatGptLoginSnapshot>>>
  _chatGptLogins = {};
  final Map<String, ({String editorId, String accountId})> _loginIntent = {};
  int? _templateGeneration;
  final Set<Future<void>> _templateReads = {};
  bool _closed = false;

  @override
  ValueObservation<AccountsState> get state => _state;
  LatestValue<AccountResource<AccountDetails>> _detail(
    AccountIdentity identity,
  ) => _details.putIfAbsent(
    identity,
    () => LatestValue(const AccountResource()),
  );
  @override
  ValueObservation<AccountResource<AccountDetails>> details(
    AccountIdentity identity,
  ) => _detail(identity);
  LatestValue<AccountResource<ChatGptLoginSnapshot>> _chatGptLogin(
    String loginId,
  ) => _chatGptLogins.putIfAbsent(
    loginId,
    () => LatestValue(const AccountResource()),
  );
  @override
  ValueObservation<AccountResource<ChatGptLoginSnapshot>> chatGptLogin(
    String loginId,
  ) => _chatGptLogin(loginId);
  @override
  AccountDemand registerChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) {
    final prior = _loginIntent[loginId];
    final identity = (editorId: editorId, accountId: accountId);
    if (prior != null && prior != identity) {
      throw StateError('ChatGPT login identity was reused');
    }
    _loginIntent[loginId] = identity;
    _chatGptLogin(loginId);
    return _LoginIntentDemand(() {
      if (_loginIntent[loginId] == identity) {
        _loginIntent.remove(loginId);
        _chatGptLogins.remove(loginId);
      }
    });
  }

  @override
  AccountDemand observeChatGptLogin(String loginId) {
    if (!_loginIntent.containsKey(loginId)) {
      throw StateError('ChatGPT login intent must be registered first');
    }
    return observations.acquire(ChatGptLoginTarget(loginId));
  }

  @override
  Future<ChatGptLoginSnapshot> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    _requireLoginIntent(loginId, editorId, accountId);
    final generation = observations.generation;
    final reply = await port.startChatGptLogin(
      loginId: loginId,
      editorId: editorId,
      accountId: accountId,
    );
    _applyChatGptLoginReply(reply, loginId, editorId, accountId, generation);
    return reply.snapshot;
  }

  @override
  Future<ChatGptLoginSnapshot> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    final generation = observations.generation;
    final reply = await port.cancelChatGptLogin(
      loginId: loginId,
      editorId: editorId,
      accountId: accountId,
    );
    _applyChatGptLoginReply(reply, loginId, editorId, accountId, generation);
    return reply.snapshot;
  }

  void _requireLoginIntent(String loginId, String editorId, String accountId) {
    if (_loginIntent[loginId] != (editorId: editorId, accountId: accountId)) {
      throw StateError('ChatGPT login does not match the active editor');
    }
  }

  void _applyChatGptLoginReply(
    ChatGptLoginCommandReply reply,
    String loginId,
    String editorId,
    String accountId,
    int generation,
  ) {
    if (_closed ||
        generation != observations.generation ||
        !observations.accepts(reply.stamp)) {
      throw StateError('ChatGPT login owner changed during command');
    }
    final snapshot = reply.snapshot;
    if (snapshot.loginId != loginId ||
        snapshot.editorId != editorId ||
        snapshot.accountId != accountId ||
        reply.stamp.revision != snapshot.revision) {
      throw StateError('ChatGPT login reply identity or revision mismatch');
    }
    observations.apply(ChatGptLoginFrame(reply.stamp, snapshot));
  }

  void _applyChatGptLoginFrame(ChatGptLoginFrame frame) {
    final snapshot = frame.snapshot;
    final intent = _loginIntent[snapshot.loginId];
    if (intent == null) return;
    if (intent.editorId != snapshot.editorId ||
        intent.accountId != snapshot.accountId ||
        frame.stamp.revision != snapshot.revision) {
      throw StateError('ChatGPT login frame does not match editor intent');
    }
    final source = _chatGptLogin(snapshot.loginId);
    final current = source.value.value;
    if (current != null && current.revision >= snapshot.revision) return;
    source.publish(AccountResource(stamp: frame.stamp, value: snapshot));
  }

  void Function() prepareOwnerChange(bool Function() isCurrent) {
    final details = [
      for (final source in _details.values) (source, source.value),
    ];
    final current = _state.value;
    return () {
      if (!isCurrent()) return;
      if (identical(current, _state.value))
        _state.publish(
          AccountsState(
            stamp: current.stamp,
            accounts: current.accounts,
            templates: current.templates,
            stale: true,
            loading: true,
          ),
        );
      for (final (source, value) in details) {
        if (!isCurrent()) return;
        // A callback may already have supplied this lifecycle's new baseline.
        if (!identical(source.value, value)) continue;
        source.publish(
          AccountResource(
            stamp: value.stamp,
            value: value.value,
            stale: true,
            loading: true,
          ),
        );
      }
    };
  }

  @override
  AccountDemand observeSummaries() =>
      observations.acquire(const AccountSummariesTarget());
  @override
  AccountDemand observeDetails(AccountIdentity identity) =>
      observations.acquire(AccountDetailTarget(identity));
  @override
  Future<void> loadTemplates() {
    if (_closed)
      return Future.error(StateError('Account configuration is closed'));
    final existing = _templates;
    if (existing != null && _templateGeneration == observations.generation)
      return existing;
    final generation = observations.generation;
    final completion = Completer<void>();
    final work = completion.future;
    _templates = work;
    _templateGeneration = generation;
    _templateReads.add(work);
    unawaited(
      _loadTemplates(generation).then<void>(
        (_) {
          if (identical(_templates, work)) _templates = null;
          _templateReads.remove(work);
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_templates, work)) _templates = null;
          _templateReads.remove(work);
          completion.completeError(error, stack);
        },
      ),
    );
    return work;
  }

  Future<void> _loadTemplates(int generation) async {
    final catalog = await port.loadAccountCatalog();
    if (_closed || generation != observations.generation) return;
    final current = _state.value;
    final immutableCatalog = AccountCatalogView(
      schemaVersion: catalog.schemaVersion,
      revision: catalog.revision,
      templates: List.unmodifiable(catalog.templates),
      modelCatalogs: Map.unmodifiable({
        for (final entry in catalog.modelCatalogs.entries)
          entry.key: List<AccountModelView>.unmodifiable(
            entry.value.map(immutableModelDescriptor),
          ),
      }),
    );
    _state.publish(
      AccountsState(
        stamp: current.stamp,
        accounts: current.accounts,
        templates: immutableCatalog,
        loading: current.loading,
        failure: current.failure,
        stale: current.stale || _summaryGeneration != observations.generation,
      ),
    );
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait([
      for (final pending in _templateReads.toList())
        pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
    _loginIntent.clear();
    _chatGptLogins.clear();
  }

  void apply(AccountDomainFrame frame) {
    switch (frame) {
      case ChatGptLoginFrame():
        _applyChatGptLoginFrame(frame);
      case AccountSummariesFrame(:final stamp, :final accounts):
        _summaryGeneration = observations.generation;
        final current = _state.value;
        _state.publish(
          AccountsState(
            stamp: stamp,
            accounts: accounts,
            templates: current.templates,
          ),
        );
      case AccountDetailFrame(:final stamp, :final identity, :final account):
        if (account != null && account.identity != identity)
          throw StateError('Account detail identity mismatch');
        _detail(identity)
            .publish(AccountResource(stamp: stamp, value: account));
      default:
        throw ArgumentError('Not account configuration content');
    }
  }

  void fail(AccountObservationTarget target, StudioFailure failure) {
    if (target is ChatGptLoginTarget) {
      if (!_loginIntent.containsKey(target.loginId)) return;
      final source = _chatGptLogin(target.loginId);
      final current = source.value;
      source.publish(
        AccountResource(
          stamp: current.stamp,
          value: current.value,
          failure: failure,
          stale: current.stale,
        ),
      );
    } else if (target is AccountDetailTarget) {
      final source = _detail(target.identity);
      final current = source.value;
      source.publish(
        AccountResource(
          stamp: current.stamp,
          value: current.value,
          failure: failure,
          stale: current.stale,
        ),
      );
    } else if (target is AccountSummariesTarget) {
      final current = _state.value;
      _state.publish(
        AccountsState(
          stamp: current.stamp,
          accounts: current.accounts,
          templates: current.templates,
          failure: failure,
          stale: current.stale,
        ),
      );
    }
  }

  Map<String, AccountObservationTarget> _targets(
    NativeAccountIdentity identity, {
    bool summaries = false,
  }) => {
    'settings': summaries
        ? const AccountSummariesTarget()
        : AccountDetailTarget(identity),
    'model-catalog': AccountModelsTarget(identity),
  };
  @override
  Future<OperationState> create(
    CreateAccountCommand command, {
    DraftStamp? draft,
  }) => mutations.run(
    key: 'account:native:${command.identity.accountId}',
    draft: draft,
    targets: _targets(command.identity),
    request: (revision, operation) =>
        port.createAccount(revision, command, operationId: operation),
  );
  @override
  Future<OperationState> patch(
    PatchAccountCommand command, {
    DraftStamp? draft,
  }) => mutations.run(
    key: 'account:native:${command.identity.accountId}',
    draft: draft,
    targets: _targets(command.identity),
    request: (revision, operation) =>
        port.patchAccount(revision, command, operationId: operation),
  );
  @override
  Future<OperationState> remove(
    NativeAccountIdentity identity, {
    NativeAccountIdentity? replacement,
  }) => mutations.run(
    key: 'account:native:${identity.accountId}',
    targets: _targets(identity),
    request: (revision, operation) => port.removeAccount(
      revision,
      identity.accountId,
      replacementAccountId: replacement?.accountId,
      operationId: operation,
    ),
  );
  @override
  Future<OperationState> setDefault(NativeAccountIdentity identity) =>
      mutations.run(
        key: 'account:default',
        targets: _targets(identity, summaries: true),
        request: (revision, operation) => port.setDefaultAccount(
          revision,
          identity.accountId,
          operationId: operation,
        ),
      );
  @override
  Future<OperationState> setBillingKind(
    NativeAccountIdentity identity,
    BillingKind? kind,
  ) => mutations.run(
    key: 'account:billing:${identity.accountId}',
    targets: _targets(identity, summaries: true),
    request: (revision, operation) => port.setAccountBillingKind(
      revision,
      identity.accountId,
      kind,
      operationId: operation,
    ),
  );
}

final class _LoginIntentDemand implements AccountDemand {
  _LoginIntentDemand(this._onRelease);

  final void Function() _onRelease;
  Future<void>? _release;

  @override
  Future<void> release() => _release ??= _releaseOnce();

  Future<void> _releaseOnce() async {
    _onRelease();
  }
}
