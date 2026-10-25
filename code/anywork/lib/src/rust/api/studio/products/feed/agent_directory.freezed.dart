// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAgentDirectoryEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryEventCopyWith<BridgeAgentDirectoryEvent> get copyWith => _$BridgeAgentDirectoryEventCopyWithImpl<BridgeAgentDirectoryEvent>(this as BridgeAgentDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAgentDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAgentDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAgentDirectoryEvent;
  return 'BridgeAgentDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryEventCopyWith<$Res>  {
  factory $BridgeAgentDirectoryEventCopyWith(BridgeAgentDirectoryEvent value, $Res Function(BridgeAgentDirectoryEvent) _then) = _$BridgeAgentDirectoryEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeAgentDirectoryEventCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryEventCopyWith<$Res> {
  _$BridgeAgentDirectoryEventCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryEvent _self;
  final $Res Function(BridgeAgentDirectoryEvent) _then;

/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAgentDirectoryEvent].
extension BridgeAgentDirectoryEventPatterns on BridgeAgentDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentDirectoryEvent_Baseline value)?  baseline,TResult Function( BridgeAgentDirectoryEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAgentDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentDirectoryEvent_Baseline value)  baseline,required TResult Function( BridgeAgentDirectoryEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline():
return baseline(_that);case BridgeAgentDirectoryEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentDirectoryEvent_Baseline value)?  baseline,TResult? Function( BridgeAgentDirectoryEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAgentDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentDirectoryBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentDirectoryBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentDirectoryEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentDirectoryBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentDirectoryEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentDirectoryEvent_Baseline extends BridgeAgentDirectoryEvent {
  const BridgeAgentDirectoryEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAgentDirectoryBaseline value;

/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryEvent_BaselineCopyWith<BridgeAgentDirectoryEvent_Baseline> get copyWith => _$BridgeAgentDirectoryEvent_BaselineCopyWithImpl<BridgeAgentDirectoryEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAgentDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryEvent_BaselineCopyWith<$Res> implements $BridgeAgentDirectoryEventCopyWith<$Res> {
  factory $BridgeAgentDirectoryEvent_BaselineCopyWith(BridgeAgentDirectoryEvent_Baseline value, $Res Function(BridgeAgentDirectoryEvent_Baseline) _then) = _$BridgeAgentDirectoryEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAgentDirectoryBaseline value
});




}
/// @nodoc
class _$BridgeAgentDirectoryEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryEvent_BaselineCopyWith<$Res> {
  _$BridgeAgentDirectoryEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryEvent_Baseline _self;
  final $Res Function(BridgeAgentDirectoryEvent_Baseline) _then;

/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAgentDirectoryEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAgentDirectoryBaseline,
  ));
}


}

/// @nodoc


class BridgeAgentDirectoryEvent_Change extends BridgeAgentDirectoryEvent {
  const BridgeAgentDirectoryEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAgentDirectoryChange value;

/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryEvent_ChangeCopyWith<BridgeAgentDirectoryEvent_Change> get copyWith => _$BridgeAgentDirectoryEvent_ChangeCopyWithImpl<BridgeAgentDirectoryEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAgentDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryEvent_ChangeCopyWith<$Res> implements $BridgeAgentDirectoryEventCopyWith<$Res> {
  factory $BridgeAgentDirectoryEvent_ChangeCopyWith(BridgeAgentDirectoryEvent_Change value, $Res Function(BridgeAgentDirectoryEvent_Change) _then) = _$BridgeAgentDirectoryEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAgentDirectoryChange value
});




}
/// @nodoc
class _$BridgeAgentDirectoryEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryEvent_ChangeCopyWith<$Res> {
  _$BridgeAgentDirectoryEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryEvent_Change _self;
  final $Res Function(BridgeAgentDirectoryEvent_Change) _then;

/// Create a copy of BridgeAgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAgentDirectoryEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAgentDirectoryChange,
  ));
}


}

/// @nodoc
mixin _$BridgeAgentDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentDirectoryFrame()';
}


}

