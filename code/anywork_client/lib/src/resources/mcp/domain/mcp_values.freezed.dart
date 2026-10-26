// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$McpServerState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $McpServerStateCopyWith<$Res>  {
$McpServerStateCopyWith(McpServerState _, $Res Function(McpServerState) __);
}


/// Adds pattern-matching-related methods to [McpServerState].
extension McpServerStatePatterns on McpServerState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisabledMcpServerState value)?  disabled,TResult Function( MissingCredentialMcpServerState value)?  missingCredential,TResult Function( CheckingMcpServerState value)?  checking,TResult Function( AvailableMcpServerState value)?  available,TResult Function( UnavailableMcpServerState value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisabledMcpServerState() when disabled != null:
return disabled(_that);case MissingCredentialMcpServerState() when missingCredential != null:
return missingCredential(_that);case CheckingMcpServerState() when checking != null:
return checking(_that);case AvailableMcpServerState() when available != null:
return available(_that);case UnavailableMcpServerState() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisabledMcpServerState value)  disabled,required TResult Function( MissingCredentialMcpServerState value)  missingCredential,required TResult Function( CheckingMcpServerState value)  checking,required TResult Function( AvailableMcpServerState value)  available,required TResult Function( UnavailableMcpServerState value)  unavailable,}){
final _that = this;
switch (_that) {
case DisabledMcpServerState():
return disabled(_that);case MissingCredentialMcpServerState():
return missingCredential(_that);case CheckingMcpServerState():
return checking(_that);case AvailableMcpServerState():
return available(_that);case UnavailableMcpServerState():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisabledMcpServerState value)?  disabled,TResult? Function( MissingCredentialMcpServerState value)?  missingCredential,TResult? Function( CheckingMcpServerState value)?  checking,TResult? Function( AvailableMcpServerState value)?  available,TResult? Function( UnavailableMcpServerState value)?  unavailable,}){
final _that = this;
switch (_that) {
case DisabledMcpServerState() when disabled != null:
return disabled(_that);case MissingCredentialMcpServerState() when missingCredential != null:
return missingCredential(_that);case CheckingMcpServerState() when checking != null:
return checking(_that);case AvailableMcpServerState() when available != null:
return available(_that);case UnavailableMcpServerState() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  disabled,TResult Function( String message)?  missingCredential,TResult Function( String message)?  checking,TResult Function( int checkedAt,  int toolCount)?  available,TResult Function( int checkedAt,  SourceStateError error)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisabledMcpServerState() when disabled != null:
return disabled(_that.message);case MissingCredentialMcpServerState() when missingCredential != null:
return missingCredential(_that.message);case CheckingMcpServerState() when checking != null:
return checking(_that.message);case AvailableMcpServerState() when available != null:
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerState() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  disabled,required TResult Function( String message)  missingCredential,required TResult Function( String message)  checking,required TResult Function( int checkedAt,  int toolCount)  available,required TResult Function( int checkedAt,  SourceStateError error)  unavailable,}) {final _that = this;
switch (_that) {
case DisabledMcpServerState():
return disabled(_that.message);case MissingCredentialMcpServerState():
return missingCredential(_that.message);case CheckingMcpServerState():
return checking(_that.message);case AvailableMcpServerState():
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerState():
return unavailable(_that.checkedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  disabled,TResult? Function( String message)?  missingCredential,TResult? Function( String message)?  checking,TResult? Function( int checkedAt,  int toolCount)?  available,TResult? Function( int checkedAt,  SourceStateError error)?  unavailable,}) {final _that = this;
switch (_that) {
case DisabledMcpServerState() when disabled != null:
return disabled(_that.message);case MissingCredentialMcpServerState() when missingCredential != null:
return missingCredential(_that.message);case CheckingMcpServerState() when checking != null:
return checking(_that.message);case AvailableMcpServerState() when available != null:
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerState() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class DisabledMcpServerState implements McpServerState {
  const DisabledMcpServerState({required this.message});


 final  String message;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledMcpServerStateCopyWith<DisabledMcpServerState> get copyWith => _$DisabledMcpServerStateCopyWithImpl<DisabledMcpServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledMcpServerState&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $DisabledMcpServerStateCopyWith<$Res> implements $McpServerStateCopyWith<$Res> {
  factory $DisabledMcpServerStateCopyWith(DisabledMcpServerState value, $Res Function(DisabledMcpServerState) _then) = _$DisabledMcpServerStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$DisabledMcpServerStateCopyWithImpl<$Res>
    implements $DisabledMcpServerStateCopyWith<$Res> {
  _$DisabledMcpServerStateCopyWithImpl(this._self, this._then);

  final DisabledMcpServerState _self;
  final $Res Function(DisabledMcpServerState) _then;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(DisabledMcpServerState(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MissingCredentialMcpServerState implements McpServerState {
  const MissingCredentialMcpServerState({required this.message});


 final  String message;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MissingCredentialMcpServerStateCopyWith<MissingCredentialMcpServerState> get copyWith => _$MissingCredentialMcpServerStateCopyWithImpl<MissingCredentialMcpServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MissingCredentialMcpServerState&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $MissingCredentialMcpServerStateCopyWith<$Res> implements $McpServerStateCopyWith<$Res> {
  factory $MissingCredentialMcpServerStateCopyWith(MissingCredentialMcpServerState value, $Res Function(MissingCredentialMcpServerState) _then) = _$MissingCredentialMcpServerStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$MissingCredentialMcpServerStateCopyWithImpl<$Res>
    implements $MissingCredentialMcpServerStateCopyWith<$Res> {
  _$MissingCredentialMcpServerStateCopyWithImpl(this._self, this._then);

  final MissingCredentialMcpServerState _self;
  final $Res Function(MissingCredentialMcpServerState) _then;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MissingCredentialMcpServerState(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CheckingMcpServerState implements McpServerState {
  const CheckingMcpServerState({required this.message});


 final  String message;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingMcpServerStateCopyWith<CheckingMcpServerState> get copyWith => _$CheckingMcpServerStateCopyWithImpl<CheckingMcpServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingMcpServerState&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $CheckingMcpServerStateCopyWith<$Res> implements $McpServerStateCopyWith<$Res> {
  factory $CheckingMcpServerStateCopyWith(CheckingMcpServerState value, $Res Function(CheckingMcpServerState) _then) = _$CheckingMcpServerStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CheckingMcpServerStateCopyWithImpl<$Res>
    implements $CheckingMcpServerStateCopyWith<$Res> {
  _$CheckingMcpServerStateCopyWithImpl(this._self, this._then);

  final CheckingMcpServerState _self;
  final $Res Function(CheckingMcpServerState) _then;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CheckingMcpServerState(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AvailableMcpServerState implements McpServerState {
  const AvailableMcpServerState({required this.checkedAt, required this.toolCount});


 final  int checkedAt;
 final  int toolCount;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableMcpServerStateCopyWith<AvailableMcpServerState> get copyWith => _$AvailableMcpServerStateCopyWithImpl<AvailableMcpServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableMcpServerState&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.toolCount, toolCount) || other.toolCount == toolCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,toolCount);
}



}

/// @nodoc
abstract mixin class $AvailableMcpServerStateCopyWith<$Res> implements $McpServerStateCopyWith<$Res> {
  factory $AvailableMcpServerStateCopyWith(AvailableMcpServerState value, $Res Function(AvailableMcpServerState) _then) = _$AvailableMcpServerStateCopyWithImpl;
@useResult
$Res call({
 int checkedAt, int toolCount
});




}
/// @nodoc
class _$AvailableMcpServerStateCopyWithImpl<$Res>
    implements $AvailableMcpServerStateCopyWith<$Res> {
  _$AvailableMcpServerStateCopyWithImpl(this._self, this._then);

  final AvailableMcpServerState _self;
  final $Res Function(AvailableMcpServerState) _then;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? toolCount = null,}) {
  return _then(AvailableMcpServerState(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,toolCount: null == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class UnavailableMcpServerState implements McpServerState {
  const UnavailableMcpServerState({required this.checkedAt, required this.error});


 final  int checkedAt;
 final  SourceStateError error;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableMcpServerStateCopyWith<UnavailableMcpServerState> get copyWith => _$UnavailableMcpServerStateCopyWithImpl<UnavailableMcpServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableMcpServerState&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}



}

/// @nodoc
abstract mixin class $UnavailableMcpServerStateCopyWith<$Res> implements $McpServerStateCopyWith<$Res> {
  factory $UnavailableMcpServerStateCopyWith(UnavailableMcpServerState value, $Res Function(UnavailableMcpServerState) _then) = _$UnavailableMcpServerStateCopyWithImpl;
@useResult
$Res call({
 int checkedAt, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$UnavailableMcpServerStateCopyWithImpl<$Res>
    implements $UnavailableMcpServerStateCopyWith<$Res> {
  _$UnavailableMcpServerStateCopyWithImpl(this._self, this._then);

  final UnavailableMcpServerState _self;
  final $Res Function(UnavailableMcpServerState) _then;

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(UnavailableMcpServerState(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of McpServerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$McpServer {

 String get id; String get transport; String get endpoint; String get sourceKind; String get mutationPolicy; McpServerState get state;
/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerCopyWith<McpServer> get copyWith => _$McpServerCopyWithImpl<McpServer>(this as McpServer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpServer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServer&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.sourceKind, _this.sourceKind) || other.sourceKind == _this.sourceKind)&&(identical(other.mutationPolicy, _this.mutationPolicy) || other.mutationPolicy == _this.mutationPolicy)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as McpServer;
  return Object.hash(runtimeType,_this.id,_this.transport,_this.endpoint,_this.sourceKind,_this.mutationPolicy,_this.state);
}



}

/// @nodoc
abstract mixin class $McpServerCopyWith<$Res>  {
  factory $McpServerCopyWith(McpServer value, $Res Function(McpServer) _then) = _$McpServerCopyWithImpl;
@useResult
$Res call({
 String id, String transport, String endpoint, String sourceKind, String mutationPolicy, McpServerState state
});


$McpServerStateCopyWith<$Res> get state;

}
/// @nodoc
class _$McpServerCopyWithImpl<$Res>
    implements $McpServerCopyWith<$Res> {
  _$McpServerCopyWithImpl(this._self, this._then);

  final McpServer _self;
  final $Res Function(McpServer) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? sourceKind = null,Object? mutationPolicy = null,Object? state = null,}) {
  return _then(McpServer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as McpServerState,
  ));
}
/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerStateCopyWith<$Res> get state {

  return $McpServerStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpServer].
extension McpServerPatterns on McpServer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpServer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpServer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpServer value)  $default,){
final _that = this;
switch (_that) {
case _McpServer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpServer value)?  $default,){
final _that = this;
switch (_that) {
case _McpServer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String transport,  String endpoint,  String sourceKind,  String mutationPolicy,  McpServerState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpServer() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String transport,  String endpoint,  String sourceKind,  String mutationPolicy,  McpServerState state)  $default,) {final _that = this;
switch (_that) {
case _McpServer():
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String transport,  String endpoint,  String sourceKind,  String mutationPolicy,  McpServerState state)?  $default,) {final _that = this;
switch (_that) {
case _McpServer() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _McpServer implements McpServer {
  const _McpServer({required this.id, required this.transport, required this.endpoint, required this.sourceKind, required this.mutationPolicy, required this.state});


@override final  String id;
@override final  String transport;
@override final  String endpoint;
@override final  String sourceKind;
@override final  String mutationPolicy;
@override final  McpServerState state;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpServerCopyWith<_McpServer> get copyWith => __$McpServerCopyWithImpl<_McpServer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServer&&(identical(other.id, id) || other.id == id)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.sourceKind, sourceKind) || other.sourceKind == sourceKind)&&(identical(other.mutationPolicy, mutationPolicy) || other.mutationPolicy == mutationPolicy)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,transport,endpoint,sourceKind,mutationPolicy,state);
}



}

/// @nodoc
abstract mixin class _$McpServerCopyWith<$Res> implements $McpServerCopyWith<$Res> {
  factory _$McpServerCopyWith(_McpServer value, $Res Function(_McpServer) _then) = __$McpServerCopyWithImpl;
@override @useResult
$Res call({
 String id, String transport, String endpoint, String sourceKind, String mutationPolicy, McpServerState state
});


@override $McpServerStateCopyWith<$Res> get state;

}
/// @nodoc
class __$McpServerCopyWithImpl<$Res>
    implements _$McpServerCopyWith<$Res> {
  __$McpServerCopyWithImpl(this._self, this._then);

  final _McpServer _self;
  final $Res Function(_McpServer) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? sourceKind = null,Object? mutationPolicy = null,Object? state = null,}) {
  return _then(_McpServer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as McpServerState,
  ));
}

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerStateCopyWith<$Res> get state {

  return $McpServerStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$McpHealth {

 List<McpServer> get mcpServers; List<String> get activeMcpServers;
/// Create a copy of McpHealth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpHealthCopyWith<McpHealth> get copyWith => _$McpHealthCopyWithImpl<McpHealth>(this as McpHealth, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpHealth;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpHealth&&const DeepCollectionEquality().equals(other.mcpServers, _this.mcpServers)&&const DeepCollectionEquality().equals(other.activeMcpServers, _this.activeMcpServers));
}


@override
int get hashCode {
  final _this = this as McpHealth;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.mcpServers),const DeepCollectionEquality().hash(_this.activeMcpServers));
}

@override
String toString() {
  final _this = this as McpHealth;
  return 'McpHealth(mcpServers: ${_this.mcpServers}, activeMcpServers: ${_this.activeMcpServers})';
}


}

/// @nodoc
abstract mixin class $McpHealthCopyWith<$Res>  {
  factory $McpHealthCopyWith(McpHealth value, $Res Function(McpHealth) _then) = _$McpHealthCopyWithImpl;
@useResult
$Res call({
 List<McpServer> mcpServers, List<String> activeMcpServers
});




}
/// @nodoc
class _$McpHealthCopyWithImpl<$Res>
    implements $McpHealthCopyWith<$Res> {
  _$McpHealthCopyWithImpl(this._self, this._then);

  final McpHealth _self;
  final $Res Function(McpHealth) _then;

/// Create a copy of McpHealth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mcpServers = null,Object? activeMcpServers = null,}) {
  return _then(McpHealth(
mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,activeMcpServers: null == activeMcpServers ? _self.activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [McpHealth].
extension McpHealthPatterns on McpHealth {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpHealth value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpHealth() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpHealth value)  $default,){
final _that = this;
switch (_that) {
case _McpHealth():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpHealth value)?  $default,){
final _that = this;
switch (_that) {
case _McpHealth() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<McpServer> mcpServers,  List<String> activeMcpServers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpHealth() when $default != null:
return $default(_that.mcpServers,_that.activeMcpServers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<McpServer> mcpServers,  List<String> activeMcpServers)  $default,) {final _that = this;
switch (_that) {
case _McpHealth():
return $default(_that.mcpServers,_that.activeMcpServers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<McpServer> mcpServers,  List<String> activeMcpServers)?  $default,) {final _that = this;
switch (_that) {
case _McpHealth() when $default != null:
return $default(_that.mcpServers,_that.activeMcpServers);case _:
  return null;

}
}

}

/// @nodoc


class _McpHealth implements McpHealth {
  const _McpHealth({required  List<McpServer> mcpServers, required  List<String> activeMcpServers}): _mcpServers = mcpServers,_activeMcpServers = activeMcpServers;


 final  List<McpServer> _mcpServers;
@override List<McpServer> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

 final  List<String> _activeMcpServers;
@override List<String> get activeMcpServers {
  if (_activeMcpServers is EqualUnmodifiableListView) return _activeMcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeMcpServers);
}


/// Create a copy of McpHealth
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpHealthCopyWith<_McpHealth> get copyWith => __$McpHealthCopyWithImpl<_McpHealth>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpHealth&&const DeepCollectionEquality().equals(other.mcpServers, _mcpServers)&&const DeepCollectionEquality().equals(other.activeMcpServers, _activeMcpServers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_mcpServers),const DeepCollectionEquality().hash(_activeMcpServers));
}

@override
String toString() {
    return 'McpHealth(mcpServers: $mcpServers, activeMcpServers: $activeMcpServers)';
}


}

/// @nodoc
abstract mixin class _$McpHealthCopyWith<$Res> implements $McpHealthCopyWith<$Res> {
  factory _$McpHealthCopyWith(_McpHealth value, $Res Function(_McpHealth) _then) = __$McpHealthCopyWithImpl;
@override @useResult
$Res call({
 List<McpServer> mcpServers, List<String> activeMcpServers
});




}
/// @nodoc
class __$McpHealthCopyWithImpl<$Res>
    implements _$McpHealthCopyWith<$Res> {
  __$McpHealthCopyWithImpl(this._self, this._then);

  final _McpHealth _self;
  final $Res Function(_McpHealth) _then;

/// Create a copy of McpHealth
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mcpServers = null,Object? activeMcpServers = null,}) {
  return _then(_McpHealth(
mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,activeMcpServers: null == activeMcpServers ? _self._activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$McpValue {

 String get desiredConfigFingerprint; String get appliedConfigFingerprint; McpHealth get health;
/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpValueCopyWith<McpValue> get copyWith => _$McpValueCopyWithImpl<McpValue>(this as McpValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpValue&&(identical(other.desiredConfigFingerprint, _this.desiredConfigFingerprint) || other.desiredConfigFingerprint == _this.desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, _this.appliedConfigFingerprint) || other.appliedConfigFingerprint == _this.appliedConfigFingerprint)&&(identical(other.health, _this.health) || other.health == _this.health));
}


@override
int get hashCode {
  final _this = this as McpValue;
  return Object.hash(runtimeType,_this.desiredConfigFingerprint,_this.appliedConfigFingerprint,_this.health);
}

@override
String toString() {
  final _this = this as McpValue;
  return 'McpValue(desiredConfigFingerprint: ${_this.desiredConfigFingerprint}, appliedConfigFingerprint: ${_this.appliedConfigFingerprint}, health: ${_this.health})';
}


}

/// @nodoc
abstract mixin class $McpValueCopyWith<$Res>  {
  factory $McpValueCopyWith(McpValue value, $Res Function(McpValue) _then) = _$McpValueCopyWithImpl;
@useResult
$Res call({
 String desiredConfigFingerprint, String appliedConfigFingerprint, McpHealth health
});


$McpHealthCopyWith<$Res> get health;

}
/// @nodoc
class _$McpValueCopyWithImpl<$Res>
    implements $McpValueCopyWith<$Res> {
  _$McpValueCopyWithImpl(this._self, this._then);

  final McpValue _self;
  final $Res Function(McpValue) _then;

/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? desiredConfigFingerprint = null,Object? appliedConfigFingerprint = null,Object? health = null,}) {
  return _then(McpValue(
desiredConfigFingerprint: null == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as String,appliedConfigFingerprint: null == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as String,health: null == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as McpHealth,
  ));
}
/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpHealthCopyWith<$Res> get health {

  return $McpHealthCopyWith<$Res>(_self.health, (value) {
    return _then(_self.copyWith(health: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpValue].
extension McpValuePatterns on McpValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpValue value)  $default,){
final _that = this;
switch (_that) {
case _McpValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpValue value)?  $default,){
final _that = this;
switch (_that) {
case _McpValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String desiredConfigFingerprint,  String appliedConfigFingerprint,  McpHealth health)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpValue() when $default != null:
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String desiredConfigFingerprint,  String appliedConfigFingerprint,  McpHealth health)  $default,) {final _that = this;
switch (_that) {
case _McpValue():
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String desiredConfigFingerprint,  String appliedConfigFingerprint,  McpHealth health)?  $default,) {final _that = this;
switch (_that) {
case _McpValue() when $default != null:
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
  return null;

}
}

}

/// @nodoc


class _McpValue implements McpValue {
  const _McpValue({required this.desiredConfigFingerprint, required this.appliedConfigFingerprint, required this.health});


@override final  String desiredConfigFingerprint;
@override final  String appliedConfigFingerprint;
@override final  McpHealth health;

/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpValueCopyWith<_McpValue> get copyWith => __$McpValueCopyWithImpl<_McpValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpValue&&(identical(other.desiredConfigFingerprint, desiredConfigFingerprint) || other.desiredConfigFingerprint == desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, appliedConfigFingerprint) || other.appliedConfigFingerprint == appliedConfigFingerprint)&&(identical(other.health, health) || other.health == health));
}


@override
int get hashCode {
    return Object.hash(runtimeType,desiredConfigFingerprint,appliedConfigFingerprint,health);
}

@override
String toString() {
    return 'McpValue(desiredConfigFingerprint: $desiredConfigFingerprint, appliedConfigFingerprint: $appliedConfigFingerprint, health: $health)';
}


}

/// @nodoc
abstract mixin class _$McpValueCopyWith<$Res> implements $McpValueCopyWith<$Res> {
  factory _$McpValueCopyWith(_McpValue value, $Res Function(_McpValue) _then) = __$McpValueCopyWithImpl;
@override @useResult
$Res call({
 String desiredConfigFingerprint, String appliedConfigFingerprint, McpHealth health
});


@override $McpHealthCopyWith<$Res> get health;

}
/// @nodoc
class __$McpValueCopyWithImpl<$Res>
    implements _$McpValueCopyWith<$Res> {
  __$McpValueCopyWithImpl(this._self, this._then);

  final _McpValue _self;
  final $Res Function(_McpValue) _then;

/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? desiredConfigFingerprint = null,Object? appliedConfigFingerprint = null,Object? health = null,}) {
  return _then(_McpValue(
desiredConfigFingerprint: null == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as String,appliedConfigFingerprint: null == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as String,health: null == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as McpHealth,
  ));
}

/// Create a copy of McpValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpHealthCopyWith<$Res> get health {

  return $McpHealthCopyWith<$Res>(_self.health, (value) {
    return _then(_self.copyWith(health: value));
  });
}
}

// dart format on
