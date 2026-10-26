// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots_commands_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SaveBotRequest {

 OperationId get operationId; String? get botId; int get expectedConfigRevision; String get name; String get projectId; String get appId; BotSecretUpdate get secret; bool get enabled; bool get toolsEnabled; BotModelRoute? get modelRoute;
/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SaveBotRequestCopyWith<SaveBotRequest> get copyWith => _$SaveBotRequestCopyWithImpl<SaveBotRequest>(this as SaveBotRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SaveBotRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveBotRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.appId, _this.appId) || other.appId == _this.appId)&&(identical(other.secret, _this.secret) || other.secret == _this.secret)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.toolsEnabled, _this.toolsEnabled) || other.toolsEnabled == _this.toolsEnabled)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute));
}


@override
int get hashCode {
  final _this = this as SaveBotRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.expectedConfigRevision,_this.name,_this.projectId,_this.appId,_this.secret,_this.enabled,_this.toolsEnabled,_this.modelRoute);
}



}

/// @nodoc
abstract mixin class $SaveBotRequestCopyWith<$Res>  {
  factory $SaveBotRequestCopyWith(SaveBotRequest value, $Res Function(SaveBotRequest) _then) = _$SaveBotRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String? botId, int expectedConfigRevision, String name, String projectId, String appId, BotSecretUpdate secret, bool enabled, bool toolsEnabled, BotModelRoute? modelRoute
});


$OperationIdCopyWith<$Res> get operationId;$BotSecretUpdateCopyWith<$Res> get secret;$BotModelRouteCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class _$SaveBotRequestCopyWithImpl<$Res>
    implements $SaveBotRequestCopyWith<$Res> {
  _$SaveBotRequestCopyWithImpl(this._self, this._then);

  final SaveBotRequest _self;
  final $Res Function(SaveBotRequest) _then;

/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = freezed,Object? expectedConfigRevision = null,Object? name = null,Object? projectId = null,Object? appId = null,Object? secret = null,Object? enabled = null,Object? toolsEnabled = null,Object? modelRoute = freezed,}) {
  return _then(SaveBotRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as BotSecretUpdate,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as BotModelRoute?,
  ));
}
/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSecretUpdateCopyWith<$Res> get secret {

  return $BotSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $BotModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}


/// Adds pattern-matching-related methods to [SaveBotRequest].
extension SaveBotRequestPatterns on SaveBotRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SaveBotRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SaveBotRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SaveBotRequest value)  $default,){
final _that = this;
switch (_that) {
case _SaveBotRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SaveBotRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SaveBotRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SaveBotRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)  $default,) {final _that = this;
switch (_that) {
case _SaveBotRequest():
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)?  $default,) {final _that = this;
switch (_that) {
case _SaveBotRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
  return null;

}
}

}

/// @nodoc


class _SaveBotRequest implements SaveBotRequest {
  const _SaveBotRequest({required this.operationId, required this.botId, required this.expectedConfigRevision, required this.name, required this.projectId, required this.appId, required this.secret, required this.enabled, required this.toolsEnabled, required this.modelRoute});


@override final  OperationId operationId;
@override final  String? botId;
@override final  int expectedConfigRevision;
@override final  String name;
@override final  String projectId;
@override final  String appId;
@override final  BotSecretUpdate secret;
@override final  bool enabled;
@override final  bool toolsEnabled;
@override final  BotModelRoute? modelRoute;

/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SaveBotRequestCopyWith<_SaveBotRequest> get copyWith => __$SaveBotRequestCopyWithImpl<_SaveBotRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SaveBotRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.name, name) || other.name == name)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.appId, appId) || other.appId == appId)&&(identical(other.secret, secret) || other.secret == secret)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.modelRoute, modelRoute) || other.modelRoute == modelRoute));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId,expectedConfigRevision,name,projectId,appId,secret,enabled,toolsEnabled,modelRoute);
}



}

/// @nodoc
abstract mixin class _$SaveBotRequestCopyWith<$Res> implements $SaveBotRequestCopyWith<$Res> {
  factory _$SaveBotRequestCopyWith(_SaveBotRequest value, $Res Function(_SaveBotRequest) _then) = __$SaveBotRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String? botId, int expectedConfigRevision, String name, String projectId, String appId, BotSecretUpdate secret, bool enabled, bool toolsEnabled, BotModelRoute? modelRoute
});


@override $OperationIdCopyWith<$Res> get operationId;@override $BotSecretUpdateCopyWith<$Res> get secret;@override $BotModelRouteCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class __$SaveBotRequestCopyWithImpl<$Res>
    implements _$SaveBotRequestCopyWith<$Res> {
  __$SaveBotRequestCopyWithImpl(this._self, this._then);

  final _SaveBotRequest _self;
  final $Res Function(_SaveBotRequest) _then;

/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = freezed,Object? expectedConfigRevision = null,Object? name = null,Object? projectId = null,Object? appId = null,Object? secret = null,Object? enabled = null,Object? toolsEnabled = null,Object? modelRoute = freezed,}) {
  return _then(_SaveBotRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as BotSecretUpdate,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as BotModelRoute?,
  ));
}

/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSecretUpdateCopyWith<$Res> get secret {

  return $BotSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}/// Create a copy of SaveBotRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $BotModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}

/// @nodoc
mixin _$StartBotRegistrationRequest {

 OperationId get operationId; String get name; String get projectId;
/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartBotRegistrationRequestCopyWith<StartBotRegistrationRequest> get copyWith => _$StartBotRegistrationRequestCopyWithImpl<StartBotRegistrationRequest>(this as StartBotRegistrationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartBotRegistrationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartBotRegistrationRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId));
}


@override
int get hashCode {
  final _this = this as StartBotRegistrationRequest;
  return Object.hash(runtimeType,_this.operationId,_this.name,_this.projectId);
}



}

