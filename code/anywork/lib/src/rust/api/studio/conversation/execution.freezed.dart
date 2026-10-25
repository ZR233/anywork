// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'execution.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeActivityReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeActivityReplacement()';
}


}

/// @nodoc
class $BridgeActivityReplacementCopyWith<$Res>  {
$BridgeActivityReplacementCopyWith(BridgeActivityReplacement _, $Res Function(BridgeActivityReplacement) __);
}


/// Adds pattern-matching-related methods to [BridgeActivityReplacement].
extension BridgeActivityReplacementPatterns on BridgeActivityReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeActivityReplacement_Unchanged value)?  unchanged,TResult Function( BridgeActivityReplacement_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeActivityReplacement_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeActivityReplacement_Unchanged value)  unchanged,required TResult Function( BridgeActivityReplacement_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged():
return unchanged(_that);case BridgeActivityReplacement_Replace():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeActivityReplacement_Unchanged value)?  unchanged,TResult? Function( BridgeActivityReplacement_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeActivityReplacement_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( BridgeActivityBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeActivityReplacement_Replace() when replace != null:
return replace(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( BridgeActivityBrief? value)  replace,}) {final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged():
return unchanged();case BridgeActivityReplacement_Replace():
return replace(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( BridgeActivityBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeActivityReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeActivityReplacement_Replace() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeActivityReplacement_Unchanged extends BridgeActivityReplacement {
  const BridgeActivityReplacement_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityReplacement_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeActivityReplacement.unchanged()';
}


}




/// @nodoc


class BridgeActivityReplacement_Replace extends BridgeActivityReplacement {
  const BridgeActivityReplacement_Replace({this.value}): super._();


 final  BridgeActivityBrief? value;

/// Create a copy of BridgeActivityReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityReplacement_ReplaceCopyWith<BridgeActivityReplacement_Replace> get copyWith => _$BridgeActivityReplacement_ReplaceCopyWithImpl<BridgeActivityReplacement_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityReplacement_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeActivityReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityReplacement_ReplaceCopyWith<$Res> implements $BridgeActivityReplacementCopyWith<$Res> {
  factory $BridgeActivityReplacement_ReplaceCopyWith(BridgeActivityReplacement_Replace value, $Res Function(BridgeActivityReplacement_Replace) _then) = _$BridgeActivityReplacement_ReplaceCopyWithImpl;
@useResult
$Res call({
 BridgeActivityBrief? value
});




}
/// @nodoc
class _$BridgeActivityReplacement_ReplaceCopyWithImpl<$Res>
    implements $BridgeActivityReplacement_ReplaceCopyWith<$Res> {
  _$BridgeActivityReplacement_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeActivityReplacement_Replace _self;
  final $Res Function(BridgeActivityReplacement_Replace) _then;

/// Create a copy of BridgeActivityReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(BridgeActivityReplacement_Replace(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeActivityBrief?,
  ));
}


}

