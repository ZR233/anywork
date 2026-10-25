import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart' show BillingKind;
import 'package:anywork_client/resources_ports.dart';

import 'configuration_command_fixture.dart';
import 'profile_command_fixture.dart';
import 'profile_native_pin.dart';
import 'profile_reload_fixture.dart';
import 'scripted_feed.dart';

AgentProfileSnapshot profileSnapshot({
  String accountId = 'account-0',
  String modelId = 'text',
  String? effort = 'low',
}) => AgentProfileSnapshot(
  profileId: 'custom_profile',
  displayName: 'Profile',
  description: 'A custom profile',
  whenToUse: 'For this task',
  systemInstructions: 'Keep the original instructions.',
  accountId: accountId,
  modelId: modelId,
  effort: effort,
  source: 'user',
  revision: 'native-profile-7',
  contentHash: 'native-content-hash',
  system: false,
  enabled: true,
  workspaceMode: AgentWorkspaceMode.directory,
);

/// An explicit native open reply, not a reconnect/resync implementation. Only
/// the original first open is automatic; later handles belong to the test.
final class ProfileConfigurationOpen {
  ProfileConfigurationOpen(this.index);
  final int index;
  final reply = Completer<FeedConnection<ConfigurationFrame>>();
  ScriptedFeed<ConfigurationFrame>? native;
  void accept(ScriptedFeed<ConfigurationFrame> feed) {
    native = feed;
    reply.complete(feed);
  }

  ScriptedFeed<ConfigurationFrame> acceptNew(String feedId) {
    final feed = ScriptedFeed<ConfigurationFrame>(
      feedId: feedId,
      sequenceOf: (frame) =>
          frame is ConfigurationData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ConfigurationData,
    );
    accept(feed);
    return feed;
  }
}

final class ProfileRoleCall {
  ProfileRoleCall(this.target, this.roleId, this.pin);
  final ConfigurationRoleReadTarget target;
  final String roleId;
  final ProfileNativePin pin;
  final reply = Completer<RoleRouteRead>();
}

/// Declared native Settings/Profile versions, not a validator, reducer or CAS
/// retry implementation. Each save reply is explicitly controlled by its test.
final class ProfileConfigurationPort implements ConfigurationPort {
  ProfileConfigurationPort({
    required this.origin,
    required List<String> accounts,
    this.profile,
  }) : accounts = List.unmodifiable(accounts) {
    profileSnapshots[7] = profile;
  }
  final ProductReadOrigin origin;
  final List<String> accounts;
  final AgentProfileSnapshot? profile;
  final feed = ScriptedFeed<ConfigurationFrame>(
    feedId: 'profile-settings',
    sequenceOf: (frame) =>
        frame is ConfigurationData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ConfigurationData,
  );
  final profilesFeed = ScriptedFeed<AgentProfilesFrame>(
    feedId: 'profile-catalog',
    sequenceOf: (frame) =>
        frame is AgentProfilesData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AgentProfilesData,
  );
  bool scriptProfileCommands = false;
  bool scriptReload = false;
  final saves = <RecordedProfileCall<SaveProfileRequest>>[];
  final _saveWaiters =
      <int, Completer<RecordedProfileCall<SaveProfileRequest>>>{};
  final enabledChanges =
      <RecordedProfileCall<SetSystemProfileEnabledRequest>>[];
  final _enabledWaiters =
      <int, Completer<RecordedProfileCall<SetSystemProfileEnabledRequest>>>{};
  final reloads = <RecordedProfileReload>[];
  final _reloadWaiters = <int, Completer<RecordedProfileReload>>{};
  final profileLookups = <RecordedProfileLookup>[];
  final _profileLookupWaiters = <int, Completer<RecordedProfileLookup>>{};
  final reloadLookups = <RecordedProfileReloadLookup>[];
  final _reloadLookupWaiters = <int, Completer<RecordedProfileReloadLookup>>{};
  final profileSnapshots = <int, AgentProfileSnapshot?>{};
  final settingsRevisions = <int>{1};
  final configurationOpens = <ProfileConfigurationOpen>[];
  final _configurationOpenWaiters =
      <int, Completer<ProfileConfigurationOpen>>{};
  final _roleTargets = <ConfigurationRoleReadTarget>{};
  final roleCalls = <ProfileRoleCall>[];
  final rolePins = <ProfileNativePin>[];
  final _roleWaiters = <int, Completer<ProfileRoleCall>>{};
  ConfigurationRoleReadTarget? _roleRead;
  int _configurationPublication = 1;
  int _settingsRevision = 1;
  int _profilesRevision = 7;
  int _profilesPublication = 1;
  int _callId = 0;