/// @nodoc
abstract mixin class $StartBotRegistrationRequestCopyWith<$Res>  {
  factory $StartBotRegistrationRequestCopyWith(StartBotRegistrationRequest value, $Res Function(StartBotRegistrationRequest) _then) = _$StartBotRegistrationRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String name, String projectId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$StartBotRegistrationRequestCopyWithImpl<$Res>
    implements $StartBotRegistrationRequestCopyWith<$Res> {
  _$StartBotRegistrationRequestCopyWithImpl(this._self, this._then);

  final StartBotRegistrationRequest _self;
  final $Res Function(StartBotRegistrationRequest) _then;

/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? name = null,Object? projectId = null,}) {
  return _then(StartBotRegistrationRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartBotRegistrationRequest].
extension StartBotRegistrationRequestPatterns on StartBotRegistrationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartBotRegistrationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartBotRegistrationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartBotRegistrationRequest value)  $default,){
final _that = this;
switch (_that) {
case _StartBotRegistrationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartBotRegistrationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _StartBotRegistrationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String name,  String projectId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartBotRegistrationRequest() when $default != null:
return $default(_that.operationId,_that.name,_that.projectId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String name,  String projectId)  $default,) {final _that = this;
switch (_that) {
case _StartBotRegistrationRequest():
return $default(_that.operationId,_that.name,_that.projectId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String name,  String projectId)?  $default,) {final _that = this;
switch (_that) {
case _StartBotRegistrationRequest() when $default != null:
return $default(_that.operationId,_that.name,_that.projectId);case _:
  return null;

}
}

}

/// @nodoc


class _StartBotRegistrationRequest implements StartBotRegistrationRequest {
  const _StartBotRegistrationRequest({required this.operationId, required this.name, required this.projectId});


@override final  OperationId operationId;
@override final  String name;
@override final  String projectId;

/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartBotRegistrationRequestCopyWith<_StartBotRegistrationRequest> get copyWith => __$StartBotRegistrationRequestCopyWithImpl<_StartBotRegistrationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartBotRegistrationRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.name, name) || other.name == name)&&(identical(other.projectId, projectId) || other.projectId == projectId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,name,projectId);
}



}

/// @nodoc
abstract mixin class _$StartBotRegistrationRequestCopyWith<$Res> implements $StartBotRegistrationRequestCopyWith<$Res> {
  factory _$StartBotRegistrationRequestCopyWith(_StartBotRegistrationRequest value, $Res Function(_StartBotRegistrationRequest) _then) = __$StartBotRegistrationRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String name, String projectId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$StartBotRegistrationRequestCopyWithImpl<$Res>
    implements _$StartBotRegistrationRequestCopyWith<$Res> {
  __$StartBotRegistrationRequestCopyWithImpl(this._self, this._then);

  final _StartBotRegistrationRequest _self;
  final $Res Function(_StartBotRegistrationRequest) _then;

/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? name = null,Object? projectId = null,}) {
  return _then(_StartBotRegistrationRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of StartBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$CancelBotRegistrationRequest {

 OperationId get operationId; String get attemptId;
/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelBotRegistrationRequestCopyWith<CancelBotRegistrationRequest> get copyWith => _$CancelBotRegistrationRequestCopyWithImpl<CancelBotRegistrationRequest>(this as CancelBotRegistrationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CancelBotRegistrationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelBotRegistrationRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId));
}


@override
int get hashCode {
  final _this = this as CancelBotRegistrationRequest;
  return Object.hash(runtimeType,_this.operationId,_this.attemptId);
}

@override
String toString() {
  final _this = this as CancelBotRegistrationRequest;
  return 'CancelBotRegistrationRequest(operationId: ${_this.operationId}, attemptId: ${_this.attemptId})';
}


}

/// @nodoc
abstract mixin class $CancelBotRegistrationRequestCopyWith<$Res>  {
  factory $CancelBotRegistrationRequestCopyWith(CancelBotRegistrationRequest value, $Res Function(CancelBotRegistrationRequest) _then) = _$CancelBotRegistrationRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String attemptId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$CancelBotRegistrationRequestCopyWithImpl<$Res>
    implements $CancelBotRegistrationRequestCopyWith<$Res> {
  _$CancelBotRegistrationRequestCopyWithImpl(this._self, this._then);

  final CancelBotRegistrationRequest _self;
  final $Res Function(CancelBotRegistrationRequest) _then;

/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? attemptId = null,}) {
  return _then(CancelBotRegistrationRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [CancelBotRegistrationRequest].
extension CancelBotRegistrationRequestPatterns on CancelBotRegistrationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CancelBotRegistrationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CancelBotRegistrationRequest value)  $default,){
final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CancelBotRegistrationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String attemptId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest() when $default != null:
return $default(_that.operationId,_that.attemptId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String attemptId)  $default,) {final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest():
return $default(_that.operationId,_that.attemptId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String attemptId)?  $default,) {final _that = this;
switch (_that) {
case _CancelBotRegistrationRequest() when $default != null:
return $default(_that.operationId,_that.attemptId);case _:
  return null;

}
}

}

/// @nodoc


class _CancelBotRegistrationRequest implements CancelBotRegistrationRequest {
  const _CancelBotRegistrationRequest({required this.operationId, required this.attemptId});


@override final  OperationId operationId;
@override final  String attemptId;

/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CancelBotRegistrationRequestCopyWith<_CancelBotRegistrationRequest> get copyWith => __$CancelBotRegistrationRequestCopyWithImpl<_CancelBotRegistrationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CancelBotRegistrationRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,attemptId);
}

