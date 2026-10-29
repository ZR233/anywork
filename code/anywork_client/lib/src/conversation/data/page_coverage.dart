part of 'conversation_content_impl.dart';

typedef _PageKey = ({int ordinal, String id});

_PageKey _pageKey(ConversationItem item) =>
    (ordinal: item.header.ordinal, id: item.id);

int _compareKeys(_PageKey a, _PageKey b) {
  final order = a.ordinal.compareTo(b.ordinal);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

final class _PageCoverage implements ConversationPageCoverage {
  const _PageCoverage({
    required this.issuer,
    required this.threadId,
    required this.attemptId,
    required this.subscriptionId,
    required this.epoch,
    required this.baselineVersion,
    required this.membership,
    required this.lower,
    required this.upper,
    required this.before,
    required this.hasOlder,
  });

  final Object issuer;
  final String threadId;
  final AttemptId attemptId;
  final String subscriptionId;
  final int epoch;
  final int baselineVersion;
  // A flat delivery witness, never a reference to a token or its predecessor.
  final Object membership;
  final _PageKey? lower;
  final _PageKey? upper;
  final String? before;
  final bool hasOlder;

  _PageCoverage advance(
    ConversationPage page, {
    required Object membership,
    Iterable<ConversationItem> reconciled = const [],
  }) {
    var nextLower = lower;
    var nextUpper = upper;
    for (final item in page.items.followedBy(reconciled)) {
      final key = _pageKey(item);
      if (nextLower == null || _compareKeys(key, nextLower) < 0) {
        nextLower = key;
      }
      if (nextUpper == null || _compareKeys(key, nextUpper) > 0) {
        nextUpper = key;
      }
    }
    return _PageCoverage(
      issuer: issuer,
      threadId: threadId,
      attemptId: attemptId,
      subscriptionId: subscriptionId,
      epoch: epoch,
      baselineVersion: baselineVersion,
      membership: membership,
      lower: nextLower,
      upper: nextUpper,
      before: page.before,
      hasOlder: page.hasOlder,
    );
  }
}

final class _PageProof {
  const _PageProof({
    required this.id,
    required this.key,
    required this.revision,
    required this.sequence,
    required this.removed,
    required this.lastRemoval,
    required this.presentSince,
    required this.membership,
    required this.membershipBaselineVersion,
  });
  final String id;
  final _PageKey? key;
  final int revision;
  final int sequence;
  final bool removed;
  final int lastRemoval;
  final int? presentSince;
  final Object? membership;
  final int? membershipBaselineVersion;
  int get bytes => 176 + utf8.encode(id).length;

  _PageProof withMembership(Object next) => _PageProof(
    id: id,
    key: key,
    revision: revision,
    sequence: sequence,
    removed: removed,
    lastRemoval: lastRemoval,
    presentSince: presentSince,
    membership: next,
    membershipBaselineVersion: membershipBaselineVersion,
  );
}

/// One shared identity-only ledger, not a body replay log or per-scope cache.
final class _PageProofs {
  final Map<String, _PageProof> entries = {};
  _PageKey? _uncertainLower;
  _PageKey? _uncertainUpper;
  bool _allUncertain = false;
  int _bytes = 0;
  int lostSequence = 0;
  int get retainedBytes => _bytes + _uncertaintyBytes;

  void clear() {
    entries.clear();
    _uncertainLower = _uncertainUpper = null;
    _allUncertain = false;
    _bytes = 0;
    lostSequence = 0;
  }

  _PageProofs copy() => _PageProofs()
    ..entries.addAll(entries)
    .._uncertainLower = _uncertainLower
    .._uncertainUpper = _uncertainUpper
    .._allUncertain = _allUncertain
    ..lostSequence = lostSequence
    .._bytes = _bytes;

  void item(
    ConversationItem item,
    int sequence, {
    Object? deliveredMembership,
    int? deliveredBaselineVersion,
  }) {
    final old = entries[item.id];
    final key = _pageKey(item);
    if (old?.key case final known?) {
      if (_compareKeys(known, key) != 0) {
        throw const ConversationContinuityError('proof identity changed order');
      }
    }
    if (old != null && !old.removed && item.revision < old.revision) {
      return;
    }
    _put(
      _PageProof(
        id: item.id,
        key: key,
        revision: item.revision,
        sequence: sequence,
        removed: false,
        lastRemoval: old?.lastRemoval ?? 0,
        presentSince: old != null && !old.removed ? old.presentSince : sequence,
        membership:
            deliveredMembership ??
            (old?.removed == false ? old?.membership : null),
        membershipBaselineVersion:
            deliveredBaselineVersion ??
            (old?.removed == false ? old?.membershipBaselineVersion : null),
      ),
    );
  }

  void change(ConversationChange change, int sequence) {
    switch (change) {
      case ConversationAdd(:final item):
        this.item(item, sequence);
      case ConversationUpdateItem(
        :final itemId,
        :final header,
        :final revision,
      ):
        final old = entries[itemId];
        final key = header == null
            ? old?.key
            : (ordinal: header.ordinal, id: header.id);
        if (header != null && header.id != itemId ||
            old?.key != null && key != old!.key) {
          throw const ConversationContinuityError('invalid proof update');
        }
        _put(
          _PageProof(
            id: itemId,
            key: key,
            revision: old != null && old.revision > revision
                ? old.revision
                : revision,
            sequence: sequence,
            removed: old?.removed ?? false,
            lastRemoval: old?.lastRemoval ?? 0,
            presentSince: old?.presentSince,
            membership: old?.membership,
            membershipBaselineVersion: old?.membershipBaselineVersion,
          ),
        );
      case ConversationRemove(:final itemId):
        final old = entries[itemId];
        _put(
          _PageProof(
            id: itemId,
            key: old?.key,
            revision: old?.revision ?? 0,
            sequence: sequence,
            removed: true,
            lastRemoval: sequence,
            presentSince: null,
            membership: old?.membership,
            membershipBaselineVersion: old?.membershipBaselineVersion,
          ),
        );
    }
  }

  // One witness slot per bounded proof, not a member set per scope. A branch
  // may replace it; insufficient membership evidence then fails closed.
  void transferMembership(Object previous, Object next) {
    for (final entry in entries.entries.toList(growable: false)) {
      if (identical(entry.value.membership, previous)) {
        entries[entry.key] = entry.value.withMembership(next);
      }
    }
  }

  void _put(_PageProof proof) {
    final old = entries.remove(proof.id);
    if (old != null) _bytes -= old.bytes;
    entries[proof.id] = proof;
    _bytes += proof.bytes;
    while (entries.length > ConversationContentImpl.continuityItems ||
        _bytes + _uncertaintyBytes > 8 * 1024 * 1024) {
      final removed = entries.remove(entries.keys.first)!;
      _bytes -= removed.bytes;
      if (removed.sequence > lostSequence) lostSequence = removed.sequence;
      _forget(removed.key);
    }
  }

  int get _uncertaintyBytes =>
      128 +
      (_uncertainLower == null ? 0 : utf8.encode(_uncertainLower!.id).length) +
      (_uncertainUpper == null ? 0 : utf8.encode(_uncertainUpper!.id).length);

  void _forget(_PageKey? key) {
    if (key == null) {
      _allUncertain = true;
      return;
    }
    if (_uncertainLower == null || _compareKeys(key, _uncertainLower!) < 0) {
      _uncertainLower = key;
    }
    if (_uncertainUpper == null || _compareKeys(key, _uncertainUpper!) > 0) {
      _uncertainUpper = key;
    }
    // Oversized identifiers cannot turn the bounded uncertainty marker into a
    // second unbounded cache. An unknown range is conservative, never EOF.
    if (_uncertaintyBytes > 1024 * 1024) {
      _uncertainLower = _uncertainUpper = null;
      _allUncertain = true;
    }
  }

  void requireRange(
    _PageKey? lower,
    _PageKey? upper, {
    bool upperExclusive = false,
  }) {
    final uncertainLower = _uncertainLower;
    final uncertainUpper = _uncertainUpper;
    if (_allUncertain ||
        uncertainLower != null &&
            uncertainUpper != null &&
            (lower == null || _compareKeys(uncertainUpper, lower) >= 0) &&
            (upper == null ||
                (upperExclusive
                    ? _compareKeys(uncertainLower, upper) < 0
                    : _compareKeys(uncertainLower, upper) <= 0))) {
      throw const ConversationContinuityError('page crossed forgotten proof');
    }
  }
}

bool _concurrentItemInPage(
  ConversationItem item,
  ConversationPage page,
  _PageCoverage? coverage,
) {
  final key = _pageKey(item);
  if (coverage != null) {
    return (coverage.lower == null ||
            _compareKeys(key, coverage.lower!) <= 0) &&
        (!page.hasOlder ||
            page.items.isNotEmpty &&
                _compareKeys(key, _pageKey(page.items.first)) >= 0);
  }
  if (page.items.isEmpty) return false;
  final lower = _pageKey(page.items.first);
  final upper = _pageKey(page.items.last);
  return _compareKeys(key, lower) >= 0 && _compareKeys(key, upper) <= 0;
}

extension _CoveragePageValidation on ConversationQueryScopeImpl {
  void _validateCoveragePage(
    _PageCoverage coverage,
    ConversationPage page,
    int readSequence,
  ) {
    if (page.hasOlder &&
        (page.before == coverage.before || page.items.isEmpty)) {
      throw const ConversationContinuityError('page did not prove progress');
    }
    final lower = coverage.lower;
    final upper = coverage.upper;
    final pageLower = page.items.isEmpty ? lower : _pageKey(page.items.first);
    // EOF claims the entire earlier range, not merely the returned first row.
    _attempt.proofs.requireRange(
      page.hasOlder ? pageLower : null,
      lower,
      upperExclusive: true,
    );
    final ids = <String>{};
    for (final item in page.items) {
      ids.add(item.id);
      final key = _pageKey(item);
      final proof = _attempt.proofs.entries[item.id];
      if (proof?.key != null && proof!.key != key) {
        throw const ConversationContinuityError('page identity changed order');
      }
      if (upper != null && _compareKeys(key, upper) > 0 ||
          lower != null &&
              _compareKeys(key, lower) >= 0 &&
              (proof == null ||
                  !identical(proof.membership, coverage.membership) ||
                  proof.membershipBaselineVersion !=
                      coverage.baselineVersion)) {
        throw const ConversationContinuityError(
          'unknown identity inside coverage',
        );
      }
      if (lower != null && _compareKeys(key, lower) >= 0) {
        _attempt.proofs.requireRange(key, key);
      }
      if (proof != null &&
          !proof.removed &&
          proof.revision > item.revision &&
          (_attempt.items[item.id]?.revision ?? -1) < proof.revision) {
        throw const ConversationContinuityError(
          'page revision proof has no current preview',
        );
      }
    }
    for (final proof in _attempt.proofs.entries.values) {
      if (proof.removed) continue;
      final key = proof.key;
      if (key == null) {
        throw const ConversationContinuityError(
          'page identity order is unknown',
        );
      }
      final crossed =
          (lower == null || _compareKeys(key, lower) < 0) &&
          (!page.hasOlder ||
              pageLower == null ||
              _compareKeys(key, pageLower) >= 0);
      if (crossed &&
          (proof.presentSince == null || proof.presentSince! <= readSequence) &&
          !ids.contains(proof.id)) {
        throw const ConversationContinuityError(
          'page omitted a known earlier identity',
        );
      }
    }
  }
}
