// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_catalog.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeModelCatalogEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogEventCopyWith<BridgeModelCatalogEvent> get copyWith => _$BridgeModelCatalogEventCopyWithImpl<BridgeModelCatalogEvent>(this as BridgeModelCatalogEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeModelCatalogEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeModelCatalogEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeModelCatalogEvent;
  return 'BridgeModelCatalogEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogEventCopyWith<$Res>  {
  factory $BridgeModelCatalogEventCopyWith(BridgeModelCatalogEvent value, $Res Function(BridgeModelCatalogEvent) _then) = _$BridgeModelCatalogEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeModelCatalogEventCopyWithImpl<$Res>
    implements $BridgeModelCatalogEventCopyWith<$Res> {
  _$BridgeModelCatalogEventCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogEvent _self;
  final $Res Function(BridgeModelCatalogEvent) _then;

/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeModelCatalogEvent].
extension BridgeModelCatalogEventPatterns on BridgeModelCatalogEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeModelCatalogEvent_Baseline value)?  baseline,TResult Function( BridgeModelCatalogEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeModelCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeModelCatalogEvent_Baseline value)  baseline,required TResult Function( BridgeModelCatalogEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline():
return baseline(_that);case BridgeModelCatalogEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeModelCatalogEvent_Baseline value)?  baseline,TResult? Function( BridgeModelCatalogEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeModelCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModelCatalogBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModelCatalogChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModelCatalogEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModelCatalogBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModelCatalogChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModelCatalogEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeModelCatalogBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeModelCatalogChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeModelCatalogEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeModelCatalogEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeModelCatalogEvent_Baseline extends BridgeModelCatalogEvent {
  const BridgeModelCatalogEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeModelCatalogBaseline value;

/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogEvent_BaselineCopyWith<BridgeModelCatalogEvent_Baseline> get copyWith => _$BridgeModelCatalogEvent_BaselineCopyWithImpl<BridgeModelCatalogEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeModelCatalogEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogEvent_BaselineCopyWith<$Res> implements $BridgeModelCatalogEventCopyWith<$Res> {
  factory $BridgeModelCatalogEvent_BaselineCopyWith(BridgeModelCatalogEvent_Baseline value, $Res Function(BridgeModelCatalogEvent_Baseline) _then) = _$BridgeModelCatalogEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeModelCatalogBaseline value
});




}
/// @nodoc
class _$BridgeModelCatalogEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeModelCatalogEvent_BaselineCopyWith<$Res> {
  _$BridgeModelCatalogEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogEvent_Baseline _self;
  final $Res Function(BridgeModelCatalogEvent_Baseline) _then;

/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeModelCatalogEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeModelCatalogBaseline,
  ));
}


}

/// @nodoc


class BridgeModelCatalogEvent_Change extends BridgeModelCatalogEvent {
  const BridgeModelCatalogEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeModelCatalogChange value;

/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogEvent_ChangeCopyWith<BridgeModelCatalogEvent_Change> get copyWith => _$BridgeModelCatalogEvent_ChangeCopyWithImpl<BridgeModelCatalogEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeModelCatalogEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogEvent_ChangeCopyWith<$Res> implements $BridgeModelCatalogEventCopyWith<$Res> {
  factory $BridgeModelCatalogEvent_ChangeCopyWith(BridgeModelCatalogEvent_Change value, $Res Function(BridgeModelCatalogEvent_Change) _then) = _$BridgeModelCatalogEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeModelCatalogChange value
});




}
/// @nodoc
class _$BridgeModelCatalogEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeModelCatalogEvent_ChangeCopyWith<$Res> {
  _$BridgeModelCatalogEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogEvent_Change _self;
  final $Res Function(BridgeModelCatalogEvent_Change) _then;

/// Create a copy of BridgeModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeModelCatalogEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeModelCatalogChange,
  ));
}


}

/// @nodoc
mixin _$BridgeModelCatalogFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeModelCatalogFrame()';
}


}

