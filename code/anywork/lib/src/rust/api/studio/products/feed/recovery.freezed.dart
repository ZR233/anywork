// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRecoveryEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryEventCopyWith<BridgeRecoveryEvent> get copyWith => _$BridgeRecoveryEventCopyWithImpl<BridgeRecoveryEvent>(this as BridgeRecoveryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeRecoveryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeRecoveryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeRecoveryEvent;
  return 'BridgeRecoveryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryEventCopyWith<$Res>  {
  factory $BridgeRecoveryEventCopyWith(BridgeRecoveryEvent value, $Res Function(BridgeRecoveryEvent) _then) = _$BridgeRecoveryEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeRecoveryEventCopyWithImpl<$Res>
    implements $BridgeRecoveryEventCopyWith<$Res> {
  _$BridgeRecoveryEventCopyWithImpl(this._self, this._then);

  final BridgeRecoveryEvent _self;
  final $Res Function(BridgeRecoveryEvent) _then;

/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeRecoveryEvent].
extension BridgeRecoveryEventPatterns on BridgeRecoveryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRecoveryEvent_Baseline value)?  baseline,TResult Function( BridgeRecoveryEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeRecoveryEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRecoveryEvent_Baseline value)  baseline,required TResult Function( BridgeRecoveryEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline():
return baseline(_that);case BridgeRecoveryEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRecoveryEvent_Baseline value)?  baseline,TResult? Function( BridgeRecoveryEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeRecoveryEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeRecoveryBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeRecoveryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeRecoveryEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeRecoveryBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeRecoveryChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeRecoveryEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeRecoveryBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeRecoveryChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeRecoveryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeRecoveryEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRecoveryEvent_Baseline extends BridgeRecoveryEvent {
  const BridgeRecoveryEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeRecoveryBaseline value;

/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryEvent_BaselineCopyWith<BridgeRecoveryEvent_Baseline> get copyWith => _$BridgeRecoveryEvent_BaselineCopyWithImpl<BridgeRecoveryEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeRecoveryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryEvent_BaselineCopyWith<$Res> implements $BridgeRecoveryEventCopyWith<$Res> {
  factory $BridgeRecoveryEvent_BaselineCopyWith(BridgeRecoveryEvent_Baseline value, $Res Function(BridgeRecoveryEvent_Baseline) _then) = _$BridgeRecoveryEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeRecoveryBaseline value
});




}
/// @nodoc
class _$BridgeRecoveryEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeRecoveryEvent_BaselineCopyWith<$Res> {
  _$BridgeRecoveryEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeRecoveryEvent_Baseline _self;
  final $Res Function(BridgeRecoveryEvent_Baseline) _then;

/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeRecoveryEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeRecoveryBaseline,
  ));
}


}

/// @nodoc


class BridgeRecoveryEvent_Change extends BridgeRecoveryEvent {
  const BridgeRecoveryEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeRecoveryChange value;

/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryEvent_ChangeCopyWith<BridgeRecoveryEvent_Change> get copyWith => _$BridgeRecoveryEvent_ChangeCopyWithImpl<BridgeRecoveryEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeRecoveryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryEvent_ChangeCopyWith<$Res> implements $BridgeRecoveryEventCopyWith<$Res> {
  factory $BridgeRecoveryEvent_ChangeCopyWith(BridgeRecoveryEvent_Change value, $Res Function(BridgeRecoveryEvent_Change) _then) = _$BridgeRecoveryEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeRecoveryChange value
});




}
/// @nodoc
class _$BridgeRecoveryEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeRecoveryEvent_ChangeCopyWith<$Res> {
  _$BridgeRecoveryEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeRecoveryEvent_Change _self;
  final $Res Function(BridgeRecoveryEvent_Change) _then;

/// Create a copy of BridgeRecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeRecoveryEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeRecoveryChange,
  ));
}


}

/// @nodoc
mixin _$BridgeRecoveryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeRecoveryFrame()';
}


}

