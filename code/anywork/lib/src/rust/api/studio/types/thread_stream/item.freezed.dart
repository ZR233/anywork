// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeThreadWaitIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadWaitIntent()';
}


}

/// @nodoc
class $BridgeThreadWaitIntentCopyWith<$Res>  {
$BridgeThreadWaitIntentCopyWith(BridgeThreadWaitIntent _, $Res Function(BridgeThreadWaitIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadWaitIntent].
extension BridgeThreadWaitIntentPatterns on BridgeThreadWaitIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadWaitIntent_Events value)?  events,TResult Function( BridgeThreadWaitIntent_Timer value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadWaitIntent_Events value)  events,required TResult Function( BridgeThreadWaitIntent_Timer value)  timer,}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events():
return events(_that);case BridgeThreadWaitIntent_Timer():
return timer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadWaitIntent_Events value)?  events,TResult? Function( BridgeThreadWaitIntent_Timer value)?  timer,}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)?  events,TResult Function( BigInt durationMs)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)  events,required TResult Function( BigInt durationMs)  timer,}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events():
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer():
return timer(_that.durationMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)?  events,TResult? Function( BigInt durationMs)?  timer,}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadWaitIntent_Events extends BridgeThreadWaitIntent {
  const BridgeThreadWaitIntent_Events({required  List<BridgeThreadWaitTarget> targets, required this.timeoutMs}): _targets = targets,super._();


 final  List<BridgeThreadWaitTarget> _targets;
 List<BridgeThreadWaitTarget> get targets {
  if (_targets is EqualUnmodifiableListView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targets);
}

 final  BigInt timeoutMs;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadWaitIntent_EventsCopyWith<BridgeThreadWaitIntent_Events> get copyWith => _$BridgeThreadWaitIntent_EventsCopyWithImpl<BridgeThreadWaitIntent_Events>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent_Events&&const DeepCollectionEquality().equals(other.targets, _targets)&&(identical(other.timeoutMs, timeoutMs) || other.timeoutMs == timeoutMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_targets),timeoutMs);
}

@override
String toString() {
    return 'BridgeThreadWaitIntent.events(targets: $targets, timeoutMs: $timeoutMs)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadWaitIntent_EventsCopyWith<$Res> implements $BridgeThreadWaitIntentCopyWith<$Res> {
  factory $BridgeThreadWaitIntent_EventsCopyWith(BridgeThreadWaitIntent_Events value, $Res Function(BridgeThreadWaitIntent_Events) _then) = _$BridgeThreadWaitIntent_EventsCopyWithImpl;
@useResult
$Res call({
 List<BridgeThreadWaitTarget> targets, BigInt timeoutMs
});




}
/// @nodoc
class _$BridgeThreadWaitIntent_EventsCopyWithImpl<$Res>
    implements $BridgeThreadWaitIntent_EventsCopyWith<$Res> {
  _$BridgeThreadWaitIntent_EventsCopyWithImpl(this._self, this._then);

  final BridgeThreadWaitIntent_Events _self;
  final $Res Function(BridgeThreadWaitIntent_Events) _then;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targets = null,Object? timeoutMs = null,}) {
  return _then(BridgeThreadWaitIntent_Events(
targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as List<BridgeThreadWaitTarget>,timeoutMs: null == timeoutMs ? _self.timeoutMs : timeoutMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeThreadWaitIntent_Timer extends BridgeThreadWaitIntent {
  const BridgeThreadWaitIntent_Timer({required this.durationMs}): super._();


 final  BigInt durationMs;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadWaitIntent_TimerCopyWith<BridgeThreadWaitIntent_Timer> get copyWith => _$BridgeThreadWaitIntent_TimerCopyWithImpl<BridgeThreadWaitIntent_Timer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent_Timer&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,durationMs);
}

@override
String toString() {
    return 'BridgeThreadWaitIntent.timer(durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadWaitIntent_TimerCopyWith<$Res> implements $BridgeThreadWaitIntentCopyWith<$Res> {
  factory $BridgeThreadWaitIntent_TimerCopyWith(BridgeThreadWaitIntent_Timer value, $Res Function(BridgeThreadWaitIntent_Timer) _then) = _$BridgeThreadWaitIntent_TimerCopyWithImpl;
@useResult
$Res call({
 BigInt durationMs
});




}
/// @nodoc
class _$BridgeThreadWaitIntent_TimerCopyWithImpl<$Res>
    implements $BridgeThreadWaitIntent_TimerCopyWith<$Res> {
  _$BridgeThreadWaitIntent_TimerCopyWithImpl(this._self, this._then);

  final BridgeThreadWaitIntent_Timer _self;
  final $Res Function(BridgeThreadWaitIntent_Timer) _then;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationMs = null,}) {
  return _then(BridgeThreadWaitIntent_Timer(
durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
