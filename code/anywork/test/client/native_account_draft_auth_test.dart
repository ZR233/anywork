import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/view_models/native_account_draft.dart';
import 'package:anywork_client/accounts.dart'
    hide AccountAuthenticationMethod, ChatGptAccountInfo;
import 'package:anywork_client/accounts.dart'
    as account_domain
    show AccountAuthenticationMethod, ChatGptAccountInfo;
import 'package:flutter_test/flutter_test.dart';

const _identity = NativeAccountIdentity('openai-account');
const _template = AccountTemplateView(
  id: 'openai',
  displayName: 'OpenAI',
  description: '',
  baseUrl: 'https://api.openai.com/v1',
  credentialLabel: 'API key',
  credentialEnv: 'OPENAI_API_KEY',
  modelCatalogId: 'openai',
  protocol: 'open_ai',
  suggestedModelId: 'gpt-4o',
  defaultBillingKind: BillingKind.subscription,
  supportsModelDiscovery: true,
  supportsUsageQuery: true,
);

NativeAccountDraft _draft({
  String endpoint = 'https://custom.openai.example/v1',
  String credential = 'old-api-secret-must-not-survive',
}) => NativeAccountDraft(
  name: 'OpenAI account',
  endpoint: endpoint,
  credential: credential,
  protocol: 'open_ai',
  templateId: 'openai',
  rows: const [],
);

void main() {
  test(
    'ChatGPT intent is editor-bound and never carries an API credential',
    () {
      final api = _draft();
      final subscription = api.withAuthentication(
        account_domain.AccountAuthenticationMethod.chatGpt,
      );
      expect(subscription.endpoint, 'https://api.openai.com/v1');
      expect(subscription.credential, isEmpty);
      expect(
        subscription.field(NativeAccountField.name, 'Renamed').credential,
        isEmpty,
      );
      final switchedBack = subscription.withAuthentication(
        account_domain.AccountAuthenticationMethod.apiKey,
      );
      expect(switchedBack.credential, isEmpty);
      expect(switchedBack.mustEnterApiKey, isTrue);

      expect(
        () => subscription.create(_identity, editorId: 'editor-1'),
        throwsStateError,
      );
      final pending = subscription.withAuthentication(
        account_domain.AccountAuthenticationMethod.chatGpt,
        loginId: 'login-1',
      );
      final create = pending.create(_identity, editorId: 'editor-1');
      expect(create.authentication, isA<SelectChatGptAuthentication>());
      final intent = create.authentication as SelectChatGptAuthentication;
      expect((intent.loginId, intent.editorId), ('login-1', 'editor-1'));
      expect(create.secret.action, AccountSecretAction.preserve);
    },
  );

  test('switching from ChatGPT to API requires a fresh key intent', () {
    final saved = NativeAccountDraft.fromDetails(
      NativeAccountDetails(
        identity: _identity,
        name: 'OpenAI account',
        authentication: account_domain.AccountAuthenticationMethod.chatGpt,
        chatgptAccount: const account_domain.ChatGptAccountInfo(
          issuer: 'https://auth.openai.com',
          subject: 'subject',
          clientId: 'issued-client',
          planUsageEnabled: true,
        ),
        protocol: 'open_ai',
        templateId: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        hasBearerToken: false,
        credentialRequired: false,
        usageQueryRevision: 1,
        customModels: const [],
      ),
      const {},
    );
    final api = saved.withAuthentication(
      account_domain.AccountAuthenticationMethod.apiKey,
    );
    expect(api.credential, isEmpty);
    final patch = api.patch(_identity, saved, editorId: 'editor-2');
    expect(patch.authentication, isA<SelectApiKeyAuthentication>());
    expect(patch.secret.action, AccountSecretAction.preserve);

    final withNewKey = api.field(NativeAccountField.credential, 'new-key');
    expect(withNewKey.credential, 'new-key');
    expect(
      withNewKey.patch(_identity, saved, editorId: 'editor-2').secret.action,
      AccountSecretAction.replace,
    );
  });

  test('unrelated edit of a saved subscription keeps canonical auth', () {
    final saved = NativeAccountDraft.fromTemplate(_template)
        .withAuthentication(account_domain.AccountAuthenticationMethod.chatGpt);
    final edited = saved.field(NativeAccountField.name, 'Renamed');
    final patch = edited.patch(_identity, saved, editorId: 'editor-3');
    expect(patch.authentication, isA<KeepAccountAuthentication>());
  });
}
