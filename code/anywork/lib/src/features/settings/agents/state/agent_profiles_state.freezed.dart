// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_profiles_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsRoleRead {

 String get roleId; ConfigurationRoleReadTarget? get target; int get intent; bool get pending; RoleRouteRead? get value; StudioFailure? get error;
/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsRoleReadCopyWith<SettingsRoleRead> get copyWith => _$SettingsRoleReadCopyWithImpl<SettingsRoleRead>(this as SettingsRoleRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsRoleRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsRoleRead&&(identical(other.roleId, _this.roleId) || other.roleId == _this.roleId)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as SettingsRoleRead;
  return Object.hash(runtimeType,_this.roleId,_this.target,_this.intent,_this.pending,_this.value,_this.error);
}



}

/// @nodoc
abstract mixin class $SettingsRoleReadCopyWith<$Res>  {
  factory $SettingsRoleReadCopyWith(SettingsRoleRead value, $Res Function(SettingsRoleRead) _then) = _$SettingsRoleReadCopyWithImpl;
@useResult
$Res call({
 String roleId, ConfigurationRoleReadTarget? target, int intent, bool pending, RoleRouteRead? value, StudioFailure? error
});


$ConfigurationRoleReadTargetCopyWith<$Res>? get target;$RoleRouteReadCopyWith<$Res>? get value;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$SettingsRoleReadCopyWithImpl<$Res>
    implements $SettingsRoleReadCopyWith<$Res> {
  _$SettingsRoleReadCopyWithImpl(this._self, this._then);

  final SettingsRoleRead _self;
  final $Res Function(SettingsRoleRead) _then;

/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roleId = null,Object? target = freezed,Object? intent = null,Object? pending = null,Object? value = freezed,Object? error = freezed,}) {
  return _then(SettingsRoleRead(
roleId: null == roleId ? _self.roleId : roleId // ignore: cast_nullable_to_non_nullable
as String,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RoleRouteRead?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoleRouteReadCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $RoleRouteReadCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsRoleRead].
extension SettingsRoleReadPatterns on SettingsRoleRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsRoleRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsRoleRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsRoleRead value)  $default,){
final _that = this;
switch (_that) {
case _SettingsRoleRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsRoleRead value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsRoleRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roleId,  ConfigurationRoleReadTarget? target,  int intent,  bool pending,  RoleRouteRead? value,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsRoleRead() when $default != null:
return $default(_that.roleId,_that.target,_that.intent,_that.pending,_that.value,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roleId,  ConfigurationRoleReadTarget? target,  int intent,  bool pending,  RoleRouteRead? value,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _SettingsRoleRead():
return $default(_that.roleId,_that.target,_that.intent,_that.pending,_that.value,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roleId,  ConfigurationRoleReadTarget? target,  int intent,  bool pending,  RoleRouteRead? value,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _SettingsRoleRead() when $default != null:
return $default(_that.roleId,_that.target,_that.intent,_that.pending,_that.value,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsRoleRead implements SettingsRoleRead {
  const _SettingsRoleRead({required this.roleId, required this.target, required this.intent, this.pending = false, this.value, this.error});


@override final  String roleId;
@override final  ConfigurationRoleReadTarget? target;
@override final  int intent;
@override@JsonKey() final  bool pending;
@override final  RoleRouteRead? value;
@override final  StudioFailure? error;

/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsRoleReadCopyWith<_SettingsRoleRead> get copyWith => __$SettingsRoleReadCopyWithImpl<_SettingsRoleRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsRoleRead&&(identical(other.roleId, roleId) || other.roleId == roleId)&&(identical(other.target, target) || other.target == target)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.value, value) || other.value == value)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roleId,target,intent,pending,value,error);
}



}

/// @nodoc
abstract mixin class _$SettingsRoleReadCopyWith<$Res> implements $SettingsRoleReadCopyWith<$Res> {
  factory _$SettingsRoleReadCopyWith(_SettingsRoleRead value, $Res Function(_SettingsRoleRead) _then) = __$SettingsRoleReadCopyWithImpl;
@override @useResult
$Res call({
 String roleId, ConfigurationRoleReadTarget? target, int intent, bool pending, RoleRouteRead? value, StudioFailure? error
});


@override $ConfigurationRoleReadTargetCopyWith<$Res>? get target;@override $RoleRouteReadCopyWith<$Res>? get value;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$SettingsRoleReadCopyWithImpl<$Res>
    implements _$SettingsRoleReadCopyWith<$Res> {
  __$SettingsRoleReadCopyWithImpl(this._self, this._then);

  final _SettingsRoleRead _self;
  final $Res Function(_SettingsRoleRead) _then;

/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roleId = null,Object? target = freezed,Object? intent = null,Object? pending = null,Object? value = freezed,Object? error = freezed,}) {
  return _then(_SettingsRoleRead(
roleId: null == roleId ? _self.roleId : roleId // ignore: cast_nullable_to_non_nullable
as String,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RoleRouteRead?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoleRouteReadCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $RoleRouteReadCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}/// Create a copy of SettingsRoleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$SettingsRoleRoute {

 ConfigurationRoleReadTarget get target; String get accountId; String get modelId; String? get effort; ModelDescriptor? get descriptor; bool get configured;
/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsRoleRouteCopyWith<SettingsRoleRoute> get copyWith => _$SettingsRoleRouteCopyWithImpl<SettingsRoleRoute>(this as SettingsRoleRoute, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsRoleRoute;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsRoleRoute&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.descriptor, _this.descriptor) || other.descriptor == _this.descriptor)&&(identical(other.configured, _this.configured) || other.configured == _this.configured));
}


