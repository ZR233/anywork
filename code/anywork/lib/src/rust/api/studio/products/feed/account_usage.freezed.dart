// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_usage.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAccountUsageEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageEventCopyWith<BridgeAccountUsageEvent> get copyWith => _$BridgeAccountUsageEventCopyWithImpl<BridgeAccountUsageEvent>(this as BridgeAccountUsageEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAccountUsageEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAccountUsageEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAccountUsageEvent;
  return 'BridgeAccountUsageEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageEventCopyWith<$Res>  {
  factory $BridgeAccountUsageEventCopyWith(BridgeAccountUsageEvent value, $Res Function(BridgeAccountUsageEvent) _then) = _$BridgeAccountUsageEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeAccountUsageEventCopyWithImpl<$Res>
    implements $BridgeAccountUsageEventCopyWith<$Res> {
  _$BridgeAccountUsageEventCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageEvent _self;
  final $Res Function(BridgeAccountUsageEvent) _then;

/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAccountUsageEvent].
extension BridgeAccountUsageEventPatterns on BridgeAccountUsageEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountUsageEvent_Baseline value)?  baseline,TResult Function( BridgeAccountUsageEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAccountUsageEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountUsageEvent_Baseline value)  baseline,required TResult Function( BridgeAccountUsageEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline():
return baseline(_that);case BridgeAccountUsageEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountUsageEvent_Baseline value)?  baseline,TResult? Function( BridgeAccountUsageEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAccountUsageEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountUsageBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountUsageChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountUsageEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountUsageBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountUsageChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountUsageEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountUsageBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountUsageChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountUsageEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountUsageEvent_Baseline extends BridgeAccountUsageEvent {
  const BridgeAccountUsageEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAccountUsageBaseline value;

/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageEvent_BaselineCopyWith<BridgeAccountUsageEvent_Baseline> get copyWith => _$BridgeAccountUsageEvent_BaselineCopyWithImpl<BridgeAccountUsageEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAccountUsageEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageEvent_BaselineCopyWith<$Res> implements $BridgeAccountUsageEventCopyWith<$Res> {
  factory $BridgeAccountUsageEvent_BaselineCopyWith(BridgeAccountUsageEvent_Baseline value, $Res Function(BridgeAccountUsageEvent_Baseline) _then) = _$BridgeAccountUsageEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAccountUsageBaseline value
});




}
/// @nodoc
class _$BridgeAccountUsageEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAccountUsageEvent_BaselineCopyWith<$Res> {
  _$BridgeAccountUsageEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageEvent_Baseline _self;
  final $Res Function(BridgeAccountUsageEvent_Baseline) _then;

/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAccountUsageEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAccountUsageBaseline,
  ));
}


}

/// @nodoc


class BridgeAccountUsageEvent_Change extends BridgeAccountUsageEvent {
  const BridgeAccountUsageEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAccountUsageChange value;

/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageEvent_ChangeCopyWith<BridgeAccountUsageEvent_Change> get copyWith => _$BridgeAccountUsageEvent_ChangeCopyWithImpl<BridgeAccountUsageEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAccountUsageEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageEvent_ChangeCopyWith<$Res> implements $BridgeAccountUsageEventCopyWith<$Res> {
  factory $BridgeAccountUsageEvent_ChangeCopyWith(BridgeAccountUsageEvent_Change value, $Res Function(BridgeAccountUsageEvent_Change) _then) = _$BridgeAccountUsageEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAccountUsageChange value
});




}
/// @nodoc
class _$BridgeAccountUsageEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAccountUsageEvent_ChangeCopyWith<$Res> {
  _$BridgeAccountUsageEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageEvent_Change _self;
  final $Res Function(BridgeAccountUsageEvent_Change) _then;

/// Create a copy of BridgeAccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAccountUsageEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAccountUsageChange,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountUsageFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountUsageFrame()';
}


}

