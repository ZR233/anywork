import 'package:anywork/src/features/settings/accounts/previews/account_preview_host.dart';
import 'package:anywork/src/features/settings/accounts/previews/account_template_preview_fixtures.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_editor_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OpenAI preview switches API fields and subscription login UI', (
    tester,
  ) async {
    final fixture = AccountTemplatePreviewFixtures.editor('openai');
    await tester.pumpWidget(
      accountNativeEditorPreviewHost(
        fixture.copyWith(
          authentication: AccountAuthenticationMethod.chatGpt,
          canSave: false,
        ),
      ),
    );

    expect(find.text('使用 ChatGPT 登录'), findsOneWidget);
    final connectionFields = find.byType(AccountNativeConnectionFields);
    final endpointInput = find.descendant(
      of: connectionFields,
      matching: find.text('https://api.openai.com/v1'),
    );
    final inputs = find.descendant(
      of: connectionFields,
      matching: find.byType(TextField),
    );
    expect(endpointInput, findsNothing);
    expect(inputs, findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('account-save')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('API 密钥'));
    await tester.pumpAndSettle();

    expect(endpointInput, findsOneWidget);
    expect(inputs, findsNWidgets(4));
    expect(find.text('使用 ChatGPT 登录'), findsNothing);
  });

  testWidgets('ChatGPT operation errors are displayed once', (tester) async {
    const message = 'OpenAI sign-in service unavailable';
    await tester.pumpWidget(
      accountNativeEditorPreviewHost(
        AccountTemplatePreviewFixtures.editor('openai').copyWith(
          authentication: AccountAuthenticationMethod.chatGpt,
          chatGptLogin: const ChatGptLoginSnapshot(
            phase: ChatGptLoginPhase.failed,
            failure: ChatGptLoginFailureCode.other,
          ),
          error: message,
          canSave: false,
        ),
      ),
    );

    expect(find.text(message), findsOneWidget);
    expect(find.text('使用 ChatGPT 登录'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('account-save')),
          )
          .onPressed,
      isNull,
    );
  });
}