@override
int get hashCode {
  final _this = this as SettingsRoleRoute;
  return Object.hash(runtimeType,_this.target,_this.accountId,_this.modelId,_this.effort,_this.descriptor,_this.configured);
}

@override
String toString() {
  final _this = this as SettingsRoleRoute;
  return 'SettingsRoleRoute(target: ${_this.target}, accountId: ${_this.accountId}, modelId: ${_this.modelId}, effort: ${_this.effort}, descriptor: ${_this.descriptor}, configured: ${_this.configured})';
}


}

/// @nodoc
abstract mixin class $SettingsRoleRouteCopyWith<$Res>  {
  factory $SettingsRoleRouteCopyWith(SettingsRoleRoute value, $Res Function(SettingsRoleRoute) _then) = _$SettingsRoleRouteCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadTarget target, String accountId, String modelId, String? effort, ModelDescriptor? descriptor, bool configured
});


$ConfigurationRoleReadTargetCopyWith<$Res> get target;$ModelDescriptorCopyWith<$Res>? get descriptor;

}
/// @nodoc
class _$SettingsRoleRouteCopyWithImpl<$Res>
    implements $SettingsRoleRouteCopyWith<$Res> {
  _$SettingsRoleRouteCopyWithImpl(this._self, this._then);

  final SettingsRoleRoute _self;
  final $Res Function(SettingsRoleRoute) _then;

/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? descriptor = freezed,Object? configured = null,}) {
  return _then(SettingsRoleRoute(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,descriptor: freezed == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptor?,configured: null == configured ? _self.configured : configured // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get target {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<$Res>? get descriptor {
    if (_self.descriptor == null) {
    return null;
  }

  return $ModelDescriptorCopyWith<$Res>(_self.descriptor!, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsRoleRoute].
extension SettingsRoleRoutePatterns on SettingsRoleRoute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsRoleRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsRoleRoute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsRoleRoute value)  $default,){
final _that = this;
switch (_that) {
case _SettingsRoleRoute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsRoleRoute value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsRoleRoute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationRoleReadTarget target,  String accountId,  String modelId,  String? effort,  ModelDescriptor? descriptor,  bool configured)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsRoleRoute() when $default != null:
return $default(_that.target,_that.accountId,_that.modelId,_that.effort,_that.descriptor,_that.configured);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationRoleReadTarget target,  String accountId,  String modelId,  String? effort,  ModelDescriptor? descriptor,  bool configured)  $default,) {final _that = this;
switch (_that) {
case _SettingsRoleRoute():
return $default(_that.target,_that.accountId,_that.modelId,_that.effort,_that.descriptor,_that.configured);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationRoleReadTarget target,  String accountId,  String modelId,  String? effort,  ModelDescriptor? descriptor,  bool configured)?  $default,) {final _that = this;
switch (_that) {
case _SettingsRoleRoute() when $default != null:
return $default(_that.target,_that.accountId,_that.modelId,_that.effort,_that.descriptor,_that.configured);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsRoleRoute implements SettingsRoleRoute {
  const _SettingsRoleRoute({required this.target, required this.accountId, required this.modelId, required this.effort, required this.descriptor, required this.configured});


@override final  ConfigurationRoleReadTarget target;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  ModelDescriptor? descriptor;
@override final  bool configured;

/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsRoleRouteCopyWith<_SettingsRoleRoute> get copyWith => __$SettingsRoleRouteCopyWithImpl<_SettingsRoleRoute>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsRoleRoute&&(identical(other.target, target) || other.target == target)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.descriptor, descriptor) || other.descriptor == descriptor)&&(identical(other.configured, configured) || other.configured == configured));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,accountId,modelId,effort,descriptor,configured);
}