@override
String toString() {
    return 'CancelBotRegistrationRequest(operationId: $operationId, attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class _$CancelBotRegistrationRequestCopyWith<$Res> implements $CancelBotRegistrationRequestCopyWith<$Res> {
  factory _$CancelBotRegistrationRequestCopyWith(_CancelBotRegistrationRequest value, $Res Function(_CancelBotRegistrationRequest) _then) = __$CancelBotRegistrationRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String attemptId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$CancelBotRegistrationRequestCopyWithImpl<$Res>
    implements _$CancelBotRegistrationRequestCopyWith<$Res> {
  __$CancelBotRegistrationRequestCopyWithImpl(this._self, this._then);

  final _CancelBotRegistrationRequest _self;
  final $Res Function(_CancelBotRegistrationRequest) _then;

/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? attemptId = null,}) {
  return _then(_CancelBotRegistrationRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of CancelBotRegistrationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$SetBotEnabledRequest {

 OperationId get operationId; String get botId; int get expectedConfigRevision; bool get enabled;
/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetBotEnabledRequestCopyWith<SetBotEnabledRequest> get copyWith => _$SetBotEnabledRequestCopyWithImpl<SetBotEnabledRequest>(this as SetBotEnabledRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetBotEnabledRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetBotEnabledRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled));
}


@override
int get hashCode {
  final _this = this as SetBotEnabledRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.expectedConfigRevision,_this.enabled);
}

@override
String toString() {
  final _this = this as SetBotEnabledRequest;
  return 'SetBotEnabledRequest(operationId: ${_this.operationId}, botId: ${_this.botId}, expectedConfigRevision: ${_this.expectedConfigRevision}, enabled: ${_this.enabled})';
}


}

/// @nodoc
abstract mixin class $SetBotEnabledRequestCopyWith<$Res>  {
  factory $SetBotEnabledRequestCopyWith(SetBotEnabledRequest value, $Res Function(SetBotEnabledRequest) _then) = _$SetBotEnabledRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, bool enabled
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetBotEnabledRequestCopyWithImpl<$Res>
    implements $SetBotEnabledRequestCopyWith<$Res> {
  _$SetBotEnabledRequestCopyWithImpl(this._self, this._then);

  final SetBotEnabledRequest _self;
  final $Res Function(SetBotEnabledRequest) _then;

/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? enabled = null,}) {
  return _then(SetBotEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetBotEnabledRequest].
extension SetBotEnabledRequestPatterns on SetBotEnabledRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetBotEnabledRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetBotEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetBotEnabledRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetBotEnabledRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetBotEnabledRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetBotEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetBotEnabledRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  bool enabled)  $default,) {final _that = this;
switch (_that) {
case _SetBotEnabledRequest():
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String botId,  int expectedConfigRevision,  bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _SetBotEnabledRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.enabled);case _:
  return null;

}
}

}

/// @nodoc


class _SetBotEnabledRequest implements SetBotEnabledRequest {
  const _SetBotEnabledRequest({required this.operationId, required this.botId, required this.expectedConfigRevision, required this.enabled});


@override final  OperationId operationId;
@override final  String botId;
@override final  int expectedConfigRevision;
@override final  bool enabled;

/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetBotEnabledRequestCopyWith<_SetBotEnabledRequest> get copyWith => __$SetBotEnabledRequestCopyWithImpl<_SetBotEnabledRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetBotEnabledRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId,expectedConfigRevision,enabled);
}

@override
String toString() {
    return 'SetBotEnabledRequest(operationId: $operationId, botId: $botId, expectedConfigRevision: $expectedConfigRevision, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$SetBotEnabledRequestCopyWith<$Res> implements $SetBotEnabledRequestCopyWith<$Res> {
  factory _$SetBotEnabledRequestCopyWith(_SetBotEnabledRequest value, $Res Function(_SetBotEnabledRequest) _then) = __$SetBotEnabledRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, bool enabled
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetBotEnabledRequestCopyWithImpl<$Res>
    implements _$SetBotEnabledRequestCopyWith<$Res> {
  __$SetBotEnabledRequestCopyWithImpl(this._self, this._then);

  final _SetBotEnabledRequest _self;
  final $Res Function(_SetBotEnabledRequest) _then;

/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? enabled = null,}) {
  return _then(_SetBotEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SetBotEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$RetryBotConnectionRequest {

 OperationId get operationId; String get botId;
/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryBotConnectionRequestCopyWith<RetryBotConnectionRequest> get copyWith => _$RetryBotConnectionRequestCopyWithImpl<RetryBotConnectionRequest>(this as RetryBotConnectionRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RetryBotConnectionRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryBotConnectionRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId));
}


@override
int get hashCode {
  final _this = this as RetryBotConnectionRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId);
}

@override
String toString() {
  final _this = this as RetryBotConnectionRequest;
  return 'RetryBotConnectionRequest(operationId: ${_this.operationId}, botId: ${_this.botId})';
}


}

/// @nodoc
abstract mixin class $RetryBotConnectionRequestCopyWith<$Res>  {
  factory $RetryBotConnectionRequestCopyWith(RetryBotConnectionRequest value, $Res Function(RetryBotConnectionRequest) _then) = _$RetryBotConnectionRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$RetryBotConnectionRequestCopyWithImpl<$Res>
    implements $RetryBotConnectionRequestCopyWith<$Res> {
  _$RetryBotConnectionRequestCopyWithImpl(this._self, this._then);

  final RetryBotConnectionRequest _self;
  final $Res Function(RetryBotConnectionRequest) _then;

/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,}) {
  return _then(RetryBotConnectionRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [RetryBotConnectionRequest].
extension RetryBotConnectionRequestPatterns on RetryBotConnectionRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RetryBotConnectionRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RetryBotConnectionRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RetryBotConnectionRequest value)  $default,){
final _that = this;
switch (_that) {
case _RetryBotConnectionRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RetryBotConnectionRequest value)?  $default,){
final _that = this;
switch (_that) {
case _RetryBotConnectionRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String botId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RetryBotConnectionRequest() when $default != null:
return $default(_that.operationId,_that.botId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String botId)  $default,) {final _that = this;
switch (_that) {
case _RetryBotConnectionRequest():
return $default(_that.operationId,_that.botId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String botId)?  $default,) {final _that = this;
switch (_that) {
case _RetryBotConnectionRequest() when $default != null:
return $default(_that.operationId,_that.botId);case _:
  return null;

}
}

}

/// @nodoc


class _RetryBotConnectionRequest implements RetryBotConnectionRequest {
  const _RetryBotConnectionRequest({required this.operationId, required this.botId});


@override final  OperationId operationId;
@override final  String botId;

/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RetryBotConnectionRequestCopyWith<_RetryBotConnectionRequest> get copyWith => __$RetryBotConnectionRequestCopyWithImpl<_RetryBotConnectionRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RetryBotConnectionRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId);
}

