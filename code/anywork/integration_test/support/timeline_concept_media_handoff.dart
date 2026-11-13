part of '../timeline_concept_test.dart';

const _mediaCall = 'concept-image-a';
const _mediaAnswer = '纯附件已收到，后台图片已读取。';
const _mediaPngHash =
    '0a23b4c2e99e7de221fedb9e4e96d910c786d32385a17dc44dbc1138c13a2b4b';
const _mediaInputFixtureExpectedHashes = [
  'e75b8140cad993ca5a23db4170bf70d3a4db3d7af55c9e8b43d432022aa58cd4',
  '316558a02d6a9d35fc19480c9397cdab46a0b1ff83132e25fa184af837e4cfc2',
  'eee576e2d47e68f0b0a185080f6b6e063d43cdee506cd6df180bd598a4034929',
];

extension _MediaHandoffScene on _ConceptScene {
  String get _leasePath => Platform.environment['ANYWORK_MEDIA_HANDOFF_LEASE']!;

  Future<void> closeMediaLease({required bool success}) async {
    if (!success) {
      await File('$_leasePath/abort.json').writeAsString('{}\n');
    }
    await _until(
      tester,
      () => File('$_leasePath/joined.json').existsSync(),
      'lease holder joined before GUI/reader shutdown',
      timeout: const Duration(seconds: 8),
    );
    final joined = jsonDecode(
      await File('$_leasePath/joined.json').readAsString(),
    ) as Map<String, dynamic>;
    report['leaseHolderJoined'] = joined;
    if (success) {
      expect(joined['exitCode'], 0);
      expect(File('$_leasePath/error.json').existsSync(), isFalse);
      expect(File('$_leasePath/released.json').existsSync(), isTrue);
    }
  }

  Future<ChatAtom> _completedMediaAtom(TimelineDisplayUnit unit) async {
    final row = unit.body as SingleDisplayBlock;
    return _readMediaCompletion(
      row.record.atom,
      completedOriginalId(row.record)!,
    );
  }

  Future<DisplayMemberHead> _mediaImageMember(
    TimelineDisplayUnit work, {
    required String turnId,
  }) async {
    final owner = lease;
    final reference = work.memberReference!;
    final source = ForegroundTurnChatSource(turnId: turnId);
    final matches = <DisplayMemberHead>[];
    final seen = <String>{};
    final pages = <Map<String, Object?>>[];
    report['mediaMemberLookup'] = {
      'workRowId': work.id,
      'turnId': turnId,
      'callId': _mediaCall,
      'startedAt': work.timing!.startedAt,
      'pages': pages,
    };
    DisplayMemberWindow window = const LatestDisplayMembers();
    int? before;
    // Pending ToolImages may append real wait members to this Work. Walk
    // strictly backwards from the first page's cut, rather than restarting
    // Latest or requiring the mutable total/revision to remain unchanged.
    while (true) {
      final page = await observed.readMemberPage(
        reference,
        window: window,
        demand: const ReadDemand(maxItems: 12, maxBytes: 64 * 1024),
      );
      expect(lease, same(owner));
      expect(page.block, reference);
      var previousOrder = 0;
      for (final member in page.entries) {
        expect(member.memberOrder, greaterThan(previousOrder));
        if (before != null) expect(member.memberOrder, lessThan(before));
        expect(seen.add(member.memberKey), isTrue);
        expect(member.record.atom.turnId, turnId);
        previousOrder = member.memberOrder;
        if (member.record.atom.source == source &&
            member.record.atom.tool?.callId == _mediaCall &&
            member.record.contentSource is CompletedOriginal) {
          matches.add(member);
        }
      }
      pages.add({
        'beforeRequested': before,
        'beforeReturned': page.before,
        'revision': page.revision,
        'memberOrders': page.entries
            .map((member) => member.memberOrder)
            .toList(),
        'callIds': page.entries
            .map((member) => member.record.atom.tool?.callId)
            .toList(),
      });
      final next = page.before;
      if (next == null) break;
      expect(page.entries, isNotEmpty);
      expect(next, page.entries.first.memberOrder);
      if (before != null) expect(next, lessThan(before));
      before = next;
      window = BeforeDisplayMembers(memberOrder: next);
    }
    expect(
      matches,
      hasLength(1),
      reason: 'Locate the original image, not a wait',
    );
    final member = matches.single;
    expect(member.record.atom.kind, ChatAtomKind.toolCall);
    expect(member.record.atom.tool!.callId, _mediaCall);
    expect(member.record.atom.tool!.name, 'view_image');
    expect(member.memberKey, isNotEmpty);
    expect(member.record.atom.id, isNotEmpty);
    expect(completedOriginalId(member.record), isNotNull);
    expect(completedOriginalId(member.record), isNotEmpty);
    expect(
      member.record.atom.completionItemId,
      completedOriginalId(member.record),
    );
    expect(member.record.atom.completionSeq, greaterThan(0));
    return member;
  }

