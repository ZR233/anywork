// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_auth.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpAuthEvent {

 BridgeProductProjectionStamp get stamp; BridgeAcpAuthSnapshot get value;
/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthEventCopyWith<BridgeAcpAuthEvent> get copyWith => _$BridgeAcpAuthEventCopyWithImpl<BridgeAcpAuthEvent>(this as BridgeAcpAuthEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpAuthEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAcpAuthEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeAcpAuthEvent;
  return 'BridgeAcpAuthEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthEventCopyWith<$Res>  {
  factory $BridgeAcpAuthEventCopyWith(BridgeAcpAuthEvent value, $Res Function(BridgeAcpAuthEvent) _then) = _$BridgeAcpAuthEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgeAcpAuthSnapshot value
});




}
/// @nodoc
class _$BridgeAcpAuthEventCopyWithImpl<$Res>
    implements $BridgeAcpAuthEventCopyWith<$Res> {
  _$BridgeAcpAuthEventCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthEvent _self;
  final $Res Function(BridgeAcpAuthEvent) _then;

/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthSnapshot,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAcpAuthEvent].
extension BridgeAcpAuthEventPatterns on BridgeAcpAuthEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAuthEvent_Baseline value)?  baseline,TResult Function( BridgeAcpAuthEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAcpAuthEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAuthEvent_Baseline value)  baseline,required TResult Function( BridgeAcpAuthEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline():
return baseline(_that);case BridgeAcpAuthEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAuthEvent_Baseline value)?  baseline,TResult? Function( BridgeAcpAuthEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAcpAuthEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpAuthSnapshot value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpAuthSnapshot value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpAuthEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpAuthSnapshot value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpAuthSnapshot value)  change,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpAuthEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpAuthSnapshot value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpAuthSnapshot value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpAuthEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAuthEvent_Baseline extends BridgeAcpAuthEvent {
  const BridgeAcpAuthEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAcpAuthSnapshot value;

/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthEvent_BaselineCopyWith<BridgeAcpAuthEvent_Baseline> get copyWith => _$BridgeAcpAuthEvent_BaselineCopyWithImpl<BridgeAcpAuthEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAcpAuthEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthEvent_BaselineCopyWith<$Res> implements $BridgeAcpAuthEventCopyWith<$Res> {
  factory $BridgeAcpAuthEvent_BaselineCopyWith(BridgeAcpAuthEvent_Baseline value, $Res Function(BridgeAcpAuthEvent_Baseline) _then) = _$BridgeAcpAuthEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAcpAuthSnapshot value
});




}
/// @nodoc
class _$BridgeAcpAuthEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAcpAuthEvent_BaselineCopyWith<$Res> {
  _$BridgeAcpAuthEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthEvent_Baseline _self;
  final $Res Function(BridgeAcpAuthEvent_Baseline) _then;

/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAcpAuthEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthSnapshot,
  ));
}


}

/// @nodoc


class BridgeAcpAuthEvent_Change extends BridgeAcpAuthEvent {
  const BridgeAcpAuthEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAcpAuthSnapshot value;

/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthEvent_ChangeCopyWith<BridgeAcpAuthEvent_Change> get copyWith => _$BridgeAcpAuthEvent_ChangeCopyWithImpl<BridgeAcpAuthEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAcpAuthEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthEvent_ChangeCopyWith<$Res> implements $BridgeAcpAuthEventCopyWith<$Res> {
  factory $BridgeAcpAuthEvent_ChangeCopyWith(BridgeAcpAuthEvent_Change value, $Res Function(BridgeAcpAuthEvent_Change) _then) = _$BridgeAcpAuthEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAcpAuthSnapshot value
});




}
/// @nodoc
class _$BridgeAcpAuthEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAcpAuthEvent_ChangeCopyWith<$Res> {
  _$BridgeAcpAuthEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthEvent_Change _self;
  final $Res Function(BridgeAcpAuthEvent_Change) _then;

/// Create a copy of BridgeAcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAcpAuthEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthSnapshot,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpAuthFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthFrame()';
}


}

