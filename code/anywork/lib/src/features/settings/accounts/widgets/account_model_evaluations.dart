import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

String accountEvaluationOutcomeLabel(
  AppLocalizations l10n,
  AccountEvaluationOutcome outcome,
) => switch (outcome) {
  AccountEvaluationOutcome.passed => l10n.modelDetailEvaluationPassed,
  AccountEvaluationOutcome.failed => l10n.modelDetailEvaluationFailed,
  AccountEvaluationOutcome.notRated => l10n.modelDetailEvaluationNotRated,
};

String accountEvaluationCategoryLabel(
  AppLocalizations l10n,
  AccountEvaluationCategory category,
) => switch (category) {
  AccountEvaluationCategory.reasoning => l10n.modelDetailTaskReasoning,
  AccountEvaluationCategory.coding => l10n.modelDetailTaskCoding,
  AccountEvaluationCategory.tooling => l10n.modelDetailTaskTooling,
  AccountEvaluationCategory.longContext => l10n.modelDetailTaskLongContext,
  AccountEvaluationCategory.multimodal => l10n.modelDetailTaskMultimodal,
  AccountEvaluationCategory.general => l10n.modelDetailTaskGeneral,
};

class AccountEvaluationSummaryPanel extends StatelessWidget {
  const AccountEvaluationSummaryPanel({required this.value, super.key});
  final AccountEvaluationSummary value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final scores = Wrap(
                  spacing: 32,
                  runSpacing: 16,
                  children: [
                    for (final score in [
                      (l10n.modelDetailQuality, value.quality),
                      (
                        l10n.modelDetailInstructionFollowing,
                        value.instructionFollowing,
                      ),
                    ])
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${score.$2?.toStringAsFixed(1) ?? '—'} / 5',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            score.$1,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                  ],
                );
                final distribution = Column(
                  children: [
                    for (var score = 5; score >= 1; score--)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                '$score',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: value.count == 0
                                    ? 0
                                    : (value.qualityDistribution[score] ?? 0) /
                                          value.count,
                                minHeight: 4,
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${value.qualityDistribution[score] ?? 0}',
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return constraints.maxWidth >= 650
                    ? Row(
                        children: [
                          Expanded(child: scores),
                          const SizedBox(width: 32),
                          Expanded(child: distribution),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          scores,
                          const SizedBox(height: 20),
                          distribution,
                        ],
                      );
              },
            ),
            const Divider(height: 28),
            Text(
              l10n.accountsEvaluationWindow,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class AccountEvaluationFilters extends StatelessWidget {
  const AccountEvaluationFilters({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final AccountEvaluationFilter value;
  final ValueChanged<AccountEvaluationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outcomes = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          label: Text(l10n.accountsFilterAll),
          selected: value.outcome == null,
          onSelected: (_) => onChanged(value.copyWith(outcome: null)),
        ),
        for (final outcome in AccountEvaluationOutcome.values)
          FilterChip(
            label: Text(accountEvaluationOutcomeLabel(l10n, outcome)),
            selected: value.outcome == outcome,
            onSelected: (selected) =>
                onChanged(value.copyWith(outcome: selected ? outcome : null)),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final fieldWidth = (200 * scale)
            .clamp(0, constraints.maxWidth)
            .toDouble();
        final qualityWidth = (180 * scale)
            .clamp(0, constraints.maxWidth)
            .toDouble();
        final category = DropdownMenu<AccountEvaluationCategory?>(
          key: ValueKey(('category', value.category)),
          initialSelection: value.category,
          width: fieldWidth,
          label: Text(l10n.accountsFilterCategory),
          menuHeight: 360,
          dropdownMenuEntries: [
            DropdownMenuEntry(value: null, label: l10n.accountsFilterCategory),
            for (final category in AccountEvaluationCategory.values)
              DropdownMenuEntry(
                value: category,
                label: accountEvaluationCategoryLabel(l10n, category),
              ),
          ],
          onSelected: (category) =>
              onChanged(value.copyWith(category: category)),
        );
        final quality = DropdownMenu<int?>(
          key: ValueKey(('minimum-quality', value.minimumQuality)),
          width: qualityWidth,
          maxLines: null,
          label: Text(l10n.accountsFilterScore),
          menuHeight: 360,
          initialSelection: value.minimumQuality,
          dropdownMenuEntries: [
            DropdownMenuEntry(value: null, label: l10n.accountsFilterScore),
            for (var score = 1; score <= 5; score++)
              DropdownMenuEntry(
                value: score,
                label: '${l10n.modelDetailQuality} ≥ $score',
              ),
          ],
          onSelected: (score) =>
              onChanged(value.copyWith(minimumQuality: score)),
        );
        final sort = DropdownMenu<AccountEvaluationSort>(
          key: ValueKey(('evaluation-sort', value.sort)),
          initialSelection: value.sort,
          width: fieldWidth,
          maxLines: null,
          menuHeight: 260,
          dropdownMenuEntries: [
            DropdownMenuEntry(
              value: AccountEvaluationSort.newest,
              label: l10n.accountsSortNewest,
            ),
            DropdownMenuEntry(
              value: AccountEvaluationSort.highestQuality,
              label: l10n.accountsSortHighest,
            ),
            DropdownMenuEntry(
              value: AccountEvaluationSort.lowestQuality,
              label: l10n.accountsSortLowest,
            ),
          ],
          onSelected: (sort) {
            if (sort != null) onChanged(value.copyWith(sort: sort));
          },
        );
        final filters = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            outcomes,
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [category, quality]),
          ],
        );
        return constraints.maxWidth >= 760 * scale
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: filters),
                  const SizedBox(width: 16),
                  sort,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filters,
                  const SizedBox(height: 12),
                  Align(alignment: AlignmentDirectional.centerEnd, child: sort),
                ],
              );
      },
    );
  }
}

class AccountEvaluationCard extends StatelessWidget {
  const AccountEvaluationCard({required this.value, super.key});
  final AccountModelEvaluation value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rated = value.outcome != AccountEvaluationOutcome.notRated;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(value.outcomeLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(value.categoryLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Text(
                  value.updatedLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AccountSelectableText(value.comment),
            const Divider(height: 28),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text(
                  '${l10n.modelDetailQuality} · ${rated && value.quality != null ? '${value.quality} / 5' : '—'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  '${l10n.modelDetailInstructionFollowing} · ${rated && value.instructionFollowing != null ? '${value.instructionFollowing} / 5' : '—'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AccountEvaluationsView extends StatelessWidget {
  const AccountEvaluationsView({
    required this.value,
    required this.onFilterChanged,
    super.key,
  });
  final AccountEvaluationSummary value;
  final ValueChanged<AccountEvaluationFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountEvaluationSummaryPanel(value: value),
        const SizedBox(height: 16),
        AccountEvaluationFilters(
          value: value.filter,
          onChanged: onFilterChanged,
        ),
        const SizedBox(height: 16),
        if (value.visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              value.count == 0
                  ? l10n.modelDetailEvaluationsEmpty
                  : l10n.accountsFilterEmpty,
            ),
          ),
        for (final evaluation in value.visible)
          AccountEvaluationCard(value: evaluation),
      ],
    );
  }
}
