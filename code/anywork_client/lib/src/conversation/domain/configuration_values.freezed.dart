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
mixin _$ModelRouteBrief {

 int get revision; bool get available; bool get hasUnavailableReason;
/// Create a copy of ModelRouteBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelRouteBriefCopyWith<ModelRouteBrief> get copyWith => _$ModelRouteBriefCopyWithImpl<ModelRouteBrief>(this as ModelRouteBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelRouteBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelRouteBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.hasUnavailableReason, _this.hasUnavailableReason) || other.hasUnavailableReason == _this.hasUnavailableReason));
}


@override
int get hashCode {
  final _this = this as ModelRouteBrief;
  return Object.hash(runtimeType,_this.revision,_this.available,_this.hasUnavailableReason);
}

@override
String toString() {
  final _this = this as ModelRouteBrief;
  return 'ModelRouteBrief(revision: ${_this.revision}, available: ${_this.available}, hasUnavailableReason: ${_this.hasUnavailableReason})';
}


}

/// @nodoc
abstract mixin class $ModelRouteBriefCopyWith<$Res>  {
  factory $ModelRouteBriefCopyWith(ModelRouteBrief value, $Res Function(ModelRouteBrief) _then) = _$ModelRouteBriefCopyWithImpl;
@useResult
$Res call({
 int revision, bool available, bool hasUnavailableReason
});




}
/// @nodoc
class _$ModelRouteBriefCopyWithImpl<$Res>
    implements $ModelRouteBriefCopyWith<$Res> {
  _$ModelRouteBriefCopyWithImpl(this._self, this._then);

  final ModelRouteBrief _self;
  final $Res Function(ModelRouteBrief) _then;

/// Create a copy of ModelRouteBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? available = null,Object? hasUnavailableReason = null,}) {
  return _then(ModelRouteBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,hasUnavailableReason: null == hasUnavailableReason ? _self.hasUnavailableReason : hasUnavailableReason // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelRouteBrief].
extension ModelRouteBriefPatterns on ModelRouteBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelRouteBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelRouteBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelRouteBrief value)  $default,){
final _that = this;
switch (_that) {
case _ModelRouteBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelRouteBrief value)?  $default,){
final _that = this;
switch (_that) {
case _ModelRouteBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  bool available,  bool hasUnavailableReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelRouteBrief() when $default != null:
return $default(_that.revision,_that.available,_that.hasUnavailableReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  bool available,  bool hasUnavailableReason)  $default,) {final _that = this;
switch (_that) {
case _ModelRouteBrief():
return $default(_that.revision,_that.available,_that.hasUnavailableReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  bool available,  bool hasUnavailableReason)?  $default,) {final _that = this;
switch (_that) {
case _ModelRouteBrief() when $default != null:
return $default(_that.revision,_that.available,_that.hasUnavailableReason);case _:
  return null;

}
}

}

/// @nodoc


class _ModelRouteBrief implements ModelRouteBrief {
  const _ModelRouteBrief({required this.revision, required this.available, required this.hasUnavailableReason});


@override final  int revision;
@override final  bool available;
@override final  bool hasUnavailableReason;

/// Create a copy of ModelRouteBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelRouteBriefCopyWith<_ModelRouteBrief> get copyWith => __$ModelRouteBriefCopyWithImpl<_ModelRouteBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelRouteBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.available, available) || other.available == available)&&(identical(other.hasUnavailableReason, hasUnavailableReason) || other.hasUnavailableReason == hasUnavailableReason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,available,hasUnavailableReason);
}

@override
String toString() {
    return 'ModelRouteBrief(revision: $revision, available: $available, hasUnavailableReason: $hasUnavailableReason)';
}


}

