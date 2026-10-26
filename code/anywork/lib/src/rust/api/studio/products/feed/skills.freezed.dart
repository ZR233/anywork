// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSkillsEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsEventCopyWith<BridgeSkillsEvent> get copyWith => _$BridgeSkillsEventCopyWithImpl<BridgeSkillsEvent>(this as BridgeSkillsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeSkillsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeSkillsEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeSkillsEvent;
  return 'BridgeSkillsEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsEventCopyWith<$Res>  {
  factory $BridgeSkillsEventCopyWith(BridgeSkillsEvent value, $Res Function(BridgeSkillsEvent) _then) = _$BridgeSkillsEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeSkillsEventCopyWithImpl<$Res>
    implements $BridgeSkillsEventCopyWith<$Res> {
  _$BridgeSkillsEventCopyWithImpl(this._self, this._then);

  final BridgeSkillsEvent _self;
  final $Res Function(BridgeSkillsEvent) _then;

/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeSkillsEvent].
extension BridgeSkillsEventPatterns on BridgeSkillsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillsEvent_Baseline value)?  baseline,TResult Function( BridgeSkillsEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeSkillsEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillsEvent_Baseline value)  baseline,required TResult Function( BridgeSkillsEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline():
return baseline(_that);case BridgeSkillsEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillsEvent_Baseline value)?  baseline,TResult? Function( BridgeSkillsEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeSkillsEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSkillsBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSkillsChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSkillsEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSkillsBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSkillsChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSkillsEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSkillsBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSkillsChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeSkillsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSkillsEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillsEvent_Baseline extends BridgeSkillsEvent {
  const BridgeSkillsEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeSkillsBaseline value;

/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsEvent_BaselineCopyWith<BridgeSkillsEvent_Baseline> get copyWith => _$BridgeSkillsEvent_BaselineCopyWithImpl<BridgeSkillsEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeSkillsEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsEvent_BaselineCopyWith<$Res> implements $BridgeSkillsEventCopyWith<$Res> {
  factory $BridgeSkillsEvent_BaselineCopyWith(BridgeSkillsEvent_Baseline value, $Res Function(BridgeSkillsEvent_Baseline) _then) = _$BridgeSkillsEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeSkillsBaseline value
});




}
/// @nodoc
class _$BridgeSkillsEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeSkillsEvent_BaselineCopyWith<$Res> {
  _$BridgeSkillsEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeSkillsEvent_Baseline _self;
  final $Res Function(BridgeSkillsEvent_Baseline) _then;

/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeSkillsEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeSkillsBaseline,
  ));
}


}

/// @nodoc


class BridgeSkillsEvent_Change extends BridgeSkillsEvent {
  const BridgeSkillsEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeSkillsChange value;

/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsEvent_ChangeCopyWith<BridgeSkillsEvent_Change> get copyWith => _$BridgeSkillsEvent_ChangeCopyWithImpl<BridgeSkillsEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeSkillsEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsEvent_ChangeCopyWith<$Res> implements $BridgeSkillsEventCopyWith<$Res> {
  factory $BridgeSkillsEvent_ChangeCopyWith(BridgeSkillsEvent_Change value, $Res Function(BridgeSkillsEvent_Change) _then) = _$BridgeSkillsEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeSkillsChange value
});




}
/// @nodoc
class _$BridgeSkillsEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeSkillsEvent_ChangeCopyWith<$Res> {
  _$BridgeSkillsEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeSkillsEvent_Change _self;
  final $Res Function(BridgeSkillsEvent_Change) _then;

/// Create a copy of BridgeSkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeSkillsEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeSkillsChange,
  ));
}


}

/// @nodoc
mixin _$BridgeSkillsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSkillsFrame()';
}


}

