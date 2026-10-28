import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../accounts_views.dart';
import 'account_preview_fixtures.dart';
import 'account_preview_host.dart';
import 'account_template_preview_fixtures.dart';

const components = 'Accounts · Components';

@Preview(
  name: 'Identity / header / unknown brand',
  group: components,
  size: Size(960, 180),
)
Widget accountIdentityHeaderPreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(24),
    child: AccountIdentity(
      name: '用于跨区域部署的超长合成账号名称',
      iconKey: 'unknown-brand',
      subtitle: '合成协议 · fallback 首字母',
      isDefault: true,
      layout: AccountIdentityLayout.header,
    ),
  ),
  scenarioIdentity: 'identity-header-unknown',
  textScale: 1.3,
);

@Preview(
  name: 'Identity / compact + list',
  group: components,
  size: Size(408, 220),
)
Widget accountIdentityCompactPreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountIdentity(
          name: '智谱',
          iconKey: 'zhipu',
          layout: AccountIdentityLayout.compact,
        ),
        SizedBox(height: 20),
        AccountIdentity(
          name: '未知品牌 · fallback',
          iconKey: 'missing',
          layout: AccountIdentityLayout.list,
        ),
      ],
    ),
  ),
  scenarioIdentity: 'identity-compact-list',
);

@Preview(
  name: 'Identity / list single-line safe origin / 408',
  group: components,
  size: Size(408, 180),
)
Widget accountIdentityListSingleLineOriginPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountIdentity(
      name: 'DeepSeek',
      iconKey: 'deepseek',
      isDefault: false,
      layout: AccountIdentityLayout.list,
      subtitle: 'https://very-long-safe-origin.synthetic.example.test:8443',
      subtitleLayout: AccountIdentitySubtitleLayout.singleLine,
    ),
  ),
  scenarioIdentity: 'identity-list-single-line-safe-origin-408',
);

@Preview(
  name: 'List item / native mixed metrics / columns 960',
  group: components,
  size: Size(960, 280),
)
Widget accountListItemColumnsPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountListItem(
      value: AccountPreviewFixtures.list.rows.first,
      layout: AccountItemLayout.columns,
      onOpen: () => record('open details'),
      onAction: (action) => record('row action: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'list-item-native-columns',
);

@Preview(
  name: 'List item / unknown billing + failed last-good / stacked 408',
  group: components,
  size: Size(408, 430),
)
Widget accountListItemStackedPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: AccountListItem(
      value: AccountPreviewFixtures.stackedLastGoodRow,
      layout: AccountItemLayout.stacked,
      onOpen: () => record('open details'),
      onAction: (action) => record('row action only: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'list-item-stacked-last-good',
  textScale: 1.3,
);

@Preview(
  name: 'List item / ACP status',
  group: components,
  size: Size(960, 180),
)
Widget accountListItemAcpPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountListItem(
      value: AccountTemplatePreviewFixtures.row('antigravity'),
      layout: AccountItemLayout.columns,
      onOpen: () => record('open ACP'),
      onAction: (action) => record('ACP action only: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'list-item-acp',
);

@Preview(
  name: 'List item / ACP long wrapped status / 960 / text 1.0',
  group: components,
  size: Size(960, 280),
)
Widget accountListItemAcpLongStatusWidePreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountListItem(
      value: AccountTemplatePreviewFixtures.row('antigravity').copyWith(
        content: const AccountRowContent.acp(
          status: 'Preparing managed connection',
        ),
      ),
      layout: AccountItemLayout.columns,
      onOpen: () => record('open ACP details'),
      onAction: (action) => record('ACP action: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'acp-long-status-columns-wide-1.0',
  locale: const Locale('en'),
);

@Preview(
  name: 'List item / ACP long wrapped status / 960 / text 1.3',
  group: components,
  size: Size(960, 320),
)
Widget accountListItemAcpLongStatusLargeTextPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountListItem(
      value: AccountTemplatePreviewFixtures.row('antigravity').copyWith(
        content: const AccountRowContent.acp(
          status: 'Preparing managed connection',
        ),
      ),
      layout: AccountItemLayout.columns,
      onOpen: () => record('open ACP details'),
      onAction: (action) => record('ACP action: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'acp-long-status-columns-wide-1.3',
  locale: const Locale('en'),
  textScale: 1.3,
);

@Preview(
  name: 'List item / safe synthetic display origin',
  group: components,
  size: Size(960, 220),
)
Widget accountListItemWithDisplayOriginPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountListItem(
      value: AccountTemplatePreviewFixtures.row(
        'deepseek',
        displayEndpoint: 'https://api.example.test:8443',
      ),
      layout: AccountItemLayout.columns,
      onOpen: () => record('open details'),
      onAction: (action) => record('row action: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'list-item-safe-display-origin',
);

@Preview(
  name: 'List item / absent display origin',
  group: components,
  size: Size(408, 240),
)
Widget accountListItemWithoutDisplayOriginPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(12),
    child: AccountListItem(
      value: AccountTemplatePreviewFixtures.row('openai'),
      layout: AccountItemLayout.stacked,
      onOpen: () => record('open details'),
      onAction: (action) => record('row action: ${action.name}'),
    ),
  ),
  scenarioIdentity: 'list-item-no-display-origin',
);

@Preview(
  name: 'Template selector / usage query supported / Native + ACP / 960',
  group: components,
  size: Size(960, 520),
)
Widget accountTemplateSelectorPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: AccountTemplateSelector(
      templates: AccountPreviewFixtures.templates,
      selected: AccountPreviewFixtures.templateKey,
      onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
    ),
  ),
  scenarioIdentity: 'template-selector-enabled',
);

@Preview(
  name: 'Template selector / usage query unsupported',
  group: components,
  size: Size(720, 460),
)
Widget accountTemplateSelectorUnsupportedUsagePreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: AccountTemplateSelector(
      templates: AccountPreviewFixtures.templates,
      selected: const AccountTemplateKey(
        kind: AccountKind.native,
        id: 'openai',
      ),
      onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
    ),
  ),
  scenarioIdentity: 'template-selector-usage-unsupported',
);

