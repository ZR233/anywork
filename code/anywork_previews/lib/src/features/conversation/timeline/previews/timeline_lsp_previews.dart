import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';

import 'timeline_preview_fixtures.dart';

Widget _lspPreviewHost(
  Widget child, {
  double maxWidth = StudioLayout.conversationWidth,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  ),
);

Widget _lspPreviewMarkdown(String id, String text) => TimelineMarkdown(
  id: id,
  text: text,
  onLink: (_) {},
  isSafeLink: (url) => Uri.tryParse(url)?.scheme == 'https',
  imageBuilder: (_, _) => const SizedBox.shrink(),
);

ChatItemPresentation _lspToolItem({
  required String id,
  required String name,
  required String contract,
  required Map<String, Object?> arguments,
  Object? result,
  String status = 'succeeded',
  String? error,
}) {
  final argsText = jsonEncode(arguments);
  final resultText = switch (result) {
    null => null,
    final String raw => raw,
    final Object json => jsonEncode(json),
  };
  return TimelinePreviewFixtures.item(
    id,
    'tool',
    {
      'invocation': {
        'toolCallId': '$id-call',
        'name': name,
        'presentationContract': contract,
      },
      'state': {
        'kind': status,
        if (status == 'succeeded') ...{
          'completedAt': 1735689610,
          'output': {'attachments': <Object>[]},
        },
        if (status == 'failed') ...{
          'failedAt': 1735689610,
          if (error != null)
            'failure': {'kind': 'executionFailed', 'message': error},
        },
      },
    },
    bodies: [
      TimelinePreviewFixtures.body('tool.arguments', argsText),
      if (resultText != null)
        TimelinePreviewFixtures.body('tool.result', resultText),
    ],
  );
}

Widget _lspCard(ChatItemPresentation item, {bool expanded = true}) =>
    ChatItemView(
      key: ValueKey(item.id),
      item: item,
      initiallyExpanded: expanded,
      bodyBuilder: _lspPreviewMarkdown,
    );

final _hoverQueryItem = _lspToolItem(
  id: 'preview-lsp-hover',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'hover',
    'filePath': 'code/pl-lsp/src/runtime/query.rs',
    'line': 42,
    'character': 12,
  },
  result: const {
    'success': true,
    'operation': 'hover',
    'serverId': 'rust-analyzer',
    'resultCount': 1,
    'result':
        '```rust\n'
        'pub async fn execute_query(\n'
        '    &self,\n'
        '    request: LspQueryRequest,\n'
        ') -> Result<LspQueryOutput, LspError>\n'
        '```\n\n'
        '在当前工作区语言服务器会话上执行有界语义查询，自动复用已初始化的客户端连接并统一转换相对路径与行列坐标。',
  },
);

final _referencesQueryItem = _lspToolItem(
  id: 'preview-lsp-references',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'findReferences',
    'filePath': 'code/pl-lsp/src/client/mod.rs',
    'line': 18,
    'character': 16,
  },
  result: const {
    'success': true,
    'operation': 'findReferences',
    'serverId': 'rust-analyzer',
    'resultCount': 5,
    'fileCount': 3,
    'result':
        'Found 5 references across 3 files:\n'
        'code/pl-lsp/src/client/mod.rs:18:16\n'
        'code/pl-lsp/src/client/mod.rs:94:22\n'
        'code/pl-lsp/src/runtime/query.rs:42:12\n'
        'code/pl-lsp/src/runtime/query.rs:108:9\n'
        'code/pl-tool/src/lsp/thread.rs:201:18',
  },
);

final _collapsedDefinitionItem = _lspToolItem(
  id: 'preview-lsp-definition-collapsed',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'goToDefinition',
    'filePath': 'code/pl-lsp/src/runtime/registry.rs',
    'line': 64,
    'character': 8,
  },
  result: const {
    'success': true,
    'operation': 'goToDefinition',
    'serverId': 'rust-analyzer',
    'resultCount': 1,
    'fileCount': 1,
    'result': 'Found 1 definition:\ncode/pl-lsp/src/runtime/registry.rs:64:8',
  },
);

