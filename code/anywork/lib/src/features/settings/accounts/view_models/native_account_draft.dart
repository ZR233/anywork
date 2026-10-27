import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart' show AccountModelView;

import '../state/account_presentations.dart';
import 'account_projection.dart';

/// Private raw editor values. Canonical descriptors/configuration remain in
/// repositories; these values are only user intent plus the frozen save base.
final class NativeAccountDraft {
  const NativeAccountDraft({
    required this.name,
    required this.endpoint,
    required this.credential,
    required this.protocol,
    required this.templateId,
    required this.rows,
    this.billing,
  });
  final String name;
  final String endpoint;
  final String credential;
  final String protocol;
  final String? templateId;
  final List<ManualModelDraft> rows;
  final BillingKind? billing;

  factory NativeAccountDraft.fromDetails(
    NativeAccountDetails details,
    Map<String, AccountConnectionMode> connections,
  ) => NativeAccountDraft(
    name: details.name,
    endpoint: details.baseUrl,
    credential: '',
    protocol: details.protocol,
    templateId: details.templateId,
    rows: [
      for (var i = 0; i < details.customModels.length; i++)
        ManualModelDraft.fromCommand(
          details.customModels[i],
          'saved-$i',
          connections[details.customModels[i].modelId],
        ),
    ],
  );
  factory NativeAccountDraft.fromTemplate(AccountTemplateView template) =>
      NativeAccountDraft(
        name: template.displayName,
        endpoint: template.baseUrl,
        credential: '',
        protocol: template.protocol,
        templateId: template.id,
        rows: const [],
      );

  NativeAccountDraft field(NativeAccountField field, String raw) =>
      NativeAccountDraft(
        name: field == NativeAccountField.name ? raw : name,
        endpoint: field == NativeAccountField.endpoint ? raw : endpoint,
        credential: field == NativeAccountField.credential ? raw : credential,
        protocol: protocol,
        templateId: templateId,
        rows: rows,
        billing: billing,
      );
  NativeAccountDraft withRows(List<ManualModelDraft> value) =>
      NativeAccountDraft(
        name: name,
        endpoint: endpoint,
        credential: credential,
        protocol: protocol,
        templateId: templateId,
        rows: List.unmodifiable(value),
        billing: billing,
      );
  NativeAccountDraft withBilling(BillingKind? value) => NativeAccountDraft(
    name: name,
    endpoint: endpoint,
    credential: credential,
    protocol: protocol,
    templateId: templateId,
    rows: rows,
    billing: value,
  );

  bool sameFields(NativeAccountDraft other) =>
      name == other.name &&
      endpoint == other.endpoint &&
      credential == other.credential &&
      protocol == other.protocol &&
      templateId == other.templateId &&
      sameModels(other) &&
      sameConnections(other) &&
      billing == other.billing;
  bool sameModels(NativeAccountDraft other) =>
      rows.length == other.rows.length &&
      List.generate(
        rows.length,
        (i) => rows[i].sameDeclaration(other.rows[i]),
      ).every((value) => value);
  bool sameConnections(NativeAccountDraft other) =>
      rows.length == other.rows.length &&
      List.generate(
        rows.length,
        (i) =>
            rows[i].id == other.rows[i].id &&
            rows[i].connection == other.rows[i].connection,
      ).every((value) => value);

  String? validate(AccountStrings strings) {
    if (name.trim().isEmpty ||
        endpoint.trim().isEmpty ||
        protocol.trim().isEmpty) {
      return strings['required'];
    }
    final ids = <String>{};
    for (final row in rows) {
      if (row.validate(strings) case final error?) return error;
      if (!ids.add(row.id.trim())) return strings['duplicateModel'];
    }
    return null;
  }

  List<AccountModelCommand> get commands => [
    for (final row in rows) row.command,
  ];
  CreateAccountCommand create(NativeAccountIdentity identity) =>
      CreateAccountCommand(
        identity: identity,
        name: name.trim(),
        protocol: protocol.trim(),
        templateId: templateId,
        baseUrl: endpoint.trim(),
        secret: credential.trim().isEmpty
            ? const AccountSecretCommand.clear()
            : AccountSecretCommand.replace(credential.trim()),
        initialBillingKind: billing,
        customModels: commands,
        modelConnectionModes: [
          for (final row in rows)
            if (row.connection != AccountConnection.automatic)
              AccountModelConnectionCommand(
                modelId: row.id.trim(),
                connectionMode: row.connection == AccountConnection.webSocket
                    ? 'web_socket'
                    : 'http',
              ),
        ],
      );
  PatchAccountCommand patch(
    NativeAccountIdentity identity,
    NativeAccountDraft baseline,
  ) => PatchAccountCommand(
    identity: identity,
    name: name == baseline.name
        ? const AccountTextPatch.keep()
        : AccountTextPatch.set(name.trim()),
    baseUrl: endpoint == baseline.endpoint
        ? const AccountTextPatch.keep()
        : AccountTextPatch.set(endpoint.trim()),
    protocol: protocol == baseline.protocol
        ? const AccountTextPatch.keep()
        : AccountTextPatch.set(protocol.trim()),
    templateId: templateId == baseline.templateId
        ? const AccountTextPatch.keep()
        : templateId == null
        ? const AccountTextPatch.restore()
        : AccountTextPatch.set(templateId!),
    secret: credential.trim().isEmpty || credential == baseline.credential
        ? const AccountSecretCommand.preserve()
        : AccountSecretCommand.replace(credential.trim()),
    customModels: sameModels(baseline)
        ? const AccountModelsPatch.keep()
        : AccountModelsPatch.set(commands),
  );
}