@Preview(
  name: 'Template selector / usage capability not provided',
  group: components,
  size: Size(720, 460),
)
Widget accountTemplateSelectorUnknownUsagePreview() =>
    accountPreviewHost((record) {
      final unknown = AccountTemplatePreviewFixtures.usageUnknownTemplate();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: AccountTemplateSelector(
          templates: [...AccountPreviewFixtures.templates, unknown],
          selected: unknown.key,
          onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
        ),
      );
    }, scenarioIdentity: 'template-selector-usage-unknown');

@Preview(
  name: 'Template selector / ACP selected',
  group: components,
  size: Size(720, 460),
)
Widget accountTemplateSelectorAcpPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: AccountTemplateSelector(
      templates: AccountPreviewFixtures.templates,
      selected: const AccountTemplateKey(
        kind: AccountKind.acp,
        id: 'antigravity',
      ),
      onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
    ),
  ),
  scenarioIdentity: 'template-selector-acp',
);

@Preview(
  name: 'Template selector / plan endpoint + large text / 408',
  group: components,
  size: Size(408, 680),
)
Widget accountTemplateSelectorNarrowPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: AccountTemplateSelector(
      templates: AccountPreviewFixtures.templates,
      selected: const AccountTemplateKey(
        kind: AccountKind.native,
        id: 'zhipu-coding-plan',
      ),
      onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
    ),
  ),
  scenarioIdentity: 'template-selector-plan-narrow',
  textScale: 1.3,
);

@Preview(
  name: 'Template selector / disabled',
  group: components,
  size: Size(408, 170),
)
Widget accountTemplateSelectorDisabledPreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountTemplateSelector(
      templates: AccountPreviewFixtures.templates,
      selected: null,
      enabled: false,
      onSelected: (_) {},
    ),
  ),
  scenarioIdentity: 'template-selector-disabled',
);

@Preview(
  name: 'Template selector / empty directory',
  group: components,
  size: Size(408, 170),
)
Widget accountTemplateSelectorEmptyPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountTemplateSelector(
      templates: const [],
      selected: null,
      onSelected: (key) => record('select ${key.kind.name}/${key.id}'),
    ),
  ),
  scenarioIdentity: 'template-selector-empty',
);

@Preview(
  name: 'Native connection fields / existing credential',
  group: components,
  size: Size(960, 450),
)
Widget accountNativeConnectionFieldsPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: AccountNativeConnectionFields(
      value: AccountPreviewFixtures.editor,
      onChanged: (field, raw) => record('${field.name}: $raw'),
    ),
  ),
  scenarioIdentity: 'native-connection-fields',
);

@Preview(
  name: 'Connection control / multiple transports',
  group: components,
  size: Size(600, 160),
)
Widget accountConnectionControlPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(24),
    child: AccountConnectionControl(
      value: AccountConnection.automatic,
      allowed: AccountConnection.values,
      onChanged: (value) => record('connection: ${value.name}'),
    ),
  ),
  scenarioIdentity: 'connection-control',
);

@Preview(
  name: 'Manual model editor / advanced values',
  group: components,
  size: Size(960, 620),
)
Widget accountManualModelEditorPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(24),
    child: AccountManualModelEditor(
      value: AccountPreviewFixtures.editor.manualModels.first,
      onFieldChanged: (field, raw) => record('${field.name}: $raw'),
      onConnectionChanged: (value) => record('connection: ${value.name}'),
      onWireApiChanged: (value) => record('wire API: ${value.name}'),
      onRemove: () => record('remove manual model'),
    ),
  ),
  scenarioIdentity: 'manual-model-editor',
);

@Preview(
  name: 'Model item / online enabled + expanded',
  group: components,
  size: Size(960, 700),
)
Widget accountModelItemOnlinePreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: Card(
      child: AccountModelListItem(
        value: AccountPreviewFixtures.model,
        actions: accountPreviewModelActions(record),
        initiallyExpanded: true,
      ),
    ),
  ),
  scenarioIdentity: 'model-item-online',
);