/// @nodoc
mixin _$BridgeExecutionEvent {

 BridgeThreadFacetStamp get stamp; Object get value;
/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionEventCopyWith<BridgeExecutionEvent> get copyWith => _$BridgeExecutionEventCopyWithImpl<BridgeExecutionEvent>(this as BridgeExecutionEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeExecutionEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeExecutionEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeExecutionEvent;
  return 'BridgeExecutionEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionEventCopyWith<$Res>  {
  factory $BridgeExecutionEventCopyWith(BridgeExecutionEvent value, $Res Function(BridgeExecutionEvent) _then) = _$BridgeExecutionEventCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFacetStamp stamp
});




}
/// @nodoc
class _$BridgeExecutionEventCopyWithImpl<$Res>
    implements $BridgeExecutionEventCopyWith<$Res> {
  _$BridgeExecutionEventCopyWithImpl(this._self, this._then);

  final BridgeExecutionEvent _self;
  final $Res Function(BridgeExecutionEvent) _then;

/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeExecutionEvent].
extension BridgeExecutionEventPatterns on BridgeExecutionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeExecutionEvent_Baseline value)?  baseline,TResult Function( BridgeExecutionEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeExecutionEvent_Change() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeExecutionEvent_Baseline value)  baseline,required TResult Function( BridgeExecutionEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline():
return baseline(_that);case BridgeExecutionEvent_Change():
return change(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeExecutionEvent_Baseline value)?  baseline,TResult? Function( BridgeExecutionEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeExecutionEvent_Change() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeExecutionBaseline value)?  baseline,TResult Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeExecutionChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeExecutionEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeExecutionBaseline value)  baseline,required TResult Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeExecutionChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeExecutionEvent_Change():
return change(_that.stamp,_that.baseRevision,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeExecutionBaseline value)?  baseline,TResult? Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeExecutionChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeExecutionEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeExecutionEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeExecutionEvent_Baseline extends BridgeExecutionEvent {
  const BridgeExecutionEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeThreadFeedIdentity identity;
@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeExecutionBaseline value;

/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionEvent_BaselineCopyWith<BridgeExecutionEvent_Baseline> get copyWith => _$BridgeExecutionEvent_BaselineCopyWithImpl<BridgeExecutionEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeExecutionEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionEvent_BaselineCopyWith<$Res> implements $BridgeExecutionEventCopyWith<$Res> {
  factory $BridgeExecutionEvent_BaselineCopyWith(BridgeExecutionEvent_Baseline value, $Res Function(BridgeExecutionEvent_Baseline) _then) = _$BridgeExecutionEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeThreadFacetStamp stamp, BridgeExecutionBaseline value
});




}
/// @nodoc
class _$BridgeExecutionEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeExecutionEvent_BaselineCopyWith<$Res> {
  _$BridgeExecutionEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeExecutionEvent_Baseline _self;
  final $Res Function(BridgeExecutionEvent_Baseline) _then;

/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeExecutionEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeExecutionBaseline,
  ));
}


}

/// @nodoc


class BridgeExecutionEvent_Change extends BridgeExecutionEvent {
  const BridgeExecutionEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeThreadFacetStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeExecutionChange value;

/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionEvent_ChangeCopyWith<BridgeExecutionEvent_Change> get copyWith => _$BridgeExecutionEvent_ChangeCopyWithImpl<BridgeExecutionEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeExecutionEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionEvent_ChangeCopyWith<$Res> implements $BridgeExecutionEventCopyWith<$Res> {
  factory $BridgeExecutionEvent_ChangeCopyWith(BridgeExecutionEvent_Change value, $Res Function(BridgeExecutionEvent_Change) _then) = _$BridgeExecutionEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFacetStamp stamp, BigInt baseRevision, BridgeExecutionChange value
});




}
/// @nodoc
class _$BridgeExecutionEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeExecutionEvent_ChangeCopyWith<$Res> {
  _$BridgeExecutionEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeExecutionEvent_Change _self;
  final $Res Function(BridgeExecutionEvent_Change) _then;

/// Create a copy of BridgeExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeExecutionEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeExecutionChange,
  ));
}


}

/// @nodoc
mixin _$BridgeExecutionFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeExecutionFrame()';
}


}

/// @nodoc
class $BridgeExecutionFrameCopyWith<$Res>  {
$BridgeExecutionFrameCopyWith(BridgeExecutionFrame _, $Res Function(BridgeExecutionFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeExecutionFrame].
extension BridgeExecutionFramePatterns on BridgeExecutionFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeExecutionFrame_Data value)?  data,TResult Function( BridgeExecutionFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeExecutionFrame_Failure value)?  failure,TResult Function( BridgeExecutionFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data() when data != null:
return data(_that);case BridgeExecutionFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeExecutionFrame_Failure() when failure != null:
return failure(_that);case BridgeExecutionFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeExecutionFrame_Data value)  data,required TResult Function( BridgeExecutionFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeExecutionFrame_Failure value)  failure,required TResult Function( BridgeExecutionFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data():
return data(_that);case BridgeExecutionFrame_ResyncRequired():
return resyncRequired(_that);case BridgeExecutionFrame_Failure():
return failure(_that);case BridgeExecutionFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeExecutionFrame_Data value)?  data,TResult? Function( BridgeExecutionFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeExecutionFrame_Failure value)?  failure,TResult? Function( BridgeExecutionFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data() when data != null:
return data(_that);case BridgeExecutionFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeExecutionFrame_Failure() when failure != null:
return failure(_that);case BridgeExecutionFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeExecutionEvent event)?  data,TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeExecutionFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeExecutionFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeExecutionFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeExecutionEvent event)  data,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)  resyncRequired,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeExecutionFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeExecutionFrame_Failure():
return failure(_that.identity,_that.error);case BridgeExecutionFrame_Closed():
return closed(_that.identity,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeExecutionEvent event)?  data,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeExecutionFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeExecutionFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeExecutionFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeExecutionFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeExecutionFrame_Data extends BridgeExecutionFrame {
  const BridgeExecutionFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeExecutionEvent event;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionFrame_DataCopyWith<BridgeExecutionFrame_Data> get copyWith => _$BridgeExecutionFrame_DataCopyWithImpl<BridgeExecutionFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeExecutionFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionFrame_DataCopyWith<$Res> implements $BridgeExecutionFrameCopyWith<$Res> {
  factory $BridgeExecutionFrame_DataCopyWith(BridgeExecutionFrame_Data value, $Res Function(BridgeExecutionFrame_Data) _then) = _$BridgeExecutionFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeExecutionEvent event
});


$BridgeExecutionEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeExecutionFrame_DataCopyWithImpl<$Res>
    implements $BridgeExecutionFrame_DataCopyWith<$Res> {
  _$BridgeExecutionFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeExecutionFrame_Data _self;
  final $Res Function(BridgeExecutionFrame_Data) _then;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeExecutionFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeExecutionEvent,
  ));
}

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeExecutionEventCopyWith<$Res> get event {

  return $BridgeExecutionEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeExecutionFrame_ResyncRequired extends BridgeExecutionFrame {
  const BridgeExecutionFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeResyncReason reason;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionFrame_ResyncRequiredCopyWith<BridgeExecutionFrame_ResyncRequired> get copyWith => _$BridgeExecutionFrame_ResyncRequiredCopyWithImpl<BridgeExecutionFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeExecutionFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionFrame_ResyncRequiredCopyWith<$Res> implements $BridgeExecutionFrameCopyWith<$Res> {
  factory $BridgeExecutionFrame_ResyncRequiredCopyWith(BridgeExecutionFrame_ResyncRequired value, $Res Function(BridgeExecutionFrame_ResyncRequired) _then) = _$BridgeExecutionFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeResyncReason reason
});




}
/// @nodoc
class _$BridgeExecutionFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeExecutionFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeExecutionFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeExecutionFrame_ResyncRequired _self;
  final $Res Function(BridgeExecutionFrame_ResyncRequired) _then;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeExecutionFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeResyncReason,
  ));
}


}

/// @nodoc


class BridgeExecutionFrame_Failure extends BridgeExecutionFrame {
  const BridgeExecutionFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionFrame_FailureCopyWith<BridgeExecutionFrame_Failure> get copyWith => _$BridgeExecutionFrame_FailureCopyWithImpl<BridgeExecutionFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeExecutionFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionFrame_FailureCopyWith<$Res> implements $BridgeExecutionFrameCopyWith<$Res> {
  factory $BridgeExecutionFrame_FailureCopyWith(BridgeExecutionFrame_Failure value, $Res Function(BridgeExecutionFrame_Failure) _then) = _$BridgeExecutionFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeExecutionFrame_FailureCopyWithImpl<$Res>
    implements $BridgeExecutionFrame_FailureCopyWith<$Res> {
  _$BridgeExecutionFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeExecutionFrame_Failure _self;
  final $Res Function(BridgeExecutionFrame_Failure) _then;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeExecutionFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeExecutionFrame_Closed extends BridgeExecutionFrame {
  const BridgeExecutionFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeFeedClosedReason reason;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExecutionFrame_ClosedCopyWith<BridgeExecutionFrame_Closed> get copyWith => _$BridgeExecutionFrame_ClosedCopyWithImpl<BridgeExecutionFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExecutionFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeExecutionFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeExecutionFrame_ClosedCopyWith<$Res> implements $BridgeExecutionFrameCopyWith<$Res> {
  factory $BridgeExecutionFrame_ClosedCopyWith(BridgeExecutionFrame_Closed value, $Res Function(BridgeExecutionFrame_Closed) _then) = _$BridgeExecutionFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeFeedClosedReason reason
});




}
/// @nodoc
class _$BridgeExecutionFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeExecutionFrame_ClosedCopyWith<$Res> {
  _$BridgeExecutionFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeExecutionFrame_Closed _self;
  final $Res Function(BridgeExecutionFrame_Closed) _then;

/// Create a copy of BridgeExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeExecutionFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeFeedClosedReason,
  ));
}


}