final _documentSymbolsItem = _lspToolItem(
  id: 'preview-lsp-doc-symbols',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'documentSymbol',
    'filePath': 'code/pl-lsp/src/runtime/state.rs',
  },
  result: const {
    'success': true,
    'operation': 'documentSymbol',
    'serverId': 'rust-analyzer',
    'resultCount': 8,
    'result':
        'runtime kind=2\n'
        '  LspServerPhase kind=10\n'
        '    Ready kind=22\n'
        '    Failed kind=22\n'
        '  LspWorkspaceRegistry kind=23\n'
        '    servers kind=8\n'
        '    snapshot kind=6\n'
        '    probe_all kind=12',
  },
);

final _workspaceSymbolsItem = _lspToolItem(
  id: 'preview-lsp-workspace-symbols',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'workspaceSymbol',
    'query': 'LspRegistry',
    'maxResults': 20,
  },
  result: const {
    'success': true,
    'operation': 'workspaceSymbol',
    'serverId': 'rust-analyzer',
    'resultCount': 7,
    'fileCount': 3,
    'result':
        'LspWorkspaceRegistry kind=23 code/pl-lsp/src/runtime/registry.rs\n'
        'CapabilityReader kind=11 code/tools/lsp/src/support/mod.rs\n'
        'register_lsp_tools kind=12 code/pl-tool/src/lsp/thread.rs\n'
        '... 4 more symbols omitted',
  },
);

final _incomingCallsItem = _lspToolItem(
  id: 'preview-lsp-incoming-calls',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'incomingCalls',
    'filePath': 'code/pl-lsp/src/runtime/query.rs',
    'line': 42,
    'character': 12,
  },
  result: const {
    'success': true,
    'operation': 'incomingCalls',
    'serverId': 'rust-analyzer',
    'resultCount': 2,
    'fileCount': 2,
    'result':
        'LspQueryTool::execute code/tools/lsp/src/query/mod.rs\n'
        'ThreadLspPort::query code/pl-tool/src/lsp/thread.rs',
  },
);

final _diagnosticsIssuesItem = _lspToolItem(
  id: 'preview-lsp-diagnostics-issues',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'rust',
    'operation': 'diagnostics',
    'filePath': 'code/pl-lsp/src/client/transport.rs',
    'maxResults': 10,
  },
  result: const {
    'success': true,
    'operation': 'diagnostics',
    'serverId': 'rust-analyzer',
    'resultCount': 2,
    'fileCount': 1,
    'result':
        'code/pl-lsp/src/client/transport.rs:87:9 unused `Result` that must be used [unused_must_use] (rustc)\n'
        'code/pl-lsp/src/client/transport.rs:142:21 this expression borrows a value the compiler would automatically borrow [clippy::needless_borrow] (clippy)',
  },
);

final _diagnosticsCleanItem = _lspToolItem(
  id: 'preview-lsp-diagnostics-clean',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  arguments: const {
    'languageId': 'dart',
    'operation': 'diagnostics',
    'filePath': 'code/anywork/lib/main.dart',
  },
  result: const {
    'success': true,
    'operation': 'diagnostics',
    'serverId': 'dart-analysis-server',
    'resultCount': 0,
    'fileCount': 0,
    'result': 'No diagnostics.',
  },
);

ChatItemPresentation get _failedQueryItem => _lspToolItem(
  id: 'preview-lsp-failed',
  name: 'lsp_query',
  contract: 'builtin.lsp_query@1',
  status: 'failed',
  error: 'language server `pyright` is unavailable: missing executable in PATH',
  arguments: const {
    'languageId': 'python',
    'operation': 'goToImplementation',
    'filePath': 'scripts/verify_pipeline.py',
    'line': 29,
    'character': 10,
  },
);

