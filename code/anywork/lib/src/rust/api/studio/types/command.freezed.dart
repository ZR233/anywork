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
mixin _$BridgeContinuationDisposition {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationDisposition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationDisposition()';
}


}

/// @nodoc
class $BridgeContinuationDispositionCopyWith<$Res>  {
$BridgeContinuationDispositionCopyWith(BridgeContinuationDisposition _, $Res Function(BridgeContinuationDisposition) __);
}


/// Adds pattern-matching-related methods to [BridgeContinuationDisposition].
extension BridgeContinuationDispositionPatterns on BridgeContinuationDisposition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContinuationDisposition_Scheduled value)?  scheduled,TResult Function( BridgeContinuationDisposition_Effective value)?  effective,TResult Function( BridgeContinuationDisposition_NotExecuted value)?  notExecuted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled() when scheduled != null:
return scheduled(_that);case BridgeContinuationDisposition_Effective() when effective != null:
return effective(_that);case BridgeContinuationDisposition_NotExecuted() when notExecuted != null:
return notExecuted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContinuationDisposition_Scheduled value)  scheduled,required TResult Function( BridgeContinuationDisposition_Effective value)  effective,required TResult Function( BridgeContinuationDisposition_NotExecuted value)  notExecuted,}){
final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled():
return scheduled(_that);case BridgeContinuationDisposition_Effective():
return effective(_that);case BridgeContinuationDisposition_NotExecuted():
return notExecuted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContinuationDisposition_Scheduled value)?  scheduled,TResult? Function( BridgeContinuationDisposition_Effective value)?  effective,TResult? Function( BridgeContinuationDisposition_NotExecuted value)?  notExecuted,}){
final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled() when scheduled != null:
return scheduled(_that);case BridgeContinuationDisposition_Effective() when effective != null:
return effective(_that);case BridgeContinuationDisposition_NotExecuted() when notExecuted != null:
return notExecuted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  scheduled,TResult Function()?  effective,TResult Function( String reason)?  notExecuted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled() when scheduled != null:
return scheduled();case BridgeContinuationDisposition_Effective() when effective != null:
return effective();case BridgeContinuationDisposition_NotExecuted() when notExecuted != null:
return notExecuted(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  scheduled,required TResult Function()  effective,required TResult Function( String reason)  notExecuted,}) {final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled():
return scheduled();case BridgeContinuationDisposition_Effective():
return effective();case BridgeContinuationDisposition_NotExecuted():
return notExecuted(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  scheduled,TResult? Function()?  effective,TResult? Function( String reason)?  notExecuted,}) {final _that = this;
switch (_that) {
case BridgeContinuationDisposition_Scheduled() when scheduled != null:
return scheduled();case BridgeContinuationDisposition_Effective() when effective != null:
return effective();case BridgeContinuationDisposition_NotExecuted() when notExecuted != null:
return notExecuted(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContinuationDisposition_Scheduled extends BridgeContinuationDisposition {
  const BridgeContinuationDisposition_Scheduled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationDisposition_Scheduled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationDisposition.scheduled()';
}


}




/// @nodoc


class BridgeContinuationDisposition_Effective extends BridgeContinuationDisposition {
  const BridgeContinuationDisposition_Effective(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationDisposition_Effective);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContinuationDisposition.effective()';
}


}




/// @nodoc


class BridgeContinuationDisposition_NotExecuted extends BridgeContinuationDisposition {
  const BridgeContinuationDisposition_NotExecuted({required this.reason}): super._();


 final  String reason;

/// Create a copy of BridgeContinuationDisposition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContinuationDisposition_NotExecutedCopyWith<BridgeContinuationDisposition_NotExecuted> get copyWith => _$BridgeContinuationDisposition_NotExecutedCopyWithImpl<BridgeContinuationDisposition_NotExecuted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContinuationDisposition_NotExecuted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeContinuationDisposition.notExecuted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeContinuationDisposition_NotExecutedCopyWith<$Res> implements $BridgeContinuationDispositionCopyWith<$Res> {
  factory $BridgeContinuationDisposition_NotExecutedCopyWith(BridgeContinuationDisposition_NotExecuted value, $Res Function(BridgeContinuationDisposition_NotExecuted) _then) = _$BridgeContinuationDisposition_NotExecutedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$BridgeContinuationDisposition_NotExecutedCopyWithImpl<$Res>
    implements $BridgeContinuationDisposition_NotExecutedCopyWith<$Res> {
  _$BridgeContinuationDisposition_NotExecutedCopyWithImpl(this._self, this._then);

  final BridgeContinuationDisposition_NotExecuted _self;
  final $Res Function(BridgeContinuationDisposition_NotExecuted) _then;

/// Create a copy of BridgeContinuationDisposition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeContinuationDisposition_NotExecuted(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