/// @nodoc
mixin _$BridgeStorageReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStorageReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeStorageReplacement()';
}


}

/// @nodoc
class $BridgeStorageReplacementCopyWith<$Res>  {
$BridgeStorageReplacementCopyWith(BridgeStorageReplacement _, $Res Function(BridgeStorageReplacement) __);
}


/// Adds pattern-matching-related methods to [BridgeStorageReplacement].
extension BridgeStorageReplacementPatterns on BridgeStorageReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeStorageReplacement_Unchanged value)?  unchanged,TResult Function( BridgeStorageReplacement_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeStorageReplacement_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeStorageReplacement_Unchanged value)  unchanged,required TResult Function( BridgeStorageReplacement_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged():
return unchanged(_that);case BridgeStorageReplacement_Replace():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeStorageReplacement_Unchanged value)?  unchanged,TResult? Function( BridgeStorageReplacement_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeStorageReplacement_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( BridgeStorageBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeStorageReplacement_Replace() when replace != null:
return replace(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( BridgeStorageBrief? value)  replace,}) {final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged():
return unchanged();case BridgeStorageReplacement_Replace():
return replace(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( BridgeStorageBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeStorageReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeStorageReplacement_Replace() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeStorageReplacement_Unchanged extends BridgeStorageReplacement {
  const BridgeStorageReplacement_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStorageReplacement_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeStorageReplacement.unchanged()';
}


}




/// @nodoc


class BridgeStorageReplacement_Replace extends BridgeStorageReplacement {
  const BridgeStorageReplacement_Replace({this.value}): super._();


 final  BridgeStorageBrief? value;

/// Create a copy of BridgeStorageReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStorageReplacement_ReplaceCopyWith<BridgeStorageReplacement_Replace> get copyWith => _$BridgeStorageReplacement_ReplaceCopyWithImpl<BridgeStorageReplacement_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStorageReplacement_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeStorageReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeStorageReplacement_ReplaceCopyWith<$Res> implements $BridgeStorageReplacementCopyWith<$Res> {
  factory $BridgeStorageReplacement_ReplaceCopyWith(BridgeStorageReplacement_Replace value, $Res Function(BridgeStorageReplacement_Replace) _then) = _$BridgeStorageReplacement_ReplaceCopyWithImpl;
@useResult
$Res call({
 BridgeStorageBrief? value
});




}
/// @nodoc
class _$BridgeStorageReplacement_ReplaceCopyWithImpl<$Res>
    implements $BridgeStorageReplacement_ReplaceCopyWith<$Res> {
  _$BridgeStorageReplacement_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeStorageReplacement_Replace _self;
  final $Res Function(BridgeStorageReplacement_Replace) _then;

/// Create a copy of BridgeStorageReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(BridgeStorageReplacement_Replace(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeStorageBrief?,
  ));
}


}

/// @nodoc
mixin _$BridgeTurnBriefState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTurnBriefState()';
}


}

/// @nodoc
class $BridgeTurnBriefStateCopyWith<$Res>  {
$BridgeTurnBriefStateCopyWith(BridgeTurnBriefState _, $Res Function(BridgeTurnBriefState) __);
}


