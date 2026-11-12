import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';

/// Static preview inputs, composed into the same production list and cards.
/// Row fixtures are deliberately not part of the list owner's runtime state.
final class AccountListPreviewData {
  const AccountListPreviewData({
    this.rows = const [],
    this.phase = AccountListPhase.ready,
    this.search = '',
    this.searchHasNoResults = false,
    this.refreshing = false,
    this.canAdd = true,
    this.canRefresh = false,
    this.error,
  });

  final List<AccountRowPresentation> rows;
  final AccountListPhase phase;
  final String search;
  final bool searchHasNoResults;
  final bool refreshing;
  final bool canAdd;
  final bool canRefresh;
  final String? error;

  AccountsListPresentation get presentation => AccountsListPresentation(
    members: [for (final row in rows) row.key],
    phase: phase,
    search: search,
    searchHasNoResults: searchHasNoResults,
    refreshing: refreshing,
    canAdd: canAdd,
    canRefresh: canRefresh,
    error: error,
  );

  AccountListPreviewData copyWith({
    List<AccountRowPresentation>? rows,
    bool? refreshing,
  }) => AccountListPreviewData(
    rows: rows ?? this.rows,
    phase: phase,
    search: search,
    searchHasNoResults: searchHasNoResults,
    refreshing: refreshing ?? this.refreshing,
    canAdd: canAdd,
    canRefresh: canRefresh,
    error: error,
  );
}
