// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeThreadDirectoryEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryEventCopyWith<BridgeThreadDirectoryEvent> get copyWith => _$BridgeThreadDirectoryEventCopyWithImpl<BridgeThreadDirectoryEvent>(this as BridgeThreadDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeThreadDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeThreadDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeThreadDirectoryEvent;
  return 'BridgeThreadDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryEventCopyWith<$Res>  {
  factory $BridgeThreadDirectoryEventCopyWith(BridgeThreadDirectoryEvent value, $Res Function(BridgeThreadDirectoryEvent) _then) = _$BridgeThreadDirectoryEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeThreadDirectoryEventCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryEventCopyWith<$Res> {
  _$BridgeThreadDirectoryEventCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryEvent _self;
  final $Res Function(BridgeThreadDirectoryEvent) _then;

/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeThreadDirectoryEvent].
extension BridgeThreadDirectoryEventPatterns on BridgeThreadDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadDirectoryEvent_Baseline value)?  baseline,TResult Function( BridgeThreadDirectoryEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeThreadDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadDirectoryEvent_Baseline value)  baseline,required TResult Function( BridgeThreadDirectoryEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline():
return baseline(_that);case BridgeThreadDirectoryEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadDirectoryEvent_Baseline value)?  baseline,TResult? Function( BridgeThreadDirectoryEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeThreadDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeThreadDirectoryBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeThreadDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeThreadDirectoryBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeThreadDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadDirectoryEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeThreadDirectoryBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeThreadDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadDirectoryEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadDirectoryEvent_Baseline extends BridgeThreadDirectoryEvent {
  const BridgeThreadDirectoryEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeThreadDirectoryBaseline value;

/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryEvent_BaselineCopyWith<BridgeThreadDirectoryEvent_Baseline> get copyWith => _$BridgeThreadDirectoryEvent_BaselineCopyWithImpl<BridgeThreadDirectoryEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeThreadDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryEvent_BaselineCopyWith<$Res> implements $BridgeThreadDirectoryEventCopyWith<$Res> {
  factory $BridgeThreadDirectoryEvent_BaselineCopyWith(BridgeThreadDirectoryEvent_Baseline value, $Res Function(BridgeThreadDirectoryEvent_Baseline) _then) = _$BridgeThreadDirectoryEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeThreadDirectoryBaseline value
});




}
/// @nodoc
class _$BridgeThreadDirectoryEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryEvent_BaselineCopyWith<$Res> {
  _$BridgeThreadDirectoryEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryEvent_Baseline _self;
  final $Res Function(BridgeThreadDirectoryEvent_Baseline) _then;

/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeThreadDirectoryEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeThreadDirectoryBaseline,
  ));
}


}

/// @nodoc


class BridgeThreadDirectoryEvent_Change extends BridgeThreadDirectoryEvent {
  const BridgeThreadDirectoryEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeThreadDirectoryChange value;

/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryEvent_ChangeCopyWith<BridgeThreadDirectoryEvent_Change> get copyWith => _$BridgeThreadDirectoryEvent_ChangeCopyWithImpl<BridgeThreadDirectoryEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeThreadDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryEvent_ChangeCopyWith<$Res> implements $BridgeThreadDirectoryEventCopyWith<$Res> {
  factory $BridgeThreadDirectoryEvent_ChangeCopyWith(BridgeThreadDirectoryEvent_Change value, $Res Function(BridgeThreadDirectoryEvent_Change) _then) = _$BridgeThreadDirectoryEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeThreadDirectoryChange value
});




}
/// @nodoc
class _$BridgeThreadDirectoryEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryEvent_ChangeCopyWith<$Res> {
  _$BridgeThreadDirectoryEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryEvent_Change _self;
  final $Res Function(BridgeThreadDirectoryEvent_Change) _then;

/// Create a copy of BridgeThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeThreadDirectoryEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeThreadDirectoryChange,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadDirectoryFrame()';
}


}

