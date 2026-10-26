// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_settings_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadSettingsSnapshot {


/// Create a copy of ThreadSettingsSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsSnapshotCopyWith<ThreadSettingsSnapshot> get copyWith => _$ThreadSettingsSnapshotCopyWithImpl<ThreadSettingsSnapshot>(this as ThreadSettingsSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsSnapshot&&(identical(other.config, _this.config) || other.config == _this.config)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsSnapshot;
  return Object.hash(runtimeType,_this.config,_this.catalog);
}



}

/// @nodoc
abstract mixin class $ThreadSettingsSnapshotCopyWith<$Res>  {
  factory $ThreadSettingsSnapshotCopyWith(ThreadSettingsSnapshot value, $Res Function(ThreadSettingsSnapshot) _then) = _$ThreadSettingsSnapshotCopyWithImpl;
@useResult
$Res call({
 ThreadSettingsConfigSnapshot config, ThreadSettingsCatalogSnapshot catalog
});


$ThreadSettingsConfigSnapshotCopyWith<$Res> get config;$ThreadSettingsCatalogSnapshotCopyWith<$Res> get catalog;

}
/// @nodoc
class _$ThreadSettingsSnapshotCopyWithImpl<$Res>
    implements $ThreadSettingsSnapshotCopyWith<$Res> {
  _$ThreadSettingsSnapshotCopyWithImpl(this._self, this._then);

  final ThreadSettingsSnapshot _self;
  final $Res Function(ThreadSettingsSnapshot) _then;

/// Create a copy of ThreadSettingsSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? config = null,Object? catalog = null,}) {
  return _then(ThreadSettingsSnapshot(
config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as ThreadSettingsConfigSnapshot,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ThreadSettingsCatalogSnapshot,
  ));
}
/// Create a copy of ThreadSettingsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadSettingsConfigSnapshotCopyWith<$Res> get config {

  return $ThreadSettingsConfigSnapshotCopyWith<$Res>(_self.config, (value) {
    return _then(_self.copyWith(config: value));
  });
}/// Create a copy of ThreadSettingsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadSettingsCatalogSnapshotCopyWith<$Res> get catalog {

  return $ThreadSettingsCatalogSnapshotCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadSettingsSnapshot].
extension ThreadSettingsSnapshotPatterns on ThreadSettingsSnapshot {
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
mixin _$ThreadSettingsConfigSnapshot {


/// Create a copy of ThreadSettingsConfigSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsConfigSnapshotCopyWith<ThreadSettingsConfigSnapshot> get copyWith => _$ThreadSettingsConfigSnapshotCopyWithImpl<ThreadSettingsConfigSnapshot>(this as ThreadSettingsConfigSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsConfigSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsConfigSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.settings, _this.settings) || other.settings == _this.settings));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsConfigSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.settings);
}



}

/// @nodoc
abstract mixin class $ThreadSettingsConfigSnapshotCopyWith<$Res>  {
  factory $ThreadSettingsConfigSnapshotCopyWith(ThreadSettingsConfigSnapshot value, $Res Function(ThreadSettingsConfigSnapshot) _then) = _$ThreadSettingsConfigSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, ThreadSettingsValue settings
});


$ThreadSettingsValueCopyWith<$Res> get settings;

}
/// @nodoc
class _$ThreadSettingsConfigSnapshotCopyWithImpl<$Res>
    implements $ThreadSettingsConfigSnapshotCopyWith<$Res> {
  _$ThreadSettingsConfigSnapshotCopyWithImpl(this._self, this._then);

  final ThreadSettingsConfigSnapshot _self;
  final $Res Function(ThreadSettingsConfigSnapshot) _then;

/// Create a copy of ThreadSettingsConfigSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? settings = null,}) {
  return _then(ThreadSettingsConfigSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as ThreadSettingsValue,
  ));
}
/// Create a copy of ThreadSettingsConfigSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadSettingsValueCopyWith<$Res> get settings {

  return $ThreadSettingsValueCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadSettingsConfigSnapshot].
