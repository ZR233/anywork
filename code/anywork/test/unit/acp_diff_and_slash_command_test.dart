import 'package:anywork/src/features/conversation/acp/state/acp_view_state.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_content_view_model.dart';
import 'package:anywork/src/features/conversation/acp/widgets/acp_slash_command_menu.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapAcpDiffPresentation (Myers line diff)', () {
    test('produces minimal hunk with 3 context lines for single edit', () {
      final oldLines = List.generate(15, (i) => 'line ${i + 1}');
      final newLines = [...oldLines]..[7] = 'line 8 updated';

      final doc = mapAcpDiffPresentation(
        AcpToolDiffView(
          path: 'lib/sample.dart',
          oldText: oldLines.join('\n'),
          newText: newLines.join('\n'),
        ),
      );

      expect(doc.files, hasLength(1));
      final file = doc.files.first;
      expect(file.op, TimelinePatchFileOp.update);
      expect(file.additions, 1);
      expect(file.deletions, 1);
      expect(doc.additions, 1);
      expect(doc.deletions, 1);
      expect(doc.hasChanges, isTrue);
      expect(file.chunks, hasLength(1));

      final lines = file.chunks.first.lines;
      // lines 5,6,7 (3 before) + -line 8 + +line 8 updated + lines 9,10,11 (3 after)
      expect(lines.length, 8);
      expect(
        lines.where((l) => l.kind == TimelinePatchLineKind.context).length,
        6,
      );
      expect(
        lines
            .where((l) => l.kind == TimelinePatchLineKind.deletion)
            .map((l) => l.text),
        ['line 8'],
      );
      expect(
        lines
            .where((l) => l.kind == TimelinePatchLineKind.addition)
            .map((l) => l.text),
        ['line 8 updated'],
      );
    });

    test(
      'splits distant edits into separate hunks and merges nearby edits',
      () {
        final oldLines = List.generate(30, (i) => 'row ${i + 1}');
        final farNew = [...oldLines]
          ..[2] = 'row 3 changed'
          ..[26] = 'row 27 changed';
        final farDoc = mapAcpDiffPresentation(
          AcpToolDiffView(
            path: 'lib/far.dart',
            oldText: oldLines.join('\n'),
            newText: farNew.join('\n'),
          ),
        );
        expect(farDoc.files.single.chunks, hasLength(2));
        expect(farDoc.additions, 2);
        expect(farDoc.deletions, 2);

        final nearNew = [...oldLines]
          ..[4] = 'row 5 changed'
          ..[7] = 'row 8 changed';
        final nearDoc = mapAcpDiffPresentation(
          AcpToolDiffView(
            path: 'lib/near.dart',
            oldText: oldLines.join('\n'),
            newText: nearNew.join('\n'),
          ),
        );
        expect(nearDoc.files.single.chunks, hasLength(1));
      },
    );

    test('handles new files, unchanged text, and CRLF line endings', () {
      final added = mapAcpDiffPresentation(
        const AcpToolDiffView(
          path: 'lib/created.dart',
          oldText: null,
          newText: 'a\nb',
        ),
      );
      expect(added.files.single.op, TimelinePatchFileOp.add);
      expect(added.additions, 2);
      expect(added.deletions, 0);

      final crlfSame = mapAcpDiffPresentation(
        const AcpToolDiffView(
          path: 'lib/crlf.dart',
          oldText: 'one\r\ntwo\r\nthree',
          newText: 'one\ntwo\nthree',
        ),
      );
      expect(crlfSame.additions, 0);
      expect(crlfSame.deletions, 0);
      expect(crlfSame.hasChanges, isFalse);
    });

    test('falls back safely when file exceeds Myers line budget', () {
      final hugeOld = List.generate(2500, (i) => 'old $i').join('\n');
      final hugeNew = List.generate(2500, (i) => 'new $i').join('\n');
      final doc = mapAcpDiffPresentation(
        AcpToolDiffView(
          path: 'lib/huge.dart',
          oldText: hugeOld,
          newText: hugeNew,
        ),
      );
      expect(doc.files.single.chunks, hasLength(1));
      expect(doc.deletions, 2500);
      expect(doc.additions, 2500);
    });
  });

  group('ACP slash command matching and ranking', () {
    const commands = [
      AcpSlashCommandPresentation(
        name: 'help',
        description: 'Show help and tips',
      ),
      AcpSlashCommandPresentation(
        name: 'fix-lint',
        description: 'Run lint checks',
      ),
      AcpSlashCommandPresentation(
        name: 'review',
        description: 'Review code changes',
        inputHint: 'target',
      ),
      AcpSlashCommandPresentation(
        name: 'preview-ui',
        description: 'Open UI preview',
      ),
    ];

    test('matchAcpSlashTrigger only fires on leading slash token', () {
      expect(matchAcpSlashTrigger('/'), '');
      expect(matchAcpSlashTrigger('/rev'), 'rev');
      expect(matchAcpSlashTrigger('/review target'), isNull);
      expect(matchAcpSlashTrigger('/review\nmore'), isNull);
      expect(matchAcpSlashTrigger('lib/main.dart'), isNull);
      expect(matchAcpSlashTrigger('please /review'), isNull);
      expect(matchAcpSlashTrigger(''), isNull);
    });

    test('rankAcpSlashCommands scores exact, prefix, boundary, substring, description', () {
      expect(
        rankAcpSlashCommands(commands, 'review').map((c) => c.name).toList(),
        ['review', 'preview-ui'],
      );
      expect(
        rankAcpSlashCommands(commands, 'lint').map((c) => c.name).toList(),
        ['fix-lint'],
      );
      expect(rankAcpSlashCommands(commands, 're').map((c) => c.name).toList(), [
        'review',
        'preview-ui',
      ]);
      expect(
        rankAcpSlashCommands(commands, 'tips').map((c) => c.name).toList(),
        ['help'],
      );
      expect(rankAcpSlashCommands(commands, '').length, commands.length);
    });

    test(
      'mapAcpSlashCommands and mapAcpUpdatePresentation preserve inputHint',
      () {
        final commands = mapAcpSlashCommands(const [
          AcpAvailableCommandView(name: 'compact', description: '整理上下文'),
          AcpAvailableCommandView(
            name: 'review',
            description: 'Review diff',
            input: AcpUnstructuredCommandInputView(hint: 'scope'),
          ),
          AcpAvailableCommandView(name: '   ', description: 'ignored blank'),
        ]);
        expect(commands, hasLength(2));
        expect(commands[0].name, 'compact');
        expect(commands[0].inputHint, isNull);
        expect(commands[1].name, 'review');
        expect(commands[1].description, 'Review diff');
        expect(commands[1].inputHint, 'scope');

        final presentation = mapAcpUpdatePresentation(
          AcpAvailableCommandsUpdateView(
            commands: const [
              AcpAvailableCommandView(
                name: 'review',
                description: 'Review diff',
                input: AcpUnstructuredCommandInputView(hint: 'scope'),
              ),
            ],
          ),
        );
        expect(presentation, isA<AcpCommandsUpdatePresentation>());
        final available = presentation as AcpCommandsUpdatePresentation;
        expect(available.commands, hasLength(1));
        expect(available.commands.single.name, 'review');
        expect(available.commands.single.inputHint, 'scope');

        final superseded = mapAcpUpdatePresentation(
          AcpAvailableCommandsUpdateView(
            commands: const [
              AcpAvailableCommandView(name: 'old', description: 'Old'),
            ],
          ),
          superseded: true,
        );
        expect(superseded, isA<AcpSupersededUpdatePresentation>());
      },
    );
  });
}
