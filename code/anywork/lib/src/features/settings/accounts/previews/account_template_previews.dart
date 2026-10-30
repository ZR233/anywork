import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'account_preview_fixtures.dart';
import 'account_preview_host.dart';
import 'account_template_preview_fixtures.dart';
import '../state/account_presentations.dart';

// All interactions use the shared production-View host and local recording.
// Names intentionally include the exact template ID for Previewer filtering.

@Preview(
  name: 'Template / openai / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateOpenaiListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('openai')],
  ),
);

@Preview(
  name: 'Template / openai / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateOpenaiDetailsPreview() =>
    accountDetailsPreviewHost(AccountTemplatePreviewFixtures.details('openai'));

@Preview(
  name: 'Template / openai / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateOpenaiEditorPreview() => accountNativeEditorPreviewHost(
  AccountTemplatePreviewFixtures.editor('openai'),
);

@Preview(
  name: 'Template / openai / ChatGPT subscription editor',
  group: 'Accounts · Templates',
  size: Size(900, 900),
)
Widget accountTemplateOpenaiChatGptEditorPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai').copyWith(
        authentication: AccountAuthenticationMethod.chatGpt,
        canSave: false,
      ),
    );

@Preview(
  name: 'Template / openai / ChatGPT waiting for browser',
  group: 'Accounts · Templates',
  size: Size(900, 900),
)
Widget accountTemplateOpenaiChatGptWaitingPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai').copyWith(
        authentication: AccountAuthenticationMethod.chatGpt,
        chatGptLogin: const ChatGptLoginSnapshot(
          phase: ChatGptLoginPhase.awaitingBrowser,
        ),
        canSave: false,
      ),
    );

@Preview(
  name: 'Template / openai / ChatGPT connected',
  group: 'Accounts · Templates',
  size: Size(900, 900),
)
Widget accountTemplateOpenaiChatGptConnectedPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai').copyWith(
        authentication: AccountAuthenticationMethod.chatGpt,
        chatGptLogin: const ChatGptLoginSnapshot(
          phase: ChatGptLoginPhase.succeeded,
          account: ChatGptAccountInfo(
            email: 'member@example.invalid',
            planUsageEnabled: true,
          ),
        ),
      ),
    );

@Preview(
  name: 'Template / openai / ChatGPT permission missing',
  group: 'Accounts · Templates',
  size: Size(900, 900),
)
Widget accountTemplateOpenaiChatGptPermissionPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai').copyWith(
        authentication: AccountAuthenticationMethod.chatGpt,
        chatGptLogin: const ChatGptLoginSnapshot(
          phase: ChatGptLoginPhase.failed,
          failure: ChatGptLoginFailureCode.missingPlanPermission,
        ),
        canSave: false,
      ),
    );

@Preview(
  name: 'Template / openai / ChatGPT expired narrow',
  group: 'Accounts · Templates',
  size: Size(420, 1000),
)
Widget accountTemplateOpenaiChatGptNarrowPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai').copyWith(
        authentication: AccountAuthenticationMethod.chatGpt,
        chatGptLogin: const ChatGptLoginSnapshot(
          phase: ChatGptLoginPhase.failed,
          failure: ChatGptLoginFailureCode.expired,
        ),
        canSave: false,
      ),
      textScale: 1.2,
    );

@Preview(
  name: 'Template / deepseek / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateDeepseekListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('deepseek')],
  ),
);

@Preview(
  name: 'Template / deepseek / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateDeepseekDetailsPreview() => accountDetailsPreviewHost(
  AccountTemplatePreviewFixtures.details('deepseek'),
);

@Preview(
  name: 'Template / deepseek / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateDeepseekEditorPreview() => accountNativeEditorPreviewHost(
  AccountTemplatePreviewFixtures.editor('deepseek'),
);

@Preview(
  name: 'Template / xai / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateXaiListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('xai')],
  ),
);