@override
String toString() {
    return 'RetryBotConnectionRequest(operationId: $operationId, botId: $botId)';
}


}

/// @nodoc
abstract mixin class _$RetryBotConnectionRequestCopyWith<$Res> implements $RetryBotConnectionRequestCopyWith<$Res> {
  factory _$RetryBotConnectionRequestCopyWith(_RetryBotConnectionRequest value, $Res Function(_RetryBotConnectionRequest) _then) = __$RetryBotConnectionRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String botId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$RetryBotConnectionRequestCopyWithImpl<$Res>
    implements _$RetryBotConnectionRequestCopyWith<$Res> {
  __$RetryBotConnectionRequestCopyWithImpl(this._self, this._then);

  final _RetryBotConnectionRequest _self;
  final $Res Function(_RetryBotConnectionRequest) _then;

/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = null,}) {
  return _then(_RetryBotConnectionRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of RetryBotConnectionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$SetBotTrustedUserRequest {

 OperationId get operationId; String get botId; int get expectedConfigRevision; String get openId; bool get trusted;
/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetBotTrustedUserRequestCopyWith<SetBotTrustedUserRequest> get copyWith => _$SetBotTrustedUserRequestCopyWithImpl<SetBotTrustedUserRequest>(this as SetBotTrustedUserRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetBotTrustedUserRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetBotTrustedUserRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.openId, _this.openId) || other.openId == _this.openId)&&(identical(other.trusted, _this.trusted) || other.trusted == _this.trusted));
}


@override
int get hashCode {
  final _this = this as SetBotTrustedUserRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.expectedConfigRevision,_this.openId,_this.trusted);
}

@override
String toString() {
  final _this = this as SetBotTrustedUserRequest;
  return 'SetBotTrustedUserRequest(operationId: ${_this.operationId}, botId: ${_this.botId}, expectedConfigRevision: ${_this.expectedConfigRevision}, openId: ${_this.openId}, trusted: ${_this.trusted})';
}


}

/// @nodoc
abstract mixin class $SetBotTrustedUserRequestCopyWith<$Res>  {
  factory $SetBotTrustedUserRequestCopyWith(SetBotTrustedUserRequest value, $Res Function(SetBotTrustedUserRequest) _then) = _$SetBotTrustedUserRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, String openId, bool trusted
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetBotTrustedUserRequestCopyWithImpl<$Res>
    implements $SetBotTrustedUserRequestCopyWith<$Res> {
  _$SetBotTrustedUserRequestCopyWithImpl(this._self, this._then);

  final SetBotTrustedUserRequest _self;
  final $Res Function(SetBotTrustedUserRequest) _then;

/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? openId = null,Object? trusted = null,}) {
  return _then(SetBotTrustedUserRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,openId: null == openId ? _self.openId : openId // ignore: cast_nullable_to_non_nullable
as String,trusted: null == trusted ? _self.trusted : trusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetBotTrustedUserRequest].
extension SetBotTrustedUserRequestPatterns on SetBotTrustedUserRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetBotTrustedUserRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetBotTrustedUserRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetBotTrustedUserRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String openId,  bool trusted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.openId,_that.trusted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String openId,  bool trusted)  $default,) {final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest():
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.openId,_that.trusted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String openId,  bool trusted)?  $default,) {final _that = this;
switch (_that) {
case _SetBotTrustedUserRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.openId,_that.trusted);case _:
  return null;

}
}

}

/// @nodoc


class _SetBotTrustedUserRequest implements SetBotTrustedUserRequest {
  const _SetBotTrustedUserRequest({required this.operationId, required this.botId, required this.expectedConfigRevision, required this.openId, required this.trusted});


@override final  OperationId operationId;
@override final  String botId;
@override final  int expectedConfigRevision;
@override final  String openId;
@override final  bool trusted;

/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetBotTrustedUserRequestCopyWith<_SetBotTrustedUserRequest> get copyWith => __$SetBotTrustedUserRequestCopyWithImpl<_SetBotTrustedUserRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetBotTrustedUserRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.openId, openId) || other.openId == openId)&&(identical(other.trusted, trusted) || other.trusted == trusted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId,expectedConfigRevision,openId,trusted);
}

@override
String toString() {
    return 'SetBotTrustedUserRequest(operationId: $operationId, botId: $botId, expectedConfigRevision: $expectedConfigRevision, openId: $openId, trusted: $trusted)';
}


}

/// @nodoc
abstract mixin class _$SetBotTrustedUserRequestCopyWith<$Res> implements $SetBotTrustedUserRequestCopyWith<$Res> {
  factory _$SetBotTrustedUserRequestCopyWith(_SetBotTrustedUserRequest value, $Res Function(_SetBotTrustedUserRequest) _then) = __$SetBotTrustedUserRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, String openId, bool trusted
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetBotTrustedUserRequestCopyWithImpl<$Res>
    implements _$SetBotTrustedUserRequestCopyWith<$Res> {
  __$SetBotTrustedUserRequestCopyWithImpl(this._self, this._then);

  final _SetBotTrustedUserRequest _self;
  final $Res Function(_SetBotTrustedUserRequest) _then;

/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? openId = null,Object? trusted = null,}) {
  return _then(_SetBotTrustedUserRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,openId: null == openId ? _self.openId : openId // ignore: cast_nullable_to_non_nullable
as String,trusted: null == trusted ? _self.trusted : trusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SetBotTrustedUserRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$SetBotTrustedChatRequest {

 OperationId get operationId; String get botId; int get expectedConfigRevision; String get chatId; bool get trusted;
/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetBotTrustedChatRequestCopyWith<SetBotTrustedChatRequest> get copyWith => _$SetBotTrustedChatRequestCopyWithImpl<SetBotTrustedChatRequest>(this as SetBotTrustedChatRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetBotTrustedChatRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetBotTrustedChatRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.trusted, _this.trusted) || other.trusted == _this.trusted));
}