  Future<RecordedProfileCall<SaveProfileRequest>> saved(int index) =>
      index < saves.length
      ? Future.value(saves[index])
      : _saveWaiters
            .putIfAbsent(
              index,
              Completer<RecordedProfileCall<SaveProfileRequest>>.new,
            )
            .future;

  Future<RecordedProfileCall<SetSystemProfileEnabledRequest>> enabledChanged(
    int index,
  ) => index < enabledChanges.length
      ? Future.value(enabledChanges[index])
      : _enabledWaiters
            .putIfAbsent(
              index,
              Completer<RecordedProfileCall<SetSystemProfileEnabledRequest>>
                  .new,
            )
            .future;

  Future<RecordedProfileReload> reloaded(int index) => index < reloads.length
      ? Future.value(reloads[index])
      : _reloadWaiters
            .putIfAbsent(index, Completer<RecordedProfileReload>.new)
            .future;

  Future<RecordedProfileLookup> profileLookedUp(int index) =>
      index < profileLookups.length
      ? Future.value(profileLookups[index])
      : _profileLookupWaiters
            .putIfAbsent(index, Completer<RecordedProfileLookup>.new)
            .future;

  Future<RecordedProfileReloadLookup> reloadLookedUp(int index) =>
      index < reloadLookups.length
      ? Future.value(reloadLookups[index])
      : _reloadLookupWaiters
            .putIfAbsent(index, Completer<RecordedProfileReloadLookup>.new)
            .future;

  Future<ProfileConfigurationOpen> configurationOpened(int index) =>
      index < configurationOpens.length
      ? Future.value(configurationOpens[index])
      : _configurationOpenWaiters
            .putIfAbsent(index, Completer<ProfileConfigurationOpen>.new)
            .future;

  Future<ProfileRoleCall> roleCalled(int index) => index < roleCalls.length
      ? Future.value(roleCalls[index])
      : _roleWaiters.putIfAbsent(index, Completer<ProfileRoleCall>.new).future;

  /// Test-declared native material, never a pair assembled from Repository
  /// latest headers. Presence/default answers still require an explicit reply.
  void declareRolePair(
    ConfigurationRoleReadTarget target, {
    bool initial = false,
  }) {
    _roleTargets.add(target);
    if (initial) _roleRead = target;
  }

  ConfigurationHeader _configurationHeader() => ConfigurationHeader(
    source: profileSource(_settingsRevision),
    configurationRevision: _settingsRevision,
    updatedAt: _settingsRevision,
    reference: ConfigurationReadRef(entry: 1, revision: _settingsRevision),
    roleRead: _roleRead,
  );

