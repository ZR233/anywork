import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart'
    show ModelsPort, ModelsRepository, createModelsRepository;
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'scripted_feed.dart';

/// ACP 接入的保存/删除属于 Settings，目录本身是配置材料的一部分。
///
/// 这个环境只声明三类真实原生边界：一条 Settings 订阅、按固定材料版本固定下来的配置
/// 读取作用域（页、文本块与关闭）、以及真实的 ACP 账号写入调用（含原始结果查询与
/// 真实关闭）。它不校验页连续性、不去重行集、不推导连接代次、不缓存第二份 canonical，
/// 也不重放命令——这些都是被测仓储的策略。
const acpConfigurationOrigin = ProductReadOrigin(
  ownerEpoch: 'acp-configuration-native',
  incarnation: 1,
);

/// 配置材料引用在 Settings header 里的 entry；材料版本由 `reference.revision` 承载。
const acpConfigurationEntry = 1;

/// Settings 写入回执绑定的资源身份。
const settingsResourceKey = 'settings';

/// 一次 Settings 写入的真实回执；`revision` 是写入后应被 settings topic 覆盖的水位。
CommitReceipt settingsAcpAccountReceipt(
  OperationId operationId, {
  required int revision,
  String ownerEpoch = 'acp-configuration-native',
}) => CommitReceipt(
  operationId: operationId,
  disposition: CommitDisposition.applied,
  targets: [
    ResourceStamp(
      resourceKey: settingsResourceKey,
      ownerEpoch: ownerEpoch,
      revision: revision,
    ),
  ],
  effect: EffectPoint.immediate,
);

/// 一次写入捕获的原配置读取目标；材料版本与 Settings revision 相互独立。
ConfigurationReadTarget acpConfigurationTarget(int materialRevision) =>
    ConfigurationReadTarget(
      origin: acpConfigurationOrigin,
      reference: ConfigurationReadRef(
        entry: acpConfigurationEntry,
        revision: materialRevision,
      ),
    );

/// 材料里一行 ACP 接入的声明。ID 与名称按 UTF-8 文本分块读取，供应商与连接代次按原值。
final class AcpAccountRow {
  const AcpAccountRow({
    required this.accountId,
    required this.name,
    this.provider = AcpProvider.antigravity,
    this.connectionRevision = 1,
  });

  final String accountId;
  final String name;
  final AcpProvider provider;
  final int connectionRevision;
}

/// 一份固定的配置材料：`listId` 是 ACP 列表引用，`pageSize`/`chunkBytes` 是这个原生
/// 环境声明的页与文本块大小（不是仓储策略）。同一个材料版本被再次固定时复用同一份值。
final class AcpScopeMaterial {
  AcpScopeMaterial({
    required List<AcpAccountRow> rows,
    this.listId = 11,
    this.pageSize = 32,
    this.chunkBytes = 65536,
  }) : rows = List.unmodifiable(rows);

  final List<AcpAccountRow> rows;
  final int listId;
  final int pageSize;
  final int chunkBytes;

  TypedListRef get reference =>
      TypedListRef(listId: listId, total: rows.length);
}

/// 行文本字段的身份：`accountId`/`name` 各占一个可分块读取的字段。
int acpAccountIdField(int row) => 100 + row * 2;
int acpAccountNameField(int row) => 101 + row * 2;

