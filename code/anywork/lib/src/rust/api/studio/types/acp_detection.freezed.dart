// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_detection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpLocalDetectionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState()';
}


}

/// @nodoc
class $BridgeAcpLocalDetectionStateCopyWith<$Res>  {
$BridgeAcpLocalDetectionStateCopyWith(BridgeAcpLocalDetectionState _, $Res Function(BridgeAcpLocalDetectionState) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpLocalDetectionState].
extension BridgeAcpLocalDetectionStatePatterns on BridgeAcpLocalDetectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpLocalDetectionState_Idle value)?  idle,TResult Function( BridgeAcpLocalDetectionState_Checking value)?  checking,TResult Function( BridgeAcpLocalDetectionState_Available value)?  available,TResult Function( BridgeAcpLocalDetectionState_Missing value)?  missing,TResult Function( BridgeAcpLocalDetectionState_Unsupported value)?  unsupported,TResult Function( BridgeAcpLocalDetectionState_Failed value)?  failed,TResult Function( BridgeAcpLocalDetectionState_Cancelling value)?  cancelling,TResult Function( BridgeAcpLocalDetectionState_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle() when idle != null:
return idle(_that);case BridgeAcpLocalDetectionState_Checking() when checking != null:
return checking(_that);case BridgeAcpLocalDetectionState_Available() when available != null:
return available(_that);case BridgeAcpLocalDetectionState_Missing() when missing != null:
return missing(_that);case BridgeAcpLocalDetectionState_Unsupported() when unsupported != null:
return unsupported(_that);case BridgeAcpLocalDetectionState_Failed() when failed != null:
return failed(_that);case BridgeAcpLocalDetectionState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpLocalDetectionState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpLocalDetectionState_Idle value)  idle,required TResult Function( BridgeAcpLocalDetectionState_Checking value)  checking,required TResult Function( BridgeAcpLocalDetectionState_Available value)  available,required TResult Function( BridgeAcpLocalDetectionState_Missing value)  missing,required TResult Function( BridgeAcpLocalDetectionState_Unsupported value)  unsupported,required TResult Function( BridgeAcpLocalDetectionState_Failed value)  failed,required TResult Function( BridgeAcpLocalDetectionState_Cancelling value)  cancelling,required TResult Function( BridgeAcpLocalDetectionState_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle():
return idle(_that);case BridgeAcpLocalDetectionState_Checking():
return checking(_that);case BridgeAcpLocalDetectionState_Available():
return available(_that);case BridgeAcpLocalDetectionState_Missing():
return missing(_that);case BridgeAcpLocalDetectionState_Unsupported():
return unsupported(_that);case BridgeAcpLocalDetectionState_Failed():
return failed(_that);case BridgeAcpLocalDetectionState_Cancelling():
return cancelling(_that);case BridgeAcpLocalDetectionState_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpLocalDetectionState_Idle value)?  idle,TResult? Function( BridgeAcpLocalDetectionState_Checking value)?  checking,TResult? Function( BridgeAcpLocalDetectionState_Available value)?  available,TResult? Function( BridgeAcpLocalDetectionState_Missing value)?  missing,TResult? Function( BridgeAcpLocalDetectionState_Unsupported value)?  unsupported,TResult? Function( BridgeAcpLocalDetectionState_Failed value)?  failed,TResult? Function( BridgeAcpLocalDetectionState_Cancelling value)?  cancelling,TResult? Function( BridgeAcpLocalDetectionState_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle() when idle != null:
return idle(_that);case BridgeAcpLocalDetectionState_Checking() when checking != null:
return checking(_that);case BridgeAcpLocalDetectionState_Available() when available != null:
return available(_that);case BridgeAcpLocalDetectionState_Missing() when missing != null:
return missing(_that);case BridgeAcpLocalDetectionState_Unsupported() when unsupported != null:
return unsupported(_that);case BridgeAcpLocalDetectionState_Failed() when failed != null:
return failed(_that);case BridgeAcpLocalDetectionState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpLocalDetectionState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  checking,TResult Function( String program,  String version)?  available,TResult Function()?  missing,TResult Function()?  unsupported,TResult Function( BridgeAcpLocalDetectionFailure failure)?  failed,TResult Function()?  cancelling,TResult Function()?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle() when idle != null:
return idle();case BridgeAcpLocalDetectionState_Checking() when checking != null:
return checking();case BridgeAcpLocalDetectionState_Available() when available != null:
return available(_that.program,_that.version);case BridgeAcpLocalDetectionState_Missing() when missing != null:
return missing();case BridgeAcpLocalDetectionState_Unsupported() when unsupported != null:
return unsupported();case BridgeAcpLocalDetectionState_Failed() when failed != null:
return failed(_that.failure);case BridgeAcpLocalDetectionState_Cancelling() when cancelling != null:
return cancelling();case BridgeAcpLocalDetectionState_Cancelled() when cancelled != null:
return cancelled();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  checking,required TResult Function( String program,  String version)  available,required TResult Function()  missing,required TResult Function()  unsupported,required TResult Function( BridgeAcpLocalDetectionFailure failure)  failed,required TResult Function()  cancelling,required TResult Function()  cancelled,}) {final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle():
return idle();case BridgeAcpLocalDetectionState_Checking():
return checking();case BridgeAcpLocalDetectionState_Available():
return available(_that.program,_that.version);case BridgeAcpLocalDetectionState_Missing():
return missing();case BridgeAcpLocalDetectionState_Unsupported():
return unsupported();case BridgeAcpLocalDetectionState_Failed():
return failed(_that.failure);case BridgeAcpLocalDetectionState_Cancelling():
return cancelling();case BridgeAcpLocalDetectionState_Cancelled():
return cancelled();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  checking,TResult? Function( String program,  String version)?  available,TResult? Function()?  missing,TResult? Function()?  unsupported,TResult? Function( BridgeAcpLocalDetectionFailure failure)?  failed,TResult? Function()?  cancelling,TResult? Function()?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeAcpLocalDetectionState_Idle() when idle != null:
return idle();case BridgeAcpLocalDetectionState_Checking() when checking != null:
return checking();case BridgeAcpLocalDetectionState_Available() when available != null:
return available(_that.program,_that.version);case BridgeAcpLocalDetectionState_Missing() when missing != null:
return missing();case BridgeAcpLocalDetectionState_Unsupported() when unsupported != null:
return unsupported();case BridgeAcpLocalDetectionState_Failed() when failed != null:
return failed(_that.failure);case BridgeAcpLocalDetectionState_Cancelling() when cancelling != null:
return cancelling();case BridgeAcpLocalDetectionState_Cancelled() when cancelled != null:
return cancelled();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpLocalDetectionState_Idle extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.idle()';
}


}