@Preview(
  name: 'Model item / bundled disabled',
  group: components,
  size: Size(408, 260),
)
Widget accountModelItemBundledPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(12),
    child: Card(
      child: AccountModelListItem(
        value: AccountPreviewFixtures.catalog.models[2],
        actions: accountPreviewModelActions(record),
      ),
    ),
  ),
  scenarioIdentity: 'model-item-bundled',
);

@Preview(
  name: 'Models view / online + bundled off + manual',
  group: components,
  size: Size(960, 900),
)
Widget accountModelsViewMixedPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountModelsView(
      value: AccountPreviewFixtures.catalog.copyWith(
        models: [
          AccountPreviewFixtures.catalog.models[0],
          AccountPreviewFixtures.catalog.models[2].copyWith(enabled: false),
          AccountPreviewFixtures.catalog.models.last,
        ],
      ),
      actions: accountPreviewModelActions(record),
      onSync: () => record('sync intent only'),
      onAddModel: () => record('add intent only'),
    ),
  ),
  scenarioIdentity: 'models-view-mixed',
);

@Preview(
  name: 'Model item / manual actions',
  group: components,
  size: Size(720, 300),
)
Widget accountModelItemManualPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Card(
      child: AccountModelListItem(
        value: AccountPreviewFixtures.catalog.models.last,
        actions: accountPreviewModelActions(record),
      ),
    ),
  ),
  scenarioIdentity: 'model-item-manual',
);

@Preview(
  name: 'Compact threshold / draft and explicit save',
  group: components,
  size: Size(960, 370),
)
Widget accountCompactDraftPreview() => accountPreviewHost(
  (record) =>
      SingleChildScrollView(child: _CompactDraftPreview(record: record)),
  scenarioIdentity: 'compact-draft',
);

class _CompactDraftPreview extends StatefulWidget {
  const _CompactDraftPreview({required this.record});
  final ValueChanged<String> record;
  @override
  State<_CompactDraftPreview> createState() => _CompactDraftPreviewState();
}

class _CompactDraftPreviewState extends State<_CompactDraftPreview> {
  AccountCompactPresentation value = AccountPreviewFixtures.model.compact!
      .copyWith(
        dirty: true,
        canSave: true,
        adjusted: true,
        contextWindow: 1000000,
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountCompactView(
      value: value,
      onChanged: (raw) =>
          setState(() => value = value.copyWith(raw: raw, dirty: true)),
      onPreset: (percent) {
        setState(
          () => value = value.copyWith(raw: 'preset $percent%', dirty: true),
        );
        widget.record('local preset draft: $percent%');
      },
      onSave: () => widget.record('save intent only'),
      onReset: () => widget.record('restore automatic intent only'),
      onRetry: () => widget.record('retry intent only'),
    ),
  );
}

@Preview(
  name: 'Compact threshold / saving + invalid',
  group: components,
  size: Size(408, 420),
)
Widget accountCompactInvalidSavingPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: AccountCompactView(
      value: const AccountCompactPresentation(
        raw: '1.2k',
        overridden: true,
        automatic: 'unknown',
        effective: '475000',
        error: '保留原始输入；请输入正整数。',
        saving: true,
        canEdit: true,
        canReset: true,
        canRetry: true,
        dirty: true,
        adjusted: true,
      ),
      onChanged: (raw) => record('raw: $raw'),
      onPreset: (value) => record('preset: $value'),
      onSave: () => record('save intent only'),
      onReset: () => record('reset intent only'),
      onRetry: () => record('retry intent only'),
    ),
  ),
  scenarioIdentity: 'compact-invalid-saving',
);

@Preview(
  name: 'Specifications / declared facts + missing performance',
  group: components,
  size: Size(960, 650),
)
Widget accountModelSpecificationsPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountModelSpecifications(
      value: AccountPreviewFixtures.model.copyWith(
        performance: const AccountPerformancePresentation(
          sampleCount: 0,
          ttftSampleCount: 0,
        ),
      ),
    ),
  ),
  scenarioIdentity: 'model-specs-missing-performance',
);

@Preview(
  name: 'Specifications / all typed fact groups empty / narrow',
  group: components,
  size: Size(408, 900),
)
Widget accountModelSpecificationsAllFactsEmptyPreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountModelSpecifications(
      value: AccountPreviewFixtures.model.copyWith(
        specificationFacts: const AccountModelSpecificationFacts(),
      ),
    ),
  ),
  scenarioIdentity: 'model-specification-all-facts-empty-narrow',
  locale: const Locale('en'),
  textScale: 1.3,
);

@Preview(
  name: 'Pricing / currency + missing cache tier values',
  group: components,
  size: Size(960, 520),
)
Widget accountModelPricingPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountModelPricing(
      value: AccountPreviewFixtures.model.copyWith(
        priceTiers: const [
          AccountModelPriceTier(label: '≤ 128K', input: 2.4, output: 9.6),
          AccountModelPriceTier(
            label: '> 128K · 未知缓存价格',
            input: 4.8,
            output: 9.6,
          ),
        ],
        currency: null,
        priceSource: null,
        priceVerifiedLabel: null,
      ),
    ),
  ),
  scenarioIdentity: 'model-pricing-unknown',
);