/// @nodoc
class $BridgeThreadDirectoryFrameCopyWith<$Res>  {
$BridgeThreadDirectoryFrameCopyWith(BridgeThreadDirectoryFrame _, $Res Function(BridgeThreadDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadDirectoryFrame].
extension BridgeThreadDirectoryFramePatterns on BridgeThreadDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadDirectoryFrame_Data value)?  data,TResult Function( BridgeThreadDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeThreadDirectoryFrame_Failure value)?  failure,TResult Function( BridgeThreadDirectoryFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data() when data != null:
return data(_that);case BridgeThreadDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeThreadDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeThreadDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadDirectoryFrame_Data value)  data,required TResult Function( BridgeThreadDirectoryFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeThreadDirectoryFrame_Failure value)  failure,required TResult Function( BridgeThreadDirectoryFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data():
return data(_that);case BridgeThreadDirectoryFrame_ResyncRequired():
return resyncRequired(_that);case BridgeThreadDirectoryFrame_Failure():
return failure(_that);case BridgeThreadDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadDirectoryFrame_Data value)?  data,TResult? Function( BridgeThreadDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeThreadDirectoryFrame_Failure value)?  failure,TResult? Function( BridgeThreadDirectoryFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data() when data != null:
return data(_that);case BridgeThreadDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeThreadDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeThreadDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeThreadDirectoryEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeThreadDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeThreadDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeThreadDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeThreadDirectoryEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeThreadDirectoryFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeThreadDirectoryFrame_Failure():
return failure(_that.identity,_that.error);case BridgeThreadDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeThreadDirectoryEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeThreadDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeThreadDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeThreadDirectoryFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadDirectoryFrame_Data extends BridgeThreadDirectoryFrame {
  const BridgeThreadDirectoryFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeThreadDirectoryEvent event;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryFrame_DataCopyWith<BridgeThreadDirectoryFrame_Data> get copyWith => _$BridgeThreadDirectoryFrame_DataCopyWithImpl<BridgeThreadDirectoryFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeThreadDirectoryFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryFrame_DataCopyWith<$Res> implements $BridgeThreadDirectoryFrameCopyWith<$Res> {
  factory $BridgeThreadDirectoryFrame_DataCopyWith(BridgeThreadDirectoryFrame_Data value, $Res Function(BridgeThreadDirectoryFrame_Data) _then) = _$BridgeThreadDirectoryFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeThreadDirectoryEvent event
});


$BridgeThreadDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeThreadDirectoryFrame_DataCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryFrame_DataCopyWith<$Res> {
  _$BridgeThreadDirectoryFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryFrame_Data _self;
  final $Res Function(BridgeThreadDirectoryFrame_Data) _then;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeThreadDirectoryFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeThreadDirectoryEvent,
  ));
}

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryEventCopyWith<$Res> get event {

  return $BridgeThreadDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeThreadDirectoryFrame_ResyncRequired extends BridgeThreadDirectoryFrame {
  const BridgeThreadDirectoryFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryFrame_ResyncRequiredCopyWith<BridgeThreadDirectoryFrame_ResyncRequired> get copyWith => _$BridgeThreadDirectoryFrame_ResyncRequiredCopyWithImpl<BridgeThreadDirectoryFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeThreadDirectoryFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryFrame_ResyncRequiredCopyWith<$Res> implements $BridgeThreadDirectoryFrameCopyWith<$Res> {
  factory $BridgeThreadDirectoryFrame_ResyncRequiredCopyWith(BridgeThreadDirectoryFrame_ResyncRequired value, $Res Function(BridgeThreadDirectoryFrame_ResyncRequired) _then) = _$BridgeThreadDirectoryFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeThreadDirectoryFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeThreadDirectoryFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryFrame_ResyncRequired _self;
  final $Res Function(BridgeThreadDirectoryFrame_ResyncRequired) _then;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeThreadDirectoryFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeThreadDirectoryFrame_Failure extends BridgeThreadDirectoryFrame {
  const BridgeThreadDirectoryFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryFrame_FailureCopyWith<BridgeThreadDirectoryFrame_Failure> get copyWith => _$BridgeThreadDirectoryFrame_FailureCopyWithImpl<BridgeThreadDirectoryFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeThreadDirectoryFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryFrame_FailureCopyWith<$Res> implements $BridgeThreadDirectoryFrameCopyWith<$Res> {
  factory $BridgeThreadDirectoryFrame_FailureCopyWith(BridgeThreadDirectoryFrame_Failure value, $Res Function(BridgeThreadDirectoryFrame_Failure) _then) = _$BridgeThreadDirectoryFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeThreadDirectoryFrame_FailureCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryFrame_FailureCopyWith<$Res> {
  _$BridgeThreadDirectoryFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryFrame_Failure _self;
  final $Res Function(BridgeThreadDirectoryFrame_Failure) _then;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeThreadDirectoryFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeThreadDirectoryFrame_Closed extends BridgeThreadDirectoryFrame {
  const BridgeThreadDirectoryFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryFrame_ClosedCopyWith<BridgeThreadDirectoryFrame_Closed> get copyWith => _$BridgeThreadDirectoryFrame_ClosedCopyWithImpl<BridgeThreadDirectoryFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeThreadDirectoryFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryFrame_ClosedCopyWith<$Res> implements $BridgeThreadDirectoryFrameCopyWith<$Res> {
  factory $BridgeThreadDirectoryFrame_ClosedCopyWith(BridgeThreadDirectoryFrame_Closed value, $Res Function(BridgeThreadDirectoryFrame_Closed) _then) = _$BridgeThreadDirectoryFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeThreadDirectoryFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryFrame_ClosedCopyWith<$Res> {
  _$BridgeThreadDirectoryFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryFrame_Closed _self;
  final $Res Function(BridgeThreadDirectoryFrame_Closed) _then;

/// Create a copy of BridgeThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeThreadDirectoryFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