final _capabilitiesItem = _lspToolItem(
  id: 'preview-lsp-capabilities',
  name: 'lsp_capabilities',
  contract: 'builtin.lsp_capabilities@1',
  arguments: const {},
  result: const {
    'servers': [
      {
        'id': 'rust-analyzer',
        'displayName': 'Rust Analyzer',
        'languageIds': ['rust'],
        'operations': [
          'goToDefinition',
          'goToImplementation',
          'findReferences',
          'hover',
          'documentSymbol',
          'workspaceSymbol',
          'prepareCallHierarchy',
          'incomingCalls',
          'outgoingCalls',
          'diagnostics',
        ],
        'availability': 'available',
        'ready': true,
      },
      {
        'id': 'dart',
        'displayName': 'Dart Analysis Server',
        'languageIds': ['dart'],
        'operations': [
          'goToDefinition',
          'findReferences',
          'hover',
          'documentSymbol',
          'workspaceSymbol',
          'diagnostics',
        ],
        'availability': 'available',
        'ready': true,
      },
    ],
  },
);

final _statusJsonText = jsonEncode({
  'workspaceRoot': '/workspace/anywork',
  'configurationDirectory': '/workspace/anywork/.anywork/lsp',
  'servers': [
    {
      'id': 'rust-analyzer',
      'displayName': 'Rust Analyzer',
      'languageIds': ['rust'],
      'configurationPath': '/workspace/anywork/.anywork/lsp/rust-analyzer.toml',
      'phase': 'ready',
      'availability': 'available',
      'activity': 'indexing',
      'activityTitle': 'Indexing crates',
      'activityMessage': 'pl-studio-runtime (28/41)',
      'activityPercentage': 68,
    },
    {
      'id': 'dart',
      'displayName': 'Dart Analysis Server',
      'languageIds': ['dart'],
      'configurationPath': '/workspace/anywork/.anywork/lsp/dart.toml',
      'phase': 'ready',
      'availability': 'available',
      'activity': 'idle',
    },
    {
      'id': 'pyright',
      'displayName': 'Pyright',
      'languageIds': ['python'],
      'configurationPath': '/workspace/anywork/.anywork/lsp/pyright.toml',
      'phase': 'failed',
      'availability': 'missingCommand',
      'activity': 'idle',
      'lastError': "executable 'pyright-langserver' not found in PATH",
    },
  ],
});

final _statusDeclaredWindowItem = ChatItemPresentation.forUnit(
  TimelineDisplayUnit(
    block: DisplayBlock(
      id: 'preview-lsp-status-unit',
      blockOrder: 1,
      body: SingleDisplayBlock(
        visibility: SingleVisibility.content,
        record: DisplayRecord(
          atom: ChatAtom(
            id: 'preview-lsp-status',
            completionItemId: 'preview-lsp-status',
            source: TimelinePreviewFixtures.groupSource,
            sourceOrder: 1,
            kind: ChatAtomKind.toolCall,
            delivery: ChatDeliveryKind.foreground,
            tool: const ChatToolIdentity(
              callId: 'preview-lsp-status-call',
              name: 'lsp_status',
            ),
            lifecycle: const TerminalChatAtom(
              started: ChatFactPosition(effectSeq: 1, suborder: 0),
              ended: ChatFactPosition(effectSeq: 2, suborder: 0),
              outcome: ChatTerminalOutcome.completed,
            ),
            contents: const [
              ChatAtomContent(
                role: ChatContentRole.toolArguments,
                reference: ContentRef(
                  databaseId: 'preview',
                  target: BodyContentTarget(
                    owner: ItemContentOwner(itemId: 'preview-lsp-status'),
                    key: 'tool.arguments',
                  ),
                ),
              ),
              ChatAtomContent(
                role: ChatContentRole.toolOutput,
                reference: ContentRef(
                  databaseId: 'preview',
                  target: BodyContentTarget(
                    owner: ItemContentOwner(itemId: 'preview-lsp-status'),
                    key: 'tool.result',
                  ),
                ),
              ),
            ],
            payload: InlinePayload(
              bytes: utf8.encode(
                jsonEncode({
                  'contract': 'anywork.chat/1',
                  'type': 'tool',
                  'data': {
                    'invocation': {
                      'toolCallId': 'preview-lsp-status-call',
                      'name': 'lsp_status',
                      'presentationContract': 'builtin.lsp_status@1',
                    },
                    'state': {
                      'kind': 'succeeded',
                      'completedAt': 1735689612,
                      'output': {'attachments': <Object>[]},
                    },
                  },
                  'bodies': [
                    TimelinePreviewFixtures.body('tool.arguments', '{}'),
                    TimelinePreviewFixtures.body(
                      'tool.result',
                      _statusJsonText,
                    ),
                  ],
                  'sealedAt': 1735689612,
                }),
              ),
            ),
          ),
          contentSource: CompletedOriginal(completionId: 'preview-lsp-status'),
        ),
      ),
    ),
  ),
);

