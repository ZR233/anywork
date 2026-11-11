import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/presentation/providers/attachment_drafts.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('ACP 创建允许空输入，编辑使用真实 startDraft 并保留既有附件', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    harness.client.drafts.startDraft.setAcpService('workspace', 'account');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          anyworkClientProvider.overrideWithValue(harness.client),
          attachmentDraftsProvider.overrideWith(
            (ref) => const AttachmentDraftBoard(
              newThreadDrafts: {
                'workspace': ComposerThreadState.idle(
                  attachments: [
                    AttachmentDraftView(
                      id: 'existing',
                      modality: AttachmentModalityView.file,
                      mediaType: 'text/plain',
                      filename: 'existing.txt',
                      byteSize: 12,
                    ),
                  ],
                ),
              },
            ),
          ),
        ],
        child: acpTestApp(const AcpStartComposer(workspaceId: 'workspace')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
      reason: 'session/new is valid without an initial prompt',
    );
    expect(find.text('existing.txt'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsNothing);
    await tester.enterText(find.byType(TextField), '保留新会话输入');
    expect(
      harness.client.drafts.startDraft.state.forProject('workspace').text,
      '保留新会话输入',
    );
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    harness.client.drafts.startDraft.setAcpService('workspace', 'other');
    await tester.pumpAndSettle();
    expect(controller.text, '保留新会话输入');
    expect(controller.selection.baseOffset, 2);
    expect(find.text('existing.txt'), findsOneWidget);
  });

  testWidgets('ACP SSH 创建提前说明，项目源更新后独立恢复本地准入', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    harness.client.drafts.startDraft.setAcpService('workspace', 'account');
    harness.client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: 2,
        values: const [
          StudioProject(
            id: 'workspace',
            name: '远端项目',
            path: '/project',
            sshAlias: 'server',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      harness.scope(const AcpStartComposer(workspaceId: 'workspace')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂不支持 SSH 项目'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    harness.client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: 3,
        values: const [
          StudioProject(id: 'workspace', name: '本地项目', path: '/project'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂不支持 SSH 项目'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(harness.port.calls.map((call) => call.$1), ['open']);
  });
}
