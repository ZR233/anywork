// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'command.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeContinuationOperationState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationOperationState()';
}


}

/// @nodoc
class $BridgeContinuationOperationStateCopyWith<$Res>  {
$BridgeContinuationOperationStateCopyWith(BridgeContinuationOperationState _, $Res Function(BridgeContinuationOperationState) __);
}


/// Adds pattern-matching-related methods to [BridgeContinuationOperationState].
extension BridgeContinuationOperationStatePatterns on BridgeContinuationOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContinuationOperationState_Pending value)?  pending,TResult Function( BridgeContinuationOperationState_Consumed value)?  consumed,TResult Function( BridgeContinuationOperationState_Discarded value)?  discarded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending() when pending != null:
return pending(_that);case BridgeContinuationOperationState_Consumed() when consumed != null:
return consumed(_that);case BridgeContinuationOperationState_Discarded() when discarded != null:
return discarded(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContinuationOperationState_Pending value)  pending,required TResult Function( BridgeContinuationOperationState_Consumed value)  consumed,required TResult Function( BridgeContinuationOperationState_Discarded value)  discarded,}){
final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending():
return pending(_that);case BridgeContinuationOperationState_Consumed():
return consumed(_that);case BridgeContinuationOperationState_Discarded():
return discarded(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContinuationOperationState_Pending value)?  pending,TResult? Function( BridgeContinuationOperationState_Consumed value)?  consumed,TResult? Function( BridgeContinuationOperationState_Discarded value)?  discarded,}){
final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending() when pending != null:
return pending(_that);case BridgeContinuationOperationState_Consumed() when consumed != null:
return consumed(_that);case BridgeContinuationOperationState_Discarded() when discarded != null:
return discarded(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pending,TResult Function( String turnId)?  consumed,TResult Function()?  discarded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending() when pending != null:
return pending();case BridgeContinuationOperationState_Consumed() when consumed != null:
return consumed(_that.turnId);case BridgeContinuationOperationState_Discarded() when discarded != null:
return discarded();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pending,required TResult Function( String turnId)  consumed,required TResult Function()  discarded,}) {final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending():
return pending();case BridgeContinuationOperationState_Consumed():
return consumed(_that.turnId);case BridgeContinuationOperationState_Discarded():
return discarded();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pending,TResult? Function( String turnId)?  consumed,TResult? Function()?  discarded,}) {final _that = this;
switch (_that) {
case BridgeContinuationOperationState_Pending() when pending != null:
return pending();case BridgeContinuationOperationState_Consumed() when consumed != null:
return consumed(_that.turnId);case BridgeContinuationOperationState_Discarded() when discarded != null:
return discarded();case _:
  return null;

}
}

}

/// @nodoc


class BridgeContinuationOperationState_Pending extends BridgeContinuationOperationState {
  const BridgeContinuationOperationState_Pending(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationOperationState_Pending);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationOperationState.pending()';
}


}




/// @nodoc


class BridgeContinuationOperationState_Consumed extends BridgeContinuationOperationState {
  const BridgeContinuationOperationState_Consumed({required this.turnId}): super._();


 final  String turnId;

/// Create a copy of BridgeContinuationOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContinuationOperationState_ConsumedCopyWith<BridgeContinuationOperationState_Consumed> get copyWith => _$BridgeContinuationOperationState_ConsumedCopyWithImpl<BridgeContinuationOperationState_Consumed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationOperationState_Consumed&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeContinuationOperationState.consumed(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeContinuationOperationState_ConsumedCopyWith<$Res> implements $BridgeContinuationOperationStateCopyWith<$Res> {
  factory $BridgeContinuationOperationState_ConsumedCopyWith(BridgeContinuationOperationState_Consumed value, $Res Function(BridgeContinuationOperationState_Consumed) _then) = _$BridgeContinuationOperationState_ConsumedCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$BridgeContinuationOperationState_ConsumedCopyWithImpl<$Res>
    implements $BridgeContinuationOperationState_ConsumedCopyWith<$Res> {
  _$BridgeContinuationOperationState_ConsumedCopyWithImpl(this._self, this._then);

  final BridgeContinuationOperationState_Consumed _self;
  final $Res Function(BridgeContinuationOperationState_Consumed) _then;

/// Create a copy of BridgeContinuationOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeContinuationOperationState_Consumed(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContinuationOperationState_Discarded extends BridgeContinuationOperationState {
  const BridgeContinuationOperationState_Discarded(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationOperationState_Discarded);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationOperationState.discarded()';
}


}




// dart format on