Widget _declaredStatusCard() {
  final bytes = utf8.encode(_statusJsonText);
  return ChatItemView(
    key: const ValueKey('preview-lsp-status-declared'),
    item: _statusDeclaredWindowItem,
    initiallyExpanded: true,
    bodyBuilder: _lspPreviewMarkdown,
    contentRangeBuilder: (id, key, label, reference, witness) =>
        TimelineContentRangeConnector(
          itemId: id,
          contentKey: key,
          label: label,
          reference: reference,
          witness: witness,
          readContent: (_, range) async => ContentWindow(
            offset: range.offset,
            bytes: bytes.sublist(
              range.offset,
              (range.offset + range.maxBytes).clamp(0, bytes.length),
            ),
            generation: 'preview',
            availableThrough: bytes.length,
            sealed: true,
          ),
        ),
  );
}

@Preview(
  name: 'LSP 查询 / 悬停说明与引用定位',
  group: 'Timeline · LSP 工具',
  size: Size(820, 720),
)
Widget timelineLspHoverAndReferencesPreview() => _lspPreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lspCard(_hoverQueryItem),
        const SizedBox(height: 12),
        _lspCard(_referencesQueryItem),
        const SizedBox(height: 12),
        _lspCard(_collapsedDefinitionItem, expanded: false),
      ],
    ),
  ),
);

@Preview(
  name: 'LSP 查询 / 符号大纲、工作区符号与调用链',
  group: 'Timeline · LSP 工具',
  size: Size(820, 860),
)
Widget timelineLspSymbolsAndCallsPreview() => _lspPreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lspCard(_documentSymbolsItem),
        const SizedBox(height: 12),
        _lspCard(_workspaceSymbolsItem),
        const SizedBox(height: 12),
        _lspCard(_incomingCallsItem),
      ],
    ),
  ),
);

@Preview(
  name: 'LSP 查询 / 代码诊断、无问题与失败态',
  group: 'Timeline · LSP 工具',
  size: Size(820, 740),
)
Widget timelineLspDiagnosticsAndFailurePreview() => _lspPreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lspCard(_diagnosticsIssuesItem),
        const SizedBox(height: 12),
        _lspCard(_diagnosticsCleanItem),
        const SizedBox(height: 12),
        _lspCard(_failedQueryItem),
      ],
    ),
  ),
);

@Preview(
  name: 'LSP 服务 / 语言服务能力与运行状态',
  group: 'Timeline · LSP 工具',
  size: Size(820, 780),
)
Widget timelineLspCapabilitiesAndStatusPreview() => _lspPreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lspCard(_capabilitiesItem),
        const SizedBox(height: 12),
        _declaredStatusCard(),
      ],
    ),
  ),
);

@Preview(
  name: 'LSP 工具 / 窄窗 360px 与 160% 大字号',
  group: 'Timeline · LSP 工具',
  size: Size(360, 960),
)
Widget timelineLspNarrowLargeTextPreview() => _lspPreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lspCard(_referencesQueryItem),
        const SizedBox(height: 12),
        _declaredStatusCard(),
      ],
    ),
  ),
  maxWidth: 360,
  textScale: 1.6,
);