@override
int get hashCode {
  final _this = this as SetBotTrustedChatRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.expectedConfigRevision,_this.chatId,_this.trusted);
}

@override
String toString() {
  final _this = this as SetBotTrustedChatRequest;
  return 'SetBotTrustedChatRequest(operationId: ${_this.operationId}, botId: ${_this.botId}, expectedConfigRevision: ${_this.expectedConfigRevision}, chatId: ${_this.chatId}, trusted: ${_this.trusted})';
}


}

/// @nodoc
abstract mixin class $SetBotTrustedChatRequestCopyWith<$Res>  {
  factory $SetBotTrustedChatRequestCopyWith(SetBotTrustedChatRequest value, $Res Function(SetBotTrustedChatRequest) _then) = _$SetBotTrustedChatRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, String chatId, bool trusted
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetBotTrustedChatRequestCopyWithImpl<$Res>
    implements $SetBotTrustedChatRequestCopyWith<$Res> {
  _$SetBotTrustedChatRequestCopyWithImpl(this._self, this._then);

  final SetBotTrustedChatRequest _self;
  final $Res Function(SetBotTrustedChatRequest) _then;

/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? chatId = null,Object? trusted = null,}) {
  return _then(SetBotTrustedChatRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,trusted: null == trusted ? _self.trusted : trusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetBotTrustedChatRequest].
extension SetBotTrustedChatRequestPatterns on SetBotTrustedChatRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetBotTrustedChatRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetBotTrustedChatRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetBotTrustedChatRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String chatId,  bool trusted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.chatId,_that.trusted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String chatId,  bool trusted)  $default,) {final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest():
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.chatId,_that.trusted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String botId,  int expectedConfigRevision,  String chatId,  bool trusted)?  $default,) {final _that = this;
switch (_that) {
case _SetBotTrustedChatRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.expectedConfigRevision,_that.chatId,_that.trusted);case _:
  return null;

}
}

}

/// @nodoc


class _SetBotTrustedChatRequest implements SetBotTrustedChatRequest {
  const _SetBotTrustedChatRequest({required this.operationId, required this.botId, required this.expectedConfigRevision, required this.chatId, required this.trusted});


@override final  OperationId operationId;
@override final  String botId;
@override final  int expectedConfigRevision;
@override final  String chatId;
@override final  bool trusted;

/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetBotTrustedChatRequestCopyWith<_SetBotTrustedChatRequest> get copyWith => __$SetBotTrustedChatRequestCopyWithImpl<_SetBotTrustedChatRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetBotTrustedChatRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.trusted, trusted) || other.trusted == trusted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId,expectedConfigRevision,chatId,trusted);
}

@override
String toString() {
    return 'SetBotTrustedChatRequest(operationId: $operationId, botId: $botId, expectedConfigRevision: $expectedConfigRevision, chatId: $chatId, trusted: $trusted)';
}


}

/// @nodoc
abstract mixin class _$SetBotTrustedChatRequestCopyWith<$Res> implements $SetBotTrustedChatRequestCopyWith<$Res> {
  factory _$SetBotTrustedChatRequestCopyWith(_SetBotTrustedChatRequest value, $Res Function(_SetBotTrustedChatRequest) _then) = __$SetBotTrustedChatRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String botId, int expectedConfigRevision, String chatId, bool trusted
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetBotTrustedChatRequestCopyWithImpl<$Res>
    implements _$SetBotTrustedChatRequestCopyWith<$Res> {
  __$SetBotTrustedChatRequestCopyWithImpl(this._self, this._then);

  final _SetBotTrustedChatRequest _self;
  final $Res Function(_SetBotTrustedChatRequest) _then;

/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = null,Object? expectedConfigRevision = null,Object? chatId = null,Object? trusted = null,}) {
  return _then(_SetBotTrustedChatRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,trusted: null == trusted ? _self.trusted : trusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SetBotTrustedChatRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$BotsCommandReply {

 CommitReceipt get receipt; ResourceStamp? get stamp; BotSnapshot? get bot; BotRegistrationAttempt? get registration;
/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsCommandReplyCopyWith<BotsCommandReply> get copyWith => _$BotsCommandReplyCopyWithImpl<BotsCommandReply>(this as BotsCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsCommandReply&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.bot, _this.bot) || other.bot == _this.bot)&&(identical(other.registration, _this.registration) || other.registration == _this.registration));
}


@override
int get hashCode {
  final _this = this as BotsCommandReply;
  return Object.hash(runtimeType,_this.receipt,_this.stamp,_this.bot,_this.registration);
}



}

