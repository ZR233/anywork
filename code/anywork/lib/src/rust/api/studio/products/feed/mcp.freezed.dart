// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMcpEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpEventCopyWith<BridgeMcpEvent> get copyWith => _$BridgeMcpEventCopyWithImpl<BridgeMcpEvent>(this as BridgeMcpEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeMcpEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeMcpEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeMcpEvent;
  return 'BridgeMcpEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeMcpEventCopyWith<$Res>  {
  factory $BridgeMcpEventCopyWith(BridgeMcpEvent value, $Res Function(BridgeMcpEvent) _then) = _$BridgeMcpEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeMcpEventCopyWithImpl<$Res>
    implements $BridgeMcpEventCopyWith<$Res> {
  _$BridgeMcpEventCopyWithImpl(this._self, this._then);

  final BridgeMcpEvent _self;
  final $Res Function(BridgeMcpEvent) _then;

/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeMcpEvent].
extension BridgeMcpEventPatterns on BridgeMcpEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMcpEvent_Baseline value)?  baseline,TResult Function( BridgeMcpEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeMcpEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMcpEvent_Baseline value)  baseline,required TResult Function( BridgeMcpEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline():
return baseline(_that);case BridgeMcpEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMcpEvent_Baseline value)?  baseline,TResult? Function( BridgeMcpEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeMcpEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeMcpBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeMcpChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMcpEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeMcpBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeMcpChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMcpEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeMcpBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeMcpChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeMcpEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMcpEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMcpEvent_Baseline extends BridgeMcpEvent {
  const BridgeMcpEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeMcpBaseline value;

/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpEvent_BaselineCopyWith<BridgeMcpEvent_Baseline> get copyWith => _$BridgeMcpEvent_BaselineCopyWithImpl<BridgeMcpEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeMcpEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpEvent_BaselineCopyWith<$Res> implements $BridgeMcpEventCopyWith<$Res> {
  factory $BridgeMcpEvent_BaselineCopyWith(BridgeMcpEvent_Baseline value, $Res Function(BridgeMcpEvent_Baseline) _then) = _$BridgeMcpEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeMcpBaseline value
});




}
/// @nodoc
class _$BridgeMcpEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeMcpEvent_BaselineCopyWith<$Res> {
  _$BridgeMcpEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeMcpEvent_Baseline _self;
  final $Res Function(BridgeMcpEvent_Baseline) _then;

/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeMcpEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeMcpBaseline,
  ));
}


}

/// @nodoc


class BridgeMcpEvent_Change extends BridgeMcpEvent {
  const BridgeMcpEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeMcpChange value;

/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpEvent_ChangeCopyWith<BridgeMcpEvent_Change> get copyWith => _$BridgeMcpEvent_ChangeCopyWithImpl<BridgeMcpEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeMcpEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpEvent_ChangeCopyWith<$Res> implements $BridgeMcpEventCopyWith<$Res> {
  factory $BridgeMcpEvent_ChangeCopyWith(BridgeMcpEvent_Change value, $Res Function(BridgeMcpEvent_Change) _then) = _$BridgeMcpEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeMcpChange value
});




}
/// @nodoc
class _$BridgeMcpEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeMcpEvent_ChangeCopyWith<$Res> {
  _$BridgeMcpEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeMcpEvent_Change _self;
  final $Res Function(BridgeMcpEvent_Change) _then;

/// Create a copy of BridgeMcpEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeMcpEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeMcpChange,
  ));
}


}

/// @nodoc
mixin _$BridgeMcpFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpFrame()';
}


}

