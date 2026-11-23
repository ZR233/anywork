import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';

/// Static preview inputs, composed into the same production list and cards.
/// Row fixtures are deliberately not part of the list owner's runtime state.
final class AccountListPreviewData {
  const AccountListPreviewData({
    this.rows = const [],
    this.phase = AccountListPhase.ready,
    this.search = '',
    this.category = AccountListCategory.all,
    this.searchHasNoResults = false,
    this.refreshing = false,
    this.canAdd = true,
    this.canRefresh = false,
    this.error,
  });

  final List<AccountRowPresentation> rows;
  final AccountListPhase phase;
  final String search;
  final AccountListCategory category;
  final bool searchHasNoResults;
  final bool refreshing;
  final bool canAdd;
  final bool canRefresh;
  final String? error;

  AccountsListPresentation get presentation {
    final acpCount = rows
        .where((row) => row.key.kind == AccountKind.acp)
        .length;
    final nativeCount = rows
        .where((row) => row.key.kind == AccountKind.native)
        .length;
    final upgradableCount = rows
        .where(
          (row) => switch (row.content) {
            AcpAccountRowContent(:final upgrade) =>
              upgrade?.phase == AcpUpgradePhase.updateAvailable,
            _ => false,
          },
        )
        .length;
    return AccountsListPresentation(
      members: [for (final row in rows) row.key],
      phase: phase,
      search: search,
      category: category,
      totalCount: rows.length,
      acpCount: acpCount,
      nativeCount: nativeCount,
      upgradableCount: upgradableCount,
      searchHasNoResults: searchHasNoResults,
      refreshing: refreshing,
      canAdd: canAdd,
      canRefresh: canRefresh,
      error: error,
    );
  }

  AccountListPreviewData copyWith({
    List<AccountRowPresentation>? rows,
    AccountListCategory? category,
    bool? refreshing,
  }) => AccountListPreviewData(
    rows: rows ?? this.rows,
    phase: phase,
    search: search,
    category: category ?? this.category,
    searchHasNoResults: searchHasNoResults,
    refreshing: refreshing ?? this.refreshing,
    canAdd: canAdd,
    canRefresh: canRefresh,
    error: error,
  );
}
