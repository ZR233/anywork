// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSshConnectionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSshConnectionState()';
}


}

/// @nodoc
class $BridgeSshConnectionStateCopyWith<$Res>  {
$BridgeSshConnectionStateCopyWith(BridgeSshConnectionState _, $Res Function(BridgeSshConnectionState) __);
}


/// Adds pattern-matching-related methods to [BridgeSshConnectionState].
extension BridgeSshConnectionStatePatterns on BridgeSshConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSshConnectionState_Disconnected value)?  disconnected,TResult Function( BridgeSshConnectionState_Connecting value)?  connecting,TResult Function( BridgeSshConnectionState_Ready value)?  ready,TResult Function( BridgeSshConnectionState_Reconnecting value)?  reconnecting,TResult Function( BridgeSshConnectionState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected() when disconnected != null:
return disconnected(_that);case BridgeSshConnectionState_Connecting() when connecting != null:
return connecting(_that);case BridgeSshConnectionState_Ready() when ready != null:
return ready(_that);case BridgeSshConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case BridgeSshConnectionState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSshConnectionState_Disconnected value)  disconnected,required TResult Function( BridgeSshConnectionState_Connecting value)  connecting,required TResult Function( BridgeSshConnectionState_Ready value)  ready,required TResult Function( BridgeSshConnectionState_Reconnecting value)  reconnecting,required TResult Function( BridgeSshConnectionState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected():
return disconnected(_that);case BridgeSshConnectionState_Connecting():
return connecting(_that);case BridgeSshConnectionState_Ready():
return ready(_that);case BridgeSshConnectionState_Reconnecting():
return reconnecting(_that);case BridgeSshConnectionState_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSshConnectionState_Disconnected value)?  disconnected,TResult? Function( BridgeSshConnectionState_Connecting value)?  connecting,TResult? Function( BridgeSshConnectionState_Ready value)?  ready,TResult? Function( BridgeSshConnectionState_Reconnecting value)?  reconnecting,TResult? Function( BridgeSshConnectionState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected() when disconnected != null:
return disconnected(_that);case BridgeSshConnectionState_Connecting() when connecting != null:
return connecting(_that);case BridgeSshConnectionState_Ready() when ready != null:
return ready(_that);case BridgeSshConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case BridgeSshConnectionState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( String helperVersion,  String architecture)?  ready,TResult Function( int attempt,  BigInt delaySeconds)?  reconnecting,TResult Function( String code,  String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected() when disconnected != null:
return disconnected();case BridgeSshConnectionState_Connecting() when connecting != null:
return connecting();case BridgeSshConnectionState_Ready() when ready != null:
return ready(_that.helperVersion,_that.architecture);case BridgeSshConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.attempt,_that.delaySeconds);case BridgeSshConnectionState_Failed() when failed != null:
return failed(_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( String helperVersion,  String architecture)  ready,required TResult Function( int attempt,  BigInt delaySeconds)  reconnecting,required TResult Function( String code,  String message)  failed,}) {final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected():
return disconnected();case BridgeSshConnectionState_Connecting():
return connecting();case BridgeSshConnectionState_Ready():
return ready(_that.helperVersion,_that.architecture);case BridgeSshConnectionState_Reconnecting():
return reconnecting(_that.attempt,_that.delaySeconds);case BridgeSshConnectionState_Failed():
return failed(_that.code,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( String helperVersion,  String architecture)?  ready,TResult? Function( int attempt,  BigInt delaySeconds)?  reconnecting,TResult? Function( String code,  String message)?  failed,}) {final _that = this;
switch (_that) {
case BridgeSshConnectionState_Disconnected() when disconnected != null:
return disconnected();case BridgeSshConnectionState_Connecting() when connecting != null:
return connecting();case BridgeSshConnectionState_Ready() when ready != null:
return ready(_that.helperVersion,_that.architecture);case BridgeSshConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.attempt,_that.delaySeconds);case BridgeSshConnectionState_Failed() when failed != null:
return failed(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSshConnectionState_Disconnected extends BridgeSshConnectionState {
  const BridgeSshConnectionState_Disconnected(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState_Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSshConnectionState.disconnected()';
}


}




/// @nodoc


class BridgeSshConnectionState_Connecting extends BridgeSshConnectionState {
  const BridgeSshConnectionState_Connecting(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState_Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSshConnectionState.connecting()';
}


}




/// @nodoc


class BridgeSshConnectionState_Ready extends BridgeSshConnectionState {
  const BridgeSshConnectionState_Ready({required this.helperVersion, required this.architecture}): super._();


 final  String helperVersion;
 final  String architecture;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSshConnectionState_ReadyCopyWith<BridgeSshConnectionState_Ready> get copyWith => _$BridgeSshConnectionState_ReadyCopyWithImpl<BridgeSshConnectionState_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState_Ready&&(identical(other.helperVersion, helperVersion) || other.helperVersion == helperVersion)&&(identical(other.architecture, architecture) || other.architecture == architecture));
}


@override
int get hashCode {
    return Object.hash(runtimeType,helperVersion,architecture);
}

@override
String toString() {
    return 'BridgeSshConnectionState.ready(helperVersion: $helperVersion, architecture: $architecture)';
}


}

