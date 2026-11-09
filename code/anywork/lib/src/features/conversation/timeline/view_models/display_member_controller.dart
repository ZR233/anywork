import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import 'conversation_current_owner.dart';

/// One display-lease-owned bounded member demand, stable across live/history.
final class DisplayMemberController extends ChangeNotifier {
  DisplayMemberController({
    required this.reference,
    required this.demand,
    required this.open,
  }) {
    select(const LatestDisplayMembers());
  }
  final DisplayBlockRef reference;
  final ReadDemand demand;
  final Future<DisplayMembers> Function(
    DisplayBlockRef,
    DisplayMemberWindow,
    ReadDemand,
  )
  open;
  DisplayMemberWindow window = const LatestDisplayMembers();
  DisplayMemberPage? page;
  Object? _error;
  Object? cleanupError;
  Object? get error => cleanupError ?? _error;
  bool loading = true;
  bool _retired = false;
  Object _qualification = Object();
  DisplayMembers? _handle;
  final Set<DisplayMembers> _closing = {};
  final Map<String, TimelineMemberDisclosure> _disclosures = {};
  Future<void> _joins = Future.value();

  bool get isActive => !_retired;
  TimelineMemberDisclosure disclosure(String memberKey) =>
      _disclosures.putIfAbsent(memberKey, TimelineMemberDisclosure.new);

  void _retireDisclosures({Set<String> keep = const {}}) {
    for (final key in _disclosures.keys.toList()) {
      if (keep.contains(key)) continue;
      _disclosures.remove(key)!.retire();
    }
  }

  void select(DisplayMemberWindow next) {
    if (_retired) return;
    _qualification = Object();
    final qualification = _qualification;
    _closeHandle();
    window = next;
    page = null;
    _retireDisclosures();
    _error = null;
    loading = true;
    notifyListeners();
    unawaited(_pull(qualification, next));
  }

  Future<void> retry() async {
    await _joins;
    if (_retired) return;
    for (final handle in List.of(_closing)) {
      _closing.remove(handle);
      _close(handle);
    }
    select(window);
  }

  bool _eligible(Object qualification) =>
      !_retired && identical(_qualification, qualification);

  Future<void> _pull(Object qualification, DisplayMemberWindow selected) async {
    DisplayMembers? handle;
    try {
      await _joins;
      if (!_eligible(qualification)) return;
      if (_closing.isNotEmpty) {
        throw cleanupError ?? StateError('Member window still closing');
      }
      handle = await open(reference, selected, demand);
      if (!_eligible(qualification)) {
        _close(handle);
        return;
      }
      _handle = handle;
      while (_eligible(qualification)) {
        final value = await handle.next();
        if (!_eligible(qualification)) return;
        if (value == null) {
          loading = false;
          _closeHandle();
          notifyListeners();
          return;
        }
        page = value;
        _retireDisclosures(
          keep: value.entries.map((entry) => entry.memberKey).toSet(),
        );
        loading = false;
        _error = null;
        notifyListeners();
        // Sealed is still one real page. Consume the explicit EOF next, rather
        // than synthesizing another page or leaving a useless history watch.
      }
    } catch (failure) {
      if (_eligible(qualification)) {
        _error = failure;
        loading = false;
        _closeHandle();
        notifyListeners();
      }
    }
  }

  void _close(DisplayMembers handle) {
    if (!_closing.add(handle)) return;
    try {
      handle.requestClose();
    } catch (failure) {
      cleanupError = failure;
    }
    _joins = _joins.then((_) async {
      try {
        await handle.close();
        _closing.remove(handle);
        if (_closing.isEmpty && cleanupError != null) {
          cleanupError = null;
          if (!_retired) notifyListeners();
        }
      } catch (failure) {
        cleanupError = failure;
        if (!_retired) {
          notifyListeners();
        }
      }
    });
  }

  void _closeHandle() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _close(handle);
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _qualification = Object();
    _closeHandle();
    page = null;
    _retireDisclosures();
  }

  Future<void> close() async {
    retire();
    await _joins;
  }
}