/// @nodoc
abstract mixin class $BotsCommandReplyCopyWith<$Res>  {
  factory $BotsCommandReplyCopyWith(BotsCommandReply value, $Res Function(BotsCommandReply) _then) = _$BotsCommandReplyCopyWithImpl;
@useResult
$Res call({
 CommitReceipt receipt, ResourceStamp? stamp, BotSnapshot? bot, BotRegistrationAttempt? registration
});


$CommitReceiptCopyWith<$Res> get receipt;$ResourceStampCopyWith<$Res>? get stamp;$BotSnapshotCopyWith<$Res>? get bot;$BotRegistrationAttemptCopyWith<$Res>? get registration;

}
/// @nodoc
class _$BotsCommandReplyCopyWithImpl<$Res>
    implements $BotsCommandReplyCopyWith<$Res> {
  _$BotsCommandReplyCopyWithImpl(this._self, this._then);

  final BotsCommandReply _self;
  final $Res Function(BotsCommandReply) _then;

/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? receipt = null,Object? stamp = freezed,Object? bot = freezed,Object? registration = freezed,}) {
  return _then(BotsCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ResourceStamp?,bot: freezed == bot ? _self.bot : bot // ignore: cast_nullable_to_non_nullable
as BotSnapshot?,registration: freezed == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as BotRegistrationAttempt?,
  ));
}
/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ResourceStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSnapshotCopyWith<$Res>? get bot {
    if (_self.bot == null) {
    return null;
  }

  return $BotSnapshotCopyWith<$Res>(_self.bot!, (value) {
    return _then(_self.copyWith(bot: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotRegistrationAttemptCopyWith<$Res>? get registration {
    if (_self.registration == null) {
    return null;
  }

  return $BotRegistrationAttemptCopyWith<$Res>(_self.registration!, (value) {
    return _then(_self.copyWith(registration: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsCommandReply].
extension BotsCommandReplyPatterns on BotsCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotsCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotsCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotsCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _BotsCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotsCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _BotsCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ResourceStamp? stamp,  BotSnapshot? bot,  BotRegistrationAttempt? registration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotsCommandReply() when $default != null:
return $default(_that.receipt,_that.stamp,_that.bot,_that.registration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ResourceStamp? stamp,  BotSnapshot? bot,  BotRegistrationAttempt? registration)  $default,) {final _that = this;
switch (_that) {
case _BotsCommandReply():
return $default(_that.receipt,_that.stamp,_that.bot,_that.registration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CommitReceipt receipt,  ResourceStamp? stamp,  BotSnapshot? bot,  BotRegistrationAttempt? registration)?  $default,) {final _that = this;
switch (_that) {
case _BotsCommandReply() when $default != null:
return $default(_that.receipt,_that.stamp,_that.bot,_that.registration);case _:
  return null;

}
}

}

/// @nodoc


class _BotsCommandReply implements BotsCommandReply {
  const _BotsCommandReply({required this.receipt, required this.stamp, required this.bot, required this.registration});


@override final  CommitReceipt receipt;
@override final  ResourceStamp? stamp;
@override final  BotSnapshot? bot;
@override final  BotRegistrationAttempt? registration;

/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotsCommandReplyCopyWith<_BotsCommandReply> get copyWith => __$BotsCommandReplyCopyWithImpl<_BotsCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotsCommandReply&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.bot, bot) || other.bot == bot)&&(identical(other.registration, registration) || other.registration == registration));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,stamp,bot,registration);
}



}

/// @nodoc
abstract mixin class _$BotsCommandReplyCopyWith<$Res> implements $BotsCommandReplyCopyWith<$Res> {
  factory _$BotsCommandReplyCopyWith(_BotsCommandReply value, $Res Function(_BotsCommandReply) _then) = __$BotsCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, ResourceStamp? stamp, BotSnapshot? bot, BotRegistrationAttempt? registration
});


@override $CommitReceiptCopyWith<$Res> get receipt;@override $ResourceStampCopyWith<$Res>? get stamp;@override $BotSnapshotCopyWith<$Res>? get bot;@override $BotRegistrationAttemptCopyWith<$Res>? get registration;

}
/// @nodoc
class __$BotsCommandReplyCopyWithImpl<$Res>
    implements _$BotsCommandReplyCopyWith<$Res> {
  __$BotsCommandReplyCopyWithImpl(this._self, this._then);

  final _BotsCommandReply _self;
  final $Res Function(_BotsCommandReply) _then;

/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? stamp = freezed,Object? bot = freezed,Object? registration = freezed,}) {
  return _then(_BotsCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ResourceStamp?,bot: freezed == bot ? _self.bot : bot // ignore: cast_nullable_to_non_nullable
as BotSnapshot?,registration: freezed == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as BotRegistrationAttempt?,
  ));
}

/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ResourceStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSnapshotCopyWith<$Res>? get bot {
    if (_self.bot == null) {
    return null;
  }

  return $BotSnapshotCopyWith<$Res>(_self.bot!, (value) {
    return _then(_self.copyWith(bot: value));
  });
}/// Create a copy of BotsCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotRegistrationAttemptCopyWith<$Res>? get registration {
    if (_self.registration == null) {
    return null;
  }

  return $BotRegistrationAttemptCopyWith<$Res>(_self.registration!, (value) {
    return _then(_self.copyWith(registration: value));
  });
}
}

/// @nodoc
mixin _$CreateBotConversationThreadRequest {

 OperationId get operationId; String get botId; String get chatId; int get expectedConfigRevision; int get expectedBindingRevision;
/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CreateBotConversationThreadRequestCopyWith<CreateBotConversationThreadRequest> get copyWith => _$CreateBotConversationThreadRequestCopyWithImpl<CreateBotConversationThreadRequest>(this as CreateBotConversationThreadRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CreateBotConversationThreadRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CreateBotConversationThreadRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.expectedBindingRevision, _this.expectedBindingRevision) || other.expectedBindingRevision == _this.expectedBindingRevision));
}


@override
int get hashCode {
  final _this = this as CreateBotConversationThreadRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.chatId,_this.expectedConfigRevision,_this.expectedBindingRevision);
}

@override
String toString() {
  final _this = this as CreateBotConversationThreadRequest;
  return 'CreateBotConversationThreadRequest(operationId: ${_this.operationId}, botId: ${_this.botId}, chatId: ${_this.chatId}, expectedConfigRevision: ${_this.expectedConfigRevision}, expectedBindingRevision: ${_this.expectedBindingRevision})';
}


}