@Preview(
  name: 'Pricing / no price facts',
  group: components,
  size: Size(408, 300),
)
Widget accountModelPricingMissingPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(12),
    child: AccountModelPricing(
      value: AccountPreviewFixtures.model.copyWith(
        priceTiers: const [],
        currency: null,
        priceSource: null,
        priceVerifiedLabel: null,
      ),
    ),
  ),
  scenarioIdentity: 'model-pricing-missing',
);

@Preview(
  name: 'Price row / known tier, unknown currency + cache',
  group: components,
  size: Size(408, 330),
)
Widget accountModelPriceRowPreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(12),
    child: AccountModelPriceRow(
      value: AccountModelPriceTier(label: '合成档位 · 缓存字段未知', input: 2, output: 3),
      currency: null,
    ),
  ),
  scenarioIdentity: 'price-row-unknown',
);

@Preview(
  name: 'Price row / long tier title and unit / narrow',
  group: components,
  size: Size(408, 540),
)
Widget accountModelPriceRowLongTitlePreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountModelPriceRow(
      value: AccountPreviewFixtures.model.priceTiers.first.copyWith(
        label: 'Synthetic extended-context tier title for layout wrapping demonstration; no additional pricing claim',
      ),
      currency: AccountPreviewFixtures.model.currency,
    ),
  ),
  scenarioIdentity: 'price-row-long-tier-title-narrow',
  locale: const Locale('en'),
  textScale: 1.3,
);

@Preview(
  name: 'Evaluations / both scores + not rated + long comment',
  group: components,
  size: Size(960, 950),
)
Widget accountEvaluationsPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AccountEvaluationsView(
      value: AccountPreviewFixtures.model.evaluationSummary,
      onFilterChanged: (filter) => record('local filter: ${filter.sort.name}'),
    ),
  ),
  scenarioIdentity: 'evaluations-filled',
  textScale: 1.15,
);

@Preview(
  name: 'Evaluations / no samples',
  group: components,
  size: Size(408, 650),
)
Widget accountEvaluationsEmptyPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: AccountEvaluationsView(
      value: const AccountEvaluationSummary(),
      onFilterChanged: (filter) => record('local filter: ${filter.sort.name}'),
    ),
  ),
  scenarioIdentity: 'evaluations-empty',
);

@Preview(
  name: 'Evaluations / filter has no results',
  group: components,
  size: Size(720, 420),
)
Widget accountEvaluationsNoFilterResultPreview() => accountPreviewHost(
  (record) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: AccountEvaluationsView(
      value: AccountPreviewFixtures.filteredEmptyEvaluationSummary,
      onFilterChanged: (filter) =>
          record('local filter: ${filter.outcome?.name}'),
    ),
  ),
  scenarioIdentity: 'evaluations-filter-empty',
);

@Preview(
  name: 'Evaluation filters / all states',
  group: components,
  size: Size(960, 260),
)
Widget accountEvaluationFiltersPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountEvaluationFilters(
      value: const AccountEvaluationFilter(),
      onChanged: (filter) => record('local filter: ${filter.sort.name}'),
    ),
  ),
  scenarioIdentity: 'evaluation-filters',
);

@Preview(
  name: 'Evaluation filters / English / 960 / text 1.0',
  group: components,
  size: Size(960, 420),
)
Widget accountEvaluationFiltersEnglishWideDefaultScalePreview() =>
    accountPreviewHost(
      (record) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _EnglishEvaluationFiltersScenario(record: record),
      ),
      scenarioIdentity: 'evaluation-filters-en-960-1.0',
      locale: const Locale('en'),
    );

@Preview(
  name: 'Evaluation filters / English / 408 / text 1.0',
  group: components,
  size: Size(408, 720),
)
Widget accountEvaluationFiltersEnglishNarrowDefaultScalePreview() =>
    accountPreviewHost(
      (record) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _EnglishEvaluationFiltersScenario(record: record),
      ),
      scenarioIdentity: 'evaluation-filters-en-408-1.0',
      locale: const Locale('en'),
    );

@Preview(
  name: 'Evaluation filters / English / 960 / text 1.3',
  group: components,
  size: Size(960, 520),
)
Widget accountEvaluationFiltersEnglishWideLargeTextPreview() =>
    accountPreviewHost(
      (record) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _EnglishEvaluationFiltersScenario(record: record),
      ),
      scenarioIdentity: 'evaluation-filters-en-960-1.3',
      locale: const Locale('en'),
      textScale: 1.3,
    );

@Preview(
  name: 'Evaluation filters / English / 408 / text 1.3',
  group: components,
  size: Size(408, 900),
)
Widget accountEvaluationFiltersEnglishNarrowLargeTextPreview() =>
    accountPreviewHost(
      (record) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _EnglishEvaluationFiltersScenario(record: record),
      ),
      scenarioIdentity: 'evaluation-filters-en-408-1.3',
      locale: const Locale('en'),
      textScale: 1.3,
    );

