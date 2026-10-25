import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/composer_view_model.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/timeline_drafts_environment.dart';

void main() {
  test('observing a missing Thread composer fails without creating a draft', () async {
    final fixture = TimelineDraftsEnvironment();
    addTearDown(fixture.close);
    final container = _container(fixture);
    addTearDown(container.dispose);
    final draftsBefore = fixture.budget.used(ResourceKind.draft);
    final provider = composerViewModelProvider(const ComposerKey.thread(threadId: 'missing'));
    final observation = container.listen(provider, (_, _) {});
    addTearDown(observation.close);

    await expectLater(container.read(provider.future), throwsA(isA<StudioFailure>()));

    expect(container.read(provider).hasError, isTrue);
    expect(fixture.budget.used(ResourceKind.draft), draftsBefore);
    expect(fixture.budget.usage.where((use) => use.owner == 'composer:missing'), isEmpty);
    expect(fixture.conversations.repository.existingSession('missing'), isNull);
    expect(fixture.conversations.context.metadataRequests, isEmpty);
    expect(fixture.conversations.timeline.requests, isEmpty);

    // A later canonical selection, not a second existence cache or a route
    // refresh, makes this same observer eligible to admit its real draft.
    fixture.conversations.select('missing');
    (await fixture.conversations.timeline.opened(0)).result.complete(
      TestTimelineConnection(initial: baseline(1, items: const [])),
    );
    await container.pump();
    expect((await container.read(provider.future)).draft, isNotNull);
    expect(fixture.budget.used(ResourceKind.draft), draftsBefore + 1);
  });

  test('observing an existing Thread creates one canonical editable composer draft', () async {
    final fixture = TimelineDraftsEnvironment();
    addTearDown(fixture.close);
    // Obtaining the real Session is explicit application admission. The
    // Composer observer itself must not create/activate one on either path.
    final session = fixture.conversations.repository.session('existing');
    final container = _container(fixture);
    addTearDown(container.dispose);
    final draftsBefore = fixture.budget.used(ResourceKind.draft);
    final provider = composerViewModelProvider(const ComposerKey.thread(threadId: 'existing'));
    final observation = container.listen(provider, (_, _) {});
    final view = await container.read(provider.future);
    expect(view.draft, isNotNull);
    expect(fixture.budget.used(ResourceKind.draft), draftsBefore + 1);
    expect(fixture.conversations.repository.existingSession('existing'), same(session));

    container.read(provider.notifier).setText('keep this raw draft');
    final draft = fixture.repository.composer('existing');
    expect(draft.state.value.text, 'keep this raw draft');
    observation.close();
    await container.pump();
    expect(draft.state.value.text, 'keep this raw draft', reason: 'observer disposal never discards authoring');
    final rebuilt = container.listen(provider, (_, _) {});
    addTearDown(rebuilt.close);
    expect((await container.read(provider.future)).draft?.text, 'keep this raw draft');
    expect(fixture.repository.composer('existing'), same(draft));
    expect(fixture.budget.used(ResourceKind.draft), draftsBefore + 1);
    expect(fixture.conversations.context.metadataRequests, isEmpty);
    expect(fixture.conversations.timeline.requests, isEmpty);
  });
}

ProviderContainer _container(TimelineDraftsEnvironment fixture) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    draftsRepositoryProvider.overrideWithValue(fixture.repository),
    conversationRepositoryProvider.overrideWithValue(fixture.conversations.repository),
  ],
);
