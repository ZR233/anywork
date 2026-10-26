import 'dart:async';

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_configuration_fixture.dart';

/// ACP 账号目录是配置材料的一部分：读取固定原配置目标并按页/文本块物化，保存与删除复用
/// 配置领域已有的受管调用。这里只通过 `ConfigurationRepository` 的公开意图观察结果，
/// 不断言 fake 的私有状态，也不为测试扩展生产接口。
const _settingsRevision = 7;
const _materialUpdatedAt = 11;

const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted Settings boundary declined this ACP write',
  retryable: false,
  correlationId: 'acp-settings-refusal',
);

AcpAccountRow _row(
  String accountId, {
  String? name,
  int connectionRevision = 1,
}) => AcpAccountRow(
  accountId: accountId,
  name: name ?? accountId,
  connectionRevision: connectionRevision,
);

AcpScopeMaterial _material(
  List<AcpAccountRow> rows, {
  int? pageSize,
  int? chunkBytes,
}) => AcpScopeMaterial(
  rows: rows,
  pageSize: pageSize ?? 32,
  chunkBytes: chunkBytes ?? 65536,
);

/// 发布 Settings 基线：材料版本与捕获时间独立于 Settings revision。
///
/// 仓储只在**首个需求**到来时才打开 Settings 订阅（`capture()` → `openConfiguration`），
/// 因此调用方必须先发起读取/写入再等这里发布，否则会一直等一个没有被 open 的订阅。
Future<void> _establish(
  AcpConfigurationFixture fixture, {
  int settingsRevision = _settingsRevision,
  int materialRevision = _settingsRevision,
  int updatedAt = _materialUpdatedAt,
  int? projectionRevision,
  bool awaitAcknowledgement = true,
}) => fixture.port.publishBaseline(
  settingsRevision: settingsRevision,
  materialRevision: materialRevision,
  updatedAt: updatedAt,
  projectionRevision: projectionRevision,
  awaitAcknowledgement: awaitAcknowledgement,
);

/// 发起首次读取并发布基线：需求先到（触发订阅打开），基线随后覆盖。
Future<AcpAccountDirectory> _loadWithBaseline(
  AcpConfigurationFixture fixture, {
  int settingsRevision = _settingsRevision,
  int materialRevision = _settingsRevision,
  int updatedAt = _materialUpdatedAt,
}) async {
  final reading = fixture.repository.loadAcpAccounts();
  await _establish(
    fixture,
    settingsRevision: settingsRevision,
    materialRevision: materialRevision,
    updatedAt: updatedAt,
  );
  return reading;
}

/// 关闭并断言真实收尾：没有未决资源，配额全部归还。
Future<void> _close(AcpConfigurationFixture fixture) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  final report = await fixture.repository.close(deadline: deadline);
  expect(report.unresolved, isEmpty);
  await fixture.modelsRepository.close(deadline: deadline);
  expect(fixture.budget.usage, isEmpty);
}

/// 关闭后断言保留的真实未决证据：原操作仍以真实阶段留在原所有者名下，不伪造 Clean。
Future<UnresolvedResource> _closeUnresolved(
  AcpConfigurationFixture fixture,
  OperationId operationId,
) async {
  final report = await fixture.repository.close(deadline: DateTime.now());
  final operation = report.unresolved.singleWhere(
    (resource) =>
        resource.owner == 'configuration:operation:${operationId.value}',
  );
  expect(
    fixture.budget.usage.any(
      (usage) =>
          usage.owner == 'configuration:operation:${operationId.value}' &&
          usage.phase == ResourcePhase.unresolved,
    ),
    isTrue,
    reason: '未观察的提交保留它的准入配额',
  );
  await fixture.modelsRepository.close(deadline: DateTime.now());
  return operation;
}

