// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentProfileSummary {

 String get profileId; String get displayName; String get description; String get whenToUse; String get accountId; String get modelId; String? get effort; String get source; String get revision; String get contentHash; bool get system; bool get enabled; AgentWorkspaceMode get workspaceMode;
/// Create a copy of AgentProfileSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfileSummaryCopyWith<AgentProfileSummary> get copyWith => _$AgentProfileSummaryCopyWithImpl<AgentProfileSummary>(this as AgentProfileSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfileSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfileSummary&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.whenToUse, _this.whenToUse) || other.whenToUse == _this.whenToUse)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash)&&(identical(other.system, _this.system) || other.system == _this.system)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode));
}


@override
int get hashCode {
  final _this = this as AgentProfileSummary;
  return Object.hash(runtimeType,_this.profileId,_this.displayName,_this.description,_this.whenToUse,_this.accountId,_this.modelId,_this.effort,_this.source,_this.revision,_this.contentHash,_this.system,_this.enabled,_this.workspaceMode);
}

@override
String toString() {
  final _this = this as AgentProfileSummary;
  return 'AgentProfileSummary(profileId: ${_this.profileId}, displayName: ${_this.displayName}, description: ${_this.description}, whenToUse: ${_this.whenToUse}, accountId: ${_this.accountId}, modelId: ${_this.modelId}, effort: ${_this.effort}, source: ${_this.source}, revision: ${_this.revision}, contentHash: ${_this.contentHash}, system: ${_this.system}, enabled: ${_this.enabled}, workspaceMode: ${_this.workspaceMode})';
}


}

/// @nodoc
abstract mixin class $AgentProfileSummaryCopyWith<$Res>  {
  factory $AgentProfileSummaryCopyWith(AgentProfileSummary value, $Res Function(AgentProfileSummary) _then) = _$AgentProfileSummaryCopyWithImpl;
@useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String accountId, String modelId, String? effort, String source, String revision, String contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class _$AgentProfileSummaryCopyWithImpl<$Res>
    implements $AgentProfileSummaryCopyWith<$Res> {
  _$AgentProfileSummaryCopyWithImpl(this._self, this._then);

  final AgentProfileSummary _self;
  final $Res Function(AgentProfileSummary) _then;

/// Create a copy of AgentProfileSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(AgentProfileSummary(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentProfileSummary].
extension AgentProfileSummaryPatterns on AgentProfileSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfileSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfileSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfileSummary value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfileSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfileSummary value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfileSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfileSummary() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)  $default,) {final _that = this;
switch (_that) {
case _AgentProfileSummary():
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String profileId,  String displayName,  String description,  String whenToUse,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfileSummary() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfileSummary implements AgentProfileSummary {
  const _AgentProfileSummary({required this.profileId, required this.displayName, required this.description, required this.whenToUse, required this.accountId, required this.modelId, required this.effort, required this.source, required this.revision, required this.contentHash, required this.system, required this.enabled, required this.workspaceMode});


@override final  String profileId;
@override final  String displayName;
@override final  String description;
@override final  String whenToUse;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  String source;
@override final  String revision;
@override final  String contentHash;
@override final  bool system;
@override final  bool enabled;
@override final  AgentWorkspaceMode workspaceMode;

/// Create a copy of AgentProfileSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfileSummaryCopyWith<_AgentProfileSummary> get copyWith => __$AgentProfileSummaryCopyWithImpl<_AgentProfileSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfileSummary&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.whenToUse, whenToUse) || other.whenToUse == whenToUse)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.source, source) || other.source == source)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.system, system) || other.system == system)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profileId,displayName,description,whenToUse,accountId,modelId,effort,source,revision,contentHash,system,enabled,workspaceMode);
}

@override
String toString() {
    return 'AgentProfileSummary(profileId: $profileId, displayName: $displayName, description: $description, whenToUse: $whenToUse, accountId: $accountId, modelId: $modelId, effort: $effort, source: $source, revision: $revision, contentHash: $contentHash, system: $system, enabled: $enabled, workspaceMode: $workspaceMode)';
}


}

/// @nodoc
abstract mixin class _$AgentProfileSummaryCopyWith<$Res> implements $AgentProfileSummaryCopyWith<$Res> {
  factory _$AgentProfileSummaryCopyWith(_AgentProfileSummary value, $Res Function(_AgentProfileSummary) _then) = __$AgentProfileSummaryCopyWithImpl;
@override @useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String accountId, String modelId, String? effort, String source, String revision, String contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class __$AgentProfileSummaryCopyWithImpl<$Res>
    implements _$AgentProfileSummaryCopyWith<$Res> {
  __$AgentProfileSummaryCopyWithImpl(this._self, this._then);

  final _AgentProfileSummary _self;
  final $Res Function(_AgentProfileSummary) _then;

/// Create a copy of AgentProfileSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(_AgentProfileSummary(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}


}

/// @nodoc
mixin _$ProfilesValue {


/// Create a copy of ProfilesValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfilesValueCopyWith<ProfilesValue> get copyWith => _$ProfilesValueCopyWithImpl<ProfilesValue>(this as ProfilesValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfilesValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfilesValue&&const DeepCollectionEquality().equals(other.profiles, _this.profiles)&&const DeepCollectionEquality().equals(other.diagnostics, _this.diagnostics));
}


@override
int get hashCode {
  final _this = this as ProfilesValue;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.profiles),const DeepCollectionEquality().hash(_this.diagnostics));
}



}