class _EnglishEvaluationFiltersScenario extends StatefulWidget {
  const _EnglishEvaluationFiltersScenario({required this.record});
  final ValueChanged<String> record;

  @override
  State<_EnglishEvaluationFiltersScenario> createState() =>
      _EnglishEvaluationFiltersScenarioState();
}

class _EnglishEvaluationFiltersScenarioState
    extends State<_EnglishEvaluationFiltersScenario> {
  AccountEvaluationFilter value = const AccountEvaluationFilter(
    sort: AccountEvaluationSort.newest,
  );

  @override
  Widget build(BuildContext context) => AccountEvaluationFilters(
    value: value,
    onChanged: (next) => setState(() {
      value = next;
      widget.record('local filter: ${next.sort.name}');
    }),
  );
}

@Preview(
  name: 'Evaluation card / unrated',
  group: components,
  size: Size(720, 360),
)
Widget accountEvaluationCardNotRatedPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountEvaluationCard(
      value: AccountPreviewFixtures.evaluations.last,
    ),
  ),
  scenarioIdentity: 'evaluation-card-not-rated',
);

@Preview(
  name: 'Evaluation card / dual scores + long comment',
  group: components,
  size: Size(720, 500),
)
Widget accountEvaluationCardLongCommentPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountEvaluationCard(
      value: AccountPreviewFixtures.evaluations.first.copyWith(
        comment:
            '合成评语：先识别用户给出的约束，再逐项核验输入边界、失败路径与可观察结果。'
            '执行中没有把未知信息补成默认值，并在出现错误时保留了原始意图。'
            '这段较长正文仅展示真实评价字段的换行与阅读体验，不包含评价者、标题或额外标签。',
      ),
    ),
  ),
  scenarioIdentity: 'evaluation-card-long-comment',
);

@Preview(
  name: 'Evaluation summary / dual score distribution',
  group: components,
  size: Size(960, 370),
)
Widget accountEvaluationSummaryPreview() => accountPreviewHost(
  (_) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountEvaluationSummaryPanel(
      value: AccountPreviewFixtures.model.evaluationSummary,
    ),
  ),
  scenarioIdentity: 'evaluation-summary',
);

@Preview(
  name: 'Usage / mixed currencies and quotas',
  group: components,
  size: Size(960, 680),
)
Widget accountUsageMixedPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountUsageView(
      value: AccountPreviewFixtures.balance.copyWith(
        quotas: AccountPreviewFixtures.subscription.quotas,
      ),
      onRetry: () => record('retry locally'),
    ),
  ),
  scenarioIdentity: 'usage-mixed',
);

@Preview(
  name: 'Usage / unsupported and missing credential',
  group: components,
  size: Size(408, 360),
)
Widget accountUsageUnknownPreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountBillingBadge(billing: AccountBilling.noCharge),
        AccountUsageView(
          value: AccountUsagePresentation(phase: AccountQueryPhase.unsupported),
        ),
        Divider(),
        AccountUsageView(
          value: AccountUsagePresentation(
            phase: AccountQueryPhase.missingCredential,
          ),
        ),
      ],
    ),
  ),
  scenarioIdentity: 'usage-unknown',
);

@Preview(
  name: 'Balance metrics / full precision',
  group: components,
  size: Size(720, 300),
)
Widget accountBalanceMetricsPreview() => accountPreviewHost(
  (_) => Padding(
    padding: EdgeInsets.all(20),
    child: AccountBalanceMetrics(
      value: AccountPreviewFixtures.balance.balances.first,
    ),
  ),
  scenarioIdentity: 'balance-metrics',
);

@Preview(
  name: 'Balance metrics / narrow long secondary / text 1.3',
  group: components,
  size: Size(408, 520),
)
Widget accountBalanceMetricsNarrowLongSecondaryPreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: const AccountBalanceMetrics(
      value: AccountCurrencyBalance(
        currency: 'CNY',
        total: '2595.22',
        granted: '0.000000000000000001',
        toppedUp: '12345678901234567890.123456789012345678',
      ),
    ),
  ),
  scenarioIdentity: 'balance-metrics-narrow-long-secondary-1.3',
  textScale: 1.3,
);

@Preview(
  name: 'Balance metrics / narrow without total',
  group: components,
  size: Size(408, 260),
)
Widget accountBalanceMetricsNarrowWithoutTotalPreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: const AccountBalanceMetrics(
      value: AccountCurrencyBalance(
        currency: 'CNY',
        granted: '12.34',
        toppedUp: '56.78',
      ),
    ),
  ),
  scenarioIdentity: 'balance-metrics-narrow-without-total',
);

@Preview(
  name: 'Quota metrics / multiple windows',
  group: components,
  size: Size(720, 420),
)
Widget accountQuotaMetricsPreview() => accountPreviewHost(
  (_) => Padding(
    padding: EdgeInsets.all(20),
    child: AccountQuotaMetrics(
      values: AccountPreviewFixtures.subscription.quotas,
    ),
  ),
  scenarioIdentity: 'quota-metrics',
);

