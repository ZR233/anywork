// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'performance_history.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgePerformanceHistoryEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryEventCopyWith<BridgePerformanceHistoryEvent> get copyWith => _$BridgePerformanceHistoryEventCopyWithImpl<BridgePerformanceHistoryEvent>(this as BridgePerformanceHistoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePerformanceHistoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgePerformanceHistoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgePerformanceHistoryEvent;
  return 'BridgePerformanceHistoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryEventCopyWith<$Res>  {
  factory $BridgePerformanceHistoryEventCopyWith(BridgePerformanceHistoryEvent value, $Res Function(BridgePerformanceHistoryEvent) _then) = _$BridgePerformanceHistoryEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgePerformanceHistoryEventCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryEventCopyWith<$Res> {
  _$BridgePerformanceHistoryEventCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryEvent _self;
  final $Res Function(BridgePerformanceHistoryEvent) _then;

/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePerformanceHistoryEvent].
extension BridgePerformanceHistoryEventPatterns on BridgePerformanceHistoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePerformanceHistoryEvent_Baseline value)?  baseline,TResult Function( BridgePerformanceHistoryEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePerformanceHistoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePerformanceHistoryEvent_Baseline value)  baseline,required TResult Function( BridgePerformanceHistoryEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline():
return baseline(_that);case BridgePerformanceHistoryEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePerformanceHistoryEvent_Baseline value)?  baseline,TResult? Function( BridgePerformanceHistoryEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePerformanceHistoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceHistoryBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceHistoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceHistoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceHistoryBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceHistoryChange value)  change,}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceHistoryEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceHistoryBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceHistoryChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceHistoryEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgePerformanceHistoryEvent_Baseline extends BridgePerformanceHistoryEvent {
  const BridgePerformanceHistoryEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgePerformanceHistoryBaseline value;

/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryEvent_BaselineCopyWith<BridgePerformanceHistoryEvent_Baseline> get copyWith => _$BridgePerformanceHistoryEvent_BaselineCopyWithImpl<BridgePerformanceHistoryEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgePerformanceHistoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryEvent_BaselineCopyWith<$Res> implements $BridgePerformanceHistoryEventCopyWith<$Res> {
  factory $BridgePerformanceHistoryEvent_BaselineCopyWith(BridgePerformanceHistoryEvent_Baseline value, $Res Function(BridgePerformanceHistoryEvent_Baseline) _then) = _$BridgePerformanceHistoryEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgePerformanceHistoryBaseline value
});




}
/// @nodoc
class _$BridgePerformanceHistoryEvent_BaselineCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryEvent_BaselineCopyWith<$Res> {
  _$BridgePerformanceHistoryEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryEvent_Baseline _self;
  final $Res Function(BridgePerformanceHistoryEvent_Baseline) _then;

/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgePerformanceHistoryEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePerformanceHistoryBaseline,
  ));
}


}

/// @nodoc


class BridgePerformanceHistoryEvent_Change extends BridgePerformanceHistoryEvent {
  const BridgePerformanceHistoryEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgePerformanceHistoryChange value;

/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryEvent_ChangeCopyWith<BridgePerformanceHistoryEvent_Change> get copyWith => _$BridgePerformanceHistoryEvent_ChangeCopyWithImpl<BridgePerformanceHistoryEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgePerformanceHistoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryEvent_ChangeCopyWith<$Res> implements $BridgePerformanceHistoryEventCopyWith<$Res> {
  factory $BridgePerformanceHistoryEvent_ChangeCopyWith(BridgePerformanceHistoryEvent_Change value, $Res Function(BridgePerformanceHistoryEvent_Change) _then) = _$BridgePerformanceHistoryEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgePerformanceHistoryChange value
});




}
/// @nodoc
class _$BridgePerformanceHistoryEvent_ChangeCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryEvent_ChangeCopyWith<$Res> {
  _$BridgePerformanceHistoryEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryEvent_Change _self;
  final $Res Function(BridgePerformanceHistoryEvent_Change) _then;

/// Create a copy of BridgePerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgePerformanceHistoryEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePerformanceHistoryChange,
  ));
}


}

/// @nodoc
mixin _$BridgePerformanceHistoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePerformanceHistoryFrame()';
}


}

/// @nodoc
class $BridgePerformanceHistoryFrameCopyWith<$Res>  {
$BridgePerformanceHistoryFrameCopyWith(BridgePerformanceHistoryFrame _, $Res Function(BridgePerformanceHistoryFrame) __);
}