  Future<ChatAtom> _readMediaCompletion(
    ChatAtom head,
    String completionId,
  ) async {
    final scope = lease.content.openScope(generation: lease.generation);
    try {
      final completed = await scope.readCompleted(
        recordId: completionId,
        demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
      );
      expect(completed.recordId, completionId);
      expect(completed.completionSeq, head.completionSeq);
      final atom = completed.atom;
      expect(atom.id, head.id);
      expect(atom.source, head.source);
      expect(atom.turnId, head.turnId);
      expect(atom.completionItemId, completionId);
      expect(atom.completionSeq, completed.completionSeq);
      return atom;
    } finally {
      scope.retire();
      expect((await scope.close()).complete, isTrue);
    }
  }

  Future<Map<String, Object?>> _mediaInput(
    String project,
    String inputId, {
    TimelineConceptImageInput? frozen,
  }) async {
    expect(inputId, isNotEmpty);
    final source = InputChatSource(inputId: inputId);
    await _until(
      tester,
      () =>
          items.where((unit) => unit.atom!.source == source).length == 1 &&
          graph.client.drafts.composer(threadId).submissions.value.isEmpty,
      'one canonical pure-attachment input and revoked local echo',
    );
    final unit = items.singleWhere((unit) => unit.atom!.source == source);
    expect(find.byKey(ValueKey('composer-submission:$inputId')), findsNothing);
    await observed.revealSingle(unit);
    final item = await waitForTimelineConceptSingle(tester, unit);
    expect(item.type, 'text');
    expect(item.body('body'), isNotNull);
    expect(item.body('body')!.byteLength, 0);
    expect(item.inlineText('body'), '');
    await waitForTimelineConceptInputImages(tester, item);
    final attachments = item.attachments;
    expect(attachments, hasLength(3));
    expect(
      attachments.map((attachment) => attachment.id),
      everyElement(isNotEmpty),
    );
    expect(
      attachments.map((attachment) => attachment.id).toSet(),
      hasLength(3),
    );
    if (frozen != null) frozen.verifyItem(unit, attachments);
    final views = tester
        .widgetList<TimelineImageView>(
          find.descendant(
            of: itemFinder(unit.id),
            matching: find.byType(TimelineImageView),
          ),
        )
        .toList();
    final evidence = <Map<String, Object?>>[];
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final name = 'concept-input-${['a', 'b', 'c'][index]}.png';
      final bytes = await File('$project/$name').readAsBytes();
      expect(attachment.filename, name);
      expect(attachment.mediaType, 'image/png');
      expect(attachment.modality, AttachmentModalityView.image);
      expect(attachment.byteSize, bytes.length);
      expect(attachment.width, [512, 256, 128][index]);
      expect(attachment.height, [512, 256, 128][index]);
      expect(views[index].attachment.id, attachment.id);
      expect(views[index].bytes, orderedEquals(bytes));
      evidence.add({
        'attachmentId': attachment.id,
        'fixtureExpectedSha256': _mediaInputFixtureExpectedHashes[index],
        'hashEvidenceSource':
            'Strict fixture PromptImages PNG matcher; not computed by Dart '
            'or derived from the attachment instance ID.',
        'filename': name,
        'byteSize': bytes.length,
        'width': attachment.width,
        'height': attachment.height,
        'originalBytesEqual': true,
      });
    }
    if (frozen != null) {
      report['draftToCanonicalAttachments'] = [
        for (var index = 0; index < attachments.length; index++)
          {
            'draftId': frozen.drafts[index].id,
            'attachmentId': attachments[index].id,
            'filename': attachments[index].filename,
          },
      ];
    }
    await capture('sent-pure-attachments');
    return {
      'inputId': inputId,
      'rowId': unit.id,
      'atomId': unit.atom!.id,
      'completionId': completedOriginalId(
        (unit.body as SingleDisplayBlock).record,
      ),
      'emptyText': true,
      'localEchoRevoked': true,
      'attachments': evidence,
    };
  }

  Future<void> mediaHandoff(String project, {required bool reopen}) async {
    expect(Platform.isLinux, isTrue);
    final output = _environment('OUTPUT');
    late String inputId;
    late ChatAtom foreground;
    Map<String, dynamic>? saved;
    TimelineConceptImageInput? input;
    if (reopen) {
      saved = jsonDecode(
        await File('$output/timeline-media-handoff.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(saved['pass'], isTrue);
      expect(saved['shutdown'], 'completed');
      expect(saved['threadId'], threadId);
      expect(saved['processObservation']['dartIoPid'], isNot(pid));
      inputId = saved['mediaInput']['inputId'] as String;
      await _admitSavedMain({
        saved['mediaInput']['rowId'] as String,
        saved['mediaResult']['blockId'] as String,
        saved['mediaWorkRowId'] as String,
      });
    } else {
      await _until(
        tester,
        () => !lease.hasOlder,
        'empty narrow media conversation',
      );
      expect(items, isEmpty);
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('composer-input')).evaluate().length == 1,
        'real composer for the empty media thread',
      );
      input = await submitTimelineConceptImageInput(
        tester,
        graph,
        threadId: threadId,
        projectPath: project,
        prompt: '',
        beforeSubmit: () => capture('pure-attachments-draft'),
      );
      report['frozenSubmission'] = input.toJson();
      inputId = input.inputId;
    }

    await _until(
      tester,
      () => observed.allWork.isNotEmpty,
      'original image Work has a real transferred terminal',
      timeout: const Duration(seconds: 15),
    );
    final work = observed.allWork.first;
    late final String turnId;
    if (reopen) {
      turnId = saved!['handoff']['turnId'] as String;
    } else {
      final session = graph.client.conversations.session(threadId).state;
      final turn = session.activeTurn ?? session.lastTurn;
      expect(turn, isNotNull);
      expect(turn!.threadId, threadId);
      expect(turn.inputId, inputId);
      turnId = turn.turnId;
    }
    final member = await _mediaImageMember(work, turnId: turnId);
    final head = member.record.atom;
    foreground = await _readMediaCompletion(
      head,
      completedOriginalId(member.record)!,
    );
    expect(foreground.source, isA<ForegroundTurnChatSource>());
    expect(foreground.source, ForegroundTurnChatSource(turnId: turnId));
    expect(foreground.turnId, turnId);
    expect(foreground.tool!.callId, _mediaCall);
    expect(foreground.tool!.name, 'view_image');
    expect(foreground.delivery, ChatDeliveryKind.backgroundHandoff);
    expect(
      (foreground.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.transferred,
    );
    final tool =
        (ChatItemPresentation.decode(foreground).toolCard as DecodedToolCard)
            .value;
    expect(tool.name, 'view_image');
    expect(tool.toolCallId, _mediaCall);
    expect(tool.statusString, 'backgroundStarted');
    expect(tool.outcome, isNull);
    expect(tool.taskId, isNotNull);
    expect(tool.taskId, isNotEmpty);
    final handoff = <String, Object?>{
      'inputId': inputId,
      'callId': _mediaCall,
      'taskId': tool.taskId!,
      'foregroundAtomId': foreground.id,
      'turnId': foreground.turnId!,
    };
    report['handoff'] = handoff;
    report['mediaWorkRowId'] = work.id;
    if (!reopen) {
      await _until(
        tester,
        () => File('$_leasePath/break.json').existsSync(),
        'real SIGIO break before explicit release',
        timeout: const Duration(seconds: 3),
      );
      final beforeRelease = await collectDisplayRecords(
        observed,
        turnId: turnId,
      );
      expect(
        beforeRelease.where(
          (entry) =>
              entry.record.atom.source is BackgroundResultChatSource &&
              entry.record.atom.tool?.callId == _mediaCall &&
              entry.record.contentSource is CompletedOriginal,
        ),
        isEmpty,
      );
      expect(
        live.where(
          (atom) =>
              atom.tool?.callId == _mediaCall &&
              atom.delivery != ChatDeliveryKind.backgroundHandoff &&
              atom.lifecycle is TerminalChatAtom,
        ),
        isEmpty,
      );
      expect(File('$_leasePath/released.json').existsSync(), isFalse);
      final temporary = File('$_leasePath/releaseRequest.tmp');
      await temporary.writeAsString(jsonEncode(handoff));
      await temporary.rename('$_leasePath/releaseRequest.json');
      await closeMediaLease(success: true);
      final released = jsonDecode(
        await File('$_leasePath/released.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(released['explicitUnlock'], isTrue);
      expect(released['breakObserved'], isTrue);
      expect(released['releaseRequest'], handoff);
      report['leaseRelease'] = released;
    } else {
      expect(handoff, saved!['handoff']);
      expect(work.id, saved['mediaWorkRowId']);
    }

    final resultClock = Stopwatch()..start();
    List<ObservedDisplayRecord> finals;
    while (true) {
      finals = (await collectDisplayRecords(observed, turnId: turnId))
          .where(
            (entry) =>
                entry.record.atom.source is BackgroundResultChatSource &&
                entry.record.atom.tool?.callId == _mediaCall &&
                entry.record.contentSource is CompletedOriginal,
          )
          .toList();
      expect(finals.length, lessThanOrEqualTo(1));
      if (finals.isNotEmpty) break;
      if (resultClock.elapsed >= const Duration(seconds: 60)) {
        fail('Same call/task final display record did not arrive');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    final location = finals.single;
    final unit = location.unit;
    expect(
      location.member,
      isNull,
      reason: 'This narrow story requires an independent MainSingle result',
    );
    expect(unit.body, isA<SingleDisplayBlock>());
    expect(unit.memberReference, isNull);
    expect(location.record, (unit.body as SingleDisplayBlock).record);
    final value = await readDisplayRecord(
      lease,
      location.record,
      displayId: unit.id,
    );
    final atom = value.atom!;
    expect(atom.delivery, ChatDeliveryKind.independent);
    expect(atom.turnId, foreground.turnId);
    expect(atom.source, isA<BackgroundResultChatSource>());
    expect(
      (atom.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    expect(atom.completionItemId, isNot(foreground.completionItemId));
    expect(atom.id, location.record.atom.id);
    expect(atom.completionItemId, completedOriginalId(location.record));
    expect(atom.completionSeq, location.record.atom.completionSeq);
    final resultTool = (value.toolCard as DecodedToolCard).value;
    expect(resultTool.toolCallId, _mediaCall);
    expect(resultTool.taskId, tool.taskId);
    expect(resultTool.outcome, TimelineToolOutcome.succeeded);
    expect(value.attachments, hasLength(1));
    expect(value.attachments.single.id, 'pl.studio.resource:$_mediaPngHash');
    report['mediaResult'] = {
      'domain': 'MainSingle',
      'rowId': unit.id,
      'blockId': unit.id,
      'atomId': atom.id,
      'completionId': atom.completionItemId,
      'resourceId': value.attachments.single.id,
      'sha256': _mediaPngHash,
      'taskId': resultTool.taskId,
    };
    await _verifyImageResult((
      foreground: foreground,
      finalUnit: unit,
      finalMember: null,
      finalAtom: atom,
      presentation: value,
    ), missing: false);
    report['mediaInput'] = await _mediaInput(project, inputId, frozen: input);
    if (reopen) {
      expect(report['mediaResult'], saved!['mediaResult']);
      expect(report['mediaInput'], saved['mediaInput']);
      final mapping = saved['draftToCanonicalAttachments'] as List<dynamic>;
      final drafts = saved['frozenSubmission']['attachments'] as List<dynamic>;
      final canonical =
          (report['mediaInput'] as Map<String, Object?>)['attachments']
              as List<Map<String, Object?>>;
      expect(mapping, hasLength(3));
      expect(
        mapping.map((entry) => entry['draftId']),
        orderedEquals(drafts.map((entry) => entry['draftId'])),
      );
      expect(
        mapping.map((entry) => entry['attachmentId']),
        orderedEquals(canonical.map((entry) => entry['attachmentId'])),
      );
      expect(
        mapping.map((entry) => entry['filename']),
        orderedEquals(canonical.map((entry) => entry['filename'])),
      );
      report['draftToCanonicalAttachments'] = mapping;
    }
    await _until(
      tester,
      () => items.any(
        (unit) =>
            unit.atom!.kind == ChatAtomKind.text &&
            unit.atom!.source == foreground.source,
      ),
      'fixed media answer persisted in canonical Main',
    );
    final answer = items.singleWhere(
      (unit) =>
          unit.atom!.kind == ChatAtomKind.text &&
          unit.atom!.source == foreground.source,
    );
    final answerAtom = await _completedMediaAtom(answer);
    final answerValue = ChatItemPresentation.decode(answerAtom);
    expect(
      answerValue.bodies.where(
        (body) => answerValue.inlineText(body.key) == _mediaAnswer,
      ),
      hasLength(1),
    );
    expect((report['frameworkErrors'] as List), isEmpty);
  }
}
