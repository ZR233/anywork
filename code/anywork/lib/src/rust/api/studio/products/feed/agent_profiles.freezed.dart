// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_profiles.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAgentProfilesEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesEventCopyWith<BridgeAgentProfilesEvent> get copyWith => _$BridgeAgentProfilesEventCopyWithImpl<BridgeAgentProfilesEvent>(this as BridgeAgentProfilesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAgentProfilesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAgentProfilesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAgentProfilesEvent;
  return 'BridgeAgentProfilesEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesEventCopyWith<$Res>  {
  factory $BridgeAgentProfilesEventCopyWith(BridgeAgentProfilesEvent value, $Res Function(BridgeAgentProfilesEvent) _then) = _$BridgeAgentProfilesEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeAgentProfilesEventCopyWithImpl<$Res>
    implements $BridgeAgentProfilesEventCopyWith<$Res> {
  _$BridgeAgentProfilesEventCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesEvent _self;
  final $Res Function(BridgeAgentProfilesEvent) _then;

/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAgentProfilesEvent].
extension BridgeAgentProfilesEventPatterns on BridgeAgentProfilesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentProfilesEvent_Baseline value)?  baseline,TResult Function( BridgeAgentProfilesEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAgentProfilesEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentProfilesEvent_Baseline value)  baseline,required TResult Function( BridgeAgentProfilesEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline():
return baseline(_that);case BridgeAgentProfilesEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentProfilesEvent_Baseline value)?  baseline,TResult? Function( BridgeAgentProfilesEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAgentProfilesEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentProfilesBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentProfilesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentProfilesEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentProfilesBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentProfilesChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentProfilesEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAgentProfilesBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAgentProfilesChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAgentProfilesEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentProfilesEvent_Baseline extends BridgeAgentProfilesEvent {
  const BridgeAgentProfilesEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAgentProfilesBaseline value;

/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesEvent_BaselineCopyWith<BridgeAgentProfilesEvent_Baseline> get copyWith => _$BridgeAgentProfilesEvent_BaselineCopyWithImpl<BridgeAgentProfilesEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAgentProfilesEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesEvent_BaselineCopyWith<$Res> implements $BridgeAgentProfilesEventCopyWith<$Res> {
  factory $BridgeAgentProfilesEvent_BaselineCopyWith(BridgeAgentProfilesEvent_Baseline value, $Res Function(BridgeAgentProfilesEvent_Baseline) _then) = _$BridgeAgentProfilesEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAgentProfilesBaseline value
});




}
/// @nodoc
class _$BridgeAgentProfilesEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAgentProfilesEvent_BaselineCopyWith<$Res> {
  _$BridgeAgentProfilesEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesEvent_Baseline _self;
  final $Res Function(BridgeAgentProfilesEvent_Baseline) _then;

/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAgentProfilesEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAgentProfilesBaseline,
  ));
}


}

/// @nodoc


class BridgeAgentProfilesEvent_Change extends BridgeAgentProfilesEvent {
  const BridgeAgentProfilesEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAgentProfilesChange value;

/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesEvent_ChangeCopyWith<BridgeAgentProfilesEvent_Change> get copyWith => _$BridgeAgentProfilesEvent_ChangeCopyWithImpl<BridgeAgentProfilesEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAgentProfilesEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesEvent_ChangeCopyWith<$Res> implements $BridgeAgentProfilesEventCopyWith<$Res> {
  factory $BridgeAgentProfilesEvent_ChangeCopyWith(BridgeAgentProfilesEvent_Change value, $Res Function(BridgeAgentProfilesEvent_Change) _then) = _$BridgeAgentProfilesEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAgentProfilesChange value
});




}
/// @nodoc
class _$BridgeAgentProfilesEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAgentProfilesEvent_ChangeCopyWith<$Res> {
  _$BridgeAgentProfilesEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesEvent_Change _self;
  final $Res Function(BridgeAgentProfilesEvent_Change) _then;

/// Create a copy of BridgeAgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAgentProfilesEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAgentProfilesChange,
  ));
}


}

/// @nodoc
mixin _$BridgeAgentProfilesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentProfilesFrame()';
}


}