/// @nodoc
class $BridgeAgentDirectoryFrameCopyWith<$Res>  {
$BridgeAgentDirectoryFrameCopyWith(BridgeAgentDirectoryFrame _, $Res Function(BridgeAgentDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentDirectoryFrame].
extension BridgeAgentDirectoryFramePatterns on BridgeAgentDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentDirectoryFrame_Data value)?  data,TResult Function( BridgeAgentDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAgentDirectoryFrame_Failure value)?  failure,TResult Function( BridgeAgentDirectoryFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data() when data != null:
return data(_that);case BridgeAgentDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAgentDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeAgentDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentDirectoryFrame_Data value)  data,required TResult Function( BridgeAgentDirectoryFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAgentDirectoryFrame_Failure value)  failure,required TResult Function( BridgeAgentDirectoryFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data():
return data(_that);case BridgeAgentDirectoryFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAgentDirectoryFrame_Failure():
return failure(_that);case BridgeAgentDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentDirectoryFrame_Data value)?  data,TResult? Function( BridgeAgentDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAgentDirectoryFrame_Failure value)?  failure,TResult? Function( BridgeAgentDirectoryFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data() when data != null:
return data(_that);case BridgeAgentDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAgentDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeAgentDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAgentDirectoryEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAgentDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAgentDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAgentDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAgentDirectoryEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAgentDirectoryFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAgentDirectoryFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAgentDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAgentDirectoryEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAgentDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAgentDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAgentDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAgentDirectoryFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentDirectoryFrame_Data extends BridgeAgentDirectoryFrame {
  const BridgeAgentDirectoryFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAgentDirectoryEvent event;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryFrame_DataCopyWith<BridgeAgentDirectoryFrame_Data> get copyWith => _$BridgeAgentDirectoryFrame_DataCopyWithImpl<BridgeAgentDirectoryFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAgentDirectoryFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryFrame_DataCopyWith<$Res> implements $BridgeAgentDirectoryFrameCopyWith<$Res> {
  factory $BridgeAgentDirectoryFrame_DataCopyWith(BridgeAgentDirectoryFrame_Data value, $Res Function(BridgeAgentDirectoryFrame_Data) _then) = _$BridgeAgentDirectoryFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAgentDirectoryEvent event
});


$BridgeAgentDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAgentDirectoryFrame_DataCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryFrame_DataCopyWith<$Res> {
  _$BridgeAgentDirectoryFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryFrame_Data _self;
  final $Res Function(BridgeAgentDirectoryFrame_Data) _then;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAgentDirectoryFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAgentDirectoryEvent,
  ));
}

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryEventCopyWith<$Res> get event {

  return $BridgeAgentDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAgentDirectoryFrame_ResyncRequired extends BridgeAgentDirectoryFrame {
  const BridgeAgentDirectoryFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryFrame_ResyncRequiredCopyWith<BridgeAgentDirectoryFrame_ResyncRequired> get copyWith => _$BridgeAgentDirectoryFrame_ResyncRequiredCopyWithImpl<BridgeAgentDirectoryFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAgentDirectoryFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAgentDirectoryFrameCopyWith<$Res> {
  factory $BridgeAgentDirectoryFrame_ResyncRequiredCopyWith(BridgeAgentDirectoryFrame_ResyncRequired value, $Res Function(BridgeAgentDirectoryFrame_ResyncRequired) _then) = _$BridgeAgentDirectoryFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAgentDirectoryFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAgentDirectoryFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryFrame_ResyncRequired _self;
  final $Res Function(BridgeAgentDirectoryFrame_ResyncRequired) _then;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAgentDirectoryFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAgentDirectoryFrame_Failure extends BridgeAgentDirectoryFrame {
  const BridgeAgentDirectoryFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryFrame_FailureCopyWith<BridgeAgentDirectoryFrame_Failure> get copyWith => _$BridgeAgentDirectoryFrame_FailureCopyWithImpl<BridgeAgentDirectoryFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAgentDirectoryFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryFrame_FailureCopyWith<$Res> implements $BridgeAgentDirectoryFrameCopyWith<$Res> {
  factory $BridgeAgentDirectoryFrame_FailureCopyWith(BridgeAgentDirectoryFrame_Failure value, $Res Function(BridgeAgentDirectoryFrame_Failure) _then) = _$BridgeAgentDirectoryFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAgentDirectoryFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryFrame_FailureCopyWith<$Res> {
  _$BridgeAgentDirectoryFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryFrame_Failure _self;
  final $Res Function(BridgeAgentDirectoryFrame_Failure) _then;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAgentDirectoryFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAgentDirectoryFrame_Closed extends BridgeAgentDirectoryFrame {
  const BridgeAgentDirectoryFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentDirectoryFrame_ClosedCopyWith<BridgeAgentDirectoryFrame_Closed> get copyWith => _$BridgeAgentDirectoryFrame_ClosedCopyWithImpl<BridgeAgentDirectoryFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentDirectoryFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAgentDirectoryFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentDirectoryFrame_ClosedCopyWith<$Res> implements $BridgeAgentDirectoryFrameCopyWith<$Res> {
  factory $BridgeAgentDirectoryFrame_ClosedCopyWith(BridgeAgentDirectoryFrame_Closed value, $Res Function(BridgeAgentDirectoryFrame_Closed) _then) = _$BridgeAgentDirectoryFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAgentDirectoryFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAgentDirectoryFrame_ClosedCopyWith<$Res> {
  _$BridgeAgentDirectoryFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAgentDirectoryFrame_Closed _self;
  final $Res Function(BridgeAgentDirectoryFrame_Closed) _then;

/// Create a copy of BridgeAgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAgentDirectoryFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