extension ThreadSettingsConfigSnapshotPatterns on ThreadSettingsConfigSnapshot {
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
mixin _$ThreadSettingsValue {


/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsValueCopyWith<ThreadSettingsValue> get copyWith => _$ThreadSettingsValueCopyWithImpl<ThreadSettingsValue>(this as ThreadSettingsValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsValue&&(identical(other.defaultAccountId, _this.defaultAccountId) || other.defaultAccountId == _this.defaultAccountId)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&const DeepCollectionEquality().equals(other.modeModelRoutes, _this.modeModelRoutes)&&const DeepCollectionEquality().equals(other.roles, _this.roles)&&(identical(other.permissionMode, _this.permissionMode) || other.permissionMode == _this.permissionMode)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&(identical(other.skills, _this.skills) || other.skills == _this.skills)&&const DeepCollectionEquality().equals(other.mcpServers, _this.mcpServers)&&(identical(other.general, _this.general) || other.general == _this.general)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepseekWebSearch, _this.deepseekWebSearch) || other.deepseekWebSearch == _this.deepseekWebSearch));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsValue;
  return Object.hash(runtimeType,_this.defaultAccountId,const DeepCollectionEquality().hash(_this.accounts),const DeepCollectionEquality().hash(_this.modeModelRoutes),const DeepCollectionEquality().hash(_this.roles),_this.permissionMode,_this.instructions,_this.skills,const DeepCollectionEquality().hash(_this.mcpServers),_this.general,_this.delegation,_this.webSearch,_this.deepseekWebSearch);
}



}

