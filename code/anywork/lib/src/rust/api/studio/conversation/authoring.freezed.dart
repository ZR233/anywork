// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'authoring.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAuthoringEvent {

 BridgeThreadFacetStamp get stamp; Object get value;
/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringEventCopyWith<BridgeAuthoringEvent> get copyWith => _$BridgeAuthoringEventCopyWithImpl<BridgeAuthoringEvent>(this as BridgeAuthoringEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAuthoringEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAuthoringEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAuthoringEvent;
  return 'BridgeAuthoringEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringEventCopyWith<$Res>  {
  factory $BridgeAuthoringEventCopyWith(BridgeAuthoringEvent value, $Res Function(BridgeAuthoringEvent) _then) = _$BridgeAuthoringEventCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFacetStamp stamp
});




}
/// @nodoc
class _$BridgeAuthoringEventCopyWithImpl<$Res>
    implements $BridgeAuthoringEventCopyWith<$Res> {
  _$BridgeAuthoringEventCopyWithImpl(this._self, this._then);

  final BridgeAuthoringEvent _self;
  final $Res Function(BridgeAuthoringEvent) _then;

/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAuthoringEvent].
extension BridgeAuthoringEventPatterns on BridgeAuthoringEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAuthoringEvent_Baseline value)?  baseline,TResult Function( BridgeAuthoringEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAuthoringEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAuthoringEvent_Baseline value)  baseline,required TResult Function( BridgeAuthoringEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline():
return baseline(_that);case BridgeAuthoringEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAuthoringEvent_Baseline value)?  baseline,TResult? Function( BridgeAuthoringEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAuthoringEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeAuthoringBaseline value)?  baseline,TResult Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeAuthoringChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAuthoringEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeAuthoringBaseline value)  baseline,required TResult Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeAuthoringChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAuthoringEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeAuthoringBaseline value)?  baseline,TResult? Function( BridgeThreadFacetStamp stamp,  BigInt baseRevision,  BridgeAuthoringChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAuthoringEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAuthoringEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAuthoringEvent_Baseline extends BridgeAuthoringEvent {
  const BridgeAuthoringEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeThreadFeedIdentity identity;
@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeAuthoringBaseline value;

/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringEvent_BaselineCopyWith<BridgeAuthoringEvent_Baseline> get copyWith => _$BridgeAuthoringEvent_BaselineCopyWithImpl<BridgeAuthoringEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAuthoringEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringEvent_BaselineCopyWith<$Res> implements $BridgeAuthoringEventCopyWith<$Res> {
  factory $BridgeAuthoringEvent_BaselineCopyWith(BridgeAuthoringEvent_Baseline value, $Res Function(BridgeAuthoringEvent_Baseline) _then) = _$BridgeAuthoringEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeThreadFacetStamp stamp, BridgeAuthoringBaseline value
});




}
/// @nodoc
class _$BridgeAuthoringEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAuthoringEvent_BaselineCopyWith<$Res> {
  _$BridgeAuthoringEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAuthoringEvent_Baseline _self;
  final $Res Function(BridgeAuthoringEvent_Baseline) _then;

/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAuthoringEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAuthoringBaseline,
  ));
}


}

/// @nodoc


class BridgeAuthoringEvent_Change extends BridgeAuthoringEvent {
  const BridgeAuthoringEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeThreadFacetStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAuthoringChange value;

/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringEvent_ChangeCopyWith<BridgeAuthoringEvent_Change> get copyWith => _$BridgeAuthoringEvent_ChangeCopyWithImpl<BridgeAuthoringEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAuthoringEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringEvent_ChangeCopyWith<$Res> implements $BridgeAuthoringEventCopyWith<$Res> {
  factory $BridgeAuthoringEvent_ChangeCopyWith(BridgeAuthoringEvent_Change value, $Res Function(BridgeAuthoringEvent_Change) _then) = _$BridgeAuthoringEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFacetStamp stamp, BigInt baseRevision, BridgeAuthoringChange value
});




}
/// @nodoc
class _$BridgeAuthoringEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAuthoringEvent_ChangeCopyWith<$Res> {
  _$BridgeAuthoringEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAuthoringEvent_Change _self;
  final $Res Function(BridgeAuthoringEvent_Change) _then;

/// Create a copy of BridgeAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAuthoringEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAuthoringChange,
  ));
}


}

/// @nodoc
mixin _$BridgeAuthoringFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAuthoringFrame()';
}


}