/// @nodoc
abstract mixin class $BridgeSshConnectionState_ReadyCopyWith<$Res> implements $BridgeSshConnectionStateCopyWith<$Res> {
  factory $BridgeSshConnectionState_ReadyCopyWith(BridgeSshConnectionState_Ready value, $Res Function(BridgeSshConnectionState_Ready) _then) = _$BridgeSshConnectionState_ReadyCopyWithImpl;
@useResult
$Res call({
 String helperVersion, String architecture
});




}
/// @nodoc
class _$BridgeSshConnectionState_ReadyCopyWithImpl<$Res>
    implements $BridgeSshConnectionState_ReadyCopyWith<$Res> {
  _$BridgeSshConnectionState_ReadyCopyWithImpl(this._self, this._then);

  final BridgeSshConnectionState_Ready _self;
  final $Res Function(BridgeSshConnectionState_Ready) _then;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? helperVersion = null,Object? architecture = null,}) {
  return _then(BridgeSshConnectionState_Ready(
helperVersion: null == helperVersion ? _self.helperVersion : helperVersion // ignore: cast_nullable_to_non_nullable
as String,architecture: null == architecture ? _self.architecture : architecture // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSshConnectionState_Reconnecting extends BridgeSshConnectionState {
  const BridgeSshConnectionState_Reconnecting({required this.attempt, required this.delaySeconds}): super._();


 final  int attempt;
 final  BigInt delaySeconds;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSshConnectionState_ReconnectingCopyWith<BridgeSshConnectionState_Reconnecting> get copyWith => _$BridgeSshConnectionState_ReconnectingCopyWithImpl<BridgeSshConnectionState_Reconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState_Reconnecting&&(identical(other.attempt, attempt) || other.attempt == attempt)&&(identical(other.delaySeconds, delaySeconds) || other.delaySeconds == delaySeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attempt,delaySeconds);
}

@override
String toString() {
    return 'BridgeSshConnectionState.reconnecting(attempt: $attempt, delaySeconds: $delaySeconds)';
}


}

/// @nodoc
abstract mixin class $BridgeSshConnectionState_ReconnectingCopyWith<$Res> implements $BridgeSshConnectionStateCopyWith<$Res> {
  factory $BridgeSshConnectionState_ReconnectingCopyWith(BridgeSshConnectionState_Reconnecting value, $Res Function(BridgeSshConnectionState_Reconnecting) _then) = _$BridgeSshConnectionState_ReconnectingCopyWithImpl;
@useResult
$Res call({
 int attempt, BigInt delaySeconds
});




}
/// @nodoc
class _$BridgeSshConnectionState_ReconnectingCopyWithImpl<$Res>
    implements $BridgeSshConnectionState_ReconnectingCopyWith<$Res> {
  _$BridgeSshConnectionState_ReconnectingCopyWithImpl(this._self, this._then);

  final BridgeSshConnectionState_Reconnecting _self;
  final $Res Function(BridgeSshConnectionState_Reconnecting) _then;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attempt = null,Object? delaySeconds = null,}) {
  return _then(BridgeSshConnectionState_Reconnecting(
attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,delaySeconds: null == delaySeconds ? _self.delaySeconds : delaySeconds // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeSshConnectionState_Failed extends BridgeSshConnectionState {
  const BridgeSshConnectionState_Failed({required this.code, required this.message}): super._();


 final  String code;
 final  String message;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSshConnectionState_FailedCopyWith<BridgeSshConnectionState_Failed> get copyWith => _$BridgeSshConnectionState_FailedCopyWithImpl<BridgeSshConnectionState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSshConnectionState_Failed&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message);
}

@override
String toString() {
    return 'BridgeSshConnectionState.failed(code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeSshConnectionState_FailedCopyWith<$Res> implements $BridgeSshConnectionStateCopyWith<$Res> {
  factory $BridgeSshConnectionState_FailedCopyWith(BridgeSshConnectionState_Failed value, $Res Function(BridgeSshConnectionState_Failed) _then) = _$BridgeSshConnectionState_FailedCopyWithImpl;
@useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$BridgeSshConnectionState_FailedCopyWithImpl<$Res>
    implements $BridgeSshConnectionState_FailedCopyWith<$Res> {
  _$BridgeSshConnectionState_FailedCopyWithImpl(this._self, this._then);

  final BridgeSshConnectionState_Failed _self;
  final $Res Function(BridgeSshConnectionState_Failed) _then;

/// Create a copy of BridgeSshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(BridgeSshConnectionState_Failed(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
