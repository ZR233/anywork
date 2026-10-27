import 'dart:async';

import 'package:anywork_client/anywork_client.dart';
import 'package:anywork_client/models.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

/// 页/详情查询属于一个展示代次的 scope：先捕获 attempt 与许可，退役后拒绝新工作、
/// 拒绝迟到发布，并在 close 时等待真实 future 退出（design/26 §26.8）。
void main() {
  Future<
    ({
      StudioTimelineChannel channel,
      TestTimelineConnection connection,
      StudioTimelineQueryScope scope,
    })
  >
  open() async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport, budget: ResourceBudget());
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    final scope = channel.openScope(generation: 1);
    expect(scope, isNotNull);
    return (channel: channel, connection: connection, scope: scope!);
  }

  test('page 透传不透明游标与显式 limit', () async {
    final ready = await open();
    final future = ready.scope.page(before: 'tlp1.opaque', limit: 32);
    expect(ready.connection.pageRequests.single.before, 'tlp1.opaque');
    expect(ready.connection.pageRequests.single.limit, 32);
    ready.connection.pageResult!.complete(
      StudioTimelinePage(
        items: [timelineItem(2, id: 'older')],
        before: 'tlp1.next',
        hasOlder: true,
      ),
    );
    final result = await future;
    final page = result;
    expect(page.items.single.id, 'older');
    expect(page.before, 'tlp1.next');
    expect(page.hasOlder, isTrue);
    await ready.channel.close();
  });

  test('非法 limit 被拒绝而不是 clamp', () async {
    final ready = await open();
    for (final limit in [0, 101, -1]) {
      await expectLater(
        ready.scope.page(limit: limit),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
    expect(ready.connection.pageRequests, isEmpty);
    await ready.channel.close();
  });

  test('非法 maxBytes 被拒绝而不是 clamp', () async {
    final ready = await open();
    for (final maxBytes in [3, 262145, 0]) {
      await expectLater(
        ready.scope.readDetail(
          itemId: 'item',
          query: StudioTimelineDetailQuery(
            field: const ThreadTextFieldView(),
            revision: 2,
            maxBytes: maxBytes,
          ),
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
    expect(ready.connection.detailRequests, isEmpty);
    await ready.channel.close();
  });

  test('详情按绑定版本与 continuation 逐块交付', () async {
    final ready = await open();
    final first = ready.scope.readDetail(
      itemId: 'item',
      query: const StudioTimelineDetailQuery(
        field: ThreadToolResultFieldView(),
        revision: 5,
        maxBytes: 8,
      ),
    );
    final request = ready.connection.detailRequests.single;
    expect(request.itemId, 'item');
    expect(request.query.revision, 5);
    expect(request.query.maxBytes, 8);
    ready.connection.detailResult!.complete(
      const StudioTimelineDetailChunk(
        itemId: 'item',
        field: ThreadToolResultFieldView(),
        revision: 5,
        text: 'ab',
        totalBytes: 6,
        continuation: 'tld1.next',
      ),
    );
    final chunk = await first;
    expect(chunk.text, 'ab');
    expect(chunk.isLast, isFalse);
    expect(chunk.totalBytes, 6);
    await ready.channel.close();
  });

  test('scope 退役后拒绝新查询且迟到回包不发布', () async {
    final ready = await open();
    final pending = ready.scope.page();
    ready.scope.retire();
    await expectLater(ready.scope.page(), throwsA(isA<StaleTimelineScope>()));
    // 已受理的查询不会被丢弃：它真正收束后仍拒绝把结果发布给已退役的代次。
    ready.connection.pageResult!.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await expectLater(pending, throwsA(isA<StaleTimelineScope>()));
    await ready.channel.close();
  });

  test('查询许可在收束后释放，close 不完结则保留 unresolved', () async {
    final transport = TestTimelineTransport();
    final budget = ResourceBudget();
    final channel = timelineChannel(transport, budget: budget);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    final scope = channel.openScope(generation: 2)!;

    final pending = scope.page();
    expect(budget.used(ResourceKind.pendingOperation), 1);
    final report = await scope.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);

    connection.pageResult!.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    // 期限后收束的查询仍被拒绝发布，但许可只在真实收束后释放。
    await expectLater(pending, throwsA(isA<StaleTimelineScope>()));
    expect(budget.used(ResourceKind.pendingOperation), 0);
    await channel.close();
    expect(budget.used(ResourceKind.chatHandle), 0);
  });

  test('attempt 退役时已开 scope 一并退役且随 close 等待', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    final scope = channel.openScope(generation: 1)!;

    final pending = scope.page();
    // 新订阅 → 旧 attempt 退役：scope 不再活动，新工作被拒且迟到回包不发布。
    channel.refresh();
    expect(scope.isActive, isFalse);
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const StudioTimelineDetailQuery(
          field: ThreadTextFieldView(),
          revision: 1,
        ),
      ),
      throwsA(isA<StaleTimelineScope>()),
    );
    connection.pageResult!.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await expectLater(pending, throwsA(isA<StaleTimelineScope>()));
    await connection.closeCompleted.future;

    // 新 attempt 是真实订阅：用新的连接收束，channel 才能正常 close。
    final replacement = TestTimelineConnection(
      initial: baseline(4, subscriptionId: 'sub2'),
    );
    transport.opens.last.complete(replacement);
    expect((await channel.ready).baseline.subscriptionId, 'sub2');
    expect((await channel.close()).complete, isTrue);
    expect(scope.isActive, isFalse);
  });

  test('关闭的连接不再开出新 scope', () async {
    final ready = await open();
    await ready.channel.close();
    expect(ready.channel.openScope(generation: 3), isNull);
  });

  test('详情读取失败保留 typed 错误而不是空正文', () async {
    final ready = await open();
    final future = ready.scope.readDetail(
      itemId: 'item',
      query: const StudioTimelineDetailQuery(
        field: ThreadTextFieldView(),
        revision: 2,
      ),
    );
    final error = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'stale',
      retryable: false,
      correlationId: 'test',
    );
    ready.connection.detailResult!.completeError(error);
    await expectLater(future, throwsA(same(error)));
    await ready.channel.close();
  });

  test('页游标错误类型保持 typed 错误', () async {
    final ready = await open();
    final future = ready.scope.page(before: 'tlp1.bad');
    final error = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'bad cursor',
      retryable: false,
      correlationId: 'test',
    );
    ready.connection.pageResult!.completeError(error);
    await expectLater(future, throwsA(same(error)));
    await ready.channel.close();
  });

  test('close 失败时连接许可保持到显式重试', () async {
    final ready = await open();
    ready.connection.closeFailure = StateError('native close failed');
    final report = await ready.channel.close();
    expect(report.complete, isFalse);
    ready.connection.closeFailure = null;
    expect((await ready.channel.retryCleanup()).complete, isTrue);
  });

  test('native close 已返回但页查询仍在途时 channel 不提前 clean', () async {
    final transport = TestTimelineTransport();
    final budget = ResourceBudget();
    final channel = timelineChannel(transport, budget: budget);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    final scope = channel.openScope(generation: 1)!;

    final pending = scope.page();
    expect(budget.used(ResourceKind.pendingOperation), 1);

    final report = await channel.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    // 连接自身的 close 已经返回（不是靠 native close 挂起来“等”）。
    expect(connection.closeCalls, 1);
    expect(report.complete, isFalse, reason: '真实受理的页查询仍持有许可');
    expect(budget.used(ResourceKind.pendingOperation), 1);
    expect(budget.used(ResourceKind.chatHandle), 1);

    connection.pageResult!.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await expectLater(pending, throwsA(isA<StaleTimelineScope>()));
    // 查询真实收束后，清理才能归还许可并移除观察。
    expect((await channel.retryCleanup()).complete, isTrue);
    expect(budget.used(ResourceKind.pendingOperation), 0);
    expect(budget.used(ResourceKind.chatHandle), 0);
  });

  for (final detail in [false, true]) {
    test(
      'synchronous ${detail ? 'detail' : 'page'} close keeps the admitted history query joined',
      () async {
        final ready = await open();
        final budget = ready.channel.budget;
        Future<CloseReport>? closing;
        ready.connection.onQuery = () {
          closing = ready.scope.close(deadline: DateTime.now());
        };
        final pending = detail
            ? ready.scope.readDetail(
                itemId: 'item',
                query: const StudioTimelineDetailQuery(
                  field: ThreadTextFieldView(),
                  revision: 1,
                ),
              )
            : ready.scope.page();
        final rejected = expectLater(
          pending,
          throwsA(isA<StaleTimelineScope>()),
        );
        expect((await closing!).complete, isFalse);
        expect(budget.used(ResourceKind.pendingOperation), 1);
        if (detail) {
          ready.connection.detailResult!.complete(
            const StudioTimelineDetailChunk(
              itemId: 'item',
              field: ThreadTextFieldView(),
              revision: 1,
              text: 'original history',
              totalBytes: 16,
              continuation: null,
            ),
          );
        } else {
          ready.connection.pageResult!.complete(
            StudioTimelinePage(
              items: [timelineItem(1)],
              before: null,
              hasOlder: false,
            ),
          );
        }
        await rejected;
        expect((await ready.scope.close()).complete, isTrue);
        expect(budget.used(ResourceKind.pendingOperation), 0);
        await ready.channel.close();
      },
    );
  }

  test('scope 真实 join 干净后解除连接归属，不积压到整条连接关闭', () async {
    final transport = TestTimelineTransport();
    final budget = ResourceBudget();
    final channel = timelineChannel(transport, budget: budget);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;

    // 同连接多代次：每个 scope 的查询都真实收束并归还许可。
    for (var round = 0; round < 3; round++) {
      final scope = channel.openScope(generation: round + 1)!;
      final page = scope.page();
      connection.pageResult!.complete(
        const StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await expectLater(page, completes);
      expect((await scope.close()).complete, isTrue);
      expect(budget.used(ResourceKind.pendingOperation), 0);
    }
    // 干净 join 之后既没有未解决项，也不影响后续关闭。
    expect(
      (await channel.joinRetired(
        deadline: DateTime.now().add(const Duration(milliseconds: 20)),
      )).unresolved,
      isEmpty,
    );
    expect((await channel.close()).complete, isTrue);
    expect(budget.used(ResourceKind.chatHandle), 0);
  });

  test('退役 attempt 的在途查询随 joinRetired 等待而不是被集合清理丢掉', () async {
    final transport = TestTimelineTransport();
    final budget = ResourceBudget();
    final channel = timelineChannel(transport, budget: budget);
    channel.start();
    final first = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(first);
    await channel.ready;
    final scope = channel.openScope(generation: 1)!;
    final pending = scope.page();

    // 新订阅：旧 attempt 退役，但它的 scope 仍归它自己，必须等真实 future。
    channel.refresh();
    final second = TestTimelineConnection(
      initial: baseline(4, subscriptionId: 'sub2'),
    );
    transport.opens.last.complete(second);
    expect((await channel.ready).baseline.subscriptionId, 'sub2');

    final report = await channel.joinRetired(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(report.complete, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);

    first.pageResult!.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await expectLater(pending, throwsA(isA<StaleTimelineScope>()));
    expect((await channel.retryCleanup()).complete, isTrue);
    expect(budget.used(ResourceKind.pendingOperation), 0);
    await channel.close();
  });
}
