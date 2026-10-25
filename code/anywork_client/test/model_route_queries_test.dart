import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/profile_editor_fixture.dart';

/// 模型/路由选择现在是原生查询，不是客户端算法：
/// - effort 候选、目录资格（`typeSupport`/exclusions）与默认值都由 Rust 决定，
///   客户端只转发 candidate 并采用原样答复；
/// - 已配置但不可用的角色路由由 `RoleRouteRead.configured/missing` 表达；
/// - Turn 吞吐只在 feature 层按“完整同源采样”格式化（
///   `code/anywork/lib/src/features/conversation/state/thread_metrics_state.dart`）。
/// 本文件锁定客户端仍拥有的那一段：原样转发、只在 pending 期间合并、不缓存。
const _catalog = ModelCatalogReadTarget(
  origin: ProductReadOrigin(ownerEpoch: 'profile-native', incarnation: 1),
  reference: ModelCatalogReadRef(entry: 1, revision: 1),
);

const _model = AccountModelKey(accountId: 'account-0', modelId: 'model-0');

Future<ProfileEditorFixture> _fixture() async {
  final fixture = ProfileEditorFixture();
  await fixture.establish();
  addTearDown(() async {
    final report = await fixture.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(report.unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

void main() {
  test('effort selection forwards the candidate verbatim and adopts the native answer', () async {
    final fixture = await _fixture();
    final supported = fixture.models.effortAfterModelSelection(
      catalog: _catalog,
      model: _model,
      candidate: 'high',
    );
    final call = await fixture.modelPort.effortCalled(0);
    expect(call.catalog, _catalog);
    expect(call.model, _model);
    expect(call.candidate, 'high');
    call.reply.complete('high');
    expect(await supported, 'high');

    // An undeclared candidate is not filtered locally: native decides.
    final undeclared = fixture.models.effortAfterModelSelection(
      catalog: _catalog,
      model: _model,
      candidate: 'medium',
    );
    final undeclaredCall = await fixture.modelPort.effortCalled(1);
    expect(undeclaredCall.candidate, 'medium');
    undeclaredCall.reply.complete(null);
    expect(await undeclared, isNull);

    // No candidate means the native default, not a client-side first entry.
    final defaulted = fixture.models.effortAfterModelSelection(
      catalog: _catalog,
      model: _model,
      candidate: null,
    );
    final defaultedCall = await fixture.modelPort.effortCalled(2);
    expect(defaultedCall.candidate, isNull);
    defaultedCall.reply.complete('medium');
    expect(await defaulted, 'medium');
    expect(fixture.modelPort.effortCalls, hasLength(3));
  });

  test(
    'only a still-pending effort query is joined and nothing is cached',
    () async {
      final fixture = await _fixture();
      final first = fixture.models.effortAfterModelSelection(
        catalog: _catalog,
        model: _model,
        candidate: 'low',
      );
      final joined = fixture.models.effortAfterModelSelection(
        catalog: _catalog,
        model: _model,
        candidate: 'low',
      );
      expect(identical(first, joined), isTrue);
      final call = await fixture.modelPort.effortCalled(0);
      call.reply.complete('low');
      expect(await first, 'low');
      expect(await joined, 'low');

      // A settled selection is not a cache: the next query asks the original
      // catalog version again instead of reusing the earlier answer.
      final again = fixture.models.effortAfterModelSelection(
        catalog: _catalog,
        model: _model,
        candidate: 'low',
      );
      expect(identical(again, first), isFalse);
      final second = await fixture.modelPort.effortCalled(1);
      second.reply.complete('low');
      expect(await again, 'low');
      expect(fixture.modelPort.effortCalls, hasLength(2));
    },
  );
}
