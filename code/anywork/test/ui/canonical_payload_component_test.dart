import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/completion_run_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/src/lifecycle/close_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';

const _payloadRef = ContentRef(
  databaseId: 'db',
  target: ItemPayloadTarget(itemId: 'completion'),
);
const _bodyRef = ContentRef(
  databaseId: 'db',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'completion'),
    key: 'body',
  ),
);

ChatAtom _atom(
  PayloadData payload, {
  String id = 'atom',
  ChatSourceId source = const InputChatSource(inputId: 'input'),
  ChatAtomKind kind = ChatAtomKind.input,
}) => ChatAtom(
  id: id,
  completionItemId: 'completion',
  completionSeq: 7,
  source: source,
  sourceOrder: 1,
  kind: kind,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: kind == ChatAtomKind.input
      ? const [ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef)]
      : const [],
  payload: payload,
);

ChatAtom _head({ChatAtomKind kind = ChatAtomKind.input}) => _atom(
  const DeferredPayload(reference: _payloadRef, byteLength: 1000),
  kind: kind,
);

CompletedEntry _entry(ChatAtom atom) => CompletedEntry(
  recordId: 'completion',
  completionSeq: 7,
  run: null,
  mainPresentation: MainPresentation.single,
  atom: atom,
);

InlinePayload _envelope(
  String type,
  Map<String, Object?> data,
  List<Map<String, Object?>> bodies,
) => InlinePayload(
  bytes: utf8.encode(
    jsonEncode({
      'contract': 'anywork.chat/1',
      'type': type,
      'data': data,
      'bodies': bodies,
    }),
  ),
);

InlinePayload _input() => _envelope(
  'text',
  {
    'channel': 'user',
    'attachments': [
      {
        'id': 'attachment',
        'modality': 'file',
        'mediaType': 'text/plain',
        'byteSize': 18,
        'filename': '原附件.txt',
      },
    ],
  },
  [
    {
      'key': 'body',
      'byteLength': 18,
      'reference': {
        'databaseId': 'db',
        'target': {
          'kind': 'body',
          'owner': {'kind': 'item', 'itemId': 'completion'},
          'key': 'body',
        },
      },
    },
  ],
);

InlinePayload _tool() => _envelope(
  'tool',
  {
    'invocation': {
      'toolCallId': 'call',
      'name': 'canonical-exec',
      'presentationContract': 'generic@1',
    },
    'state': {
      'kind': 'succeeded',
      'completedAt': 12,
      'output': {'exitCode': 0, 'attachments': []},
    },
  },
  [
    inlineBody('tool.arguments', 'public args'),
    inlineBody('tool.result', '真实工具结果'),
  ],
);

