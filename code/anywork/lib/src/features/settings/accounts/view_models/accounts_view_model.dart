import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationId, OperationState, OperationPhase;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'account_operation_result.dart';
import 'account_card_view_model.dart';

part 'accounts_view_model.g.dart';

typedef _CardObservationSource = ({
  String? ownerEpoch,
  int? connectionRevision,
  bool stale,
});

/// This list's read-only retention of one card scope and its provider listener.
/// Cancellation is idempotent and never closes an account/service owner.
final class _CardObservationLease {
  _CardObservationLease({
    required this.source,
    required this._cancelCardObservation,
    required this._detachSubscription,
    required this._boundScope,
    required this._pushAction,
  });

  final _CardObservationSource source;
  void Function()? _cancelCardObservation;
  void Function()? _detachSubscription;
  Object? _boundScope;
  void Function(AccountActionPresentation? action)? _pushAction;
  AccountActionPresentation? _pushed;
  bool _pushedOnce = false;

  Object? get boundScope => _boundScope;
  bool get closed => _pushAction == null && _cancelCardObservation == null;

  /// Deliver only an action that belongs to this lease. A new card scope starts
  /// empty; callers must pass a freshly derived projection, never a replay of
  /// the previous scope's value.
  void push(AccountActionPresentation? action) {
    final sink = _pushAction;
    if (sink == null) return;
    final accepted = action != null && _belongs(action) ? action : null;
    if (_pushedOnce && _pushed == accepted) return;
    _pushedOnce = true;
    _pushed = accepted;
    sink(accepted);
  }

  void rebind({
    required Object scope,
    required void Function(AccountActionPresentation? action) pushAction,
  }) {
    if (_pushAction == null) return;
    _boundScope = scope;
    _pushAction = pushAction;
    _pushed = null;
    _pushedOnce = false;
  }

  bool _belongs(AccountActionPresentation action) {
    if (action.ownerEpoch != source.ownerEpoch) return false;
    if (action.removing) return true;
    return action.acpConnectionRevision == source.connectionRevision;
  }

  void cancel() {
    final cancelCard = _cancelCardObservation;
    final detach = _detachSubscription;
    _cancelCardObservation = null;
    _detachSubscription = null;
    // Detach before cancellation. A pending-intent cancel can rebuild the
    // card synchronously; this lease must not deliver into that new scope.
    _pushAction = null;
    _boundScope = null;
    try {
      cancelCard?.call();
    } finally {
      detach?.call();
    }
  }
}

final class _ListAttempt {
  _ListAttempt(
    this.key,
    this.owner,
    this.acpRevision, {
    required this.lifetime,
    required this.repository,
    required this.ownerEpoch,
    this.removing = false,
  });
  final AccountDisplayKey key;
  final Object owner;
  final int? acpRevision;
  final Ref lifetime;
  final AccountsRepository repository;
  final String? ownerEpoch;
  final bool removing;
  final observations = <Observation>[];
  OperationId? operationId;
  OperationState? removalOutcome;
  Completer<bool>? removalCompletion;
  void Function()? closeRetention;
  bool waiting = true;
  bool terminal = false;
  bool retired = false;

  void closeLocal() {
    for (final observation in observations.toList()) {
      observation.cancel();
    }
    observations.clear();
    closeRetention?.call();
    closeRetention = null;
  }
}

/// Summary-only list and actions. Page location and finite editor resources
/// belong to the Router and editor session, never this owner.
@riverpod
class AccountsViewModel extends _$AccountsViewModel {
  late AccountsRepository _accounts;
  late AcpService _acp;
  AccountStrings _strings = const AccountStrings.empty();
  AccountDemand? _summaryDemand;
  bool _visible = false;
  Map<AccountDisplayKey, _CardObservationLease> _cards = {};
  Object _cardSync = Object();
  String _search = '';
  final Map<AccountDisplayKey, String> _errors = {};
  final Set<AccountDisplayKey> _pending = {};
  final Map<AccountDisplayKey, _ListAttempt> _attempts = {};
  Object _ownerLifecycle = Object();
  String? _ownerEpoch;
  bool _ownerStale = false;