/// @nodoc
abstract mixin class _$ModelRouteBriefCopyWith<$Res> implements $ModelRouteBriefCopyWith<$Res> {
  factory _$ModelRouteBriefCopyWith(_ModelRouteBrief value, $Res Function(_ModelRouteBrief) _then) = __$ModelRouteBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, bool available, bool hasUnavailableReason
});




}
/// @nodoc
class __$ModelRouteBriefCopyWithImpl<$Res>
    implements _$ModelRouteBriefCopyWith<$Res> {
  __$ModelRouteBriefCopyWithImpl(this._self, this._then);

  final _ModelRouteBrief _self;
  final $Res Function(_ModelRouteBrief) _then;

/// Create a copy of ModelRouteBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? available = null,Object? hasUnavailableReason = null,}) {
  return _then(_ModelRouteBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,hasUnavailableReason: null == hasUnavailableReason ? _self.hasUnavailableReason : hasUnavailableReason // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ThreadModelRoute {

 String? get botId; String get accountId; String get modelId; String? get effort; int get revision; bool get available; String? get unavailableReason;
/// Create a copy of ThreadModelRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadModelRouteCopyWith<ThreadModelRoute> get copyWith => _$ThreadModelRouteCopyWithImpl<ThreadModelRoute>(this as ThreadModelRoute, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadModelRoute;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModelRoute&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.unavailableReason, _this.unavailableReason) || other.unavailableReason == _this.unavailableReason));
}


@override
int get hashCode {
  final _this = this as ThreadModelRoute;
  return Object.hash(runtimeType,_this.botId,_this.accountId,_this.modelId,_this.effort,_this.revision,_this.available,_this.unavailableReason);
}



}