  /// Native declarations/publications are independent of command replies.
  /// No request is applied here and no Repository target is marked observed.
  Future<void> publishSettings(int revision) async {
    settingsRevisions.add(revision);
    _settingsRevision = revision;
    final previous = _configurationPublication++;
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: _configurationPublication,
        event: ConfigurationEvent.change(
          stamp: profileStamp(origin, _configurationPublication),
          baseRevision: previous,
          value: ConfigurationChange(
            header: _configurationHeader(),
            baseCollectionRevision: 1,
            collection: profileCollection(1, accounts.length),
            upserted: const [],
            removedEntries: const [],
          ),
        ),
      ),
    );
    await feed.acknowledged(_configurationPublication);
  }

  Future<void> publishProfiles(int revision) async {
    if (!profileSnapshots.containsKey(revision))
      throw StateError('Declare the original Profiles material first');
    final previous = _profilesRevision;
    _profilesRevision = revision;
    final sequence = ++_profilesPublication;
    profilesFeed.emit(
      AgentProfilesFrame.data(
        deliverySequence: sequence,
        event: AgentProfilesEvent.change(
          stamp: profileStamp(origin, revision),
          baseRevision: previous,
          value: AgentProfilesChange(
            header: AgentProfilesHeader(
              source: profileSource(revision),
              profilesRevision: revision,
              reference: AgentProfilesReadRef(entry: 1, revision: revision),
            ),
            baseCollectionRevision: previous,
            collection: profileCollection(
              revision,
              profileSnapshots[revision] == null ? 0 : 1,
            ),
            upserted: [
              if (profileSnapshots[revision] != null)
                ProductEntityRef(entry: 10, revision: revision),
            ],
            removedEntries: profileSnapshots[revision] == null
                ? const [10]
                : const [],
          ),
        ),
      ),
    );
    await profilesFeed.acknowledged(sequence);
  }

  Future<void> publishCasBaseline(
    ScriptedFeed<ConfigurationFrame> native,
    int revision, {
    ProductReadOrigin? sourceOrigin,
  }) async {
    settingsRevisions.add(revision);
    _settingsRevision = revision;
    _configurationPublication = revision;
    await native.listened.future;
    native.emit(
      ConfigurationFrame.data(
        deliverySequence: 1,
        event: ConfigurationEvent.baseline(
          identity: profileIdentity(
            native.feedId,
            sourceOrigin ?? origin,
            ProductResource.configuration,
          ),
          stamp: profileStamp(sourceOrigin ?? origin, revision),
          value: ConfigurationBaseline(
            header: _configurationHeader(),
            collection: profileCollection(1, accounts.length),
          ),
        ),
      ),
    );
    await native.acknowledged(1);
  }

  Future<void> publishRolePair(ConfigurationRoleReadTarget? target) async {
    if (target != null && !_roleTargets.contains(target))
      throw StateError('Declare the original native role pair first');
    _roleRead = target;
    final previous = _configurationPublication++;
    // Pair changes publish independently of the unchanged Settings value/CAS.
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: _configurationPublication,
        event: ConfigurationEvent.change(
          stamp: profileStamp(origin, _configurationPublication),
          baseRevision: previous,
          value: ConfigurationChange(
            header: _configurationHeader(),
            baseCollectionRevision: 1,
            collection: profileCollection(1, accounts.length),
            upserted: const [],
            removedEntries: const [],
          ),
        ),
      ),
    );
    await feed.acknowledged(_configurationPublication);
  }

  void baseline() {
    feed.emit(
      ConfigurationFrame.data(
        deliverySequence: 1,
        event: ConfigurationEvent.baseline(
          identity: profileIdentity(
            feed.feedId,
            origin,
            ProductResource.configuration,
          ),
          stamp: profileStamp(origin, 1),
          value: ConfigurationBaseline(
            header: _configurationHeader(),
            collection: profileCollection(1, accounts.length),
          ),
        ),
      ),
    );
    // Profiles has a separate clock, not the Settings CAS base.
    profilesFeed.emit(
      AgentProfilesFrame.data(
        deliverySequence: 1,
        event: AgentProfilesEvent.baseline(
          identity: profileIdentity(
            profilesFeed.feedId,
            origin,
            ProductResource.agentProfiles,
          ),
          stamp: profileStamp(origin, 7),
          value: AgentProfilesBaseline(
            header: AgentProfilesHeader(
              source: profileSource(7),
              profilesRevision: 7,
              reference: const AgentProfilesReadRef(entry: 1, revision: 7),
            ),
            collection: profileCollection(7, profile == null ? 0 : 1),
          ),
        ),
      ),
    );
  }

  /// Explicit new native baseline. Settings/CAS and account material remain
  /// fixed; only the test-declared projection/pair and feed identity advance.
  Future<void> publishConfigurationBaseline(
    ScriptedFeed<ConfigurationFrame> native, {
    required ConfigurationRoleReadTarget target,
    required int projectionRevision,
  }) async {
    if (!_roleTargets.contains(target))
      throw StateError('Declare the recovered native role pair first');
    await native.listened.future;
    native.emit(
      ConfigurationFrame.data(
        deliverySequence: 1,
        event: ConfigurationEvent.baseline(
          identity: profileIdentity(
            native.feedId,
            origin,
            ProductResource.configuration,
          ),
          stamp: profileStamp(origin, projectionRevision),
          value: ConfigurationBaseline(
            header: _configurationHeader().copyWith(roleRead: target),
            collection: profileCollection(1, accounts.length),
          ),
        ),
      ),
    );
    await native.acknowledged(1);
  }

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() {
    final call = ProfileConfigurationOpen(configurationOpens.length);
    configurationOpens.add(call);
    _configurationOpenWaiters.remove(call.index)?.complete(call);
    if (call.index == 0) call.accept(feed);
    return call.reply.future;
  }

  @override
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles() async =>
      profilesFeed;
  @override
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  ) =>
      throw UnsupportedError('This Profile fixture has no scripted Start read');
  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) =>
      rejectUnscriptedConfigurationBegin(
        'This Profile fixture has no scripted account begin',
      );
  @override
  Future<ConfigurationCommandCall> setDefaultAccount(
    SetDefaultAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted default-account begin',
  );
  @override
  Future<ConfigurationCommandCall> removeAccount(
    RemoveAccountRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted account-removal begin',
  );
  @override
  Future<ConfigurationCommandCall> removeAccountModel(
    RemoveAccountModelRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted model-removal begin',
  );
  @override
  Future<ConfigurationCommandCall> setAccountModelEnabled(
    SetAccountModelEnabledRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted model-enabled begin',
  );
  @override
  Future<ConfigurationCommandCall> setAccountBillingKind(
    SetAccountBillingKindRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted billing begin',
  );
  @override
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted settings-field begin',
  );
  @override
  Future<ConfigurationCommandCall> setPermission(
    UpdatePermissionSettingsRequest request,
  ) => rejectUnscriptedConfigurationBegin(
    'This Profile fixture has no scripted permission begin',
  );
  @override
  Future<ConfigurationCommandCall?> findConfigurationCommand(
    OperationId operationId,
  ) => throw UnsupportedError(
    'This Profile fixture has no scripted Configuration command lookup',
  );
  @override
  Future<ConfigurationRoleReadConnection> openRoleRead(
    ConfigurationRoleReadTarget target,
  ) async {
    if (!_roleTargets.contains(target))
      throw UnsupportedError('The original native role pair was not scripted');
    final pin = _RolePin('profile-role-${rolePins.length + 1}', target, (call) {
      roleCalls.add(call);
      _roleWaiters.remove(roleCalls.length - 1)?.complete(call);
    });
    rolePins.add(pin);
    return pin;
  }

  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != this.origin ||
        reference.entry != 1 ||
        !settingsRevisions.contains(reference.revision)) {
      throw StateError('Unscripted native Settings pin');
    }
    return _SettingsPin(accounts);
  }

  @override
  Future<AgentProfilesReadConnection> openAgentProfilesRead(
    AgentProfilesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != this.origin ||
        reference.entry != 1 ||
        !profileSnapshots.containsKey(reference.revision)) {
      throw StateError('Unscripted native Profiles pin');
    }
    return _ProfilesPin(
      profileSnapshots[reference.revision],
      reference.revision,
    );
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != this.origin || reference.entry != 9)
      throw StateError('Unscripted Settings source');
    return ProfileSourcePin(reference.revision);
  }

  @override
  Future<ProfileCommandCall> saveProfile(SaveProfileRequest request) {
    if (!scriptProfileCommands)
      rejectUnscriptedConfigurationBegin(
        'This Profile fixture has no scripted profile begin',
      );
    final call = RecordedProfileCall(
      request,
      ScriptedProfileCommandCall(
        callId: 'native-profile-${++_callId}',
        operationId: request.operationId,
      ),
    );
    saves.add(call);
    _saveWaiters.remove(saves.length - 1)?.complete(call);
    return call.beginReply.future;
  }

  @override
  Future<ProfileCommandCall> setSystemProfileEnabled(
    SetSystemProfileEnabledRequest request,
  ) {
    if (!scriptProfileCommands)
      rejectUnscriptedConfigurationBegin(
        'This Profile fixture has no scripted system-enabled begin',
      );
    final call = RecordedProfileCall(
      request,
      ScriptedProfileCommandCall(
        callId: 'native-profile-${++_callId}',
        operationId: request.operationId,
      ),
    );
    enabledChanges.add(call);
    _enabledWaiters.remove(enabledChanges.length - 1)?.complete(call);
    return call.beginReply.future;
  }

  @override
  Future<ProfileCommandCall?> findProfileCommand(OperationId operationId) {
    final lookup = RecordedProfileLookup(operationId);
    profileLookups.add(lookup);
    _profileLookupWaiters.remove(profileLookups.length - 1)?.complete(lookup);
    return lookup.reply.future;
  }

  @override
  Future<ConfigurationReloadCall> reload(ConfigurationReloadRequest request) {
    if (!scriptReload)
      rejectUnscriptedConfigurationBegin(
        'This Profile fixture has no scripted reload begin',
      );
    final call = RecordedProfileReload(
      request,
      ScriptedProfileReloadCall(
        callId: 'native-reload-${++_callId}',
        operationId: request.operationId,
      ),
    );
    reloads.add(call);
    _reloadWaiters.remove(reloads.length - 1)?.complete(call);
    return call.beginReply.future;
  }

  @override
  Future<ConfigurationReloadCall?> findConfigurationReload(
    OperationId operationId,
  ) {
    final lookup = RecordedProfileReloadLookup(operationId);
    reloadLookups.add(lookup);
    _reloadLookupWaiters.remove(reloadLookups.length - 1)?.complete(lookup);
    return lookup.reply.future;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Profile Settings capability: ${invocation.memberName}',
  );
}

