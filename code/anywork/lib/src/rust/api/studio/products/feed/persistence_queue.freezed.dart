// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence_queue.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgePersistenceQueueEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueEventCopyWith<BridgePersistenceQueueEvent> get copyWith => _$BridgePersistenceQueueEventCopyWithImpl<BridgePersistenceQueueEvent>(this as BridgePersistenceQueueEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePersistenceQueueEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgePersistenceQueueEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgePersistenceQueueEvent;
  return 'BridgePersistenceQueueEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueEventCopyWith<$Res>  {
  factory $BridgePersistenceQueueEventCopyWith(BridgePersistenceQueueEvent value, $Res Function(BridgePersistenceQueueEvent) _then) = _$BridgePersistenceQueueEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgePersistenceQueueEventCopyWithImpl<$Res>
    implements $BridgePersistenceQueueEventCopyWith<$Res> {
  _$BridgePersistenceQueueEventCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueEvent _self;
  final $Res Function(BridgePersistenceQueueEvent) _then;

/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePersistenceQueueEvent].
extension BridgePersistenceQueueEventPatterns on BridgePersistenceQueueEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceQueueEvent_Baseline value)?  baseline,TResult Function( BridgePersistenceQueueEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePersistenceQueueEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceQueueEvent_Baseline value)  baseline,required TResult Function( BridgePersistenceQueueEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline():
return baseline(_that);case BridgePersistenceQueueEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceQueueEvent_Baseline value)?  baseline,TResult? Function( BridgePersistenceQueueEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePersistenceQueueEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceQueueBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceQueueChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceQueueEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceQueueBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceQueueChange value)  change,}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceQueueEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceQueueBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceQueueChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceQueueEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceQueueEvent_Baseline extends BridgePersistenceQueueEvent {
  const BridgePersistenceQueueEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgePersistenceQueueBaseline value;

/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueEvent_BaselineCopyWith<BridgePersistenceQueueEvent_Baseline> get copyWith => _$BridgePersistenceQueueEvent_BaselineCopyWithImpl<BridgePersistenceQueueEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgePersistenceQueueEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueEvent_BaselineCopyWith<$Res> implements $BridgePersistenceQueueEventCopyWith<$Res> {
  factory $BridgePersistenceQueueEvent_BaselineCopyWith(BridgePersistenceQueueEvent_Baseline value, $Res Function(BridgePersistenceQueueEvent_Baseline) _then) = _$BridgePersistenceQueueEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgePersistenceQueueBaseline value
});




}
/// @nodoc
class _$BridgePersistenceQueueEvent_BaselineCopyWithImpl<$Res>
    implements $BridgePersistenceQueueEvent_BaselineCopyWith<$Res> {
  _$BridgePersistenceQueueEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueEvent_Baseline _self;
  final $Res Function(BridgePersistenceQueueEvent_Baseline) _then;

/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgePersistenceQueueEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePersistenceQueueBaseline,
  ));
}


}

/// @nodoc


class BridgePersistenceQueueEvent_Change extends BridgePersistenceQueueEvent {
  const BridgePersistenceQueueEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgePersistenceQueueChange value;

/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueEvent_ChangeCopyWith<BridgePersistenceQueueEvent_Change> get copyWith => _$BridgePersistenceQueueEvent_ChangeCopyWithImpl<BridgePersistenceQueueEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgePersistenceQueueEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueEvent_ChangeCopyWith<$Res> implements $BridgePersistenceQueueEventCopyWith<$Res> {
  factory $BridgePersistenceQueueEvent_ChangeCopyWith(BridgePersistenceQueueEvent_Change value, $Res Function(BridgePersistenceQueueEvent_Change) _then) = _$BridgePersistenceQueueEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgePersistenceQueueChange value
});




}
/// @nodoc
class _$BridgePersistenceQueueEvent_ChangeCopyWithImpl<$Res>
    implements $BridgePersistenceQueueEvent_ChangeCopyWith<$Res> {
  _$BridgePersistenceQueueEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueEvent_Change _self;
  final $Res Function(BridgePersistenceQueueEvent_Change) _then;

/// Create a copy of BridgePersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgePersistenceQueueEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePersistenceQueueChange,
  ));
}


}

/// @nodoc
mixin _$BridgePersistenceQueueFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePersistenceQueueFrame()';
}


}

/// @nodoc
class $BridgePersistenceQueueFrameCopyWith<$Res>  {
$BridgePersistenceQueueFrameCopyWith(BridgePersistenceQueueFrame _, $Res Function(BridgePersistenceQueueFrame) __);
}