/// @nodoc
abstract mixin class $ThreadModelRouteCopyWith<$Res>  {
  factory $ThreadModelRouteCopyWith(ThreadModelRoute value, $Res Function(ThreadModelRoute) _then) = _$ThreadModelRouteCopyWithImpl;
@useResult
$Res call({
 String? botId, String accountId, String modelId, String? effort, int revision, bool available, String? unavailableReason
});




}
/// @nodoc
class _$ThreadModelRouteCopyWithImpl<$Res>
    implements $ThreadModelRouteCopyWith<$Res> {
  _$ThreadModelRouteCopyWithImpl(this._self, this._then);

  final ThreadModelRoute _self;
  final $Res Function(ThreadModelRoute) _then;

/// Create a copy of ThreadModelRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = freezed,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? revision = null,Object? available = null,Object? unavailableReason = freezed,}) {
  return _then(ThreadModelRoute(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadModelRoute].
extension ThreadModelRoutePatterns on ThreadModelRoute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadModelRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadModelRoute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadModelRoute value)  $default,){
final _that = this;
switch (_that) {
case _ThreadModelRoute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadModelRoute value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadModelRoute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? botId,  String accountId,  String modelId,  String? effort,  int revision,  bool available,  String? unavailableReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadModelRoute() when $default != null:
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? botId,  String accountId,  String modelId,  String? effort,  int revision,  bool available,  String? unavailableReason)  $default,) {final _that = this;
switch (_that) {
case _ThreadModelRoute():
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? botId,  String accountId,  String modelId,  String? effort,  int revision,  bool available,  String? unavailableReason)?  $default,) {final _that = this;
switch (_that) {
case _ThreadModelRoute() when $default != null:
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadModelRoute implements ThreadModelRoute {
  const _ThreadModelRoute({required this.botId, required this.accountId, required this.modelId, required this.effort, required this.revision, required this.available, required this.unavailableReason});


@override final  String? botId;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  int revision;
@override final  bool available;
@override final  String? unavailableReason;

/// Create a copy of ThreadModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadModelRouteCopyWith<_ThreadModelRoute> get copyWith => __$ThreadModelRouteCopyWithImpl<_ThreadModelRoute>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadModelRoute&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.available, available) || other.available == available)&&(identical(other.unavailableReason, unavailableReason) || other.unavailableReason == unavailableReason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,accountId,modelId,effort,revision,available,unavailableReason);
}



}

/// @nodoc
abstract mixin class _$ThreadModelRouteCopyWith<$Res> implements $ThreadModelRouteCopyWith<$Res> {
  factory _$ThreadModelRouteCopyWith(_ThreadModelRoute value, $Res Function(_ThreadModelRoute) _then) = __$ThreadModelRouteCopyWithImpl;
@override @useResult
$Res call({
 String? botId, String accountId, String modelId, String? effort, int revision, bool available, String? unavailableReason
});




}
/// @nodoc
class __$ThreadModelRouteCopyWithImpl<$Res>
    implements _$ThreadModelRouteCopyWith<$Res> {
  __$ThreadModelRouteCopyWithImpl(this._self, this._then);

  final _ThreadModelRoute _self;
  final $Res Function(_ThreadModelRoute) _then;

/// Create a copy of ThreadModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = freezed,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? revision = null,Object? available = null,Object? unavailableReason = freezed,}) {
  return _then(_ThreadModelRoute(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ThreadConfigurationValue {

 ThreadConfigurationReadRef get details; ConfigProjectionStamp get sources; int get modeRevision; int? get modeBindingRevision; ModelRouteBrief? get modelRoute; int get activeSkillCount; ThreadCapabilitySupport get activeMcp; ThreadCapabilitySupport get activeLsp; ThreadCapabilitySupport get mcpHealth;
/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<ThreadConfigurationValue> get copyWith => _$ThreadConfigurationValueCopyWithImpl<ThreadConfigurationValue>(this as ThreadConfigurationValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadConfigurationValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationValue&&(identical(other.details, _this.details) || other.details == _this.details)&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.modeRevision, _this.modeRevision) || other.modeRevision == _this.modeRevision)&&(identical(other.modeBindingRevision, _this.modeBindingRevision) || other.modeBindingRevision == _this.modeBindingRevision)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute)&&(identical(other.activeSkillCount, _this.activeSkillCount) || other.activeSkillCount == _this.activeSkillCount)&&(identical(other.activeMcp, _this.activeMcp) || other.activeMcp == _this.activeMcp)&&(identical(other.activeLsp, _this.activeLsp) || other.activeLsp == _this.activeLsp)&&(identical(other.mcpHealth, _this.mcpHealth) || other.mcpHealth == _this.mcpHealth));
}


@override
int get hashCode {
  final _this = this as ThreadConfigurationValue;
  return Object.hash(runtimeType,_this.details,_this.sources,_this.modeRevision,_this.modeBindingRevision,_this.modelRoute,_this.activeSkillCount,_this.activeMcp,_this.activeLsp,_this.mcpHealth);
}

@override
String toString() {
  final _this = this as ThreadConfigurationValue;
  return 'ThreadConfigurationValue(details: ${_this.details}, sources: ${_this.sources}, modeRevision: ${_this.modeRevision}, modeBindingRevision: ${_this.modeBindingRevision}, modelRoute: ${_this.modelRoute}, activeSkillCount: ${_this.activeSkillCount}, activeMcp: ${_this.activeMcp}, activeLsp: ${_this.activeLsp}, mcpHealth: ${_this.mcpHealth})';
}


}