@Preview(
  name: 'Template / xai / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateXaiDetailsPreview() =>
    accountDetailsPreviewHost(AccountTemplatePreviewFixtures.details('xai'));

@Preview(
  name: 'Template / xai / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateXaiEditorPreview() => accountNativeEditorPreviewHost(
  AccountTemplatePreviewFixtures.editor('xai'),
);

@Preview(
  name: 'Template / zhipu / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateZhipuListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('zhipu')],
  ),
);

@Preview(
  name: 'Template / zhipu / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateZhipuDetailsPreview() =>
    accountDetailsPreviewHost(AccountTemplatePreviewFixtures.details('zhipu'));

@Preview(
  name: 'Template / zhipu / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateZhipuEditorPreview() => accountNativeEditorPreviewHost(
  AccountTemplatePreviewFixtures.editor('zhipu'),
);

@Preview(
  name: 'Template / zhipu-coding-plan / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateZhipuCodingPlanListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('zhipu-coding-plan')],
  ),
);

@Preview(
  name: 'Template / zhipu-coding-plan / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateZhipuCodingPlanDetailsPreview() =>
    accountDetailsPreviewHost(
      AccountTemplatePreviewFixtures.details('zhipu-coding-plan'),
    );

@Preview(
  name: 'Template / zhipu-coding-plan / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateZhipuCodingPlanEditorPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('zhipu-coding-plan'),
    );

@Preview(
  name: 'Template / mimo-api / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateMimoApiListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('mimo-api')],
  ),
);

@Preview(
  name: 'Template / mimo-api / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateMimoApiDetailsPreview() => accountDetailsPreviewHost(
  AccountTemplatePreviewFixtures.details('mimo-api'),
);

@Preview(
  name: 'Template / mimo-api / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateMimoApiEditorPreview() => accountNativeEditorPreviewHost(
  AccountTemplatePreviewFixtures.editor('mimo-api'),
);

@Preview(
  name: 'Template / mimo-token-plan / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateMimoTokenPlanListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('mimo-token-plan')],
  ),
);

@Preview(
  name: 'Template / mimo-token-plan / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateMimoTokenPlanDetailsPreview() =>
    accountDetailsPreviewHost(
      AccountTemplatePreviewFixtures.details('mimo-token-plan'),
    );

@Preview(
  name: 'Template / mimo-token-plan / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateMimoTokenPlanEditorPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('mimo-token-plan'),
    );

@Preview(
  name: 'Template / openai-compatible / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateOpenaiCompatibleListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('openai-compatible')],
  ),
);

@Preview(
  name: 'Template / openai-compatible / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateOpenaiCompatibleDetailsPreview() =>
    accountDetailsPreviewHost(
      AccountTemplatePreviewFixtures.details('openai-compatible'),
    );

@Preview(
  name: 'Template / openai-compatible / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateOpenaiCompatibleEditorPreview() =>
    accountNativeEditorPreviewHost(
      AccountTemplatePreviewFixtures.editor('openai-compatible'),
    );

@Preview(
  name: 'Template / antigravity / List',
  group: 'Accounts · Templates',
  size: Size(1240, 620),
)
Widget accountTemplateAntigravityListPreview() => accountListPreview(
  AccountTemplatePreviewFixtures.allTemplates.copyWith(
    rows: [AccountTemplatePreviewFixtures.row('antigravity')],
  ),
);

@Preview(
  name: 'Template / antigravity / Details',
  group: 'Accounts · Templates',
  size: Size(1180, 1100),
)
Widget accountTemplateAntigravityDetailsPreview() => accountDetailsPreviewHost(
  AccountTemplatePreviewFixtures.details('antigravity'),
);

@Preview(
  name: 'Template / antigravity / Editor',
  group: 'Accounts · Templates',
  size: Size(900, 1100),
)
Widget accountTemplateAntigravityEditorPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    templateName: 'Antigravity',
    accountKey: AccountTemplatePreviewFixtures.key('antigravity'),
    preparation: AccountPreviewFixtures.acp,
    canSave: true,
  ),
);

@Preview(
  name: 'Templates / all 8 Native + Antigravity / list',
  group: 'Accounts · Templates',
  size: Size(1240, 1400),
)
Widget accountAllTemplatesListPreview() =>
    accountListPreview(AccountTemplatePreviewFixtures.allTemplates);