/// @nodoc
class $BridgeModelCatalogFrameCopyWith<$Res>  {
$BridgeModelCatalogFrameCopyWith(BridgeModelCatalogFrame _, $Res Function(BridgeModelCatalogFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeModelCatalogFrame].
extension BridgeModelCatalogFramePatterns on BridgeModelCatalogFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeModelCatalogFrame_Data value)?  data,TResult Function( BridgeModelCatalogFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeModelCatalogFrame_Failure value)?  failure,TResult Function( BridgeModelCatalogFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data() when data != null:
return data(_that);case BridgeModelCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeModelCatalogFrame_Failure() when failure != null:
return failure(_that);case BridgeModelCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeModelCatalogFrame_Data value)  data,required TResult Function( BridgeModelCatalogFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeModelCatalogFrame_Failure value)  failure,required TResult Function( BridgeModelCatalogFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data():
return data(_that);case BridgeModelCatalogFrame_ResyncRequired():
return resyncRequired(_that);case BridgeModelCatalogFrame_Failure():
return failure(_that);case BridgeModelCatalogFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeModelCatalogFrame_Data value)?  data,TResult? Function( BridgeModelCatalogFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeModelCatalogFrame_Failure value)?  failure,TResult? Function( BridgeModelCatalogFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data() when data != null:
return data(_that);case BridgeModelCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeModelCatalogFrame_Failure() when failure != null:
return failure(_that);case BridgeModelCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeModelCatalogEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeModelCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeModelCatalogFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeModelCatalogFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeModelCatalogEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeModelCatalogFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeModelCatalogFrame_Failure():
return failure(_that.identity,_that.error);case BridgeModelCatalogFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeModelCatalogEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeModelCatalogFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeModelCatalogFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeModelCatalogFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeModelCatalogFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeModelCatalogFrame_Data extends BridgeModelCatalogFrame {
  const BridgeModelCatalogFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeModelCatalogEvent event;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogFrame_DataCopyWith<BridgeModelCatalogFrame_Data> get copyWith => _$BridgeModelCatalogFrame_DataCopyWithImpl<BridgeModelCatalogFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeModelCatalogFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogFrame_DataCopyWith<$Res> implements $BridgeModelCatalogFrameCopyWith<$Res> {
  factory $BridgeModelCatalogFrame_DataCopyWith(BridgeModelCatalogFrame_Data value, $Res Function(BridgeModelCatalogFrame_Data) _then) = _$BridgeModelCatalogFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeModelCatalogEvent event
});


$BridgeModelCatalogEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeModelCatalogFrame_DataCopyWithImpl<$Res>
    implements $BridgeModelCatalogFrame_DataCopyWith<$Res> {
  _$BridgeModelCatalogFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogFrame_Data _self;
  final $Res Function(BridgeModelCatalogFrame_Data) _then;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeModelCatalogFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeModelCatalogEvent,
  ));
}

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeModelCatalogEventCopyWith<$Res> get event {

  return $BridgeModelCatalogEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeModelCatalogFrame_ResyncRequired extends BridgeModelCatalogFrame {
  const BridgeModelCatalogFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogFrame_ResyncRequiredCopyWith<BridgeModelCatalogFrame_ResyncRequired> get copyWith => _$BridgeModelCatalogFrame_ResyncRequiredCopyWithImpl<BridgeModelCatalogFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeModelCatalogFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogFrame_ResyncRequiredCopyWith<$Res> implements $BridgeModelCatalogFrameCopyWith<$Res> {
  factory $BridgeModelCatalogFrame_ResyncRequiredCopyWith(BridgeModelCatalogFrame_ResyncRequired value, $Res Function(BridgeModelCatalogFrame_ResyncRequired) _then) = _$BridgeModelCatalogFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeModelCatalogFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeModelCatalogFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeModelCatalogFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogFrame_ResyncRequired _self;
  final $Res Function(BridgeModelCatalogFrame_ResyncRequired) _then;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeModelCatalogFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeModelCatalogFrame_Failure extends BridgeModelCatalogFrame {
  const BridgeModelCatalogFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogFrame_FailureCopyWith<BridgeModelCatalogFrame_Failure> get copyWith => _$BridgeModelCatalogFrame_FailureCopyWithImpl<BridgeModelCatalogFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeModelCatalogFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogFrame_FailureCopyWith<$Res> implements $BridgeModelCatalogFrameCopyWith<$Res> {
  factory $BridgeModelCatalogFrame_FailureCopyWith(BridgeModelCatalogFrame_Failure value, $Res Function(BridgeModelCatalogFrame_Failure) _then) = _$BridgeModelCatalogFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeModelCatalogFrame_FailureCopyWithImpl<$Res>
    implements $BridgeModelCatalogFrame_FailureCopyWith<$Res> {
  _$BridgeModelCatalogFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogFrame_Failure _self;
  final $Res Function(BridgeModelCatalogFrame_Failure) _then;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeModelCatalogFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeModelCatalogFrame_Closed extends BridgeModelCatalogFrame {
  const BridgeModelCatalogFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelCatalogFrame_ClosedCopyWith<BridgeModelCatalogFrame_Closed> get copyWith => _$BridgeModelCatalogFrame_ClosedCopyWithImpl<BridgeModelCatalogFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelCatalogFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeModelCatalogFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeModelCatalogFrame_ClosedCopyWith<$Res> implements $BridgeModelCatalogFrameCopyWith<$Res> {
  factory $BridgeModelCatalogFrame_ClosedCopyWith(BridgeModelCatalogFrame_Closed value, $Res Function(BridgeModelCatalogFrame_Closed) _then) = _$BridgeModelCatalogFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeModelCatalogFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeModelCatalogFrame_ClosedCopyWith<$Res> {
  _$BridgeModelCatalogFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeModelCatalogFrame_Closed _self;
  final $Res Function(BridgeModelCatalogFrame_Closed) _then;

/// Create a copy of BridgeModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeModelCatalogFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
