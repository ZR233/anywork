// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_preparation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeNewThreadStartEvent {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeNewThreadStartEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeNewThreadStartEvent&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeNewThreadStartEvent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeNewThreadStartEvent;
  return 'BridgeNewThreadStartEvent(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeNewThreadStartEventCopyWith<$Res>  {
$BridgeNewThreadStartEventCopyWith(BridgeNewThreadStartEvent _, $Res Function(BridgeNewThreadStartEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeNewThreadStartEvent].
extension BridgeNewThreadStartEventPatterns on BridgeNewThreadStartEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeNewThreadStartEvent_Progress value)?  progress,TResult Function( BridgeNewThreadStartEvent_Succeeded value)?  succeeded,TResult Function( BridgeNewThreadStartEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress() when progress != null:
return progress(_that);case BridgeNewThreadStartEvent_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeNewThreadStartEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeNewThreadStartEvent_Progress value)  progress,required TResult Function( BridgeNewThreadStartEvent_Succeeded value)  succeeded,required TResult Function( BridgeNewThreadStartEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress():
return progress(_that);case BridgeNewThreadStartEvent_Succeeded():
return succeeded(_that);case BridgeNewThreadStartEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeNewThreadStartEvent_Progress value)?  progress,TResult? Function( BridgeNewThreadStartEvent_Succeeded value)?  succeeded,TResult? Function( BridgeNewThreadStartEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress() when progress != null:
return progress(_that);case BridgeNewThreadStartEvent_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeNewThreadStartEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadPreparationProgress field0)?  progress,TResult Function( StartNewThreadResponse field0)?  succeeded,TResult Function( BridgeError field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress() when progress != null:
return progress(_that.field0);case BridgeNewThreadStartEvent_Succeeded() when succeeded != null:
return succeeded(_that.field0);case BridgeNewThreadStartEvent_Failed() when failed != null:
return failed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadPreparationProgress field0)  progress,required TResult Function( StartNewThreadResponse field0)  succeeded,required TResult Function( BridgeError field0)  failed,}) {final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress():
return progress(_that.field0);case BridgeNewThreadStartEvent_Succeeded():
return succeeded(_that.field0);case BridgeNewThreadStartEvent_Failed():
return failed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadPreparationProgress field0)?  progress,TResult? Function( StartNewThreadResponse field0)?  succeeded,TResult? Function( BridgeError field0)?  failed,}) {final _that = this;
switch (_that) {
case BridgeNewThreadStartEvent_Progress() when progress != null:
return progress(_that.field0);case BridgeNewThreadStartEvent_Succeeded() when succeeded != null:
return succeeded(_that.field0);case BridgeNewThreadStartEvent_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeNewThreadStartEvent_Progress extends BridgeNewThreadStartEvent {
  const BridgeNewThreadStartEvent_Progress(this.field0): super._();


@override final  BridgeThreadPreparationProgress field0;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeNewThreadStartEvent_ProgressCopyWith<BridgeNewThreadStartEvent_Progress> get copyWith => _$BridgeNewThreadStartEvent_ProgressCopyWithImpl<BridgeNewThreadStartEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeNewThreadStartEvent_Progress&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeNewThreadStartEvent.progress(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeNewThreadStartEvent_ProgressCopyWith<$Res> implements $BridgeNewThreadStartEventCopyWith<$Res> {
  factory $BridgeNewThreadStartEvent_ProgressCopyWith(BridgeNewThreadStartEvent_Progress value, $Res Function(BridgeNewThreadStartEvent_Progress) _then) = _$BridgeNewThreadStartEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 BridgeThreadPreparationProgress field0
});




}
/// @nodoc
class _$BridgeNewThreadStartEvent_ProgressCopyWithImpl<$Res>
    implements $BridgeNewThreadStartEvent_ProgressCopyWith<$Res> {
  _$BridgeNewThreadStartEvent_ProgressCopyWithImpl(this._self, this._then);

  final BridgeNewThreadStartEvent_Progress _self;
  final $Res Function(BridgeNewThreadStartEvent_Progress) _then;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeNewThreadStartEvent_Progress(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeThreadPreparationProgress,
  ));
}


}

/// @nodoc


class BridgeNewThreadStartEvent_Succeeded extends BridgeNewThreadStartEvent {
  const BridgeNewThreadStartEvent_Succeeded(this.field0): super._();


@override final  StartNewThreadResponse field0;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeNewThreadStartEvent_SucceededCopyWith<BridgeNewThreadStartEvent_Succeeded> get copyWith => _$BridgeNewThreadStartEvent_SucceededCopyWithImpl<BridgeNewThreadStartEvent_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeNewThreadStartEvent_Succeeded&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeNewThreadStartEvent.succeeded(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeNewThreadStartEvent_SucceededCopyWith<$Res> implements $BridgeNewThreadStartEventCopyWith<$Res> {
  factory $BridgeNewThreadStartEvent_SucceededCopyWith(BridgeNewThreadStartEvent_Succeeded value, $Res Function(BridgeNewThreadStartEvent_Succeeded) _then) = _$BridgeNewThreadStartEvent_SucceededCopyWithImpl;
@useResult
$Res call({
 StartNewThreadResponse field0
});




}
/// @nodoc
class _$BridgeNewThreadStartEvent_SucceededCopyWithImpl<$Res>
    implements $BridgeNewThreadStartEvent_SucceededCopyWith<$Res> {
  _$BridgeNewThreadStartEvent_SucceededCopyWithImpl(this._self, this._then);

  final BridgeNewThreadStartEvent_Succeeded _self;
  final $Res Function(BridgeNewThreadStartEvent_Succeeded) _then;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeNewThreadStartEvent_Succeeded(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as StartNewThreadResponse,
  ));
}


}

/// @nodoc


class BridgeNewThreadStartEvent_Failed extends BridgeNewThreadStartEvent {
  const BridgeNewThreadStartEvent_Failed(this.field0): super._();


@override final  BridgeError field0;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeNewThreadStartEvent_FailedCopyWith<BridgeNewThreadStartEvent_Failed> get copyWith => _$BridgeNewThreadStartEvent_FailedCopyWithImpl<BridgeNewThreadStartEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeNewThreadStartEvent_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeNewThreadStartEvent.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeNewThreadStartEvent_FailedCopyWith<$Res> implements $BridgeNewThreadStartEventCopyWith<$Res> {
  factory $BridgeNewThreadStartEvent_FailedCopyWith(BridgeNewThreadStartEvent_Failed value, $Res Function(BridgeNewThreadStartEvent_Failed) _then) = _$BridgeNewThreadStartEvent_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeError field0
});




}
/// @nodoc
class _$BridgeNewThreadStartEvent_FailedCopyWithImpl<$Res>
    implements $BridgeNewThreadStartEvent_FailedCopyWith<$Res> {
  _$BridgeNewThreadStartEvent_FailedCopyWithImpl(this._self, this._then);

  final BridgeNewThreadStartEvent_Failed _self;
  final $Res Function(BridgeNewThreadStartEvent_Failed) _then;

/// Create a copy of BridgeNewThreadStartEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeNewThreadStartEvent_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

// dart format on