/// @nodoc
class $BridgeAuthoringFrameCopyWith<$Res>  {
$BridgeAuthoringFrameCopyWith(BridgeAuthoringFrame _, $Res Function(BridgeAuthoringFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAuthoringFrame].
extension BridgeAuthoringFramePatterns on BridgeAuthoringFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAuthoringFrame_Data value)?  data,TResult Function( BridgeAuthoringFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAuthoringFrame_Failure value)?  failure,TResult Function( BridgeAuthoringFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data() when data != null:
return data(_that);case BridgeAuthoringFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAuthoringFrame_Failure() when failure != null:
return failure(_that);case BridgeAuthoringFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAuthoringFrame_Data value)  data,required TResult Function( BridgeAuthoringFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAuthoringFrame_Failure value)  failure,required TResult Function( BridgeAuthoringFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data():
return data(_that);case BridgeAuthoringFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAuthoringFrame_Failure():
return failure(_that);case BridgeAuthoringFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAuthoringFrame_Data value)?  data,TResult? Function( BridgeAuthoringFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAuthoringFrame_Failure value)?  failure,TResult? Function( BridgeAuthoringFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data() when data != null:
return data(_that);case BridgeAuthoringFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAuthoringFrame_Failure() when failure != null:
return failure(_that);case BridgeAuthoringFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAuthoringEvent event)?  data,TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAuthoringFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAuthoringFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAuthoringFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAuthoringEvent event)  data,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)  resyncRequired,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAuthoringFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAuthoringFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAuthoringFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAuthoringEvent event)?  data,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAuthoringFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAuthoringFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAuthoringFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAuthoringFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAuthoringFrame_Data extends BridgeAuthoringFrame {
  const BridgeAuthoringFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAuthoringEvent event;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringFrame_DataCopyWith<BridgeAuthoringFrame_Data> get copyWith => _$BridgeAuthoringFrame_DataCopyWithImpl<BridgeAuthoringFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAuthoringFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringFrame_DataCopyWith<$Res> implements $BridgeAuthoringFrameCopyWith<$Res> {
  factory $BridgeAuthoringFrame_DataCopyWith(BridgeAuthoringFrame_Data value, $Res Function(BridgeAuthoringFrame_Data) _then) = _$BridgeAuthoringFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAuthoringEvent event
});


$BridgeAuthoringEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAuthoringFrame_DataCopyWithImpl<$Res>
    implements $BridgeAuthoringFrame_DataCopyWith<$Res> {
  _$BridgeAuthoringFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAuthoringFrame_Data _self;
  final $Res Function(BridgeAuthoringFrame_Data) _then;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAuthoringFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAuthoringEvent,
  ));
}

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAuthoringEventCopyWith<$Res> get event {

  return $BridgeAuthoringEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAuthoringFrame_ResyncRequired extends BridgeAuthoringFrame {
  const BridgeAuthoringFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeResyncReason reason;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringFrame_ResyncRequiredCopyWith<BridgeAuthoringFrame_ResyncRequired> get copyWith => _$BridgeAuthoringFrame_ResyncRequiredCopyWithImpl<BridgeAuthoringFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAuthoringFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAuthoringFrameCopyWith<$Res> {
  factory $BridgeAuthoringFrame_ResyncRequiredCopyWith(BridgeAuthoringFrame_ResyncRequired value, $Res Function(BridgeAuthoringFrame_ResyncRequired) _then) = _$BridgeAuthoringFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeResyncReason reason
});




}
/// @nodoc
class _$BridgeAuthoringFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAuthoringFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAuthoringFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAuthoringFrame_ResyncRequired _self;
  final $Res Function(BridgeAuthoringFrame_ResyncRequired) _then;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAuthoringFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeResyncReason,
  ));
}


}

/// @nodoc


class BridgeAuthoringFrame_Failure extends BridgeAuthoringFrame {
  const BridgeAuthoringFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringFrame_FailureCopyWith<BridgeAuthoringFrame_Failure> get copyWith => _$BridgeAuthoringFrame_FailureCopyWithImpl<BridgeAuthoringFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAuthoringFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringFrame_FailureCopyWith<$Res> implements $BridgeAuthoringFrameCopyWith<$Res> {
  factory $BridgeAuthoringFrame_FailureCopyWith(BridgeAuthoringFrame_Failure value, $Res Function(BridgeAuthoringFrame_Failure) _then) = _$BridgeAuthoringFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAuthoringFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAuthoringFrame_FailureCopyWith<$Res> {
  _$BridgeAuthoringFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAuthoringFrame_Failure _self;
  final $Res Function(BridgeAuthoringFrame_Failure) _then;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAuthoringFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAuthoringFrame_Closed extends BridgeAuthoringFrame {
  const BridgeAuthoringFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeFeedClosedReason reason;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAuthoringFrame_ClosedCopyWith<BridgeAuthoringFrame_Closed> get copyWith => _$BridgeAuthoringFrame_ClosedCopyWithImpl<BridgeAuthoringFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAuthoringFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAuthoringFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAuthoringFrame_ClosedCopyWith<$Res> implements $BridgeAuthoringFrameCopyWith<$Res> {
  factory $BridgeAuthoringFrame_ClosedCopyWith(BridgeAuthoringFrame_Closed value, $Res Function(BridgeAuthoringFrame_Closed) _then) = _$BridgeAuthoringFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeFeedClosedReason reason
});




}
/// @nodoc
class _$BridgeAuthoringFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAuthoringFrame_ClosedCopyWith<$Res> {
  _$BridgeAuthoringFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAuthoringFrame_Closed _self;
  final $Res Function(BridgeAuthoringFrame_Closed) _then;

/// Create a copy of BridgeAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAuthoringFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeFeedClosedReason,
  ));
}


}