void main() {
  test('loadAcpAccounts materialises the fixed scope rows', () async {
    final fixture = AcpConfigurationFixture();
    addTearDown(() => _close(fixture));
    fixture.port.materials[_settingsRevision] = _material([
      _row('acct-work', name: 'Work', connectionRevision: 2),
      _row('acct-lab', name: 'Lab', connectionRevision: 5),
    ]);
    final directory = await _loadWithBaseline(fixture);

    expect(directory.revision, _settingsRevision);
    expect(directory.updatedAt, _materialUpdatedAt);
    expect(
      directory.origin,
      fixture.port.scopeOpens.single.origin,
      reason: '目录来源就是这个 owner 真实固定下来的读取目标，不是调用方自报的来源',
    );
    expect(
      directory.reference,
      fixture.port.scopeOpens.single.reference,
      reason: '目录引用就是这次固定读取的材料身份（entry/revision）',
    );
    expect(directory.origin, acpConfigurationOrigin);
    expect(
      directory.reference.revision,
      _settingsRevision,
      reason: '材料版本来自配置引用，不是 Settings revision 的复述',
    );
    expect(directory.accounts.map((account) => account.accountId), [
      'acct-work',
      'acct-lab',
    ]);
    final work = directory.account('acct-work')!;
    expect(work.name, 'Work');
    expect(work.provider, AcpProvider.antigravity);
    expect(
      work.connectionRevision,
      2,
      reason: '连接代次来自固定材料本身，不由 Settings 版本或列表位置推导',
    );
    expect(
      work.matches('acct-work', 2),
      isTrue,
      reason: '账号身份与连接身份共同决定一条观察是否适用',
    );
    expect(
      work.matches('acct-work', 3),
      isFalse,
      reason: '重命名不改变连接代次，另一个代次不套用本条观察',
    );
    expect(directory.account('acct-missing'), isNull);

    final scope = await fixture.port.scopeOpened(0);
    expect(scope.headerCalls, 1);
    expect(scope.pages.single.listId, 11);
    expect(scope.pages.single.offset, 0);
    expect(scope.texts.map((call) => call.fieldId), [
      acpAccountIdField(0),
      acpAccountNameField(0),
      acpAccountIdField(1),
      acpAccountNameField(1),
    ], reason: '每行的 ID 与名称都按各自字段读取');
    expect(
      fixture.port.scopeOpens.single.reference.entry,
      acpConfigurationEntry,
    );
    expect(
      fixture.repository.state.value.projection.header?.configurationRevision,
      _settingsRevision,
      reason: '有界读取不写成第二份 canonical',
    );
  });

  test(
    'a malformed fixed scope is a protocol error, never a patched directory',
    () async {
      final cases = <({String label, AcpScopeMaterial material})>[
        (label: 'empty account id', material: _material([_row('')])),
        (label: 'blank account id', material: _material([_row('   ')])),
        (
          label: 'duplicate account id',
          material: _material([_row('acct-work'), _row('acct-work')]),
        ),
        (
          label: 'negative connection revision',
          material: _material([_row('acct-work', connectionRevision: -1)]),
        ),
      ];

      for (final entry in cases) {
        final fixture = AcpConfigurationFixture();
        addTearDown(() => _close(fixture));
        fixture.port.materials[_settingsRevision] = entry.material;
        final expectation = expectLater(
          fixture.repository.loadAcpAccounts(),
          throwsA(
            isA<StudioFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  StudioFailureCode.protocol,
                )
                .having(
                  (failure) => failure.correlationId,
                  'correlationId',
                  'configuration',
                ),
          ),
          reason: entry.label,
        );
        await _establish(fixture);
        await expectation;
      }
    },
  );

  test(
    'a page or chunk that does not match its pinned field is a protocol error',
    () async {
      // 页声明缺失续页：材料有 2 行，第一页只给 1 行并谎称已结束。
      final paged = AcpConfigurationFixture();
      addTearDown(() => _close(paged));
      paged.port.materials[_settingsRevision] = _material([
        _row('acct-a'),
        _row('acct-b'),
      ], pageSize: 1);
      paged.port.headerGate = (index) => index == 0 ? Completer() : null;
      final reading = paged.repository.loadAcpAccounts();
      await _establish(paged);
      final scope = await paged.port.scopeOpened(0);
      scope.nextOffsetOverride = (offset, end) => null;
      scope.headerGate!.complete();
      await expectLater(
        reading,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
      expect(scope.pages, hasLength(1), reason: '缺续页后不再继续请求后续页');

      // 文本块偏移与固定字段不符。
      final skewed = AcpConfigurationFixture();
      addTearDown(() => _close(skewed));
      skewed.port.materials[_settingsRevision] = _material([_row('acct-a')]);
      skewed.port.textGate = (index) => index == 0 ? Completer() : null;
      final skewedReading = skewed.repository.loadAcpAccounts();
      await _establish(skewed);
      final skewedScope = await skewed.port.scopeOpened(0);
      skewedScope.textOffsetSkew = 1;
      skewedScope.textGate!.complete();
      await expectLater(
        skewedReading,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
    },
  );

  test('a negative business revision or capture time never becomes a usable directory', () async {
    final cases = <({String label, int settingsRevision, int updatedAt})>[
      (
        label: 'negative settings revision',
        settingsRevision: -1,
        updatedAt: _materialUpdatedAt,
      ),
      (
        label: 'negative capture time',
        settingsRevision: _settingsRevision,
        updatedAt: -1,
      ),
    ];

    for (final entry in cases) {
      final fixture = AcpConfigurationFixture();
      addTearDown(() async {
        // 若 SDK 选择在源状态边界拒绝该帧，被拒绝的原生帧只保留它自己的收尾责任；
        // 这里不要求整份报告为空，也不允许它冒充 Clean 之外的其他结论。
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        final report = await fixture.repository.close(deadline: deadline);
        expect(
          report.unresolved.every(
            (resource) => resource.owner == 'configuration:feed',
          ),
          isTrue,
        );
        await fixture.modelsRepository.close(deadline: deadline);
      });
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      // 投影戳是合法水位；非法的是被冻结 header 里的业务版本/捕获时间，它们是目录
      // revision/time 的唯一来源，因此这里验证的正是该材料边界的拒绝行为。
      //
      // 这个环境不预设 SDK 用哪一种合法方式拒绝（在源状态边界拒绝该 header，或在目录
      // 校验处拒绝），因此不等待可能永远不会到来的 ACK，只看可观察后果。
      //
      // 需求必须先到：读取会触发订阅打开，随后才发布这份业务版本非法的基线。
      final expectation = expectLater(
        fixture.repository.loadAcpAccounts(),
        throwsA(
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'code',
                StudioFailureCode.protocol,
              )
              .having(
                (failure) => failure.correlationId,
                'correlationId',
                'configuration',
              ),
        ),
        reason: '${entry.label}: 非法业务版本/时间不得进入可用目录',
      );
      await fixture.port.publishBaseline(
        settingsRevision: entry.settingsRevision,
        materialRevision: _settingsRevision,
        updatedAt: entry.updatedAt,
        projectionRevision: _settingsRevision,
        awaitAcknowledgement: false,
      );
      await pumpEventQueue();
      final frozen = fixture.repository.state.value.projection.header;
      if (frozen != null) {
        expect(
          frozen.configurationRevision,
          entry.settingsRevision,
          reason: '${entry.label}: 被采纳的 header 原样保留非法业务版本，不被改写成可用值',
        );
        expect(frozen.updatedAt, entry.updatedAt);
      }

      await expectation;
      if (frozen != null) {
        expect(
          fixture.port.scopes,
          hasLength(1),
          reason: '${entry.label}: 材料本身可读，拒绝来自目录校验而不是不可读的 scope',
        );
        expect(
          fixture
              .repository
              .state
              .value
              .projection
              .header
              ?.configurationRevision,
          entry.settingsRevision,
          reason: '${entry.label}: 失败后仍不伪造可用版本',
        );
      }
    }
  });

  test(
    'paging and long deferred text stay bounded by the declared material',
    () async {
      final fixture = AcpConfigurationFixture();
      addTearDown(() => _close(fixture));
      final longName = '接入账号名称' * 700; // 4200 个 CJK 字符，UTF-8 远超内联上限
      fixture.port.materials[_settingsRevision] = _material(
        [
          _row('acct-a', name: longName),
          _row('acct-b', name: 'B'),
          _row('acct-c', name: 'C'),
        ],
        pageSize: 2,
        chunkBytes: 512,
      );
      final directory = await _loadWithBaseline(fixture);
      final scope = await fixture.port.scopeOpened(0);

      expect(directory.accounts.map((account) => account.accountId), [
        'acct-a',
        'acct-b',
        'acct-c',
      ]);
      expect(
        directory.account('acct-a')!.name,
        longName,
        reason: '分块文本按连续偏移完整拼接',
      );
      expect(scope.pages.map((call) => call.offset), [
        0,
        2,
      ], reason: '按材料的页大小连续读到总量为止');
      expect(scope.pages.every((call) => call.listId == 11), isTrue);
      final nameCalls = scope.texts
          .where((call) => call.fieldId == acpAccountNameField(0))
          .toList();
      expect(nameCalls.length, greaterThan(1), reason: '超长名称由多块组成，而不是被截断');
      expect(nameCalls.every((call) => call.maxBytes <= 65536), isTrue);
      expect(
        nameCalls.map((call) => call.offset).toSet().length,
        nameCalls.length,
        reason: '每块都从上一块的结束偏移继续',
      );
    },
  );

  test(
    'a load keeps the frozen header even when the settings revision advances',
    () async {
      final fixture = AcpConfigurationFixture();
      addTearDown(() => _close(fixture));
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      fixture.port.headerGate = (index) => index == 0 ? Completer() : null;
      final reading = fixture.repository.loadAcpAccounts();
      await _establish(fixture, settingsRevision: 7, materialRevision: 7);
      final scope = await fixture.port.scopeOpened(0);
      // 读取已受理但尚未完成时，Settings revision 前进而材料引用不变。
      await fixture.port.publishChange(
        settingsRevision: 8,
        materialRevision: 7,
        updatedAt: 99,
      );
      scope.headerGate!.complete();

      final directory = await reading;
      expect(
        directory.revision,
        7,
        reason: '目录报告的是受理时冻结的 Settings 版本，不是 await 之后的 latest',
      );
      expect(directory.updatedAt, _materialUpdatedAt);
      expect(
        directory.origin,
        fixture.port.scopeOpens.single.origin,
        reason: '来源仍是受理时固定的那个 owner',
      );
      expect(
        directory.reference,
        fixture.port.scopeOpens.single.reference,
        reason: '引用仍是受理时固定的材料身份：Settings 已前进到 8，材料引用仍是 7',
      );
      expect(
        directory.reference.revision,
        _settingsRevision,
        reason: '材料引用仍是冻结时的 7；Settings 已前进到 8，两者独立且不要求相等',
      );
      expect(
        fixture.repository.state.value.projection.header?.configurationRevision,
        8,
        reason: 'canonical 已前进，说明目录没有读取 latest',
      );
      expect(directory.accounts.single.accountId, 'acct-work');
    },
  );

  test('a load whose header is replaced re-reads at most once and never mixes materials', () async {
    final fixture = AcpConfigurationFixture();
    addTearDown(() => _close(fixture));
    fixture.port.materials[7] = _material([_row('acct-old')]);
    fixture.port.materials[8] = _material([
      _row('acct-new'),
      _row('acct-new-2'),
    ]);
    fixture.port.headerGate = (index) => Completer();
    final reading = fixture.repository.loadAcpAccounts();
    await _establish(fixture, settingsRevision: 7, materialRevision: 7);
    final first = await fixture.port.scopeOpened(0);
    // 原 header 被替换：材料引用前进到 8。
    await fixture.port.publishChange(
      settingsRevision: 8,
      materialRevision: 8,
      updatedAt: 12,
    );
    first.headerGate!.complete();
    final second = await fixture.port.scopeOpened(1);
    second.headerGate!.complete();

    final directory = await reading;
    expect(directory.accounts.map((account) => account.accountId), [
      'acct-new',
      'acct-new-2',
    ], reason: '只采用新的固定材料，不混用旧 scope 的行');
    expect(directory.revision, 8);
    expect(directory.updatedAt, 12);
    expect(
      directory.origin,
      fixture.port.scopeOpens.last.origin,
      reason: '返回的目录绑定替换后那次真实固定读取的来源',
    );
    expect(
      directory.reference,
      fixture.port.scopeOpens.last.reference,
      reason: '返回的目录绑定替换后那次真实固定读取的材料引用',
    );
    expect(
      directory.reference,
      isNot(fixture.port.scopeOpens.first.reference),
      reason: '被替换后不复用旧材料引用：旧目录不能被补成当前引用',
    );
    expect(fixture.port.scopes, hasLength(2), reason: '被替换后只做一次有界重取');
    expect(fixture.port.scopeOpens.map((open) => open.reference.revision), [
      7,
      8,
    ], reason: '两次固定读取各自绑定当时冻结的材料版本');
    expect(first.headerCalls, 1);
  });

  test('a load that keeps losing its header reports superseded after two fixed reads', () async {
    final fixture = AcpConfigurationFixture();
    addTearDown(() => _close(fixture));
    fixture.port.materials[7] = _material([_row('acct-7')]);
    fixture.port.materials[8] = _material([_row('acct-8')]);
    fixture.port.materials[9] = _material([_row('acct-9')]);
    fixture.port.headerGate = (index) => Completer();
    final reading = fixture.repository.loadAcpAccounts();
    await _establish(fixture, settingsRevision: 7, materialRevision: 7);
    final first = await fixture.port.scopeOpened(0);
    await fixture.port.publishChange(
      settingsRevision: 8,
      materialRevision: 8,
      updatedAt: 12,
    );
    first.headerGate!.complete();
    final second = await fixture.port.scopeOpened(1);
    await fixture.port.publishChange(
      settingsRevision: 9,
      materialRevision: 9,
      updatedAt: 13,
    );
    // 先挂上判定再放行最后一次读取，避免失败先于监听到达。
    final expectation = expectLater(
      reading,
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.superseded,
            )
            .having((failure) => failure.retryable, 'retryable', isTrue),
      ),
    );
    second.headerGate!.complete();
    await expectation;
    expect(fixture.port.scopes, hasLength(2), reason: '重取次数有界，不无限追赶最新材料');
    expect(fixture.port.scopeOpens.map((open) => open.reference.revision), [
      7,
      8,
    ], reason: '两次固定读取各绑定当时声明的材料，不去追第三次声明');
    final projection = fixture.repository.state.value.projection;
    expect(
      projection.header?.configurationRevision,
      9,
      reason: '读取失败不改写 Settings 事实',
    );
    expect(
      projection.stamp?.ownerEpoch,
      acpConfigurationOrigin.ownerEpoch,
      reason: '没有返回任何目录，也就没有把旧 owner 的目录补成本次来源',
    );
  });

  test(
    'saveAcpAccount consumes the captured target and then covers the receipt',
    () async {
      final fixture = AcpConfigurationFixture();
      addTearDown(() => _close(fixture));
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work', name: 'Work', connectionRevision: 2),
      ]);
      fixture.port.headerGate = (index) => index == 0 ? Completer() : null;
      const update = AcpAccountUpdate(
        accountId: 'acct-new',
        name: 'Work',
        provider: AcpProvider.antigravity,
      );
      final ticket = fixture.repository.saveAcpAccount(update);
      await _establish(fixture);
      final call = await fixture.port.saved(0);
      expect(call.request.operationId, ticket.id);
      expect(
        call.request.expectedRevision,
        _settingsRevision,
        reason: '写入冻结受理时的 Settings 版本',
      );
      expect(call.request.account, update, reason: '受理的意图被冻结，不随调用方对象变化');

      final receipt = settingsAcpAccountReceipt(ticket.id, revision: 8);
      call.native.accept(
        0,
        AcpAccountCommandReply(
          receipt: receipt,
          configuration: acpConfigurationTarget(_settingsRevision),
        ),
      );

      // 回复已到：必须先按原目标读完目录，再等 settings 水位覆盖回执。
      // 这里只断言顺序（目录读取完成在前、回执观察在后），不断言 receipt 被观察了几次：
      // 目录读取与 Settings 水位覆盖属于同一次已受理写入的证据链，重复观察是生产侧要修
      // 的缺陷，不应被测试固化成预期。
      final scope = await fixture.port.scopeOpened(0);
      await pumpEventQueue();
      expect(scope.headerCalls, 1, reason: '观察先按原目标读取元数据头');
      expect(scope.pages, isEmpty, reason: 'settings 水位尚未覆盖，不提前完成观察');
      scope.headerGate!.complete();
      await pumpEventQueue();
      expect(scope.pages, isNotEmpty, reason: '原目标的目录页被真实读取');
      expect(
        fixture.repository.state.value.projection.header?.configurationRevision,
        _settingsRevision,
        reason: '目录读取本身不推进 Settings 水位',
      );

      await fixture.port.publishChange(
        settingsRevision: 8,
        materialRevision: _settingsRevision,
        updatedAt: _materialUpdatedAt,
      );

      final result = await ticket.result;
      expect(result, isA<CommittedCommandResult<Unit>>());
      final committed = result as CommittedCommandResult<Unit>;
      expect(committed.receipt, receipt);
      expect(
        committed.receipt.targets.single,
        isA<ResourceStamp>().having(
          (stamp) => stamp.resourceKey,
          'resourceKey',
          settingsResourceKey,
        ),
      );
      expect(fixture.port.saves, hasLength(1));
      expect(
        fixture.repository.state.value.projection.header?.configurationRevision,
        8,
      );
    },
  );

  test('a committed write whose captured target cannot be read settles without rewriting', () async {
    final fixture = AcpConfigurationFixture();
    fixture.port.materials[_settingsRevision] = _material([
      _row('acct-work'),
      _row('acct-work'),
    ]);
    final ticket = fixture.repository.saveAcpAccount(
      const AcpAccountUpdate(
        accountId: 'acct-new',
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
    );
    await _establish(fixture);
    final call = await fixture.port.saved(0);
    final receipt = settingsAcpAccountReceipt(ticket.id, revision: 8);
    call.native.accept(
      0,
      AcpAccountCommandReply(
        receipt: receipt,
        configuration: acpConfigurationTarget(_settingsRevision),
      ),
    );

    // 回复已经返回：ticket 必须在原目标读取失败时结算，而不是留在途。
    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<Unit>>());
    final settled = result as SyncFailedCommandResult<Unit>;
    expect(settled.receipt, receipt, reason: '已确认的 Settings 回执被保留为证据');
    expect(settled.error.code, StudioFailureCode.protocol);
    final state = ticket.state.value;
    expect(state.failurePhase, OperationFailurePhase.syncFailed);
    expect(state.observed, isFalse, reason: '读取失败不能冒充已验证的提交');
    expect(state.isPending, isTrue);
    expect(
      fixture.repository.state.value.projection.header?.configurationRevision,
      _settingsRevision,
      reason: 'target 读取失败不推进 Settings 水位',
    );
    expect(fixture.port.saves, hasLength(1), reason: '读取失败不重新保存');

    addTearDown(() async {
      final operation = await _closeUnresolved(fixture, ticket.id);
      expect(operation.issues.single.diagnostic.code, 'syncFailed');
      expect(
        operation.issues.single.recovery,
        CleanupRecovery.retryClose,
        reason: '原调用在显式关闭前保留真实收尾责任',
      );
    });
  });

  test('a malformed Settings receipt keeps the real receipt but never claims success', () async {
    final fixture = AcpConfigurationFixture();
    fixture.port.materials[_settingsRevision] = _material([_row('acct-work')]);
    final ticket = fixture.repository.saveAcpAccount(
      const AcpAccountUpdate(
        accountId: 'acct-new',
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
    );
    await _establish(fixture);
    addTearDown(() async {
      final operation = await _closeUnresolved(fixture, ticket.id);
      expect(operation.issues.single.diagnostic.code, 'syncFailed');
    });
    final call = await fixture.port.saved(0);
    // 真实 Settings 回执必须只有一个 settings 目标；这里多带一个 ViewStamp，
    // 它单独看是合法观察身份，一起出现时就不是这份写入可以消费的回执。
    final settingsStamp = ResourceStamp(
      resourceKey: settingsResourceKey,
      ownerEpoch: acpConfigurationOrigin.ownerEpoch,
      revision: 8,
    );
    final receipt = CommitReceipt(
      operationId: ticket.id,
      disposition: CommitDisposition.applied,
      targets: [
        settingsStamp,
        const ViewStamp(
          threadId: 'thread-1',
          viewId: 'timeline',
          viewEpoch: 'view-epoch-1',
          version: 3,
        ),
      ],
      effect: EffectPoint.immediate,
    );
    call.native.accept(
      0,
      AcpAccountCommandReply(
        receipt: receipt,
        configuration: acpConfigurationTarget(_settingsRevision),
      ),
    );
    // 即使 Settings 水位随后前进，这份回执也不能被当作已完成的写入。
    await fixture.port.publishChange(
      settingsRevision: 8,
      materialRevision: _settingsRevision,
      updatedAt: _materialUpdatedAt,
    );

    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<Unit>>());
    final settled = result as SyncFailedCommandResult<Unit>;
    expect(settled.receipt, receipt, reason: '不可用的回执原样保留，不替换成别的身份');
    expect(settled.receipt.targets, [
      settingsStamp,
      receipt.targets.last,
    ], reason: '原 targets 顺序与内容保持不变（settings + 一个 view 观察）');
    expect(
      settled.receipt.targets.whereType<ViewStamp>(),
      hasLength(1),
      reason: '多出来的观察身份没有被抹掉，也没有被当作 Settings 目标',
    );
    expect(settled.error.code, StudioFailureCode.protocol);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(ticket.state.value.observed, isFalse);
    expect(fixture.port.saves, hasLength(1));
    expect(fixture.port.scopes, isEmpty, reason: '回执形状非法时不读取任何配置目标');
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('a reply target from another owner is refused before the directory is opened', () async {
    final fixture = AcpConfigurationFixture();
    // 两份材料各自合法：Settings 所有者一份，另一个所有者名下也声明了一份，
    // 这样“拒绝”与“误读另一份材料”在结果上可区分。
    fixture.port.materials[_settingsRevision] = _material([_row('acct-work')]);
    final ticket = fixture.repository.saveAcpAccount(
      const AcpAccountUpdate(
        accountId: 'acct-new',
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
    );
    await _establish(fixture);
    addTearDown(() async {
      final operation = await _closeUnresolved(fixture, ticket.id);
      expect(operation.issues.single.diagnostic.code, 'syncFailed');
    });
    final call = await fixture.port.saved(0);
    final receipt = settingsAcpAccountReceipt(ticket.id, revision: 8);
    // 回执属于 Settings 所有者，读取目标却指向另一个 owner epoch：两者各自形状合法，
    // 各自也能满足自己的 read/observe，但混用会把别的所有者的目录当作本写入的材料。
    final foreignTarget = ConfigurationReadTarget(
      origin: const ProductReadOrigin(
        ownerEpoch: 'acp-configuration-other',
        incarnation: 1,
      ),
      reference: ConfigurationReadRef(
        entry: acpConfigurationEntry,
        revision: _settingsRevision,
      ),
    );
    call.native.accept(
      0,
      AcpAccountCommandReply(receipt: receipt, configuration: foreignTarget),
    );
    // Settings 水位前进也不改变结论：另一所有者的目标不是本写入的材料。
    await fixture.port.publishChange(
      settingsRevision: 8,
      materialRevision: _settingsRevision,
      updatedAt: _materialUpdatedAt,
    );

    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<Unit>>());
    final settled = result as SyncFailedCommandResult<Unit>;
    expect(settled.receipt, receipt, reason: '真实 Settings 回执被保留为证据');
    expect(settled.error.code, StudioFailureCode.protocol);
    expect(fixture.port.scopes, isEmpty, reason: '在打开原目录之前就拒绝跨所有者的材料');
    expect(
      fixture.port.scopeOpens,
      isEmpty,
      reason: '没有为另一个 owner epoch 固定过读取作用域',
    );
    expect(fixture.port.saves, hasLength(1), reason: '不重新保存');
    final projection = fixture.repository.state.value.projection;
    expect(
      projection.stamp?.ownerEpoch,
      acpConfigurationOrigin.ownerEpoch,
      reason: 'Settings 投影仍只属于它自己的所有者',
    );
    expect(ticket.state.value.observed, isFalse);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test(
    'a receipt naming another operation never settles as a known commit',
    () async {
      final fixture = AcpConfigurationFixture();
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      final ticket = fixture.repository.saveAcpAccount(
        const AcpAccountUpdate(
          accountId: 'acct-new',
          name: 'Work',
          provider: AcpProvider.antigravity,
        ),
      );
      await _establish(fixture);
      addTearDown(() async {
        final operation = await _closeUnresolved(fixture, ticket.id);
        expect(operation.issues.single.diagnostic.code, 'syncFailed');
      });
      final call = await fixture.port.saved(0);
      call.native.accept(
        0,
        AcpAccountCommandReply(
          receipt: settingsAcpAccountReceipt(
            const OperationId('an-other-operation'),
            revision: 8,
          ),
          configuration: acpConfigurationTarget(_settingsRevision),
        ),
      );

      final result = await ticket.result;
      expect(result, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
      final settled = result as AcknowledgedSyncFailedCommandResult<Unit>;
      expect(settled.error.code, StudioFailureCode.protocol);
      expect(settled.value, isNull, reason: '无法映射的回执不产出受理值');
      final state = ticket.state.value;
      expect(state.acknowledged, isTrue);
      expect(state.receipt, isNull, reason: '另一个操作的回执不能成为本操作证据');
      expect(state.observed, isFalse);
      expect(fixture.port.saves, hasLength(1), reason: '不重发第二次提交');
    },
  );

  test(
    'a lost begin reply is an unknown outcome that is never resent',
    () async {
      final fixture = AcpConfigurationFixture();
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      fixture.port
        ..loseSaveReply = true
        ..originalCallRegistered = false;

      final ticket = fixture.repository.saveAcpAccount(
        const AcpAccountUpdate(
          accountId: 'acct-new',
          name: 'Work',
          provider: AcpProvider.antigravity,
        ),
      );
      await _establish(fixture);
      final result = await ticket.result;

      expect(result, isA<UnknownOutcomeCommandResult<Unit>>());
      expect(
        (result as UnknownOutcomeCommandResult<Unit>).error,
        fixture.port.lostReplyFailure,
      );
      final state = ticket.state.value;
      expect(state.failurePhase, OperationFailurePhase.unknownOutcome);
      expect(state.isPending, isTrue);
      expect(state.receipt, isNull);
      expect(fixture.port.saves, hasLength(1), reason: '响应丢失不构成第二次提交的授权');
      expect(fixture.port.findCalls, [ticket.id], reason: '只查找原操作的调用');

      addTearDown(() async {
        final operation = await _closeUnresolved(fixture, ticket.id);
        expect(operation.issues.single.diagnostic.code, 'unknownOutcome');
      });
    },
  );

  test(
    'a lost begin reply joins the original call instead of committing twice',
    () async {
      final fixture = AcpConfigurationFixture();
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      fixture.port.loseSaveReply = true;

      final ticket = fixture.repository.saveAcpAccount(
        const AcpAccountUpdate(
          accountId: 'acct-new',
          name: 'Work',
          provider: AcpProvider.antigravity,
        ),
      );
      await _establish(fixture);
      final call = await fixture.port.saved(0);
      final receipt = settingsAcpAccountReceipt(ticket.id, revision: 8);
      call.native.accept(
        0,
        AcpAccountCommandReply(
          receipt: receipt,
          configuration: acpConfigurationTarget(_settingsRevision),
        ),
      );
      await fixture.port.publishChange(
        settingsRevision: 8,
        materialRevision: _settingsRevision,
        updatedAt: _materialUpdatedAt,
      );

      final result = await ticket.result;
      expect(result, isA<CommittedCommandResult<Unit>>());
      expect(
        (result as CommittedCommandResult<Unit>).receipt,
        receipt,
        reason: '加入的原调用带来了它自己的真实回执',
      );
      expect(fixture.port.saves, hasLength(1), reason: '没有第二次提交');
      expect(fixture.port.findCalls, [ticket.id]);

      await pumpEventQueue();
      expect(
        call.native.closeCalls + call.native.retryCloseCalls,
        greaterThanOrEqualTo(1),
        reason: '原调用被真实关闭，而不是丢掉句柄',
      );
      addTearDown(() => _close(fixture));
    },
  );

  test(
    'a refused write is rejected and leaves no optimistic Settings edit',
    () async {
      final fixture = AcpConfigurationFixture();
      addTearDown(() => _close(fixture));
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      final ticket = fixture.repository.saveAcpAccount(
        const AcpAccountUpdate(
          accountId: 'acct-new',
          name: 'Work',
          provider: AcpProvider.antigravity,
        ),
      );
      await _establish(fixture);
      final call = await fixture.port.saved(0);
      call.native.reject(
        0,
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );

      final result = await ticket.result;
      expect(result, isA<RejectedCommandResult<Unit>>());
      expect((result as RejectedCommandResult<Unit>).error, _nativeRefusal);
      expect(ticket.state.value.receipt, isNull);
      expect(
        fixture.repository.state.value.projection.header?.configurationRevision,
        _settingsRevision,
        reason: '被拒绝的写入不产生乐观 canonical 编辑',
      );
      expect(fixture.port.saves, hasLength(1));
      expect(fixture.port.scopes, isEmpty, reason: '被拒绝的写入不读取任何目标');
      await pumpEventQueue();
      expect(
        call.native.closeCalls + call.native.retryCloseCalls,
        greaterThanOrEqualTo(1),
        reason: '被拒绝的原调用仍被真实关闭',
      );
    },
  );

  test('removeAcpAccount uses the same lane and only the account id', () async {
    final fixture = AcpConfigurationFixture();
    addTearDown(() => _close(fixture));
    fixture.port.materials[_settingsRevision] = _material([_row('acct-old')]);
    final ticket = fixture.repository.removeAcpAccount('acct-old');
    await _establish(fixture);
    final call = await fixture.port.removed(0);
    expect(call.request.operationId, ticket.id);
    expect(call.request.expectedRevision, _settingsRevision);
    expect(call.request.accountId, 'acct-old');

    final receipt = settingsAcpAccountReceipt(ticket.id, revision: 8);
    call.native.accept(
      0,
      AcpAccountCommandReply(
        receipt: receipt,
        configuration: acpConfigurationTarget(_settingsRevision),
      ),
    );
    await fixture.port.publishChange(
      settingsRevision: 8,
      materialRevision: _settingsRevision,
      updatedAt: _materialUpdatedAt,
    );

    expect(await ticket.result, isA<CommittedCommandResult<Unit>>());
    final scope = await fixture.port.scopeOpened(0);
    expect(scope.pages, isNotEmpty, reason: '删除同样消费本次提交捕获的原目标行集');
  });

  test(
    'the writable ACP account intent carries no execution entry point',
    () async {
      const update = AcpAccountUpdate(
        accountId: 'acct-new',
        name: 'Work',
        provider: AcpProvider.antigravity,
      );
      expect(
        update.copyWith(name: 'Renamed'),
        const AcpAccountUpdate(
          accountId: 'acct-new',
          name: 'Renamed',
          provider: AcpProvider.antigravity,
        ),
        reason: '改名只改名称，不改变 provider 与身份',
      );
      final AcpAccountUpdate(:accountId, :name, :provider) = update;
      expect(
        [accountId, name, provider],
        ['acct-new', 'Work', AcpProvider.antigravity],
      );

      final fixture = AcpConfigurationFixture();
      addTearDown(() => _close(fixture));
      fixture.port.materials[_settingsRevision] = _material([
        _row('acct-work'),
      ]);
      final ticket = fixture.repository.saveAcpAccount(update);
      await _establish(fixture);
      final call = await fixture.port.saved(0);
      final surface = call.request.account.toString();
      expect(surface, contains('accountId'));
      expect(surface, contains('provider'));
      for (final excluded in [
        'program',
        'argv',
        'args',
        'version',
        'baseUrl',
      ]) {
        expect(
          surface,
          isNot(contains(excluded)),
          reason: '线协议意图没有 $excluded 字段',
        );
      }
      call.native.reject(
        0,
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );
      await ticket.result;
    },
  );
}
