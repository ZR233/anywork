import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'typed read-only interaction details hide secret question fields',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ReadOnlyInteractionDetails(
                id: 'interaction',
                payload: UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: 'public',
                      header: '公开问题',
                      question: '公开详情',
                      isOther: true,
                      isSecret: false,
                      options: [],
                    ),
                    UserQuestionView(
                      id: 'secret',
                      header: '秘密问题',
                      question: '秘密详情',
                      isOther: false,
                      isSecret: true,
                      options: [],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('公开问题'), findsOneWidget);
      expect(find.textContaining('公开详情'), findsOneWidget);
      expect(find.textContaining('秘密问题'), findsNothing);
      expect(find.textContaining('秘密详情'), findsNothing);
      final details = tester.element(find.byType(ReadOnlyInteractionDetails));
      expect(
        find.text(
          AppLocalizations.of(details).interactionDetailsSecretQuestionHidden,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
