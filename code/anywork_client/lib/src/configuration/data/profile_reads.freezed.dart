// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentProfilesReadHeader {

 TypedListRef get profiles; TypedListRef get diagnostics;
/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesReadHeaderCopyWith<AgentProfilesReadHeader> get copyWith => _$AgentProfilesReadHeaderCopyWithImpl<AgentProfilesReadHeader>(this as AgentProfilesReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesReadHeader&&(identical(other.profiles, _this.profiles) || other.profiles == _this.profiles)&&(identical(other.diagnostics, _this.diagnostics) || other.diagnostics == _this.diagnostics));
}


@override
int get hashCode {
  final _this = this as AgentProfilesReadHeader;
  return Object.hash(runtimeType,_this.profiles,_this.diagnostics);
}

@override
String toString() {
  final _this = this as AgentProfilesReadHeader;
  return 'AgentProfilesReadHeader(profiles: ${_this.profiles}, diagnostics: ${_this.diagnostics})';
}


}

/// @nodoc
abstract mixin class $AgentProfilesReadHeaderCopyWith<$Res>  {
  factory $AgentProfilesReadHeaderCopyWith(AgentProfilesReadHeader value, $Res Function(AgentProfilesReadHeader) _then) = _$AgentProfilesReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef profiles, TypedListRef diagnostics
});


$TypedListRefCopyWith<$Res> get profiles;$TypedListRefCopyWith<$Res> get diagnostics;

}
/// @nodoc
class _$AgentProfilesReadHeaderCopyWithImpl<$Res>
    implements $AgentProfilesReadHeaderCopyWith<$Res> {
  _$AgentProfilesReadHeaderCopyWithImpl(this._self, this._then);

  final AgentProfilesReadHeader _self;
  final $Res Function(AgentProfilesReadHeader) _then;

/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profiles = null,Object? diagnostics = null,}) {
  return _then(AgentProfilesReadHeader(
profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as TypedListRef,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get profiles {

  return $TypedListRefCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get diagnostics {

  return $TypedListRefCopyWith<$Res>(_self.diagnostics, (value) {
    return _then(_self.copyWith(diagnostics: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfilesReadHeader].
extension AgentProfilesReadHeaderPatterns on AgentProfilesReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef profiles,  TypedListRef diagnostics)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfilesReadHeader() when $default != null:
return $default(_that.profiles,_that.diagnostics);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef profiles,  TypedListRef diagnostics)  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesReadHeader():
return $default(_that.profiles,_that.diagnostics);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef profiles,  TypedListRef diagnostics)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesReadHeader() when $default != null:
return $default(_that.profiles,_that.diagnostics);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesReadHeader implements AgentProfilesReadHeader {
  const _AgentProfilesReadHeader({required this.profiles, required this.diagnostics});


@override final  TypedListRef profiles;
@override final  TypedListRef diagnostics;

/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesReadHeaderCopyWith<_AgentProfilesReadHeader> get copyWith => __$AgentProfilesReadHeaderCopyWithImpl<_AgentProfilesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesReadHeader&&(identical(other.profiles, profiles) || other.profiles == profiles)&&(identical(other.diagnostics, diagnostics) || other.diagnostics == diagnostics));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profiles,diagnostics);
}

@override
String toString() {
    return 'AgentProfilesReadHeader(profiles: $profiles, diagnostics: $diagnostics)';
}


}

/// @nodoc
abstract mixin class _$AgentProfilesReadHeaderCopyWith<$Res> implements $AgentProfilesReadHeaderCopyWith<$Res> {
  factory _$AgentProfilesReadHeaderCopyWith(_AgentProfilesReadHeader value, $Res Function(_AgentProfilesReadHeader) _then) = __$AgentProfilesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef profiles, TypedListRef diagnostics
});


@override $TypedListRefCopyWith<$Res> get profiles;@override $TypedListRefCopyWith<$Res> get diagnostics;

}
/// @nodoc
class __$AgentProfilesReadHeaderCopyWithImpl<$Res>
    implements _$AgentProfilesReadHeaderCopyWith<$Res> {
  __$AgentProfilesReadHeaderCopyWithImpl(this._self, this._then);

  final _AgentProfilesReadHeader _self;
  final $Res Function(_AgentProfilesReadHeader) _then;

/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profiles = null,Object? diagnostics = null,}) {
  return _then(_AgentProfilesReadHeader(
profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as TypedListRef,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get profiles {

  return $TypedListRefCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}/// Create a copy of AgentProfilesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get diagnostics {

  return $TypedListRefCopyWith<$Res>(_self.diagnostics, (value) {
    return _then(_self.copyWith(diagnostics: value));
  });
}
}

/// @nodoc
mixin _$AgentProfileRead {

 ReadText get profileId; ReadText get displayName; ReadText get description; ReadText get whenToUse; ReadText get systemInstructions; ReadText get accountId; ReadText get modelId; ReadText? get effort; ReadText get source; ReadText get revision; ReadText get contentHash; bool get system; bool get enabled; AgentWorkspaceMode get workspaceMode;
/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfileReadCopyWith<AgentProfileRead> get copyWith => _$AgentProfileReadCopyWithImpl<AgentProfileRead>(this as AgentProfileRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfileRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfileRead&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.whenToUse, _this.whenToUse) || other.whenToUse == _this.whenToUse)&&(identical(other.systemInstructions, _this.systemInstructions) || other.systemInstructions == _this.systemInstructions)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash)&&(identical(other.system, _this.system) || other.system == _this.system)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode));
}