/// @nodoc
abstract mixin class $CreateBotConversationThreadRequestCopyWith<$Res>  {
  factory $CreateBotConversationThreadRequestCopyWith(CreateBotConversationThreadRequest value, $Res Function(CreateBotConversationThreadRequest) _then) = _$CreateBotConversationThreadRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, String chatId, int expectedConfigRevision, int expectedBindingRevision
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$CreateBotConversationThreadRequestCopyWithImpl<$Res>
    implements $CreateBotConversationThreadRequestCopyWith<$Res> {
  _$CreateBotConversationThreadRequestCopyWithImpl(this._self, this._then);

  final CreateBotConversationThreadRequest _self;
  final $Res Function(CreateBotConversationThreadRequest) _then;

/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? chatId = null,Object? expectedConfigRevision = null,Object? expectedBindingRevision = null,}) {
  return _then(CreateBotConversationThreadRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,expectedBindingRevision: null == expectedBindingRevision ? _self.expectedBindingRevision : expectedBindingRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [CreateBotConversationThreadRequest].
extension CreateBotConversationThreadRequestPatterns on CreateBotConversationThreadRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CreateBotConversationThreadRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CreateBotConversationThreadRequest value)  $default,){
final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CreateBotConversationThreadRequest value)?  $default,){
final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  String chatId,  int expectedConfigRevision,  int expectedBindingRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.chatId,_that.expectedConfigRevision,_that.expectedBindingRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String botId,  String chatId,  int expectedConfigRevision,  int expectedBindingRevision)  $default,) {final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest():
return $default(_that.operationId,_that.botId,_that.chatId,_that.expectedConfigRevision,_that.expectedBindingRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String botId,  String chatId,  int expectedConfigRevision,  int expectedBindingRevision)?  $default,) {final _that = this;
switch (_that) {
case _CreateBotConversationThreadRequest() when $default != null:
return $default(_that.operationId,_that.botId,_that.chatId,_that.expectedConfigRevision,_that.expectedBindingRevision);case _:
  return null;

}
}

}

/// @nodoc


class _CreateBotConversationThreadRequest implements CreateBotConversationThreadRequest {
  const _CreateBotConversationThreadRequest({required this.operationId, required this.botId, required this.chatId, required this.expectedConfigRevision, required this.expectedBindingRevision});


@override final  OperationId operationId;
@override final  String botId;
@override final  String chatId;
@override final  int expectedConfigRevision;
@override final  int expectedBindingRevision;

/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CreateBotConversationThreadRequestCopyWith<_CreateBotConversationThreadRequest> get copyWith => __$CreateBotConversationThreadRequestCopyWithImpl<_CreateBotConversationThreadRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CreateBotConversationThreadRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.expectedBindingRevision, expectedBindingRevision) || other.expectedBindingRevision == expectedBindingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,botId,chatId,expectedConfigRevision,expectedBindingRevision);
}

@override
String toString() {
    return 'CreateBotConversationThreadRequest(operationId: $operationId, botId: $botId, chatId: $chatId, expectedConfigRevision: $expectedConfigRevision, expectedBindingRevision: $expectedBindingRevision)';
}


}