void main() {
  testWidgets(
    'Main Deferred Single restores body and attachments without changing the block or atom',
    (tester) async {
      final h = _Harness();
      final head = _head();
      final original = _entry(_atom(_input()));
      final gate = Completer<CompletedEntry>();
      h.content.read = (_, _) => gate.future;
      await h.controls.adapter.applyTimeline(
        displayBatch([
          DisplayBlock(
            id: 'single-block-not-record',
            historyPos: 1,
            body: SingleDisplayBlock(atom: head, completionId: 'completion'),
          ),
        ]),
      );
      final message = h.controls.controller.messages.single;
      final presentation = chatItemPresentationOf(message)!;
      await tester.pumpWidget(h.host());
      await tester.pump();
      expect(h.content.requests.single.$1, 'completion');
      expect(h.content.requests.single.$2.maxItems, 1);
      expect(h.content.requests.single.$2.maxBytes, 64 * 1024);
      gate.complete(original);
      await tester.pumpAndSettle();
      expect(find.text('原附件.txt'), findsOneWidget);
      // The body remains a separate bounded content read, not part of metadata IO.
      await tester.tap(find.text('body · 18 字节'));
      await tester.pumpAndSettle();
      expect(find.text('原始输入正文'), findsOneWidget);
      expect(h.content.bodyRequests.single.$1, _bodyRef);
      expect(h.content.bodyRequests.single.$2.maxBytes, 64 * 1024);
      final rendered = tester
          .widget<ChatItemView>(find.byType(ChatItemView))
          .item;
      expect(rendered.id, 'single-block-not-record');
      expect(rendered.atom, same(head));
      expect(rendered.displayUnit, same(presentation.displayUnit));
      expect(h.controls.controller.messages.single, same(message));
      expect(
        find.byKey(StudioDriverKeys.timelineRow('single-block-not-record')),
        findsOneWidget,
      );
      await tester.pumpWidget(h.host());
      await tester.pumpAndSettle();
      expect(
        h.content.requests,
        hasLength(1),
        reason: 'stable rebuild does not reread canonical metadata',
      );
      await h.close(tester);
    },
  );

  testWidgets(
    'collapsed Work reads no originals; expanded Deferred member restores the real tool renderer',
    (tester) async {
      final h = _Harness();
      final head = _head(kind: ChatAtomKind.toolCall);
      final canonical = _entry(_atom(_tool(), kind: ChatAtomKind.toolCall));
      h.content.read = (_, _) async => canonical;
      final intent = TimelineExpansionIntent();
      final members = _Members(head);
      intent.openDisplayMembers = (_, _, _) async => members;
      h.groupIntent = intent;
      await h.controls.adapter.applyTimeline(
        displayBatch([displayWork('work', 1)]),
      );
      await tester.pumpWidget(h.host());
      await tester.pumpAndSettle();
      expect(members.calls, 0);
      expect(h.content.requests, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('completion-run-header:work')),
      );
      await tester.pumpAndSettle();
      expect(h.content.requests, hasLength(1));
      expect(find.text('canonical-exec 已完成'), findsOneWidget);
      final details = tester.widget<TimelineToolDetails>(
        find.byType(TimelineToolDetails),
      );
      expect(details.item.statusString, 'succeeded');
      expect(details.item.output, '真实工具结果');
      final member = tester
          .widget<ChatItemView>(find.byType(ChatItemView).last)
          .item;
      expect(member.atom, same(head));
      expect(member.id, 'atom');
      await tester.tap(find.text('canonical-exec 已完成'));
      await tester.pumpAndSettle();
      expect(find.text('真实工具结果'), findsOneWidget);
      await tester.pumpWidget(h.host());
      await tester.pumpAndSettle();
      expect(h.content.requests, hasLength(1));
      await h.close(tester);
      intent.retire();
    },
  );

  for (final action in ['fold', 'replace', 'leave']) {
    testWidgets(
      '$action revokes a pending member canonical read before its late result',
      (tester) async {
        final h = _Harness();
        final gate = Completer<CompletedEntry>();
        h.content.read = (_, _) => gate.future;
        final intent = TimelineExpansionIntent()..expanded = true;
        intent.openDisplayMembers = (_, _, _) async =>
            _Members(_head(kind: ChatAtomKind.toolCall));
        h.groupIntent = intent;
        await h.controls.adapter.applyTimeline(
          displayBatch([displayWork('work', 1)]),
        );
        await tester.pumpWidget(h.host());
        await tester.pumpAndSettle();
        final scope = h.content.scopes.single;
        if (action == 'fold') {
          await tester.tap(
            find.byKey(const ValueKey('completion-run-header:work')),
          );
        } else if (action == 'replace') {
          intent.replaceBody();
        } else {
          h.retirement.value = true;
          await tester.pumpWidget(const SizedBox());
        }
        expect(scope.active, isFalse, reason: 'retirement is synchronous');
        gate.complete(_entry(_atom(_tool(), kind: ChatAtomKind.toolCall)));
        // Do not let a new replacement read obscure the old read's assertion.
        h.retirement.value = true;
        await tester.pumpAndSettle();
        expect(find.byType(TimelineToolDetails), findsNothing);
        expect(scope.closed, isTrue);
        expect(tester.takeException(), isNull);
        await h.close(tester);
        intent.retire();
      },
    );
  }

  for (final failure in [
    'deferred',
    'record',
    'atom',
    'source',
    'sequence',
    'malformed',
  ]) {
    testWidgets(
      'canonical $failure limitation is explicit and never exposes raw JSON',
      (tester) async {
        final h = _Harness();
        var value = _entry(_atom(_tool()));
        if (failure == 'deferred') value = _entry(_head());
        if (failure == 'atom') value = _entry(_atom(_tool(), id: 'other'));
        if (failure == 'source') {
          value = _entry(
            _atom(_tool(), source: const InputChatSource(inputId: 'other')),
          );
        }
        if (failure == 'record' || failure == 'sequence') {
          value = CompletedEntry(
            recordId: failure == 'record' ? 'other' : 'completion',
            completionSeq: failure == 'sequence' ? 8 : 7,
            run: null,
            mainPresentation: MainPresentation.single,
            atom: value.atom,
          );
        }
        if (failure == 'malformed') {
          value = _entry(
            _atom(InlinePayload(bytes: utf8.encode('{"PRIVATE":'))),
          );
        }
        h.content.read = (_, _) async => value;
        await h.controls.adapter.applyTimeline(
          displayBatch([
            DisplayBlock(
              id: 'block',
              historyPos: 1,
              body: SingleDisplayBlock(
                atom: _head(),
                completionId: 'completion',
              ),
            ),
          ]),
        );
        await tester.pumpWidget(h.host());
        await tester.pumpAndSettle();
        expect(
          find.text(switch (failure) {
            'deferred' => '完成内容超出单次读取预算（64 KiB）',
            'malformed' => '完成内容格式无法解析',
            _ => '完成内容身份不一致',
          }),
          findsOneWidget,
        );
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.byType(TimelineToolDetails), findsNothing);
        expect(h.content.requests, hasLength(1));
        await h.close(tester);
      },
    );
  }
}