@Preview(
  name: 'Billing + status badges',
  group: components,
  size: Size(408, 200),
)
Widget accountBadgesPreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(20),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        AccountBillingBadge(
          billing: AccountBilling.metered,
          health: AccountBalanceHealth.sufficient,
        ),
        AccountBillingBadge(billing: AccountBilling.subscription),
        AccountBillingBadge(billing: AccountBilling.noCharge),
        AccountBillingBadge(billing: AccountBilling.unknown),
        AccountStatusBadge(label: 'ACP · 需要登录'),
      ],
    ),
  ),
  scenarioIdentity: 'account-badges',
);

@Preview(
  name: 'Status badges / wrapping / 140 and 150 / text 1.3',
  group: components,
  size: Size(408, 560),
)
Widget accountStatusBadgesWrappingPreview() => accountPreviewHost(
  (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(
          width: 140,
          child: AccountBillingBadge(
            billing: AccountBilling.subscription,
            labelLayout: AccountStatusLabelLayout.wrap,
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          width: 150,
          child: AccountBillingBadge(
            billing: AccountBilling.subscription,
            labelLayout: AccountStatusLabelLayout.wrap,
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          width: 140,
          child: AccountStatusBadge(
            label: 'Preparing managed connection',
            labelLayout: AccountStatusLabelLayout.wrap,
          ),
        ),
      ],
    ),
  ),
  scenarioIdentity: 'status-wrap-narrow-scaled',
  locale: const Locale('en'),
  textScale: 1.3,
);

@Preview(
  name: 'Billing control / explicit override + automatic restore',
  group: components,
  size: Size(720, 220),
)
Widget accountBillingControlPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountBillingControl(
      value: AccountPreviewFixtures.billing.copyWith(
        billingKindOverride: AccountBilling.subscription,
      ),
      onChanged: (billing) => record('billing intent: ${billing.name}'),
      onReset: () => record('restore automatic intent'),
    ),
  ),
  scenarioIdentity: 'billing-control',
);

@Preview(
  name: 'Details header / full actions',
  group: components,
  size: Size(960, 220),
)
Widget accountDetailsHeaderPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountDetailsHeader(
      value: AccountPreviewFixtures.details,
      onEdit: () => record('edit intent'),
      onDelete: () => record('delete intent'),
      onSetDefault: () => record('set default intent'),
    ),
  ),
  scenarioIdentity: 'details-header',
  textScale: 1.3,
);

@Preview(
  name: 'Section + facts + raw input + footer',
  group: components,
  size: Size(720, 560),
)
Widget accountSectionsAndFieldsPreview() => accountPreviewHost(
  (record) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      AccountSection(
        title: '合成独立分组',
        actions: [
          TextButton(
            onPressed: () => record('section action'),
            child: const Text('局部操作'),
          ),
        ],
        child: const AccountFacts(
          facts: [
            AccountDisplayFact(label: '币种金额（原始精度）', value: '2595.220000'),
            AccountDisplayFact(label: '状态', value: 'unknown · 不补零'),
          ],
        ),
      ),
      AccountRawTextField(
        value: const AccountTextPresentation(
          raw: '保留 raw 输入',
          error: '合成校验错误示例',
        ),
        label: '独立原始输入',
        onChanged: (raw) => record('raw: $raw'),
      ),
      const AccountInlineError(message: '合成错误不会自动重试。'),
      AccountEditorFooter(
        saving: false,
        canSave: true,
        onSave: () => record('save intent only'),
        onCancel: () => record('cancel'),
      ),
    ],
  ),
  scenarioIdentity: 'sections-fields-footer',
);

@Preview(
  name: 'Selectable text / long multiline / narrow 1.3',
  group: components,
  size: Size(408, 420),
)
Widget accountSelectableTextPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(24),
    child: AccountSelectableText(
      '合成长文本用于独立检查选择与滚动行为。账号详情中的说明和返回值可能包含多行内容，窄屏下应保持可读，并允许用户选择、复制完整文本。\n\n'
      '第二段继续提供足够的文字长度，以便检查内容换行、纵向滚动以及滚动状态不会与外层页面共用。此内容不代表真实账号或供应商数据。',
    ),
  ),
  scenarioIdentity: 'selectable-text-long-multiline',
  textScale: 1.3,
);

@Preview(
  name: 'Account menu button / icon + text triggers',
  group: components,
  size: Size(720, 220),
)
Widget accountMenuButtonTriggersPreview() => accountPreviewHost(
  (record) => Center(
    child: Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AccountMenuButton(
          buttonKey: const ValueKey('preview-menu-icon'),
          tooltip: '账号操作',
          menuChildren: [
            MenuItemButton(
              onPressed: () => record('icon menu: refresh'),
              child: const Text('刷新用量'),
            ),
            MenuItemButton(
              onPressed: () => record('icon menu: edit'),
              child: const Text('编辑账号'),
            ),
          ],
        ),
        AccountMenuButton(
          buttonKey: const ValueKey('preview-menu-text'),
          tooltip: '更多账号操作',
          label: '更多操作',
          menuChildren: [
            MenuItemButton(
              onPressed: () => record('text menu: set default'),
              child: const Text('设为默认'),
            ),
            MenuItemButton(
              onPressed: () => record('text menu: delete'),
              child: const Text('删除账号'),
            ),
          ],
        ),
      ],
    ),
  ),
  scenarioIdentity: 'account-menu-button-triggers',
);