/// Adds pattern-matching-related methods to [BridgeTurnBriefState].
extension BridgeTurnBriefStatePatterns on BridgeTurnBriefState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTurnBriefState_Queued value)?  queued,TResult Function( BridgeTurnBriefState_Running value)?  running,TResult Function( BridgeTurnBriefState_Completed value)?  completed,TResult Function( BridgeTurnBriefState_Cancelled value)?  cancelled,TResult Function( BridgeTurnBriefState_Failed value)?  failed,TResult Function( BridgeTurnBriefState_BudgetLimited value)?  budgetLimited,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued() when queued != null:
return queued(_that);case BridgeTurnBriefState_Running() when running != null:
return running(_that);case BridgeTurnBriefState_Completed() when completed != null:
return completed(_that);case BridgeTurnBriefState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTurnBriefState_Failed() when failed != null:
return failed(_that);case BridgeTurnBriefState_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTurnBriefState_Queued value)  queued,required TResult Function( BridgeTurnBriefState_Running value)  running,required TResult Function( BridgeTurnBriefState_Completed value)  completed,required TResult Function( BridgeTurnBriefState_Cancelled value)  cancelled,required TResult Function( BridgeTurnBriefState_Failed value)  failed,required TResult Function( BridgeTurnBriefState_BudgetLimited value)  budgetLimited,}){
final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued():
return queued(_that);case BridgeTurnBriefState_Running():
return running(_that);case BridgeTurnBriefState_Completed():
return completed(_that);case BridgeTurnBriefState_Cancelled():
return cancelled(_that);case BridgeTurnBriefState_Failed():
return failed(_that);case BridgeTurnBriefState_BudgetLimited():
return budgetLimited(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTurnBriefState_Queued value)?  queued,TResult? Function( BridgeTurnBriefState_Running value)?  running,TResult? Function( BridgeTurnBriefState_Completed value)?  completed,TResult? Function( BridgeTurnBriefState_Cancelled value)?  cancelled,TResult? Function( BridgeTurnBriefState_Failed value)?  failed,TResult? Function( BridgeTurnBriefState_BudgetLimited value)?  budgetLimited,}){
final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued() when queued != null:
return queued(_that);case BridgeTurnBriefState_Running() when running != null:
return running(_that);case BridgeTurnBriefState_Completed() when completed != null:
return completed(_that);case BridgeTurnBriefState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTurnBriefState_Failed() when failed != null:
return failed(_that);case BridgeTurnBriefState_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 queuedAt)?  queued,TResult Function( PlatformInt64 startedAt,  BridgeTurnPhase phase)?  running,TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)?  completed,TResult Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationKind cause)?  cancelled,TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureCategory category,  BridgeProviderFailureKind? providerKind,  int? httpStatus,  BridgeRetryDisposition retry)?  failed,TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverKind rollover)?  budgetLimited,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued() when queued != null:
return queued(_that.queuedAt);case BridgeTurnBriefState_Running() when running != null:
return running(_that.startedAt,_that.phase);case BridgeTurnBriefState_Completed() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTurnBriefState_Cancelled() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTurnBriefState_Failed() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BridgeTurnBriefState_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 queuedAt)  queued,required TResult Function( PlatformInt64 startedAt,  BridgeTurnPhase phase)  running,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)  completed,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationKind cause)  cancelled,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureCategory category,  BridgeProviderFailureKind? providerKind,  int? httpStatus,  BridgeRetryDisposition retry)  failed,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverKind rollover)  budgetLimited,}) {final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued():
return queued(_that.queuedAt);case BridgeTurnBriefState_Running():
return running(_that.startedAt,_that.phase);case BridgeTurnBriefState_Completed():
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTurnBriefState_Cancelled():
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTurnBriefState_Failed():
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BridgeTurnBriefState_BudgetLimited():
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 queuedAt)?  queued,TResult? Function( PlatformInt64 startedAt,  BridgeTurnPhase phase)?  running,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)?  completed,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationKind cause)?  cancelled,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureCategory category,  BridgeProviderFailureKind? providerKind,  int? httpStatus,  BridgeRetryDisposition retry)?  failed,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverKind rollover)?  budgetLimited,}) {final _that = this;
switch (_that) {
case BridgeTurnBriefState_Queued() when queued != null:
return queued(_that.queuedAt);case BridgeTurnBriefState_Running() when running != null:
return running(_that.startedAt,_that.phase);case BridgeTurnBriefState_Completed() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTurnBriefState_Cancelled() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTurnBriefState_Failed() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BridgeTurnBriefState_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTurnBriefState_Queued extends BridgeTurnBriefState {
  const BridgeTurnBriefState_Queued({required this.queuedAt}): super._();


 final  PlatformInt64 queuedAt;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_QueuedCopyWith<BridgeTurnBriefState_Queued> get copyWith => _$BridgeTurnBriefState_QueuedCopyWithImpl<BridgeTurnBriefState_Queued>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_Queued&&(identical(other.queuedAt, queuedAt) || other.queuedAt == queuedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,queuedAt);
}

@override
String toString() {
    return 'BridgeTurnBriefState.queued(queuedAt: $queuedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_QueuedCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_QueuedCopyWith(BridgeTurnBriefState_Queued value, $Res Function(BridgeTurnBriefState_Queued) _then) = _$BridgeTurnBriefState_QueuedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 queuedAt
});




}
/// @nodoc
class _$BridgeTurnBriefState_QueuedCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_QueuedCopyWith<$Res> {
  _$BridgeTurnBriefState_QueuedCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_Queued _self;
  final $Res Function(BridgeTurnBriefState_Queued) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? queuedAt = null,}) {
  return _then(BridgeTurnBriefState_Queued(
queuedAt: null == queuedAt ? _self.queuedAt : queuedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTurnBriefState_Running extends BridgeTurnBriefState {
  const BridgeTurnBriefState_Running({required this.startedAt, required this.phase}): super._();


 final  PlatformInt64 startedAt;
 final  BridgeTurnPhase phase;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_RunningCopyWith<BridgeTurnBriefState_Running> get copyWith => _$BridgeTurnBriefState_RunningCopyWithImpl<BridgeTurnBriefState_Running>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_Running&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,phase);
}

@override
String toString() {
    return 'BridgeTurnBriefState.running(startedAt: $startedAt, phase: $phase)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_RunningCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_RunningCopyWith(BridgeTurnBriefState_Running value, $Res Function(BridgeTurnBriefState_Running) _then) = _$BridgeTurnBriefState_RunningCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 startedAt, BridgeTurnPhase phase
});




}
/// @nodoc
class _$BridgeTurnBriefState_RunningCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_RunningCopyWith<$Res> {
  _$BridgeTurnBriefState_RunningCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_Running _self;
  final $Res Function(BridgeTurnBriefState_Running) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = null,Object? phase = null,}) {
  return _then(BridgeTurnBriefState_Running(
startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as BridgeTurnPhase,
  ));
}


}

