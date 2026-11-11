import 'package:anywork/src/infrastructure/frb/studio_acp_business_mapper.dart';
import 'package:anywork/src/rust/api/studio/types/acp.dart' as auth;
import 'package:anywork/src/rust/api/studio/types/acp_business.dart' as b;
import 'package:anywork/src/rust/api/studio/types/acp_business/content.dart'
    as c;
import 'package:anywork/src/rust/api/studio/types/acp_business/notification.dart'
    as n;
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
final minI64 = -(BigInt.one << 63);
final target = b.BridgeAcpSessionTarget(
  sessionId: 'product-session',
  agentId: 'agent',
  threadId: 'thread',
  instance: maxU64,
);
final run = b.BridgeAcpRunId(
  instance: maxU64 - BigInt.one,
  sequence: maxU64 - BigInt.two,
);
const meta = <String, b.BridgeAcpJsonValue>{
  'key': b.BridgeAcpJsonValue.string(value: 'value'),
};
const text = c.BridgeAcpContentBlock.text(text: 'hello', meta: meta);
const chunk = n.BridgeAcpContentChunk(
  content: text,
  messageId: 'message',
  meta: meta,
);
const failure = b.BridgeAcpBusinessFailure(
  kind: b.BridgeAcpBusinessFailureKind.rpc,
  rpcCode: -32001,
  message: 'remote',
  rpcData: b.BridgeAcpJsonValue.object(
    fields: {'nested': b.BridgeAcpJsonValue.null_()},
  ),
  authMethods: [
    auth.BridgeAcpAuthMethod(
      id: 'login',
      name: 'Agent login',
      description: null,
      kind: auth.BridgeAcpAuthMethodKind.agent,
    ),
  ],
);
const booleanOption = b.BridgeAcpConfigOption(
  id: b.BridgeAcpConfigId(value: 'config'),
  name: 'Boolean',
  kind: b.BridgeAcpConfigKind.boolean(currentValue: false),
  meta: meta,
);
const toolUpdate = n.BridgeAcpToolCallUpdate(
  toolCallId: 'tool',
  name: 'real-tool',
  rawInput: b.BridgeAcpJsonValue.null_(),
  content: [],
  meta: meta,
);

AcpSessionEventView event(b.BridgeAcpSessionEvent value) => (acpFrameFromFrb(
  b.BridgeAcpSessionFrame.event(event: value),
) as AcpEventFrameView).event;
AcpBusinessSnapshotView snapshot({
  List<b.BridgeAcpConfigOption>? configOptions,
}) => acpSnapshotFromFrb(
  b.BridgeAcpBusinessSnapshot(
    target: target,
    ready: true,
    closing: false,
    configPending: true,
    configOptions: configOptions,
    authMethods: const [],
  ),
);
void expectMeta(AcpJsonObject? value) =>
    expect((value!.values['key'] as AcpJsonString).value, 'value');

