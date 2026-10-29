import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test('same revision Thinking and Tool preserve whole typed terminal descriptors in either order', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    ConversationItem item(
      ConversationDescriptor descriptor, {
      bool terminal = false,
      bool saved = false,
    }) => ConversationItem(
      header: timelineItem(1).header,
      revision: 1,
      descriptor: descriptor,
      saved: saved,
      lifecycle: terminal
          ? ConversationLifecycle.terminal
          : ConversationLifecycle.streaming,
      fields: const [],
    );
    final completedAt = DateTime.utc(2026);
    final thinking = item(
      const ConversationThinkingDescriptor(
        lifecycle: StreamingThreadContentView(),
      ),
    );
    final completedThinking = item(
      ConversationThinkingDescriptor(
        lifecycle: CompletedThreadContentView(completedAt),
      ),
      terminal: true,
      saved: true,
    );
    const invocation = ConversationToolInvocation(
      toolCallId: 'call',
      name: 'tool',
    );
    const output = ConversationToolOutputDescriptor(
      exitCode: 0,
      attachments: [
        ThreadAttachmentView(
          id: 'artifact',
          modality: AttachmentModalityView.file,
          mediaType: 'text/plain',
          byteSize: 3,
          filename: 'result.txt',
        ),
      ],
    );
    final running = item(
      const ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolRunning(),
      ),
    );
    final succeeded = item(
      ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolSucceeded(
          completedAt: completedAt,
          output: output,
        ),
      ),
      terminal: true,
      saved: true,
    );
    for (final pair in [
      (thinking, completedThinking),
      (completedThinking, thinking),
    ]) {
      final result = content.mergeItem(pair.$1, pair.$2);
      expect(result.terminal, isTrue);
      expect(result.saved, isTrue);
      expect(
        (result.descriptor as ConversationThinkingDescriptor).lifecycle,
        isA<CompletedThreadContentView>().having(
          (state) => state.completedAt,
          'completion time',
          completedAt,
        ),
      );
    }
    for (final pair in [(running, succeeded), (succeeded, running)]) {
      final result = content.mergeItem(pair.$1, pair.$2);
      expect(result.terminal, isTrue);
      expect(result.saved, isTrue);
      final state =
          (result.descriptor as ConversationToolDescriptor).state
              as ConversationToolSucceeded;
      expect(state.completedAt, completedAt);
      expect(state.output.exitCode, 0);
      expect(state.output.attachments.single.id, 'artifact');
      expect(state.output.attachments.single.filename, 'result.txt');
    }
    // The same typed rule applies to an atomic Update, not only Add/page merge.
    final reduced = content.reduceItem(
      succeeded,
      const ConversationUpdateItem(
        itemId: 'item',
        expectedRevision: 1,
        revision: 1,
        saved: false,
        lifecycle: ConversationLifecycle.streaming,
        descriptor: ConversationToolDescriptor(
          invocation: invocation,
          state: ConversationToolRunning(),
        ),
        fields: [],
      ),
    );
    expect(
      (reduced.descriptor as ConversationToolDescriptor).state,
      isA<ConversationToolSucceeded>(),
    );
    expect(reduced.saved, isTrue);
    expect(reduced.terminal, isTrue);
    await fixture.close();
  });

  test('same revision incompatible typed terminal, static identity and nonterminal facts require resync', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    ConversationItem item(
      ConversationDescriptor descriptor, {
      bool terminal = true,
    }) => ConversationItem(
      header: timelineItem(1).header,
      revision: 1,
      descriptor: descriptor,
      saved: false,
      lifecycle: terminal
          ? ConversationLifecycle.terminal
          : ConversationLifecycle.streaming,
      fields: const [],
    );
    final date = DateTime.utc(2026);
    final text = item(
      ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: CompletedThreadContentView(date),
      ),
    );
    final failedText = item(
      ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: FailedThreadContentView(date, 'failed'),
      ),
    );
    final thinking = item(
      ConversationThinkingDescriptor(
        lifecycle: CompletedThreadContentView(date),
      ),
    );
    final failedThinking = item(
      ConversationThinkingDescriptor(
        lifecycle: FailedThreadContentView(date, 'failed'),
      ),
    );
    const invocation = ConversationToolInvocation(
      toolCallId: 'call',
      name: 'tool',
    );
    final success = item(
      ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolSucceeded(
          completedAt: date,
          output: const ConversationToolOutputDescriptor(
            attachments: [],
            exitCode: 0,
          ),
        ),
      ),
    );
    final failure = item(
      ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolFailed(
          failedAt: date,
          failure: const ThreadToolFailureView(
            kind: ThreadToolFailureKindView.execution,
            message: 'failed',
          ),
        ),
      ),
    );
    final changedOutput = item(
      ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolSucceeded(
          completedAt: date,
          output: const ConversationToolOutputDescriptor(
            attachments: [],
            exitCode: 1,
          ),
        ),
      ),
    );
    final running = item(
      const ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolRunning(),
      ),
      terminal: false,
    );
    final streaming = item(
      const ConversationToolDescriptor(
        invocation: invocation,
        state: ConversationToolStreaming(),
      ),
      terminal: false,
    );
    final differentIdentity = item(
      const ConversationToolDescriptor(
        invocation: ConversationToolInvocation(
          toolCallId: 'other',
          name: 'tool',
        ),
        state: ConversationToolRunning(),
      ),
      terminal: false,
    );
    for (final pair in [
      (text, failedText),
      (thinking, failedThinking),
      (success, failure),
      (success, changedOutput),
      (running, streaming),
      (running, differentIdentity),
    ]) {
      for (final order in [pair, (pair.$2, pair.$1)]) {
        expect(
          () => content.mergeItem(order.$1, order.$2),
          throwsA(isA<ConversationContinuityError>()),
        );
      }
    }
    await fixture.close();
  });

  test(
    'same revision independent previews converge without a second body mirror',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final partial = timelineItem(4, body: 'a', totalBytes: 4);
      final fuller = timelineItem(
        4,
        body: 'abc\n',
        totalBytes: 4,
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
      );
      final result = content.mergeItem(partial, fuller);
      expect(result.fields.single.text, 'abc\n');
      expect(result.saved, isTrue);
      expect(result.terminal, isTrue);
      expect(result.omittedBytes, 0);
      final latePartial = content.mergeItem(result, partial);
      expect(latePartial.fields.single.text, 'abc\n');
      expect(latePartial.saved, isTrue);
      expect(latePartial.terminal, isTrue);
      expect(
        (latePartial.descriptor as ConversationTextDescriptor).lifecycle,
        isA<CompletedThreadContentView>(),
      );
      expect(
        (result.descriptor as ConversationTextDescriptor).lifecycle,
        isA<CompletedThreadContentView>(),
      );
      expect(latePartial.details.single.revision, 4);
      await fixture.close();
    },
  );

  test('same revision field-wise fuller previews combine only with compatible declared lengths', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    ConversationItem thinking(String summary, String body) => ConversationItem(
      header: timelineItem(1).header,
      revision: 1,
      descriptor: const ConversationThinkingDescriptor(
        lifecycle: StreamingThreadContentView(),
      ),
      saved: false,
      lifecycle: ConversationLifecycle.streaming,
      fields: [
        ConversationFieldPreview(
          field: const ThreadThinkingSummaryFieldView(8),
          text: summary,
          totalBytes: 3,
        ),
        ConversationFieldPreview(
          field: const ThreadThinkingContentFieldView(16),
          text: body,
          totalBytes: 3,
        ),
      ],
    );
    final result = content.mergeItem(
      thinking('abc', 'x'),
      thinking('a', 'xyz'),
    );
    expect(
      result.fieldFor(const ThreadThinkingSummaryFieldView(8))!.text,
      'abc',
    );
    expect(
      result.fieldFor(const ThreadThinkingContentFieldView(16))!.text,
      'xyz',
    );
    expect(result.omittedBytes, 0);
    expect(
      () => content.mergeItem(thinking('abc', 'x'), thinking('abd', 'xyz')),
      throwsA(isA<ConversationContinuityError>()),
    );
    await fixture.close();
  });

  test('higher revisions can shorten original text and replace Turn association without changing identity', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final old = timelineItem(8, body: 'longer');
    final header = old.header;
    final next = ConversationItem(
      header: ConversationItemHeader(
        id: header.id,
        threadId: header.threadId,
        turnId: 'rebound-turn',
        ordinal: header.ordinal,
        createdAt: header.createdAt,
        updatedAt: header.updatedAt,
      ),
      revision: 9,
      descriptor: old.descriptor,
      saved: false,
      lifecycle: old.lifecycle,
      fields: const [
        ConversationFieldPreview(
          field: ThreadTextFieldView(),
          text: 'x',
          totalBytes: 1,
        ),
      ],
    );
    final result = content.mergeItem(old, next);
    expect(result.header.turnId, 'rebound-turn');
    expect(result.fields.single.text, 'x');
    expect(content.mergeItem(result, old), same(result));
    final otherIdentity = timelineItem(9, id: 'other');
    expect(
      () => content.mergeItem(result, otherIdentity),
      throwsA(isA<ConversationContinuityError>()),
    );
    await fixture.close();
  });

  test('same revision authoritative headers update Turn association but not stable identity', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final current = timelineItem(4, body: 'same');
    ConversationItemHeader header({
      String threadId = 'thread',
      int ordinal = 0,
      String turnId = 'new-turn',
    }) => ConversationItemHeader(
      id: current.id,
      threadId: threadId,
      turnId: turnId,
      ordinal: ordinal,
      createdAt: current.header.createdAt,
      updatedAt: DateTime.utc(2026, 2),
    );
    final incoming = ConversationItem(
      header: header(),
      revision: current.revision,
      descriptor: current.descriptor,
      saved: current.saved,
      lifecycle: current.lifecycle,
      fields: current.fields,
    );
    final merged = content.mergeItem(current, incoming);
    expect(merged.header.turnId, 'new-turn');
    expect(merged.header.updatedAt, DateTime.utc(2026, 2));
    final reduced = content.reduceItem(
      current,
      ConversationUpdateItem(
        itemId: current.id,
        expectedRevision: current.revision,
        revision: current.revision,
        saved: current.saved,
        lifecycle: current.lifecycle,
        header: header(turnId: 'updated-turn'),
        fields: const [],
      ),
    );
    expect(reduced.header.turnId, 'updated-turn');
    for (final invalid in [
      header(threadId: 'other-thread'),
      header(ordinal: 1),
    ]) {
      expect(
        () => content.reduceItem(
          current,
          ConversationUpdateItem(
            itemId: current.id,
            expectedRevision: current.revision,
            revision: current.revision,
            saved: current.saved,
            lifecycle: current.lifecycle,
            header: invalid,
            fields: const [],
          ),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
    }
    await fixture.close();
  });

  test('field identities use value equality and budgets reject overlarge previews rather than trim', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final item = timelineItem(1, body: 'body');
    expect(item.fieldFor(const ThreadTextFieldView())!.text, 'body');
    expect(
      () =>
          content.mergeItem(item, timelineItem(1, body: 'x' * (32 * 1024 + 1))),
      throwsA(isA<ConversationContinuityError>()),
    );
    final tool = ConversationItem(
      header: item.header,
      revision: 1,
      descriptor: const ConversationToolDescriptor(
        invocation: ConversationToolInvocation(
          toolCallId: 'call',
          name: 'exec',
        ),
        state: ConversationToolRunning(),
      ),
      saved: false,
      lifecycle: ConversationLifecycle.streaming,
      fields: [
        ConversationFieldPreview(
          field: const ThreadToolArgumentsFieldView(),
          text: 'x' * 4097,
          totalBytes: 4097,
        ),
      ],
    );
    expect(
      () => content.mergeItem(tool, tool),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(item.fields.single.text, 'body');
    await fixture.close();
  });
}