final class ManualModelDraft {
  const ManualModelDraft({
    required this.editorKey,
    this.id = '',
    this.name = '',
    this.context = '',
    this.output = '',
    this.wireApi = AccountWireApi.chatCompletions,
    this.connection = AccountConnection.automatic,
    this.savedId,
  });
  factory ManualModelDraft.fromCommand(
    AccountModelCommand model,
    String editorKey,
    AccountConnectionMode? connection,
  ) => ManualModelDraft(
    editorKey: editorKey,
    id: model.modelId,
    name: model.displayName,
    context: model.contextWindow?.toString() ?? '',
    output: model.maxOutputTokens?.toString() ?? '',
    wireApi: model.wireApi == 'responses'
        ? AccountWireApi.responses
        : AccountWireApi.chatCompletions,
    connection: switch (connection) {
      null => AccountConnection.automatic,
      AccountConnectionMode.http => AccountConnection.http,
      AccountConnectionMode.webSocket => AccountConnection.webSocket,
    },
    savedId: model.modelId,
  );
  final String editorKey;
  final String id;
  final String name;
  final String context;
  final String output;
  final AccountWireApi wireApi;
  final AccountConnection connection;
  final String? savedId;
  ManualModelDraft saved({String? key}) => ManualModelDraft(
    editorKey: key ?? editorKey,
    id: id,
    name: name,
    context: context,
    output: output,
    wireApi: wireApi,
    connection: connection,
    savedId: id.trim(),
  );
  ManualModelDraft change({
    ManualModelField? field,
    String? raw,
    AccountWireApi? api,
    AccountConnection? mode,
  }) => ManualModelDraft(
    editorKey: editorKey,
    id: field == ManualModelField.id && savedId == null ? raw! : id,
    name: field == ManualModelField.name ? raw! : name,
    context: field == ManualModelField.contextWindow ? raw! : context,
    output: field == ManualModelField.maxOutputTokens ? raw! : output,
    wireApi: api ?? wireApi,
    connection: mode ?? connection,
    savedId: savedId,
  );
  bool sameDeclaration(ManualModelDraft other) =>
      id == other.id &&
      name == other.name &&
      context == other.context &&
      output == other.output &&
      wireApi == other.wireApi;
  String? validate(AccountStrings strings) {
    if (id.trim().isEmpty) return strings['required'];
    if (savedId == null && connection == AccountConnection.webSocket) {
      return strings['connectionUnsupported'];
    }
    if ((context.isNotEmpty && positiveAccountInteger(context) == null) ||
        (output.isNotEmpty && positiveAccountInteger(output) == null)) {
      return strings['positiveInteger'];
    }
    final window = positiveAccountInteger(context);
    final maxOutput = positiveAccountInteger(output);
    if (window != null && maxOutput != null && maxOutput > window) {
      return strings['outputBudget'];
    }
    return null;
  }

  AccountModelCommand get command => AccountModelCommand(
    modelId: id.trim(),
    displayName: name.trim().isEmpty ? id.trim() : name.trim(),
    wireApi: wireApi == AccountWireApi.responses
        ? 'responses'
        : 'chat_completions',
    contextWindow: positiveAccountInteger(context),
    maxOutputTokens: positiveAccountInteger(output),
  );
  ManualAccountModelPresentation presentation(
    AccountStrings strings,
    AccountModelView? descriptor,
  ) => ManualAccountModelPresentation(
    editorKey: editorKey,
    id: AccountTextPresentation(
      raw: id,
      error: id.trim().isEmpty ? strings['required'] : null,
    ),
    name: AccountTextPresentation(raw: name),
    contextWindow: AccountTextPresentation(
      raw: context,
      error: context.isNotEmpty && positiveAccountInteger(context) == null
          ? strings['positiveInteger']
          : null,
    ),
    maxOutputTokens: AccountTextPresentation(
      raw: output,
      error: output.isNotEmpty && positiveAccountInteger(output) == null
          ? strings['positiveInteger']
          : null,
    ),
    wireApi: wireApi,
    allowedWireApis: AccountWireApi.values,
    connection: connection,
    allowedConnections: [
      AccountConnection.automatic,
      if (savedId == null ||
          descriptor?.supportedConnectionModes.contains('http') == true)
        AccountConnection.http,
      if (savedId != null &&
          descriptor?.supportedConnectionModes.contains('web_socket') == true)
        AccountConnection.webSocket,
    ],
    canRemove: true,
    canEditId: savedId == null,
    error: validate(strings),
  );
}
