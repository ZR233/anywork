// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConfigurationValue {


/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationValueCopyWith<ConfigurationValue> get copyWith => _$ConfigurationValueCopyWithImpl<ConfigurationValue>(this as ConfigurationValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationValue&&(identical(other.defaultAccountId, _this.defaultAccountId) || other.defaultAccountId == _this.defaultAccountId)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&const DeepCollectionEquality().equals(other.modeModelRoutes, _this.modeModelRoutes)&&const DeepCollectionEquality().equals(other.roles, _this.roles)&&(identical(other.permissionMode, _this.permissionMode) || other.permissionMode == _this.permissionMode)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&(identical(other.skills, _this.skills) || other.skills == _this.skills)&&const DeepCollectionEquality().equals(other.mcpServers, _this.mcpServers)&&(identical(other.general, _this.general) || other.general == _this.general)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepseekWebSearch, _this.deepseekWebSearch) || other.deepseekWebSearch == _this.deepseekWebSearch));
}


@override
int get hashCode {
  final _this = this as ConfigurationValue;
  return Object.hash(runtimeType,_this.defaultAccountId,const DeepCollectionEquality().hash(_this.accounts),const DeepCollectionEquality().hash(_this.modeModelRoutes),const DeepCollectionEquality().hash(_this.roles),_this.permissionMode,_this.instructions,_this.skills,const DeepCollectionEquality().hash(_this.mcpServers),_this.general,_this.delegation,_this.webSearch,_this.deepseekWebSearch);
}

@override
String toString() {
  final _this = this as ConfigurationValue;
  return 'ConfigurationValue(defaultAccountId: ${_this.defaultAccountId}, accounts: ${_this.accounts}, modeModelRoutes: ${_this.modeModelRoutes}, roles: ${_this.roles}, permissionMode: ${_this.permissionMode}, instructions: ${_this.instructions}, skills: ${_this.skills}, mcpServers: ${_this.mcpServers}, general: ${_this.general}, delegation: ${_this.delegation}, webSearch: ${_this.webSearch}, deepseekWebSearch: ${_this.deepseekWebSearch})';
}


}

