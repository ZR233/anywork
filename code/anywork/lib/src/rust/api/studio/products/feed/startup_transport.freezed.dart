// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup_transport.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeStartupProgressFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartupProgressFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeStartupProgressFrame()';
}


}

/// @nodoc
class $BridgeStartupProgressFrameCopyWith<$Res>  {
$BridgeStartupProgressFrameCopyWith(BridgeStartupProgressFrame _, $Res Function(BridgeStartupProgressFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeStartupProgressFrame].
extension BridgeStartupProgressFramePatterns on BridgeStartupProgressFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeStartupProgressFrame_Data value)?  data,TResult Function( BridgeStartupProgressFrame_Failure value)?  failure,TResult Function( BridgeStartupProgressFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data() when data != null:
return data(_that);case BridgeStartupProgressFrame_Failure() when failure != null:
return failure(_that);case BridgeStartupProgressFrame_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeStartupProgressFrame_Data value)  data,required TResult Function( BridgeStartupProgressFrame_Failure value)  failure,required TResult Function( BridgeStartupProgressFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data():
return data(_that);case BridgeStartupProgressFrame_Failure():
return failure(_that);case BridgeStartupProgressFrame_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeStartupProgressFrame_Data value)?  data,TResult? Function( BridgeStartupProgressFrame_Failure value)?  failure,TResult? Function( BridgeStartupProgressFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data() when data != null:
return data(_that);case BridgeStartupProgressFrame_Failure() when failure != null:
return failure(_that);case BridgeStartupProgressFrame_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeStartupStage stage)?  data,TResult Function( BridgeError error)?  failure,TResult Function( BridgeStartupCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data() when data != null:
return data(_that.deliverySequence,_that.stage);case BridgeStartupProgressFrame_Failure() when failure != null:
return failure(_that.error);case BridgeStartupProgressFrame_Closed() when closed != null:
return closed(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeStartupStage stage)  data,required TResult Function( BridgeError error)  failure,required TResult Function( BridgeStartupCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data():
return data(_that.deliverySequence,_that.stage);case BridgeStartupProgressFrame_Failure():
return failure(_that.error);case BridgeStartupProgressFrame_Closed():
return closed(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeStartupStage stage)?  data,TResult? Function( BridgeError error)?  failure,TResult? Function( BridgeStartupCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeStartupProgressFrame_Data() when data != null:
return data(_that.deliverySequence,_that.stage);case BridgeStartupProgressFrame_Failure() when failure != null:
return failure(_that.error);case BridgeStartupProgressFrame_Closed() when closed != null:
return closed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeStartupProgressFrame_Data extends BridgeStartupProgressFrame {
  const BridgeStartupProgressFrame_Data({required this.deliverySequence, required this.stage}): super._();


 final  BigInt deliverySequence;
 final  BridgeStartupStage stage;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartupProgressFrame_DataCopyWith<BridgeStartupProgressFrame_Data> get copyWith => _$BridgeStartupProgressFrame_DataCopyWithImpl<BridgeStartupProgressFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartupProgressFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,stage);
}

@override
String toString() {
    return 'BridgeStartupProgressFrame.data(deliverySequence: $deliverySequence, stage: $stage)';
}


}

/// @nodoc
abstract mixin class $BridgeStartupProgressFrame_DataCopyWith<$Res> implements $BridgeStartupProgressFrameCopyWith<$Res> {
  factory $BridgeStartupProgressFrame_DataCopyWith(BridgeStartupProgressFrame_Data value, $Res Function(BridgeStartupProgressFrame_Data) _then) = _$BridgeStartupProgressFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeStartupStage stage
});




}
/// @nodoc
class _$BridgeStartupProgressFrame_DataCopyWithImpl<$Res>
    implements $BridgeStartupProgressFrame_DataCopyWith<$Res> {
  _$BridgeStartupProgressFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeStartupProgressFrame_Data _self;
  final $Res Function(BridgeStartupProgressFrame_Data) _then;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? stage = null,}) {
  return _then(BridgeStartupProgressFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as BridgeStartupStage,
  ));
}


}

/// @nodoc


class BridgeStartupProgressFrame_Failure extends BridgeStartupProgressFrame {
  const BridgeStartupProgressFrame_Failure({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartupProgressFrame_FailureCopyWith<BridgeStartupProgressFrame_Failure> get copyWith => _$BridgeStartupProgressFrame_FailureCopyWithImpl<BridgeStartupProgressFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartupProgressFrame_Failure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeStartupProgressFrame.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeStartupProgressFrame_FailureCopyWith<$Res> implements $BridgeStartupProgressFrameCopyWith<$Res> {
  factory $BridgeStartupProgressFrame_FailureCopyWith(BridgeStartupProgressFrame_Failure value, $Res Function(BridgeStartupProgressFrame_Failure) _then) = _$BridgeStartupProgressFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeStartupProgressFrame_FailureCopyWithImpl<$Res>
    implements $BridgeStartupProgressFrame_FailureCopyWith<$Res> {
  _$BridgeStartupProgressFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeStartupProgressFrame_Failure _self;
  final $Res Function(BridgeStartupProgressFrame_Failure) _then;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeStartupProgressFrame_Failure(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeStartupProgressFrame_Closed extends BridgeStartupProgressFrame {
  const BridgeStartupProgressFrame_Closed({required this.reason}): super._();


 final  BridgeStartupCloseReason reason;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartupProgressFrame_ClosedCopyWith<BridgeStartupProgressFrame_Closed> get copyWith => _$BridgeStartupProgressFrame_ClosedCopyWithImpl<BridgeStartupProgressFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartupProgressFrame_Closed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeStartupProgressFrame.closed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeStartupProgressFrame_ClosedCopyWith<$Res> implements $BridgeStartupProgressFrameCopyWith<$Res> {
  factory $BridgeStartupProgressFrame_ClosedCopyWith(BridgeStartupProgressFrame_Closed value, $Res Function(BridgeStartupProgressFrame_Closed) _then) = _$BridgeStartupProgressFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeStartupCloseReason reason
});




}
/// @nodoc
class _$BridgeStartupProgressFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeStartupProgressFrame_ClosedCopyWith<$Res> {
  _$BridgeStartupProgressFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeStartupProgressFrame_Closed _self;
  final $Res Function(BridgeStartupProgressFrame_Closed) _then;

/// Create a copy of BridgeStartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeStartupProgressFrame_Closed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeStartupCloseReason,
  ));
}


}

// dart format on
