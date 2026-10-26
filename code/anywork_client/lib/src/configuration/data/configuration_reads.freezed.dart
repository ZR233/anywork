// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConfigurationReadHeader {

 ReadText? get defaultAccountId; TypedListRef get accounts; TypedListRef get acpAccounts; TypedListRef get modeModelRoutes; TypedListRef get roles; ReadText get permissionMode; InstructionsSettingsRead get instructions; SkillsSettingsRead get skills; TypedListRef get mcpServers; GeneralSettingsRead get general; DelegationSettings get delegation; WebSearchConfigurationRead get webSearch; DeepSeekSearchConfigurationRead get deepseekWebSearch;
/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationReadHeaderCopyWith<ConfigurationReadHeader> get copyWith => _$ConfigurationReadHeaderCopyWithImpl<ConfigurationReadHeader>(this as ConfigurationReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationReadHeader&&(identical(other.defaultAccountId, _this.defaultAccountId) || other.defaultAccountId == _this.defaultAccountId)&&(identical(other.accounts, _this.accounts) || other.accounts == _this.accounts)&&(identical(other.acpAccounts, _this.acpAccounts) || other.acpAccounts == _this.acpAccounts)&&(identical(other.modeModelRoutes, _this.modeModelRoutes) || other.modeModelRoutes == _this.modeModelRoutes)&&(identical(other.roles, _this.roles) || other.roles == _this.roles)&&(identical(other.permissionMode, _this.permissionMode) || other.permissionMode == _this.permissionMode)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&(identical(other.skills, _this.skills) || other.skills == _this.skills)&&(identical(other.mcpServers, _this.mcpServers) || other.mcpServers == _this.mcpServers)&&(identical(other.general, _this.general) || other.general == _this.general)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepseekWebSearch, _this.deepseekWebSearch) || other.deepseekWebSearch == _this.deepseekWebSearch));
}


@override
int get hashCode {
  final _this = this as ConfigurationReadHeader;
  return Object.hash(runtimeType,_this.defaultAccountId,_this.accounts,_this.acpAccounts,_this.modeModelRoutes,_this.roles,_this.permissionMode,_this.instructions,_this.skills,_this.mcpServers,_this.general,_this.delegation,_this.webSearch,_this.deepseekWebSearch);
}



}

/// @nodoc
abstract mixin class $ConfigurationReadHeaderCopyWith<$Res>  {
  factory $ConfigurationReadHeaderCopyWith(ConfigurationReadHeader value, $Res Function(ConfigurationReadHeader) _then) = _$ConfigurationReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadText? defaultAccountId, TypedListRef accounts, TypedListRef acpAccounts, TypedListRef modeModelRoutes, TypedListRef roles, ReadText permissionMode, InstructionsSettingsRead instructions, SkillsSettingsRead skills, TypedListRef mcpServers, GeneralSettingsRead general, DelegationSettings delegation, WebSearchConfigurationRead webSearch, DeepSeekSearchConfigurationRead deepseekWebSearch
});


