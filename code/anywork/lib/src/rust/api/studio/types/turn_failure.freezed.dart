// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'turn_failure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRetryDisposition {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRetryDisposition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeRetryDisposition()';
}


}

/// @nodoc
class $BridgeRetryDispositionCopyWith<$Res>  {
$BridgeRetryDispositionCopyWith(BridgeRetryDisposition _, $Res Function(BridgeRetryDisposition) __);
}


/// Adds pattern-matching-related methods to [BridgeRetryDisposition].
extension BridgeRetryDispositionPatterns on BridgeRetryDisposition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRetryDisposition_Retryable value)?  retryable,TResult Function( BridgeRetryDisposition_Permanent value)?  permanent,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable() when retryable != null:
return retryable(_that);case BridgeRetryDisposition_Permanent() when permanent != null:
return permanent(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRetryDisposition_Retryable value)  retryable,required TResult Function( BridgeRetryDisposition_Permanent value)  permanent,}){
final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable():
return retryable(_that);case BridgeRetryDisposition_Permanent():
return permanent(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRetryDisposition_Retryable value)?  retryable,TResult? Function( BridgeRetryDisposition_Permanent value)?  permanent,}){
final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable() when retryable != null:
return retryable(_that);case BridgeRetryDisposition_Permanent() when permanent != null:
return permanent(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt? retryAfterMs)?  retryable,TResult Function()?  permanent,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable() when retryable != null:
return retryable(_that.retryAfterMs);case BridgeRetryDisposition_Permanent() when permanent != null:
return permanent();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt? retryAfterMs)  retryable,required TResult Function()  permanent,}) {final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable():
return retryable(_that.retryAfterMs);case BridgeRetryDisposition_Permanent():
return permanent();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt? retryAfterMs)?  retryable,TResult? Function()?  permanent,}) {final _that = this;
switch (_that) {
case BridgeRetryDisposition_Retryable() when retryable != null:
return retryable(_that.retryAfterMs);case BridgeRetryDisposition_Permanent() when permanent != null:
return permanent();case _:
  return null;

}
}

}

/// @nodoc


class BridgeRetryDisposition_Retryable extends BridgeRetryDisposition {
  const BridgeRetryDisposition_Retryable({this.retryAfterMs}): super._();


 final  BigInt? retryAfterMs;

/// Create a copy of BridgeRetryDisposition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRetryDisposition_RetryableCopyWith<BridgeRetryDisposition_Retryable> get copyWith => _$BridgeRetryDisposition_RetryableCopyWithImpl<BridgeRetryDisposition_Retryable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRetryDisposition_Retryable&&(identical(other.retryAfterMs, retryAfterMs) || other.retryAfterMs == retryAfterMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,retryAfterMs);
}

@override
String toString() {
    return 'BridgeRetryDisposition.retryable(retryAfterMs: $retryAfterMs)';
}


}

/// @nodoc
abstract mixin class $BridgeRetryDisposition_RetryableCopyWith<$Res> implements $BridgeRetryDispositionCopyWith<$Res> {
  factory $BridgeRetryDisposition_RetryableCopyWith(BridgeRetryDisposition_Retryable value, $Res Function(BridgeRetryDisposition_Retryable) _then) = _$BridgeRetryDisposition_RetryableCopyWithImpl;
@useResult
$Res call({
 BigInt? retryAfterMs
});




}
/// @nodoc
class _$BridgeRetryDisposition_RetryableCopyWithImpl<$Res>
    implements $BridgeRetryDisposition_RetryableCopyWith<$Res> {
  _$BridgeRetryDisposition_RetryableCopyWithImpl(this._self, this._then);

  final BridgeRetryDisposition_Retryable _self;
  final $Res Function(BridgeRetryDisposition_Retryable) _then;

/// Create a copy of BridgeRetryDisposition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? retryAfterMs = freezed,}) {
  return _then(BridgeRetryDisposition_Retryable(
retryAfterMs: freezed == retryAfterMs ? _self.retryAfterMs : retryAfterMs // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class BridgeRetryDisposition_Permanent extends BridgeRetryDisposition {
  const BridgeRetryDisposition_Permanent(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRetryDisposition_Permanent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeRetryDisposition.permanent()';
}


}




// dart format on