/// @nodoc
class $BridgeRecoveryFrameCopyWith<$Res>  {
$BridgeRecoveryFrameCopyWith(BridgeRecoveryFrame _, $Res Function(BridgeRecoveryFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeRecoveryFrame].
extension BridgeRecoveryFramePatterns on BridgeRecoveryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRecoveryFrame_Data value)?  data,TResult Function( BridgeRecoveryFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeRecoveryFrame_Failure value)?  failure,TResult Function( BridgeRecoveryFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data() when data != null:
return data(_that);case BridgeRecoveryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeRecoveryFrame_Failure() when failure != null:
return failure(_that);case BridgeRecoveryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRecoveryFrame_Data value)  data,required TResult Function( BridgeRecoveryFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeRecoveryFrame_Failure value)  failure,required TResult Function( BridgeRecoveryFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data():
return data(_that);case BridgeRecoveryFrame_ResyncRequired():
return resyncRequired(_that);case BridgeRecoveryFrame_Failure():
return failure(_that);case BridgeRecoveryFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRecoveryFrame_Data value)?  data,TResult? Function( BridgeRecoveryFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeRecoveryFrame_Failure value)?  failure,TResult? Function( BridgeRecoveryFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data() when data != null:
return data(_that);case BridgeRecoveryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeRecoveryFrame_Failure() when failure != null:
return failure(_that);case BridgeRecoveryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeRecoveryEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeRecoveryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeRecoveryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeRecoveryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeRecoveryEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeRecoveryFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeRecoveryFrame_Failure():
return failure(_that.identity,_that.error);case BridgeRecoveryFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeRecoveryEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeRecoveryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeRecoveryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeRecoveryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeRecoveryFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRecoveryFrame_Data extends BridgeRecoveryFrame {
  const BridgeRecoveryFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeRecoveryEvent event;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryFrame_DataCopyWith<BridgeRecoveryFrame_Data> get copyWith => _$BridgeRecoveryFrame_DataCopyWithImpl<BridgeRecoveryFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeRecoveryFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryFrame_DataCopyWith<$Res> implements $BridgeRecoveryFrameCopyWith<$Res> {
  factory $BridgeRecoveryFrame_DataCopyWith(BridgeRecoveryFrame_Data value, $Res Function(BridgeRecoveryFrame_Data) _then) = _$BridgeRecoveryFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeRecoveryEvent event
});


$BridgeRecoveryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeRecoveryFrame_DataCopyWithImpl<$Res>
    implements $BridgeRecoveryFrame_DataCopyWith<$Res> {
  _$BridgeRecoveryFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeRecoveryFrame_Data _self;
  final $Res Function(BridgeRecoveryFrame_Data) _then;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeRecoveryFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeRecoveryEvent,
  ));
}

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeRecoveryEventCopyWith<$Res> get event {

  return $BridgeRecoveryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeRecoveryFrame_ResyncRequired extends BridgeRecoveryFrame {
  const BridgeRecoveryFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryFrame_ResyncRequiredCopyWith<BridgeRecoveryFrame_ResyncRequired> get copyWith => _$BridgeRecoveryFrame_ResyncRequiredCopyWithImpl<BridgeRecoveryFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeRecoveryFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryFrame_ResyncRequiredCopyWith<$Res> implements $BridgeRecoveryFrameCopyWith<$Res> {
  factory $BridgeRecoveryFrame_ResyncRequiredCopyWith(BridgeRecoveryFrame_ResyncRequired value, $Res Function(BridgeRecoveryFrame_ResyncRequired) _then) = _$BridgeRecoveryFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeRecoveryFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeRecoveryFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeRecoveryFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeRecoveryFrame_ResyncRequired _self;
  final $Res Function(BridgeRecoveryFrame_ResyncRequired) _then;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeRecoveryFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeRecoveryFrame_Failure extends BridgeRecoveryFrame {
  const BridgeRecoveryFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryFrame_FailureCopyWith<BridgeRecoveryFrame_Failure> get copyWith => _$BridgeRecoveryFrame_FailureCopyWithImpl<BridgeRecoveryFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeRecoveryFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryFrame_FailureCopyWith<$Res> implements $BridgeRecoveryFrameCopyWith<$Res> {
  factory $BridgeRecoveryFrame_FailureCopyWith(BridgeRecoveryFrame_Failure value, $Res Function(BridgeRecoveryFrame_Failure) _then) = _$BridgeRecoveryFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeRecoveryFrame_FailureCopyWithImpl<$Res>
    implements $BridgeRecoveryFrame_FailureCopyWith<$Res> {
  _$BridgeRecoveryFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeRecoveryFrame_Failure _self;
  final $Res Function(BridgeRecoveryFrame_Failure) _then;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeRecoveryFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeRecoveryFrame_Closed extends BridgeRecoveryFrame {
  const BridgeRecoveryFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRecoveryFrame_ClosedCopyWith<BridgeRecoveryFrame_Closed> get copyWith => _$BridgeRecoveryFrame_ClosedCopyWithImpl<BridgeRecoveryFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRecoveryFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeRecoveryFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeRecoveryFrame_ClosedCopyWith<$Res> implements $BridgeRecoveryFrameCopyWith<$Res> {
  factory $BridgeRecoveryFrame_ClosedCopyWith(BridgeRecoveryFrame_Closed value, $Res Function(BridgeRecoveryFrame_Closed) _then) = _$BridgeRecoveryFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeRecoveryFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeRecoveryFrame_ClosedCopyWith<$Res> {
  _$BridgeRecoveryFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeRecoveryFrame_Closed _self;
  final $Res Function(BridgeRecoveryFrame_Closed) _then;

/// Create a copy of BridgeRecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeRecoveryFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