@override
String toString() {
    return 'SettingsRoleRoute(target: $target, accountId: $accountId, modelId: $modelId, effort: $effort, descriptor: $descriptor, configured: $configured)';
}


}

/// @nodoc
abstract mixin class _$SettingsRoleRouteCopyWith<$Res> implements $SettingsRoleRouteCopyWith<$Res> {
  factory _$SettingsRoleRouteCopyWith(_SettingsRoleRoute value, $Res Function(_SettingsRoleRoute) _then) = __$SettingsRoleRouteCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationRoleReadTarget target, String accountId, String modelId, String? effort, ModelDescriptor? descriptor, bool configured
});


@override $ConfigurationRoleReadTargetCopyWith<$Res> get target;@override $ModelDescriptorCopyWith<$Res>? get descriptor;

}
/// @nodoc
class __$SettingsRoleRouteCopyWithImpl<$Res>
    implements _$SettingsRoleRouteCopyWith<$Res> {
  __$SettingsRoleRouteCopyWithImpl(this._self, this._then);

  final _SettingsRoleRoute _self;
  final $Res Function(_SettingsRoleRoute) _then;

/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? descriptor = freezed,Object? configured = null,}) {
  return _then(_SettingsRoleRoute(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,descriptor: freezed == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptor?,configured: null == configured ? _self.configured : configured // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get target {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SettingsRoleRoute
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<$Res>? get descriptor {
    if (_self.descriptor == null) {
    return null;
  }

  return $ModelDescriptorCopyWith<$Res>(_self.descriptor!, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}
}

/// @nodoc
mixin _$AgentProfilesViewState {

 ProfilesState get source; ConfigurationState get configurationSource; ModelsState get modelSource; RecoveryState get recoverySource; String get query; Map<String, String> get systemSearchLabels; List<String> get matchingProfileIds; Map<String, SettingsRoleRead> get roleReads; Map<String, SettingsRoleRoute> get routes; Map<(String, AgentProfileAction,), SettingsAction> get actions; Map<(WorktreeOwner, String, int,), SettingsAction> get cleanupActions; SettingsAction? get retryRecoveryAction; ProfileEditorKey? get editor; int get latestIntent; Map<AgentProfilesReadField, StudioFailure> get readIssues; Set<AgentProfilesReadField> get reading;
/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesViewStateCopyWith<AgentProfilesViewState> get copyWith => _$AgentProfilesViewStateCopyWithImpl<AgentProfilesViewState>(this as AgentProfilesViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.configurationSource, _this.configurationSource) || other.configurationSource == _this.configurationSource)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.recoverySource, _this.recoverySource) || other.recoverySource == _this.recoverySource)&&(identical(other.query, _this.query) || other.query == _this.query)&&const DeepCollectionEquality().equals(other.systemSearchLabels, _this.systemSearchLabels)&&const DeepCollectionEquality().equals(other.matchingProfileIds, _this.matchingProfileIds)&&const DeepCollectionEquality().equals(other.roleReads, _this.roleReads)&&const DeepCollectionEquality().equals(other.routes, _this.routes)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&const DeepCollectionEquality().equals(other.cleanupActions, _this.cleanupActions)&&(identical(other.retryRecoveryAction, _this.retryRecoveryAction) || other.retryRecoveryAction == _this.retryRecoveryAction)&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading));
}