class _Content extends Fake implements ConversationContent {
  late Future<CompletedEntry> Function(String, ReadDemand) read;
  final requests = <(String, ReadDemand)>[];
  final bodyRequests = <(ContentRef, ContentRange)>[];
  final scopes = <_Scope>[];
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope(this);
    scopes.add(scope);
    return scope;
  }
}

class _Scope extends Fake implements ConversationQueryScope {
  _Scope(this.content);
  final _Content content;
  bool active = true;
  bool closed = false;
  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) {
    content.requests.add((recordId, demand));
    return content.read(recordId, demand);
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) async {
    content.bodyRequests.add((reference, range));
    return ContentWindow(
      offset: 0,
      bytes: utf8.encode('原始输入正文'),
      generation: 'sealed',
      availableThrough: 18,
      sealed: true,
    );
  }

  @override
  void retire() => active = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closed = true;
    return CloseReport();
  }
}

class _Members implements DisplayMembers {
  _Members(this.atom);
  final ChatAtom atom;
  final stopped = Completer<DisplayMemberPage?>();
  int calls = 0;
  @override
  Future<DisplayMemberPage?> next() async {
    if (calls++ > 0) return stopped.future;
    return DisplayMemberPage(
      block: const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
      revision: 1,
      sealed: true,
      entries: [
        DisplayMemberHead(
          memberKey: 'member-key',
          memberOrder: 1,
          atom: atom,
          completionId: 'completion',
        ),
      ],
    );
  }

  @override
  void requestClose() {
    if (!stopped.isCompleted) stopped.complete(null);
  }

  @override
  Future<void> close() async => requestClose();
}

class _Harness {
  final controls = _Controls();
  final content = _Content();
  final retirement = ValueNotifier(false);
  set groupIntent(TimelineExpansionIntent value) =>
      controls.groupIntent = value;
  Widget host() => MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TimelineView(
        threadId: 'thread',
        controls: controls,
        view: const TimelineSessionViewState(
          threadId: 'thread',
          generation: 1,
          mode: TimelineDisplayMode.history,
          connection: TimelineConnectionPhase.ready,
        ),
        onLoadOlder: () async {},
        onRetryOlder: () async {},
        onReturnLive: () async {},
        onEnterHistory: () {},
        onRetryConnection: () {},
        onLink: (_) {},
        isSafeLink: (_) => false,
        remoteImageBuilder: (_, _) => const SizedBox(),
        canonicalPresentationBuilder: (item, render) =>
            TimelineCanonicalPayloadConnector(
              item: item,
              content: content,
              retirement: retirement,
              isActive: () => !retirement.value,
              render: render,
            ),
        contentRangeBuilder: (id, key, label, reference, witness) =>
            TimelineContentRangeConnector(
              itemId: id,
              contentKey: key,
              label: label,
              reference: reference,
              witness: witness,
              readContent: (reference, range) => content
                  .openScope(generation: 1)
                  .readContent(reference: reference, range: range),
            ),
        attachmentBuilder: (item) => TimelineAttachmentsConnector(
          item: item,
          resources: controls.images,
          readAttachment: null,
          isActive: () => !retirement.value,
        ),
        groupMembersBuilder: (unit) {
          return CompletionRunConnector(
            unit: unit,
            threadId: 'thread',
            content: content,
            images: controls.images,
          );
        },
      ),
    ),
  );
  Future<void> close(WidgetTester tester) async {
    retirement.value = true;
    await tester.pumpWidget(const SizedBox());
    await controls.dispose();
    retirement.dispose();
  }
}

class _Controls implements TimelineUiControllers {
  @override
  final InMemoryChatController controller = InMemoryChatController();
  @override
  final scrollController = ScrollController();
  final images = TimelineImageResources(threadId: 'thread');
  TimelineExpansionIntent? groupIntent;
  late final adapter = TimelineMessageController(
    controller,
    generation: 1,
    expansionForBlock: (_) => groupIntent ??= TimelineExpansionIntent(),
  );
  @override
  Key get chatKey => const ValueKey('canonical-test');
  @override
  bool get isRetired => false;
  @override
  void bind() {}
  @override
  Future<void> unbind() async {}
  Future<void> dispose() async {
    groupIntent?.retire();
    adapter.dispose();
    images.release();
    controller.dispose();
    scrollController.dispose();
  }
}