/// @nodoc
class $BridgeAcpAuthFrameCopyWith<$Res>  {
$BridgeAcpAuthFrameCopyWith(BridgeAcpAuthFrame _, $Res Function(BridgeAcpAuthFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpAuthFrame].
extension BridgeAcpAuthFramePatterns on BridgeAcpAuthFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAuthFrame_Data value)?  data,TResult Function( BridgeAcpAuthFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAcpAuthFrame_Failure value)?  failure,TResult Function( BridgeAcpAuthFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data() when data != null:
return data(_that);case BridgeAcpAuthFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAcpAuthFrame_Failure() when failure != null:
return failure(_that);case BridgeAcpAuthFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAuthFrame_Data value)  data,required TResult Function( BridgeAcpAuthFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAcpAuthFrame_Failure value)  failure,required TResult Function( BridgeAcpAuthFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data():
return data(_that);case BridgeAcpAuthFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAcpAuthFrame_Failure():
return failure(_that);case BridgeAcpAuthFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAuthFrame_Data value)?  data,TResult? Function( BridgeAcpAuthFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAcpAuthFrame_Failure value)?  failure,TResult? Function( BridgeAcpAuthFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data() when data != null:
return data(_that);case BridgeAcpAuthFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAcpAuthFrame_Failure() when failure != null:
return failure(_that);case BridgeAcpAuthFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAcpAuthEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAcpAuthFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAcpAuthFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAcpAuthFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAcpAuthEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAcpAuthFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAcpAuthFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAcpAuthFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAcpAuthEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAcpAuthFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAcpAuthFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAcpAuthFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAuthFrame_Data extends BridgeAcpAuthFrame {
  const BridgeAcpAuthFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAcpAuthEvent event;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthFrame_DataCopyWith<BridgeAcpAuthFrame_Data> get copyWith => _$BridgeAcpAuthFrame_DataCopyWithImpl<BridgeAcpAuthFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAcpAuthFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthFrame_DataCopyWith<$Res> implements $BridgeAcpAuthFrameCopyWith<$Res> {
  factory $BridgeAcpAuthFrame_DataCopyWith(BridgeAcpAuthFrame_Data value, $Res Function(BridgeAcpAuthFrame_Data) _then) = _$BridgeAcpAuthFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAcpAuthEvent event
});


$BridgeAcpAuthEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAcpAuthFrame_DataCopyWithImpl<$Res>
    implements $BridgeAcpAuthFrame_DataCopyWith<$Res> {
  _$BridgeAcpAuthFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthFrame_Data _self;
  final $Res Function(BridgeAcpAuthFrame_Data) _then;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAcpAuthFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthEvent,
  ));
}

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpAuthEventCopyWith<$Res> get event {

  return $BridgeAcpAuthEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAcpAuthFrame_ResyncRequired extends BridgeAcpAuthFrame {
  const BridgeAcpAuthFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthFrame_ResyncRequiredCopyWith<BridgeAcpAuthFrame_ResyncRequired> get copyWith => _$BridgeAcpAuthFrame_ResyncRequiredCopyWithImpl<BridgeAcpAuthFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAcpAuthFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAcpAuthFrameCopyWith<$Res> {
  factory $BridgeAcpAuthFrame_ResyncRequiredCopyWith(BridgeAcpAuthFrame_ResyncRequired value, $Res Function(BridgeAcpAuthFrame_ResyncRequired) _then) = _$BridgeAcpAuthFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAcpAuthFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAcpAuthFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAcpAuthFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthFrame_ResyncRequired _self;
  final $Res Function(BridgeAcpAuthFrame_ResyncRequired) _then;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAcpAuthFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAcpAuthFrame_Failure extends BridgeAcpAuthFrame {
  const BridgeAcpAuthFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthFrame_FailureCopyWith<BridgeAcpAuthFrame_Failure> get copyWith => _$BridgeAcpAuthFrame_FailureCopyWithImpl<BridgeAcpAuthFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAcpAuthFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthFrame_FailureCopyWith<$Res> implements $BridgeAcpAuthFrameCopyWith<$Res> {
  factory $BridgeAcpAuthFrame_FailureCopyWith(BridgeAcpAuthFrame_Failure value, $Res Function(BridgeAcpAuthFrame_Failure) _then) = _$BridgeAcpAuthFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAcpAuthFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAcpAuthFrame_FailureCopyWith<$Res> {
  _$BridgeAcpAuthFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthFrame_Failure _self;
  final $Res Function(BridgeAcpAuthFrame_Failure) _then;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAcpAuthFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAcpAuthFrame_Closed extends BridgeAcpAuthFrame {
  const BridgeAcpAuthFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthFrame_ClosedCopyWith<BridgeAcpAuthFrame_Closed> get copyWith => _$BridgeAcpAuthFrame_ClosedCopyWithImpl<BridgeAcpAuthFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAcpAuthFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthFrame_ClosedCopyWith<$Res> implements $BridgeAcpAuthFrameCopyWith<$Res> {
  factory $BridgeAcpAuthFrame_ClosedCopyWith(BridgeAcpAuthFrame_Closed value, $Res Function(BridgeAcpAuthFrame_Closed) _then) = _$BridgeAcpAuthFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAcpAuthFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAcpAuthFrame_ClosedCopyWith<$Res> {
  _$BridgeAcpAuthFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthFrame_Closed _self;
  final $Res Function(BridgeAcpAuthFrame_Closed) _then;

/// Create a copy of BridgeAcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAcpAuthFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