/// 配置读取作用域的元数据头：ACP 列表引用由材料决定，其余字段在这个环境里为空。
///
/// 这里不构造任何 Settings 业务时钟：材料版本只来自 `acpAccounts` 引用。
ConfigurationReadHeader acpReadHeader({required AcpScopeMaterial material}) =>
    ConfigurationReadHeader(
      defaultAccountId: null,
      accounts: const TypedListRef(listId: 1, total: 0),
      acpAccounts: material.reference,
      modeModelRoutes: const TypedListRef(listId: 2, total: 0),
      roles: const TypedListRef(listId: 3, total: 0),
      permissionMode: const ReadText.inline(text: 'workspace-write'),
      instructions: InstructionsSettingsRead(
        baseOverride: const ReadText.inline(text: ''),
        developer: const ReadText.inline(text: ''),
        user: const ReadText.inline(text: ''),
        projectDocMaxBytes: 4096,
        projectDocFallbackFilenames: const TypedListRef(listId: 4, total: 0),
      ),
      skills: SkillsSettingsRead(
        enabled: false,
        autoLearn: false,
        systemEnabled: false,
        projectDir: const ReadText.inline(text: ''),
        userDir: const ReadText.inline(text: ''),
        externalDirs: const TypedListRef(listId: 5, total: 0),
        disabled: const TypedListRef(listId: 6, total: 0),
        autoLearnMinToolCalls: 0,
      ),
      mcpServers: const TypedListRef(listId: 7, total: 0),
      general: GeneralSettingsRead(
        followActiveTurn: false,
        compactTimeline: false,
        sidebarWidth: null,
        pinnedThreadIds: const TypedListRef(listId: 8, total: 0),
        pinnedProjectIds: const TypedListRef(listId: 9, total: 0),
      ),
      delegation: DelegationSettings(
        mode: DelegationMode.profile,
        preference: DelegationPreference.balanced,
      ),
      webSearch: WebSearchConfigurationRead(
        configuredMode: const ReadText.inline(text: 'off'),
        contextSize: null,
        allowedDomains: const TypedListRef(listId: 10, total: 0),
        country: null,
        region: null,
        city: null,
        timezone: null,
      ),
      deepseekWebSearch: DeepSeekSearchConfigurationRead(
        configuredEnabled: false,
        configuredFetchEnabled: false,
      ),
    );

/// 一个真实固定的配置读取作用域：测试给出材料，作用域只按页/块返回并记录具名调用。
///
/// 屏障（`headerGate`/`pageGate`/`textGate`）让调用顺序完全确定；脚本化失败与非法页
/// 覆盖只表达“这个原生环境返回了什么”，不实现任何仓储校验或重试。
final class ScriptedConfigurationScope implements ConfigurationReadConnection {
  ScriptedConfigurationScope({
    required this.index,
    required this.reference,
    required this.origin,
    required this.material,
    this.headerGate,
    this.pageGate,
    this.textGate,
  }) : _fields = {
         for (var row = 0; row < material.rows.length; row += 1) ...{
           acpAccountIdField(row): material.rows[row].accountId,
           acpAccountNameField(row): material.rows[row].name,
         },
       };

  final int index;

  /// 被固定的读取引用与来源；材料版本就是 [reference] 的 revision。
  final ConfigurationReadRef reference;
  final ProductReadOrigin origin;
  final AcpScopeMaterial material;

  /// 具名调用记录：证明读了哪一份固定材料、哪些页与哪些文本块。
  int headerCalls = 0;
  final pages = <({int listId, int offset, int limit})>[];
  final texts = <({int fieldId, int offset, int maxBytes})>[];

  /// 顺序屏障；为空表示不阻塞。
  Completer<void>? headerGate;
  Completer<void>? pageGate;
  Completer<void>? textGate;

  /// 一次性脚本化失败（消费后清空）。
  StudioFailure? headerFailure;
  StudioFailure? pageFailure;
  StudioFailure? textFailure;

  /// 一次性脚本化非法页声明。
  int? Function(int offset, int end)? nextOffsetOverride;
  int? totalOverride;

  /// 脚本化“返回了另一个偏移的文本块”；0 表示如实返回。
  int textOffsetSkew = 0;

  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  Completer<FeedCloseReport>? closeReceipt;

  final Map<int, String> _fields;

  /// 该作用域声明的元数据头值（与一次 `header()` 返回的内容一致）。
  ConfigurationReadHeader get headerValue => acpReadHeader(material: material);

  @override
  Future<ConfigurationReadHeader> header() async {
    headerCalls += 1;
    final gate = headerGate;
    if (gate != null) await gate.future;
    final failure = headerFailure;
    if (failure != null) {
      headerFailure = null;
      throw failure;
    }
    return headerValue;
  }