/// @nodoc
abstract mixin class $ConfigurationValueCopyWith<$Res>  {
  factory $ConfigurationValueCopyWith(ConfigurationValue value, $Res Function(ConfigurationValue) _then) = _$ConfigurationValueCopyWithImpl;
@useResult
$Res call({
 String? defaultAccountId, List<AccountConfiguration> accounts, List<ModeModelRoute> modeModelRoutes, List<RoleModelRoute> roles, String permissionMode, InstructionsSettings instructions, SkillsSettings skills, List<McpConfiguration> mcpServers, GeneralSettings general, DelegationSettings delegation, WebSearchConfiguration webSearch, DeepSeekSearchConfiguration deepseekWebSearch
});


$InstructionsSettingsCopyWith<$Res> get instructions;$SkillsSettingsCopyWith<$Res> get skills;$GeneralSettingsCopyWith<$Res> get general;$DelegationSettingsCopyWith<$Res> get delegation;$WebSearchConfigurationCopyWith<$Res> get webSearch;$DeepSeekSearchConfigurationCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class _$ConfigurationValueCopyWithImpl<$Res>
    implements $ConfigurationValueCopyWith<$Res> {
  _$ConfigurationValueCopyWithImpl(this._self, this._then);

  final ConfigurationValue _self;
  final $Res Function(ConfigurationValue) _then;

/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? defaultAccountId = freezed,Object? accounts = null,Object? modeModelRoutes = null,Object? roles = null,Object? permissionMode = null,Object? instructions = null,Object? skills = null,Object? mcpServers = null,Object? general = null,Object? delegation = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(ConfigurationValue(
defaultAccountId: freezed == defaultAccountId ? _self.defaultAccountId : defaultAccountId // ignore: cast_nullable_to_non_nullable
as String?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AccountConfiguration>,modeModelRoutes: null == modeModelRoutes ? _self.modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as List<ModeModelRoute>,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<RoleModelRoute>,permissionMode: null == permissionMode ? _self.permissionMode : permissionMode // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as InstructionsSettings,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as SkillsSettings,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpConfiguration>,general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as GeneralSettings,delegation: null == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchConfiguration,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfiguration,
  ));
}
/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsCopyWith<$Res> get instructions {

  return $InstructionsSettingsCopyWith<$Res>(_self.instructions, (value) {
    return _then(_self.copyWith(instructions: value));
  });
}/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsSettingsCopyWith<$Res> get skills {

  return $SkillsSettingsCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsCopyWith<$Res> get general {

  return $GeneralSettingsCopyWith<$Res>(_self.general, (value) {
    return _then(_self.copyWith(general: value));
  });
}/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get delegation {

  return $DelegationSettingsCopyWith<$Res>(_self.delegation, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationCopyWith<$Res> get webSearch {

  return $WebSearchConfigurationCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationCopyWith<$Res> get deepseekWebSearch {

  return $DeepSeekSearchConfigurationCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationValue].
extension ConfigurationValuePatterns on ConfigurationValue {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$AccountConfiguration {


/// Create a copy of AccountConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<AccountConfiguration> get copyWith => _$AccountConfigurationCopyWithImpl<AccountConfiguration>(this as AccountConfiguration, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountConfiguration&&(identical(other.pricingEnabled, _this.pricingEnabled) || other.pricingEnabled == _this.pricingEnabled)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.billingKindOverride, _this.billingKindOverride) || other.billingKindOverride == _this.billingKindOverride)&&const DeepCollectionEquality().equals(other.disabledModels, _this.disabledModels)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.templateId, _this.templateId) || other.templateId == _this.templateId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.hasBearerToken, _this.hasBearerToken) || other.hasBearerToken == _this.hasBearerToken)&&(identical(other.bearerTokenEnv, _this.bearerTokenEnv) || other.bearerTokenEnv == _this.bearerTokenEnv)&&(identical(other.usageQueryRevision, _this.usageQueryRevision) || other.usageQueryRevision == _this.usageQueryRevision)&&const DeepCollectionEquality().equals(other.customModels, _this.customModels)&&const DeepCollectionEquality().equals(other.modelConnectionModes, _this.modelConnectionModes)&&const DeepCollectionEquality().equals(other.modelAutoCompactLimits, _this.modelAutoCompactLimits)&&(identical(other.catalogId, _this.catalogId) || other.catalogId == _this.catalogId));
}


@override
int get hashCode {
  final _this = this as AccountConfiguration;
  return Object.hash(runtimeType,_this.pricingEnabled,_this.billingKind,_this.billingKindOverride,const DeepCollectionEquality().hash(_this.disabledModels),_this.accountId,_this.templateId,_this.protocol,_this.name,_this.baseUrl,_this.hasBearerToken,_this.bearerTokenEnv,_this.usageQueryRevision,const DeepCollectionEquality().hash(_this.customModels),const DeepCollectionEquality().hash(_this.modelConnectionModes),const DeepCollectionEquality().hash(_this.modelAutoCompactLimits),_this.catalogId);
}

@override
String toString() {
  final _this = this as AccountConfiguration;
  return 'AccountConfiguration(pricingEnabled: ${_this.pricingEnabled}, billingKind: ${_this.billingKind}, billingKindOverride: ${_this.billingKindOverride}, disabledModels: ${_this.disabledModels}, accountId: ${_this.accountId}, templateId: ${_this.templateId}, protocol: ${_this.protocol}, name: ${_this.name}, baseUrl: ${_this.baseUrl}, hasBearerToken: ${_this.hasBearerToken}, bearerTokenEnv: ${_this.bearerTokenEnv}, usageQueryRevision: ${_this.usageQueryRevision}, customModels: ${_this.customModels}, modelConnectionModes: ${_this.modelConnectionModes}, modelAutoCompactLimits: ${_this.modelAutoCompactLimits}, catalogId: ${_this.catalogId})';
}


}

/// @nodoc
abstract mixin class $AccountConfigurationCopyWith<$Res>  {
  factory $AccountConfigurationCopyWith(AccountConfiguration value, $Res Function(AccountConfiguration) _then) = _$AccountConfigurationCopyWithImpl;
@useResult
$Res call({
 bool pricingEnabled, BillingKind billingKind, BillingKind? billingKindOverride, List<String> disabledModels, String accountId, String? templateId, String protocol, String name, String baseUrl, bool hasBearerToken, String? bearerTokenEnv, int usageQueryRevision, List<CustomModelConfiguration> customModels, List<ModelConnection> modelConnectionModes, List<ModelAutoCompact> modelAutoCompactLimits, String? catalogId
});




}
/// @nodoc
class _$AccountConfigurationCopyWithImpl<$Res>
    implements $AccountConfigurationCopyWith<$Res> {
  _$AccountConfigurationCopyWithImpl(this._self, this._then);

  final AccountConfiguration _self;
  final $Res Function(AccountConfiguration) _then;

/// Create a copy of AccountConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pricingEnabled = null,Object? billingKind = null,Object? billingKindOverride = freezed,Object? disabledModels = null,Object? accountId = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? hasBearerToken = null,Object? bearerTokenEnv = freezed,Object? usageQueryRevision = null,Object? customModels = null,Object? modelConnectionModes = null,Object? modelAutoCompactLimits = null,Object? catalogId = freezed,}) {
  return _then(AccountConfiguration(
pricingEnabled: null == pricingEnabled ? _self.pricingEnabled : pricingEnabled // ignore: cast_nullable_to_non_nullable
as bool,billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,billingKindOverride: freezed == billingKindOverride ? _self.billingKindOverride : billingKindOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,disabledModels: null == disabledModels ? _self.disabledModels : disabledModels // ignore: cast_nullable_to_non_nullable
as List<String>,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as String?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,hasBearerToken: null == hasBearerToken ? _self.hasBearerToken : hasBearerToken // ignore: cast_nullable_to_non_nullable
as bool,bearerTokenEnv: freezed == bearerTokenEnv ? _self.bearerTokenEnv : bearerTokenEnv // ignore: cast_nullable_to_non_nullable
as String?,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as List<CustomModelConfiguration>,modelConnectionModes: null == modelConnectionModes ? _self.modelConnectionModes : modelConnectionModes // ignore: cast_nullable_to_non_nullable
as List<ModelConnection>,modelAutoCompactLimits: null == modelAutoCompactLimits ? _self.modelAutoCompactLimits : modelAutoCompactLimits // ignore: cast_nullable_to_non_nullable
as List<ModelAutoCompact>,catalogId: freezed == catalogId ? _self.catalogId : catalogId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountConfiguration].
extension AccountConfigurationPatterns on AccountConfiguration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$CustomModelConfiguration {


/// Create a copy of CustomModelConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomModelConfigurationCopyWith<CustomModelConfiguration> get copyWith => _$CustomModelConfigurationCopyWithImpl<CustomModelConfiguration>(this as CustomModelConfiguration, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CustomModelConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomModelConfiguration&&const DeepCollectionEquality().equals(other.inputCapabilities, _this.inputCapabilities)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&const DeepCollectionEquality().equals(other.reasoningEfforts, _this.reasoningEfforts)&&(identical(other.baseInstructions, _this.baseInstructions) || other.baseInstructions == _this.baseInstructions)&&(identical(other.wireApi, _this.wireApi) || other.wireApi == _this.wireApi)&&const DeepCollectionEquality().equals(other.supportedConnectionModes, _this.supportedConnectionModes)&&(identical(other.defaultConnectionMode, _this.defaultConnectionMode) || other.defaultConnectionMode == _this.defaultConnectionMode));
}


@override
int get hashCode {
  final _this = this as CustomModelConfiguration;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.inputCapabilities),_this.contextWindow,_this.maxOutputTokens,_this.modelId,_this.displayName,const DeepCollectionEquality().hash(_this.reasoningEfforts),_this.baseInstructions,_this.wireApi,const DeepCollectionEquality().hash(_this.supportedConnectionModes),_this.defaultConnectionMode);
}

@override
String toString() {
  final _this = this as CustomModelConfiguration;
  return 'CustomModelConfiguration(inputCapabilities: ${_this.inputCapabilities}, contextWindow: ${_this.contextWindow}, maxOutputTokens: ${_this.maxOutputTokens}, modelId: ${_this.modelId}, displayName: ${_this.displayName}, reasoningEfforts: ${_this.reasoningEfforts}, baseInstructions: ${_this.baseInstructions}, wireApi: ${_this.wireApi}, supportedConnectionModes: ${_this.supportedConnectionModes}, defaultConnectionMode: ${_this.defaultConnectionMode})';
}


}

/// @nodoc
abstract mixin class $CustomModelConfigurationCopyWith<$Res>  {
  factory $CustomModelConfigurationCopyWith(CustomModelConfiguration value, $Res Function(CustomModelConfiguration) _then) = _$CustomModelConfigurationCopyWithImpl;
@useResult
$Res call({
 List<ModelInputCapability> inputCapabilities, int? contextWindow, int? maxOutputTokens, String modelId, String displayName, List<String> reasoningEfforts, String baseInstructions, String wireApi, List<String> supportedConnectionModes, String defaultConnectionMode
});




}
/// @nodoc
class _$CustomModelConfigurationCopyWithImpl<$Res>
    implements $CustomModelConfigurationCopyWith<$Res> {
  _$CustomModelConfigurationCopyWithImpl(this._self, this._then);

  final CustomModelConfiguration _self;
  final $Res Function(CustomModelConfiguration) _then;

/// Create a copy of CustomModelConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputCapabilities = null,Object? contextWindow = freezed,Object? maxOutputTokens = freezed,Object? modelId = null,Object? displayName = null,Object? reasoningEfforts = null,Object? baseInstructions = null,Object? wireApi = null,Object? supportedConnectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(CustomModelConfiguration(
inputCapabilities: null == inputCapabilities ? _self.inputCapabilities : inputCapabilities // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapability>,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,reasoningEfforts: null == reasoningEfforts ? _self.reasoningEfforts : reasoningEfforts // ignore: cast_nullable_to_non_nullable
as List<String>,baseInstructions: null == baseInstructions ? _self.baseInstructions : baseInstructions // ignore: cast_nullable_to_non_nullable
as String,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as String,supportedConnectionModes: null == supportedConnectionModes ? _self.supportedConnectionModes : supportedConnectionModes // ignore: cast_nullable_to_non_nullable
as List<String>,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomModelConfiguration].
extension CustomModelConfigurationPatterns on CustomModelConfiguration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$ModelConnection {

 String get modelId; String get connectionMode;
/// Create a copy of ModelConnection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelConnectionCopyWith<ModelConnection> get copyWith => _$ModelConnectionCopyWithImpl<ModelConnection>(this as ModelConnection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelConnection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelConnection&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.connectionMode, _this.connectionMode) || other.connectionMode == _this.connectionMode));
}


@override
int get hashCode {
  final _this = this as ModelConnection;
  return Object.hash(runtimeType,_this.modelId,_this.connectionMode);
}

@override
String toString() {
  final _this = this as ModelConnection;
  return 'ModelConnection(modelId: ${_this.modelId}, connectionMode: ${_this.connectionMode})';
}


}

/// @nodoc
abstract mixin class $ModelConnectionCopyWith<$Res>  {
  factory $ModelConnectionCopyWith(ModelConnection value, $Res Function(ModelConnection) _then) = _$ModelConnectionCopyWithImpl;
@useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class _$ModelConnectionCopyWithImpl<$Res>
    implements $ModelConnectionCopyWith<$Res> {
  _$ModelConnectionCopyWithImpl(this._self, this._then);

  final ModelConnection _self;
  final $Res Function(ModelConnection) _then;

/// Create a copy of ModelConnection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(ModelConnection(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelConnection].
extension ModelConnectionPatterns on ModelConnection {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelConnection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelConnection() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelConnection value)  $default,){
final _that = this;
switch (_that) {
case _ModelConnection():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelConnection value)?  $default,){
final _that = this;
switch (_that) {
case _ModelConnection() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelConnection() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)  $default,) {final _that = this;
switch (_that) {
case _ModelConnection():
return $default(_that.modelId,_that.connectionMode);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  String connectionMode)?  $default,) {final _that = this;
switch (_that) {
case _ModelConnection() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _ModelConnection implements ModelConnection {
  const _ModelConnection({required this.modelId, required this.connectionMode});


@override final  String modelId;
@override final  String connectionMode;

/// Create a copy of ModelConnection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelConnectionCopyWith<_ModelConnection> get copyWith => __$ModelConnectionCopyWithImpl<_ModelConnection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelConnection&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.connectionMode, connectionMode) || other.connectionMode == connectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,connectionMode);
}

@override
String toString() {
    return 'ModelConnection(modelId: $modelId, connectionMode: $connectionMode)';
}


}

/// @nodoc
abstract mixin class _$ModelConnectionCopyWith<$Res> implements $ModelConnectionCopyWith<$Res> {
  factory _$ModelConnectionCopyWith(_ModelConnection value, $Res Function(_ModelConnection) _then) = __$ModelConnectionCopyWithImpl;
@override @useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class __$ModelConnectionCopyWithImpl<$Res>
    implements _$ModelConnectionCopyWith<$Res> {
  __$ModelConnectionCopyWithImpl(this._self, this._then);

  final _ModelConnection _self;
  final $Res Function(_ModelConnection) _then;

/// Create a copy of ModelConnection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(_ModelConnection(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModelAutoCompact {

 String get modelId; int? get overrideLimit;
/// Create a copy of ModelAutoCompact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelAutoCompactCopyWith<ModelAutoCompact> get copyWith => _$ModelAutoCompactCopyWithImpl<ModelAutoCompact>(this as ModelAutoCompact, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelAutoCompact;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelAutoCompact&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.overrideLimit, _this.overrideLimit) || other.overrideLimit == _this.overrideLimit));
}


@override
int get hashCode {
  final _this = this as ModelAutoCompact;
  return Object.hash(runtimeType,_this.modelId,_this.overrideLimit);
}

@override
String toString() {
  final _this = this as ModelAutoCompact;
  return 'ModelAutoCompact(modelId: ${_this.modelId}, overrideLimit: ${_this.overrideLimit})';
}


}

/// @nodoc
abstract mixin class $ModelAutoCompactCopyWith<$Res>  {
  factory $ModelAutoCompactCopyWith(ModelAutoCompact value, $Res Function(ModelAutoCompact) _then) = _$ModelAutoCompactCopyWithImpl;
@useResult
$Res call({
 String modelId, int? overrideLimit
});




}
/// @nodoc
class _$ModelAutoCompactCopyWithImpl<$Res>
    implements $ModelAutoCompactCopyWith<$Res> {
  _$ModelAutoCompactCopyWithImpl(this._self, this._then);

  final ModelAutoCompact _self;
  final $Res Function(ModelAutoCompact) _then;

/// Create a copy of ModelAutoCompact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(ModelAutoCompact(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelAutoCompact].
extension ModelAutoCompactPatterns on ModelAutoCompact {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelAutoCompact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelAutoCompact() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelAutoCompact value)  $default,){
final _that = this;
switch (_that) {
case _ModelAutoCompact():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelAutoCompact value)?  $default,){
final _that = this;
switch (_that) {
case _ModelAutoCompact() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  int? overrideLimit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelAutoCompact() when $default != null:
return $default(_that.modelId,_that.overrideLimit);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  int? overrideLimit)  $default,) {final _that = this;
switch (_that) {
case _ModelAutoCompact():
return $default(_that.modelId,_that.overrideLimit);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  int? overrideLimit)?  $default,) {final _that = this;
switch (_that) {
case _ModelAutoCompact() when $default != null:
return $default(_that.modelId,_that.overrideLimit);case _:
  return null;

}
}

}

/// @nodoc


class _ModelAutoCompact implements ModelAutoCompact {
  const _ModelAutoCompact({required this.modelId, required this.overrideLimit});


@override final  String modelId;
@override final  int? overrideLimit;

/// Create a copy of ModelAutoCompact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelAutoCompactCopyWith<_ModelAutoCompact> get copyWith => __$ModelAutoCompactCopyWithImpl<_ModelAutoCompact>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelAutoCompact&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.overrideLimit, overrideLimit) || other.overrideLimit == overrideLimit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,overrideLimit);
}

@override
String toString() {
    return 'ModelAutoCompact(modelId: $modelId, overrideLimit: $overrideLimit)';
}


}

/// @nodoc
abstract mixin class _$ModelAutoCompactCopyWith<$Res> implements $ModelAutoCompactCopyWith<$Res> {
  factory _$ModelAutoCompactCopyWith(_ModelAutoCompact value, $Res Function(_ModelAutoCompact) _then) = __$ModelAutoCompactCopyWithImpl;
@override @useResult
$Res call({
 String modelId, int? overrideLimit
});




}
/// @nodoc
class __$ModelAutoCompactCopyWithImpl<$Res>
    implements _$ModelAutoCompactCopyWith<$Res> {
  __$ModelAutoCompactCopyWithImpl(this._self, this._then);

  final _ModelAutoCompact _self;
  final $Res Function(_ModelAutoCompact) _then;

/// Create a copy of ModelAutoCompact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(_ModelAutoCompact(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$ModeModelRoute {

 String get modeId; String get accountId; String get modelId; String get effort;
/// Create a copy of ModeModelRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeModelRouteCopyWith<ModeModelRoute> get copyWith => _$ModeModelRouteCopyWithImpl<ModeModelRoute>(this as ModeModelRoute, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeModelRoute;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeModelRoute&&(identical(other.modeId, _this.modeId) || other.modeId == _this.modeId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as ModeModelRoute;
  return Object.hash(runtimeType,_this.modeId,_this.accountId,_this.modelId,_this.effort);
}

@override
String toString() {
  final _this = this as ModeModelRoute;
  return 'ModeModelRoute(modeId: ${_this.modeId}, accountId: ${_this.accountId}, modelId: ${_this.modelId}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $ModeModelRouteCopyWith<$Res>  {
  factory $ModeModelRouteCopyWith(ModeModelRoute value, $Res Function(ModeModelRoute) _then) = _$ModeModelRouteCopyWithImpl;
@useResult
$Res call({
 String modeId, String accountId, String modelId, String effort
});




}
/// @nodoc
class _$ModeModelRouteCopyWithImpl<$Res>
    implements $ModeModelRouteCopyWith<$Res> {
  _$ModeModelRouteCopyWithImpl(this._self, this._then);

  final ModeModelRoute _self;
  final $Res Function(ModeModelRoute) _then;

/// Create a copy of ModeModelRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modeId = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(ModeModelRoute(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ModeModelRoute].
extension ModeModelRoutePatterns on ModeModelRoute {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeModelRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeModelRoute() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeModelRoute value)  $default,){
final _that = this;
switch (_that) {
case _ModeModelRoute():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeModelRoute value)?  $default,){
final _that = this;
switch (_that) {
case _ModeModelRoute() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modeId,  String accountId,  String modelId,  String effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeModelRoute() when $default != null:
return $default(_that.modeId,_that.accountId,_that.modelId,_that.effort);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modeId,  String accountId,  String modelId,  String effort)  $default,) {final _that = this;
switch (_that) {
case _ModeModelRoute():
return $default(_that.modeId,_that.accountId,_that.modelId,_that.effort);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modeId,  String accountId,  String modelId,  String effort)?  $default,) {final _that = this;
switch (_that) {
case _ModeModelRoute() when $default != null:
return $default(_that.modeId,_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _ModeModelRoute implements ModeModelRoute {
  const _ModeModelRoute({required this.modeId, required this.accountId, required this.modelId, required this.effort});


@override final  String modeId;
@override final  String accountId;
@override final  String modelId;
@override final  String effort;

/// Create a copy of ModeModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeModelRouteCopyWith<_ModeModelRoute> get copyWith => __$ModeModelRouteCopyWithImpl<_ModeModelRoute>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeModelRoute&&(identical(other.modeId, modeId) || other.modeId == modeId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modeId,accountId,modelId,effort);
}

@override
String toString() {
    return 'ModeModelRoute(modeId: $modeId, accountId: $accountId, modelId: $modelId, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$ModeModelRouteCopyWith<$Res> implements $ModeModelRouteCopyWith<$Res> {
  factory _$ModeModelRouteCopyWith(_ModeModelRoute value, $Res Function(_ModeModelRoute) _then) = __$ModeModelRouteCopyWithImpl;
@override @useResult
$Res call({
 String modeId, String accountId, String modelId, String effort
});




}
/// @nodoc
class __$ModeModelRouteCopyWithImpl<$Res>
    implements _$ModeModelRouteCopyWith<$Res> {
  __$ModeModelRouteCopyWithImpl(this._self, this._then);

  final _ModeModelRoute _self;
  final $Res Function(_ModeModelRoute) _then;

/// Create a copy of ModeModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modeId = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(_ModeModelRoute(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RoleModelRoute {

 String get key; String get accountId; String get modelId; String get effort;
/// Create a copy of RoleModelRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoleModelRouteCopyWith<RoleModelRoute> get copyWith => _$RoleModelRouteCopyWithImpl<RoleModelRoute>(this as RoleModelRoute, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RoleModelRoute;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoleModelRoute&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as RoleModelRoute;
  return Object.hash(runtimeType,_this.key,_this.accountId,_this.modelId,_this.effort);
}

@override
String toString() {
  final _this = this as RoleModelRoute;
  return 'RoleModelRoute(key: ${_this.key}, accountId: ${_this.accountId}, modelId: ${_this.modelId}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $RoleModelRouteCopyWith<$Res>  {
  factory $RoleModelRouteCopyWith(RoleModelRoute value, $Res Function(RoleModelRoute) _then) = _$RoleModelRouteCopyWithImpl;
@useResult
$Res call({
 String key, String accountId, String modelId, String effort
});




}
/// @nodoc
class _$RoleModelRouteCopyWithImpl<$Res>
    implements $RoleModelRouteCopyWith<$Res> {
  _$RoleModelRouteCopyWithImpl(this._self, this._then);

  final RoleModelRoute _self;
  final $Res Function(RoleModelRoute) _then;

/// Create a copy of RoleModelRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(RoleModelRoute(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoleModelRoute].
extension RoleModelRoutePatterns on RoleModelRoute {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoleModelRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoleModelRoute() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoleModelRoute value)  $default,){
final _that = this;
switch (_that) {
case _RoleModelRoute():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoleModelRoute value)?  $default,){
final _that = this;
switch (_that) {
case _RoleModelRoute() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String accountId,  String modelId,  String effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoleModelRoute() when $default != null:
return $default(_that.key,_that.accountId,_that.modelId,_that.effort);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String accountId,  String modelId,  String effort)  $default,) {final _that = this;
switch (_that) {
case _RoleModelRoute():
return $default(_that.key,_that.accountId,_that.modelId,_that.effort);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String accountId,  String modelId,  String effort)?  $default,) {final _that = this;
switch (_that) {
case _RoleModelRoute() when $default != null:
return $default(_that.key,_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _RoleModelRoute implements RoleModelRoute {
  const _RoleModelRoute({required this.key, required this.accountId, required this.modelId, required this.effort});


@override final  String key;
@override final  String accountId;
@override final  String modelId;
@override final  String effort;

/// Create a copy of RoleModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoleModelRouteCopyWith<_RoleModelRoute> get copyWith => __$RoleModelRouteCopyWithImpl<_RoleModelRoute>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoleModelRoute&&(identical(other.key, key) || other.key == key)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,accountId,modelId,effort);
}

@override
String toString() {
    return 'RoleModelRoute(key: $key, accountId: $accountId, modelId: $modelId, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$RoleModelRouteCopyWith<$Res> implements $RoleModelRouteCopyWith<$Res> {
  factory _$RoleModelRouteCopyWith(_RoleModelRoute value, $Res Function(_RoleModelRoute) _then) = __$RoleModelRouteCopyWithImpl;
@override @useResult
$Res call({
 String key, String accountId, String modelId, String effort
});




}
/// @nodoc
class __$RoleModelRouteCopyWithImpl<$Res>
    implements _$RoleModelRouteCopyWith<$Res> {
  __$RoleModelRouteCopyWithImpl(this._self, this._then);

  final _RoleModelRoute _self;
  final $Res Function(_RoleModelRoute) _then;

/// Create a copy of RoleModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(_RoleModelRoute(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$InstructionsSettings {


/// Create a copy of InstructionsSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstructionsSettingsCopyWith<InstructionsSettings> get copyWith => _$InstructionsSettingsCopyWithImpl<InstructionsSettings>(this as InstructionsSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InstructionsSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstructionsSettings&&(identical(other.baseOverride, _this.baseOverride) || other.baseOverride == _this.baseOverride)&&(identical(other.developer, _this.developer) || other.developer == _this.developer)&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.projectDocMaxBytes, _this.projectDocMaxBytes) || other.projectDocMaxBytes == _this.projectDocMaxBytes)&&const DeepCollectionEquality().equals(other.projectDocFallbackFilenames, _this.projectDocFallbackFilenames));
}


@override
int get hashCode {
  final _this = this as InstructionsSettings;
  return Object.hash(runtimeType,_this.baseOverride,_this.developer,_this.user,_this.projectDocMaxBytes,const DeepCollectionEquality().hash(_this.projectDocFallbackFilenames));
}

@override
String toString() {
  final _this = this as InstructionsSettings;
  return 'InstructionsSettings(baseOverride: ${_this.baseOverride}, developer: ${_this.developer}, user: ${_this.user}, projectDocMaxBytes: ${_this.projectDocMaxBytes}, projectDocFallbackFilenames: ${_this.projectDocFallbackFilenames})';
}


}

/// @nodoc
abstract mixin class $InstructionsSettingsCopyWith<$Res>  {
  factory $InstructionsSettingsCopyWith(InstructionsSettings value, $Res Function(InstructionsSettings) _then) = _$InstructionsSettingsCopyWithImpl;
@useResult
$Res call({
 String baseOverride, String developer, String user, int projectDocMaxBytes, List<String> projectDocFallbackFilenames
});




}
/// @nodoc
class _$InstructionsSettingsCopyWithImpl<$Res>
    implements $InstructionsSettingsCopyWith<$Res> {
  _$InstructionsSettingsCopyWithImpl(this._self, this._then);

  final InstructionsSettings _self;
  final $Res Function(InstructionsSettings) _then;

/// Create a copy of InstructionsSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseOverride = null,Object? developer = null,Object? user = null,Object? projectDocMaxBytes = null,Object? projectDocFallbackFilenames = null,}) {
  return _then(InstructionsSettings(
baseOverride: null == baseOverride ? _self.baseOverride : baseOverride // ignore: cast_nullable_to_non_nullable
as String,developer: null == developer ? _self.developer : developer // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String,projectDocMaxBytes: null == projectDocMaxBytes ? _self.projectDocMaxBytes : projectDocMaxBytes // ignore: cast_nullable_to_non_nullable
as int,projectDocFallbackFilenames: null == projectDocFallbackFilenames ? _self.projectDocFallbackFilenames : projectDocFallbackFilenames // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [InstructionsSettings].
extension InstructionsSettingsPatterns on InstructionsSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$SkillsSettings {


/// Create a copy of SkillsSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsSettingsCopyWith<SkillsSettings> get copyWith => _$SkillsSettingsCopyWithImpl<SkillsSettings>(this as SkillsSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsSettings&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.autoLearn, _this.autoLearn) || other.autoLearn == _this.autoLearn)&&(identical(other.systemEnabled, _this.systemEnabled) || other.systemEnabled == _this.systemEnabled)&&(identical(other.projectDir, _this.projectDir) || other.projectDir == _this.projectDir)&&(identical(other.userDir, _this.userDir) || other.userDir == _this.userDir)&&const DeepCollectionEquality().equals(other.externalDirs, _this.externalDirs)&&const DeepCollectionEquality().equals(other.disabled, _this.disabled)&&(identical(other.autoLearnMinToolCalls, _this.autoLearnMinToolCalls) || other.autoLearnMinToolCalls == _this.autoLearnMinToolCalls));
}


@override
int get hashCode {
  final _this = this as SkillsSettings;
  return Object.hash(runtimeType,_this.enabled,_this.autoLearn,_this.systemEnabled,_this.projectDir,_this.userDir,const DeepCollectionEquality().hash(_this.externalDirs),const DeepCollectionEquality().hash(_this.disabled),_this.autoLearnMinToolCalls);
}

@override
String toString() {
  final _this = this as SkillsSettings;
  return 'SkillsSettings(enabled: ${_this.enabled}, autoLearn: ${_this.autoLearn}, systemEnabled: ${_this.systemEnabled}, projectDir: ${_this.projectDir}, userDir: ${_this.userDir}, externalDirs: ${_this.externalDirs}, disabled: ${_this.disabled}, autoLearnMinToolCalls: ${_this.autoLearnMinToolCalls})';
}


}

/// @nodoc
abstract mixin class $SkillsSettingsCopyWith<$Res>  {
  factory $SkillsSettingsCopyWith(SkillsSettings value, $Res Function(SkillsSettings) _then) = _$SkillsSettingsCopyWithImpl;
@useResult
$Res call({
 bool enabled, bool autoLearn, bool systemEnabled, String projectDir, String userDir, List<String> externalDirs, List<String> disabled, int autoLearnMinToolCalls
});




}
/// @nodoc
class _$SkillsSettingsCopyWithImpl<$Res>
    implements $SkillsSettingsCopyWith<$Res> {
  _$SkillsSettingsCopyWithImpl(this._self, this._then);

  final SkillsSettings _self;
  final $Res Function(SkillsSettings) _then;

/// Create a copy of SkillsSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? autoLearn = null,Object? systemEnabled = null,Object? projectDir = null,Object? userDir = null,Object? externalDirs = null,Object? disabled = null,Object? autoLearnMinToolCalls = null,}) {
  return _then(SkillsSettings(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,autoLearn: null == autoLearn ? _self.autoLearn : autoLearn // ignore: cast_nullable_to_non_nullable
as bool,systemEnabled: null == systemEnabled ? _self.systemEnabled : systemEnabled // ignore: cast_nullable_to_non_nullable
as bool,projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as String,userDir: null == userDir ? _self.userDir : userDir // ignore: cast_nullable_to_non_nullable
as String,externalDirs: null == externalDirs ? _self.externalDirs : externalDirs // ignore: cast_nullable_to_non_nullable
as List<String>,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as List<String>,autoLearnMinToolCalls: null == autoLearnMinToolCalls ? _self.autoLearnMinToolCalls : autoLearnMinToolCalls // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillsSettings].
extension SkillsSettingsPatterns on SkillsSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$McpConfiguration {

 String get id; String get transport; String get endpoint; McpConfigurationState get configuration; String get sourceKind; String get mutationPolicy;
/// Create a copy of McpConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpConfigurationCopyWith<McpConfiguration> get copyWith => _$McpConfigurationCopyWithImpl<McpConfiguration>(this as McpConfiguration, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpConfiguration&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.sourceKind, _this.sourceKind) || other.sourceKind == _this.sourceKind)&&(identical(other.mutationPolicy, _this.mutationPolicy) || other.mutationPolicy == _this.mutationPolicy));
}


@override
int get hashCode {
  final _this = this as McpConfiguration;
  return Object.hash(runtimeType,_this.id,_this.transport,_this.endpoint,_this.configuration,_this.sourceKind,_this.mutationPolicy);
}

@override
String toString() {
  final _this = this as McpConfiguration;
  return 'McpConfiguration(id: ${_this.id}, transport: ${_this.transport}, endpoint: ${_this.endpoint}, configuration: ${_this.configuration}, sourceKind: ${_this.sourceKind}, mutationPolicy: ${_this.mutationPolicy})';
}


}

/// @nodoc
abstract mixin class $McpConfigurationCopyWith<$Res>  {
  factory $McpConfigurationCopyWith(McpConfiguration value, $Res Function(McpConfiguration) _then) = _$McpConfigurationCopyWithImpl;
@useResult
$Res call({
 String id, String transport, String endpoint, McpConfigurationState configuration, String sourceKind, String mutationPolicy
});




}
/// @nodoc
class _$McpConfigurationCopyWithImpl<$Res>
    implements $McpConfigurationCopyWith<$Res> {
  _$McpConfigurationCopyWithImpl(this._self, this._then);

  final McpConfiguration _self;
  final $Res Function(McpConfiguration) _then;

/// Create a copy of McpConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? configuration = null,Object? sourceKind = null,Object? mutationPolicy = null,}) {
  return _then(McpConfiguration(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as McpConfigurationState,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [McpConfiguration].
extension McpConfigurationPatterns on McpConfiguration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpConfiguration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpConfiguration() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpConfiguration value)  $default,){
final _that = this;
switch (_that) {
case _McpConfiguration():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpConfiguration value)?  $default,){
final _that = this;
switch (_that) {
case _McpConfiguration() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String transport,  String endpoint,  McpConfigurationState configuration,  String sourceKind,  String mutationPolicy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpConfiguration() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.configuration,_that.sourceKind,_that.mutationPolicy);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String transport,  String endpoint,  McpConfigurationState configuration,  String sourceKind,  String mutationPolicy)  $default,) {final _that = this;
switch (_that) {
case _McpConfiguration():
return $default(_that.id,_that.transport,_that.endpoint,_that.configuration,_that.sourceKind,_that.mutationPolicy);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String transport,  String endpoint,  McpConfigurationState configuration,  String sourceKind,  String mutationPolicy)?  $default,) {final _that = this;
switch (_that) {
case _McpConfiguration() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.configuration,_that.sourceKind,_that.mutationPolicy);case _:
  return null;

}
}

}

/// @nodoc


class _McpConfiguration implements McpConfiguration {
  const _McpConfiguration({required this.id, required this.transport, required this.endpoint, required this.configuration, required this.sourceKind, required this.mutationPolicy});


@override final  String id;
@override final  String transport;
@override final  String endpoint;
@override final  McpConfigurationState configuration;
@override final  String sourceKind;
@override final  String mutationPolicy;

/// Create a copy of McpConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpConfigurationCopyWith<_McpConfiguration> get copyWith => __$McpConfigurationCopyWithImpl<_McpConfiguration>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpConfiguration&&(identical(other.id, id) || other.id == id)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.sourceKind, sourceKind) || other.sourceKind == sourceKind)&&(identical(other.mutationPolicy, mutationPolicy) || other.mutationPolicy == mutationPolicy));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,transport,endpoint,configuration,sourceKind,mutationPolicy);
}

@override
String toString() {
    return 'McpConfiguration(id: $id, transport: $transport, endpoint: $endpoint, configuration: $configuration, sourceKind: $sourceKind, mutationPolicy: $mutationPolicy)';
}


}

/// @nodoc
abstract mixin class _$McpConfigurationCopyWith<$Res> implements $McpConfigurationCopyWith<$Res> {
  factory _$McpConfigurationCopyWith(_McpConfiguration value, $Res Function(_McpConfiguration) _then) = __$McpConfigurationCopyWithImpl;
@override @useResult
$Res call({
 String id, String transport, String endpoint, McpConfigurationState configuration, String sourceKind, String mutationPolicy
});




}
/// @nodoc
class __$McpConfigurationCopyWithImpl<$Res>
    implements _$McpConfigurationCopyWith<$Res> {
  __$McpConfigurationCopyWithImpl(this._self, this._then);

  final _McpConfiguration _self;
  final $Res Function(_McpConfiguration) _then;

/// Create a copy of McpConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? configuration = null,Object? sourceKind = null,Object? mutationPolicy = null,}) {
  return _then(_McpConfiguration(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as McpConfigurationState,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$GeneralSettings {


/// Create a copy of GeneralSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GeneralSettingsCopyWith<GeneralSettings> get copyWith => _$GeneralSettingsCopyWithImpl<GeneralSettings>(this as GeneralSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GeneralSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GeneralSettings&&(identical(other.followActiveTurn, _this.followActiveTurn) || other.followActiveTurn == _this.followActiveTurn)&&(identical(other.compactTimeline, _this.compactTimeline) || other.compactTimeline == _this.compactTimeline)&&(identical(other.sidebarWidth, _this.sidebarWidth) || other.sidebarWidth == _this.sidebarWidth)&&const DeepCollectionEquality().equals(other.pinnedThreadIds, _this.pinnedThreadIds)&&const DeepCollectionEquality().equals(other.pinnedProjectIds, _this.pinnedProjectIds));
}


@override
int get hashCode {
  final _this = this as GeneralSettings;
  return Object.hash(runtimeType,_this.followActiveTurn,_this.compactTimeline,_this.sidebarWidth,const DeepCollectionEquality().hash(_this.pinnedThreadIds),const DeepCollectionEquality().hash(_this.pinnedProjectIds));
}

@override
String toString() {
  final _this = this as GeneralSettings;
  return 'GeneralSettings(followActiveTurn: ${_this.followActiveTurn}, compactTimeline: ${_this.compactTimeline}, sidebarWidth: ${_this.sidebarWidth}, pinnedThreadIds: ${_this.pinnedThreadIds}, pinnedProjectIds: ${_this.pinnedProjectIds})';
}


}

/// @nodoc
abstract mixin class $GeneralSettingsCopyWith<$Res>  {
  factory $GeneralSettingsCopyWith(GeneralSettings value, $Res Function(GeneralSettings) _then) = _$GeneralSettingsCopyWithImpl;
@useResult
$Res call({
 bool followActiveTurn, bool compactTimeline, int? sidebarWidth, List<String> pinnedThreadIds, List<String> pinnedProjectIds
});




}
/// @nodoc
class _$GeneralSettingsCopyWithImpl<$Res>
    implements $GeneralSettingsCopyWith<$Res> {
  _$GeneralSettingsCopyWithImpl(this._self, this._then);

  final GeneralSettings _self;
  final $Res Function(GeneralSettings) _then;

/// Create a copy of GeneralSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? followActiveTurn = null,Object? compactTimeline = null,Object? sidebarWidth = freezed,Object? pinnedThreadIds = null,Object? pinnedProjectIds = null,}) {
  return _then(GeneralSettings(
followActiveTurn: null == followActiveTurn ? _self.followActiveTurn : followActiveTurn // ignore: cast_nullable_to_non_nullable
as bool,compactTimeline: null == compactTimeline ? _self.compactTimeline : compactTimeline // ignore: cast_nullable_to_non_nullable
as bool,sidebarWidth: freezed == sidebarWidth ? _self.sidebarWidth : sidebarWidth // ignore: cast_nullable_to_non_nullable
as int?,pinnedThreadIds: null == pinnedThreadIds ? _self.pinnedThreadIds : pinnedThreadIds // ignore: cast_nullable_to_non_nullable
as List<String>,pinnedProjectIds: null == pinnedProjectIds ? _self.pinnedProjectIds : pinnedProjectIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [GeneralSettings].
extension GeneralSettingsPatterns on GeneralSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$WebSearchConfiguration {


/// Create a copy of WebSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSearchConfigurationCopyWith<WebSearchConfiguration> get copyWith => _$WebSearchConfigurationCopyWithImpl<WebSearchConfiguration>(this as WebSearchConfiguration, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WebSearchConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSearchConfiguration&&(identical(other.configuredMode, _this.configuredMode) || other.configuredMode == _this.configuredMode)&&(identical(other.contextSize, _this.contextSize) || other.contextSize == _this.contextSize)&&const DeepCollectionEquality().equals(other.allowedDomains, _this.allowedDomains)&&(identical(other.country, _this.country) || other.country == _this.country)&&(identical(other.region, _this.region) || other.region == _this.region)&&(identical(other.city, _this.city) || other.city == _this.city)&&(identical(other.timezone, _this.timezone) || other.timezone == _this.timezone));
}


@override
int get hashCode {
  final _this = this as WebSearchConfiguration;
  return Object.hash(runtimeType,_this.configuredMode,_this.contextSize,const DeepCollectionEquality().hash(_this.allowedDomains),_this.country,_this.region,_this.city,_this.timezone);
}

@override
String toString() {
  final _this = this as WebSearchConfiguration;
  return 'WebSearchConfiguration(configuredMode: ${_this.configuredMode}, contextSize: ${_this.contextSize}, allowedDomains: ${_this.allowedDomains}, country: ${_this.country}, region: ${_this.region}, city: ${_this.city}, timezone: ${_this.timezone})';
}


}

/// @nodoc
abstract mixin class $WebSearchConfigurationCopyWith<$Res>  {
  factory $WebSearchConfigurationCopyWith(WebSearchConfiguration value, $Res Function(WebSearchConfiguration) _then) = _$WebSearchConfigurationCopyWithImpl;
@useResult
$Res call({
 String configuredMode, String? contextSize, List<String> allowedDomains, String? country, String? region, String? city, String? timezone
});




}
/// @nodoc
class _$WebSearchConfigurationCopyWithImpl<$Res>
    implements $WebSearchConfigurationCopyWith<$Res> {
  _$WebSearchConfigurationCopyWithImpl(this._self, this._then);

  final WebSearchConfiguration _self;
  final $Res Function(WebSearchConfiguration) _then;

/// Create a copy of WebSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuredMode = null,Object? contextSize = freezed,Object? allowedDomains = null,Object? country = freezed,Object? region = freezed,Object? city = freezed,Object? timezone = freezed,}) {
  return _then(WebSearchConfiguration(
configuredMode: null == configuredMode ? _self.configuredMode : configuredMode // ignore: cast_nullable_to_non_nullable
as String,contextSize: freezed == contextSize ? _self.contextSize : contextSize // ignore: cast_nullable_to_non_nullable
as String?,allowedDomains: null == allowedDomains ? _self.allowedDomains : allowedDomains // ignore: cast_nullable_to_non_nullable
as List<String>,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String?,city: freezed == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String?,timezone: freezed == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WebSearchConfiguration].
extension WebSearchConfigurationPatterns on WebSearchConfiguration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$DeepSeekSearchConfiguration {

 bool get configuredEnabled; bool get configuredFetchEnabled;
/// Create a copy of DeepSeekSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationCopyWith<DeepSeekSearchConfiguration> get copyWith => _$DeepSeekSearchConfigurationCopyWithImpl<DeepSeekSearchConfiguration>(this as DeepSeekSearchConfiguration, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeepSeekSearchConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeepSeekSearchConfiguration&&(identical(other.configuredEnabled, _this.configuredEnabled) || other.configuredEnabled == _this.configuredEnabled)&&(identical(other.configuredFetchEnabled, _this.configuredFetchEnabled) || other.configuredFetchEnabled == _this.configuredFetchEnabled));
}


@override
int get hashCode {
  final _this = this as DeepSeekSearchConfiguration;
  return Object.hash(runtimeType,_this.configuredEnabled,_this.configuredFetchEnabled);
}

@override
String toString() {
  final _this = this as DeepSeekSearchConfiguration;
  return 'DeepSeekSearchConfiguration(configuredEnabled: ${_this.configuredEnabled}, configuredFetchEnabled: ${_this.configuredFetchEnabled})';
}


}

/// @nodoc
abstract mixin class $DeepSeekSearchConfigurationCopyWith<$Res>  {
  factory $DeepSeekSearchConfigurationCopyWith(DeepSeekSearchConfiguration value, $Res Function(DeepSeekSearchConfiguration) _then) = _$DeepSeekSearchConfigurationCopyWithImpl;
@useResult
$Res call({
 bool configuredEnabled, bool configuredFetchEnabled
});




}
/// @nodoc
class _$DeepSeekSearchConfigurationCopyWithImpl<$Res>
    implements $DeepSeekSearchConfigurationCopyWith<$Res> {
  _$DeepSeekSearchConfigurationCopyWithImpl(this._self, this._then);

  final DeepSeekSearchConfiguration _self;
  final $Res Function(DeepSeekSearchConfiguration) _then;

/// Create a copy of DeepSeekSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuredEnabled = null,Object? configuredFetchEnabled = null,}) {
  return _then(DeepSeekSearchConfiguration(
configuredEnabled: null == configuredEnabled ? _self.configuredEnabled : configuredEnabled // ignore: cast_nullable_to_non_nullable
as bool,configuredFetchEnabled: null == configuredFetchEnabled ? _self.configuredFetchEnabled : configuredFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeepSeekSearchConfiguration].
extension DeepSeekSearchConfigurationPatterns on DeepSeekSearchConfiguration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeepSeekSearchConfiguration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeepSeekSearchConfiguration value)  $default,){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeepSeekSearchConfiguration value)?  $default,){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool configuredEnabled,  bool configuredFetchEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration() when $default != null:
return $default(_that.configuredEnabled,_that.configuredFetchEnabled);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool configuredEnabled,  bool configuredFetchEnabled)  $default,) {final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration():
return $default(_that.configuredEnabled,_that.configuredFetchEnabled);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool configuredEnabled,  bool configuredFetchEnabled)?  $default,) {final _that = this;
switch (_that) {
case _DeepSeekSearchConfiguration() when $default != null:
return $default(_that.configuredEnabled,_that.configuredFetchEnabled);case _:
  return null;

}
}

}

/// @nodoc


class _DeepSeekSearchConfiguration implements DeepSeekSearchConfiguration {
  const _DeepSeekSearchConfiguration({required this.configuredEnabled, required this.configuredFetchEnabled});


@override final  bool configuredEnabled;
@override final  bool configuredFetchEnabled;

/// Create a copy of DeepSeekSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeepSeekSearchConfigurationCopyWith<_DeepSeekSearchConfiguration> get copyWith => __$DeepSeekSearchConfigurationCopyWithImpl<_DeepSeekSearchConfiguration>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeepSeekSearchConfiguration&&(identical(other.configuredEnabled, configuredEnabled) || other.configuredEnabled == configuredEnabled)&&(identical(other.configuredFetchEnabled, configuredFetchEnabled) || other.configuredFetchEnabled == configuredFetchEnabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configuredEnabled,configuredFetchEnabled);
}

@override
String toString() {
    return 'DeepSeekSearchConfiguration(configuredEnabled: $configuredEnabled, configuredFetchEnabled: $configuredFetchEnabled)';
}


}

/// @nodoc
abstract mixin class _$DeepSeekSearchConfigurationCopyWith<$Res> implements $DeepSeekSearchConfigurationCopyWith<$Res> {
  factory _$DeepSeekSearchConfigurationCopyWith(_DeepSeekSearchConfiguration value, $Res Function(_DeepSeekSearchConfiguration) _then) = __$DeepSeekSearchConfigurationCopyWithImpl;
@override @useResult
$Res call({
 bool configuredEnabled, bool configuredFetchEnabled
});




}
/// @nodoc
class __$DeepSeekSearchConfigurationCopyWithImpl<$Res>
    implements _$DeepSeekSearchConfigurationCopyWith<$Res> {
  __$DeepSeekSearchConfigurationCopyWithImpl(this._self, this._then);

  final _DeepSeekSearchConfiguration _self;
  final $Res Function(_DeepSeekSearchConfiguration) _then;

/// Create a copy of DeepSeekSearchConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configuredEnabled = null,Object? configuredFetchEnabled = null,}) {
  return _then(_DeepSeekSearchConfiguration(
configuredEnabled: null == configuredEnabled ? _self.configuredEnabled : configuredEnabled // ignore: cast_nullable_to_non_nullable
as bool,configuredFetchEnabled: null == configuredFetchEnabled ? _self.configuredFetchEnabled : configuredFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$DelegationSettings {

 DelegationMode get mode; DelegationPreference get preference;
/// Create a copy of DelegationSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<DelegationSettings> get copyWith => _$DelegationSettingsCopyWithImpl<DelegationSettings>(this as DelegationSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationSettings&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.preference, _this.preference) || other.preference == _this.preference));
}


@override
int get hashCode {
  final _this = this as DelegationSettings;
  return Object.hash(runtimeType,_this.mode,_this.preference);
}

@override
String toString() {
  final _this = this as DelegationSettings;
  return 'DelegationSettings(mode: ${_this.mode}, preference: ${_this.preference})';
}


}

/// @nodoc
abstract mixin class $DelegationSettingsCopyWith<$Res>  {
  factory $DelegationSettingsCopyWith(DelegationSettings value, $Res Function(DelegationSettings) _then) = _$DelegationSettingsCopyWithImpl;
@useResult
$Res call({
 DelegationMode mode, DelegationPreference preference
});




}
/// @nodoc
class _$DelegationSettingsCopyWithImpl<$Res>
    implements $DelegationSettingsCopyWith<$Res> {
  _$DelegationSettingsCopyWithImpl(this._self, this._then);

  final DelegationSettings _self;
  final $Res Function(DelegationSettings) _then;

/// Create a copy of DelegationSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? preference = null,}) {
  return _then(DelegationSettings(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,
  ));
}

}


/// Adds pattern-matching-related methods to [DelegationSettings].
extension DelegationSettingsPatterns on DelegationSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DelegationSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DelegationSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DelegationSettings value)  $default,){
final _that = this;
switch (_that) {
case _DelegationSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DelegationSettings value)?  $default,){
final _that = this;
switch (_that) {
case _DelegationSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DelegationMode mode,  DelegationPreference preference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DelegationSettings() when $default != null:
return $default(_that.mode,_that.preference);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DelegationMode mode,  DelegationPreference preference)  $default,) {final _that = this;
switch (_that) {
case _DelegationSettings():
return $default(_that.mode,_that.preference);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DelegationMode mode,  DelegationPreference preference)?  $default,) {final _that = this;
switch (_that) {
case _DelegationSettings() when $default != null:
return $default(_that.mode,_that.preference);case _:
  return null;

}
}

}

/// @nodoc


class _DelegationSettings implements DelegationSettings {
  const _DelegationSettings({required this.mode, required this.preference});


@override final  DelegationMode mode;
@override final  DelegationPreference preference;

/// Create a copy of DelegationSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DelegationSettingsCopyWith<_DelegationSettings> get copyWith => __$DelegationSettingsCopyWithImpl<_DelegationSettings>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DelegationSettings&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.preference, preference) || other.preference == preference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode,preference);
}

@override
String toString() {
    return 'DelegationSettings(mode: $mode, preference: $preference)';
}


}

/// @nodoc
abstract mixin class _$DelegationSettingsCopyWith<$Res> implements $DelegationSettingsCopyWith<$Res> {
  factory _$DelegationSettingsCopyWith(_DelegationSettings value, $Res Function(_DelegationSettings) _then) = __$DelegationSettingsCopyWithImpl;
@override @useResult
$Res call({
 DelegationMode mode, DelegationPreference preference
});




}
/// @nodoc
class __$DelegationSettingsCopyWithImpl<$Res>
    implements _$DelegationSettingsCopyWith<$Res> {
  __$DelegationSettingsCopyWithImpl(this._self, this._then);

  final _DelegationSettings _self;
  final $Res Function(_DelegationSettings) _then;

/// Create a copy of DelegationSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? preference = null,}) {
  return _then(_DelegationSettings(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,
  ));
}


}

// dart format on