final class _SettingsPin extends ProfileNativePin
    implements ConfigurationReadConnection {
  _SettingsPin(this.accountIds) : super('profile-settings-pin');
  final List<String> accountIds;
  ProductEntityRef _reference(int index) =>
      ProductEntityRef(entry: 100 + index, revision: 1);
  @override
  Future<ConfigurationEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final end = (offset + limit).clamp(0, accountIds.length);
    return ConfigurationEntryPage(
      collection: profileCollection(1, accountIds.length),
      offset: offset,
      items: [for (var index = offset; index < end; index++) _reference(index)],
      nextOffset: end == accountIds.length ? null : end,
    );
  }

  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) async {
    admit();
    final index = reference.entry - 100;
    if (index < 0 ||
        index >= accountIds.length ||
        reference != _reference(index))
      throw StateError('Unscripted account row');
    return ConfigurationEntityRead(
      reference: reference,
      value: AccountConfigurationRead(
        pricingEnabled: false,
        accountId: ReadText.inline(text: accountIds[index]),
        templateId: null,
        billingKind: BillingKind.unknown,
        billingKindOverride: null,
        disabledModels: const TypedListRef(listId: 0, total: 0),
        protocol: const ReadText.inline(text: 'openai'),
        name: ReadText.inline(text: accountIds[index]),
        baseUrl: const ReadText.inline(text: 'https://profile.invalid'),
        hasBearerToken: false,
        bearerTokenEnv: null,
        usageQueryRevision: 1,
        customModels: const TypedListRef(listId: 0, total: 0),
        modelConnectionModes: const TypedListRef(listId: 0, total: 0),
        modelAutoCompactLimits: const TypedListRef(listId: 0, total: 0),
        catalogId: null,
      ),
    );
  }
}