/// Adds pattern-matching-related methods to [BridgePerformanceHistoryFrame].
extension BridgePerformanceHistoryFramePatterns on BridgePerformanceHistoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePerformanceHistoryFrame_Data value)?  data,TResult Function( BridgePerformanceHistoryFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgePerformanceHistoryFrame_Failure value)?  failure,TResult Function( BridgePerformanceHistoryFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data() when data != null:
return data(_that);case BridgePerformanceHistoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePerformanceHistoryFrame_Failure() when failure != null:
return failure(_that);case BridgePerformanceHistoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePerformanceHistoryFrame_Data value)  data,required TResult Function( BridgePerformanceHistoryFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgePerformanceHistoryFrame_Failure value)  failure,required TResult Function( BridgePerformanceHistoryFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data():
return data(_that);case BridgePerformanceHistoryFrame_ResyncRequired():
return resyncRequired(_that);case BridgePerformanceHistoryFrame_Failure():
return failure(_that);case BridgePerformanceHistoryFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePerformanceHistoryFrame_Data value)?  data,TResult? Function( BridgePerformanceHistoryFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgePerformanceHistoryFrame_Failure value)?  failure,TResult? Function( BridgePerformanceHistoryFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data() when data != null:
return data(_that);case BridgePerformanceHistoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePerformanceHistoryFrame_Failure() when failure != null:
return failure(_that);case BridgePerformanceHistoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgePerformanceHistoryEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePerformanceHistoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceHistoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePerformanceHistoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgePerformanceHistoryEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgePerformanceHistoryFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceHistoryFrame_Failure():
return failure(_that.identity,_that.error);case BridgePerformanceHistoryFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgePerformanceHistoryEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgePerformanceHistoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePerformanceHistoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceHistoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePerformanceHistoryFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgePerformanceHistoryFrame_Data extends BridgePerformanceHistoryFrame {
  const BridgePerformanceHistoryFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgePerformanceHistoryEvent event;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryFrame_DataCopyWith<BridgePerformanceHistoryFrame_Data> get copyWith => _$BridgePerformanceHistoryFrame_DataCopyWithImpl<BridgePerformanceHistoryFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgePerformanceHistoryFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryFrame_DataCopyWith<$Res> implements $BridgePerformanceHistoryFrameCopyWith<$Res> {
  factory $BridgePerformanceHistoryFrame_DataCopyWith(BridgePerformanceHistoryFrame_Data value, $Res Function(BridgePerformanceHistoryFrame_Data) _then) = _$BridgePerformanceHistoryFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgePerformanceHistoryEvent event
});


$BridgePerformanceHistoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgePerformanceHistoryFrame_DataCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryFrame_DataCopyWith<$Res> {
  _$BridgePerformanceHistoryFrame_DataCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryFrame_Data _self;
  final $Res Function(BridgePerformanceHistoryFrame_Data) _then;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgePerformanceHistoryFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgePerformanceHistoryEvent,
  ));
}

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryEventCopyWith<$Res> get event {

  return $BridgePerformanceHistoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgePerformanceHistoryFrame_ResyncRequired extends BridgePerformanceHistoryFrame {
  const BridgePerformanceHistoryFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryFrame_ResyncRequiredCopyWith<BridgePerformanceHistoryFrame_ResyncRequired> get copyWith => _$BridgePerformanceHistoryFrame_ResyncRequiredCopyWithImpl<BridgePerformanceHistoryFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePerformanceHistoryFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryFrame_ResyncRequiredCopyWith<$Res> implements $BridgePerformanceHistoryFrameCopyWith<$Res> {
  factory $BridgePerformanceHistoryFrame_ResyncRequiredCopyWith(BridgePerformanceHistoryFrame_ResyncRequired value, $Res Function(BridgePerformanceHistoryFrame_ResyncRequired) _then) = _$BridgePerformanceHistoryFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgePerformanceHistoryFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgePerformanceHistoryFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryFrame_ResyncRequired _self;
  final $Res Function(BridgePerformanceHistoryFrame_ResyncRequired) _then;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePerformanceHistoryFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgePerformanceHistoryFrame_Failure extends BridgePerformanceHistoryFrame {
  const BridgePerformanceHistoryFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryFrame_FailureCopyWith<BridgePerformanceHistoryFrame_Failure> get copyWith => _$BridgePerformanceHistoryFrame_FailureCopyWithImpl<BridgePerformanceHistoryFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgePerformanceHistoryFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryFrame_FailureCopyWith<$Res> implements $BridgePerformanceHistoryFrameCopyWith<$Res> {
  factory $BridgePerformanceHistoryFrame_FailureCopyWith(BridgePerformanceHistoryFrame_Failure value, $Res Function(BridgePerformanceHistoryFrame_Failure) _then) = _$BridgePerformanceHistoryFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgePerformanceHistoryFrame_FailureCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryFrame_FailureCopyWith<$Res> {
  _$BridgePerformanceHistoryFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryFrame_Failure _self;
  final $Res Function(BridgePerformanceHistoryFrame_Failure) _then;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgePerformanceHistoryFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgePerformanceHistoryFrame_Closed extends BridgePerformanceHistoryFrame {
  const BridgePerformanceHistoryFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceHistoryFrame_ClosedCopyWith<BridgePerformanceHistoryFrame_Closed> get copyWith => _$BridgePerformanceHistoryFrame_ClosedCopyWithImpl<BridgePerformanceHistoryFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceHistoryFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePerformanceHistoryFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceHistoryFrame_ClosedCopyWith<$Res> implements $BridgePerformanceHistoryFrameCopyWith<$Res> {
  factory $BridgePerformanceHistoryFrame_ClosedCopyWith(BridgePerformanceHistoryFrame_Closed value, $Res Function(BridgePerformanceHistoryFrame_Closed) _then) = _$BridgePerformanceHistoryFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgePerformanceHistoryFrame_ClosedCopyWithImpl<$Res>
    implements $BridgePerformanceHistoryFrame_ClosedCopyWith<$Res> {
  _$BridgePerformanceHistoryFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgePerformanceHistoryFrame_Closed _self;
  final $Res Function(BridgePerformanceHistoryFrame_Closed) _then;

/// Create a copy of BridgePerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePerformanceHistoryFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