void main() {
  test(
    'structured JSON preserves signed/unsigned boundaries and nested values',
    () {
      final values = [
        b.BridgeAcpJsonValue.number(
          value: b.BridgeAcpJsonNumber.signed(value: minI64.toInt()),
        ),
        b.BridgeAcpJsonValue.number(
          value: b.BridgeAcpJsonNumber.unsigned(value: maxU64),
        ),
        const b.BridgeAcpJsonValue.number(
          value: b.BridgeAcpJsonNumber.float(value: 1.25),
        ),
        const b.BridgeAcpJsonValue.bool(value: false),
        const b.BridgeAcpJsonValue.string(value: 'false'),
        const b.BridgeAcpJsonValue.null_(),
      ];
      final mapped = acpJsonFromFrb(
        b.BridgeAcpJsonValue.object(
          fields: {'array': b.BridgeAcpJsonValue.array(values: values)},
        ),
      ) as AcpJsonObject;
      final array = mapped.values['array'] as AcpJsonArray;
      expect((array.values[0] as AcpJsonInteger).value, minI64);
      expect((array.values[1] as AcpJsonInteger).value, maxU64);
      expect((array.values[2] as AcpJsonDecimal).value, 1.25);
      expect((array.values[3] as AcpJsonBool).value, false);
      expect((array.values[4] as AcpJsonString).value, 'false');
      expect(array.values[5], isA<AcpJsonNull>());
      expect(
        acpJsonToFrb(mapped),
        b.BridgeAcpJsonValue.object(
          fields: {'array': b.BridgeAcpJsonValue.array(values: values)},
        ),
      );
      expect(
        () => acpJsonToFrb(AcpJsonInteger(maxU64 + BigInt.one)),
        throwsRangeError,
      );
      expect(
        () => acpJsonToFrb(AcpJsonInteger(minI64 - BigInt.one)),
        throwsRangeError,
      );
    },
  );

  test(
    'all five content blocks and both resources retain every optional field',
    () {
      const annotations = c.BridgeAcpAnnotations(
        audience: [c.BridgeAcpRole.user, c.BridgeAcpRole.assistant],
        lastModified: 'timestamp',
        priority: .75,
        meta: meta,
      );
      final values = <c.BridgeAcpContentBlock>[
        const c.BridgeAcpContentBlock.text(
          text: 'text',
          annotations: annotations,
          meta: meta,
        ),
        const c.BridgeAcpContentBlock.image(
          data: 'bytes',
          mimeType: 'image/png',
          uri: 'image://uri',
          annotations: annotations,
          meta: meta,
        ),
        const c.BridgeAcpContentBlock.audio(
          data: 'sound',
          mimeType: 'audio/wav',
          annotations: annotations,
          meta: meta,
        ),
        c.BridgeAcpContentBlock.resourceLink(
          name: 'name',
          uri: 'file://uri',
          title: 'title',
          description: 'description',
          mimeType: 'text/plain',
          size: minI64.toInt(),
          annotations: annotations,
          meta: meta,
        ),
        const c.BridgeAcpContentBlock.resource(
          resource: c.BridgeAcpEmbeddedResource.text(
            text: 'resource text',
            uri: 'text://uri',
            mimeType: 'text/plain',
            meta: meta,
          ),
          annotations: annotations,
          meta: meta,
        ),
        const c.BridgeAcpContentBlock.resource(
          resource: c.BridgeAcpEmbeddedResource.blob(
            blob: 'blob',
            uri: 'blob://uri',
            mimeType: 'binary',
            meta: meta,
          ),
          annotations: annotations,
          meta: meta,
        ),
      ];
      for (final value in values) {
        final mapped = acpContentFromFrb(value);
        expect(mapped.annotations!.audience, [
          AcpContentRoleView.user,
          AcpContentRoleView.assistant,
        ]);
        expect(mapped.annotations!.lastModified, 'timestamp');
        expect(mapped.annotations!.priority, .75);
        expectMeta(mapped.meta);
        expectMeta(mapped.annotations!.meta);
        final roundTrip = acpContentToFrb(mapped);
        // BridgeAcpAnnotations uses identity equality for its List/Map fields.
        // Check those fields structurally rather than requiring object reuse.
        expect(roundTrip.annotations!.audience, annotations.audience);
        expect(roundTrip.annotations!.lastModified, annotations.lastModified);
        expect(roundTrip.annotations!.priority, annotations.priority);
        expect(roundTrip.annotations!.meta, annotations.meta);
        expect(
          roundTrip.copyWith(annotations: null),
          value.copyWith(annotations: null),
        );
      }
      expect(
        (acpContentFromFrb(values[3]) as AcpResourceLinkView).size,
        minI64,
      );
      expect(acpContentFromFrb(text).annotations, isNull);
    },
  );

  test(
    'config null differs from empty; select string false is not boolean false',
    () {
      expect(snapshot().configOptions, isNull);
      expect(snapshot(configOptions: const []).configOptions, isEmpty);
      final select = acpConfigFromFrb(
        const b.BridgeAcpConfigOption(
          id: b.BridgeAcpConfigId(value: 'select-id'),
          name: 'Select',
          description: 'description',
          category: b.BridgeAcpConfigCategory.other(value: 'vendor-category'),
          meta: meta,
          kind: b.BridgeAcpConfigKind.select(
            currentValue: b.BridgeAcpConfigValueId(value: 'false'),
            options: b.BridgeAcpSelectOptions.grouped(
              groups: [
                b.BridgeAcpSelectGroup(
                  group: 'group-id',
                  name: 'Group',
                  options: [
                    b.BridgeAcpSelectOption(
                      value: b.BridgeAcpConfigValueId(value: 'false'),
                      name: 'False label',
                      description: 'false description',
                      meta: meta,
                    ),
                  ],
                  meta: meta,
                ),
              ],
            ),
          ),
        ),
      );
      expect(select.id.value, 'select-id');
      expect(select.description, 'description');
      expect(select.category!.other, 'vendor-category');
      expectMeta(select.meta);
      final kind = select.kind as AcpSelectConfigView;
      expect(kind.currentValue.value, 'false');
      final group = (kind.options as AcpGroupedOptionsView).groups.single;
      expect(group.group.value, 'group-id');
      expect(group.name, 'Group');
      expectMeta(group.meta);
      expect(group.options.single.value.value, 'false');
      expect(group.options.single.description, 'false description');
      expectMeta(group.options.single.meta);
      expect(
        (acpConfigFromFrb(booleanOption).kind as AcpBooleanConfigView)
            .currentValue,
        false,
      );
      expect(
        acpConfigValueToFrb(const AcpBooleanConfigValueView(false)),
        const b.BridgeAcpConfigValue.boolean(value: false),
      );
      expect(
        acpConfigValueToFrb(
          const AcpSelectConfigValueView(AcpConfigValueId('false')),
        ),
        const b.BridgeAcpConfigValue.valueId(
          value: b.BridgeAcpConfigValueId(value: 'false'),
        ),
      );
      for (final (wire, expected) in [
        (
          const b.BridgeAcpConfigCategory.mode(),
          AcpConfigCategoryKindView.mode,
        ),
        (
          const b.BridgeAcpConfigCategory.model(),
          AcpConfigCategoryKindView.model,
        ),
        (
          const b.BridgeAcpConfigCategory.modelConfig(),
          AcpConfigCategoryKindView.modelConfig,
        ),
        (
          const b.BridgeAcpConfigCategory.thoughtLevel(),
          AcpConfigCategoryKindView.thoughtLevel,
        ),
      ]) {
        final option = acpConfigFromFrb(
          b.BridgeAcpConfigOption(
            id: booleanOption.id,
            name: 'known',
            category: wire,
            kind: const b.BridgeAcpConfigKind.select(
              currentValue: b.BridgeAcpConfigValueId(value: 'v'),
              options: b.BridgeAcpSelectOptions.ungrouped(options: []),
            ),
          ),
        );
        expect(option.category!.kind, expected);
        expect(
          ((option.kind as AcpSelectConfigView).options
                  as AcpUngroupedOptionsView)
              .options,
          isEmpty,
        );
      }
    },
  );

  test('all fourteen stable updates preserve rich payloads and ordering', () {
    final user = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.userMessageChunk(chunk: chunk),
    ) as AcpUserMessageChunkView;
    final agent = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.agentMessageChunk(chunk: chunk),
    ) as AcpAgentMessageChunkView;
    final thought = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.agentThoughtChunk(chunk: chunk),
    ) as AcpAgentThoughtChunkView;
    for (final chunk in [user.chunk, agent.chunk, thought.chunk]) {
      expect(chunk.messageId!.value, 'message');
      expect((chunk.content as AcpTextContentView).text, 'hello');
      expectMeta(chunk.meta);
    }
    final call = (acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.toolCall(
        call: n.BridgeAcpToolCall(
          toolCallId: 'tool',
          title: 'Title',
          name: 'real-tool',
          kind: n.BridgeAcpToolKind.execute,
          status: n.BridgeAcpToolStatus.inProgress,
          content: [
            n.BridgeAcpToolContent.content(content: text, meta: meta),
            n.BridgeAcpToolContent.diff(
              path: '/p',
              oldText: null,
              newText: 'new',
              meta: meta,
            ),
            n.BridgeAcpToolContent.terminal(terminalId: 'terminal', meta: meta),
          ],
          locations: [
            n.BridgeAcpToolLocation(path: '/p', line: 19, meta: meta),
          ],
          rawInput: b.BridgeAcpJsonValue.bool(value: false),
          rawOutput: b.BridgeAcpJsonValue.null_(),
          meta: meta,
        ),
      ),
    ) as AcpToolCallSessionUpdateView).toolCall;
    expect(call.toolCallId.value, 'tool');
    expect(call.name, 'real-tool');
    expect(call.title, 'Title');
    expect(call.kind, AcpToolKindView.execute);
    expect(call.status, AcpToolCallStatusView.inProgress);
    expect(
      (call.content[0] as AcpToolContentView).content,
      isA<AcpTextContentView>(),
    );
    expect((call.content[1] as AcpToolDiffView).oldText, isNull);
    expect((call.content[1] as AcpToolDiffView).newText, 'new');
    expect(
      (call.content[2] as AcpToolTerminalView).terminalId.value,
      'terminal',
    );
    expect(call.locations.single.line, 19);
    expectMeta(call.locations.single.meta);
    expect((call.rawInput as AcpJsonBool).value, false);
    expect(call.rawOutput, isA<AcpJsonNull>());
    expectMeta(call.meta);
    final changed = (acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.toolCallUpdate(update: toolUpdate),
    ) as AcpToolCallChangedView).toolCall;
    expect(changed.toolCallId.value, 'tool');
    expect(changed.fields.kind, isNull);
    expect(changed.fields.content, isEmpty);
    expect(changed.fields.locations, isNull);
    expect(changed.fields.rawInput, isA<AcpJsonNull>());
    expect(changed.fields.rawOutput, isNull);
    expectMeta(changed.meta);
    final plan = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.plan(
        entries: [
          n.BridgeAcpPlanEntry(
            content: 'first',
            priority: n.BridgeAcpPlanPriority.high,
            status: n.BridgeAcpPlanStatus.pending,
          ),
          n.BridgeAcpPlanEntry(
            content: 'second',
            priority: n.BridgeAcpPlanPriority.low,
            status: n.BridgeAcpPlanStatus.completed,
            meta: meta,
          ),
        ],
        meta: meta,
      ),
    ) as AcpPlanView;
    expect(plan.entries.map((e) => e.content), ['first', 'second']);
    expect(plan.entries[1].priority, AcpPlanPriorityView.low);
    expect(plan.entries[1].status, AcpPlanStatusView.completed);
    expectMeta(plan.entries[1].meta);
    expectMeta(plan.meta);
    final commands = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.availableCommands(
        commands: [
          n.BridgeAcpAvailableCommand(
            name: 'cmd',
            description: 'description',
            input: n.BridgeAcpCommandInput(hint: 'hint', meta: meta),
            meta: meta,
          ),
          n.BridgeAcpAvailableCommand(name: 'empty', description: ''),
        ],
        meta: meta,
      ),
    ) as AcpAvailableCommandsUpdateView;
    expect(commands.commands.map((c) => c.name), ['cmd', 'empty']);
    expect(
      (commands.commands.first.input as AcpUnstructuredCommandInputView).hint,
      'hint',
    );
    expectMeta(
      (commands.commands.first.input as AcpUnstructuredCommandInputView).meta,
    );
    expect(commands.commands.last.input, isNull);
    expectMeta(commands.meta);
    final mode = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.currentMode(
        modeId: b.BridgeAcpModeId(value: 'mode'),
        meta: meta,
      ),
    ) as AcpCurrentModeUpdateView;
    expect(mode.currentModeId.value, 'mode');
    expectMeta(mode.meta);
    final config = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.configOptions(
        configOptions: [booleanOption],
        meta: meta,
      ),
    ) as AcpConfigOptionsUpdateView;
    expect(config.configOptions.single.id.value, 'config');
    expectMeta(config.meta);
    final info = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.sessionInfo(
        title: n.BridgeAcpStringField.value(value: 'title'),
        updatedAt: n.BridgeAcpStringField.null_(),
        meta: meta,
      ),
    ) as AcpSessionInfoUpdateView;
    expect((info.title as AcpFieldValue<String>).value, 'title');
    expect(info.updatedAt, isA<AcpFieldNull<String>>());
    expectMeta(info.meta);
    final usage = acpUpdateFromFrb(
      n.BridgeAcpSessionUpdate.usage(
        used: maxU64,
        size: maxU64 - BigInt.one,
        cost: const n.BridgeAcpCost(amount: 1.5, currency: 'USD', meta: meta),
        meta: meta,
      ),
    ) as AcpUsageUpdateView;
    expect(usage.used, maxU64);
    expect(usage.size, maxU64 - BigInt.one);
    expect(usage.cost!.amount, 1.5);
    expect(usage.cost!.currency, 'USD');
    expectMeta(usage.cost!.meta);
    expectMeta(usage.meta);
    final notice = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.notice(
        severity: n.BridgeAcpNoticeSeverity.other(value: 'vendor-notice'),
        title: 'Title',
        description: 'details',
        meta: meta,
      ),
    ) as AcpNoticeView;
    expect(notice.severity.other, 'vendor-notice');
    expect(notice.title, 'Title');
    expect(notice.description, 'details');
    expectMeta(notice.meta);
    final compaction = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.compaction(
        compactionId: 'compaction',
        status: n.BridgeAcpCompactionStatus.other(value: 'vendor-status'),
        summary: n.BridgeAcpContentField.value(value: [text]),
        error: n.BridgeAcpStringField.value(value: 'error'),
        meta: n.BridgeAcpMetaField.value(value: meta),
      ),
    ) as AcpCompactionUpdateView;
    expect(compaction.compactionId.value, 'compaction');
    expect(compaction.status.other, 'vendor-status');
    expect(
      ((compaction.summary as AcpFieldValue<List<AcpContentBlockView>>)
                  .value
                  .single
              as AcpTextContentView)
          .text,
      'hello',
    );
    expect((compaction.error as AcpFieldValue<String>).value, 'error');
    expectMeta((compaction.meta as AcpFieldValue<AcpJsonObject>).value);
    final summary = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.compactionSummary(
        compactionId: 'compaction',
        content: text,
        meta: meta,
      ),
    ) as AcpCompactionSummaryChunkView;
    expect(summary.compactionId.value, 'compaction');
    expect((summary.content as AcpTextContentView).text, 'hello');
    expectMeta(summary.meta);
  });

  test('MaybeUndefined has absent, explicit null and present empty values', () {
    final absent = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.compaction(
        compactionId: 'id',
        status: n.BridgeAcpCompactionStatus.inProgress(),
        summary: n.BridgeAcpContentField.undefined(),
        error: n.BridgeAcpStringField.undefined(),
        meta: n.BridgeAcpMetaField.undefined(),
      ),
    ) as AcpCompactionUpdateView;
    expect(absent.summary, isA<AcpFieldAbsent<List<AcpContentBlockView>>>());
    expect(absent.error, isA<AcpFieldAbsent<String>>());
    expect(absent.meta, isA<AcpFieldAbsent<AcpJsonObject>>());
    final explicitNull = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.compaction(
        compactionId: 'id',
        status: n.BridgeAcpCompactionStatus.completed(),
        summary: n.BridgeAcpContentField.null_(),
        error: n.BridgeAcpStringField.null_(),
        meta: n.BridgeAcpMetaField.null_(),
      ),
    ) as AcpCompactionUpdateView;
    expect(
      explicitNull.summary,
      isA<AcpFieldNull<List<AcpContentBlockView>>>(),
    );
    expect(explicitNull.error, isA<AcpFieldNull<String>>());
    expect(explicitNull.meta, isA<AcpFieldNull<AcpJsonObject>>());
    final empty = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.compaction(
        compactionId: 'id',
        status: n.BridgeAcpCompactionStatus.failed(),
        summary: n.BridgeAcpContentField.value(value: []),
        error: n.BridgeAcpStringField.value(value: ''),
        meta: n.BridgeAcpMetaField.value(value: {}),
      ),
    ) as AcpCompactionUpdateView;
    expect(
      (empty.summary as AcpFieldValue<List<AcpContentBlockView>>).value,
      isEmpty,
    );
    expect((empty.error as AcpFieldValue<String>).value, '');
    expect((empty.meta as AcpFieldValue<AcpJsonObject>).value.values, isEmpty);
    final info = acpUpdateFromFrb(
      const n.BridgeAcpSessionUpdate.sessionInfo(
        title: n.BridgeAcpStringField.undefined(),
        updatedAt: n.BridgeAcpStringField.value(value: ''),
      ),
    ) as AcpSessionInfoUpdateView;
    expect(info.title, isA<AcpFieldAbsent<String>>());
    expect((info.updatedAt as AcpFieldValue<String>).value, '');
  });

  test(
    'frames and all event variants keep target/SDK qualifications independent',
    () {
      final accepted = acpFrameFromFrb(
        b.BridgeAcpSessionFrame.accepted(target: target, hasObservation: false),
      ) as AcpAcceptedFrameView;
      expect(accepted.target.sessionId, 'product-session');
      expect(accepted.target.agentId, 'agent');
      expect(accepted.target.threadId, 'thread');
      expect(accepted.target.instance, maxU64);
      expect(accepted.hasObservation, false);
      final ready = event(
        const b.BridgeAcpSessionEvent.ready(
          response: b.BridgeAcpNewSessionResponse(
            sessionId: b.BridgeAcpRemoteSessionId(value: 'remote'),
            modes: b.BridgeAcpModeState(
              currentModeId: b.BridgeAcpModeId(value: 'mode'),
              availableModes: [
                b.BridgeAcpMode(
                  id: b.BridgeAcpModeId(value: 'mode'),
                  name: 'Mode',
                  description: 'description',
                  meta: meta,
                ),
              ],
              meta: meta,
            ),
            configOptions: [],
            meta: meta,
          ),
        ),
      ) as AcpReadyEventView;
      expect(ready.response.sessionId.value, 'remote');
      expect(ready.response.configOptions, isEmpty);
      expect(ready.response.modes!.currentModeId.value, 'mode');
      expect(
        ready.response.modes!.availableModes.single.description,
        'description',
      );
      expectMeta(ready.response.modes!.availableModes.single.meta);
      expectMeta(ready.response.meta);
      final update = event(
        const b.BridgeAcpSessionEvent.update(
          update: n.BridgeAcpSessionNotification(
            sessionId: b.BridgeAcpRemoteSessionId(value: 'remote'),
            update: n.BridgeAcpSessionUpdate.agentMessageChunk(chunk: chunk),
            meta: meta,
          ),
        ),
      ) as AcpUpdateEventView;
      expect(update.update.sessionId.value, 'remote');
      expect(update.update.update, isA<AcpAgentMessageChunkView>());
      expectMeta(update.update.meta);
      expect(
        (event(
          const b.BridgeAcpSessionEvent.failed(failure: failure),
        ) as AcpFailedEventView).error.rpcCode,
        -32001,
      );
      final permission = event(
        b.BridgeAcpSessionEvent.permission(
          id: b.BridgeAcpPermissionId(instance: run.instance, sequence: maxU64),
          request: const n.BridgeAcpPermissionRequest(
            sessionId: b.BridgeAcpRemoteSessionId(value: 'remote'),
            toolCall: toolUpdate,
            options: [
              n.BridgeAcpPermissionOption(
                optionId: b.BridgeAcpPermissionOptionId(
                  value: 'permission-option',
                ),
                name: 'Allow',
                kind: n.BridgeAcpPermissionKind.allowOnce,
                meta: meta,
              ),
            ],
            meta: meta,
          ),
        ),
      ) as AcpPermissionEventView;
      expect(permission.id.instance, run.instance);
      expect(permission.id.instance, isNot(accepted.target.instance));
      expect(permission.id.sequence, maxU64);
      expect(
        permission.request.options.single.optionId.value,
        'permission-option',
      );
      expect(
        permission.request.options.single.kind,
        AcpPermissionOptionKindView.allowOnce,
      );
      expectMeta(permission.request.meta);
      final configured = event(
        const b.BridgeAcpSessionEvent.configured(
          configOptions: [booleanOption],
          meta: meta,
        ),
      ) as AcpConfiguredEventView;
      expect(configured.response.configOptions.single.id.value, 'config');
      expectMeta(configured.response.meta);
      expect(
        (event(
          const b.BridgeAcpSessionEvent.modeSet(
            modeId: b.BridgeAcpModeId(value: 'mode'),
          ),
        ) as AcpModeSetEventView).modeId.value,
        'mode',
      );
      final completed = event(
        b.BridgeAcpSessionEvent.completed(
          completed: b.BridgeAcpCompletedRun(
            run: run,
            completionSequence: maxU64,
            result: const b.BridgeAcpPromptResult.succeeded(
              response: b.BridgeAcpPromptResponse(
                stopReason: b.BridgeAcpStopReason.maxTurnRequests,
                meta: meta,
              ),
            ),
            summary: 'summary',
            truncated: true,
          ),
        ),
      ) as AcpCompletedEventView;
      expect(completed.completed.run.instance, run.instance);
      expect(completed.completed.completionSequence, maxU64);
      expect(completed.completed.summary, 'summary');
      expect(completed.completed.truncated, true);
      expect(
        (completed.completed.result as AcpSuccessView<AcpPromptResponseView>)
            .value
            .stopReason,
        AcpStopReasonView.maxTurnRequests,
      );
      expectMeta(
        (completed.completed.result as AcpSuccessView<AcpPromptResponseView>)
            .value
            .meta,
      );
      for (final (wire, expected) in [
        (
          b.BridgeAcpObservationGap.windowExceeded,
          AcpObservationGapView.windowExceeded,
        ),
        (
          b.BridgeAcpObservationGap.disconnected,
          AcpObservationGapView.disconnected,
        ),
        (b.BridgeAcpObservationGap.encoding, AcpObservationGapView.encoding),
      ]) {
        expect(
          (event(
            b.BridgeAcpSessionEvent.gap(gap: wire),
          ) as AcpGapEventView).gap,
          expected,
        );
      }
      expect(
        (acpFrameFromFrb(
          const b.BridgeAcpSessionFrame.settled(
            result: b.BridgeAcpSettlement.succeeded(),
          ),
        ) as AcpSettledFrameView).result,
        isA<AcpSuccessView<void>>(),
      );
      expect(
        ((acpFrameFromFrb(
                  const b.BridgeAcpSessionFrame.settled(
                    result: b.BridgeAcpSettlement.failed(failure: failure),
                  ),
                ) as AcpSettledFrameView).result
                as AcpFailureView<void>)
            .error
            .rpcCode,
        -32001,
      );
    },
  );

  test('startup failures preserve distinct kinds and safe guidance, not generic preparation', () {
    for (final (wire, expected) in [
      (
        b.BridgeAcpBusinessFailureKind.installRequired,
        AcpBusinessFailureKindView.installRequired,
      ),
      (
        b.BridgeAcpBusinessFailureKind.installationInvalid,
        AcpBusinessFailureKindView.installationInvalid,
      ),
      (
        b.BridgeAcpBusinessFailureKind.unsupportedPlatform,
        AcpBusinessFailureKindView.unsupportedPlatform,
      ),
      (
        b.BridgeAcpBusinessFailureKind.missingExecutable,
        AcpBusinessFailureKindView.missingExecutable,
      ),
      (
        b.BridgeAcpBusinessFailureKind.invalidWorkingDirectory,
        AcpBusinessFailureKindView.invalidWorkingDirectory,
      ),
      (
        b.BridgeAcpBusinessFailureKind.invalidDefinition,
        AcpBusinessFailureKindView.invalidDefinition,
      ),
      (b.BridgeAcpBusinessFailureKind.io, AcpBusinessFailureKindView.io),
      (
        b.BridgeAcpBusinessFailureKind.cancelled,
        AcpBusinessFailureKindView.cancelled,
      ),
    ]) {
      final message = switch (expected) {
        AcpBusinessFailureKindView.installRequired =>
          'Installation is required. Choose Install explicitly.',
        AcpBusinessFailureKindView.missingExecutable =>
          'Configured ACP executable was not found.',
        _ => 'Safe startup failure.',
      };
      final mapped = acpFailureFromFrb(
        b.BridgeAcpBusinessFailure(
          kind: wire,
          message: message,
          authMethods: const [],
        ),
      );
      expect(mapped.kind, expected);
      expect(mapped.kind, isNot(AcpBusinessFailureKindView.preparation));
      expect(mapped.message, message);
    }
  });

  test('failure/auth details and partial close/snapshot facts never become success', () {
    final error = acpFailureFromFrb(failure);
    expect(error.kind, AcpBusinessFailureKindView.rpc);
    expect(error.message, 'remote');
    expect(error.rpcCode, -32001);
    expect(
      (error.rpcData as AcpJsonObject).values['nested'],
      isA<AcpJsonNull>(),
    );
    expect(error.authMethods.single.id, 'login');
    expect(error.authMethods.single.name, 'Agent login');
    expect(error.authMethods.single.description, isNull);
    expect(error.authMethods.single.kind, AcpAuthMethodKindView.agent);
    final completed = b.BridgeAcpCompletedRun(
      run: run,
      completionSequence: maxU64,
      result: const b.BridgeAcpPromptResult.failed(failure: failure),
      summary: 'bounded summary',
      truncated: true,
    );
    final close = acpCloseFromFrb(
      b.BridgeAcpBusinessClose(
        localComplete: false,
        sdkFinished: true,
        cleanupTimedOut: true,
        remoteCloseError: failure,
        sdkError: failure,
        workerError: 'worker',
        driverError: 'driver',
        unfinishedPrompt: run,
        unfinishedControls: true,
        lastCompleted: completed,
        ownerFailures: const [
          b.BridgeAcpMemberCloseFailure(
            threadId: 'other-thread',
            message: 'owner',
          ),
        ],
      ),
    );
    expect(close.localComplete, false);
    expect(close.sdkFinished, true);
    expect(close.cleanupTimedOut, true);
    expect(close.remoteCloseError!.rpcCode, -32001);
    expect(close.sdkError!.rpcCode, -32001);
    expect(close.workerError, 'worker');
    expect(close.driverError, 'driver');
    expect(close.unfinishedPrompt!.instance, run.instance);
    expect(close.unfinishedControls, true);
    expect(close.lastCompleted!.completionSequence, maxU64);
    expect(
      (close.lastCompleted!.result as AcpFailureView<AcpPromptResponseView>)
          .error
          .rpcCode,
      -32001,
    );
    expect(close.ownerFailures.single.threadId, 'other-thread');
    expect(close.ownerFailures.single.message, 'owner');
    final state = acpSnapshotFromFrb(
      b.BridgeAcpBusinessSnapshot(
        target: target,
        acpSessionId: const b.BridgeAcpRemoteSessionId(value: 'remote'),
        ready: false,
        closing: true,
        configPending: true,
        configOptions: const [booleanOption],
        activeRun: run,
        lastCompleted: completed,
        observationGap: b.BridgeAcpObservationGap.encoding,
        authMethods: failure.authMethods,
      ),
    );
    expect(state.target.instance, maxU64);
    expect(state.acpSessionId!.value, 'remote');
    expect(state.ready, false);
    expect(state.closing, true);
    expect(state.configPending, true);
    expect(state.activeRun!.instance, run.instance);
    expect(state.observationGap, AcpObservationGapView.encoding);
    expect(state.lastCompleted!.summary, 'bounded summary');
    expect(state.authMethods.single.description, isNull);
  });

  test(
    'list and open intents preserve optional data without reidentification',
    () {
      final response = acpListFromFrb(
        const b.BridgeAcpListResponse(
          sessions: [
            b.BridgeAcpSessionInfo(
              sessionId: b.BridgeAcpRemoteSessionId(value: 'remote'),
              cwd: '/workspace',
              additionalDirectories: ['/b', '/a'],
              title: '',
              updatedAt: null,
              meta: meta,
            ),
          ],
          nextCursor: 'cursor',
          meta: meta,
        ),
      );
      expect(response.sessions.single.sessionId.value, 'remote');
      expect(response.sessions.single.cwd, '/workspace');
      expect(response.sessions.single.additionalDirectories, ['/b', '/a']);
      expect(response.sessions.single.title, '');
      expect(response.sessions.single.updatedAt, isNull);
      expect(response.nextCursor, 'cursor');
      expectMeta(response.meta);
      expectMeta(response.sessions.single.meta);
      for (final (intent, type) in [
        (const AcpNewIntentView(), b.BridgeAcpOpenIntent_New),
        (
          const AcpLoadIntentView(AcpRemoteSessionId('remote')),
          b.BridgeAcpOpenIntent_Load,
        ),
        (
          const AcpResumeIntentView(AcpRemoteSessionId('remote')),
          b.BridgeAcpOpenIntent_Resume,
        ),
      ]) {
        final wire = acpOpenToFrb(
          OpenAcpSessionRequestView(
            accountId: 'account',
            expectedConnectionRevision: maxU64,
            workspaceId: 'workspace',
            intent: intent,
          ),
        );
        expect(wire.intent.runtimeType, type);
        expect(wire.accountId, 'account');
        expect(wire.expectedConnectionRevision, maxU64);
        expect(wire.workspaceId, 'workspace');
        expect(wire.threadId, isNull);
      }
    },
  );
}
