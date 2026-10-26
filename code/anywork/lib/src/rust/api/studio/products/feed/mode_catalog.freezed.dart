// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_catalog.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeModeCatalogEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogEventCopyWith<BridgeModeCatalogEvent> get copyWith => _$BridgeModeCatalogEventCopyWithImpl<BridgeModeCatalogEvent>(this as BridgeModeCatalogEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeModeCatalogEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeModeCatalogEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeModeCatalogEvent;
  return 'BridgeModeCatalogEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogEventCopyWith<$Res>  {
  factory $BridgeModeCatalogEventCopyWith(BridgeModeCatalogEvent value, $Res Function(BridgeModeCatalogEvent) _then) = _$BridgeModeCatalogEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeModeCatalogEventCopyWithImpl<$Res>
    implements $BridgeModeCatalogEventCopyWith<$Res> {
  _$BridgeModeCatalogEventCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogEvent _self;
  final $Res Function(BridgeModeCatalogEvent) _then;

/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeModeCatalogEvent].
extension BridgeModeCatalogEventPatterns on BridgeModeCatalogEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeModeCatalogEvent_Baseline value)?  baseline,TResult Function( BridgeModeCatalogEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeModeCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeModeCatalogEvent_Baseline value)  baseline,required TResult Function( BridgeModeCatalogEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline():
return baseline(_that);case BridgeModeCatalogEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeModeCatalogEvent_Baseline value)?  baseline,TResult? Function( BridgeModeCatalogEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeModeCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModeCatalogBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModeCatalogChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModeCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModeCatalogBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModeCatalogChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModeCatalogEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModeCatalogBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModeCatalogChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeModeCatalogEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModeCatalogEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeModeCatalogEvent_Baseline extends BridgeModeCatalogEvent {
  const BridgeModeCatalogEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeModeCatalogBaseline value;

/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogEvent_BaselineCopyWith<BridgeModeCatalogEvent_Baseline> get copyWith => _$BridgeModeCatalogEvent_BaselineCopyWithImpl<BridgeModeCatalogEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeModeCatalogEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogEvent_BaselineCopyWith<$Res> implements $BridgeModeCatalogEventCopyWith<$Res> {
  factory $BridgeModeCatalogEvent_BaselineCopyWith(BridgeModeCatalogEvent_Baseline value, $Res Function(BridgeModeCatalogEvent_Baseline) _then) = _$BridgeModeCatalogEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeModeCatalogBaseline value
});




}
/// @nodoc
class _$BridgeModeCatalogEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeModeCatalogEvent_BaselineCopyWith<$Res> {
  _$BridgeModeCatalogEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogEvent_Baseline _self;
  final $Res Function(BridgeModeCatalogEvent_Baseline) _then;

/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeModeCatalogEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeModeCatalogBaseline,
  ));
}


}

/// @nodoc


class BridgeModeCatalogEvent_Change extends BridgeModeCatalogEvent {
  const BridgeModeCatalogEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeModeCatalogChange value;

/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogEvent_ChangeCopyWith<BridgeModeCatalogEvent_Change> get copyWith => _$BridgeModeCatalogEvent_ChangeCopyWithImpl<BridgeModeCatalogEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeModeCatalogEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogEvent_ChangeCopyWith<$Res> implements $BridgeModeCatalogEventCopyWith<$Res> {
  factory $BridgeModeCatalogEvent_ChangeCopyWith(BridgeModeCatalogEvent_Change value, $Res Function(BridgeModeCatalogEvent_Change) _then) = _$BridgeModeCatalogEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeModeCatalogChange value
});




}
/// @nodoc
class _$BridgeModeCatalogEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeModeCatalogEvent_ChangeCopyWith<$Res> {
  _$BridgeModeCatalogEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogEvent_Change _self;
  final $Res Function(BridgeModeCatalogEvent_Change) _then;

/// Create a copy of BridgeModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeModeCatalogEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeModeCatalogChange,
  ));
}


}

/// @nodoc
mixin _$BridgeModeCatalogFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeModeCatalogFrame()';
}


}