/// @nodoc
class $BridgeSkillsFrameCopyWith<$Res>  {
$BridgeSkillsFrameCopyWith(BridgeSkillsFrame _, $Res Function(BridgeSkillsFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeSkillsFrame].
extension BridgeSkillsFramePatterns on BridgeSkillsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillsFrame_Data value)?  data,TResult Function( BridgeSkillsFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeSkillsFrame_Failure value)?  failure,TResult Function( BridgeSkillsFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data() when data != null:
return data(_that);case BridgeSkillsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeSkillsFrame_Failure() when failure != null:
return failure(_that);case BridgeSkillsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillsFrame_Data value)  data,required TResult Function( BridgeSkillsFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeSkillsFrame_Failure value)  failure,required TResult Function( BridgeSkillsFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data():
return data(_that);case BridgeSkillsFrame_ResyncRequired():
return resyncRequired(_that);case BridgeSkillsFrame_Failure():
return failure(_that);case BridgeSkillsFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillsFrame_Data value)?  data,TResult? Function( BridgeSkillsFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeSkillsFrame_Failure value)?  failure,TResult? Function( BridgeSkillsFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data() when data != null:
return data(_that);case BridgeSkillsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeSkillsFrame_Failure() when failure != null:
return failure(_that);case BridgeSkillsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeSkillsEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeSkillsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeSkillsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeSkillsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeSkillsEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeSkillsFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeSkillsFrame_Failure():
return failure(_that.identity,_that.error);case BridgeSkillsFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeSkillsEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeSkillsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeSkillsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeSkillsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeSkillsFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillsFrame_Data extends BridgeSkillsFrame {
  const BridgeSkillsFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeSkillsEvent event;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsFrame_DataCopyWith<BridgeSkillsFrame_Data> get copyWith => _$BridgeSkillsFrame_DataCopyWithImpl<BridgeSkillsFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeSkillsFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsFrame_DataCopyWith<$Res> implements $BridgeSkillsFrameCopyWith<$Res> {
  factory $BridgeSkillsFrame_DataCopyWith(BridgeSkillsFrame_Data value, $Res Function(BridgeSkillsFrame_Data) _then) = _$BridgeSkillsFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeSkillsEvent event
});


$BridgeSkillsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeSkillsFrame_DataCopyWithImpl<$Res>
    implements $BridgeSkillsFrame_DataCopyWith<$Res> {
  _$BridgeSkillsFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeSkillsFrame_Data _self;
  final $Res Function(BridgeSkillsFrame_Data) _then;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeSkillsFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeSkillsEvent,
  ));
}

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSkillsEventCopyWith<$Res> get event {

  return $BridgeSkillsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeSkillsFrame_ResyncRequired extends BridgeSkillsFrame {
  const BridgeSkillsFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsFrame_ResyncRequiredCopyWith<BridgeSkillsFrame_ResyncRequired> get copyWith => _$BridgeSkillsFrame_ResyncRequiredCopyWithImpl<BridgeSkillsFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeSkillsFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsFrame_ResyncRequiredCopyWith<$Res> implements $BridgeSkillsFrameCopyWith<$Res> {
  factory $BridgeSkillsFrame_ResyncRequiredCopyWith(BridgeSkillsFrame_ResyncRequired value, $Res Function(BridgeSkillsFrame_ResyncRequired) _then) = _$BridgeSkillsFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeSkillsFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeSkillsFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeSkillsFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeSkillsFrame_ResyncRequired _self;
  final $Res Function(BridgeSkillsFrame_ResyncRequired) _then;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeSkillsFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeSkillsFrame_Failure extends BridgeSkillsFrame {
  const BridgeSkillsFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsFrame_FailureCopyWith<BridgeSkillsFrame_Failure> get copyWith => _$BridgeSkillsFrame_FailureCopyWithImpl<BridgeSkillsFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeSkillsFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsFrame_FailureCopyWith<$Res> implements $BridgeSkillsFrameCopyWith<$Res> {
  factory $BridgeSkillsFrame_FailureCopyWith(BridgeSkillsFrame_Failure value, $Res Function(BridgeSkillsFrame_Failure) _then) = _$BridgeSkillsFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeSkillsFrame_FailureCopyWithImpl<$Res>
    implements $BridgeSkillsFrame_FailureCopyWith<$Res> {
  _$BridgeSkillsFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeSkillsFrame_Failure _self;
  final $Res Function(BridgeSkillsFrame_Failure) _then;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeSkillsFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeSkillsFrame_Closed extends BridgeSkillsFrame {
  const BridgeSkillsFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillsFrame_ClosedCopyWith<BridgeSkillsFrame_Closed> get copyWith => _$BridgeSkillsFrame_ClosedCopyWithImpl<BridgeSkillsFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillsFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeSkillsFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillsFrame_ClosedCopyWith<$Res> implements $BridgeSkillsFrameCopyWith<$Res> {
  factory $BridgeSkillsFrame_ClosedCopyWith(BridgeSkillsFrame_Closed value, $Res Function(BridgeSkillsFrame_Closed) _then) = _$BridgeSkillsFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeSkillsFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeSkillsFrame_ClosedCopyWith<$Res> {
  _$BridgeSkillsFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeSkillsFrame_Closed _self;
  final $Res Function(BridgeSkillsFrame_Closed) _then;

/// Create a copy of BridgeSkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeSkillsFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