@override
int get hashCode {
  final _this = this as AgentProfilesViewState;
  return Object.hash(runtimeType,_this.source,_this.configurationSource,_this.modelSource,_this.recoverySource,_this.query,const DeepCollectionEquality().hash(_this.systemSearchLabels),const DeepCollectionEquality().hash(_this.matchingProfileIds),const DeepCollectionEquality().hash(_this.roleReads),const DeepCollectionEquality().hash(_this.routes),const DeepCollectionEquality().hash(_this.actions),const DeepCollectionEquality().hash(_this.cleanupActions),_this.retryRecoveryAction,_this.editor,_this.latestIntent,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading));
}

@override
String toString() {
  final _this = this as AgentProfilesViewState;
  return 'AgentProfilesViewState(source: ${_this.source}, configurationSource: ${_this.configurationSource}, modelSource: ${_this.modelSource}, recoverySource: ${_this.recoverySource}, query: ${_this.query}, systemSearchLabels: ${_this.systemSearchLabels}, matchingProfileIds: ${_this.matchingProfileIds}, roleReads: ${_this.roleReads}, routes: ${_this.routes}, actions: ${_this.actions}, cleanupActions: ${_this.cleanupActions}, retryRecoveryAction: ${_this.retryRecoveryAction}, editor: ${_this.editor}, latestIntent: ${_this.latestIntent}, readIssues: ${_this.readIssues}, reading: ${_this.reading})';
}


}