/// @nodoc


class BridgeTurnBriefState_Completed extends BridgeTurnBriefState {
  const BridgeTurnBriefState_Completed({this.startedAt, required this.completedAt, required this.completion}): super._();


 final  PlatformInt64? startedAt;
 final  PlatformInt64 completedAt;
 final  BridgeTurnCompletion completion;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_CompletedCopyWith<BridgeTurnBriefState_Completed> get copyWith => _$BridgeTurnBriefState_CompletedCopyWithImpl<BridgeTurnBriefState_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_Completed&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,completion);
}

@override
String toString() {
    return 'BridgeTurnBriefState.completed(startedAt: $startedAt, completedAt: $completedAt, completion: $completion)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_CompletedCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_CompletedCopyWith(BridgeTurnBriefState_Completed value, $Res Function(BridgeTurnBriefState_Completed) _then) = _$BridgeTurnBriefState_CompletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnCompletion completion
});




}
/// @nodoc
class _$BridgeTurnBriefState_CompletedCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_CompletedCopyWith<$Res> {
  _$BridgeTurnBriefState_CompletedCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_Completed _self;
  final $Res Function(BridgeTurnBriefState_Completed) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? completion = null,}) {
  return _then(BridgeTurnBriefState_Completed(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,completion: null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as BridgeTurnCompletion,
  ));
}


}

/// @nodoc


class BridgeTurnBriefState_Cancelled extends BridgeTurnBriefState {
  const BridgeTurnBriefState_Cancelled({this.startedAt, required this.requestedAt, required this.completedAt, required this.cause}): super._();


 final  PlatformInt64? startedAt;
 final  PlatformInt64 requestedAt;
 final  PlatformInt64 completedAt;
 final  BridgeTurnCancellationKind cause;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_CancelledCopyWith<BridgeTurnBriefState_Cancelled> get copyWith => _$BridgeTurnBriefState_CancelledCopyWithImpl<BridgeTurnBriefState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_Cancelled&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.cause, cause) || other.cause == cause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,requestedAt,completedAt,cause);
}

@override
String toString() {
    return 'BridgeTurnBriefState.cancelled(startedAt: $startedAt, requestedAt: $requestedAt, completedAt: $completedAt, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_CancelledCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_CancelledCopyWith(BridgeTurnBriefState_Cancelled value, $Res Function(BridgeTurnBriefState_Cancelled) _then) = _$BridgeTurnBriefState_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 requestedAt, PlatformInt64 completedAt, BridgeTurnCancellationKind cause
});




}
/// @nodoc
class _$BridgeTurnBriefState_CancelledCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_CancelledCopyWith<$Res> {
  _$BridgeTurnBriefState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_Cancelled _self;
  final $Res Function(BridgeTurnBriefState_Cancelled) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? requestedAt = null,Object? completedAt = null,Object? cause = null,}) {
  return _then(BridgeTurnBriefState_Cancelled(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as BridgeTurnCancellationKind,
  ));
}


}

/// @nodoc