@Preview(
  name: 'ACP panel / login + actions',
  group: components,
  size: Size(720, 700),
)
Widget accountAcpPanelPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(20),
    child: AcpAccountPanel(
      value: AccountPreviewFixtures.acp,
      onAction: (action) => record('ACP intent: ${action.name}'),
      onLoginMethodChanged: (id) => record('login method: $id'),
    ),
  ),
  scenarioIdentity: 'acp-panel',
);

@Preview(
  name: 'Model details / three tabs / synthetic readout',
  group: 'Accounts · Model details',
  size: Size(960, 1100),
)
Widget accountModelDetailsPagePreview() => accountPreviewHost(
  (record) => _ModelDetailsPreviewScenario(
    value: AccountPreviewFixtures.model,
    accountName: 'DeepSeek · 合成账号',
    iconKey: 'deepseek',
    record: record,
  ),
  scenarioIdentity: 'model-details-page',
);

@Preview(
  name: 'Model details / three tabs / narrow / text 1.0',
  group: 'Accounts · Model details',
  size: Size(408, 1000),
)
Widget accountModelDetailsNarrowDefaultScalePreview() => accountPreviewHost(
  (record) => _ModelDetailsPreviewScenario(
    value: AccountPreviewFixtures.model,
    accountName: 'DeepSeek · 合成账号',
    iconKey: 'deepseek',
    initialModelTab: AccountModelTab.specifications,
    record: record,
  ),
  scenarioIdentity: 'model-details-narrow-default-scale',
);

@Preview(
  name: 'Model details / evaluations tab / narrow',
  group: 'Accounts · Model details',
  size: Size(408, 1000),
)
Widget accountModelDetailsEvaluationsPreview() => accountPreviewHost(
  (record) => _ModelDetailsPreviewScenario(
    value: AccountPreviewFixtures.model,
    accountName: '长名称 · 合成账号',
    iconKey: 'unknown-brand',
    initialModelTab: AccountModelTab.evaluations,
    record: record,
  ),
  scenarioIdentity: 'model-details-evaluations-narrow',
  textScale: 1.3,
);

@Preview(
  name: 'Model details / filter-empty evaluations / narrow',
  group: 'Accounts · Model details',
  size: Size(408, 1000),
)
Widget accountModelDetailsFilterEmptyPreview() => accountPreviewHost(
  (record) => _ModelDetailsPreviewScenario(
    value: AccountPreviewFixtures.model.copyWith(
      evaluationSummary: AccountPreviewFixtures.filteredEmptyEvaluationSummary,
    ),
    accountName: 'DeepSeek · 合成账号',
    iconKey: 'deepseek',
    initialModelTab: AccountModelTab.evaluations,
    record: record,
  ),
  scenarioIdentity: 'model-details-filter-empty-narrow',
  textScale: 1.3,
);

@Preview(
  name: 'Model details / long summary and errors / narrow',
  group: 'Accounts · Model details',
  size: Size(408, 1000),
)
Widget accountModelDetailsLongContentPreview() => accountPreviewHost(
  (record) => _ModelDetailsPreviewScenario(
    value: AccountPreviewFixtures.model.copyWith(
      name: '用于跨区域部署与长上下文评估的合成模型名称',
      summary: '合成模型摘要：保留能力说明、上下文范围、连接特征和评价来源等多段描述，供窄屏观察换行与滚动。',
      error: '合成目录错误：在线模型目录刷新失败，保留最近一次可用数据并展示完整说明。',
      readoutError: '合成资料读取错误：性能与评价资料暂时不可用，可通过页面操作重试。',
    ),
    accountName: '用于跨区域部署的超长合成账号名称 · 仅预览',
    iconKey: 'unknown-brand',
    initialModelTab: AccountModelTab.specifications,
    record: record,
  ),
  scenarioIdentity: 'model-details-long-content-narrow',
  textScale: 1.3,
);

class _ModelDetailsPreviewScenario extends StatefulWidget {
  const _ModelDetailsPreviewScenario({
    required this.value,
    required this.accountName,
    required this.initialModelTab,
    required this.record,
    this.iconKey,
  });

  final AccountModelPresentation value;
  final String accountName;
  final String? iconKey;
  final AccountModelTab initialModelTab;
  final ValueChanged<String> record;

  @override
  State<_ModelDetailsPreviewScenario> createState() =>
      _ModelDetailsPreviewScenarioState();
}

