import 'package:anywork/src/features/settings/settings_provider_draft_save.dart';
import 'package:anywork/src/features/settings/settings_provider_usage_demand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderUsageAutoDemand', () {
    test('visible first pass requests every identity concurrently once', () {
      final demand = ProviderUsageAutoDemand();
      final started = <String>[];
      final needed = demand.apply(
        visible: true,
        providers: const [
          ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
          ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ],
        refresh: started.add,
      );
      expect(needed, ['a', 'b']);
      expect(started, ['a', 'b']);
      expect(
        demand.apply(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
            ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
          ],
          refresh: started.add,
        ),
        isEmpty,
      );
      expect(started, ['a', 'b']);
    });

    test(
      'hidden identity changes wait until visible and only refresh self',
      () {
        final demand = ProviderUsageAutoDemand();
        expect(
          demand.sync(
            visible: true,
            providers: const [
              ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
              ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
            ],
          ),
          ['a', 'b'],
        );
        expect(
          demand.sync(
            visible: false,
            providers: const [
              ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
              ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
              ProviderUsageQueryIdentity(id: 'c', usageQueryRevision: 1),
            ],
          ),
          isEmpty,
        );
        expect(
          demand.sync(
            visible: true,
            providers: const [
              ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
              ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
              ProviderUsageQueryIdentity(id: 'c', usageQueryRevision: 1),
            ],
          ),
          ['a', 'c'],
        );
      },
    );

    test('failed identity is not retried until revision or page rebuild', () {
      final demand = ProviderUsageAutoDemand();
      expect(
        demand.sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 3),
          ],
        ),
        ['a'],
      );
      expect(
        demand.sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 3),
          ],
        ),
        isEmpty,
      );
      expect(
        ProviderUsageAutoDemand().sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 3),
          ],
        ),
        ['a'],
      );
    });

    test('deleted providers drop attempted identity', () {
      final demand = ProviderUsageAutoDemand();
      expect(
        demand.sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'keep', usageQueryRevision: 1),
            ProviderUsageQueryIdentity(id: 'gone', usageQueryRevision: 1),
          ],
        ),
        ['keep', 'gone'],
      );
      expect(
        demand.sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'keep', usageQueryRevision: 1),
          ],
        ),
        isEmpty,
      );
      expect(
        demand.sync(
          visible: true,
          providers: const [
            ProviderUsageQueryIdentity(id: 'keep', usageQueryRevision: 1),
            ProviderUsageQueryIdentity(id: 'gone', usageQueryRevision: 1),
          ],
        ),
        ['gone'],
      );
    });
  });

  group('ProviderDraftSaveSession', () {
    test('old save finally cannot lock a newer add draft', () {
      final session = ProviderDraftSaveSession();
      final first = session.begin();
      expect(session.isSaving, isTrue);
      session.abandon();
      expect(session.isSaving, isFalse);
      final second = session.begin();
      expect(session.owns(first), isFalse);
      session.succeed(first);
      expect(session.isSaving, isTrue);
      session.fail(first);
      expect(session.isSaving, isTrue);
      session.succeed(second);
      expect(session.isSaving, isFalse);
    });
  });
}