/// @nodoc
class $BridgeMcpFrameCopyWith<$Res>  {
$BridgeMcpFrameCopyWith(BridgeMcpFrame _, $Res Function(BridgeMcpFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeMcpFrame].
extension BridgeMcpFramePatterns on BridgeMcpFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMcpFrame_Data value)?  data,TResult Function( BridgeMcpFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeMcpFrame_Failure value)?  failure,TResult Function( BridgeMcpFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMcpFrame_Data() when data != null:
return data(_that);case BridgeMcpFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeMcpFrame_Failure() when failure != null:
return failure(_that);case BridgeMcpFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMcpFrame_Data value)  data,required TResult Function( BridgeMcpFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeMcpFrame_Failure value)  failure,required TResult Function( BridgeMcpFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeMcpFrame_Data():
return data(_that);case BridgeMcpFrame_ResyncRequired():
return resyncRequired(_that);case BridgeMcpFrame_Failure():
return failure(_that);case BridgeMcpFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMcpFrame_Data value)?  data,TResult? Function( BridgeMcpFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeMcpFrame_Failure value)?  failure,TResult? Function( BridgeMcpFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeMcpFrame_Data() when data != null:
return data(_that);case BridgeMcpFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeMcpFrame_Failure() when failure != null:
return failure(_that);case BridgeMcpFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeMcpEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMcpFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeMcpFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeMcpFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeMcpFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeMcpEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeMcpFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeMcpFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeMcpFrame_Failure():
return failure(_that.identity,_that.error);case BridgeMcpFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeMcpEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeMcpFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeMcpFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeMcpFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeMcpFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMcpFrame_Data extends BridgeMcpFrame {
  const BridgeMcpFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeMcpEvent event;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpFrame_DataCopyWith<BridgeMcpFrame_Data> get copyWith => _$BridgeMcpFrame_DataCopyWithImpl<BridgeMcpFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeMcpFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpFrame_DataCopyWith<$Res> implements $BridgeMcpFrameCopyWith<$Res> {
  factory $BridgeMcpFrame_DataCopyWith(BridgeMcpFrame_Data value, $Res Function(BridgeMcpFrame_Data) _then) = _$BridgeMcpFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeMcpEvent event
});


$BridgeMcpEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeMcpFrame_DataCopyWithImpl<$Res>
    implements $BridgeMcpFrame_DataCopyWith<$Res> {
  _$BridgeMcpFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeMcpFrame_Data _self;
  final $Res Function(BridgeMcpFrame_Data) _then;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeMcpFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeMcpEvent,
  ));
}

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeMcpEventCopyWith<$Res> get event {

  return $BridgeMcpEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeMcpFrame_ResyncRequired extends BridgeMcpFrame {
  const BridgeMcpFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpFrame_ResyncRequiredCopyWith<BridgeMcpFrame_ResyncRequired> get copyWith => _$BridgeMcpFrame_ResyncRequiredCopyWithImpl<BridgeMcpFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeMcpFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpFrame_ResyncRequiredCopyWith<$Res> implements $BridgeMcpFrameCopyWith<$Res> {
  factory $BridgeMcpFrame_ResyncRequiredCopyWith(BridgeMcpFrame_ResyncRequired value, $Res Function(BridgeMcpFrame_ResyncRequired) _then) = _$BridgeMcpFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeMcpFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeMcpFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeMcpFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeMcpFrame_ResyncRequired _self;
  final $Res Function(BridgeMcpFrame_ResyncRequired) _then;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeMcpFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeMcpFrame_Failure extends BridgeMcpFrame {
  const BridgeMcpFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpFrame_FailureCopyWith<BridgeMcpFrame_Failure> get copyWith => _$BridgeMcpFrame_FailureCopyWithImpl<BridgeMcpFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeMcpFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpFrame_FailureCopyWith<$Res> implements $BridgeMcpFrameCopyWith<$Res> {
  factory $BridgeMcpFrame_FailureCopyWith(BridgeMcpFrame_Failure value, $Res Function(BridgeMcpFrame_Failure) _then) = _$BridgeMcpFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeMcpFrame_FailureCopyWithImpl<$Res>
    implements $BridgeMcpFrame_FailureCopyWith<$Res> {
  _$BridgeMcpFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeMcpFrame_Failure _self;
  final $Res Function(BridgeMcpFrame_Failure) _then;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeMcpFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeMcpFrame_Closed extends BridgeMcpFrame {
  const BridgeMcpFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpFrame_ClosedCopyWith<BridgeMcpFrame_Closed> get copyWith => _$BridgeMcpFrame_ClosedCopyWithImpl<BridgeMcpFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeMcpFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpFrame_ClosedCopyWith<$Res> implements $BridgeMcpFrameCopyWith<$Res> {
  factory $BridgeMcpFrame_ClosedCopyWith(BridgeMcpFrame_Closed value, $Res Function(BridgeMcpFrame_Closed) _then) = _$BridgeMcpFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeMcpFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeMcpFrame_ClosedCopyWith<$Res> {
  _$BridgeMcpFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeMcpFrame_Closed _self;
  final $Res Function(BridgeMcpFrame_Closed) _then;

/// Create a copy of BridgeMcpFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeMcpFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