  @override
  Future<AcpAccountConfigurationReadPage> acpAccounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    pages.add((listId: listId, offset: offset, limit: limit));
    final gate = pageGate;
    if (gate != null) await gate.future;
    final failure = pageFailure;
    if (failure != null) {
      pageFailure = null;
      throw failure;
    }
    final total = totalOverride ?? material.rows.length;
    final end = math.min<int>(
      offset + math.min<int>(limit, material.pageSize),
      total,
    );
    final override = nextOffsetOverride;
    return AcpAccountConfigurationReadPage(
      listId: listId,
      offset: offset,
      total: total,
      items: [for (var row = offset; row < end; row += 1) _row(row)],
      // 覆盖值即使为 null 也表示“这个环境就是这样声明的”，不回退到默认声明。
      nextOffset: override == null
          ? (end == total ? null : end)
          : override(offset, end),
    );
  }

  @override
  Future<TextChunk> text(
    int fieldId, {
    int offset = 0,
    int maxBytes = 65536,
  }) async {
    texts.add((fieldId: fieldId, offset: offset, maxBytes: maxBytes));
    final gate = textGate;
    if (gate != null) await gate.future;
    final failure = textFailure;
    if (failure != null) {
      textFailure = null;
      throw failure;
    }
    final value = _fields[fieldId];
    if (value == null) {
      throw StateError('Unscripted configuration text field $fieldId');
    }
    final chunk = _chunk(fieldId, value, offset, maxBytes);
    if (textOffsetSkew == 0) return chunk;
    return chunk.copyWith(offset: chunk.offset + textOffsetSkew);
  }

  AcpAccountConfigurationRead _row(int row) {
    if (row >= material.rows.length) {
      throw StateError('Unscripted ACP account row $row');
    }
    final value = material.rows[row];
    return AcpAccountConfigurationRead(
      accountId: ReadText.deferred(
        fieldId: acpAccountIdField(row),
        utf8Bytes: utf8.encode(value.accountId).length,
      ),
      name: ReadText.deferred(
        fieldId: acpAccountNameField(row),
        utf8Bytes: utf8.encode(value.name).length,
      ),
      provider: value.provider,
      connectionRevision: value.connectionRevision,
    );
  }

  /// 按 UTF-8 字节偏移切出一块**字符边界对齐**的文本；块大小由材料声明。
  TextChunk _chunk(int fieldId, String value, int offset, int maxBytes) {
    final boundaries = _runeBoundaries(value);
    final start = boundaries.indexOf(offset);
    if (start < 0) {
      throw StateError('Unscripted text offset $offset for field $fieldId');
    }
    final budget = math.min(maxBytes, material.chunkBytes);
    var end = start;
    while (end + 1 < boundaries.length &&
        boundaries[end + 1] - offset <= budget) {
      end += 1;
    }
    if (end == start) {
      throw StateError(
        'The declared chunk budget cannot advance field $fieldId',
      );
    }
    final bytes = utf8.encode(value);
    return TextChunk(
      fieldId: fieldId,
      offset: offset,
      text: utf8.decode(bytes.sublist(offset, boundaries[end])),
      nextOffset: boundaries[end] == bytes.length ? null : boundaries[end],
    );
  }

  List<int> _runeBoundaries(String value) {
    final result = <int>[];
    var at = 0;
    for (final rune in value.runes) {
      result.add(at);
      at += utf8.encode(String.fromCharCode(rune)).length;
    }
    result.add(at);
    return result;
  }

  @override
  void requestClose() => requestCloseCalls += 1;

  @override
  Future<FeedCloseReport> close() {
    closeCalls += 1;
    return closeReceipt?.future ??
        Future.value(
          FeedCloseReport(
            feedId: 'acp-configuration-scope-$index',
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls += 1;
    return closeReceipt?.future ??
        Future.value(
          FeedCloseReport(
            feedId: 'acp-configuration-scope-$index',
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted configuration scope capability: ${invocation.memberName}',
  );
}

/// One real ACP account write call retained by the native boundary.
///
/// `result()` observes that one invocation; `requestClose`/`close`/`retryClose` are the
/// real retained-call identity and close receipts, not a local cleanup stand-in.
final class ScriptedAcpAccountCall implements AcpAccountCommandCall {
  ScriptedAcpAccountCall({required this.callId, required this.operationId});

  @override
  final String callId;
  @override
  final OperationId operationId;

  final results = <int, Completer<AcpAccountCommandReply>>{};
  int _resultCalls = 0;
  int get resultCalls => _resultCalls;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  Completer<FeedCloseReport>? closeReceipt;

  Completer<AcpAccountCommandReply> resultAt(int index) =>
      results.putIfAbsent(index, Completer.new);

  /// Completes the write with the test-declared native reply.
  void accept(int index, AcpAccountCommandReply reply) =>
      resultAt(index).complete(reply);

  /// Dispatch evidence raised by the native boundary itself.
  void reject(int index, CommandDispatchFailure failure) =>
      resultAt(index).completeError(failure);

  /// A plain failure, which is exactly what an FRB call can produce.
  void fail(int index, StudioFailure failure) =>
      resultAt(index).completeError(failure);

  @override
  Future<AcpAccountCommandReply> result() => resultAt(_resultCalls++).future;

  @override
  void requestClose() => requestCloseCalls += 1;

  @override
  Future<FeedCloseReport> close() {
    closeCalls += 1;
    return closeReceipt?.future ??
        Future.value(
          FeedCloseReport(
            feedId: callId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls += 1;
    return closeReceipt?.future ??
        Future.value(
          FeedCloseReport(
            feedId: callId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
  }
}

/// One recorded native ACP account write, not the SDK's Settings lane.
final class RecordedAcpAccountCall<T> {
  RecordedAcpAccountCall(this.request, this.native);
  final T request;
  final ScriptedAcpAccountCall native;
}

final class AcpConfigurationPort implements ConfigurationPort {
  final feeds = <ScriptedFeed<ConfigurationFrame>>[];
  final _feedWaiters = <int, Completer<ScriptedFeed<ConfigurationFrame>>>{};

  /// 每个固定材料版本声明的材料：键是 `ConfigurationReadRef.revision`（材料身份，
  /// 不是 Settings revision）。
  final materials = <int, AcpScopeMaterial>{};

  /// 已打开的作用域与开放记录（引用 + 来源）。
  final scopes = <ScriptedConfigurationScope>[];
  final scopeOpens =
      <({ConfigurationReadRef reference, ProductReadOrigin origin})>[];
  final _scopeWaiters = <int, Completer<ScriptedConfigurationScope>>{};

  /// 每个新作用域使用的屏障工厂：测试据此精确控制“读取进行中”的时点。
  Completer<void>? Function(int scopeIndex)? headerGate;
  Completer<void>? Function(int scopeIndex)? pageGate;
  Completer<void>? Function(int scopeIndex)? textGate;

  final saves = <RecordedAcpAccountCall<UpdateAcpAccountRequest>>[];
  final removals = <RecordedAcpAccountCall<RemoveAcpAccountRequest>>[];
  final _saveWaiters =
      <int, Completer<RecordedAcpAccountCall<UpdateAcpAccountRequest>>>{};
  final _removalWaiters =
      <int, Completer<RecordedAcpAccountCall<RemoveAcpAccountRequest>>>{};

  /// 原始结果查询记录与屏障。
  final findCalls = <OperationId>[];
  Completer<void>? findGate;

  /// 这个环境声明的“原调用是否登记过”。
  ///
  /// `false` 只表达原生侧从未登记这次调用（因此找不到），不代表“未提交”。
  bool originalCallRegistered = true;

  /// 声明承载调用句柄的响应丢失：原调用仍被登记，只是这次 begin 没有回执。
  bool loseSaveReply = false;
  bool loseRemoveReply = false;
  StudioFailure lostReplyFailure = const StudioFailure(
    code: StudioFailureCode.unavailable,
    message: 'The native reply carrying the ACP account call was lost.',
    retryable: true,
    correlationId: 'acp-configuration-lost-reply',
  );

  int _callSequence = 0;
  int _delivery = 0;
  int _projectionRevision = 0;
  ProductCollectionRef? _collection;

  Future<ScriptedFeed<ConfigurationFrame>> opened(int index) =>
      index < feeds.length
      ? Future.value(feeds[index])
      : _feedWaiters
            .putIfAbsent(index, Completer<ScriptedFeed<ConfigurationFrame>>.new)
            .future;

  Future<ScriptedConfigurationScope> scopeOpened(int index) =>
      index < scopes.length
      ? Future.value(scopes[index])
      : _scopeWaiters
            .putIfAbsent(index, Completer<ScriptedConfigurationScope>.new)
            .future;

  Future<RecordedAcpAccountCall<UpdateAcpAccountRequest>> saved(int index) =>
      index < saves.length
      ? Future.value(saves[index])
      : _saveWaiters
            .putIfAbsent(
              index,
              Completer<RecordedAcpAccountCall<UpdateAcpAccountRequest>>.new,
            )
            .future;

  Future<RecordedAcpAccountCall<RemoveAcpAccountRequest>> removed(int index) =>
      index < removals.length
      ? Future.value(removals[index])
      : _removalWaiters
            .putIfAbsent(
              index,
              Completer<RecordedAcpAccountCall<RemoveAcpAccountRequest>>.new,
            )
            .future;

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() async {
    final index = feeds.length;
    final feed = ScriptedFeed<ConfigurationFrame>(
      feedId: 'acp-configuration-$index',
      sequenceOf: (frame) =>
          frame is ConfigurationData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ConfigurationData,
    );
    feeds.add(feed);
    _feedWaiters.remove(index)?.complete(feed);
    return feed;
  }

  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    scopeOpens.add((reference: reference, origin: origin));
    final material = materials[reference.revision];
    if (material == null) {
      throw StateError(
        'Unscripted ACP material for reference revision ${reference.revision}',
      );
    }
    final index = scopes.length;
    final scope = ScriptedConfigurationScope(
      index: index,
      reference: reference,
      origin: origin,
      material: material,
      headerGate: headerGate?.call(index),
      pageGate: pageGate?.call(index),
      textGate: textGate?.call(index),
    );
    scopes.add(scope);
    _scopeWaiters.remove(index)?.complete(scope);
    return scope;
  }

  ConfigurationHeader _header({
    required int settingsRevision,
    required int materialRevision,
    required int updatedAt,
  }) => ConfigurationHeader(
    source: ObservedHeader(
      brief: ObservedBrief.ready(
        revision: settingsRevision,
        updatedAt: updatedAt,
        lastCheckedAt: null,
      ),
      status: ProductSourceStatusRef(entry: 9, revision: settingsRevision),
    ),
    configurationRevision: settingsRevision,
    updatedAt: updatedAt,
    reference: ConfigurationReadRef(
      entry: acpConfigurationEntry,
      revision: materialRevision,
    ),
    roleRead: null,
  );

  /// Publishes the Settings baseline the write lane freezes its CAS base from.
  ///
  /// `materialRevision` 是配置材料引用版本，`updatedAt` 是材料捕获时间；二者与
  /// `settingsRevision` 相互独立。
  ///
  /// `projectionRevision` 是传输投影戳（feed 自己的水位）；缺省沿用
  /// `settingsRevision`。它单独可声明，用于让“业务版本非法”与“投影版本非法”这两种
  /// 原生事实分别可测，而不是靠抬高其中一个掩盖另一个。
  Future<void> publishBaseline({
    required int settingsRevision,
    required int materialRevision,
    required int updatedAt,
    int? projectionRevision,
    bool awaitAcknowledgement = true,
  }) async {
    final feed = await opened(0);
    await feed.listened.future;
    _projectionRevision = projectionRevision ?? settingsRevision;
    // 集合时钟跟传输投影走：业务版本（configurationRevision）可以非法，而集合本身
    // 仍是这个 feed 声明的一份普通材料引用，避免用业务版本掩盖集合水位。
    _collection = ProductCollectionRef(
      entry: 2,
      revision: _projectionRevision,
      total: 1,
    );
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: ++_delivery,
        event: ConfigurationEvent.baseline(
          identity: ProductFeedIdentity(
            feedId: feed.feedId,
            ownerEpoch: acpConfigurationOrigin.ownerEpoch,
            incarnation: acpConfigurationOrigin.incarnation,
            resource: ProductResource.configuration,
          ),
          stamp: ProductProjectionStamp(
            ownerEpoch: acpConfigurationOrigin.ownerEpoch,
            incarnation: acpConfigurationOrigin.incarnation,
            revision: _projectionRevision,
          ),
          value: ConfigurationBaseline(
            header: _header(
              settingsRevision: settingsRevision,
              materialRevision: materialRevision,
              updatedAt: updatedAt,
            ),
            collection: _collection,
          ),
        ),
      ),
    );
    // 预期被 reducer 拒绝的帧永远不会 ACK；此时由测试改为观察仓储自己的 sync 状态。
    if (awaitAcknowledgement) await feed.acknowledged(_delivery);
  }

  /// Publishes the next Settings fact; the collection never changes here, so a change
  /// only advances the Settings revision (and optionally the material reference).
  Future<void> publishChange({
    required int settingsRevision,
    required int materialRevision,
    required int updatedAt,
    int? projectionRevision,
    bool awaitAcknowledgement = true,
  }) async {
    final feed = feeds.single;
    final base = _projectionRevision;
    final previousCollection = _collection!;
    _projectionRevision = projectionRevision ?? base + 1;
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: ++_delivery,
        event: ConfigurationEvent.change(
          stamp: ProductProjectionStamp(
            ownerEpoch: acpConfigurationOrigin.ownerEpoch,
            incarnation: acpConfigurationOrigin.incarnation,
            revision: _projectionRevision,
          ),
          baseRevision: base,
          value: ConfigurationChange(
            header: _header(
              settingsRevision: settingsRevision,
              materialRevision: materialRevision,
              updatedAt: updatedAt,
            ),
            baseCollectionRevision: previousCollection.revision,
            collection: previousCollection,
            upserted: const [],
            removedEntries: const [],
          ),
        ),
      ),
    );
    if (awaitAcknowledgement) await feed.acknowledged(_delivery);
  }

  RecordedAcpAccountCall<T> _record<T>(
    T request,
    OperationId operationId,
    List<RecordedAcpAccountCall<T>> calls,
    Map<int, Completer<RecordedAcpAccountCall<T>>> waiters,
  ) {
    final call = RecordedAcpAccountCall<T>(
      request,
      ScriptedAcpAccountCall(
        callId: 'acp-configuration-call-${++_callSequence}',
        operationId: operationId,
      ),
    );
    calls.add(call);
    waiters.remove(calls.length - 1)?.complete(call);
    return call;
  }

  @override
  Future<AcpAccountCommandCall> saveAcpAccount(
    UpdateAcpAccountRequest request,
  ) {
    final call = _record(request, request.operationId, saves, _saveWaiters);
    if (loseSaveReply) return Future.error(lostReplyFailure);
    return Future.value(call.native);
  }

  @override
  Future<AcpAccountCommandCall> removeAcpAccount(
    RemoveAcpAccountRequest request,
  ) {
    final call = _record(
      request,
      request.operationId,
      removals,
      _removalWaiters,
    );
    if (loseRemoveReply) return Future.error(lostReplyFailure);
    return Future.value(call.native);
  }

  @override
  Future<AcpAccountCommandCall?> findAcpAccountCommand(
    OperationId operationId,
  ) async {
    findCalls.add(operationId);
    await findGate?.future;
    if (!originalCallRegistered) return null;
    for (final call in [...saves, ...removals]) {
      if (call.native.operationId == operationId) return call.native;
    }
    return null;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted configuration capability: ${invocation.memberName}',
  );
}

final class _UnusedModelsPort implements ModelsPort {
  const _UnusedModelsPort();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'ACP account configuration must not demand model data: '
    '${invocation.memberName}',
  );
}

/// The production factories; only the native boundaries are scripted.
final class AcpConfigurationFixture {
  AcpConfigurationFixture({ResourceBudget? budget})
    : budget = budget ?? ResourceBudget() {
    operations = OperationRegistry(
      clientId: 'acp-configuration-test',
      budget: this.budget,
    );
    final models = createModelsRepository(
      port: const _UnusedModelsPort(),
      budget: this.budget,
    );
    modelsRepository = models.repository;
    repository = createConfigurationRepository(
      port: port,
      budget: this.budget,
      operations: operations,
      modelTargets: models.targets,
    );
  }

  final ResourceBudget budget;
  final port = AcpConfigurationPort();
  late final OperationRegistry operations;
  late final ModelsRepository modelsRepository;
  late final ConfigurationRepository repository;
}