$ReadTextCopyWith<$Res>? get defaultAccountId;$TypedListRefCopyWith<$Res> get accounts;$TypedListRefCopyWith<$Res> get acpAccounts;$TypedListRefCopyWith<$Res> get modeModelRoutes;$TypedListRefCopyWith<$Res> get roles;$ReadTextCopyWith<$Res> get permissionMode;$InstructionsSettingsReadCopyWith<$Res> get instructions;$SkillsSettingsReadCopyWith<$Res> get skills;$TypedListRefCopyWith<$Res> get mcpServers;$GeneralSettingsReadCopyWith<$Res> get general;$DelegationSettingsCopyWith<$Res> get delegation;$WebSearchConfigurationReadCopyWith<$Res> get webSearch;$DeepSeekSearchConfigurationReadCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class _$ConfigurationReadHeaderCopyWithImpl<$Res>
    implements $ConfigurationReadHeaderCopyWith<$Res> {
  _$ConfigurationReadHeaderCopyWithImpl(this._self, this._then);

  final ConfigurationReadHeader _self;
  final $Res Function(ConfigurationReadHeader) _then;

/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? defaultAccountId = freezed,Object? accounts = null,Object? acpAccounts = null,Object? modeModelRoutes = null,Object? roles = null,Object? permissionMode = null,Object? instructions = null,Object? skills = null,Object? mcpServers = null,Object? general = null,Object? delegation = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(ConfigurationReadHeader(
defaultAccountId: freezed == defaultAccountId ? _self.defaultAccountId : defaultAccountId // ignore: cast_nullable_to_non_nullable
as ReadText?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,acpAccounts: null == acpAccounts ? _self.acpAccounts : acpAccounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,modeModelRoutes: null == modeModelRoutes ? _self.modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as TypedListRef,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as TypedListRef,permissionMode: null == permissionMode ? _self.permissionMode : permissionMode // ignore: cast_nullable_to_non_nullable
as ReadText,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as InstructionsSettingsRead,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as SkillsSettingsRead,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as GeneralSettingsRead,delegation: null == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchConfigurationRead,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfigurationRead,
  ));
}
/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get defaultAccountId {
    if (_self.defaultAccountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.defaultAccountId!, (value) {
    return _then(_self.copyWith(defaultAccountId: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get accounts {

  return $TypedListRefCopyWith<$Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get acpAccounts {

  return $TypedListRefCopyWith<$Res>(_self.acpAccounts, (value) {
    return _then(_self.copyWith(acpAccounts: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modeModelRoutes {

  return $TypedListRefCopyWith<$Res>(_self.modeModelRoutes, (value) {
    return _then(_self.copyWith(modeModelRoutes: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get roles {

  return $TypedListRefCopyWith<$Res>(_self.roles, (value) {
    return _then(_self.copyWith(roles: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get permissionMode {

  return $ReadTextCopyWith<$Res>(_self.permissionMode, (value) {
    return _then(_self.copyWith(permissionMode: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsReadCopyWith<$Res> get instructions {

  return $InstructionsSettingsReadCopyWith<$Res>(_self.instructions, (value) {
    return _then(_self.copyWith(instructions: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsSettingsReadCopyWith<$Res> get skills {

  return $SkillsSettingsReadCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mcpServers {

  return $TypedListRefCopyWith<$Res>(_self.mcpServers, (value) {
    return _then(_self.copyWith(mcpServers: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsReadCopyWith<$Res> get general {

  return $GeneralSettingsReadCopyWith<$Res>(_self.general, (value) {
    return _then(_self.copyWith(general: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get delegation {

  return $DelegationSettingsCopyWith<$Res>(_self.delegation, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationReadCopyWith<$Res> get webSearch {

  return $WebSearchConfigurationReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationReadCopyWith<$Res> get deepseekWebSearch {

  return $DeepSeekSearchConfigurationReadCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationReadHeader].
extension ConfigurationReadHeaderPatterns on ConfigurationReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText? defaultAccountId,  TypedListRef accounts,  TypedListRef acpAccounts,  TypedListRef modeModelRoutes,  TypedListRef roles,  ReadText permissionMode,  InstructionsSettingsRead instructions,  SkillsSettingsRead skills,  TypedListRef mcpServers,  GeneralSettingsRead general,  DelegationSettings delegation,  WebSearchConfigurationRead webSearch,  DeepSeekSearchConfigurationRead deepseekWebSearch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationReadHeader() when $default != null:
return $default(_that.defaultAccountId,_that.accounts,_that.acpAccounts,_that.modeModelRoutes,_that.roles,_that.permissionMode,_that.instructions,_that.skills,_that.mcpServers,_that.general,_that.delegation,_that.webSearch,_that.deepseekWebSearch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText? defaultAccountId,  TypedListRef accounts,  TypedListRef acpAccounts,  TypedListRef modeModelRoutes,  TypedListRef roles,  ReadText permissionMode,  InstructionsSettingsRead instructions,  SkillsSettingsRead skills,  TypedListRef mcpServers,  GeneralSettingsRead general,  DelegationSettings delegation,  WebSearchConfigurationRead webSearch,  DeepSeekSearchConfigurationRead deepseekWebSearch)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReadHeader():
return $default(_that.defaultAccountId,_that.accounts,_that.acpAccounts,_that.modeModelRoutes,_that.roles,_that.permissionMode,_that.instructions,_that.skills,_that.mcpServers,_that.general,_that.delegation,_that.webSearch,_that.deepseekWebSearch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText? defaultAccountId,  TypedListRef accounts,  TypedListRef acpAccounts,  TypedListRef modeModelRoutes,  TypedListRef roles,  ReadText permissionMode,  InstructionsSettingsRead instructions,  SkillsSettingsRead skills,  TypedListRef mcpServers,  GeneralSettingsRead general,  DelegationSettings delegation,  WebSearchConfigurationRead webSearch,  DeepSeekSearchConfigurationRead deepseekWebSearch)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReadHeader() when $default != null:
return $default(_that.defaultAccountId,_that.accounts,_that.acpAccounts,_that.modeModelRoutes,_that.roles,_that.permissionMode,_that.instructions,_that.skills,_that.mcpServers,_that.general,_that.delegation,_that.webSearch,_that.deepseekWebSearch);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationReadHeader implements ConfigurationReadHeader {
  const _ConfigurationReadHeader({required this.defaultAccountId, required this.accounts, required this.acpAccounts, required this.modeModelRoutes, required this.roles, required this.permissionMode, required this.instructions, required this.skills, required this.mcpServers, required this.general, required this.delegation, required this.webSearch, required this.deepseekWebSearch});


@override final  ReadText? defaultAccountId;
@override final  TypedListRef accounts;
@override final  TypedListRef acpAccounts;
@override final  TypedListRef modeModelRoutes;
@override final  TypedListRef roles;
@override final  ReadText permissionMode;
@override final  InstructionsSettingsRead instructions;
@override final  SkillsSettingsRead skills;
@override final  TypedListRef mcpServers;
@override final  GeneralSettingsRead general;
@override final  DelegationSettings delegation;
@override final  WebSearchConfigurationRead webSearch;
@override final  DeepSeekSearchConfigurationRead deepseekWebSearch;

/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationReadHeaderCopyWith<_ConfigurationReadHeader> get copyWith => __$ConfigurationReadHeaderCopyWithImpl<_ConfigurationReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationReadHeader&&(identical(other.defaultAccountId, defaultAccountId) || other.defaultAccountId == defaultAccountId)&&(identical(other.accounts, accounts) || other.accounts == accounts)&&(identical(other.acpAccounts, acpAccounts) || other.acpAccounts == acpAccounts)&&(identical(other.modeModelRoutes, modeModelRoutes) || other.modeModelRoutes == modeModelRoutes)&&(identical(other.roles, roles) || other.roles == roles)&&(identical(other.permissionMode, permissionMode) || other.permissionMode == permissionMode)&&(identical(other.instructions, instructions) || other.instructions == instructions)&&(identical(other.skills, skills) || other.skills == skills)&&(identical(other.mcpServers, mcpServers) || other.mcpServers == mcpServers)&&(identical(other.general, general) || other.general == general)&&(identical(other.delegation, delegation) || other.delegation == delegation)&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.deepseekWebSearch, deepseekWebSearch) || other.deepseekWebSearch == deepseekWebSearch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,defaultAccountId,accounts,acpAccounts,modeModelRoutes,roles,permissionMode,instructions,skills,mcpServers,general,delegation,webSearch,deepseekWebSearch);
}



}

/// @nodoc
abstract mixin class _$ConfigurationReadHeaderCopyWith<$Res> implements $ConfigurationReadHeaderCopyWith<$Res> {
  factory _$ConfigurationReadHeaderCopyWith(_ConfigurationReadHeader value, $Res Function(_ConfigurationReadHeader) _then) = __$ConfigurationReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadText? defaultAccountId, TypedListRef accounts, TypedListRef acpAccounts, TypedListRef modeModelRoutes, TypedListRef roles, ReadText permissionMode, InstructionsSettingsRead instructions, SkillsSettingsRead skills, TypedListRef mcpServers, GeneralSettingsRead general, DelegationSettings delegation, WebSearchConfigurationRead webSearch, DeepSeekSearchConfigurationRead deepseekWebSearch
});


@override $ReadTextCopyWith<$Res>? get defaultAccountId;@override $TypedListRefCopyWith<$Res> get accounts;@override $TypedListRefCopyWith<$Res> get acpAccounts;@override $TypedListRefCopyWith<$Res> get modeModelRoutes;@override $TypedListRefCopyWith<$Res> get roles;@override $ReadTextCopyWith<$Res> get permissionMode;@override $InstructionsSettingsReadCopyWith<$Res> get instructions;@override $SkillsSettingsReadCopyWith<$Res> get skills;@override $TypedListRefCopyWith<$Res> get mcpServers;@override $GeneralSettingsReadCopyWith<$Res> get general;@override $DelegationSettingsCopyWith<$Res> get delegation;@override $WebSearchConfigurationReadCopyWith<$Res> get webSearch;@override $DeepSeekSearchConfigurationReadCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class __$ConfigurationReadHeaderCopyWithImpl<$Res>
    implements _$ConfigurationReadHeaderCopyWith<$Res> {
  __$ConfigurationReadHeaderCopyWithImpl(this._self, this._then);

  final _ConfigurationReadHeader _self;
  final $Res Function(_ConfigurationReadHeader) _then;

/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? defaultAccountId = freezed,Object? accounts = null,Object? acpAccounts = null,Object? modeModelRoutes = null,Object? roles = null,Object? permissionMode = null,Object? instructions = null,Object? skills = null,Object? mcpServers = null,Object? general = null,Object? delegation = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(_ConfigurationReadHeader(
defaultAccountId: freezed == defaultAccountId ? _self.defaultAccountId : defaultAccountId // ignore: cast_nullable_to_non_nullable
as ReadText?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,acpAccounts: null == acpAccounts ? _self.acpAccounts : acpAccounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,modeModelRoutes: null == modeModelRoutes ? _self.modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as TypedListRef,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as TypedListRef,permissionMode: null == permissionMode ? _self.permissionMode : permissionMode // ignore: cast_nullable_to_non_nullable
as ReadText,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as InstructionsSettingsRead,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as SkillsSettingsRead,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as GeneralSettingsRead,delegation: null == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchConfigurationRead,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfigurationRead,
  ));
}

/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get defaultAccountId {
    if (_self.defaultAccountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.defaultAccountId!, (value) {
    return _then(_self.copyWith(defaultAccountId: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get accounts {

  return $TypedListRefCopyWith<$Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get acpAccounts {

  return $TypedListRefCopyWith<$Res>(_self.acpAccounts, (value) {
    return _then(_self.copyWith(acpAccounts: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modeModelRoutes {

  return $TypedListRefCopyWith<$Res>(_self.modeModelRoutes, (value) {
    return _then(_self.copyWith(modeModelRoutes: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get roles {

  return $TypedListRefCopyWith<$Res>(_self.roles, (value) {
    return _then(_self.copyWith(roles: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get permissionMode {

  return $ReadTextCopyWith<$Res>(_self.permissionMode, (value) {
    return _then(_self.copyWith(permissionMode: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsReadCopyWith<$Res> get instructions {

  return $InstructionsSettingsReadCopyWith<$Res>(_self.instructions, (value) {
    return _then(_self.copyWith(instructions: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsSettingsReadCopyWith<$Res> get skills {

  return $SkillsSettingsReadCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mcpServers {

  return $TypedListRefCopyWith<$Res>(_self.mcpServers, (value) {
    return _then(_self.copyWith(mcpServers: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsReadCopyWith<$Res> get general {

  return $GeneralSettingsReadCopyWith<$Res>(_self.general, (value) {
    return _then(_self.copyWith(general: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get delegation {

  return $DelegationSettingsCopyWith<$Res>(_self.delegation, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationReadCopyWith<$Res> get webSearch {

  return $WebSearchConfigurationReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationReadCopyWith<$Res> get deepseekWebSearch {

  return $DeepSeekSearchConfigurationReadCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}

/// @nodoc
mixin _$AcpAccountConfigurationRead {

 ReadText get accountId; ReadText get name; AcpProvider get provider; int get connectionRevision;
/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountConfigurationReadCopyWith<AcpAccountConfigurationRead> get copyWith => _$AcpAccountConfigurationReadCopyWithImpl<AcpAccountConfigurationRead>(this as AcpAccountConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountConfigurationRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.connectionRevision, _this.connectionRevision) || other.connectionRevision == _this.connectionRevision));
}


@override
int get hashCode {
  final _this = this as AcpAccountConfigurationRead;
  return Object.hash(runtimeType,_this.accountId,_this.name,_this.provider,_this.connectionRevision);
}



}

/// @nodoc
abstract mixin class $AcpAccountConfigurationReadCopyWith<$Res>  {
  factory $AcpAccountConfigurationReadCopyWith(AcpAccountConfigurationRead value, $Res Function(AcpAccountConfigurationRead) _then) = _$AcpAccountConfigurationReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, ReadText name, AcpProvider provider, int connectionRevision
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class _$AcpAccountConfigurationReadCopyWithImpl<$Res>
    implements $AcpAccountConfigurationReadCopyWith<$Res> {
  _$AcpAccountConfigurationReadCopyWithImpl(this._self, this._then);

  final AcpAccountConfigurationRead _self;
  final $Res Function(AcpAccountConfigurationRead) _then;

/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? name = null,Object? provider = null,Object? connectionRevision = null,}) {
  return _then(AcpAccountConfigurationRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountConfigurationRead].
extension AcpAccountConfigurationReadPatterns on AcpAccountConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText name,  AcpProvider provider,  int connectionRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead() when $default != null:
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText name,  AcpProvider provider,  int connectionRevision)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead():
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  ReadText name,  AcpProvider provider,  int connectionRevision)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountConfigurationRead() when $default != null:
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountConfigurationRead implements AcpAccountConfigurationRead {
  const _AcpAccountConfigurationRead({required this.accountId, required this.name, required this.provider, required this.connectionRevision});


@override final  ReadText accountId;
@override final  ReadText name;
@override final  AcpProvider provider;
@override final  int connectionRevision;

/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountConfigurationReadCopyWith<_AcpAccountConfigurationRead> get copyWith => __$AcpAccountConfigurationReadCopyWithImpl<_AcpAccountConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountConfigurationRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.name, name) || other.name == name)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,name,provider,connectionRevision);
}



}

/// @nodoc
abstract mixin class _$AcpAccountConfigurationReadCopyWith<$Res> implements $AcpAccountConfigurationReadCopyWith<$Res> {
  factory _$AcpAccountConfigurationReadCopyWith(_AcpAccountConfigurationRead value, $Res Function(_AcpAccountConfigurationRead) _then) = __$AcpAccountConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, ReadText name, AcpProvider provider, int connectionRevision
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class __$AcpAccountConfigurationReadCopyWithImpl<$Res>
    implements _$AcpAccountConfigurationReadCopyWith<$Res> {
  __$AcpAccountConfigurationReadCopyWithImpl(this._self, this._then);

  final _AcpAccountConfigurationRead _self;
  final $Res Function(_AcpAccountConfigurationRead) _then;

/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? name = null,Object? provider = null,Object? connectionRevision = null,}) {
  return _then(_AcpAccountConfigurationRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AcpAccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}

/// @nodoc
mixin _$AccountConfigurationRead {

 BillingKind get billingKind; BillingKind? get billingKindOverride; TypedListRef get disabledModels; ReadText get accountId; ReadText? get templateId; ReadText get protocol; ReadText get name; ReadText get baseUrl; bool get hasBearerToken; ReadText? get bearerTokenEnv; int get usageQueryRevision; TypedListRef get customModels; TypedListRef get modelConnectionModes; TypedListRef get modelAutoCompactLimits; ReadText? get catalogId;
/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountConfigurationReadCopyWith<AccountConfigurationRead> get copyWith => _$AccountConfigurationReadCopyWithImpl<AccountConfigurationRead>(this as AccountConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountConfigurationRead&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.billingKindOverride, _this.billingKindOverride) || other.billingKindOverride == _this.billingKindOverride)&&(identical(other.disabledModels, _this.disabledModels) || other.disabledModels == _this.disabledModels)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.templateId, _this.templateId) || other.templateId == _this.templateId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.hasBearerToken, _this.hasBearerToken) || other.hasBearerToken == _this.hasBearerToken)&&(identical(other.bearerTokenEnv, _this.bearerTokenEnv) || other.bearerTokenEnv == _this.bearerTokenEnv)&&(identical(other.usageQueryRevision, _this.usageQueryRevision) || other.usageQueryRevision == _this.usageQueryRevision)&&(identical(other.customModels, _this.customModels) || other.customModels == _this.customModels)&&(identical(other.modelConnectionModes, _this.modelConnectionModes) || other.modelConnectionModes == _this.modelConnectionModes)&&(identical(other.modelAutoCompactLimits, _this.modelAutoCompactLimits) || other.modelAutoCompactLimits == _this.modelAutoCompactLimits)&&(identical(other.catalogId, _this.catalogId) || other.catalogId == _this.catalogId));
}


@override
int get hashCode {
  final _this = this as AccountConfigurationRead;
  return Object.hash(runtimeType,_this.billingKind,_this.billingKindOverride,_this.disabledModels,_this.accountId,_this.templateId,_this.protocol,_this.name,_this.baseUrl,_this.hasBearerToken,_this.bearerTokenEnv,_this.usageQueryRevision,_this.customModels,_this.modelConnectionModes,_this.modelAutoCompactLimits,_this.catalogId);
}



}

/// @nodoc
abstract mixin class $AccountConfigurationReadCopyWith<$Res>  {
  factory $AccountConfigurationReadCopyWith(AccountConfigurationRead value, $Res Function(AccountConfigurationRead) _then) = _$AccountConfigurationReadCopyWithImpl;
@useResult
$Res call({
 BillingKind billingKind, BillingKind? billingKindOverride, TypedListRef disabledModels, ReadText accountId, ReadText? templateId, ReadText protocol, ReadText name, ReadText baseUrl, bool hasBearerToken, ReadText? bearerTokenEnv, int usageQueryRevision, TypedListRef customModels, TypedListRef modelConnectionModes, TypedListRef modelAutoCompactLimits, ReadText? catalogId
});


$TypedListRefCopyWith<$Res> get disabledModels;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res>? get templateId;$ReadTextCopyWith<$Res> get protocol;$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get baseUrl;$ReadTextCopyWith<$Res>? get bearerTokenEnv;$TypedListRefCopyWith<$Res> get customModels;$TypedListRefCopyWith<$Res> get modelConnectionModes;$TypedListRefCopyWith<$Res> get modelAutoCompactLimits;$ReadTextCopyWith<$Res>? get catalogId;

}
/// @nodoc
class _$AccountConfigurationReadCopyWithImpl<$Res>
    implements $AccountConfigurationReadCopyWith<$Res> {
  _$AccountConfigurationReadCopyWithImpl(this._self, this._then);

  final AccountConfigurationRead _self;
  final $Res Function(AccountConfigurationRead) _then;

/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? billingKind = null,Object? billingKindOverride = freezed,Object? disabledModels = null,Object? accountId = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? hasBearerToken = null,Object? bearerTokenEnv = freezed,Object? usageQueryRevision = null,Object? customModels = null,Object? modelConnectionModes = null,Object? modelAutoCompactLimits = null,Object? catalogId = freezed,}) {
  return _then(AccountConfigurationRead(
billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,billingKindOverride: freezed == billingKindOverride ? _self.billingKindOverride : billingKindOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,disabledModels: null == disabledModels ? _self.disabledModels : disabledModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as ReadText?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as ReadText,hasBearerToken: null == hasBearerToken ? _self.hasBearerToken : hasBearerToken // ignore: cast_nullable_to_non_nullable
as bool,bearerTokenEnv: freezed == bearerTokenEnv ? _self.bearerTokenEnv : bearerTokenEnv // ignore: cast_nullable_to_non_nullable
as ReadText?,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelConnectionModes: null == modelConnectionModes ? _self.modelConnectionModes : modelConnectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelAutoCompactLimits: null == modelAutoCompactLimits ? _self.modelAutoCompactLimits : modelAutoCompactLimits // ignore: cast_nullable_to_non_nullable
as TypedListRef,catalogId: freezed == catalogId ? _self.catalogId : catalogId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get disabledModels {

  return $TypedListRefCopyWith<$Res>(_self.disabledModels, (value) {
    return _then(_self.copyWith(disabledModels: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get templateId {
    if (_self.templateId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.templateId!, (value) {
    return _then(_self.copyWith(templateId: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseUrl {

  return $ReadTextCopyWith<$Res>(_self.baseUrl, (value) {
    return _then(_self.copyWith(baseUrl: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get bearerTokenEnv {
    if (_self.bearerTokenEnv == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.bearerTokenEnv!, (value) {
    return _then(_self.copyWith(bearerTokenEnv: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get customModels {

  return $TypedListRefCopyWith<$Res>(_self.customModels, (value) {
    return _then(_self.copyWith(customModels: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelConnectionModes {

  return $TypedListRefCopyWith<$Res>(_self.modelConnectionModes, (value) {
    return _then(_self.copyWith(modelConnectionModes: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelAutoCompactLimits {

  return $TypedListRefCopyWith<$Res>(_self.modelAutoCompactLimits, (value) {
    return _then(_self.copyWith(modelAutoCompactLimits: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get catalogId {
    if (_self.catalogId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.catalogId!, (value) {
    return _then(_self.copyWith(catalogId: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountConfigurationRead].
extension AccountConfigurationReadPatterns on AccountConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( BillingKind billingKind,  BillingKind? billingKindOverride,  TypedListRef disabledModels,  ReadText accountId,  ReadText? templateId,  ReadText protocol,  ReadText name,  ReadText baseUrl,  bool hasBearerToken,  ReadText? bearerTokenEnv,  int usageQueryRevision,  TypedListRef customModels,  TypedListRef modelConnectionModes,  TypedListRef modelAutoCompactLimits,  ReadText? catalogId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountConfigurationRead() when $default != null:
return $default(_that.billingKind,_that.billingKindOverride,_that.disabledModels,_that.accountId,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.hasBearerToken,_that.bearerTokenEnv,_that.usageQueryRevision,_that.customModels,_that.modelConnectionModes,_that.modelAutoCompactLimits,_that.catalogId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( BillingKind billingKind,  BillingKind? billingKindOverride,  TypedListRef disabledModels,  ReadText accountId,  ReadText? templateId,  ReadText protocol,  ReadText name,  ReadText baseUrl,  bool hasBearerToken,  ReadText? bearerTokenEnv,  int usageQueryRevision,  TypedListRef customModels,  TypedListRef modelConnectionModes,  TypedListRef modelAutoCompactLimits,  ReadText? catalogId)  $default,) {final _that = this;
switch (_that) {
case _AccountConfigurationRead():
return $default(_that.billingKind,_that.billingKindOverride,_that.disabledModels,_that.accountId,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.hasBearerToken,_that.bearerTokenEnv,_that.usageQueryRevision,_that.customModels,_that.modelConnectionModes,_that.modelAutoCompactLimits,_that.catalogId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( BillingKind billingKind,  BillingKind? billingKindOverride,  TypedListRef disabledModels,  ReadText accountId,  ReadText? templateId,  ReadText protocol,  ReadText name,  ReadText baseUrl,  bool hasBearerToken,  ReadText? bearerTokenEnv,  int usageQueryRevision,  TypedListRef customModels,  TypedListRef modelConnectionModes,  TypedListRef modelAutoCompactLimits,  ReadText? catalogId)?  $default,) {final _that = this;
switch (_that) {
case _AccountConfigurationRead() when $default != null:
return $default(_that.billingKind,_that.billingKindOverride,_that.disabledModels,_that.accountId,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.hasBearerToken,_that.bearerTokenEnv,_that.usageQueryRevision,_that.customModels,_that.modelConnectionModes,_that.modelAutoCompactLimits,_that.catalogId);case _:
  return null;

}
}

}

/// @nodoc


class _AccountConfigurationRead implements AccountConfigurationRead {
  const _AccountConfigurationRead({required this.billingKind, required this.billingKindOverride, required this.disabledModels, required this.accountId, required this.templateId, required this.protocol, required this.name, required this.baseUrl, required this.hasBearerToken, required this.bearerTokenEnv, required this.usageQueryRevision, required this.customModels, required this.modelConnectionModes, required this.modelAutoCompactLimits, required this.catalogId});


@override final  BillingKind billingKind;
@override final  BillingKind? billingKindOverride;
@override final  TypedListRef disabledModels;
@override final  ReadText accountId;
@override final  ReadText? templateId;
@override final  ReadText protocol;
@override final  ReadText name;
@override final  ReadText baseUrl;
@override final  bool hasBearerToken;
@override final  ReadText? bearerTokenEnv;
@override final  int usageQueryRevision;
@override final  TypedListRef customModels;
@override final  TypedListRef modelConnectionModes;
@override final  TypedListRef modelAutoCompactLimits;
@override final  ReadText? catalogId;

/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountConfigurationReadCopyWith<_AccountConfigurationRead> get copyWith => __$AccountConfigurationReadCopyWithImpl<_AccountConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountConfigurationRead&&(identical(other.billingKind, billingKind) || other.billingKind == billingKind)&&(identical(other.billingKindOverride, billingKindOverride) || other.billingKindOverride == billingKindOverride)&&(identical(other.disabledModels, disabledModels) || other.disabledModels == disabledModels)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.templateId, templateId) || other.templateId == templateId)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.name, name) || other.name == name)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.hasBearerToken, hasBearerToken) || other.hasBearerToken == hasBearerToken)&&(identical(other.bearerTokenEnv, bearerTokenEnv) || other.bearerTokenEnv == bearerTokenEnv)&&(identical(other.usageQueryRevision, usageQueryRevision) || other.usageQueryRevision == usageQueryRevision)&&(identical(other.customModels, customModels) || other.customModels == customModels)&&(identical(other.modelConnectionModes, modelConnectionModes) || other.modelConnectionModes == modelConnectionModes)&&(identical(other.modelAutoCompactLimits, modelAutoCompactLimits) || other.modelAutoCompactLimits == modelAutoCompactLimits)&&(identical(other.catalogId, catalogId) || other.catalogId == catalogId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,billingKind,billingKindOverride,disabledModels,accountId,templateId,protocol,name,baseUrl,hasBearerToken,bearerTokenEnv,usageQueryRevision,customModels,modelConnectionModes,modelAutoCompactLimits,catalogId);
}



}

/// @nodoc
abstract mixin class _$AccountConfigurationReadCopyWith<$Res> implements $AccountConfigurationReadCopyWith<$Res> {
  factory _$AccountConfigurationReadCopyWith(_AccountConfigurationRead value, $Res Function(_AccountConfigurationRead) _then) = __$AccountConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 BillingKind billingKind, BillingKind? billingKindOverride, TypedListRef disabledModels, ReadText accountId, ReadText? templateId, ReadText protocol, ReadText name, ReadText baseUrl, bool hasBearerToken, ReadText? bearerTokenEnv, int usageQueryRevision, TypedListRef customModels, TypedListRef modelConnectionModes, TypedListRef modelAutoCompactLimits, ReadText? catalogId
});


@override $TypedListRefCopyWith<$Res> get disabledModels;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res>? get templateId;@override $ReadTextCopyWith<$Res> get protocol;@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get baseUrl;@override $ReadTextCopyWith<$Res>? get bearerTokenEnv;@override $TypedListRefCopyWith<$Res> get customModels;@override $TypedListRefCopyWith<$Res> get modelConnectionModes;@override $TypedListRefCopyWith<$Res> get modelAutoCompactLimits;@override $ReadTextCopyWith<$Res>? get catalogId;

}
/// @nodoc
class __$AccountConfigurationReadCopyWithImpl<$Res>
    implements _$AccountConfigurationReadCopyWith<$Res> {
  __$AccountConfigurationReadCopyWithImpl(this._self, this._then);

  final _AccountConfigurationRead _self;
  final $Res Function(_AccountConfigurationRead) _then;

/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? billingKind = null,Object? billingKindOverride = freezed,Object? disabledModels = null,Object? accountId = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? hasBearerToken = null,Object? bearerTokenEnv = freezed,Object? usageQueryRevision = null,Object? customModels = null,Object? modelConnectionModes = null,Object? modelAutoCompactLimits = null,Object? catalogId = freezed,}) {
  return _then(_AccountConfigurationRead(
billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,billingKindOverride: freezed == billingKindOverride ? _self.billingKindOverride : billingKindOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,disabledModels: null == disabledModels ? _self.disabledModels : disabledModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as ReadText?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as ReadText,hasBearerToken: null == hasBearerToken ? _self.hasBearerToken : hasBearerToken // ignore: cast_nullable_to_non_nullable
as bool,bearerTokenEnv: freezed == bearerTokenEnv ? _self.bearerTokenEnv : bearerTokenEnv // ignore: cast_nullable_to_non_nullable
as ReadText?,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelConnectionModes: null == modelConnectionModes ? _self.modelConnectionModes : modelConnectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelAutoCompactLimits: null == modelAutoCompactLimits ? _self.modelAutoCompactLimits : modelAutoCompactLimits // ignore: cast_nullable_to_non_nullable
as TypedListRef,catalogId: freezed == catalogId ? _self.catalogId : catalogId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get disabledModels {

  return $TypedListRefCopyWith<$Res>(_self.disabledModels, (value) {
    return _then(_self.copyWith(disabledModels: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get templateId {
    if (_self.templateId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.templateId!, (value) {
    return _then(_self.copyWith(templateId: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseUrl {

  return $ReadTextCopyWith<$Res>(_self.baseUrl, (value) {
    return _then(_self.copyWith(baseUrl: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get bearerTokenEnv {
    if (_self.bearerTokenEnv == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.bearerTokenEnv!, (value) {
    return _then(_self.copyWith(bearerTokenEnv: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get customModels {

  return $TypedListRefCopyWith<$Res>(_self.customModels, (value) {
    return _then(_self.copyWith(customModels: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelConnectionModes {

  return $TypedListRefCopyWith<$Res>(_self.modelConnectionModes, (value) {
    return _then(_self.copyWith(modelConnectionModes: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelAutoCompactLimits {

  return $TypedListRefCopyWith<$Res>(_self.modelAutoCompactLimits, (value) {
    return _then(_self.copyWith(modelAutoCompactLimits: value));
  });
}/// Create a copy of AccountConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get catalogId {
    if (_self.catalogId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.catalogId!, (value) {
    return _then(_self.copyWith(catalogId: value));
  });
}
}

/// @nodoc
mixin _$CustomModelConfigurationRead {

 TypedListRef get inputCapabilities; int? get contextWindow; int? get maxOutputTokens; ReadText get modelId; ReadText get displayName; TypedListRef get reasoningEfforts; ReadText get baseInstructions; ReadText get wireApi; TypedListRef get supportedConnectionModes; ReadText get defaultConnectionMode;
/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomModelConfigurationReadCopyWith<CustomModelConfigurationRead> get copyWith => _$CustomModelConfigurationReadCopyWithImpl<CustomModelConfigurationRead>(this as CustomModelConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CustomModelConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomModelConfigurationRead&&(identical(other.inputCapabilities, _this.inputCapabilities) || other.inputCapabilities == _this.inputCapabilities)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.reasoningEfforts, _this.reasoningEfforts) || other.reasoningEfforts == _this.reasoningEfforts)&&(identical(other.baseInstructions, _this.baseInstructions) || other.baseInstructions == _this.baseInstructions)&&(identical(other.wireApi, _this.wireApi) || other.wireApi == _this.wireApi)&&(identical(other.supportedConnectionModes, _this.supportedConnectionModes) || other.supportedConnectionModes == _this.supportedConnectionModes)&&(identical(other.defaultConnectionMode, _this.defaultConnectionMode) || other.defaultConnectionMode == _this.defaultConnectionMode));
}


@override
int get hashCode {
  final _this = this as CustomModelConfigurationRead;
  return Object.hash(runtimeType,_this.inputCapabilities,_this.contextWindow,_this.maxOutputTokens,_this.modelId,_this.displayName,_this.reasoningEfforts,_this.baseInstructions,_this.wireApi,_this.supportedConnectionModes,_this.defaultConnectionMode);
}



}

/// @nodoc
abstract mixin class $CustomModelConfigurationReadCopyWith<$Res>  {
  factory $CustomModelConfigurationReadCopyWith(CustomModelConfigurationRead value, $Res Function(CustomModelConfigurationRead) _then) = _$CustomModelConfigurationReadCopyWithImpl;
@useResult
$Res call({
 TypedListRef inputCapabilities, int? contextWindow, int? maxOutputTokens, ReadText modelId, ReadText displayName, TypedListRef reasoningEfforts, ReadText baseInstructions, ReadText wireApi, TypedListRef supportedConnectionModes, ReadText defaultConnectionMode
});


$TypedListRefCopyWith<$Res> get inputCapabilities;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res> get displayName;$TypedListRefCopyWith<$Res> get reasoningEfforts;$ReadTextCopyWith<$Res> get baseInstructions;$ReadTextCopyWith<$Res> get wireApi;$TypedListRefCopyWith<$Res> get supportedConnectionModes;$ReadTextCopyWith<$Res> get defaultConnectionMode;

}
/// @nodoc
class _$CustomModelConfigurationReadCopyWithImpl<$Res>
    implements $CustomModelConfigurationReadCopyWith<$Res> {
  _$CustomModelConfigurationReadCopyWithImpl(this._self, this._then);

  final CustomModelConfigurationRead _self;
  final $Res Function(CustomModelConfigurationRead) _then;

/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputCapabilities = null,Object? contextWindow = freezed,Object? maxOutputTokens = freezed,Object? modelId = null,Object? displayName = null,Object? reasoningEfforts = null,Object? baseInstructions = null,Object? wireApi = null,Object? supportedConnectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(CustomModelConfigurationRead(
inputCapabilities: null == inputCapabilities ? _self.inputCapabilities : inputCapabilities // ignore: cast_nullable_to_non_nullable
as TypedListRef,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,reasoningEfforts: null == reasoningEfforts ? _self.reasoningEfforts : reasoningEfforts // ignore: cast_nullable_to_non_nullable
as TypedListRef,baseInstructions: null == baseInstructions ? _self.baseInstructions : baseInstructions // ignore: cast_nullable_to_non_nullable
as ReadText,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as ReadText,supportedConnectionModes: null == supportedConnectionModes ? _self.supportedConnectionModes : supportedConnectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get inputCapabilities {

  return $TypedListRefCopyWith<$Res>(_self.inputCapabilities, (value) {
    return _then(_self.copyWith(inputCapabilities: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get reasoningEfforts {

  return $TypedListRefCopyWith<$Res>(_self.reasoningEfforts, (value) {
    return _then(_self.copyWith(reasoningEfforts: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseInstructions {

  return $ReadTextCopyWith<$Res>(_self.baseInstructions, (value) {
    return _then(_self.copyWith(baseInstructions: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get wireApi {

  return $ReadTextCopyWith<$Res>(_self.wireApi, (value) {
    return _then(_self.copyWith(wireApi: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get supportedConnectionModes {

  return $TypedListRefCopyWith<$Res>(_self.supportedConnectionModes, (value) {
    return _then(_self.copyWith(supportedConnectionModes: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultConnectionMode {

  return $ReadTextCopyWith<$Res>(_self.defaultConnectionMode, (value) {
    return _then(_self.copyWith(defaultConnectionMode: value));
  });
}
}


/// Adds pattern-matching-related methods to [CustomModelConfigurationRead].
extension CustomModelConfigurationReadPatterns on CustomModelConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomModelConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomModelConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomModelConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _CustomModelConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomModelConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _CustomModelConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef inputCapabilities,  int? contextWindow,  int? maxOutputTokens,  ReadText modelId,  ReadText displayName,  TypedListRef reasoningEfforts,  ReadText baseInstructions,  ReadText wireApi,  TypedListRef supportedConnectionModes,  ReadText defaultConnectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomModelConfigurationRead() when $default != null:
return $default(_that.inputCapabilities,_that.contextWindow,_that.maxOutputTokens,_that.modelId,_that.displayName,_that.reasoningEfforts,_that.baseInstructions,_that.wireApi,_that.supportedConnectionModes,_that.defaultConnectionMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef inputCapabilities,  int? contextWindow,  int? maxOutputTokens,  ReadText modelId,  ReadText displayName,  TypedListRef reasoningEfforts,  ReadText baseInstructions,  ReadText wireApi,  TypedListRef supportedConnectionModes,  ReadText defaultConnectionMode)  $default,) {final _that = this;
switch (_that) {
case _CustomModelConfigurationRead():
return $default(_that.inputCapabilities,_that.contextWindow,_that.maxOutputTokens,_that.modelId,_that.displayName,_that.reasoningEfforts,_that.baseInstructions,_that.wireApi,_that.supportedConnectionModes,_that.defaultConnectionMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef inputCapabilities,  int? contextWindow,  int? maxOutputTokens,  ReadText modelId,  ReadText displayName,  TypedListRef reasoningEfforts,  ReadText baseInstructions,  ReadText wireApi,  TypedListRef supportedConnectionModes,  ReadText defaultConnectionMode)?  $default,) {final _that = this;
switch (_that) {
case _CustomModelConfigurationRead() when $default != null:
return $default(_that.inputCapabilities,_that.contextWindow,_that.maxOutputTokens,_that.modelId,_that.displayName,_that.reasoningEfforts,_that.baseInstructions,_that.wireApi,_that.supportedConnectionModes,_that.defaultConnectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _CustomModelConfigurationRead implements CustomModelConfigurationRead {
  const _CustomModelConfigurationRead({required this.inputCapabilities, required this.contextWindow, required this.maxOutputTokens, required this.modelId, required this.displayName, required this.reasoningEfforts, required this.baseInstructions, required this.wireApi, required this.supportedConnectionModes, required this.defaultConnectionMode});


@override final  TypedListRef inputCapabilities;
@override final  int? contextWindow;
@override final  int? maxOutputTokens;
@override final  ReadText modelId;
@override final  ReadText displayName;
@override final  TypedListRef reasoningEfforts;
@override final  ReadText baseInstructions;
@override final  ReadText wireApi;
@override final  TypedListRef supportedConnectionModes;
@override final  ReadText defaultConnectionMode;

/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomModelConfigurationReadCopyWith<_CustomModelConfigurationRead> get copyWith => __$CustomModelConfigurationReadCopyWithImpl<_CustomModelConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomModelConfigurationRead&&(identical(other.inputCapabilities, inputCapabilities) || other.inputCapabilities == inputCapabilities)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxOutputTokens, maxOutputTokens) || other.maxOutputTokens == maxOutputTokens)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.reasoningEfforts, reasoningEfforts) || other.reasoningEfforts == reasoningEfforts)&&(identical(other.baseInstructions, baseInstructions) || other.baseInstructions == baseInstructions)&&(identical(other.wireApi, wireApi) || other.wireApi == wireApi)&&(identical(other.supportedConnectionModes, supportedConnectionModes) || other.supportedConnectionModes == supportedConnectionModes)&&(identical(other.defaultConnectionMode, defaultConnectionMode) || other.defaultConnectionMode == defaultConnectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inputCapabilities,contextWindow,maxOutputTokens,modelId,displayName,reasoningEfforts,baseInstructions,wireApi,supportedConnectionModes,defaultConnectionMode);
}



}

/// @nodoc
abstract mixin class _$CustomModelConfigurationReadCopyWith<$Res> implements $CustomModelConfigurationReadCopyWith<$Res> {
  factory _$CustomModelConfigurationReadCopyWith(_CustomModelConfigurationRead value, $Res Function(_CustomModelConfigurationRead) _then) = __$CustomModelConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef inputCapabilities, int? contextWindow, int? maxOutputTokens, ReadText modelId, ReadText displayName, TypedListRef reasoningEfforts, ReadText baseInstructions, ReadText wireApi, TypedListRef supportedConnectionModes, ReadText defaultConnectionMode
});


@override $TypedListRefCopyWith<$Res> get inputCapabilities;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res> get displayName;@override $TypedListRefCopyWith<$Res> get reasoningEfforts;@override $ReadTextCopyWith<$Res> get baseInstructions;@override $ReadTextCopyWith<$Res> get wireApi;@override $TypedListRefCopyWith<$Res> get supportedConnectionModes;@override $ReadTextCopyWith<$Res> get defaultConnectionMode;

}
/// @nodoc
class __$CustomModelConfigurationReadCopyWithImpl<$Res>
    implements _$CustomModelConfigurationReadCopyWith<$Res> {
  __$CustomModelConfigurationReadCopyWithImpl(this._self, this._then);

  final _CustomModelConfigurationRead _self;
  final $Res Function(_CustomModelConfigurationRead) _then;

/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inputCapabilities = null,Object? contextWindow = freezed,Object? maxOutputTokens = freezed,Object? modelId = null,Object? displayName = null,Object? reasoningEfforts = null,Object? baseInstructions = null,Object? wireApi = null,Object? supportedConnectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(_CustomModelConfigurationRead(
inputCapabilities: null == inputCapabilities ? _self.inputCapabilities : inputCapabilities // ignore: cast_nullable_to_non_nullable
as TypedListRef,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,reasoningEfforts: null == reasoningEfforts ? _self.reasoningEfforts : reasoningEfforts // ignore: cast_nullable_to_non_nullable
as TypedListRef,baseInstructions: null == baseInstructions ? _self.baseInstructions : baseInstructions // ignore: cast_nullable_to_non_nullable
as ReadText,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as ReadText,supportedConnectionModes: null == supportedConnectionModes ? _self.supportedConnectionModes : supportedConnectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get inputCapabilities {

  return $TypedListRefCopyWith<$Res>(_self.inputCapabilities, (value) {
    return _then(_self.copyWith(inputCapabilities: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get reasoningEfforts {

  return $TypedListRefCopyWith<$Res>(_self.reasoningEfforts, (value) {
    return _then(_self.copyWith(reasoningEfforts: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseInstructions {

  return $ReadTextCopyWith<$Res>(_self.baseInstructions, (value) {
    return _then(_self.copyWith(baseInstructions: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get wireApi {

  return $ReadTextCopyWith<$Res>(_self.wireApi, (value) {
    return _then(_self.copyWith(wireApi: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get supportedConnectionModes {

  return $TypedListRefCopyWith<$Res>(_self.supportedConnectionModes, (value) {
    return _then(_self.copyWith(supportedConnectionModes: value));
  });
}/// Create a copy of CustomModelConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultConnectionMode {

  return $ReadTextCopyWith<$Res>(_self.defaultConnectionMode, (value) {
    return _then(_self.copyWith(defaultConnectionMode: value));
  });
}
}

/// @nodoc
mixin _$ModelConnectionRead {

 ReadText get modelId; ReadText get connectionMode;
/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelConnectionReadCopyWith<ModelConnectionRead> get copyWith => _$ModelConnectionReadCopyWithImpl<ModelConnectionRead>(this as ModelConnectionRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelConnectionRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelConnectionRead&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.connectionMode, _this.connectionMode) || other.connectionMode == _this.connectionMode));
}


@override
int get hashCode {
  final _this = this as ModelConnectionRead;
  return Object.hash(runtimeType,_this.modelId,_this.connectionMode);
}



}

/// @nodoc
abstract mixin class $ModelConnectionReadCopyWith<$Res>  {
  factory $ModelConnectionReadCopyWith(ModelConnectionRead value, $Res Function(ModelConnectionRead) _then) = _$ModelConnectionReadCopyWithImpl;
@useResult
$Res call({
 ReadText modelId, ReadText connectionMode
});


$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res> get connectionMode;

}
/// @nodoc
class _$ModelConnectionReadCopyWithImpl<$Res>
    implements $ModelConnectionReadCopyWith<$Res> {
  _$ModelConnectionReadCopyWithImpl(this._self, this._then);

  final ModelConnectionRead _self;
  final $Res Function(ModelConnectionRead) _then;

/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(ModelConnectionRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get connectionMode {

  return $ReadTextCopyWith<$Res>(_self.connectionMode, (value) {
    return _then(_self.copyWith(connectionMode: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelConnectionRead].
extension ModelConnectionReadPatterns on ModelConnectionRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelConnectionRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelConnectionRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelConnectionRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelConnectionRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelConnectionRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelConnectionRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText modelId,  ReadText connectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelConnectionRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText modelId,  ReadText connectionMode)  $default,) {final _that = this;
switch (_that) {
case _ModelConnectionRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText modelId,  ReadText connectionMode)?  $default,) {final _that = this;
switch (_that) {
case _ModelConnectionRead() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _ModelConnectionRead implements ModelConnectionRead {
  const _ModelConnectionRead({required this.modelId, required this.connectionMode});


@override final  ReadText modelId;
@override final  ReadText connectionMode;

/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelConnectionReadCopyWith<_ModelConnectionRead> get copyWith => __$ModelConnectionReadCopyWithImpl<_ModelConnectionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelConnectionRead&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.connectionMode, connectionMode) || other.connectionMode == connectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,connectionMode);
}



}

/// @nodoc
abstract mixin class _$ModelConnectionReadCopyWith<$Res> implements $ModelConnectionReadCopyWith<$Res> {
  factory _$ModelConnectionReadCopyWith(_ModelConnectionRead value, $Res Function(_ModelConnectionRead) _then) = __$ModelConnectionReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText modelId, ReadText connectionMode
});


@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res> get connectionMode;

}
/// @nodoc
class __$ModelConnectionReadCopyWithImpl<$Res>
    implements _$ModelConnectionReadCopyWith<$Res> {
  __$ModelConnectionReadCopyWithImpl(this._self, this._then);

  final _ModelConnectionRead _self;
  final $Res Function(_ModelConnectionRead) _then;

/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(_ModelConnectionRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelConnectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get connectionMode {

  return $ReadTextCopyWith<$Res>(_self.connectionMode, (value) {
    return _then(_self.copyWith(connectionMode: value));
  });
}
}

/// @nodoc
mixin _$ModelAutoCompactRead {

 ReadText get modelId; int? get overrideLimit;
/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelAutoCompactReadCopyWith<ModelAutoCompactRead> get copyWith => _$ModelAutoCompactReadCopyWithImpl<ModelAutoCompactRead>(this as ModelAutoCompactRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelAutoCompactRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelAutoCompactRead&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.overrideLimit, _this.overrideLimit) || other.overrideLimit == _this.overrideLimit));
}


@override
int get hashCode {
  final _this = this as ModelAutoCompactRead;
  return Object.hash(runtimeType,_this.modelId,_this.overrideLimit);
}



}

/// @nodoc
abstract mixin class $ModelAutoCompactReadCopyWith<$Res>  {
  factory $ModelAutoCompactReadCopyWith(ModelAutoCompactRead value, $Res Function(ModelAutoCompactRead) _then) = _$ModelAutoCompactReadCopyWithImpl;
@useResult
$Res call({
 ReadText modelId, int? overrideLimit
});


$ReadTextCopyWith<$Res> get modelId;

}
/// @nodoc
class _$ModelAutoCompactReadCopyWithImpl<$Res>
    implements $ModelAutoCompactReadCopyWith<$Res> {
  _$ModelAutoCompactReadCopyWithImpl(this._self, this._then);

  final ModelAutoCompactRead _self;
  final $Res Function(ModelAutoCompactRead) _then;

/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(ModelAutoCompactRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelAutoCompactRead].
extension ModelAutoCompactReadPatterns on ModelAutoCompactRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelAutoCompactRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelAutoCompactRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelAutoCompactRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelAutoCompactRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelAutoCompactRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelAutoCompactRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText modelId,  int? overrideLimit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelAutoCompactRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText modelId,  int? overrideLimit)  $default,) {final _that = this;
switch (_that) {
case _ModelAutoCompactRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText modelId,  int? overrideLimit)?  $default,) {final _that = this;
switch (_that) {
case _ModelAutoCompactRead() when $default != null:
return $default(_that.modelId,_that.overrideLimit);case _:
  return null;

}
}

}

/// @nodoc


class _ModelAutoCompactRead implements ModelAutoCompactRead {
  const _ModelAutoCompactRead({required this.modelId, required this.overrideLimit});


@override final  ReadText modelId;
@override final  int? overrideLimit;

/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelAutoCompactReadCopyWith<_ModelAutoCompactRead> get copyWith => __$ModelAutoCompactReadCopyWithImpl<_ModelAutoCompactRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelAutoCompactRead&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.overrideLimit, overrideLimit) || other.overrideLimit == overrideLimit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,overrideLimit);
}



}

/// @nodoc
abstract mixin class _$ModelAutoCompactReadCopyWith<$Res> implements $ModelAutoCompactReadCopyWith<$Res> {
  factory _$ModelAutoCompactReadCopyWith(_ModelAutoCompactRead value, $Res Function(_ModelAutoCompactRead) _then) = __$ModelAutoCompactReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText modelId, int? overrideLimit
});


@override $ReadTextCopyWith<$Res> get modelId;

}
/// @nodoc
class __$ModelAutoCompactReadCopyWithImpl<$Res>
    implements _$ModelAutoCompactReadCopyWith<$Res> {
  __$ModelAutoCompactReadCopyWithImpl(this._self, this._then);

  final _ModelAutoCompactRead _self;
  final $Res Function(_ModelAutoCompactRead) _then;

/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(_ModelAutoCompactRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of ModelAutoCompactRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}

/// @nodoc
mixin _$ModeModelRouteRead {

 ReadText get modeId; ReadText get accountId; ReadText get modelId; ReadText get effort;
/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeModelRouteReadCopyWith<ModeModelRouteRead> get copyWith => _$ModeModelRouteReadCopyWithImpl<ModeModelRouteRead>(this as ModeModelRouteRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeModelRouteRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeModelRouteRead&&(identical(other.modeId, _this.modeId) || other.modeId == _this.modeId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as ModeModelRouteRead;
  return Object.hash(runtimeType,_this.modeId,_this.accountId,_this.modelId,_this.effort);
}



}

/// @nodoc
abstract mixin class $ModeModelRouteReadCopyWith<$Res>  {
  factory $ModeModelRouteReadCopyWith(ModeModelRouteRead value, $Res Function(ModeModelRouteRead) _then) = _$ModeModelRouteReadCopyWithImpl;
@useResult
$Res call({
 ReadText modeId, ReadText accountId, ReadText modelId, ReadText effort
});


$ReadTextCopyWith<$Res> get modeId;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res> get effort;

}
/// @nodoc
class _$ModeModelRouteReadCopyWithImpl<$Res>
    implements $ModeModelRouteReadCopyWith<$Res> {
  _$ModeModelRouteReadCopyWithImpl(this._self, this._then);

  final ModeModelRouteRead _self;
  final $Res Function(ModeModelRouteRead) _then;

/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modeId = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(ModeModelRouteRead(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeId {

  return $ReadTextCopyWith<$Res>(_self.modeId, (value) {
    return _then(_self.copyWith(modeId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effort {

  return $ReadTextCopyWith<$Res>(_self.effort, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeModelRouteRead].
extension ModeModelRouteReadPatterns on ModeModelRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeModelRouteRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeModelRouteRead value)  $default,){
final _that = this;
switch (_that) {
case _ModeModelRouteRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeModelRouteRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModeModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText modeId,  ReadText accountId,  ReadText modelId,  ReadText effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText modeId,  ReadText accountId,  ReadText modelId,  ReadText effort)  $default,) {final _that = this;
switch (_that) {
case _ModeModelRouteRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText modeId,  ReadText accountId,  ReadText modelId,  ReadText effort)?  $default,) {final _that = this;
switch (_that) {
case _ModeModelRouteRead() when $default != null:
return $default(_that.modeId,_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _ModeModelRouteRead implements ModeModelRouteRead {
  const _ModeModelRouteRead({required this.modeId, required this.accountId, required this.modelId, required this.effort});


@override final  ReadText modeId;
@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText effort;

/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeModelRouteReadCopyWith<_ModeModelRouteRead> get copyWith => __$ModeModelRouteReadCopyWithImpl<_ModeModelRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeModelRouteRead&&(identical(other.modeId, modeId) || other.modeId == modeId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modeId,accountId,modelId,effort);
}



}

/// @nodoc
abstract mixin class _$ModeModelRouteReadCopyWith<$Res> implements $ModeModelRouteReadCopyWith<$Res> {
  factory _$ModeModelRouteReadCopyWith(_ModeModelRouteRead value, $Res Function(_ModeModelRouteRead) _then) = __$ModeModelRouteReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText modeId, ReadText accountId, ReadText modelId, ReadText effort
});


@override $ReadTextCopyWith<$Res> get modeId;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res> get effort;

}
/// @nodoc
class __$ModeModelRouteReadCopyWithImpl<$Res>
    implements _$ModeModelRouteReadCopyWith<$Res> {
  __$ModeModelRouteReadCopyWithImpl(this._self, this._then);

  final _ModeModelRouteRead _self;
  final $Res Function(_ModeModelRouteRead) _then;

/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modeId = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(_ModeModelRouteRead(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeId {

  return $ReadTextCopyWith<$Res>(_self.modeId, (value) {
    return _then(_self.copyWith(modeId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModeModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effort {

  return $ReadTextCopyWith<$Res>(_self.effort, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}

/// @nodoc
mixin _$RoleModelRouteRead {

 ReadText get key; ReadText get accountId; ReadText get modelId; ReadText get effort;
/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoleModelRouteReadCopyWith<RoleModelRouteRead> get copyWith => _$RoleModelRouteReadCopyWithImpl<RoleModelRouteRead>(this as RoleModelRouteRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RoleModelRouteRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoleModelRouteRead&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as RoleModelRouteRead;
  return Object.hash(runtimeType,_this.key,_this.accountId,_this.modelId,_this.effort);
}



}

/// @nodoc
abstract mixin class $RoleModelRouteReadCopyWith<$Res>  {
  factory $RoleModelRouteReadCopyWith(RoleModelRouteRead value, $Res Function(RoleModelRouteRead) _then) = _$RoleModelRouteReadCopyWithImpl;
@useResult
$Res call({
 ReadText key, ReadText accountId, ReadText modelId, ReadText effort
});


$ReadTextCopyWith<$Res> get key;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res> get effort;

}
/// @nodoc
class _$RoleModelRouteReadCopyWithImpl<$Res>
    implements $RoleModelRouteReadCopyWith<$Res> {
  _$RoleModelRouteReadCopyWithImpl(this._self, this._then);

  final RoleModelRouteRead _self;
  final $Res Function(RoleModelRouteRead) _then;

/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(RoleModelRouteRead(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get key {

  return $ReadTextCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effort {

  return $ReadTextCopyWith<$Res>(_self.effort, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}


/// Adds pattern-matching-related methods to [RoleModelRouteRead].
extension RoleModelRouteReadPatterns on RoleModelRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoleModelRouteRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoleModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoleModelRouteRead value)  $default,){
final _that = this;
switch (_that) {
case _RoleModelRouteRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoleModelRouteRead value)?  $default,){
final _that = this;
switch (_that) {
case _RoleModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText key,  ReadText accountId,  ReadText modelId,  ReadText effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoleModelRouteRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText key,  ReadText accountId,  ReadText modelId,  ReadText effort)  $default,) {final _that = this;
switch (_that) {
case _RoleModelRouteRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText key,  ReadText accountId,  ReadText modelId,  ReadText effort)?  $default,) {final _that = this;
switch (_that) {
case _RoleModelRouteRead() when $default != null:
return $default(_that.key,_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _RoleModelRouteRead implements RoleModelRouteRead {
  const _RoleModelRouteRead({required this.key, required this.accountId, required this.modelId, required this.effort});


@override final  ReadText key;
@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText effort;

/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoleModelRouteReadCopyWith<_RoleModelRouteRead> get copyWith => __$RoleModelRouteReadCopyWithImpl<_RoleModelRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoleModelRouteRead&&(identical(other.key, key) || other.key == key)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,accountId,modelId,effort);
}



}

/// @nodoc
abstract mixin class _$RoleModelRouteReadCopyWith<$Res> implements $RoleModelRouteReadCopyWith<$Res> {
  factory _$RoleModelRouteReadCopyWith(_RoleModelRouteRead value, $Res Function(_RoleModelRouteRead) _then) = __$RoleModelRouteReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText key, ReadText accountId, ReadText modelId, ReadText effort
});


@override $ReadTextCopyWith<$Res> get key;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res> get effort;

}
/// @nodoc
class __$RoleModelRouteReadCopyWithImpl<$Res>
    implements _$RoleModelRouteReadCopyWith<$Res> {
  __$RoleModelRouteReadCopyWithImpl(this._self, this._then);

  final _RoleModelRouteRead _self;
  final $Res Function(_RoleModelRouteRead) _then;

/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? accountId = null,Object? modelId = null,Object? effort = null,}) {
  return _then(_RoleModelRouteRead(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: null == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get key {

  return $ReadTextCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of RoleModelRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effort {

  return $ReadTextCopyWith<$Res>(_self.effort, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}

/// @nodoc
mixin _$InstructionsSettingsRead {

 ReadText get baseOverride; ReadText get developer; ReadText get user; int get projectDocMaxBytes; TypedListRef get projectDocFallbackFilenames;
/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstructionsSettingsReadCopyWith<InstructionsSettingsRead> get copyWith => _$InstructionsSettingsReadCopyWithImpl<InstructionsSettingsRead>(this as InstructionsSettingsRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InstructionsSettingsRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstructionsSettingsRead&&(identical(other.baseOverride, _this.baseOverride) || other.baseOverride == _this.baseOverride)&&(identical(other.developer, _this.developer) || other.developer == _this.developer)&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.projectDocMaxBytes, _this.projectDocMaxBytes) || other.projectDocMaxBytes == _this.projectDocMaxBytes)&&(identical(other.projectDocFallbackFilenames, _this.projectDocFallbackFilenames) || other.projectDocFallbackFilenames == _this.projectDocFallbackFilenames));
}


@override
int get hashCode {
  final _this = this as InstructionsSettingsRead;
  return Object.hash(runtimeType,_this.baseOverride,_this.developer,_this.user,_this.projectDocMaxBytes,_this.projectDocFallbackFilenames);
}



}

/// @nodoc
abstract mixin class $InstructionsSettingsReadCopyWith<$Res>  {
  factory $InstructionsSettingsReadCopyWith(InstructionsSettingsRead value, $Res Function(InstructionsSettingsRead) _then) = _$InstructionsSettingsReadCopyWithImpl;
@useResult
$Res call({
 ReadText baseOverride, ReadText developer, ReadText user, int projectDocMaxBytes, TypedListRef projectDocFallbackFilenames
});


$ReadTextCopyWith<$Res> get baseOverride;$ReadTextCopyWith<$Res> get developer;$ReadTextCopyWith<$Res> get user;$TypedListRefCopyWith<$Res> get projectDocFallbackFilenames;

}
/// @nodoc
class _$InstructionsSettingsReadCopyWithImpl<$Res>
    implements $InstructionsSettingsReadCopyWith<$Res> {
  _$InstructionsSettingsReadCopyWithImpl(this._self, this._then);

  final InstructionsSettingsRead _self;
  final $Res Function(InstructionsSettingsRead) _then;

/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseOverride = null,Object? developer = null,Object? user = null,Object? projectDocMaxBytes = null,Object? projectDocFallbackFilenames = null,}) {
  return _then(InstructionsSettingsRead(
baseOverride: null == baseOverride ? _self.baseOverride : baseOverride // ignore: cast_nullable_to_non_nullable
as ReadText,developer: null == developer ? _self.developer : developer // ignore: cast_nullable_to_non_nullable
as ReadText,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as ReadText,projectDocMaxBytes: null == projectDocMaxBytes ? _self.projectDocMaxBytes : projectDocMaxBytes // ignore: cast_nullable_to_non_nullable
as int,projectDocFallbackFilenames: null == projectDocFallbackFilenames ? _self.projectDocFallbackFilenames : projectDocFallbackFilenames // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseOverride {

  return $ReadTextCopyWith<$Res>(_self.baseOverride, (value) {
    return _then(_self.copyWith(baseOverride: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get developer {

  return $ReadTextCopyWith<$Res>(_self.developer, (value) {
    return _then(_self.copyWith(developer: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get user {

  return $ReadTextCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get projectDocFallbackFilenames {

  return $TypedListRefCopyWith<$Res>(_self.projectDocFallbackFilenames, (value) {
    return _then(_self.copyWith(projectDocFallbackFilenames: value));
  });
}
}


/// Adds pattern-matching-related methods to [InstructionsSettingsRead].
extension InstructionsSettingsReadPatterns on InstructionsSettingsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InstructionsSettingsRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InstructionsSettingsRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InstructionsSettingsRead value)  $default,){
final _that = this;
switch (_that) {
case _InstructionsSettingsRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InstructionsSettingsRead value)?  $default,){
final _that = this;
switch (_that) {
case _InstructionsSettingsRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText baseOverride,  ReadText developer,  ReadText user,  int projectDocMaxBytes,  TypedListRef projectDocFallbackFilenames)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InstructionsSettingsRead() when $default != null:
return $default(_that.baseOverride,_that.developer,_that.user,_that.projectDocMaxBytes,_that.projectDocFallbackFilenames);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText baseOverride,  ReadText developer,  ReadText user,  int projectDocMaxBytes,  TypedListRef projectDocFallbackFilenames)  $default,) {final _that = this;
switch (_that) {
case _InstructionsSettingsRead():
return $default(_that.baseOverride,_that.developer,_that.user,_that.projectDocMaxBytes,_that.projectDocFallbackFilenames);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText baseOverride,  ReadText developer,  ReadText user,  int projectDocMaxBytes,  TypedListRef projectDocFallbackFilenames)?  $default,) {final _that = this;
switch (_that) {
case _InstructionsSettingsRead() when $default != null:
return $default(_that.baseOverride,_that.developer,_that.user,_that.projectDocMaxBytes,_that.projectDocFallbackFilenames);case _:
  return null;

}
}

}

/// @nodoc


class _InstructionsSettingsRead implements InstructionsSettingsRead {
  const _InstructionsSettingsRead({required this.baseOverride, required this.developer, required this.user, required this.projectDocMaxBytes, required this.projectDocFallbackFilenames});


@override final  ReadText baseOverride;
@override final  ReadText developer;
@override final  ReadText user;
@override final  int projectDocMaxBytes;
@override final  TypedListRef projectDocFallbackFilenames;

/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstructionsSettingsReadCopyWith<_InstructionsSettingsRead> get copyWith => __$InstructionsSettingsReadCopyWithImpl<_InstructionsSettingsRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstructionsSettingsRead&&(identical(other.baseOverride, baseOverride) || other.baseOverride == baseOverride)&&(identical(other.developer, developer) || other.developer == developer)&&(identical(other.user, user) || other.user == user)&&(identical(other.projectDocMaxBytes, projectDocMaxBytes) || other.projectDocMaxBytes == projectDocMaxBytes)&&(identical(other.projectDocFallbackFilenames, projectDocFallbackFilenames) || other.projectDocFallbackFilenames == projectDocFallbackFilenames));
}


@override
int get hashCode {
    return Object.hash(runtimeType,baseOverride,developer,user,projectDocMaxBytes,projectDocFallbackFilenames);
}



}

/// @nodoc
abstract mixin class _$InstructionsSettingsReadCopyWith<$Res> implements $InstructionsSettingsReadCopyWith<$Res> {
  factory _$InstructionsSettingsReadCopyWith(_InstructionsSettingsRead value, $Res Function(_InstructionsSettingsRead) _then) = __$InstructionsSettingsReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText baseOverride, ReadText developer, ReadText user, int projectDocMaxBytes, TypedListRef projectDocFallbackFilenames
});


@override $ReadTextCopyWith<$Res> get baseOverride;@override $ReadTextCopyWith<$Res> get developer;@override $ReadTextCopyWith<$Res> get user;@override $TypedListRefCopyWith<$Res> get projectDocFallbackFilenames;

}
/// @nodoc
class __$InstructionsSettingsReadCopyWithImpl<$Res>
    implements _$InstructionsSettingsReadCopyWith<$Res> {
  __$InstructionsSettingsReadCopyWithImpl(this._self, this._then);

  final _InstructionsSettingsRead _self;
  final $Res Function(_InstructionsSettingsRead) _then;

/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? baseOverride = null,Object? developer = null,Object? user = null,Object? projectDocMaxBytes = null,Object? projectDocFallbackFilenames = null,}) {
  return _then(_InstructionsSettingsRead(
baseOverride: null == baseOverride ? _self.baseOverride : baseOverride // ignore: cast_nullable_to_non_nullable
as ReadText,developer: null == developer ? _self.developer : developer // ignore: cast_nullable_to_non_nullable
as ReadText,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as ReadText,projectDocMaxBytes: null == projectDocMaxBytes ? _self.projectDocMaxBytes : projectDocMaxBytes // ignore: cast_nullable_to_non_nullable
as int,projectDocFallbackFilenames: null == projectDocFallbackFilenames ? _self.projectDocFallbackFilenames : projectDocFallbackFilenames // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseOverride {

  return $ReadTextCopyWith<$Res>(_self.baseOverride, (value) {
    return _then(_self.copyWith(baseOverride: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get developer {

  return $ReadTextCopyWith<$Res>(_self.developer, (value) {
    return _then(_self.copyWith(developer: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get user {

  return $ReadTextCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}/// Create a copy of InstructionsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get projectDocFallbackFilenames {

  return $TypedListRefCopyWith<$Res>(_self.projectDocFallbackFilenames, (value) {
    return _then(_self.copyWith(projectDocFallbackFilenames: value));
  });
}
}

/// @nodoc
mixin _$SkillsSettingsRead {

 bool get enabled; bool get autoLearn; bool get systemEnabled; ReadText get projectDir; ReadText get userDir; TypedListRef get externalDirs; TypedListRef get disabled; int get autoLearnMinToolCalls;
/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsSettingsReadCopyWith<SkillsSettingsRead> get copyWith => _$SkillsSettingsReadCopyWithImpl<SkillsSettingsRead>(this as SkillsSettingsRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsSettingsRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsSettingsRead&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.autoLearn, _this.autoLearn) || other.autoLearn == _this.autoLearn)&&(identical(other.systemEnabled, _this.systemEnabled) || other.systemEnabled == _this.systemEnabled)&&(identical(other.projectDir, _this.projectDir) || other.projectDir == _this.projectDir)&&(identical(other.userDir, _this.userDir) || other.userDir == _this.userDir)&&(identical(other.externalDirs, _this.externalDirs) || other.externalDirs == _this.externalDirs)&&(identical(other.disabled, _this.disabled) || other.disabled == _this.disabled)&&(identical(other.autoLearnMinToolCalls, _this.autoLearnMinToolCalls) || other.autoLearnMinToolCalls == _this.autoLearnMinToolCalls));
}


@override
int get hashCode {
  final _this = this as SkillsSettingsRead;
  return Object.hash(runtimeType,_this.enabled,_this.autoLearn,_this.systemEnabled,_this.projectDir,_this.userDir,_this.externalDirs,_this.disabled,_this.autoLearnMinToolCalls);
}



}

/// @nodoc
abstract mixin class $SkillsSettingsReadCopyWith<$Res>  {
  factory $SkillsSettingsReadCopyWith(SkillsSettingsRead value, $Res Function(SkillsSettingsRead) _then) = _$SkillsSettingsReadCopyWithImpl;
@useResult
$Res call({
 bool enabled, bool autoLearn, bool systemEnabled, ReadText projectDir, ReadText userDir, TypedListRef externalDirs, TypedListRef disabled, int autoLearnMinToolCalls
});


$ReadTextCopyWith<$Res> get projectDir;$ReadTextCopyWith<$Res> get userDir;$TypedListRefCopyWith<$Res> get externalDirs;$TypedListRefCopyWith<$Res> get disabled;

}
/// @nodoc
class _$SkillsSettingsReadCopyWithImpl<$Res>
    implements $SkillsSettingsReadCopyWith<$Res> {
  _$SkillsSettingsReadCopyWithImpl(this._self, this._then);

  final SkillsSettingsRead _self;
  final $Res Function(SkillsSettingsRead) _then;

/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? autoLearn = null,Object? systemEnabled = null,Object? projectDir = null,Object? userDir = null,Object? externalDirs = null,Object? disabled = null,Object? autoLearnMinToolCalls = null,}) {
  return _then(SkillsSettingsRead(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,autoLearn: null == autoLearn ? _self.autoLearn : autoLearn // ignore: cast_nullable_to_non_nullable
as bool,systemEnabled: null == systemEnabled ? _self.systemEnabled : systemEnabled // ignore: cast_nullable_to_non_nullable
as bool,projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as ReadText,userDir: null == userDir ? _self.userDir : userDir // ignore: cast_nullable_to_non_nullable
as ReadText,externalDirs: null == externalDirs ? _self.externalDirs : externalDirs // ignore: cast_nullable_to_non_nullable
as TypedListRef,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as TypedListRef,autoLearnMinToolCalls: null == autoLearnMinToolCalls ? _self.autoLearnMinToolCalls : autoLearnMinToolCalls // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectDir {

  return $ReadTextCopyWith<$Res>(_self.projectDir, (value) {
    return _then(_self.copyWith(projectDir: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get userDir {

  return $ReadTextCopyWith<$Res>(_self.userDir, (value) {
    return _then(_self.copyWith(userDir: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get externalDirs {

  return $TypedListRefCopyWith<$Res>(_self.externalDirs, (value) {
    return _then(_self.copyWith(externalDirs: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get disabled {

  return $TypedListRefCopyWith<$Res>(_self.disabled, (value) {
    return _then(_self.copyWith(disabled: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsSettingsRead].
extension SkillsSettingsReadPatterns on SkillsSettingsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsSettingsRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsSettingsRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsSettingsRead value)  $default,){
final _that = this;
switch (_that) {
case _SkillsSettingsRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsSettingsRead value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsSettingsRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled,  bool autoLearn,  bool systemEnabled,  ReadText projectDir,  ReadText userDir,  TypedListRef externalDirs,  TypedListRef disabled,  int autoLearnMinToolCalls)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsSettingsRead() when $default != null:
return $default(_that.enabled,_that.autoLearn,_that.systemEnabled,_that.projectDir,_that.userDir,_that.externalDirs,_that.disabled,_that.autoLearnMinToolCalls);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled,  bool autoLearn,  bool systemEnabled,  ReadText projectDir,  ReadText userDir,  TypedListRef externalDirs,  TypedListRef disabled,  int autoLearnMinToolCalls)  $default,) {final _that = this;
switch (_that) {
case _SkillsSettingsRead():
return $default(_that.enabled,_that.autoLearn,_that.systemEnabled,_that.projectDir,_that.userDir,_that.externalDirs,_that.disabled,_that.autoLearnMinToolCalls);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled,  bool autoLearn,  bool systemEnabled,  ReadText projectDir,  ReadText userDir,  TypedListRef externalDirs,  TypedListRef disabled,  int autoLearnMinToolCalls)?  $default,) {final _that = this;
switch (_that) {
case _SkillsSettingsRead() when $default != null:
return $default(_that.enabled,_that.autoLearn,_that.systemEnabled,_that.projectDir,_that.userDir,_that.externalDirs,_that.disabled,_that.autoLearnMinToolCalls);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsSettingsRead implements SkillsSettingsRead {
  const _SkillsSettingsRead({required this.enabled, required this.autoLearn, required this.systemEnabled, required this.projectDir, required this.userDir, required this.externalDirs, required this.disabled, required this.autoLearnMinToolCalls});


@override final  bool enabled;
@override final  bool autoLearn;
@override final  bool systemEnabled;
@override final  ReadText projectDir;
@override final  ReadText userDir;
@override final  TypedListRef externalDirs;
@override final  TypedListRef disabled;
@override final  int autoLearnMinToolCalls;

/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsSettingsReadCopyWith<_SkillsSettingsRead> get copyWith => __$SkillsSettingsReadCopyWithImpl<_SkillsSettingsRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsSettingsRead&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.autoLearn, autoLearn) || other.autoLearn == autoLearn)&&(identical(other.systemEnabled, systemEnabled) || other.systemEnabled == systemEnabled)&&(identical(other.projectDir, projectDir) || other.projectDir == projectDir)&&(identical(other.userDir, userDir) || other.userDir == userDir)&&(identical(other.externalDirs, externalDirs) || other.externalDirs == externalDirs)&&(identical(other.disabled, disabled) || other.disabled == disabled)&&(identical(other.autoLearnMinToolCalls, autoLearnMinToolCalls) || other.autoLearnMinToolCalls == autoLearnMinToolCalls));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled,autoLearn,systemEnabled,projectDir,userDir,externalDirs,disabled,autoLearnMinToolCalls);
}



}

/// @nodoc
abstract mixin class _$SkillsSettingsReadCopyWith<$Res> implements $SkillsSettingsReadCopyWith<$Res> {
  factory _$SkillsSettingsReadCopyWith(_SkillsSettingsRead value, $Res Function(_SkillsSettingsRead) _then) = __$SkillsSettingsReadCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, bool autoLearn, bool systemEnabled, ReadText projectDir, ReadText userDir, TypedListRef externalDirs, TypedListRef disabled, int autoLearnMinToolCalls
});


@override $ReadTextCopyWith<$Res> get projectDir;@override $ReadTextCopyWith<$Res> get userDir;@override $TypedListRefCopyWith<$Res> get externalDirs;@override $TypedListRefCopyWith<$Res> get disabled;

}
/// @nodoc
class __$SkillsSettingsReadCopyWithImpl<$Res>
    implements _$SkillsSettingsReadCopyWith<$Res> {
  __$SkillsSettingsReadCopyWithImpl(this._self, this._then);

  final _SkillsSettingsRead _self;
  final $Res Function(_SkillsSettingsRead) _then;

/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? autoLearn = null,Object? systemEnabled = null,Object? projectDir = null,Object? userDir = null,Object? externalDirs = null,Object? disabled = null,Object? autoLearnMinToolCalls = null,}) {
  return _then(_SkillsSettingsRead(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,autoLearn: null == autoLearn ? _self.autoLearn : autoLearn // ignore: cast_nullable_to_non_nullable
as bool,systemEnabled: null == systemEnabled ? _self.systemEnabled : systemEnabled // ignore: cast_nullable_to_non_nullable
as bool,projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as ReadText,userDir: null == userDir ? _self.userDir : userDir // ignore: cast_nullable_to_non_nullable
as ReadText,externalDirs: null == externalDirs ? _self.externalDirs : externalDirs // ignore: cast_nullable_to_non_nullable
as TypedListRef,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as TypedListRef,autoLearnMinToolCalls: null == autoLearnMinToolCalls ? _self.autoLearnMinToolCalls : autoLearnMinToolCalls // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectDir {

  return $ReadTextCopyWith<$Res>(_self.projectDir, (value) {
    return _then(_self.copyWith(projectDir: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get userDir {

  return $ReadTextCopyWith<$Res>(_self.userDir, (value) {
    return _then(_self.copyWith(userDir: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get externalDirs {

  return $TypedListRefCopyWith<$Res>(_self.externalDirs, (value) {
    return _then(_self.copyWith(externalDirs: value));
  });
}/// Create a copy of SkillsSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get disabled {

  return $TypedListRefCopyWith<$Res>(_self.disabled, (value) {
    return _then(_self.copyWith(disabled: value));
  });
}
}

/// @nodoc
mixin _$McpConfigurationRead {

 ReadText get id; ReadText get transport; ReadText get endpoint; McpConfigurationState get configuration; ReadText get sourceKind; ReadText get mutationPolicy;
/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpConfigurationReadCopyWith<McpConfigurationRead> get copyWith => _$McpConfigurationReadCopyWithImpl<McpConfigurationRead>(this as McpConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpConfigurationRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.sourceKind, _this.sourceKind) || other.sourceKind == _this.sourceKind)&&(identical(other.mutationPolicy, _this.mutationPolicy) || other.mutationPolicy == _this.mutationPolicy));
}


@override
int get hashCode {
  final _this = this as McpConfigurationRead;
  return Object.hash(runtimeType,_this.id,_this.transport,_this.endpoint,_this.configuration,_this.sourceKind,_this.mutationPolicy);
}



}

/// @nodoc
abstract mixin class $McpConfigurationReadCopyWith<$Res>  {
  factory $McpConfigurationReadCopyWith(McpConfigurationRead value, $Res Function(McpConfigurationRead) _then) = _$McpConfigurationReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText transport, ReadText endpoint, McpConfigurationState configuration, ReadText sourceKind, ReadText mutationPolicy
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get transport;$ReadTextCopyWith<$Res> get endpoint;$ReadTextCopyWith<$Res> get sourceKind;$ReadTextCopyWith<$Res> get mutationPolicy;

}
/// @nodoc
class _$McpConfigurationReadCopyWithImpl<$Res>
    implements $McpConfigurationReadCopyWith<$Res> {
  _$McpConfigurationReadCopyWithImpl(this._self, this._then);

  final McpConfigurationRead _self;
  final $Res Function(McpConfigurationRead) _then;

/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? configuration = null,Object? sourceKind = null,Object? mutationPolicy = null,}) {
  return _then(McpConfigurationRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ReadText,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as ReadText,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as McpConfigurationState,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as ReadText,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get transport {

  return $ReadTextCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get endpoint {

  return $ReadTextCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sourceKind {

  return $ReadTextCopyWith<$Res>(_self.sourceKind, (value) {
    return _then(_self.copyWith(sourceKind: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mutationPolicy {

  return $ReadTextCopyWith<$Res>(_self.mutationPolicy, (value) {
    return _then(_self.copyWith(mutationPolicy: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpConfigurationRead].
extension McpConfigurationReadPatterns on McpConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _McpConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _McpConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText transport,  ReadText endpoint,  McpConfigurationState configuration,  ReadText sourceKind,  ReadText mutationPolicy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText transport,  ReadText endpoint,  McpConfigurationState configuration,  ReadText sourceKind,  ReadText mutationPolicy)  $default,) {final _that = this;
switch (_that) {
case _McpConfigurationRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText transport,  ReadText endpoint,  McpConfigurationState configuration,  ReadText sourceKind,  ReadText mutationPolicy)?  $default,) {final _that = this;
switch (_that) {
case _McpConfigurationRead() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.configuration,_that.sourceKind,_that.mutationPolicy);case _:
  return null;

}
}

}

/// @nodoc


class _McpConfigurationRead implements McpConfigurationRead {
  const _McpConfigurationRead({required this.id, required this.transport, required this.endpoint, required this.configuration, required this.sourceKind, required this.mutationPolicy});


@override final  ReadText id;
@override final  ReadText transport;
@override final  ReadText endpoint;
@override final  McpConfigurationState configuration;
@override final  ReadText sourceKind;
@override final  ReadText mutationPolicy;

/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpConfigurationReadCopyWith<_McpConfigurationRead> get copyWith => __$McpConfigurationReadCopyWithImpl<_McpConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpConfigurationRead&&(identical(other.id, id) || other.id == id)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.sourceKind, sourceKind) || other.sourceKind == sourceKind)&&(identical(other.mutationPolicy, mutationPolicy) || other.mutationPolicy == mutationPolicy));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,transport,endpoint,configuration,sourceKind,mutationPolicy);
}



}

/// @nodoc
abstract mixin class _$McpConfigurationReadCopyWith<$Res> implements $McpConfigurationReadCopyWith<$Res> {
  factory _$McpConfigurationReadCopyWith(_McpConfigurationRead value, $Res Function(_McpConfigurationRead) _then) = __$McpConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText transport, ReadText endpoint, McpConfigurationState configuration, ReadText sourceKind, ReadText mutationPolicy
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get transport;@override $ReadTextCopyWith<$Res> get endpoint;@override $ReadTextCopyWith<$Res> get sourceKind;@override $ReadTextCopyWith<$Res> get mutationPolicy;

}
/// @nodoc
class __$McpConfigurationReadCopyWithImpl<$Res>
    implements _$McpConfigurationReadCopyWith<$Res> {
  __$McpConfigurationReadCopyWithImpl(this._self, this._then);

  final _McpConfigurationRead _self;
  final $Res Function(_McpConfigurationRead) _then;

/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? configuration = null,Object? sourceKind = null,Object? mutationPolicy = null,}) {
  return _then(_McpConfigurationRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ReadText,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as ReadText,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as McpConfigurationState,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as ReadText,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get transport {

  return $ReadTextCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get endpoint {

  return $ReadTextCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sourceKind {

  return $ReadTextCopyWith<$Res>(_self.sourceKind, (value) {
    return _then(_self.copyWith(sourceKind: value));
  });
}/// Create a copy of McpConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mutationPolicy {

  return $ReadTextCopyWith<$Res>(_self.mutationPolicy, (value) {
    return _then(_self.copyWith(mutationPolicy: value));
  });
}
}

/// @nodoc
mixin _$GeneralSettingsRead {

 bool get followActiveTurn; bool get compactTimeline; int? get sidebarWidth; TypedListRef get pinnedThreadIds; TypedListRef get pinnedProjectIds;
/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GeneralSettingsReadCopyWith<GeneralSettingsRead> get copyWith => _$GeneralSettingsReadCopyWithImpl<GeneralSettingsRead>(this as GeneralSettingsRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GeneralSettingsRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GeneralSettingsRead&&(identical(other.followActiveTurn, _this.followActiveTurn) || other.followActiveTurn == _this.followActiveTurn)&&(identical(other.compactTimeline, _this.compactTimeline) || other.compactTimeline == _this.compactTimeline)&&(identical(other.sidebarWidth, _this.sidebarWidth) || other.sidebarWidth == _this.sidebarWidth)&&(identical(other.pinnedThreadIds, _this.pinnedThreadIds) || other.pinnedThreadIds == _this.pinnedThreadIds)&&(identical(other.pinnedProjectIds, _this.pinnedProjectIds) || other.pinnedProjectIds == _this.pinnedProjectIds));
}


@override
int get hashCode {
  final _this = this as GeneralSettingsRead;
  return Object.hash(runtimeType,_this.followActiveTurn,_this.compactTimeline,_this.sidebarWidth,_this.pinnedThreadIds,_this.pinnedProjectIds);
}

@override
String toString() {
  final _this = this as GeneralSettingsRead;
  return 'GeneralSettingsRead(followActiveTurn: ${_this.followActiveTurn}, compactTimeline: ${_this.compactTimeline}, sidebarWidth: ${_this.sidebarWidth}, pinnedThreadIds: ${_this.pinnedThreadIds}, pinnedProjectIds: ${_this.pinnedProjectIds})';
}


}

/// @nodoc
abstract mixin class $GeneralSettingsReadCopyWith<$Res>  {
  factory $GeneralSettingsReadCopyWith(GeneralSettingsRead value, $Res Function(GeneralSettingsRead) _then) = _$GeneralSettingsReadCopyWithImpl;
@useResult
$Res call({
 bool followActiveTurn, bool compactTimeline, int? sidebarWidth, TypedListRef pinnedThreadIds, TypedListRef pinnedProjectIds
});


$TypedListRefCopyWith<$Res> get pinnedThreadIds;$TypedListRefCopyWith<$Res> get pinnedProjectIds;

}
/// @nodoc
class _$GeneralSettingsReadCopyWithImpl<$Res>
    implements $GeneralSettingsReadCopyWith<$Res> {
  _$GeneralSettingsReadCopyWithImpl(this._self, this._then);

  final GeneralSettingsRead _self;
  final $Res Function(GeneralSettingsRead) _then;

/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? followActiveTurn = null,Object? compactTimeline = null,Object? sidebarWidth = freezed,Object? pinnedThreadIds = null,Object? pinnedProjectIds = null,}) {
  return _then(GeneralSettingsRead(
followActiveTurn: null == followActiveTurn ? _self.followActiveTurn : followActiveTurn // ignore: cast_nullable_to_non_nullable
as bool,compactTimeline: null == compactTimeline ? _self.compactTimeline : compactTimeline // ignore: cast_nullable_to_non_nullable
as bool,sidebarWidth: freezed == sidebarWidth ? _self.sidebarWidth : sidebarWidth // ignore: cast_nullable_to_non_nullable
as int?,pinnedThreadIds: null == pinnedThreadIds ? _self.pinnedThreadIds : pinnedThreadIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,pinnedProjectIds: null == pinnedProjectIds ? _self.pinnedProjectIds : pinnedProjectIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get pinnedThreadIds {

  return $TypedListRefCopyWith<$Res>(_self.pinnedThreadIds, (value) {
    return _then(_self.copyWith(pinnedThreadIds: value));
  });
}/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get pinnedProjectIds {

  return $TypedListRefCopyWith<$Res>(_self.pinnedProjectIds, (value) {
    return _then(_self.copyWith(pinnedProjectIds: value));
  });
}
}


/// Adds pattern-matching-related methods to [GeneralSettingsRead].
extension GeneralSettingsReadPatterns on GeneralSettingsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GeneralSettingsRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GeneralSettingsRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GeneralSettingsRead value)  $default,){
final _that = this;
switch (_that) {
case _GeneralSettingsRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GeneralSettingsRead value)?  $default,){
final _that = this;
switch (_that) {
case _GeneralSettingsRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool followActiveTurn,  bool compactTimeline,  int? sidebarWidth,  TypedListRef pinnedThreadIds,  TypedListRef pinnedProjectIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GeneralSettingsRead() when $default != null:
return $default(_that.followActiveTurn,_that.compactTimeline,_that.sidebarWidth,_that.pinnedThreadIds,_that.pinnedProjectIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool followActiveTurn,  bool compactTimeline,  int? sidebarWidth,  TypedListRef pinnedThreadIds,  TypedListRef pinnedProjectIds)  $default,) {final _that = this;
switch (_that) {
case _GeneralSettingsRead():
return $default(_that.followActiveTurn,_that.compactTimeline,_that.sidebarWidth,_that.pinnedThreadIds,_that.pinnedProjectIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool followActiveTurn,  bool compactTimeline,  int? sidebarWidth,  TypedListRef pinnedThreadIds,  TypedListRef pinnedProjectIds)?  $default,) {final _that = this;
switch (_that) {
case _GeneralSettingsRead() when $default != null:
return $default(_that.followActiveTurn,_that.compactTimeline,_that.sidebarWidth,_that.pinnedThreadIds,_that.pinnedProjectIds);case _:
  return null;

}
}

}

/// @nodoc


class _GeneralSettingsRead implements GeneralSettingsRead {
  const _GeneralSettingsRead({required this.followActiveTurn, required this.compactTimeline, required this.sidebarWidth, required this.pinnedThreadIds, required this.pinnedProjectIds});


@override final  bool followActiveTurn;
@override final  bool compactTimeline;
@override final  int? sidebarWidth;
@override final  TypedListRef pinnedThreadIds;
@override final  TypedListRef pinnedProjectIds;

/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GeneralSettingsReadCopyWith<_GeneralSettingsRead> get copyWith => __$GeneralSettingsReadCopyWithImpl<_GeneralSettingsRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GeneralSettingsRead&&(identical(other.followActiveTurn, followActiveTurn) || other.followActiveTurn == followActiveTurn)&&(identical(other.compactTimeline, compactTimeline) || other.compactTimeline == compactTimeline)&&(identical(other.sidebarWidth, sidebarWidth) || other.sidebarWidth == sidebarWidth)&&(identical(other.pinnedThreadIds, pinnedThreadIds) || other.pinnedThreadIds == pinnedThreadIds)&&(identical(other.pinnedProjectIds, pinnedProjectIds) || other.pinnedProjectIds == pinnedProjectIds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,followActiveTurn,compactTimeline,sidebarWidth,pinnedThreadIds,pinnedProjectIds);
}

@override
String toString() {
    return 'GeneralSettingsRead(followActiveTurn: $followActiveTurn, compactTimeline: $compactTimeline, sidebarWidth: $sidebarWidth, pinnedThreadIds: $pinnedThreadIds, pinnedProjectIds: $pinnedProjectIds)';
}


}

/// @nodoc
abstract mixin class _$GeneralSettingsReadCopyWith<$Res> implements $GeneralSettingsReadCopyWith<$Res> {
  factory _$GeneralSettingsReadCopyWith(_GeneralSettingsRead value, $Res Function(_GeneralSettingsRead) _then) = __$GeneralSettingsReadCopyWithImpl;
@override @useResult
$Res call({
 bool followActiveTurn, bool compactTimeline, int? sidebarWidth, TypedListRef pinnedThreadIds, TypedListRef pinnedProjectIds
});


@override $TypedListRefCopyWith<$Res> get pinnedThreadIds;@override $TypedListRefCopyWith<$Res> get pinnedProjectIds;

}
/// @nodoc
class __$GeneralSettingsReadCopyWithImpl<$Res>
    implements _$GeneralSettingsReadCopyWith<$Res> {
  __$GeneralSettingsReadCopyWithImpl(this._self, this._then);

  final _GeneralSettingsRead _self;
  final $Res Function(_GeneralSettingsRead) _then;

/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? followActiveTurn = null,Object? compactTimeline = null,Object? sidebarWidth = freezed,Object? pinnedThreadIds = null,Object? pinnedProjectIds = null,}) {
  return _then(_GeneralSettingsRead(
followActiveTurn: null == followActiveTurn ? _self.followActiveTurn : followActiveTurn // ignore: cast_nullable_to_non_nullable
as bool,compactTimeline: null == compactTimeline ? _self.compactTimeline : compactTimeline // ignore: cast_nullable_to_non_nullable
as bool,sidebarWidth: freezed == sidebarWidth ? _self.sidebarWidth : sidebarWidth // ignore: cast_nullable_to_non_nullable
as int?,pinnedThreadIds: null == pinnedThreadIds ? _self.pinnedThreadIds : pinnedThreadIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,pinnedProjectIds: null == pinnedProjectIds ? _self.pinnedProjectIds : pinnedProjectIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get pinnedThreadIds {

  return $TypedListRefCopyWith<$Res>(_self.pinnedThreadIds, (value) {
    return _then(_self.copyWith(pinnedThreadIds: value));
  });
}/// Create a copy of GeneralSettingsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get pinnedProjectIds {

  return $TypedListRefCopyWith<$Res>(_self.pinnedProjectIds, (value) {
    return _then(_self.copyWith(pinnedProjectIds: value));
  });
}
}

/// @nodoc
mixin _$WebSearchConfigurationRead {

 ReadText get configuredMode; ReadText? get contextSize; TypedListRef get allowedDomains; ReadText? get country; ReadText? get region; ReadText? get city; ReadText? get timezone;
/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSearchConfigurationReadCopyWith<WebSearchConfigurationRead> get copyWith => _$WebSearchConfigurationReadCopyWithImpl<WebSearchConfigurationRead>(this as WebSearchConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WebSearchConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSearchConfigurationRead&&(identical(other.configuredMode, _this.configuredMode) || other.configuredMode == _this.configuredMode)&&(identical(other.contextSize, _this.contextSize) || other.contextSize == _this.contextSize)&&(identical(other.allowedDomains, _this.allowedDomains) || other.allowedDomains == _this.allowedDomains)&&(identical(other.country, _this.country) || other.country == _this.country)&&(identical(other.region, _this.region) || other.region == _this.region)&&(identical(other.city, _this.city) || other.city == _this.city)&&(identical(other.timezone, _this.timezone) || other.timezone == _this.timezone));
}


@override
int get hashCode {
  final _this = this as WebSearchConfigurationRead;
  return Object.hash(runtimeType,_this.configuredMode,_this.contextSize,_this.allowedDomains,_this.country,_this.region,_this.city,_this.timezone);
}



}

/// @nodoc
abstract mixin class $WebSearchConfigurationReadCopyWith<$Res>  {
  factory $WebSearchConfigurationReadCopyWith(WebSearchConfigurationRead value, $Res Function(WebSearchConfigurationRead) _then) = _$WebSearchConfigurationReadCopyWithImpl;
@useResult
$Res call({
 ReadText configuredMode, ReadText? contextSize, TypedListRef allowedDomains, ReadText? country, ReadText? region, ReadText? city, ReadText? timezone
});


$ReadTextCopyWith<$Res> get configuredMode;$ReadTextCopyWith<$Res>? get contextSize;$TypedListRefCopyWith<$Res> get allowedDomains;$ReadTextCopyWith<$Res>? get country;$ReadTextCopyWith<$Res>? get region;$ReadTextCopyWith<$Res>? get city;$ReadTextCopyWith<$Res>? get timezone;

}
/// @nodoc
class _$WebSearchConfigurationReadCopyWithImpl<$Res>
    implements $WebSearchConfigurationReadCopyWith<$Res> {
  _$WebSearchConfigurationReadCopyWithImpl(this._self, this._then);

  final WebSearchConfigurationRead _self;
  final $Res Function(WebSearchConfigurationRead) _then;

/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuredMode = null,Object? contextSize = freezed,Object? allowedDomains = null,Object? country = freezed,Object? region = freezed,Object? city = freezed,Object? timezone = freezed,}) {
  return _then(WebSearchConfigurationRead(
configuredMode: null == configuredMode ? _self.configuredMode : configuredMode // ignore: cast_nullable_to_non_nullable
as ReadText,contextSize: freezed == contextSize ? _self.contextSize : contextSize // ignore: cast_nullable_to_non_nullable
as ReadText?,allowedDomains: null == allowedDomains ? _self.allowedDomains : allowedDomains // ignore: cast_nullable_to_non_nullable
as TypedListRef,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as ReadText?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as ReadText?,city: freezed == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as ReadText?,timezone: freezed == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configuredMode {

  return $ReadTextCopyWith<$Res>(_self.configuredMode, (value) {
    return _then(_self.copyWith(configuredMode: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get contextSize {
    if (_self.contextSize == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.contextSize!, (value) {
    return _then(_self.copyWith(contextSize: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get allowedDomains {

  return $TypedListRefCopyWith<$Res>(_self.allowedDomains, (value) {
    return _then(_self.copyWith(allowedDomains: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get country {
    if (_self.country == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.country!, (value) {
    return _then(_self.copyWith(country: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get region {
    if (_self.region == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.region!, (value) {
    return _then(_self.copyWith(region: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get city {
    if (_self.city == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.city!, (value) {
    return _then(_self.copyWith(city: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get timezone {
    if (_self.timezone == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.timezone!, (value) {
    return _then(_self.copyWith(timezone: value));
  });
}
}


/// Adds pattern-matching-related methods to [WebSearchConfigurationRead].
extension WebSearchConfigurationReadPatterns on WebSearchConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSearchConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSearchConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSearchConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _WebSearchConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSearchConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _WebSearchConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText configuredMode,  ReadText? contextSize,  TypedListRef allowedDomains,  ReadText? country,  ReadText? region,  ReadText? city,  ReadText? timezone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSearchConfigurationRead() when $default != null:
return $default(_that.configuredMode,_that.contextSize,_that.allowedDomains,_that.country,_that.region,_that.city,_that.timezone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText configuredMode,  ReadText? contextSize,  TypedListRef allowedDomains,  ReadText? country,  ReadText? region,  ReadText? city,  ReadText? timezone)  $default,) {final _that = this;
switch (_that) {
case _WebSearchConfigurationRead():
return $default(_that.configuredMode,_that.contextSize,_that.allowedDomains,_that.country,_that.region,_that.city,_that.timezone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText configuredMode,  ReadText? contextSize,  TypedListRef allowedDomains,  ReadText? country,  ReadText? region,  ReadText? city,  ReadText? timezone)?  $default,) {final _that = this;
switch (_that) {
case _WebSearchConfigurationRead() when $default != null:
return $default(_that.configuredMode,_that.contextSize,_that.allowedDomains,_that.country,_that.region,_that.city,_that.timezone);case _:
  return null;

}
}

}

/// @nodoc


class _WebSearchConfigurationRead implements WebSearchConfigurationRead {
  const _WebSearchConfigurationRead({required this.configuredMode, required this.contextSize, required this.allowedDomains, required this.country, required this.region, required this.city, required this.timezone});


@override final  ReadText configuredMode;
@override final  ReadText? contextSize;
@override final  TypedListRef allowedDomains;
@override final  ReadText? country;
@override final  ReadText? region;
@override final  ReadText? city;
@override final  ReadText? timezone;

/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSearchConfigurationReadCopyWith<_WebSearchConfigurationRead> get copyWith => __$WebSearchConfigurationReadCopyWithImpl<_WebSearchConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSearchConfigurationRead&&(identical(other.configuredMode, configuredMode) || other.configuredMode == configuredMode)&&(identical(other.contextSize, contextSize) || other.contextSize == contextSize)&&(identical(other.allowedDomains, allowedDomains) || other.allowedDomains == allowedDomains)&&(identical(other.country, country) || other.country == country)&&(identical(other.region, region) || other.region == region)&&(identical(other.city, city) || other.city == city)&&(identical(other.timezone, timezone) || other.timezone == timezone));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configuredMode,contextSize,allowedDomains,country,region,city,timezone);
}



}

/// @nodoc
abstract mixin class _$WebSearchConfigurationReadCopyWith<$Res> implements $WebSearchConfigurationReadCopyWith<$Res> {
  factory _$WebSearchConfigurationReadCopyWith(_WebSearchConfigurationRead value, $Res Function(_WebSearchConfigurationRead) _then) = __$WebSearchConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText configuredMode, ReadText? contextSize, TypedListRef allowedDomains, ReadText? country, ReadText? region, ReadText? city, ReadText? timezone
});


@override $ReadTextCopyWith<$Res> get configuredMode;@override $ReadTextCopyWith<$Res>? get contextSize;@override $TypedListRefCopyWith<$Res> get allowedDomains;@override $ReadTextCopyWith<$Res>? get country;@override $ReadTextCopyWith<$Res>? get region;@override $ReadTextCopyWith<$Res>? get city;@override $ReadTextCopyWith<$Res>? get timezone;

}
/// @nodoc
class __$WebSearchConfigurationReadCopyWithImpl<$Res>
    implements _$WebSearchConfigurationReadCopyWith<$Res> {
  __$WebSearchConfigurationReadCopyWithImpl(this._self, this._then);

  final _WebSearchConfigurationRead _self;
  final $Res Function(_WebSearchConfigurationRead) _then;

/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configuredMode = null,Object? contextSize = freezed,Object? allowedDomains = null,Object? country = freezed,Object? region = freezed,Object? city = freezed,Object? timezone = freezed,}) {
  return _then(_WebSearchConfigurationRead(
configuredMode: null == configuredMode ? _self.configuredMode : configuredMode // ignore: cast_nullable_to_non_nullable
as ReadText,contextSize: freezed == contextSize ? _self.contextSize : contextSize // ignore: cast_nullable_to_non_nullable
as ReadText?,allowedDomains: null == allowedDomains ? _self.allowedDomains : allowedDomains // ignore: cast_nullable_to_non_nullable
as TypedListRef,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as ReadText?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as ReadText?,city: freezed == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as ReadText?,timezone: freezed == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configuredMode {

  return $ReadTextCopyWith<$Res>(_self.configuredMode, (value) {
    return _then(_self.copyWith(configuredMode: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get contextSize {
    if (_self.contextSize == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.contextSize!, (value) {
    return _then(_self.copyWith(contextSize: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get allowedDomains {

  return $TypedListRefCopyWith<$Res>(_self.allowedDomains, (value) {
    return _then(_self.copyWith(allowedDomains: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get country {
    if (_self.country == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.country!, (value) {
    return _then(_self.copyWith(country: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get region {
    if (_self.region == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.region!, (value) {
    return _then(_self.copyWith(region: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get city {
    if (_self.city == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.city!, (value) {
    return _then(_self.copyWith(city: value));
  });
}/// Create a copy of WebSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get timezone {
    if (_self.timezone == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.timezone!, (value) {
    return _then(_self.copyWith(timezone: value));
  });
}
}

/// @nodoc
mixin _$DeepSeekSearchConfigurationRead {

 bool get configuredEnabled; bool get configuredFetchEnabled;
/// Create a copy of DeepSeekSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationReadCopyWith<DeepSeekSearchConfigurationRead> get copyWith => _$DeepSeekSearchConfigurationReadCopyWithImpl<DeepSeekSearchConfigurationRead>(this as DeepSeekSearchConfigurationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeepSeekSearchConfigurationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeepSeekSearchConfigurationRead&&(identical(other.configuredEnabled, _this.configuredEnabled) || other.configuredEnabled == _this.configuredEnabled)&&(identical(other.configuredFetchEnabled, _this.configuredFetchEnabled) || other.configuredFetchEnabled == _this.configuredFetchEnabled));
}


@override
int get hashCode {
  final _this = this as DeepSeekSearchConfigurationRead;
  return Object.hash(runtimeType,_this.configuredEnabled,_this.configuredFetchEnabled);
}

@override
String toString() {
  final _this = this as DeepSeekSearchConfigurationRead;
  return 'DeepSeekSearchConfigurationRead(configuredEnabled: ${_this.configuredEnabled}, configuredFetchEnabled: ${_this.configuredFetchEnabled})';
}


}

/// @nodoc
abstract mixin class $DeepSeekSearchConfigurationReadCopyWith<$Res>  {
  factory $DeepSeekSearchConfigurationReadCopyWith(DeepSeekSearchConfigurationRead value, $Res Function(DeepSeekSearchConfigurationRead) _then) = _$DeepSeekSearchConfigurationReadCopyWithImpl;
@useResult
$Res call({
 bool configuredEnabled, bool configuredFetchEnabled
});




}
/// @nodoc
class _$DeepSeekSearchConfigurationReadCopyWithImpl<$Res>
    implements $DeepSeekSearchConfigurationReadCopyWith<$Res> {
  _$DeepSeekSearchConfigurationReadCopyWithImpl(this._self, this._then);

  final DeepSeekSearchConfigurationRead _self;
  final $Res Function(DeepSeekSearchConfigurationRead) _then;

/// Create a copy of DeepSeekSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuredEnabled = null,Object? configuredFetchEnabled = null,}) {
  return _then(DeepSeekSearchConfigurationRead(
configuredEnabled: null == configuredEnabled ? _self.configuredEnabled : configuredEnabled // ignore: cast_nullable_to_non_nullable
as bool,configuredFetchEnabled: null == configuredFetchEnabled ? _self.configuredFetchEnabled : configuredFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeepSeekSearchConfigurationRead].
extension DeepSeekSearchConfigurationReadPatterns on DeepSeekSearchConfigurationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeepSeekSearchConfigurationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfigurationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeepSeekSearchConfigurationRead value)  $default,){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfigurationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeepSeekSearchConfigurationRead value)?  $default,){
final _that = this;
switch (_that) {
case _DeepSeekSearchConfigurationRead() when $default != null:
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
case _DeepSeekSearchConfigurationRead() when $default != null:
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
case _DeepSeekSearchConfigurationRead():
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
case _DeepSeekSearchConfigurationRead() when $default != null:
return $default(_that.configuredEnabled,_that.configuredFetchEnabled);case _:
  return null;

}
}

}

/// @nodoc


class _DeepSeekSearchConfigurationRead implements DeepSeekSearchConfigurationRead {
  const _DeepSeekSearchConfigurationRead({required this.configuredEnabled, required this.configuredFetchEnabled});


@override final  bool configuredEnabled;
@override final  bool configuredFetchEnabled;

/// Create a copy of DeepSeekSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeepSeekSearchConfigurationReadCopyWith<_DeepSeekSearchConfigurationRead> get copyWith => __$DeepSeekSearchConfigurationReadCopyWithImpl<_DeepSeekSearchConfigurationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeepSeekSearchConfigurationRead&&(identical(other.configuredEnabled, configuredEnabled) || other.configuredEnabled == configuredEnabled)&&(identical(other.configuredFetchEnabled, configuredFetchEnabled) || other.configuredFetchEnabled == configuredFetchEnabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configuredEnabled,configuredFetchEnabled);
}

@override
String toString() {
    return 'DeepSeekSearchConfigurationRead(configuredEnabled: $configuredEnabled, configuredFetchEnabled: $configuredFetchEnabled)';
}


}

/// @nodoc
abstract mixin class _$DeepSeekSearchConfigurationReadCopyWith<$Res> implements $DeepSeekSearchConfigurationReadCopyWith<$Res> {
  factory _$DeepSeekSearchConfigurationReadCopyWith(_DeepSeekSearchConfigurationRead value, $Res Function(_DeepSeekSearchConfigurationRead) _then) = __$DeepSeekSearchConfigurationReadCopyWithImpl;
@override @useResult
$Res call({
 bool configuredEnabled, bool configuredFetchEnabled
});




}
/// @nodoc
class __$DeepSeekSearchConfigurationReadCopyWithImpl<$Res>
    implements _$DeepSeekSearchConfigurationReadCopyWith<$Res> {
  __$DeepSeekSearchConfigurationReadCopyWithImpl(this._self, this._then);

  final _DeepSeekSearchConfigurationRead _self;
  final $Res Function(_DeepSeekSearchConfigurationRead) _then;

/// Create a copy of DeepSeekSearchConfigurationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configuredEnabled = null,Object? configuredFetchEnabled = null,}) {
  return _then(_DeepSeekSearchConfigurationRead(
configuredEnabled: null == configuredEnabled ? _self.configuredEnabled : configuredEnabled // ignore: cast_nullable_to_non_nullable
as bool,configuredFetchEnabled: null == configuredFetchEnabled ? _self.configuredFetchEnabled : configuredFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