/// @nodoc
abstract mixin class $AgentProfilesViewStateCopyWith<$Res>  {
  factory $AgentProfilesViewStateCopyWith(AgentProfilesViewState value, $Res Function(AgentProfilesViewState) _then) = _$AgentProfilesViewStateCopyWithImpl;
@useResult
$Res call({
 ProfilesState source, ConfigurationState configurationSource, ModelsState modelSource, RecoveryState recoverySource, String query, Map<String, String> systemSearchLabels, List<String> matchingProfileIds, Map<String, SettingsRoleRead> roleReads, Map<String, SettingsRoleRoute> routes, Map<(String, AgentProfileAction,), SettingsAction> actions, Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions, SettingsAction? retryRecoveryAction, ProfileEditorKey? editor, int latestIntent, Map<AgentProfilesReadField, StudioFailure> readIssues, Set<AgentProfilesReadField> reading
});


$ProfilesStateCopyWith<$Res> get source;$ConfigurationStateCopyWith<$Res> get configurationSource;$ModelsStateCopyWith<$Res> get modelSource;$RecoveryStateCopyWith<$Res> get recoverySource;$SettingsActionCopyWith<$Res>? get retryRecoveryAction;$ProfileEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class _$AgentProfilesViewStateCopyWithImpl<$Res>
    implements $AgentProfilesViewStateCopyWith<$Res> {
  _$AgentProfilesViewStateCopyWithImpl(this._self, this._then);

  final AgentProfilesViewState _self;
  final $Res Function(AgentProfilesViewState) _then;

/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? configurationSource = null,Object? modelSource = null,Object? recoverySource = null,Object? query = null,Object? systemSearchLabels = null,Object? matchingProfileIds = null,Object? roleReads = null,Object? routes = null,Object? actions = null,Object? cleanupActions = null,Object? retryRecoveryAction = freezed,Object? editor = freezed,Object? latestIntent = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(AgentProfilesViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ProfilesState,configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,recoverySource: null == recoverySource ? _self.recoverySource : recoverySource // ignore: cast_nullable_to_non_nullable
as RecoveryState,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,systemSearchLabels: null == systemSearchLabels ? _self.systemSearchLabels : systemSearchLabels // ignore: cast_nullable_to_non_nullable
as Map<String, String>,matchingProfileIds: null == matchingProfileIds ? _self.matchingProfileIds : matchingProfileIds // ignore: cast_nullable_to_non_nullable
as List<String>,roleReads: null == roleReads ? _self.roleReads : roleReads // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsRoleRead>,routes: null == routes ? _self.routes : routes // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsRoleRoute>,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<(String, AgentProfileAction,), SettingsAction>,cleanupActions: null == cleanupActions ? _self.cleanupActions : cleanupActions // ignore: cast_nullable_to_non_nullable
as Map<(WorktreeOwner, String, int,), SettingsAction>,retryRecoveryAction: freezed == retryRecoveryAction ? _self.retryRecoveryAction : retryRecoveryAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<AgentProfilesReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<AgentProfilesReadField>,
  ));
}
/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfilesStateCopyWith<$Res> get source {

  return $ProfilesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<$Res> get recoverySource {

  return $RecoveryStateCopyWith<$Res>(_self.recoverySource, (value) {
    return _then(_self.copyWith(recoverySource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get retryRecoveryAction {
    if (_self.retryRecoveryAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.retryRecoveryAction!, (value) {
    return _then(_self.copyWith(retryRecoveryAction: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $ProfileEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfilesViewState].
extension AgentProfilesViewStatePatterns on AgentProfilesViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesViewState value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProfilesState source,  ConfigurationState configurationSource,  ModelsState modelSource,  RecoveryState recoverySource,  String query,  Map<String, String> systemSearchLabels,  List<String> matchingProfileIds,  Map<String, SettingsRoleRead> roleReads,  Map<String, SettingsRoleRoute> routes,  Map<(String, AgentProfileAction,), SettingsAction> actions,  Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions,  SettingsAction? retryRecoveryAction,  ProfileEditorKey? editor,  int latestIntent,  Map<AgentProfilesReadField, StudioFailure> readIssues,  Set<AgentProfilesReadField> reading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfilesViewState() when $default != null:
return $default(_that.source,_that.configurationSource,_that.modelSource,_that.recoverySource,_that.query,_that.systemSearchLabels,_that.matchingProfileIds,_that.roleReads,_that.routes,_that.actions,_that.cleanupActions,_that.retryRecoveryAction,_that.editor,_that.latestIntent,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProfilesState source,  ConfigurationState configurationSource,  ModelsState modelSource,  RecoveryState recoverySource,  String query,  Map<String, String> systemSearchLabels,  List<String> matchingProfileIds,  Map<String, SettingsRoleRead> roleReads,  Map<String, SettingsRoleRoute> routes,  Map<(String, AgentProfileAction,), SettingsAction> actions,  Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions,  SettingsAction? retryRecoveryAction,  ProfileEditorKey? editor,  int latestIntent,  Map<AgentProfilesReadField, StudioFailure> readIssues,  Set<AgentProfilesReadField> reading)  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesViewState():
return $default(_that.source,_that.configurationSource,_that.modelSource,_that.recoverySource,_that.query,_that.systemSearchLabels,_that.matchingProfileIds,_that.roleReads,_that.routes,_that.actions,_that.cleanupActions,_that.retryRecoveryAction,_that.editor,_that.latestIntent,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProfilesState source,  ConfigurationState configurationSource,  ModelsState modelSource,  RecoveryState recoverySource,  String query,  Map<String, String> systemSearchLabels,  List<String> matchingProfileIds,  Map<String, SettingsRoleRead> roleReads,  Map<String, SettingsRoleRoute> routes,  Map<(String, AgentProfileAction,), SettingsAction> actions,  Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions,  SettingsAction? retryRecoveryAction,  ProfileEditorKey? editor,  int latestIntent,  Map<AgentProfilesReadField, StudioFailure> readIssues,  Set<AgentProfilesReadField> reading)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesViewState() when $default != null:
return $default(_that.source,_that.configurationSource,_that.modelSource,_that.recoverySource,_that.query,_that.systemSearchLabels,_that.matchingProfileIds,_that.roleReads,_that.routes,_that.actions,_that.cleanupActions,_that.retryRecoveryAction,_that.editor,_that.latestIntent,_that.readIssues,_that.reading);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesViewState implements AgentProfilesViewState {
  const _AgentProfilesViewState({required this.source, required this.configurationSource, required this.modelSource, required this.recoverySource, this.query = '',  Map<String, String> systemSearchLabels = const {},  List<String> matchingProfileIds = const [],  Map<String, SettingsRoleRead> roleReads = const {},  Map<String, SettingsRoleRoute> routes = const {},  Map<(String, AgentProfileAction,), SettingsAction> actions = const {},  Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions = const {}, this.retryRecoveryAction, this.editor, this.latestIntent = 0,  Map<AgentProfilesReadField, StudioFailure> readIssues = const {},  Set<AgentProfilesReadField> reading = const {}}): _systemSearchLabels = systemSearchLabels,_matchingProfileIds = matchingProfileIds,_roleReads = roleReads,_routes = routes,_actions = actions,_cleanupActions = cleanupActions,_readIssues = readIssues,_reading = reading;


@override final  ProfilesState source;
@override final  ConfigurationState configurationSource;
@override final  ModelsState modelSource;
@override final  RecoveryState recoverySource;
@override@JsonKey() final  String query;
 final  Map<String, String> _systemSearchLabels;
@override@JsonKey() Map<String, String> get systemSearchLabels {
  if (_systemSearchLabels is EqualUnmodifiableMapView) return _systemSearchLabels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_systemSearchLabels);
}

 final  List<String> _matchingProfileIds;
@override@JsonKey() List<String> get matchingProfileIds {
  if (_matchingProfileIds is EqualUnmodifiableListView) return _matchingProfileIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_matchingProfileIds);
}

 final  Map<String, SettingsRoleRead> _roleReads;
@override@JsonKey() Map<String, SettingsRoleRead> get roleReads {
  if (_roleReads is EqualUnmodifiableMapView) return _roleReads;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_roleReads);
}

 final  Map<String, SettingsRoleRoute> _routes;
@override@JsonKey() Map<String, SettingsRoleRoute> get routes {
  if (_routes is EqualUnmodifiableMapView) return _routes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_routes);
}

 final  Map<(String, AgentProfileAction,), SettingsAction> _actions;
@override@JsonKey() Map<(String, AgentProfileAction,), SettingsAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

 final  Map<(WorktreeOwner, String, int,), SettingsAction> _cleanupActions;
@override@JsonKey() Map<(WorktreeOwner, String, int,), SettingsAction> get cleanupActions {
  if (_cleanupActions is EqualUnmodifiableMapView) return _cleanupActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_cleanupActions);
}

@override final  SettingsAction? retryRecoveryAction;
@override final  ProfileEditorKey? editor;
@override@JsonKey() final  int latestIntent;
 final  Map<AgentProfilesReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<AgentProfilesReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<AgentProfilesReadField> _reading;
@override@JsonKey() Set<AgentProfilesReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}


/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesViewStateCopyWith<_AgentProfilesViewState> get copyWith => __$AgentProfilesViewStateCopyWithImpl<_AgentProfilesViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.configurationSource, configurationSource) || other.configurationSource == configurationSource)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.recoverySource, recoverySource) || other.recoverySource == recoverySource)&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.systemSearchLabels, _systemSearchLabels)&&const DeepCollectionEquality().equals(other.matchingProfileIds, _matchingProfileIds)&&const DeepCollectionEquality().equals(other.roleReads, _roleReads)&&const DeepCollectionEquality().equals(other.routes, _routes)&&const DeepCollectionEquality().equals(other.actions, _actions)&&const DeepCollectionEquality().equals(other.cleanupActions, _cleanupActions)&&(identical(other.retryRecoveryAction, retryRecoveryAction) || other.retryRecoveryAction == retryRecoveryAction)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,configurationSource,modelSource,recoverySource,query,const DeepCollectionEquality().hash(_systemSearchLabels),const DeepCollectionEquality().hash(_matchingProfileIds),const DeepCollectionEquality().hash(_roleReads),const DeepCollectionEquality().hash(_routes),const DeepCollectionEquality().hash(_actions),const DeepCollectionEquality().hash(_cleanupActions),retryRecoveryAction,editor,latestIntent,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading));
}