/// @nodoc
class $BridgeAccountUsageFrameCopyWith<$Res>  {
$BridgeAccountUsageFrameCopyWith(BridgeAccountUsageFrame _, $Res Function(BridgeAccountUsageFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountUsageFrame].
extension BridgeAccountUsageFramePatterns on BridgeAccountUsageFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountUsageFrame_Data value)?  data,TResult Function( BridgeAccountUsageFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAccountUsageFrame_Failure value)?  failure,TResult Function( BridgeAccountUsageFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data() when data != null:
return data(_that);case BridgeAccountUsageFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAccountUsageFrame_Failure() when failure != null:
return failure(_that);case BridgeAccountUsageFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountUsageFrame_Data value)  data,required TResult Function( BridgeAccountUsageFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAccountUsageFrame_Failure value)  failure,required TResult Function( BridgeAccountUsageFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data():
return data(_that);case BridgeAccountUsageFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAccountUsageFrame_Failure():
return failure(_that);case BridgeAccountUsageFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountUsageFrame_Data value)?  data,TResult? Function( BridgeAccountUsageFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAccountUsageFrame_Failure value)?  failure,TResult? Function( BridgeAccountUsageFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data() when data != null:
return data(_that);case BridgeAccountUsageFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAccountUsageFrame_Failure() when failure != null:
return failure(_that);case BridgeAccountUsageFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAccountUsageEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAccountUsageFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAccountUsageFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAccountUsageFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAccountUsageEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAccountUsageFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAccountUsageFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAccountUsageFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAccountUsageEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAccountUsageFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAccountUsageFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAccountUsageFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountUsageFrame_Data extends BridgeAccountUsageFrame {
  const BridgeAccountUsageFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAccountUsageEvent event;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageFrame_DataCopyWith<BridgeAccountUsageFrame_Data> get copyWith => _$BridgeAccountUsageFrame_DataCopyWithImpl<BridgeAccountUsageFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAccountUsageFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageFrame_DataCopyWith<$Res> implements $BridgeAccountUsageFrameCopyWith<$Res> {
  factory $BridgeAccountUsageFrame_DataCopyWith(BridgeAccountUsageFrame_Data value, $Res Function(BridgeAccountUsageFrame_Data) _then) = _$BridgeAccountUsageFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAccountUsageEvent event
});


$BridgeAccountUsageEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAccountUsageFrame_DataCopyWithImpl<$Res>
    implements $BridgeAccountUsageFrame_DataCopyWith<$Res> {
  _$BridgeAccountUsageFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageFrame_Data _self;
  final $Res Function(BridgeAccountUsageFrame_Data) _then;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAccountUsageFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAccountUsageEvent,
  ));
}

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAccountUsageEventCopyWith<$Res> get event {

  return $BridgeAccountUsageEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAccountUsageFrame_ResyncRequired extends BridgeAccountUsageFrame {
  const BridgeAccountUsageFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageFrame_ResyncRequiredCopyWith<BridgeAccountUsageFrame_ResyncRequired> get copyWith => _$BridgeAccountUsageFrame_ResyncRequiredCopyWithImpl<BridgeAccountUsageFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAccountUsageFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAccountUsageFrameCopyWith<$Res> {
  factory $BridgeAccountUsageFrame_ResyncRequiredCopyWith(BridgeAccountUsageFrame_ResyncRequired value, $Res Function(BridgeAccountUsageFrame_ResyncRequired) _then) = _$BridgeAccountUsageFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAccountUsageFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAccountUsageFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAccountUsageFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageFrame_ResyncRequired _self;
  final $Res Function(BridgeAccountUsageFrame_ResyncRequired) _then;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAccountUsageFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAccountUsageFrame_Failure extends BridgeAccountUsageFrame {
  const BridgeAccountUsageFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageFrame_FailureCopyWith<BridgeAccountUsageFrame_Failure> get copyWith => _$BridgeAccountUsageFrame_FailureCopyWithImpl<BridgeAccountUsageFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAccountUsageFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageFrame_FailureCopyWith<$Res> implements $BridgeAccountUsageFrameCopyWith<$Res> {
  factory $BridgeAccountUsageFrame_FailureCopyWith(BridgeAccountUsageFrame_Failure value, $Res Function(BridgeAccountUsageFrame_Failure) _then) = _$BridgeAccountUsageFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAccountUsageFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAccountUsageFrame_FailureCopyWith<$Res> {
  _$BridgeAccountUsageFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageFrame_Failure _self;
  final $Res Function(BridgeAccountUsageFrame_Failure) _then;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAccountUsageFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAccountUsageFrame_Closed extends BridgeAccountUsageFrame {
  const BridgeAccountUsageFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageFrame_ClosedCopyWith<BridgeAccountUsageFrame_Closed> get copyWith => _$BridgeAccountUsageFrame_ClosedCopyWithImpl<BridgeAccountUsageFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAccountUsageFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageFrame_ClosedCopyWith<$Res> implements $BridgeAccountUsageFrameCopyWith<$Res> {
  factory $BridgeAccountUsageFrame_ClosedCopyWith(BridgeAccountUsageFrame_Closed value, $Res Function(BridgeAccountUsageFrame_Closed) _then) = _$BridgeAccountUsageFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAccountUsageFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAccountUsageFrame_ClosedCopyWith<$Res> {
  _$BridgeAccountUsageFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageFrame_Closed _self;
  final $Res Function(BridgeAccountUsageFrame_Closed) _then;

/// Create a copy of BridgeAccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAccountUsageFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