/// @nodoc
class $BridgeAgentProfilesFrameCopyWith<$Res>  {
$BridgeAgentProfilesFrameCopyWith(BridgeAgentProfilesFrame _, $Res Function(BridgeAgentProfilesFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentProfilesFrame].
extension BridgeAgentProfilesFramePatterns on BridgeAgentProfilesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentProfilesFrame_Data value)?  data,TResult Function( BridgeAgentProfilesFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAgentProfilesFrame_Failure value)?  failure,TResult Function( BridgeAgentProfilesFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data() when data != null:
return data(_that);case BridgeAgentProfilesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAgentProfilesFrame_Failure() when failure != null:
return failure(_that);case BridgeAgentProfilesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentProfilesFrame_Data value)  data,required TResult Function( BridgeAgentProfilesFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAgentProfilesFrame_Failure value)  failure,required TResult Function( BridgeAgentProfilesFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data():
return data(_that);case BridgeAgentProfilesFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAgentProfilesFrame_Failure():
return failure(_that);case BridgeAgentProfilesFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentProfilesFrame_Data value)?  data,TResult? Function( BridgeAgentProfilesFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAgentProfilesFrame_Failure value)?  failure,TResult? Function( BridgeAgentProfilesFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data() when data != null:
return data(_that);case BridgeAgentProfilesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAgentProfilesFrame_Failure() when failure != null:
return failure(_that);case BridgeAgentProfilesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAgentProfilesEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAgentProfilesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAgentProfilesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAgentProfilesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAgentProfilesEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAgentProfilesFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAgentProfilesFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAgentProfilesFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAgentProfilesEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAgentProfilesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAgentProfilesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAgentProfilesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAgentProfilesFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentProfilesFrame_Data extends BridgeAgentProfilesFrame {
  const BridgeAgentProfilesFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAgentProfilesEvent event;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesFrame_DataCopyWith<BridgeAgentProfilesFrame_Data> get copyWith => _$BridgeAgentProfilesFrame_DataCopyWithImpl<BridgeAgentProfilesFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAgentProfilesFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesFrame_DataCopyWith<$Res> implements $BridgeAgentProfilesFrameCopyWith<$Res> {
  factory $BridgeAgentProfilesFrame_DataCopyWith(BridgeAgentProfilesFrame_Data value, $Res Function(BridgeAgentProfilesFrame_Data) _then) = _$BridgeAgentProfilesFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAgentProfilesEvent event
});


$BridgeAgentProfilesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAgentProfilesFrame_DataCopyWithImpl<$Res>
    implements $BridgeAgentProfilesFrame_DataCopyWith<$Res> {
  _$BridgeAgentProfilesFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesFrame_Data _self;
  final $Res Function(BridgeAgentProfilesFrame_Data) _then;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAgentProfilesFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAgentProfilesEvent,
  ));
}

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAgentProfilesEventCopyWith<$Res> get event {

  return $BridgeAgentProfilesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAgentProfilesFrame_ResyncRequired extends BridgeAgentProfilesFrame {
  const BridgeAgentProfilesFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesFrame_ResyncRequiredCopyWith<BridgeAgentProfilesFrame_ResyncRequired> get copyWith => _$BridgeAgentProfilesFrame_ResyncRequiredCopyWithImpl<BridgeAgentProfilesFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAgentProfilesFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAgentProfilesFrameCopyWith<$Res> {
  factory $BridgeAgentProfilesFrame_ResyncRequiredCopyWith(BridgeAgentProfilesFrame_ResyncRequired value, $Res Function(BridgeAgentProfilesFrame_ResyncRequired) _then) = _$BridgeAgentProfilesFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAgentProfilesFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAgentProfilesFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAgentProfilesFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesFrame_ResyncRequired _self;
  final $Res Function(BridgeAgentProfilesFrame_ResyncRequired) _then;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAgentProfilesFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAgentProfilesFrame_Failure extends BridgeAgentProfilesFrame {
  const BridgeAgentProfilesFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesFrame_FailureCopyWith<BridgeAgentProfilesFrame_Failure> get copyWith => _$BridgeAgentProfilesFrame_FailureCopyWithImpl<BridgeAgentProfilesFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAgentProfilesFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesFrame_FailureCopyWith<$Res> implements $BridgeAgentProfilesFrameCopyWith<$Res> {
  factory $BridgeAgentProfilesFrame_FailureCopyWith(BridgeAgentProfilesFrame_Failure value, $Res Function(BridgeAgentProfilesFrame_Failure) _then) = _$BridgeAgentProfilesFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAgentProfilesFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAgentProfilesFrame_FailureCopyWith<$Res> {
  _$BridgeAgentProfilesFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesFrame_Failure _self;
  final $Res Function(BridgeAgentProfilesFrame_Failure) _then;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAgentProfilesFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAgentProfilesFrame_Closed extends BridgeAgentProfilesFrame {
  const BridgeAgentProfilesFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentProfilesFrame_ClosedCopyWith<BridgeAgentProfilesFrame_Closed> get copyWith => _$BridgeAgentProfilesFrame_ClosedCopyWithImpl<BridgeAgentProfilesFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentProfilesFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAgentProfilesFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentProfilesFrame_ClosedCopyWith<$Res> implements $BridgeAgentProfilesFrameCopyWith<$Res> {
  factory $BridgeAgentProfilesFrame_ClosedCopyWith(BridgeAgentProfilesFrame_Closed value, $Res Function(BridgeAgentProfilesFrame_Closed) _then) = _$BridgeAgentProfilesFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAgentProfilesFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAgentProfilesFrame_ClosedCopyWith<$Res> {
  _$BridgeAgentProfilesFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAgentProfilesFrame_Closed _self;
  final $Res Function(BridgeAgentProfilesFrame_Closed) _then;

/// Create a copy of BridgeAgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAgentProfilesFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