class _ModelDetailsPreviewScenarioState
    extends State<_ModelDetailsPreviewScenario> {
  late AccountModelTab _tab = widget.initialModelTab;

  @override
  Widget build(BuildContext context) => AccountModelDetailsView(
    value: widget.value,
    accountName: widget.accountName,
    iconKey: widget.iconKey,
    tab: _tab,
    onTabChanged: (tab) {
      setState(() => _tab = tab);
      widget.record('model tab: ${tab.name}');
    },
    onBack: () => widget.record('back'),
    onRetry: () => widget.record('retry readout'),
    onEnabledChanged: (enabled) => widget.record('model enabled: $enabled'),
    onFilterChanged: (filter) => widget.record('filter: ${filter.sort.name}'),
  );
}

@Preview(
  name: 'Editor scaffold / dirty / production page geometry',
  group: components,
  size: Size(960, 900),
)
Widget accountEditorScaffoldPreview() => accountPreviewHost(
  (record) => AccountEditorScaffold(
    title: '合成账号编辑',
    scrollKey: const ValueKey('preview-account-editor-scroll'),
    dirty: true,
    children: [
      AccountSection(
        title: '连接与计费',
        child: AccountNativeConnectionFields(
          value: AccountPreviewFixtures.editor,
          onChanged: (field, raw) => record('${field.name}: $raw'),
          billingControl: AccountBillingControl(
            value: AccountPreviewFixtures.billing,
            layout: AccountBillingControlLayout.field,
            onChanged: (billing) => record('billing: ${billing.name}'),
            onReset: () => record('restore automatic'),
          ),
        ),
      ),
      AccountEditorFooter(
        saving: false,
        canSave: true,
        onSave: () => record('save intent only'),
        onCancel: () => record('cancel intent'),
      ),
    ],
  ),
  scenarioIdentity: 'editor-scaffold-dirty',
);

@Preview(
  name: 'Billing control / editor field layout',
  group: components,
  size: Size(408, 300),
)
Widget accountBillingControlFieldPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(16),
    child: AccountBillingControl(
      value: AccountPreviewFixtures.billing.copyWith(
        billingKindOverride: AccountBilling.subscription,
      ),
      layout: AccountBillingControlLayout.field,
      onChanged: (billing) => record('billing intent: ${billing.name}'),
      onReset: () => record('restore automatic intent'),
    ),
  ),
  scenarioIdentity: 'billing-control-field',
);

@Preview(
  name: 'Usage / health suppressed by caller',
  group: components,
  size: Size(720, 360),
)
Widget accountUsageWithoutHealthPreview() => accountPreviewHost(
  (record) => Padding(
    padding: const EdgeInsets.all(20),
    child: AccountUsageView(
      value: AccountPreviewFixtures.balance.copyWith(
        balanceHealth: AccountBalanceHealth.insufficient,
      ),
      showHealth: false,
      onRetry: () => record('retry locally'),
    ),
  ),
  scenarioIdentity: 'usage-health-hidden',
);

@Preview(
  name: 'Identity / caller-provided badge',
  group: components,
  size: Size(720, 180),
)
Widget accountIdentityWithBadgePreview() => accountPreviewHost(
  (_) => const Padding(
    padding: EdgeInsets.all(20),
    child: AccountIdentity(
      name: '合成 Native 账号',
      iconKey: 'deepseek',
      badge: Chip(label: Text('目录未知'), visualDensity: VisualDensity.compact),
    ),
  ),
  scenarioIdentity: 'identity-badge',
);

@Preview(
  name: 'Unsaved dialog / unknown save / discard warning',
  group: components,
  size: Size(640, 460),
)
Widget accountUnsavedUnknownOutcomePreview() => accountPreviewHost(
  (record) => Center(
    child: AccountUnsavedChangesDialog(
      canSave: false,
      canDiscard: true,
      warning: '保存结果尚未确认。放弃只会清除本地编辑，不会撤销已发送的保存；稍后状态仍可能更新。',
      onChoice: (choice) => record('local choice only: ${choice.name}'),
    ),
  ),
  scenarioIdentity: 'unsaved-unknown-outcome',
);

@Preview(
  name: 'Native editor / focus synthetic manual model ID',
  group: 'Accounts · Editor',
  size: Size(960, 1100),
)
Widget accountNativeEditorFocusedManualModelPreview() =>
    accountNativeEditorPreviewHost(
      AccountPreviewFixtures.editor,
      focusManualModelEditorKey:
          AccountPreviewFixtures.editor.manualModels.first.editorKey,
      focusManualModelId: true,
    );

@Preview(
  name: 'Native editor / create / set default on create',
  group: 'Accounts · Editor',
  size: Size(960, 1100),
)
Widget accountNativeEditorSetDefaultOnCreatePreview() =>
    accountNativeEditorPreviewHost(
      AccountPreviewFixtures.editor.copyWith(
        accountKey: null,
        hasStoredCredential: false,
        canSave: false,
        setDefaultOnCreate: false,
        showSetDefaultOnCreate: true,
      ),
    );

@Preview(
  name: 'Native editor / usage capability not provided',
  group: 'Accounts · Editor',
  size: Size(408, 1000),
)
Widget accountNativeEditorUsageUnknownPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editorWithUsageUnknownTemplate,
      textScale: 1.3,
    );