/// @nodoc
abstract mixin class _$CreateBotConversationThreadRequestCopyWith<$Res> implements $CreateBotConversationThreadRequestCopyWith<$Res> {
  factory _$CreateBotConversationThreadRequestCopyWith(_CreateBotConversationThreadRequest value, $Res Function(_CreateBotConversationThreadRequest) _then) = __$CreateBotConversationThreadRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String botId, String chatId, int expectedConfigRevision, int expectedBindingRevision
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$CreateBotConversationThreadRequestCopyWithImpl<$Res>
    implements _$CreateBotConversationThreadRequestCopyWith<$Res> {
  __$CreateBotConversationThreadRequestCopyWithImpl(this._self, this._then);

  final _CreateBotConversationThreadRequest _self;
  final $Res Function(_CreateBotConversationThreadRequest) _then;

/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? botId = null,Object? chatId = null,Object? expectedConfigRevision = null,Object? expectedBindingRevision = null,}) {
  return _then(_CreateBotConversationThreadRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,expectedBindingRevision: null == expectedBindingRevision ? _self.expectedBindingRevision : expectedBindingRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of CreateBotConversationThreadRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$BotConversationThreadReply {

 BotConversationThreadBinding get binding; CommitReceipt get receipt;
/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConversationThreadReplyCopyWith<BotConversationThreadReply> get copyWith => _$BotConversationThreadReplyCopyWithImpl<BotConversationThreadReply>(this as BotConversationThreadReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotConversationThreadReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConversationThreadReply&&(identical(other.binding, _this.binding) || other.binding == _this.binding)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as BotConversationThreadReply;
  return Object.hash(runtimeType,_this.binding,_this.receipt);
}



}

/// @nodoc
abstract mixin class $BotConversationThreadReplyCopyWith<$Res>  {
  factory $BotConversationThreadReplyCopyWith(BotConversationThreadReply value, $Res Function(BotConversationThreadReply) _then) = _$BotConversationThreadReplyCopyWithImpl;
@useResult
$Res call({
 BotConversationThreadBinding binding, CommitReceipt receipt
});


$BotConversationThreadBindingCopyWith<$Res> get binding;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$BotConversationThreadReplyCopyWithImpl<$Res>
    implements $BotConversationThreadReplyCopyWith<$Res> {
  _$BotConversationThreadReplyCopyWithImpl(this._self, this._then);

  final BotConversationThreadReply _self;
  final $Res Function(BotConversationThreadReply) _then;

/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? binding = null,Object? receipt = null,}) {
  return _then(BotConversationThreadReply(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as BotConversationThreadBinding,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationThreadBindingCopyWith<$Res> get binding {

  return $BotConversationThreadBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotConversationThreadReply].
extension BotConversationThreadReplyPatterns on BotConversationThreadReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotConversationThreadReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotConversationThreadReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotConversationThreadReply value)  $default,){
final _that = this;
switch (_that) {
case _BotConversationThreadReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotConversationThreadReply value)?  $default,){
final _that = this;
switch (_that) {
case _BotConversationThreadReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( BotConversationThreadBinding binding,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotConversationThreadReply() when $default != null:
return $default(_that.binding,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( BotConversationThreadBinding binding,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _BotConversationThreadReply():
return $default(_that.binding,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( BotConversationThreadBinding binding,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _BotConversationThreadReply() when $default != null:
return $default(_that.binding,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _BotConversationThreadReply implements BotConversationThreadReply {
  const _BotConversationThreadReply({required this.binding, required this.receipt});


@override final  BotConversationThreadBinding binding;
@override final  CommitReceipt receipt;

/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotConversationThreadReplyCopyWith<_BotConversationThreadReply> get copyWith => __$BotConversationThreadReplyCopyWithImpl<_BotConversationThreadReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotConversationThreadReply&&(identical(other.binding, binding) || other.binding == binding)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,binding,receipt);
}



}

/// @nodoc
abstract mixin class _$BotConversationThreadReplyCopyWith<$Res> implements $BotConversationThreadReplyCopyWith<$Res> {
  factory _$BotConversationThreadReplyCopyWith(_BotConversationThreadReply value, $Res Function(_BotConversationThreadReply) _then) = __$BotConversationThreadReplyCopyWithImpl;
@override @useResult
$Res call({
 BotConversationThreadBinding binding, CommitReceipt receipt
});


@override $BotConversationThreadBindingCopyWith<$Res> get binding;@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$BotConversationThreadReplyCopyWithImpl<$Res>
    implements _$BotConversationThreadReplyCopyWith<$Res> {
  __$BotConversationThreadReplyCopyWithImpl(this._self, this._then);

  final _BotConversationThreadReply _self;
  final $Res Function(_BotConversationThreadReply) _then;

/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? binding = null,Object? receipt = null,}) {
  return _then(_BotConversationThreadReply(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as BotConversationThreadBinding,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationThreadBindingCopyWith<$Res> get binding {

  return $BotConversationThreadBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of BotConversationThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc
mixin _$ListBotConversationsRequest {

 String get botId; String? get cursor; int? get limit;
/// Create a copy of ListBotConversationsRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListBotConversationsRequestCopyWith<ListBotConversationsRequest> get copyWith => _$ListBotConversationsRequestCopyWithImpl<ListBotConversationsRequest>(this as ListBotConversationsRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ListBotConversationsRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListBotConversationsRequest&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor)&&(identical(other.limit, _this.limit) || other.limit == _this.limit));
}


@override
int get hashCode {
  final _this = this as ListBotConversationsRequest;
  return Object.hash(runtimeType,_this.botId,_this.cursor,_this.limit);
}



}

/// @nodoc
abstract mixin class $ListBotConversationsRequestCopyWith<$Res>  {
  factory $ListBotConversationsRequestCopyWith(ListBotConversationsRequest value, $Res Function(ListBotConversationsRequest) _then) = _$ListBotConversationsRequestCopyWithImpl;
@useResult
$Res call({
 String botId, String? cursor, int? limit
});




}
/// @nodoc
class _$ListBotConversationsRequestCopyWithImpl<$Res>
    implements $ListBotConversationsRequestCopyWith<$Res> {
  _$ListBotConversationsRequestCopyWithImpl(this._self, this._then);

  final ListBotConversationsRequest _self;
  final $Res Function(ListBotConversationsRequest) _then;

/// Create a copy of ListBotConversationsRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? cursor = freezed,Object? limit = freezed,}) {
  return _then(ListBotConversationsRequest(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,limit: freezed == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ListBotConversationsRequest].
extension ListBotConversationsRequestPatterns on ListBotConversationsRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ListBotConversationsRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ListBotConversationsRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ListBotConversationsRequest value)  $default,){
final _that = this;
switch (_that) {
case _ListBotConversationsRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ListBotConversationsRequest value)?  $default,){
final _that = this;
switch (_that) {
case _ListBotConversationsRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String botId,  String? cursor,  int? limit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ListBotConversationsRequest() when $default != null:
return $default(_that.botId,_that.cursor,_that.limit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String botId,  String? cursor,  int? limit)  $default,) {final _that = this;
switch (_that) {
case _ListBotConversationsRequest():
return $default(_that.botId,_that.cursor,_that.limit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String botId,  String? cursor,  int? limit)?  $default,) {final _that = this;
switch (_that) {
case _ListBotConversationsRequest() when $default != null:
return $default(_that.botId,_that.cursor,_that.limit);case _:
  return null;

}
}

}

/// @nodoc


class _ListBotConversationsRequest implements ListBotConversationsRequest {
  const _ListBotConversationsRequest({required this.botId, required this.cursor, required this.limit});


@override final  String botId;
@override final  String? cursor;
@override final  int? limit;

/// Create a copy of ListBotConversationsRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ListBotConversationsRequestCopyWith<_ListBotConversationsRequest> get copyWith => __$ListBotConversationsRequestCopyWithImpl<_ListBotConversationsRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ListBotConversationsRequest&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.limit, limit) || other.limit == limit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,cursor,limit);
}



}

/// @nodoc
abstract mixin class _$ListBotConversationsRequestCopyWith<$Res> implements $ListBotConversationsRequestCopyWith<$Res> {
  factory _$ListBotConversationsRequestCopyWith(_ListBotConversationsRequest value, $Res Function(_ListBotConversationsRequest) _then) = __$ListBotConversationsRequestCopyWithImpl;
@override @useResult
$Res call({
 String botId, String? cursor, int? limit
});




}
/// @nodoc
class __$ListBotConversationsRequestCopyWithImpl<$Res>
    implements _$ListBotConversationsRequestCopyWith<$Res> {
  __$ListBotConversationsRequestCopyWithImpl(this._self, this._then);

  final _ListBotConversationsRequest _self;
  final $Res Function(_ListBotConversationsRequest) _then;

/// Create a copy of ListBotConversationsRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = null,Object? cursor = freezed,Object? limit = freezed,}) {
  return _then(_ListBotConversationsRequest(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,limit: freezed == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