final class _ProfilesPin extends ProfileNativePin
    implements AgentProfilesReadConnection {
  _ProfilesPin(this.profile, this.revision)
    : super('profile-catalog-pin-$revision');
  final AgentProfileSnapshot? profile;
  final int revision;
  ProductEntityRef get _reference =>
      ProductEntityRef(entry: 10, revision: revision);
  @override
  Future<AgentProfilesReadHeader> header() async {
    admit();
    return AgentProfilesReadHeader(
      profiles: TypedListRef(listId: 1, total: profile == null ? 0 : 1),
      diagnostics: const TypedListRef(listId: 2, total: 0),
    );
  }

  @override
  Future<AgentProfilesEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final refs = [if (profile != null) _reference];
    final end = (offset + limit).clamp(0, refs.length);
    return AgentProfilesEntryPage(
      collection: profileCollection(revision, refs.length),
      offset: offset,
      items: refs.sublist(offset, end),
      nextOffset: end == refs.length ? null : end,
    );
  }

  @override
  Future<ProductEntityRef?> lookupProfile(String id) async {
    admit();
    return profile?.profileId == id ? _reference : null;
  }

  @override
  Future<AgentProfilesEntityRead> entity(ProductEntityRef reference) async {
    admit();
    final value = profile;
    if (value == null || reference != _reference)
      throw StateError('Unscripted Profile row');
    return AgentProfilesEntityRead(
      reference: reference,
      value: AgentProfileRead(
        profileId: ReadText.inline(text: value.profileId),
        displayName: ReadText.inline(text: value.displayName),
        description: ReadText.inline(text: value.description),
        whenToUse: ReadText.inline(text: value.whenToUse),
        systemInstructions: ReadText.inline(text: value.systemInstructions),
        accountId: ReadText.inline(text: value.accountId),
        modelId: ReadText.inline(text: value.modelId),
        effort: value.effort == null
            ? null
            : ReadText.inline(text: value.effort!),
        source: ReadText.inline(text: value.source),
        revision: ReadText.inline(text: value.revision),
        contentHash: ReadText.inline(text: value.contentHash),
        system: value.system,
        enabled: value.enabled,
        workspaceMode: value.workspaceMode,
      ),
    );
  }
}

final class _RolePin extends ProfileNativePin
    implements ConfigurationRoleReadConnection {
  _RolePin(super.id, this.target, this.called);
  final ConfigurationRoleReadTarget target;
  final void Function(ProfileRoleCall call) called;
  @override
  Future<ConfigurationRoleReadTarget> header() async {
    admit();
    return target;
  }

  @override
  Future<RoleRouteRead> roleRoute(String roleId) {
    admit();
    final call = ProfileRoleCall(target, roleId, this);
    called(call);
    return reply(call.reply.future);
  }
}