/// Adds pattern-matching-related methods to [BridgePersistenceQueueFrame].
extension BridgePersistenceQueueFramePatterns on BridgePersistenceQueueFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceQueueFrame_Data value)?  data,TResult Function( BridgePersistenceQueueFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgePersistenceQueueFrame_Failure value)?  failure,TResult Function( BridgePersistenceQueueFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data() when data != null:
return data(_that);case BridgePersistenceQueueFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePersistenceQueueFrame_Failure() when failure != null:
return failure(_that);case BridgePersistenceQueueFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceQueueFrame_Data value)  data,required TResult Function( BridgePersistenceQueueFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgePersistenceQueueFrame_Failure value)  failure,required TResult Function( BridgePersistenceQueueFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data():
return data(_that);case BridgePersistenceQueueFrame_ResyncRequired():
return resyncRequired(_that);case BridgePersistenceQueueFrame_Failure():
return failure(_that);case BridgePersistenceQueueFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceQueueFrame_Data value)?  data,TResult? Function( BridgePersistenceQueueFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgePersistenceQueueFrame_Failure value)?  failure,TResult? Function( BridgePersistenceQueueFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data() when data != null:
return data(_that);case BridgePersistenceQueueFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePersistenceQueueFrame_Failure() when failure != null:
return failure(_that);case BridgePersistenceQueueFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgePersistenceQueueEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePersistenceQueueFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceQueueFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePersistenceQueueFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgePersistenceQueueEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgePersistenceQueueFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceQueueFrame_Failure():
return failure(_that.identity,_that.error);case BridgePersistenceQueueFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgePersistenceQueueEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgePersistenceQueueFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePersistenceQueueFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceQueueFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePersistenceQueueFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceQueueFrame_Data extends BridgePersistenceQueueFrame {
  const BridgePersistenceQueueFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgePersistenceQueueEvent event;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueFrame_DataCopyWith<BridgePersistenceQueueFrame_Data> get copyWith => _$BridgePersistenceQueueFrame_DataCopyWithImpl<BridgePersistenceQueueFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgePersistenceQueueFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueFrame_DataCopyWith<$Res> implements $BridgePersistenceQueueFrameCopyWith<$Res> {
  factory $BridgePersistenceQueueFrame_DataCopyWith(BridgePersistenceQueueFrame_Data value, $Res Function(BridgePersistenceQueueFrame_Data) _then) = _$BridgePersistenceQueueFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgePersistenceQueueEvent event
});


$BridgePersistenceQueueEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgePersistenceQueueFrame_DataCopyWithImpl<$Res>
    implements $BridgePersistenceQueueFrame_DataCopyWith<$Res> {
  _$BridgePersistenceQueueFrame_DataCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueFrame_Data _self;
  final $Res Function(BridgePersistenceQueueFrame_Data) _then;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgePersistenceQueueFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgePersistenceQueueEvent,
  ));
}

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgePersistenceQueueEventCopyWith<$Res> get event {

  return $BridgePersistenceQueueEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgePersistenceQueueFrame_ResyncRequired extends BridgePersistenceQueueFrame {
  const BridgePersistenceQueueFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueFrame_ResyncRequiredCopyWith<BridgePersistenceQueueFrame_ResyncRequired> get copyWith => _$BridgePersistenceQueueFrame_ResyncRequiredCopyWithImpl<BridgePersistenceQueueFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePersistenceQueueFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueFrame_ResyncRequiredCopyWith<$Res> implements $BridgePersistenceQueueFrameCopyWith<$Res> {
  factory $BridgePersistenceQueueFrame_ResyncRequiredCopyWith(BridgePersistenceQueueFrame_ResyncRequired value, $Res Function(BridgePersistenceQueueFrame_ResyncRequired) _then) = _$BridgePersistenceQueueFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgePersistenceQueueFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgePersistenceQueueFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgePersistenceQueueFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueFrame_ResyncRequired _self;
  final $Res Function(BridgePersistenceQueueFrame_ResyncRequired) _then;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePersistenceQueueFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgePersistenceQueueFrame_Failure extends BridgePersistenceQueueFrame {
  const BridgePersistenceQueueFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueFrame_FailureCopyWith<BridgePersistenceQueueFrame_Failure> get copyWith => _$BridgePersistenceQueueFrame_FailureCopyWithImpl<BridgePersistenceQueueFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgePersistenceQueueFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueFrame_FailureCopyWith<$Res> implements $BridgePersistenceQueueFrameCopyWith<$Res> {
  factory $BridgePersistenceQueueFrame_FailureCopyWith(BridgePersistenceQueueFrame_Failure value, $Res Function(BridgePersistenceQueueFrame_Failure) _then) = _$BridgePersistenceQueueFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgePersistenceQueueFrame_FailureCopyWithImpl<$Res>
    implements $BridgePersistenceQueueFrame_FailureCopyWith<$Res> {
  _$BridgePersistenceQueueFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueFrame_Failure _self;
  final $Res Function(BridgePersistenceQueueFrame_Failure) _then;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgePersistenceQueueFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgePersistenceQueueFrame_Closed extends BridgePersistenceQueueFrame {
  const BridgePersistenceQueueFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceQueueFrame_ClosedCopyWith<BridgePersistenceQueueFrame_Closed> get copyWith => _$BridgePersistenceQueueFrame_ClosedCopyWithImpl<BridgePersistenceQueueFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceQueueFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePersistenceQueueFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceQueueFrame_ClosedCopyWith<$Res> implements $BridgePersistenceQueueFrameCopyWith<$Res> {
  factory $BridgePersistenceQueueFrame_ClosedCopyWith(BridgePersistenceQueueFrame_Closed value, $Res Function(BridgePersistenceQueueFrame_Closed) _then) = _$BridgePersistenceQueueFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgePersistenceQueueFrame_ClosedCopyWithImpl<$Res>
    implements $BridgePersistenceQueueFrame_ClosedCopyWith<$Res> {
  _$BridgePersistenceQueueFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgePersistenceQueueFrame_Closed _self;
  final $Res Function(BridgePersistenceQueueFrame_Closed) _then;

/// Create a copy of BridgePersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePersistenceQueueFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