/// @nodoc
abstract mixin class $ThreadConfigurationValueCopyWith<$Res>  {
  factory $ThreadConfigurationValueCopyWith(ThreadConfigurationValue value, $Res Function(ThreadConfigurationValue) _then) = _$ThreadConfigurationValueCopyWithImpl;
@useResult
$Res call({
 ThreadConfigurationReadRef details, ConfigProjectionStamp sources, int modeRevision, int? modeBindingRevision, ModelRouteBrief? modelRoute, int activeSkillCount, ThreadCapabilitySupport activeMcp, ThreadCapabilitySupport activeLsp, ThreadCapabilitySupport mcpHealth
});


$ThreadConfigurationReadRefCopyWith<$Res> get details;$ConfigProjectionStampCopyWith<$Res> get sources;$ModelRouteBriefCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class _$ThreadConfigurationValueCopyWithImpl<$Res>
    implements $ThreadConfigurationValueCopyWith<$Res> {
  _$ThreadConfigurationValueCopyWithImpl(this._self, this._then);

  final ThreadConfigurationValue _self;
  final $Res Function(ThreadConfigurationValue) _then;

/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? details = null,Object? sources = null,Object? modeRevision = null,Object? modeBindingRevision = freezed,Object? modelRoute = freezed,Object? activeSkillCount = null,Object? activeMcp = null,Object? activeLsp = null,Object? mcpHealth = null,}) {
  return _then(ThreadConfigurationValue(
details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationReadRef,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,modeRevision: null == modeRevision ? _self.modeRevision : modeRevision // ignore: cast_nullable_to_non_nullable
as int,modeBindingRevision: freezed == modeBindingRevision ? _self.modeBindingRevision : modeBindingRevision // ignore: cast_nullable_to_non_nullable
as int?,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ModelRouteBrief?,activeSkillCount: null == activeSkillCount ? _self.activeSkillCount : activeSkillCount // ignore: cast_nullable_to_non_nullable
as int,activeMcp: null == activeMcp ? _self.activeMcp : activeMcp // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,activeLsp: null == activeLsp ? _self.activeLsp : activeLsp // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,mcpHealth: null == mcpHealth ? _self.mcpHealth : mcpHealth // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,
  ));
}
/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationReadRefCopyWith<$Res> get details {

  return $ThreadConfigurationReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get sources {

  return $ConfigProjectionStampCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelRouteBriefCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $ModelRouteBriefCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadConfigurationValue].
extension ThreadConfigurationValuePatterns on ThreadConfigurationValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadConfigurationValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadConfigurationValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadConfigurationValue value)  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadConfigurationValue value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadConfigurationReadRef details,  ConfigProjectionStamp sources,  int modeRevision,  int? modeBindingRevision,  ModelRouteBrief? modelRoute,  int activeSkillCount,  ThreadCapabilitySupport activeMcp,  ThreadCapabilitySupport activeLsp,  ThreadCapabilitySupport mcpHealth)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadConfigurationValue() when $default != null:
return $default(_that.details,_that.sources,_that.modeRevision,_that.modeBindingRevision,_that.modelRoute,_that.activeSkillCount,_that.activeMcp,_that.activeLsp,_that.mcpHealth);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadConfigurationReadRef details,  ConfigProjectionStamp sources,  int modeRevision,  int? modeBindingRevision,  ModelRouteBrief? modelRoute,  int activeSkillCount,  ThreadCapabilitySupport activeMcp,  ThreadCapabilitySupport activeLsp,  ThreadCapabilitySupport mcpHealth)  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationValue():
return $default(_that.details,_that.sources,_that.modeRevision,_that.modeBindingRevision,_that.modelRoute,_that.activeSkillCount,_that.activeMcp,_that.activeLsp,_that.mcpHealth);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadConfigurationReadRef details,  ConfigProjectionStamp sources,  int modeRevision,  int? modeBindingRevision,  ModelRouteBrief? modelRoute,  int activeSkillCount,  ThreadCapabilitySupport activeMcp,  ThreadCapabilitySupport activeLsp,  ThreadCapabilitySupport mcpHealth)?  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationValue() when $default != null:
return $default(_that.details,_that.sources,_that.modeRevision,_that.modeBindingRevision,_that.modelRoute,_that.activeSkillCount,_that.activeMcp,_that.activeLsp,_that.mcpHealth);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadConfigurationValue implements ThreadConfigurationValue {
  const _ThreadConfigurationValue({required this.details, required this.sources, required this.modeRevision, required this.modeBindingRevision, required this.modelRoute, required this.activeSkillCount, required this.activeMcp, required this.activeLsp, required this.mcpHealth});


@override final  ThreadConfigurationReadRef details;
@override final  ConfigProjectionStamp sources;
@override final  int modeRevision;
@override final  int? modeBindingRevision;
@override final  ModelRouteBrief? modelRoute;
@override final  int activeSkillCount;
@override final  ThreadCapabilitySupport activeMcp;
@override final  ThreadCapabilitySupport activeLsp;
@override final  ThreadCapabilitySupport mcpHealth;

/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadConfigurationValueCopyWith<_ThreadConfigurationValue> get copyWith => __$ThreadConfigurationValueCopyWithImpl<_ThreadConfigurationValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadConfigurationValue&&(identical(other.details, details) || other.details == details)&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.modeRevision, modeRevision) || other.modeRevision == modeRevision)&&(identical(other.modeBindingRevision, modeBindingRevision) || other.modeBindingRevision == modeBindingRevision)&&(identical(other.modelRoute, modelRoute) || other.modelRoute == modelRoute)&&(identical(other.activeSkillCount, activeSkillCount) || other.activeSkillCount == activeSkillCount)&&(identical(other.activeMcp, activeMcp) || other.activeMcp == activeMcp)&&(identical(other.activeLsp, activeLsp) || other.activeLsp == activeLsp)&&(identical(other.mcpHealth, mcpHealth) || other.mcpHealth == mcpHealth));
}