/// @nodoc


class BridgeAcpLocalDetectionState_Checking extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Checking(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Checking);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.checking()';
}


}




/// @nodoc


class BridgeAcpLocalDetectionState_Available extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Available({required this.program, required this.version}): super._();


 final  String program;
 final  String version;

/// Create a copy of BridgeAcpLocalDetectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpLocalDetectionState_AvailableCopyWith<BridgeAcpLocalDetectionState_Available> get copyWith => _$BridgeAcpLocalDetectionState_AvailableCopyWithImpl<BridgeAcpLocalDetectionState_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Available&&(identical(other.program, program) || other.program == program)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,program,version);
}

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.available(program: $program, version: $version)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpLocalDetectionState_AvailableCopyWith<$Res> implements $BridgeAcpLocalDetectionStateCopyWith<$Res> {
  factory $BridgeAcpLocalDetectionState_AvailableCopyWith(BridgeAcpLocalDetectionState_Available value, $Res Function(BridgeAcpLocalDetectionState_Available) _then) = _$BridgeAcpLocalDetectionState_AvailableCopyWithImpl;
@useResult
$Res call({
 String program, String version
});




}
/// @nodoc
class _$BridgeAcpLocalDetectionState_AvailableCopyWithImpl<$Res>
    implements $BridgeAcpLocalDetectionState_AvailableCopyWith<$Res> {
  _$BridgeAcpLocalDetectionState_AvailableCopyWithImpl(this._self, this._then);

  final BridgeAcpLocalDetectionState_Available _self;
  final $Res Function(BridgeAcpLocalDetectionState_Available) _then;

/// Create a copy of BridgeAcpLocalDetectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? program = null,Object? version = null,}) {
  return _then(BridgeAcpLocalDetectionState_Available(
program: null == program ? _self.program : program // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpLocalDetectionState_Missing extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Missing(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Missing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.missing()';
}


}




/// @nodoc


class BridgeAcpLocalDetectionState_Unsupported extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Unsupported(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.unsupported()';
}


}




/// @nodoc


class BridgeAcpLocalDetectionState_Failed extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Failed({required this.failure}): super._();


 final  BridgeAcpLocalDetectionFailure failure;

/// Create a copy of BridgeAcpLocalDetectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpLocalDetectionState_FailedCopyWith<BridgeAcpLocalDetectionState_Failed> get copyWith => _$BridgeAcpLocalDetectionState_FailedCopyWithImpl<BridgeAcpLocalDetectionState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpLocalDetectionState_FailedCopyWith<$Res> implements $BridgeAcpLocalDetectionStateCopyWith<$Res> {
  factory $BridgeAcpLocalDetectionState_FailedCopyWith(BridgeAcpLocalDetectionState_Failed value, $Res Function(BridgeAcpLocalDetectionState_Failed) _then) = _$BridgeAcpLocalDetectionState_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpLocalDetectionFailure failure
});




}
/// @nodoc
class _$BridgeAcpLocalDetectionState_FailedCopyWithImpl<$Res>
    implements $BridgeAcpLocalDetectionState_FailedCopyWith<$Res> {
  _$BridgeAcpLocalDetectionState_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpLocalDetectionState_Failed _self;
  final $Res Function(BridgeAcpLocalDetectionState_Failed) _then;

/// Create a copy of BridgeAcpLocalDetectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeAcpLocalDetectionState_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpLocalDetectionFailure,
  ));
}


}

/// @nodoc


class BridgeAcpLocalDetectionState_Cancelling extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Cancelling(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Cancelling);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.cancelling()';
}


}




/// @nodoc


class BridgeAcpLocalDetectionState_Cancelled extends BridgeAcpLocalDetectionState {
  const BridgeAcpLocalDetectionState_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpLocalDetectionState_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpLocalDetectionState.cancelled()';
}


}




// dart format on