/// @nodoc
class $BridgeModeCatalogFrameCopyWith<$Res>  {
$BridgeModeCatalogFrameCopyWith(BridgeModeCatalogFrame _, $Res Function(BridgeModeCatalogFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeModeCatalogFrame].
extension BridgeModeCatalogFramePatterns on BridgeModeCatalogFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeModeCatalogFrame_Data value)?  data,TResult Function( BridgeModeCatalogFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeModeCatalogFrame_Failure value)?  failure,TResult Function( BridgeModeCatalogFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data() when data != null:
return data(_that);case BridgeModeCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeModeCatalogFrame_Failure() when failure != null:
return failure(_that);case BridgeModeCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeModeCatalogFrame_Data value)  data,required TResult Function( BridgeModeCatalogFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeModeCatalogFrame_Failure value)  failure,required TResult Function( BridgeModeCatalogFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data():
return data(_that);case BridgeModeCatalogFrame_ResyncRequired():
return resyncRequired(_that);case BridgeModeCatalogFrame_Failure():
return failure(_that);case BridgeModeCatalogFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeModeCatalogFrame_Data value)?  data,TResult? Function( BridgeModeCatalogFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeModeCatalogFrame_Failure value)?  failure,TResult? Function( BridgeModeCatalogFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data() when data != null:
return data(_that);case BridgeModeCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeModeCatalogFrame_Failure() when failure != null:
return failure(_that);case BridgeModeCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeModeCatalogEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeModeCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeModeCatalogFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeModeCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeModeCatalogEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeModeCatalogFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeModeCatalogFrame_Failure():
return failure(_that.identity,_that.error);case BridgeModeCatalogFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeModeCatalogEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeModeCatalogFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeModeCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeModeCatalogFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeModeCatalogFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeModeCatalogFrame_Data extends BridgeModeCatalogFrame {
  const BridgeModeCatalogFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeModeCatalogEvent event;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogFrame_DataCopyWith<BridgeModeCatalogFrame_Data> get copyWith => _$BridgeModeCatalogFrame_DataCopyWithImpl<BridgeModeCatalogFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeModeCatalogFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogFrame_DataCopyWith<$Res> implements $BridgeModeCatalogFrameCopyWith<$Res> {
  factory $BridgeModeCatalogFrame_DataCopyWith(BridgeModeCatalogFrame_Data value, $Res Function(BridgeModeCatalogFrame_Data) _then) = _$BridgeModeCatalogFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeModeCatalogEvent event
});


$BridgeModeCatalogEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeModeCatalogFrame_DataCopyWithImpl<$Res>
    implements $BridgeModeCatalogFrame_DataCopyWith<$Res> {
  _$BridgeModeCatalogFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogFrame_Data _self;
  final $Res Function(BridgeModeCatalogFrame_Data) _then;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeModeCatalogFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeModeCatalogEvent,
  ));
}

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeModeCatalogEventCopyWith<$Res> get event {

  return $BridgeModeCatalogEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeModeCatalogFrame_ResyncRequired extends BridgeModeCatalogFrame {
  const BridgeModeCatalogFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogFrame_ResyncRequiredCopyWith<BridgeModeCatalogFrame_ResyncRequired> get copyWith => _$BridgeModeCatalogFrame_ResyncRequiredCopyWithImpl<BridgeModeCatalogFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeModeCatalogFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogFrame_ResyncRequiredCopyWith<$Res> implements $BridgeModeCatalogFrameCopyWith<$Res> {
  factory $BridgeModeCatalogFrame_ResyncRequiredCopyWith(BridgeModeCatalogFrame_ResyncRequired value, $Res Function(BridgeModeCatalogFrame_ResyncRequired) _then) = _$BridgeModeCatalogFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeModeCatalogFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeModeCatalogFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeModeCatalogFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogFrame_ResyncRequired _self;
  final $Res Function(BridgeModeCatalogFrame_ResyncRequired) _then;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeModeCatalogFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeModeCatalogFrame_Failure extends BridgeModeCatalogFrame {
  const BridgeModeCatalogFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogFrame_FailureCopyWith<BridgeModeCatalogFrame_Failure> get copyWith => _$BridgeModeCatalogFrame_FailureCopyWithImpl<BridgeModeCatalogFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeModeCatalogFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogFrame_FailureCopyWith<$Res> implements $BridgeModeCatalogFrameCopyWith<$Res> {
  factory $BridgeModeCatalogFrame_FailureCopyWith(BridgeModeCatalogFrame_Failure value, $Res Function(BridgeModeCatalogFrame_Failure) _then) = _$BridgeModeCatalogFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeModeCatalogFrame_FailureCopyWithImpl<$Res>
    implements $BridgeModeCatalogFrame_FailureCopyWith<$Res> {
  _$BridgeModeCatalogFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogFrame_Failure _self;
  final $Res Function(BridgeModeCatalogFrame_Failure) _then;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeModeCatalogFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeModeCatalogFrame_Closed extends BridgeModeCatalogFrame {
  const BridgeModeCatalogFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModeCatalogFrame_ClosedCopyWith<BridgeModeCatalogFrame_Closed> get copyWith => _$BridgeModeCatalogFrame_ClosedCopyWithImpl<BridgeModeCatalogFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModeCatalogFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeModeCatalogFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeModeCatalogFrame_ClosedCopyWith<$Res> implements $BridgeModeCatalogFrameCopyWith<$Res> {
  factory $BridgeModeCatalogFrame_ClosedCopyWith(BridgeModeCatalogFrame_Closed value, $Res Function(BridgeModeCatalogFrame_Closed) _then) = _$BridgeModeCatalogFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeModeCatalogFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeModeCatalogFrame_ClosedCopyWith<$Res> {
  _$BridgeModeCatalogFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeModeCatalogFrame_Closed _self;
  final $Res Function(BridgeModeCatalogFrame_Closed) _then;

/// Create a copy of BridgeModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeModeCatalogFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