@override
int get hashCode {
    return Object.hash(runtimeType,details,sources,modeRevision,modeBindingRevision,modelRoute,activeSkillCount,activeMcp,activeLsp,mcpHealth);
}

@override
String toString() {
    return 'ThreadConfigurationValue(details: $details, sources: $sources, modeRevision: $modeRevision, modeBindingRevision: $modeBindingRevision, modelRoute: $modelRoute, activeSkillCount: $activeSkillCount, activeMcp: $activeMcp, activeLsp: $activeLsp, mcpHealth: $mcpHealth)';
}


}

/// @nodoc
abstract mixin class _$ThreadConfigurationValueCopyWith<$Res> implements $ThreadConfigurationValueCopyWith<$Res> {
  factory _$ThreadConfigurationValueCopyWith(_ThreadConfigurationValue value, $Res Function(_ThreadConfigurationValue) _then) = __$ThreadConfigurationValueCopyWithImpl;
@override @useResult
$Res call({
 ThreadConfigurationReadRef details, ConfigProjectionStamp sources, int modeRevision, int? modeBindingRevision, ModelRouteBrief? modelRoute, int activeSkillCount, ThreadCapabilitySupport activeMcp, ThreadCapabilitySupport activeLsp, ThreadCapabilitySupport mcpHealth
});


@override $ThreadConfigurationReadRefCopyWith<$Res> get details;@override $ConfigProjectionStampCopyWith<$Res> get sources;@override $ModelRouteBriefCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class __$ThreadConfigurationValueCopyWithImpl<$Res>
    implements _$ThreadConfigurationValueCopyWith<$Res> {
  __$ThreadConfigurationValueCopyWithImpl(this._self, this._then);

  final _ThreadConfigurationValue _self;
  final $Res Function(_ThreadConfigurationValue) _then;

/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? details = null,Object? sources = null,Object? modeRevision = null,Object? modeBindingRevision = freezed,Object? modelRoute = freezed,Object? activeSkillCount = null,Object? activeMcp = null,Object? activeLsp = null,Object? mcpHealth = null,}) {
  return _then(_ThreadConfigurationValue(
details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationReadRef,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,modeRevision: null == modeRevision ? _self.modeRevision : modeRevision // ignore: cast_nullable_to_non_nullable
as int,modeBindingRevision: freezed == modeBindingRevision ? _self.modeBindingRevision : modeBindingRevision // ignore: cast_nullable_to_non_nullable
as int?,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ModelRouteBrief?,activeSkillCount: null == activeSkillCount ? _self.activeSkillCount : activeSkillCount // ignore: cast_nullable_to_non_nullable
as int,activeMcp: null == activeMcp ? _self.activeMcp : activeMcp // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,activeLsp: null == activeLsp ? _self.activeLsp : activeLsp // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,mcpHealth: null == mcpHealth ? _self.mcpHealth : mcpHealth // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,
  ));
}

/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationReadRefCopyWith<$Res> get details {

  return $ThreadConfigurationReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get sources {

  return $ConfigProjectionStampCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of ThreadConfigurationValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelRouteBriefCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $ModelRouteBriefCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}

// dart format on