/// @nodoc
abstract mixin class $ThreadSettingsValueCopyWith<$Res>  {
  factory $ThreadSettingsValueCopyWith(ThreadSettingsValue value, $Res Function(ThreadSettingsValue) _then) = _$ThreadSettingsValueCopyWithImpl;
@useResult
$Res call({
 String? defaultAccountId, List<ThreadSettingsAccount> accounts, List<ModeModelRoute> modeModelRoutes, List<RoleModelRoute> roles, String permissionMode, InstructionsSettings instructions, SkillsSettings skills, List<McpConfiguration> mcpServers, GeneralSettings general, DelegationSettings delegation, ThreadWebSearchSettings webSearch, ThreadDeepSeekSearchSettings deepseekWebSearch
});


$InstructionsSettingsCopyWith<$Res> get instructions;$SkillsSettingsCopyWith<$Res> get skills;$GeneralSettingsCopyWith<$Res> get general;$DelegationSettingsCopyWith<$Res> get delegation;$ThreadWebSearchSettingsCopyWith<$Res> get webSearch;$ThreadDeepSeekSearchSettingsCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class _$ThreadSettingsValueCopyWithImpl<$Res>
    implements $ThreadSettingsValueCopyWith<$Res> {
  _$ThreadSettingsValueCopyWithImpl(this._self, this._then);

  final ThreadSettingsValue _self;
  final $Res Function(ThreadSettingsValue) _then;

/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? defaultAccountId = freezed,Object? accounts = null,Object? modeModelRoutes = null,Object? roles = null,Object? permissionMode = null,Object? instructions = null,Object? skills = null,Object? mcpServers = null,Object? general = null,Object? delegation = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(ThreadSettingsValue(
defaultAccountId: freezed == defaultAccountId ? _self.defaultAccountId : defaultAccountId // ignore: cast_nullable_to_non_nullable
as String?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ThreadSettingsAccount>,modeModelRoutes: null == modeModelRoutes ? _self.modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as List<ModeModelRoute>,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<RoleModelRoute>,permissionMode: null == permissionMode ? _self.permissionMode : permissionMode // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as InstructionsSettings,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as SkillsSettings,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpConfiguration>,general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as GeneralSettings,delegation: null == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as ThreadWebSearchSettings,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as ThreadDeepSeekSearchSettings,
  ));
}
/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsCopyWith<$Res> get instructions {

  return $InstructionsSettingsCopyWith<$Res>(_self.instructions, (value) {
    return _then(_self.copyWith(instructions: value));
  });
}/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsSettingsCopyWith<$Res> get skills {

  return $SkillsSettingsCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsCopyWith<$Res> get general {

  return $GeneralSettingsCopyWith<$Res>(_self.general, (value) {
    return _then(_self.copyWith(general: value));
  });
}/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get delegation {

  return $DelegationSettingsCopyWith<$Res>(_self.delegation, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWebSearchSettingsCopyWith<$Res> get webSearch {

  return $ThreadWebSearchSettingsCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ThreadSettingsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDeepSeekSearchSettingsCopyWith<$Res> get deepseekWebSearch {

  return $ThreadDeepSeekSearchSettingsCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadSettingsValue].
extension ThreadSettingsValuePatterns on ThreadSettingsValue {
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
mixin _$ThreadSettingsAccount {


/// Create a copy of ThreadSettingsAccount
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsAccountCopyWith<ThreadSettingsAccount> get copyWith => _$ThreadSettingsAccountCopyWithImpl<ThreadSettingsAccount>(this as ThreadSettingsAccount, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsAccount;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsAccount&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.credentialRequired, _this.credentialRequired) || other.credentialRequired == _this.credentialRequired)&&(identical(other.capabilitySource, _this.capabilitySource) || other.capabilitySource == _this.capabilitySource)&&(identical(other.hostedWebSearch, _this.hostedWebSearch) || other.hostedWebSearch == _this.hostedWebSearch)&&(identical(other.hostedWebSearchDialect, _this.hostedWebSearchDialect) || other.hostedWebSearchDialect == _this.hostedWebSearchDialect)&&(identical(other.standaloneWebSearch, _this.standaloneWebSearch) || other.standaloneWebSearch == _this.standaloneWebSearch)&&(identical(other.promptCacheDialect, _this.promptCacheDialect) || other.promptCacheDialect == _this.promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, _this.responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == _this.responsesProgrammaticToolCalling)&&(identical(other.defaultModelId, _this.defaultModelId) || other.defaultModelId == _this.defaultModelId));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsAccount;
  return Object.hash(runtimeType,_this.configuration,_this.credentialRequired,_this.capabilitySource,_this.hostedWebSearch,_this.hostedWebSearchDialect,_this.standaloneWebSearch,_this.promptCacheDialect,_this.responsesProgrammaticToolCalling,_this.defaultModelId);
}



}

/// @nodoc
abstract mixin class $ThreadSettingsAccountCopyWith<$Res>  {
  factory $ThreadSettingsAccountCopyWith(ThreadSettingsAccount value, $Res Function(ThreadSettingsAccount) _then) = _$ThreadSettingsAccountCopyWithImpl;
@useResult
$Res call({
 AccountConfiguration configuration, bool credentialRequired, String capabilitySource, bool hostedWebSearch, String hostedWebSearchDialect, String? standaloneWebSearch, String promptCacheDialect, bool responsesProgrammaticToolCalling, String defaultModelId
});


$AccountConfigurationCopyWith<$Res> get configuration;

}
/// @nodoc
class _$ThreadSettingsAccountCopyWithImpl<$Res>
    implements $ThreadSettingsAccountCopyWith<$Res> {
  _$ThreadSettingsAccountCopyWithImpl(this._self, this._then);

  final ThreadSettingsAccount _self;
  final $Res Function(ThreadSettingsAccount) _then;

/// Create a copy of ThreadSettingsAccount
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuration = null,Object? credentialRequired = null,Object? capabilitySource = null,Object? hostedWebSearch = null,Object? hostedWebSearchDialect = null,Object? standaloneWebSearch = freezed,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,Object? defaultModelId = null,}) {
  return _then(ThreadSettingsAccount(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as AccountConfiguration,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,capabilitySource: null == capabilitySource ? _self.capabilitySource : capabilitySource // ignore: cast_nullable_to_non_nullable
as String,hostedWebSearch: null == hostedWebSearch ? _self.hostedWebSearch : hostedWebSearch // ignore: cast_nullable_to_non_nullable
as bool,hostedWebSearchDialect: null == hostedWebSearchDialect ? _self.hostedWebSearchDialect : hostedWebSearchDialect // ignore: cast_nullable_to_non_nullable
as String,standaloneWebSearch: freezed == standaloneWebSearch ? _self.standaloneWebSearch : standaloneWebSearch // ignore: cast_nullable_to_non_nullable
as String?,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as String,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,defaultModelId: null == defaultModelId ? _self.defaultModelId : defaultModelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of ThreadSettingsAccount
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res> get configuration {

  return $AccountConfigurationCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadSettingsAccount].
extension ThreadSettingsAccountPatterns on ThreadSettingsAccount {
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
mixin _$ThreadWebSearchSettings {


/// Create a copy of ThreadWebSearchSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWebSearchSettingsCopyWith<ThreadWebSearchSettings> get copyWith => _$ThreadWebSearchSettingsCopyWithImpl<ThreadWebSearchSettings>(this as ThreadWebSearchSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWebSearchSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWebSearchSettings&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.effective, _this.effective) || other.effective == _this.effective));
}


@override
int get hashCode {
  final _this = this as ThreadWebSearchSettings;
  return Object.hash(runtimeType,_this.configuration,_this.effective);
}



}

/// @nodoc
abstract mixin class $ThreadWebSearchSettingsCopyWith<$Res>  {
  factory $ThreadWebSearchSettingsCopyWith(ThreadWebSearchSettings value, $Res Function(ThreadWebSearchSettings) _then) = _$ThreadWebSearchSettingsCopyWithImpl;
@useResult
$Res call({
 WebSearchConfiguration configuration, EffectiveWebSearch effective
});


$WebSearchConfigurationCopyWith<$Res> get configuration;$EffectiveWebSearchCopyWith<$Res> get effective;

}
/// @nodoc
class _$ThreadWebSearchSettingsCopyWithImpl<$Res>
    implements $ThreadWebSearchSettingsCopyWith<$Res> {
  _$ThreadWebSearchSettingsCopyWithImpl(this._self, this._then);

  final ThreadWebSearchSettings _self;
  final $Res Function(ThreadWebSearchSettings) _then;

/// Create a copy of ThreadWebSearchSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuration = null,Object? effective = null,}) {
  return _then(ThreadWebSearchSettings(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as WebSearchConfiguration,effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearch,
  ));
}
/// Create a copy of ThreadWebSearchSettings
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationCopyWith<$Res> get configuration {

  return $WebSearchConfigurationCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ThreadWebSearchSettings
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchCopyWith<$Res> get effective {

  return $EffectiveWebSearchCopyWith<$Res>(_self.effective, (value) {
    return _then(_self.copyWith(effective: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadWebSearchSettings].
extension ThreadWebSearchSettingsPatterns on ThreadWebSearchSettings {
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
mixin _$ThreadDeepSeekSearchSettings {


/// Create a copy of ThreadDeepSeekSearchSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDeepSeekSearchSettingsCopyWith<ThreadDeepSeekSearchSettings> get copyWith => _$ThreadDeepSeekSearchSettingsCopyWithImpl<ThreadDeepSeekSearchSettings>(this as ThreadDeepSeekSearchSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDeepSeekSearchSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDeepSeekSearchSettings&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.effective, _this.effective) || other.effective == _this.effective));
}


@override
int get hashCode {
  final _this = this as ThreadDeepSeekSearchSettings;
  return Object.hash(runtimeType,_this.configuration,_this.effective);
}



}

/// @nodoc
abstract mixin class $ThreadDeepSeekSearchSettingsCopyWith<$Res>  {
  factory $ThreadDeepSeekSearchSettingsCopyWith(ThreadDeepSeekSearchSettings value, $Res Function(ThreadDeepSeekSearchSettings) _then) = _$ThreadDeepSeekSearchSettingsCopyWithImpl;
@useResult
$Res call({
 DeepSeekSearchConfiguration configuration, EffectiveDeepSeekSearch effective
});


$DeepSeekSearchConfigurationCopyWith<$Res> get configuration;$EffectiveDeepSeekSearchCopyWith<$Res> get effective;

}
/// @nodoc
class _$ThreadDeepSeekSearchSettingsCopyWithImpl<$Res>
    implements $ThreadDeepSeekSearchSettingsCopyWith<$Res> {
  _$ThreadDeepSeekSearchSettingsCopyWithImpl(this._self, this._then);

  final ThreadDeepSeekSearchSettings _self;
  final $Res Function(ThreadDeepSeekSearchSettings) _then;

/// Create a copy of ThreadDeepSeekSearchSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuration = null,Object? effective = null,}) {
  return _then(ThreadDeepSeekSearchSettings(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfiguration,effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearch,
  ));
}
/// Create a copy of ThreadDeepSeekSearchSettings
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationCopyWith<$Res> get configuration {

  return $DeepSeekSearchConfigurationCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ThreadDeepSeekSearchSettings
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchCopyWith<$Res> get effective {

  return $EffectiveDeepSeekSearchCopyWith<$Res>(_self.effective, (value) {
    return _then(_self.copyWith(effective: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDeepSeekSearchSettings].
extension ThreadDeepSeekSearchSettingsPatterns on ThreadDeepSeekSearchSettings {
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
mixin _$ThreadSettingsCatalogSnapshot {


/// Create a copy of ThreadSettingsCatalogSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsCatalogSnapshotCopyWith<ThreadSettingsCatalogSnapshot> get copyWith => _$ThreadSettingsCatalogSnapshotCopyWithImpl<ThreadSettingsCatalogSnapshot>(this as ThreadSettingsCatalogSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsCatalogSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsCatalogSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsCatalogSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,const DeepCollectionEquality().hash(_this.accounts));
}



}

/// @nodoc
abstract mixin class $ThreadSettingsCatalogSnapshotCopyWith<$Res>  {
  factory $ThreadSettingsCatalogSnapshotCopyWith(ThreadSettingsCatalogSnapshot value, $Res Function(ThreadSettingsCatalogSnapshot) _then) = _$ThreadSettingsCatalogSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, List<ThreadSettingsCatalogAccount> accounts
});




}
/// @nodoc
class _$ThreadSettingsCatalogSnapshotCopyWithImpl<$Res>
    implements $ThreadSettingsCatalogSnapshotCopyWith<$Res> {
  _$ThreadSettingsCatalogSnapshotCopyWithImpl(this._self, this._then);

  final ThreadSettingsCatalogSnapshot _self;
  final $Res Function(ThreadSettingsCatalogSnapshot) _then;

/// Create a copy of ThreadSettingsCatalogSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? accounts = null,}) {
  return _then(ThreadSettingsCatalogSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ThreadSettingsCatalogAccount>,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadSettingsCatalogSnapshot].
extension ThreadSettingsCatalogSnapshotPatterns on ThreadSettingsCatalogSnapshot {
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
mixin _$ThreadSettingsCatalogAccount {


/// Create a copy of ThreadSettingsCatalogAccount
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSettingsCatalogAccountCopyWith<ThreadSettingsCatalogAccount> get copyWith => _$ThreadSettingsCatalogAccountCopyWithImpl<ThreadSettingsCatalogAccount>(this as ThreadSettingsCatalogAccount, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadSettingsCatalogAccount;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSettingsCatalogAccount&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&const DeepCollectionEquality().equals(other.effectiveModels, _this.effectiveModels)&&(identical(other.modelCatalog, _this.modelCatalog) || other.modelCatalog == _this.modelCatalog));
}


@override
int get hashCode {
  final _this = this as ThreadSettingsCatalogAccount;
  return Object.hash(runtimeType,_this.accountId,const DeepCollectionEquality().hash(_this.effectiveModels),_this.modelCatalog);
}



}

/// @nodoc
abstract mixin class $ThreadSettingsCatalogAccountCopyWith<$Res>  {
  factory $ThreadSettingsCatalogAccountCopyWith(ThreadSettingsCatalogAccount value, $Res Function(ThreadSettingsCatalogAccount) _then) = _$ThreadSettingsCatalogAccountCopyWithImpl;
@useResult
$Res call({
 String accountId, List<ModelDescriptor> effectiveModels, ModelCatalogStatus modelCatalog
});


$ModelCatalogStatusCopyWith<$Res> get modelCatalog;

}
/// @nodoc
class _$ThreadSettingsCatalogAccountCopyWithImpl<$Res>
    implements $ThreadSettingsCatalogAccountCopyWith<$Res> {
  _$ThreadSettingsCatalogAccountCopyWithImpl(this._self, this._then);

  final ThreadSettingsCatalogAccount _self;
  final $Res Function(ThreadSettingsCatalogAccount) _then;

/// Create a copy of ThreadSettingsCatalogAccount
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? effectiveModels = null,Object? modelCatalog = null,}) {
  return _then(ThreadSettingsCatalogAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,effectiveModels: null == effectiveModels ? _self.effectiveModels : effectiveModels // ignore: cast_nullable_to_non_nullable
as List<ModelDescriptor>,modelCatalog: null == modelCatalog ? _self.modelCatalog : modelCatalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogStatus,
  ));
}
/// Create a copy of ThreadSettingsCatalogAccount
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogStatusCopyWith<$Res> get modelCatalog {

  return $ModelCatalogStatusCopyWith<$Res>(_self.modelCatalog, (value) {
    return _then(_self.copyWith(modelCatalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadSettingsCatalogAccount].
extension ThreadSettingsCatalogAccountPatterns on ThreadSettingsCatalogAccount {
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

// dart format on