/// @nodoc
abstract mixin class $ProfilesValueCopyWith<$Res>  {
  factory $ProfilesValueCopyWith(ProfilesValue value, $Res Function(ProfilesValue) _then) = _$ProfilesValueCopyWithImpl;
@useResult
$Res call({
 List<AgentProfileSnapshot> profiles, List<ProfileDiagnostic> diagnostics
});




}
/// @nodoc
class _$ProfilesValueCopyWithImpl<$Res>
    implements $ProfilesValueCopyWith<$Res> {
  _$ProfilesValueCopyWithImpl(this._self, this._then);

  final ProfilesValue _self;
  final $Res Function(ProfilesValue) _then;

/// Create a copy of ProfilesValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profiles = null,Object? diagnostics = null,}) {
  return _then(ProfilesValue(
profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as List<AgentProfileSnapshot>,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<ProfileDiagnostic>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProfilesValue].
extension ProfilesValuePatterns on ProfilesValue {
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
mixin _$AgentProfileSnapshot {

 String get profileId; String get displayName; String get description; String get whenToUse; String get systemInstructions; String get accountId; String get modelId; String? get effort; String get source; String get revision; String get contentHash; bool get system; bool get enabled; AgentWorkspaceMode get workspaceMode;
/// Create a copy of AgentProfileSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfileSnapshotCopyWith<AgentProfileSnapshot> get copyWith => _$AgentProfileSnapshotCopyWithImpl<AgentProfileSnapshot>(this as AgentProfileSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfileSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfileSnapshot&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.whenToUse, _this.whenToUse) || other.whenToUse == _this.whenToUse)&&(identical(other.systemInstructions, _this.systemInstructions) || other.systemInstructions == _this.systemInstructions)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash)&&(identical(other.system, _this.system) || other.system == _this.system)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode));
}


@override
int get hashCode {
  final _this = this as AgentProfileSnapshot;
  return Object.hash(runtimeType,_this.profileId,_this.displayName,_this.description,_this.whenToUse,_this.systemInstructions,_this.accountId,_this.modelId,_this.effort,_this.source,_this.revision,_this.contentHash,_this.system,_this.enabled,_this.workspaceMode);
}



}

/// @nodoc
abstract mixin class $AgentProfileSnapshotCopyWith<$Res>  {
  factory $AgentProfileSnapshotCopyWith(AgentProfileSnapshot value, $Res Function(AgentProfileSnapshot) _then) = _$AgentProfileSnapshotCopyWithImpl;
@useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String systemInstructions, String accountId, String modelId, String? effort, String source, String revision, String contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class _$AgentProfileSnapshotCopyWithImpl<$Res>
    implements $AgentProfileSnapshotCopyWith<$Res> {
  _$AgentProfileSnapshotCopyWithImpl(this._self, this._then);

  final AgentProfileSnapshot _self;
  final $Res Function(AgentProfileSnapshot) _then;

/// Create a copy of AgentProfileSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(AgentProfileSnapshot(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentProfileSnapshot].
extension AgentProfileSnapshotPatterns on AgentProfileSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfileSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfileSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfileSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfileSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfileSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfileSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfileSnapshot() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)  $default,) {final _that = this;
switch (_that) {
case _AgentProfileSnapshot():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  String source,  String revision,  String contentHash,  bool system,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfileSnapshot() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.source,_that.revision,_that.contentHash,_that.system,_that.enabled,_that.workspaceMode);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfileSnapshot implements AgentProfileSnapshot {
  const _AgentProfileSnapshot({required this.profileId, required this.displayName, required this.description, required this.whenToUse, required this.systemInstructions, required this.accountId, required this.modelId, required this.effort, required this.source, required this.revision, required this.contentHash, required this.system, required this.enabled, required this.workspaceMode});


@override final  String profileId;
@override final  String displayName;
@override final  String description;
@override final  String whenToUse;
@override final  String systemInstructions;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  String source;
@override final  String revision;
@override final  String contentHash;
@override final  bool system;
@override final  bool enabled;
@override final  AgentWorkspaceMode workspaceMode;

/// Create a copy of AgentProfileSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfileSnapshotCopyWith<_AgentProfileSnapshot> get copyWith => __$AgentProfileSnapshotCopyWithImpl<_AgentProfileSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfileSnapshot&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.whenToUse, whenToUse) || other.whenToUse == whenToUse)&&(identical(other.systemInstructions, systemInstructions) || other.systemInstructions == systemInstructions)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.source, source) || other.source == source)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.system, system) || other.system == system)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profileId,displayName,description,whenToUse,systemInstructions,accountId,modelId,effort,source,revision,contentHash,system,enabled,workspaceMode);
}



}

/// @nodoc
abstract mixin class _$AgentProfileSnapshotCopyWith<$Res> implements $AgentProfileSnapshotCopyWith<$Res> {
  factory _$AgentProfileSnapshotCopyWith(_AgentProfileSnapshot value, $Res Function(_AgentProfileSnapshot) _then) = __$AgentProfileSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String systemInstructions, String accountId, String modelId, String? effort, String source, String revision, String contentHash, bool system, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class __$AgentProfileSnapshotCopyWithImpl<$Res>
    implements _$AgentProfileSnapshotCopyWith<$Res> {
  __$AgentProfileSnapshotCopyWithImpl(this._self, this._then);

  final _AgentProfileSnapshot _self;
  final $Res Function(_AgentProfileSnapshot) _then;

/// Create a copy of AgentProfileSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? source = null,Object? revision = null,Object? contentHash = null,Object? system = null,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(_AgentProfileSnapshot(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}


}

/// @nodoc
mixin _$ProfileDiagnostic {

 String get path; String get message;
/// Create a copy of ProfileDiagnostic
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileDiagnosticCopyWith<ProfileDiagnostic> get copyWith => _$ProfileDiagnosticCopyWithImpl<ProfileDiagnostic>(this as ProfileDiagnostic, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileDiagnostic;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileDiagnostic&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ProfileDiagnostic;
  return Object.hash(runtimeType,_this.path,_this.message);
}

@override
String toString() {
  final _this = this as ProfileDiagnostic;
  return 'ProfileDiagnostic(path: ${_this.path}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $ProfileDiagnosticCopyWith<$Res>  {
  factory $ProfileDiagnosticCopyWith(ProfileDiagnostic value, $Res Function(ProfileDiagnostic) _then) = _$ProfileDiagnosticCopyWithImpl;
@useResult
$Res call({
 String path, String message
});




}
/// @nodoc
class _$ProfileDiagnosticCopyWithImpl<$Res>
    implements $ProfileDiagnosticCopyWith<$Res> {
  _$ProfileDiagnosticCopyWithImpl(this._self, this._then);

  final ProfileDiagnostic _self;
  final $Res Function(ProfileDiagnostic) _then;

/// Create a copy of ProfileDiagnostic
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? message = null,}) {
  return _then(ProfileDiagnostic(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProfileDiagnostic].
extension ProfileDiagnosticPatterns on ProfileDiagnostic {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileDiagnostic value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileDiagnostic() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileDiagnostic value)  $default,){
final _that = this;
switch (_that) {
case _ProfileDiagnostic():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileDiagnostic value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileDiagnostic() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileDiagnostic() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String message)  $default,) {final _that = this;
switch (_that) {
case _ProfileDiagnostic():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String message)?  $default,) {final _that = this;
switch (_that) {
case _ProfileDiagnostic() when $default != null:
return $default(_that.path,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileDiagnostic implements ProfileDiagnostic {
  const _ProfileDiagnostic({required this.path, required this.message});


@override final  String path;
@override final  String message;

/// Create a copy of ProfileDiagnostic
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileDiagnosticCopyWith<_ProfileDiagnostic> get copyWith => __$ProfileDiagnosticCopyWithImpl<_ProfileDiagnostic>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileDiagnostic&&(identical(other.path, path) || other.path == path)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,message);
}

@override
String toString() {
    return 'ProfileDiagnostic(path: $path, message: $message)';
}


}

/// @nodoc
abstract mixin class _$ProfileDiagnosticCopyWith<$Res> implements $ProfileDiagnosticCopyWith<$Res> {
  factory _$ProfileDiagnosticCopyWith(_ProfileDiagnostic value, $Res Function(_ProfileDiagnostic) _then) = __$ProfileDiagnosticCopyWithImpl;
@override @useResult
$Res call({
 String path, String message
});




}
/// @nodoc
class __$ProfileDiagnosticCopyWithImpl<$Res>
    implements _$ProfileDiagnosticCopyWith<$Res> {
  __$ProfileDiagnosticCopyWithImpl(this._self, this._then);

  final _ProfileDiagnostic _self;
  final $Res Function(_ProfileDiagnostic) _then;

/// Create a copy of ProfileDiagnostic
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? message = null,}) {
  return _then(_ProfileDiagnostic(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AgentProfileEdit {

 String get profileId; String get displayName; String get description; String get whenToUse; String get systemInstructions; String get accountId; String get modelId; String? get effort; bool get enabled; AgentWorkspaceMode get workspaceMode;
/// Create a copy of AgentProfileEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfileEditCopyWith<AgentProfileEdit> get copyWith => _$AgentProfileEditCopyWithImpl<AgentProfileEdit>(this as AgentProfileEdit, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfileEdit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfileEdit&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.whenToUse, _this.whenToUse) || other.whenToUse == _this.whenToUse)&&(identical(other.systemInstructions, _this.systemInstructions) || other.systemInstructions == _this.systemInstructions)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode));
}


@override
int get hashCode {
  final _this = this as AgentProfileEdit;
  return Object.hash(runtimeType,_this.profileId,_this.displayName,_this.description,_this.whenToUse,_this.systemInstructions,_this.accountId,_this.modelId,_this.effort,_this.enabled,_this.workspaceMode);
}



}

/// @nodoc
abstract mixin class $AgentProfileEditCopyWith<$Res>  {
  factory $AgentProfileEditCopyWith(AgentProfileEdit value, $Res Function(AgentProfileEdit) _then) = _$AgentProfileEditCopyWithImpl;
@useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String systemInstructions, String accountId, String modelId, String? effort, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class _$AgentProfileEditCopyWithImpl<$Res>
    implements $AgentProfileEditCopyWith<$Res> {
  _$AgentProfileEditCopyWithImpl(this._self, this._then);

  final AgentProfileEdit _self;
  final $Res Function(AgentProfileEdit) _then;

/// Create a copy of AgentProfileEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(AgentProfileEdit(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentProfileEdit].
extension AgentProfileEditPatterns on AgentProfileEdit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfileEdit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfileEdit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfileEdit value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfileEdit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfileEdit value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfileEdit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfileEdit() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode)  $default,) {final _that = this;
switch (_that) {
case _AgentProfileEdit():
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String profileId,  String displayName,  String description,  String whenToUse,  String systemInstructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfileEdit() when $default != null:
return $default(_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.systemInstructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfileEdit implements AgentProfileEdit {
  const _AgentProfileEdit({required this.profileId, required this.displayName, required this.description, required this.whenToUse, required this.systemInstructions, required this.accountId, required this.modelId, required this.effort, required this.enabled, required this.workspaceMode});


@override final  String profileId;
@override final  String displayName;
@override final  String description;
@override final  String whenToUse;
@override final  String systemInstructions;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  bool enabled;
@override final  AgentWorkspaceMode workspaceMode;

/// Create a copy of AgentProfileEdit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfileEditCopyWith<_AgentProfileEdit> get copyWith => __$AgentProfileEditCopyWithImpl<_AgentProfileEdit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfileEdit&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.whenToUse, whenToUse) || other.whenToUse == whenToUse)&&(identical(other.systemInstructions, systemInstructions) || other.systemInstructions == systemInstructions)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profileId,displayName,description,whenToUse,systemInstructions,accountId,modelId,effort,enabled,workspaceMode);
}



}

/// @nodoc
abstract mixin class _$AgentProfileEditCopyWith<$Res> implements $AgentProfileEditCopyWith<$Res> {
  factory _$AgentProfileEditCopyWith(_AgentProfileEdit value, $Res Function(_AgentProfileEdit) _then) = __$AgentProfileEditCopyWithImpl;
@override @useResult
$Res call({
 String profileId, String displayName, String description, String whenToUse, String systemInstructions, String accountId, String modelId, String? effort, bool enabled, AgentWorkspaceMode workspaceMode
});




}
/// @nodoc
class __$AgentProfileEditCopyWithImpl<$Res>
    implements _$AgentProfileEditCopyWith<$Res> {
  __$AgentProfileEditCopyWithImpl(this._self, this._then);

  final _AgentProfileEdit _self;
  final $Res Function(_AgentProfileEdit) _then;

/// Create a copy of AgentProfileEdit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? systemInstructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? enabled = null,Object? workspaceMode = null,}) {
  return _then(_AgentProfileEdit(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,systemInstructions: null == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,
  ));
}


}

// dart format on