  @override
  FutureOr<AccountsViewState> build() {
    final lifetime = ref;
    // Each provider build owns its own leases, even if Riverpod reuses this
    // notifier. An old disposal callback can only detach its captured set.
    final cards = <AccountDisplayKey, _CardObservationLease>{};
    _cards = cards;
    _cardSync = Object();
    _accounts = ref.read(accountsRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    _ownerEpoch = _accounts.state.value.stamp?.ownerEpoch;
    _ownerStale = _accounts.state.value.stale;
    _summaryDemand = _accounts.observeSummaries();
    final observations = [
      _accounts.state.watch((source) {
        if (lifetime.mounted && identical(lifetime, ref)) {
          _summariesChanged(source);
        }
      }),
    ];
    ref.onDispose(() {
      for (final observation in observations) {
        observation.cancel();
      }
      releaseAccountDemand(_summaryDemand);
      for (final lease in cards.values.toList()) {
        lease.cancel();
      }
      for (final attempt in _attempts.values.toList()) {
        if (identical(attempt.lifetime, lifetime)) _retireAttempt(attempt);
      }
    });
    scheduleMicrotask(() {
      if (lifetime.mounted && identical(cards, _cards) && _visible) {
        _syncCards();
      }
    });
    return _derive();
  }

  void setStrings(AccountStrings strings) {
    _strings = strings;
    for (final key in _cards.keys) {
      ref.read(accountCardViewModelProvider(key).notifier).setStrings(strings);
    }
    _publish();
  }

  void setVisible(bool visible) {
    if (!ref.mounted) return;
    _visible = visible;
    _syncCards();
  }

  void _syncCards() {
    final lifetime = ref;
    final cards = _cards;
    final pass = Object();
    _cardSync = pass;
    bool isCurrent() =>
        lifetime.mounted &&
        identical(lifetime, ref) &&
        identical(cards, _cards) &&
        identical(pass, _cardSync);
    final source = _accounts.state.value;
    final members = {
      if (_visible)
        for (final account in source.accounts)
          displayIdentity(account.identity),
    };
    for (final key in cards.keys.toList()) {
      if (!members.contains(key)) {
        cards.remove(key)!.cancel();
        if (!isCurrent()) return;
      }
    }
    for (final key in members) {
      final identity = (
        ownerEpoch: source.stamp?.ownerEpoch,
        connectionRevision: source
            .account(domainIdentity(key))
            ?.acpConnectionRevision,
        stale: source.stale,
      );
      if (cards.containsKey(key)) {
        if (cards[key]!.source == identity) continue;
        cards.remove(key)!.cancel();
        if (!isCurrent()) return;
      }
      if (!ref
          .read(accountCardViewModelProvider(key).notifier)
          .isObservationActive()) {
        ref.invalidate(accountCardViewModelProvider(key));
      }
      if (!isCurrent()) return;
      // Retain every real member, not just rows surviving the search filter.
      _CardObservationLease? installed;
      final subscription = ref.listen(accountCardViewModelProvider(key), (
        _,
        _,
      ) {
        final lease = installed;
        if (lease == null || !isCurrent() || !identical(cards[key], lease)) {
          return;
        }
        _rebindRebuiltCard(key, lease);
      }, weak: false);
      final card = ref.read(accountCardViewModelProvider(key).notifier);
      final lease = _CardObservationLease(
        source: identity,
        cancelCardObservation: card.cancellationForCurrentObservation(),
        detachSubscription: subscription.close,
        boundScope: card.currentObservationScope(),
        pushAction: card.actionSinkForCurrentObservation(),
      );
      installed = lease;
      if (!isCurrent()) {
        lease.cancel();
        return;
      }
      cards[key] = lease;
      card.setStrings(_strings);
      if (!isCurrent()) return;
      // Fresh derivation only. Do not replay the previously published action:
      // an owner/revision replacement may still be sitting in that old state.
      lease.push(_derive().actions[key]);
      if (!isCurrent()) return;
    }
  }

  void _rebindRebuiltCard(AccountDisplayKey key, _CardObservationLease lease) {
    if (lease.closed || !identical(_cards[key], lease)) return;
    final card = ref.read(accountCardViewModelProvider(key).notifier);
    if (!card.isObservationActive() ||
        identical(card.currentObservationScope(), lease.boundScope)) {
      return;
    }
    lease.rebind(
      scope: card.currentObservationScope(),
      pushAction: card.actionSinkForCurrentObservation(),
    );
    lease.push(_derive().actions[key]);
  }

  void search(String raw) {
    _search = raw;
    _publish();
  }

  Future<void> refresh(AccountDisplayKey key) async {
    if (!_cards.containsKey(key)) return;
    await ref.read(accountCardViewModelProvider(key).notifier).refresh();
  }

  Future<void> refreshAll() async {
    final keys = [
      for (final account in _accounts.state.value.accounts)
        if ((account.identity is NativeAccountIdentity &&
                account.capabilities.queryUsage) ||
            (account.identity is AcpAccountIdentity &&
                account.acpConnectionRevision != null))
          displayIdentity(account.identity),
    ];
    await Future.wait(keys.map(refresh));
  }

  void retryObservation() {
    releaseAccountDemand(_summaryDemand);
    _summaryDemand = _accounts.observeSummaries();
  }

  String accountName(AccountDisplayKey key) =>
      _accounts.state.value.account(domainIdentity(key))?.name ?? key.id;

  bool needsReplacement(AccountDisplayKey key) =>
      key.kind == AccountKind.native &&
      _accounts.state.value.account(domainIdentity(key))?.isDefault == true &&
      replacements(key).isNotEmpty;
  List<AccountRowPresentation> replacements(AccountDisplayKey key) => [
    for (final summary in _accounts.state.value.accounts)
      if (summary.identity is NativeAccountIdentity &&
          summary.identity != domainIdentity(key))
        AccountRowPresentation(
          key: displayIdentity(summary.identity),
          name: summary.name,
          content: AccountRowContent.native(
            billing: displayBilling(summary.billingKind),
            usage: const AccountUsagePresentation(),
            displayEndpoint: summary.displayEndpoint,
          ),
        ),
  ];

  bool isRemovalBlocked(AccountDisplayKey key) {
    final attempt = _attempts[key];
    return attempt != null &&
        attempt.removing &&
        _ownsRemoval(attempt) &&
        _pending.contains(key);
  }

  Future<bool> remove(
    AccountDisplayKey key, {
    AccountDisplayKey? replacement,
    required bool Function() isCompactClean,
  }) {
    final lifetime = ref;
    final repository = _accounts;
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(key));
    if (replacement?.kind == AccountKind.acp ||
        !source.loaded ||
        source.stale ||
        source.stamp == null ||
        summary == null ||
        !summary.capabilities.remove ||
        _pending.contains(key) ||
        (key.kind == AccountKind.acp &&
            summary.acpConnectionRevision == null)) {
      return Future.value(false);
    }
    // The caller captured existing Models resources (or their absence), not a
    // route. Invoke this once, synchronously, and never retain the callback.
    try {
      if (!isCompactClean()) return Future.value(false);
    } catch (error) {
      _errors[key] = safeAccountError(error, _strings);
      _publish();
      return Future.value(false);
    }
    if (!lifetime.mounted ||
        !identical(ref, lifetime) ||
        !identical(_accounts, repository) ||
        _accounts.state.value.stamp?.ownerEpoch != source.stamp!.ownerEpoch) {
      return Future.value(false);
    }
    return _command(
      key,
      () => key.kind == AccountKind.native
          ? _accounts.remove(
              NativeAccountIdentity(key.id),
              replacement: replacement == null
                  ? null
                  : NativeAccountIdentity(replacement.id),
            )
          : _acp.remove(AcpAccountIdentity(key.id)),
      removing: true,
    );
  }