/// @nodoc
mixin _$BridgePlanReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePlanReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePlanReplacement()';
}


}

/// @nodoc
class $BridgePlanReplacementCopyWith<$Res>  {
$BridgePlanReplacementCopyWith(BridgePlanReplacement _, $Res Function(BridgePlanReplacement) __);
}


/// Adds pattern-matching-related methods to [BridgePlanReplacement].
extension BridgePlanReplacementPatterns on BridgePlanReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePlanReplacement_Unchanged value)?  unchanged,TResult Function( BridgePlanReplacement_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgePlanReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePlanReplacement_Unchanged value)  unchanged,required TResult Function( BridgePlanReplacement_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged():
return unchanged(_that);case BridgePlanReplacement_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePlanReplacement_Unchanged value)?  unchanged,TResult? Function( BridgePlanReplacement_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgePlanReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( BridgePlanBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgePlanReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( BridgePlanBrief? value)  replace,}) {final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged():
return unchanged();case BridgePlanReplacement_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( BridgePlanBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case BridgePlanReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgePlanReplacement_Replace() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgePlanReplacement_Unchanged extends BridgePlanReplacement {
  const BridgePlanReplacement_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePlanReplacement_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePlanReplacement.unchanged()';
}


}




/// @nodoc


class BridgePlanReplacement_Replace extends BridgePlanReplacement {
  const BridgePlanReplacement_Replace({this.value}): super._();


 final  BridgePlanBrief? value;

/// Create a copy of BridgePlanReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePlanReplacement_ReplaceCopyWith<BridgePlanReplacement_Replace> get copyWith => _$BridgePlanReplacement_ReplaceCopyWithImpl<BridgePlanReplacement_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePlanReplacement_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgePlanReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePlanReplacement_ReplaceCopyWith<$Res> implements $BridgePlanReplacementCopyWith<$Res> {
  factory $BridgePlanReplacement_ReplaceCopyWith(BridgePlanReplacement_Replace value, $Res Function(BridgePlanReplacement_Replace) _then) = _$BridgePlanReplacement_ReplaceCopyWithImpl;
@useResult
$Res call({
 BridgePlanBrief? value
});




}
/// @nodoc
class _$BridgePlanReplacement_ReplaceCopyWithImpl<$Res>
    implements $BridgePlanReplacement_ReplaceCopyWith<$Res> {
  _$BridgePlanReplacement_ReplaceCopyWithImpl(this._self, this._then);

  final BridgePlanReplacement_Replace _self;
  final $Res Function(BridgePlanReplacement_Replace) _then;

/// Create a copy of BridgePlanReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(BridgePlanReplacement_Replace(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePlanBrief?,
  ));
}


}

/// @nodoc
mixin _$BridgeTodoReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTodoReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTodoReplacement()';
}


}

/// @nodoc
class $BridgeTodoReplacementCopyWith<$Res>  {
$BridgeTodoReplacementCopyWith(BridgeTodoReplacement _, $Res Function(BridgeTodoReplacement) __);
}