class BridgeTurnBriefState_Failed extends BridgeTurnBriefState {
  const BridgeTurnBriefState_Failed({this.startedAt, required this.completedAt, required this.category, this.providerKind, this.httpStatus, required this.retry}): super._();


 final  PlatformInt64? startedAt;
 final  PlatformInt64 completedAt;
 final  BridgeTurnFailureCategory category;
 final  BridgeProviderFailureKind? providerKind;
 final  int? httpStatus;
 final  BridgeRetryDisposition retry;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_FailedCopyWith<BridgeTurnBriefState_Failed> get copyWith => _$BridgeTurnBriefState_FailedCopyWithImpl<BridgeTurnBriefState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_Failed&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.category, category) || other.category == category)&&(identical(other.providerKind, providerKind) || other.providerKind == providerKind)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus)&&(identical(other.retry, retry) || other.retry == retry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,category,providerKind,httpStatus,retry);
}

@override
String toString() {
    return 'BridgeTurnBriefState.failed(startedAt: $startedAt, completedAt: $completedAt, category: $category, providerKind: $providerKind, httpStatus: $httpStatus, retry: $retry)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_FailedCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_FailedCopyWith(BridgeTurnBriefState_Failed value, $Res Function(BridgeTurnBriefState_Failed) _then) = _$BridgeTurnBriefState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnFailureCategory category, BridgeProviderFailureKind? providerKind, int? httpStatus, BridgeRetryDisposition retry
});


$BridgeRetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class _$BridgeTurnBriefState_FailedCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_FailedCopyWith<$Res> {
  _$BridgeTurnBriefState_FailedCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_Failed _self;
  final $Res Function(BridgeTurnBriefState_Failed) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? category = null,Object? providerKind = freezed,Object? httpStatus = freezed,Object? retry = null,}) {
  return _then(BridgeTurnBriefState_Failed(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as BridgeTurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as BridgeProviderFailureKind?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as BridgeRetryDisposition,
  ));
}

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeRetryDispositionCopyWith<$Res> get retry {

  return $BridgeRetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}

/// @nodoc


class BridgeTurnBriefState_BudgetLimited extends BridgeTurnBriefState {
  const BridgeTurnBriefState_BudgetLimited({this.startedAt, required this.completedAt, required this.limit, required this.rollover}): super._();


 final  PlatformInt64? startedAt;
 final  PlatformInt64 completedAt;
 final  BridgeTurnBudgetLimit limit;
 final  BridgeTurnRolloverKind rollover;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTurnBriefState_BudgetLimitedCopyWith<BridgeTurnBriefState_BudgetLimited> get copyWith => _$BridgeTurnBriefState_BudgetLimitedCopyWithImpl<BridgeTurnBriefState_BudgetLimited>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTurnBriefState_BudgetLimited&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.rollover, rollover) || other.rollover == rollover));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,limit,rollover);
}

@override
String toString() {
    return 'BridgeTurnBriefState.budgetLimited(startedAt: $startedAt, completedAt: $completedAt, limit: $limit, rollover: $rollover)';
}


}

/// @nodoc
abstract mixin class $BridgeTurnBriefState_BudgetLimitedCopyWith<$Res> implements $BridgeTurnBriefStateCopyWith<$Res> {
  factory $BridgeTurnBriefState_BudgetLimitedCopyWith(BridgeTurnBriefState_BudgetLimited value, $Res Function(BridgeTurnBriefState_BudgetLimited) _then) = _$BridgeTurnBriefState_BudgetLimitedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnBudgetLimit limit, BridgeTurnRolloverKind rollover
});




}
/// @nodoc
class _$BridgeTurnBriefState_BudgetLimitedCopyWithImpl<$Res>
    implements $BridgeTurnBriefState_BudgetLimitedCopyWith<$Res> {
  _$BridgeTurnBriefState_BudgetLimitedCopyWithImpl(this._self, this._then);

  final BridgeTurnBriefState_BudgetLimited _self;
  final $Res Function(BridgeTurnBriefState_BudgetLimited) _then;

/// Create a copy of BridgeTurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? limit = null,Object? rollover = null,}) {
  return _then(BridgeTurnBriefState_BudgetLimited(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BridgeTurnBudgetLimit,rollover: null == rollover ? _self.rollover : rollover // ignore: cast_nullable_to_non_nullable
as BridgeTurnRolloverKind,
  ));
}


}

// dart format on
