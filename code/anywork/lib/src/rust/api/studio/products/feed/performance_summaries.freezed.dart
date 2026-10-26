// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'performance_summaries.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgePerformanceSummariesEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesEventCopyWith<BridgePerformanceSummariesEvent> get copyWith => _$BridgePerformanceSummariesEventCopyWithImpl<BridgePerformanceSummariesEvent>(this as BridgePerformanceSummariesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePerformanceSummariesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgePerformanceSummariesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgePerformanceSummariesEvent;
  return 'BridgePerformanceSummariesEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesEventCopyWith<$Res>  {
  factory $BridgePerformanceSummariesEventCopyWith(BridgePerformanceSummariesEvent value, $Res Function(BridgePerformanceSummariesEvent) _then) = _$BridgePerformanceSummariesEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgePerformanceSummariesEventCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesEventCopyWith<$Res> {
  _$BridgePerformanceSummariesEventCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesEvent _self;
  final $Res Function(BridgePerformanceSummariesEvent) _then;

/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePerformanceSummariesEvent].
extension BridgePerformanceSummariesEventPatterns on BridgePerformanceSummariesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePerformanceSummariesEvent_Baseline value)?  baseline,TResult Function( BridgePerformanceSummariesEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePerformanceSummariesEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePerformanceSummariesEvent_Baseline value)  baseline,required TResult Function( BridgePerformanceSummariesEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline():
return baseline(_that);case BridgePerformanceSummariesEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePerformanceSummariesEvent_Baseline value)?  baseline,TResult? Function( BridgePerformanceSummariesEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePerformanceSummariesEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceSummariesBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceSummariesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceSummariesEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceSummariesBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceSummariesChange value)  change,}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceSummariesEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePerformanceSummariesBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePerformanceSummariesChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePerformanceSummariesEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgePerformanceSummariesEvent_Baseline extends BridgePerformanceSummariesEvent {
  const BridgePerformanceSummariesEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgePerformanceSummariesBaseline value;

/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesEvent_BaselineCopyWith<BridgePerformanceSummariesEvent_Baseline> get copyWith => _$BridgePerformanceSummariesEvent_BaselineCopyWithImpl<BridgePerformanceSummariesEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgePerformanceSummariesEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesEvent_BaselineCopyWith<$Res> implements $BridgePerformanceSummariesEventCopyWith<$Res> {
  factory $BridgePerformanceSummariesEvent_BaselineCopyWith(BridgePerformanceSummariesEvent_Baseline value, $Res Function(BridgePerformanceSummariesEvent_Baseline) _then) = _$BridgePerformanceSummariesEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgePerformanceSummariesBaseline value
});




}
/// @nodoc
class _$BridgePerformanceSummariesEvent_BaselineCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesEvent_BaselineCopyWith<$Res> {
  _$BridgePerformanceSummariesEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesEvent_Baseline _self;
  final $Res Function(BridgePerformanceSummariesEvent_Baseline) _then;

/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgePerformanceSummariesEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePerformanceSummariesBaseline,
  ));
}


}

/// @nodoc


class BridgePerformanceSummariesEvent_Change extends BridgePerformanceSummariesEvent {
  const BridgePerformanceSummariesEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgePerformanceSummariesChange value;

/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesEvent_ChangeCopyWith<BridgePerformanceSummariesEvent_Change> get copyWith => _$BridgePerformanceSummariesEvent_ChangeCopyWithImpl<BridgePerformanceSummariesEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgePerformanceSummariesEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesEvent_ChangeCopyWith<$Res> implements $BridgePerformanceSummariesEventCopyWith<$Res> {
  factory $BridgePerformanceSummariesEvent_ChangeCopyWith(BridgePerformanceSummariesEvent_Change value, $Res Function(BridgePerformanceSummariesEvent_Change) _then) = _$BridgePerformanceSummariesEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgePerformanceSummariesChange value
});




}
/// @nodoc
class _$BridgePerformanceSummariesEvent_ChangeCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesEvent_ChangeCopyWith<$Res> {
  _$BridgePerformanceSummariesEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesEvent_Change _self;
  final $Res Function(BridgePerformanceSummariesEvent_Change) _then;

/// Create a copy of BridgePerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgePerformanceSummariesEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePerformanceSummariesChange,
  ));
}


}

/// @nodoc
mixin _$BridgePerformanceSummariesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePerformanceSummariesFrame()';
}


}

/// @nodoc
class $BridgePerformanceSummariesFrameCopyWith<$Res>  {
$BridgePerformanceSummariesFrameCopyWith(BridgePerformanceSummariesFrame _, $Res Function(BridgePerformanceSummariesFrame) __);
}