@override
String toString() {
    return 'AgentProfilesViewState(source: $source, configurationSource: $configurationSource, modelSource: $modelSource, recoverySource: $recoverySource, query: $query, systemSearchLabels: $systemSearchLabels, matchingProfileIds: $matchingProfileIds, roleReads: $roleReads, routes: $routes, actions: $actions, cleanupActions: $cleanupActions, retryRecoveryAction: $retryRecoveryAction, editor: $editor, latestIntent: $latestIntent, readIssues: $readIssues, reading: $reading)';
}


}

/// @nodoc
abstract mixin class _$AgentProfilesViewStateCopyWith<$Res> implements $AgentProfilesViewStateCopyWith<$Res> {
  factory _$AgentProfilesViewStateCopyWith(_AgentProfilesViewState value, $Res Function(_AgentProfilesViewState) _then) = __$AgentProfilesViewStateCopyWithImpl;
@override @useResult
$Res call({
 ProfilesState source, ConfigurationState configurationSource, ModelsState modelSource, RecoveryState recoverySource, String query, Map<String, String> systemSearchLabels, List<String> matchingProfileIds, Map<String, SettingsRoleRead> roleReads, Map<String, SettingsRoleRoute> routes, Map<(String, AgentProfileAction,), SettingsAction> actions, Map<(WorktreeOwner, String, int,), SettingsAction> cleanupActions, SettingsAction? retryRecoveryAction, ProfileEditorKey? editor, int latestIntent, Map<AgentProfilesReadField, StudioFailure> readIssues, Set<AgentProfilesReadField> reading
});


@override $ProfilesStateCopyWith<$Res> get source;@override $ConfigurationStateCopyWith<$Res> get configurationSource;@override $ModelsStateCopyWith<$Res> get modelSource;@override $RecoveryStateCopyWith<$Res> get recoverySource;@override $SettingsActionCopyWith<$Res>? get retryRecoveryAction;@override $ProfileEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class __$AgentProfilesViewStateCopyWithImpl<$Res>
    implements _$AgentProfilesViewStateCopyWith<$Res> {
  __$AgentProfilesViewStateCopyWithImpl(this._self, this._then);

  final _AgentProfilesViewState _self;
  final $Res Function(_AgentProfilesViewState) _then;

/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? configurationSource = null,Object? modelSource = null,Object? recoverySource = null,Object? query = null,Object? systemSearchLabels = null,Object? matchingProfileIds = null,Object? roleReads = null,Object? routes = null,Object? actions = null,Object? cleanupActions = null,Object? retryRecoveryAction = freezed,Object? editor = freezed,Object? latestIntent = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(_AgentProfilesViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ProfilesState,configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,recoverySource: null == recoverySource ? _self.recoverySource : recoverySource // ignore: cast_nullable_to_non_nullable
as RecoveryState,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,systemSearchLabels: null == systemSearchLabels ? _self._systemSearchLabels : systemSearchLabels // ignore: cast_nullable_to_non_nullable
as Map<String, String>,matchingProfileIds: null == matchingProfileIds ? _self._matchingProfileIds : matchingProfileIds // ignore: cast_nullable_to_non_nullable
as List<String>,roleReads: null == roleReads ? _self._roleReads : roleReads // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsRoleRead>,routes: null == routes ? _self._routes : routes // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsRoleRoute>,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<(String, AgentProfileAction,), SettingsAction>,cleanupActions: null == cleanupActions ? _self._cleanupActions : cleanupActions // ignore: cast_nullable_to_non_nullable
as Map<(WorktreeOwner, String, int,), SettingsAction>,retryRecoveryAction: freezed == retryRecoveryAction ? _self.retryRecoveryAction : retryRecoveryAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<AgentProfilesReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<AgentProfilesReadField>,
  ));
}

/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfilesStateCopyWith<$Res> get source {

  return $ProfilesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<$Res> get recoverySource {

  return $RecoveryStateCopyWith<$Res>(_self.recoverySource, (value) {
    return _then(_self.copyWith(recoverySource: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get retryRecoveryAction {
    if (_self.retryRecoveryAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.retryRecoveryAction!, (value) {
    return _then(_self.copyWith(retryRecoveryAction: value));
  });
}/// Create a copy of AgentProfilesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $ProfileEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}

// dart format on