  Future<bool> setDefault(AccountDisplayKey key) =>
      key.kind == AccountKind.native
      ? _command(key, () => _accounts.setDefault(NativeAccountIdentity(key.id)))
      : Future.value(false);

  Future<bool> _command(
    AccountDisplayKey key,
    Future<OperationState> Function() action, {
    bool removing = false,
  }) async {
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(key));
    if (!source.loaded ||
        summary == null ||
        (removing &&
            (source.stale ||
                source.stamp == null ||
                !summary.capabilities.remove)) ||
        (key.kind == AccountKind.acp &&
            summary.acpConnectionRevision == null) ||
        !_pending.add(key)) {
      return false;
    }
    final previous = _attempts[key];
    if (previous != null) {
      previous.retired = true;
      previous.closeLocal();
    }
    final attempt = _ListAttempt(
      key,
      _ownerLifecycle,
      key.kind == AccountKind.acp ? summary.acpConnectionRevision : null,
      lifetime: ref,
      repository: _accounts,
      ownerEpoch: source.stamp?.ownerEpoch,
      removing: removing,
    );
    if (removing) attempt.closeRetention = ref.keepAlive().close;
    _attempts[key] = attempt;
    _errors.remove(key);
    _publish();
    try {
      if (!_owns(attempt)) return false;
      final result = await action();
      attempt.operationId = result.id;
      if (!_owns(attempt)) return false;
      void apply(OperationState operation) {
        if (!_owns(attempt) || operation.id != attempt.operationId) return;
        if (attempt.removing) {
          attempt.removalOutcome = operation;
          if (operation.failurePhase == OperationPhase.rejected) {
            _pending.remove(key);
            attempt.terminal = true;
            _completeRemovalWait(attempt, false);
          } else if (operation.failurePhase != null) {
            // Failure ends this caller's wait, not the unresolved deletion's
            // write fence or retained operation responsibility.
            _completeRemovalWait(attempt, false);
          } else {
            _settleRemovalIfAbsent(attempt);
          }
        } else if (operationSaved(operation) ||
            operation.failurePhase == OperationPhase.rejected) {
          _pending.remove(key);
          attempt.terminal = true;
        }
        final message =
            attempt.removing && !attempt.terminal && operationSaved(operation)
            ? _strings['awaitingObservation']
            : operationMessage(operation, _strings);
        if (message == null) {
          _errors.remove(key);
        } else {
          _errors[key] = message;
        }
        _publish();
        _releaseSettledAttempt(attempt);
      }

      trackAccountOperation(ref, result, attempt.observations, apply);
      if (removing) {
        // A failure returned by this admission is frozen. Do not read a newer
        // source to turn it into success. Pending success may observe this ID.
        final settled = result.failurePhase != null
            ? result
            : await observeAccountOperation(attempt.lifetime, result) ?? result;
        if (!_ownsRemoval(attempt) || !operationSaved(settled)) return false;
        // Saved and current canonical absence are separate public facts. Keep
        // this exact attempt/pending/retention closed until both are present.
        // A callback may already have delivered a later failure: do not replace
        // it with this older saved snapshot merely to authorize navigation.
        attempt.removalOutcome ??= settled;
        if (attempt.removalOutcome!.failurePhase != null) return false;
        if (_settleRemovalIfAbsent(attempt)) return true;
        final completion = attempt.removalCompletion ??= Completer<bool>();
        if (!await completion.future || !_ownsRemoval(attempt)) return false;
        return _hasRemovalAbsence(attempt) &&
            operationSaved(attempt.removalOutcome!);
      }
      return operationSaved(result);
    } catch (error) {
      if (_owns(attempt)) {
        _errors[key] = safeAccountError(error, _strings);
        if (!removing || attempt.operationId == null) {
          // The SDK reports admitted failures as OperationState. A throw before
          // any returned operation is a before-admission failure, not success.
          _pending.remove(key);
          attempt.terminal = true;
          if (attempt.removing) _completeRemovalWait(attempt, false);
        }
      }
      return false;
    } finally {
      final current = _owns(attempt);
      attempt.waiting = false;
      _releaseSettledAttempt(attempt);
      if (current && ref.mounted && identical(ref, attempt.lifetime)) {
        _publish();
      }
    }
  }

  bool _owns(_ListAttempt attempt) {
    if (attempt.removing) return _ownsRemoval(attempt);
    if (!ref.mounted ||
        !attempt.lifetime.mounted ||
        !identical(ref, attempt.lifetime) ||
        attempt.retired ||
        !identical(_attempts[attempt.key], attempt) ||
        !identical(_ownerLifecycle, attempt.owner)) {
      return false;
    }
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(attempt.key));
    return source.loaded &&
        summary != null &&
        (attempt.key.kind == AccountKind.native ||
            summary.acpConnectionRevision == attempt.acpRevision);
  }

  bool _ownsRemoval(_ListAttempt attempt) {
    final epoch = _accounts.state.value.stamp?.ownerEpoch;
    return ref.mounted &&
        attempt.lifetime.mounted &&
        identical(ref, attempt.lifetime) &&
        !attempt.retired &&
        identical(_accounts, attempt.repository) &&
        identical(_attempts[attempt.key], attempt) &&
        (epoch == null || epoch == attempt.ownerEpoch);
  }

  bool _hasRemovalAbsence(_ListAttempt attempt) {
    final source = _accounts.state.value;
    return _ownsRemoval(attempt) &&
        source.loaded &&
        !source.stale &&
        source.stamp?.ownerEpoch == attempt.ownerEpoch &&
        source.account(domainIdentity(attempt.key)) == null;
  }

  bool _settleRemovalIfAbsent(_ListAttempt attempt) {
    final outcome = attempt.removalOutcome;
    if (outcome == null ||
        outcome.id != attempt.operationId ||
        !operationSaved(outcome) ||
        !_hasRemovalAbsence(attempt)) {
      return false;
    }
    _pending.remove(attempt.key);
    attempt.terminal = true;
    _errors.remove(attempt.key);
    _completeRemovalWait(attempt, true);
    return true;
  }

  void _completeRemovalWait(_ListAttempt attempt, bool success) {
    final completion = attempt.removalCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(success);
    }
  }

  void _releaseSettledAttempt(_ListAttempt attempt) {
    if (attempt.retired || (attempt.terminal && !attempt.waiting)) {
      attempt.closeLocal();
      if (!attempt.retired &&
          attempt.removing &&
          _ownsRemoval(attempt) &&
          _accounts.state.value.loaded &&
          _accounts.state.value.account(domainIdentity(attempt.key)) == null) {
        // A completed, absent target is not history retained by the list.
        _attempts.remove(attempt.key);
        _errors.remove(attempt.key);
      }
    }
  }

  void _retireAttempt(_ListAttempt attempt) {
    attempt.retired = true;
    if (attempt.removing) _completeRemovalWait(attempt, false);
    attempt.closeLocal();
    if (identical(_attempts[attempt.key], attempt)) {
      _attempts.remove(attempt.key);
      _errors.remove(attempt.key);
      _pending.remove(attempt.key);
    }
  }

  void _summariesChanged(AccountsState source) {
    final epoch = source.stamp?.ownerEpoch;
    final changed =
        (source.stale && !_ownerStale) ||
        (epoch != null && epoch != _ownerEpoch);
    if (changed) {
      _ownerLifecycle = Object();
    }
    _ownerStale = source.stale;
    _ownerEpoch = epoch ?? _ownerEpoch;
    for (final attempt in _attempts.values.toList()) {
      if (attempt.removing) {
        // Absence can be published synchronously by this removal's reply,
        // before the operation's receipt observation returns to the caller.
        if (!identical(_accounts, attempt.repository) ||
            !attempt.lifetime.mounted ||
            (epoch != null && epoch != attempt.ownerEpoch)) {
          _retireAttempt(attempt);
        } else if (_settleRemovalIfAbsent(attempt)) {
          _releaseSettledAttempt(attempt);
        }
        continue;
      }
      final summary = source.account(domainIdentity(attempt.key));
      if (changed ||
          (source.loaded &&
              (summary == null ||
                  (attempt.key.kind == AccountKind.acp &&
                      summary.acpConnectionRevision != attempt.acpRevision)))) {
        _retireAttempt(attempt);
      }
    }
    _syncCards();
    _publish();
  }

  AccountsViewState _derive() {
    final source = _accounts.state.value;
    final filtered = source.accounts.where((account) {
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          account.name.toLowerCase().contains(query) ||
          account.identity.accountId.toLowerCase().contains(query);
    });
    return AccountsViewState(
      actions: {
        for (final entry in _errors.entries)
          if (!_attempts.containsKey(entry.key) && source.stamp != null)
            entry.key: AccountActionPresentation(
              ownerEpoch: source.stamp!.ownerEpoch,
              removing: false,
              acpConnectionRevision: source
                  .account(domainIdentity(entry.key))
                  ?.acpConnectionRevision,
              message: entry.value,
            ),
        for (final attempt in _attempts.values)
          if (_owns(attempt))
            attempt.key: AccountActionPresentation(
              ownerEpoch: attempt.ownerEpoch ?? source.stamp!.ownerEpoch,
              removing: attempt.removing,
              acpConnectionRevision: attempt.acpRevision,
              pending: _pending.contains(attempt.key),
              message: _errors[attempt.key],
            ),
      },
      list: AccountsListPresentation(
        phase: source.stamp == null
            ? (source.failure != null
                  ? AccountListPhase.failed
                  : AccountListPhase.loading)
            : AccountListPhase.ready,
        search: _search,
        searchHasNoResults: _search.trim().isNotEmpty && filtered.isEmpty,
        refreshing: source.loading,
        canAdd: source.loaded,
        canRefresh: source.loaded,
        error: source.stale ? _strings['stale'] : source.failure?.message,
        members: [
          for (final account in filtered) displayIdentity(account.identity),
        ],
      ),
    );
  }

  void _publish() {
    if (!ref.mounted) return;
    final previous = state.asData?.value;
    final next = _derive();
    _deliverActionChanges(previous?.actions, next.actions);
    if (previous != next) state = AsyncData(next);
  }

  void _deliverActionChanges(
    Map<AccountDisplayKey, AccountActionPresentation>? previous,
    Map<AccountDisplayKey, AccountActionPresentation> next,
  ) {
    final keys = {...?previous?.keys, ...next.keys};
    for (final key in keys) {
      if (previous?[key] == next[key]) continue;
      _cards[key]?.push(next[key]);
    }
  }
}