@override
int get hashCode {
  final _this = this as AgentProfileRead;
  return Object.hash(runtimeType,_this.profileId,_this.displayName,_this.description,_this.whenToUse,_this.systemInstructions,_this.accountId,_this.modelId,_this.effort,_this.source,_this.revision,_this.contentHash,_this.system,_this.enabled,_this.workspaceMode);
}



}

/// @nodoc
abstract mixin class $AgentProfileReadCopyWith<$Res>  {
  factory $AgentProfileReadCopyWith(AgentProfileRead value, $Res Function(AgentProfileRead) _then) = _$AgentProfileReadCopyWithImpl;
@useResult
$Res call({
 ReadText profileId, ReadText displayName, ReadText description, ReadText whenToUse, ReadText systemInstructions, ReadText accountId, ReadText modelId, ReadText? effort, ReadText source, ReadText revision, ReadText contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});


$ReadTextCopyWith<$Res> get profileId;$ReadTextCopyWith<$Res> get displayName;$ReadTextCopyWith<$Res> get description;$ReadTextCopyWith<$Res> get whenToUse;$ReadTextCopyWith<$Res> get systemInstructions;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res>? get effort;$ReadTextCopyWith<$Res> get source;$ReadTextCopyWith<$Res> get revision;$ReadTextCopyWith<$Res> get contentHash;

}
/// @nodoc
class _$AgentProfileReadCopyWithImpl<$Res>
    implements $AgentProfileReadCopyWith<$Res> {
  _$AgentProfileReadCopyWithImpl(this._self, this._then);

  final AgentProfileRead _self;
  final $Res Function(AgentProfileRead) _then;

/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(AgentProfileRead(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as ReadText,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as ReadText,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as ReadText,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}
/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get profileId {

  return $ReadTextCopyWith<$Res>(_self.profileId, (value) {
    return _then(_self.copyWith(profileId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get whenToUse {

  return $ReadTextCopyWith<$Res>(_self.whenToUse, (value) {
    return _then(_self.copyWith(whenToUse: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get systemInstructions {

  return $ReadTextCopyWith<$Res>(_self.systemInstructions, (value) {
    return _then(_self.copyWith(systemInstructions: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get source {

  return $ReadTextCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get revision {

  return $ReadTextCopyWith<$Res>(_self.revision, (value) {
    return _then(_self.copyWith(revision: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get contentHash {

  return $ReadTextCopyWith<$Res>(_self.contentHash, (value) {
    return _then(_self.copyWith(contentHash: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfileRead].
extension AgentProfileReadPatterns on AgentProfileRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfileRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfileRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfileRead value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfileRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfileRead value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfileRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText profileId,  ReadText displayName,  ReadText description,  ReadText whenToUse,  ReadText systemInstructions,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText source,  ReadText revision,  ReadText contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfileRead() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText profileId,  ReadText displayName,  ReadText description,  ReadText whenToUse,  ReadText systemInstructions,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText source,  ReadText revision,  ReadText contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)  $default,) {final _that = this;
switch (_that) {
case _AgentProfileRead():
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText profileId,  ReadText displayName,  ReadText description,  ReadText whenToUse,  ReadText systemInstructions,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText source,  ReadText revision,  ReadText contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfileRead() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfileRead implements AgentProfileRead {
  const _AgentProfileRead({required this.profileId, required this.displayName, required this.description, required this.whenToUse, required this.systemInstructions, required this.accountId, required this.modelId, required this.effort, required this.source, required this.revision, required this.contentHash, required this.system, required this.enabled, required this.workspaceMode});


@override final  ReadText profileId;
@override final  ReadText displayName;
@override final  ReadText description;
@override final  ReadText whenToUse;
@override final  ReadText systemInstructions;
@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText? effort;
@override final  ReadText source;
@override final  ReadText revision;
@override final  ReadText contentHash;
@override final  bool system;
@override final  bool enabled;
@override final  AgentWorkspaceMode workspaceMode;

/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfileReadCopyWith<_AgentProfileRead> get copyWith => __$AgentProfileReadCopyWithImpl<_AgentProfileRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfileRead&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.whenToUse, whenToUse) || other.whenToUse == whenToUse)&&(identical(other.systemInstructions, systemInstructions) || other.systemInstructions == systemInstructions)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.source, source) || other.source == source)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.system, system) || other.system == system)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profileId,displayName,description,whenToUse,systemInstructions,accountId,modelId,effort,source,revision,contentHash,system,enabled,workspaceMode);
}



}

/// @nodoc
abstract mixin class _$AgentProfileReadCopyWith<$Res> implements $AgentProfileReadCopyWith<$Res> {
  factory _$AgentProfileReadCopyWith(_AgentProfileRead value, $Res Function(_AgentProfileRead) _then) = __$AgentProfileReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText profileId, ReadText displayName, ReadText description, ReadText whenToUse, ReadText systemInstructions, ReadText accountId, ReadText modelId, ReadText? effort, ReadText source, ReadText revision, ReadText contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});


@override $ReadTextCopyWith<$Res> get profileId;@override $ReadTextCopyWith<$Res> get displayName;@override $ReadTextCopyWith<$Res> get description;@override $ReadTextCopyWith<$Res> get whenToUse;@override $ReadTextCopyWith<$Res> get systemInstructions;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res>? get effort;@override $ReadTextCopyWith<$Res> get source;@override $ReadTextCopyWith<$Res> get revision;@override $ReadTextCopyWith<$Res> get contentHash;

}
/// @nodoc
class __$AgentProfileReadCopyWithImpl<$Res>
    implements _$AgentProfileReadCopyWith<$Res> {
  __$AgentProfileReadCopyWithImpl(this._self, this._then);

  final _AgentProfileRead _self;
  final $Res Function(_AgentProfileRead) _then;

/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(_AgentProfileRead(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as ReadText,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as ReadText,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as ReadText,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}

/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get profileId {

  return $ReadTextCopyWith<$Res>(_self.profileId, (value) {
    return _then(_self.copyWith(profileId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get whenToUse {

  return $ReadTextCopyWith<$Res>(_self.whenToUse, (value) {
    return _then(_self.copyWith(whenToUse: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get systemInstructions {

  return $ReadTextCopyWith<$Res>(_self.systemInstructions, (value) {
    return _then(_self.copyWith(systemInstructions: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get source {

  return $ReadTextCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get revision {

  return $ReadTextCopyWith<$Res>(_self.revision, (value) {
    return _then(_self.copyWith(revision: value));
  });
}/// Create a copy of AgentProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get contentHash {

  return $ReadTextCopyWith<$Res>(_self.contentHash, (value) {
    return _then(_self.copyWith(contentHash: value));
  });
}
}

/// @nodoc
mixin _$ProfileDiagnosticRead {

 ReadText get path; ReadText get message;
/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileDiagnosticReadCopyWith<ProfileDiagnosticRead> get copyWith => _$ProfileDiagnosticReadCopyWithImpl<ProfileDiagnosticRead>(this as ProfileDiagnosticRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileDiagnosticRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileDiagnosticRead&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ProfileDiagnosticRead;
  return Object.hash(runtimeType,_this.path,_this.message);
}



}

/// @nodoc
abstract mixin class $ProfileDiagnosticReadCopyWith<$Res>  {
  factory $ProfileDiagnosticReadCopyWith(ProfileDiagnosticRead value, $Res Function(ProfileDiagnosticRead) _then) = _$ProfileDiagnosticReadCopyWithImpl;
@useResult
$Res call({
 ReadText path, ReadText message
});


$ReadTextCopyWith<$Res> get path;$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$ProfileDiagnosticReadCopyWithImpl<$Res>
    implements $ProfileDiagnosticReadCopyWith<$Res> {
  _$ProfileDiagnosticReadCopyWithImpl(this._self, this._then);

  final ProfileDiagnosticRead _self;
  final $Res Function(ProfileDiagnosticRead) _then;

/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? message = null,}) {
  return _then(ProfileDiagnosticRead(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfileDiagnosticRead].
extension ProfileDiagnosticReadPatterns on ProfileDiagnosticRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileDiagnosticRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileDiagnosticRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileDiagnosticRead value)  $default,){
final _that = this;
switch (_that) {
case _ProfileDiagnosticRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileDiagnosticRead value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileDiagnosticRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText path,  ReadText message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileDiagnosticRead() when $default != null:
return $default(_that.path,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText path,  ReadText message)  $default,) {final _that = this;
switch (_that) {
case _ProfileDiagnosticRead():
return $default(_that.path,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText path,  ReadText message)?  $default,) {final _that = this;
switch (_that) {
case _ProfileDiagnosticRead() when $default != null:
return $default(_that.path,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileDiagnosticRead implements ProfileDiagnosticRead {
  const _ProfileDiagnosticRead({required this.path, required this.message});


@override final  ReadText path;
@override final  ReadText message;

/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileDiagnosticReadCopyWith<_ProfileDiagnosticRead> get copyWith => __$ProfileDiagnosticReadCopyWithImpl<_ProfileDiagnosticRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileDiagnosticRead&&(identical(other.path, path) || other.path == path)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,message);
}



}

/// @nodoc
abstract mixin class _$ProfileDiagnosticReadCopyWith<$Res> implements $ProfileDiagnosticReadCopyWith<$Res> {
  factory _$ProfileDiagnosticReadCopyWith(_ProfileDiagnosticRead value, $Res Function(_ProfileDiagnosticRead) _then) = __$ProfileDiagnosticReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText path, ReadText message
});


@override $ReadTextCopyWith<$Res> get path;@override $ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class __$ProfileDiagnosticReadCopyWithImpl<$Res>
    implements _$ProfileDiagnosticReadCopyWith<$Res> {
  __$ProfileDiagnosticReadCopyWithImpl(this._self, this._then);

  final _ProfileDiagnosticRead _self;
  final $Res Function(_ProfileDiagnosticRead) _then;

/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? message = null,}) {
  return _then(_ProfileDiagnosticRead(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of ProfileDiagnosticRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

// dart format on