/// Adds pattern-matching-related methods to [BridgeTodoReplacement].
extension BridgeTodoReplacementPatterns on BridgeTodoReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTodoReplacement_Unchanged value)?  unchanged,TResult Function( BridgeTodoReplacement_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeTodoReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTodoReplacement_Unchanged value)  unchanged,required TResult Function( BridgeTodoReplacement_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged():
return unchanged(_that);case BridgeTodoReplacement_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTodoReplacement_Unchanged value)?  unchanged,TResult? Function( BridgeTodoReplacement_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeTodoReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( BridgeTodoBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeTodoReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( BridgeTodoBrief? value)  replace,}) {final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged():
return unchanged();case BridgeTodoReplacement_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( BridgeTodoBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeTodoReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeTodoReplacement_Replace() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTodoReplacement_Unchanged extends BridgeTodoReplacement {
  const BridgeTodoReplacement_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTodoReplacement_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTodoReplacement.unchanged()';
}


}




/// @nodoc


class BridgeTodoReplacement_Replace extends BridgeTodoReplacement {
  const BridgeTodoReplacement_Replace({this.value}): super._();


 final  BridgeTodoBrief? value;

/// Create a copy of BridgeTodoReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTodoReplacement_ReplaceCopyWith<BridgeTodoReplacement_Replace> get copyWith => _$BridgeTodoReplacement_ReplaceCopyWithImpl<BridgeTodoReplacement_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTodoReplacement_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeTodoReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeTodoReplacement_ReplaceCopyWith<$Res> implements $BridgeTodoReplacementCopyWith<$Res> {
  factory $BridgeTodoReplacement_ReplaceCopyWith(BridgeTodoReplacement_Replace value, $Res Function(BridgeTodoReplacement_Replace) _then) = _$BridgeTodoReplacement_ReplaceCopyWithImpl;
@useResult
$Res call({
 BridgeTodoBrief? value
});




}
/// @nodoc
class _$BridgeTodoReplacement_ReplaceCopyWithImpl<$Res>
    implements $BridgeTodoReplacement_ReplaceCopyWith<$Res> {
  _$BridgeTodoReplacement_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeTodoReplacement_Replace _self;
  final $Res Function(BridgeTodoReplacement_Replace) _then;

/// Create a copy of BridgeTodoReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(BridgeTodoReplacement_Replace(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeTodoBrief?,
  ));
}


}

/// @nodoc
mixin _$BridgeWorkflowReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkflowReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeWorkflowReplacement()';
}


}

/// @nodoc
class $BridgeWorkflowReplacementCopyWith<$Res>  {
$BridgeWorkflowReplacementCopyWith(BridgeWorkflowReplacement _, $Res Function(BridgeWorkflowReplacement) __);
}


/// Adds pattern-matching-related methods to [BridgeWorkflowReplacement].
extension BridgeWorkflowReplacementPatterns on BridgeWorkflowReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeWorkflowReplacement_Unchanged value)?  unchanged,TResult Function( BridgeWorkflowReplacement_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeWorkflowReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeWorkflowReplacement_Unchanged value)  unchanged,required TResult Function( BridgeWorkflowReplacement_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged():
return unchanged(_that);case BridgeWorkflowReplacement_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeWorkflowReplacement_Unchanged value)?  unchanged,TResult? Function( BridgeWorkflowReplacement_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeWorkflowReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( BridgeWorkflowBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeWorkflowReplacement_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( BridgeWorkflowBrief? value)  replace,}) {final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged():
return unchanged();case BridgeWorkflowReplacement_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( BridgeWorkflowBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeWorkflowReplacement_Unchanged() when unchanged != null:
return unchanged();case BridgeWorkflowReplacement_Replace() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeWorkflowReplacement_Unchanged extends BridgeWorkflowReplacement {
  const BridgeWorkflowReplacement_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkflowReplacement_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeWorkflowReplacement.unchanged()';
}


}




/// @nodoc


class BridgeWorkflowReplacement_Replace extends BridgeWorkflowReplacement {
  const BridgeWorkflowReplacement_Replace({this.value}): super._();


 final  BridgeWorkflowBrief? value;

/// Create a copy of BridgeWorkflowReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkflowReplacement_ReplaceCopyWith<BridgeWorkflowReplacement_Replace> get copyWith => _$BridgeWorkflowReplacement_ReplaceCopyWithImpl<BridgeWorkflowReplacement_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkflowReplacement_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeWorkflowReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkflowReplacement_ReplaceCopyWith<$Res> implements $BridgeWorkflowReplacementCopyWith<$Res> {
  factory $BridgeWorkflowReplacement_ReplaceCopyWith(BridgeWorkflowReplacement_Replace value, $Res Function(BridgeWorkflowReplacement_Replace) _then) = _$BridgeWorkflowReplacement_ReplaceCopyWithImpl;
@useResult
$Res call({
 BridgeWorkflowBrief? value
});




}
/// @nodoc
class _$BridgeWorkflowReplacement_ReplaceCopyWithImpl<$Res>
    implements $BridgeWorkflowReplacement_ReplaceCopyWith<$Res> {
  _$BridgeWorkflowReplacement_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeWorkflowReplacement_Replace _self;
  final $Res Function(BridgeWorkflowReplacement_Replace) _then;

/// Create a copy of BridgeWorkflowReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(BridgeWorkflowReplacement_Replace(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeWorkflowBrief?,
  ));
}


}

// dart format on