/// Adds pattern-matching-related methods to [BridgePerformanceSummariesFrame].
extension BridgePerformanceSummariesFramePatterns on BridgePerformanceSummariesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePerformanceSummariesFrame_Data value)?  data,TResult Function( BridgePerformanceSummariesFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgePerformanceSummariesFrame_Failure value)?  failure,TResult Function( BridgePerformanceSummariesFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data() when data != null:
return data(_that);case BridgePerformanceSummariesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePerformanceSummariesFrame_Failure() when failure != null:
return failure(_that);case BridgePerformanceSummariesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePerformanceSummariesFrame_Data value)  data,required TResult Function( BridgePerformanceSummariesFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgePerformanceSummariesFrame_Failure value)  failure,required TResult Function( BridgePerformanceSummariesFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data():
return data(_that);case BridgePerformanceSummariesFrame_ResyncRequired():
return resyncRequired(_that);case BridgePerformanceSummariesFrame_Failure():
return failure(_that);case BridgePerformanceSummariesFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePerformanceSummariesFrame_Data value)?  data,TResult? Function( BridgePerformanceSummariesFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgePerformanceSummariesFrame_Failure value)?  failure,TResult? Function( BridgePerformanceSummariesFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data() when data != null:
return data(_that);case BridgePerformanceSummariesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePerformanceSummariesFrame_Failure() when failure != null:
return failure(_that);case BridgePerformanceSummariesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgePerformanceSummariesEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePerformanceSummariesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceSummariesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePerformanceSummariesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgePerformanceSummariesEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgePerformanceSummariesFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceSummariesFrame_Failure():
return failure(_that.identity,_that.error);case BridgePerformanceSummariesFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgePerformanceSummariesEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgePerformanceSummariesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePerformanceSummariesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePerformanceSummariesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePerformanceSummariesFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgePerformanceSummariesFrame_Data extends BridgePerformanceSummariesFrame {
  const BridgePerformanceSummariesFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgePerformanceSummariesEvent event;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesFrame_DataCopyWith<BridgePerformanceSummariesFrame_Data> get copyWith => _$BridgePerformanceSummariesFrame_DataCopyWithImpl<BridgePerformanceSummariesFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgePerformanceSummariesFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesFrame_DataCopyWith<$Res> implements $BridgePerformanceSummariesFrameCopyWith<$Res> {
  factory $BridgePerformanceSummariesFrame_DataCopyWith(BridgePerformanceSummariesFrame_Data value, $Res Function(BridgePerformanceSummariesFrame_Data) _then) = _$BridgePerformanceSummariesFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgePerformanceSummariesEvent event
});


$BridgePerformanceSummariesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgePerformanceSummariesFrame_DataCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesFrame_DataCopyWith<$Res> {
  _$BridgePerformanceSummariesFrame_DataCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesFrame_Data _self;
  final $Res Function(BridgePerformanceSummariesFrame_Data) _then;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgePerformanceSummariesFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgePerformanceSummariesEvent,
  ));
}

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesEventCopyWith<$Res> get event {

  return $BridgePerformanceSummariesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgePerformanceSummariesFrame_ResyncRequired extends BridgePerformanceSummariesFrame {
  const BridgePerformanceSummariesFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesFrame_ResyncRequiredCopyWith<BridgePerformanceSummariesFrame_ResyncRequired> get copyWith => _$BridgePerformanceSummariesFrame_ResyncRequiredCopyWithImpl<BridgePerformanceSummariesFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePerformanceSummariesFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesFrame_ResyncRequiredCopyWith<$Res> implements $BridgePerformanceSummariesFrameCopyWith<$Res> {
  factory $BridgePerformanceSummariesFrame_ResyncRequiredCopyWith(BridgePerformanceSummariesFrame_ResyncRequired value, $Res Function(BridgePerformanceSummariesFrame_ResyncRequired) _then) = _$BridgePerformanceSummariesFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgePerformanceSummariesFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgePerformanceSummariesFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesFrame_ResyncRequired _self;
  final $Res Function(BridgePerformanceSummariesFrame_ResyncRequired) _then;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePerformanceSummariesFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgePerformanceSummariesFrame_Failure extends BridgePerformanceSummariesFrame {
  const BridgePerformanceSummariesFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesFrame_FailureCopyWith<BridgePerformanceSummariesFrame_Failure> get copyWith => _$BridgePerformanceSummariesFrame_FailureCopyWithImpl<BridgePerformanceSummariesFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgePerformanceSummariesFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesFrame_FailureCopyWith<$Res> implements $BridgePerformanceSummariesFrameCopyWith<$Res> {
  factory $BridgePerformanceSummariesFrame_FailureCopyWith(BridgePerformanceSummariesFrame_Failure value, $Res Function(BridgePerformanceSummariesFrame_Failure) _then) = _$BridgePerformanceSummariesFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgePerformanceSummariesFrame_FailureCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesFrame_FailureCopyWith<$Res> {
  _$BridgePerformanceSummariesFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesFrame_Failure _self;
  final $Res Function(BridgePerformanceSummariesFrame_Failure) _then;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgePerformanceSummariesFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgePerformanceSummariesFrame_Closed extends BridgePerformanceSummariesFrame {
  const BridgePerformanceSummariesFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePerformanceSummariesFrame_ClosedCopyWith<BridgePerformanceSummariesFrame_Closed> get copyWith => _$BridgePerformanceSummariesFrame_ClosedCopyWithImpl<BridgePerformanceSummariesFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePerformanceSummariesFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePerformanceSummariesFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePerformanceSummariesFrame_ClosedCopyWith<$Res> implements $BridgePerformanceSummariesFrameCopyWith<$Res> {
  factory $BridgePerformanceSummariesFrame_ClosedCopyWith(BridgePerformanceSummariesFrame_Closed value, $Res Function(BridgePerformanceSummariesFrame_Closed) _then) = _$BridgePerformanceSummariesFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgePerformanceSummariesFrame_ClosedCopyWithImpl<$Res>
    implements $BridgePerformanceSummariesFrame_ClosedCopyWith<$Res> {
  _$BridgePerformanceSummariesFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgePerformanceSummariesFrame_Closed _self;
  final $Res Function(BridgePerformanceSummariesFrame_Closed) _then;

/// Create a copy of BridgePerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePerformanceSummariesFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
