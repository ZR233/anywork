// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeProjectDirectoryEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryEventCopyWith<BridgeProjectDirectoryEvent> get copyWith => _$BridgeProjectDirectoryEventCopyWithImpl<BridgeProjectDirectoryEvent>(this as BridgeProjectDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeProjectDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeProjectDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeProjectDirectoryEvent;
  return 'BridgeProjectDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryEventCopyWith<$Res>  {
  factory $BridgeProjectDirectoryEventCopyWith(BridgeProjectDirectoryEvent value, $Res Function(BridgeProjectDirectoryEvent) _then) = _$BridgeProjectDirectoryEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeProjectDirectoryEventCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryEventCopyWith<$Res> {
  _$BridgeProjectDirectoryEventCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryEvent _self;
  final $Res Function(BridgeProjectDirectoryEvent) _then;

/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeProjectDirectoryEvent].
extension BridgeProjectDirectoryEventPatterns on BridgeProjectDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProjectDirectoryEvent_Baseline value)?  baseline,TResult Function( BridgeProjectDirectoryEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeProjectDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProjectDirectoryEvent_Baseline value)  baseline,required TResult Function( BridgeProjectDirectoryEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline():
return baseline(_that);case BridgeProjectDirectoryEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProjectDirectoryEvent_Baseline value)?  baseline,TResult? Function( BridgeProjectDirectoryEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeProjectDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeProjectDirectoryBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeProjectDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeProjectDirectoryEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeProjectDirectoryBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeProjectDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeProjectDirectoryEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeProjectDirectoryBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeProjectDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeProjectDirectoryEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProjectDirectoryEvent_Baseline extends BridgeProjectDirectoryEvent {
  const BridgeProjectDirectoryEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeProjectDirectoryBaseline value;

/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryEvent_BaselineCopyWith<BridgeProjectDirectoryEvent_Baseline> get copyWith => _$BridgeProjectDirectoryEvent_BaselineCopyWithImpl<BridgeProjectDirectoryEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeProjectDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryEvent_BaselineCopyWith<$Res> implements $BridgeProjectDirectoryEventCopyWith<$Res> {
  factory $BridgeProjectDirectoryEvent_BaselineCopyWith(BridgeProjectDirectoryEvent_Baseline value, $Res Function(BridgeProjectDirectoryEvent_Baseline) _then) = _$BridgeProjectDirectoryEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeProjectDirectoryBaseline value
});




}
/// @nodoc
class _$BridgeProjectDirectoryEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryEvent_BaselineCopyWith<$Res> {
  _$BridgeProjectDirectoryEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryEvent_Baseline _self;
  final $Res Function(BridgeProjectDirectoryEvent_Baseline) _then;

/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeProjectDirectoryEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeProjectDirectoryBaseline,
  ));
}


}

/// @nodoc


class BridgeProjectDirectoryEvent_Change extends BridgeProjectDirectoryEvent {
  const BridgeProjectDirectoryEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeProjectDirectoryChange value;

/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryEvent_ChangeCopyWith<BridgeProjectDirectoryEvent_Change> get copyWith => _$BridgeProjectDirectoryEvent_ChangeCopyWithImpl<BridgeProjectDirectoryEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeProjectDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryEvent_ChangeCopyWith<$Res> implements $BridgeProjectDirectoryEventCopyWith<$Res> {
  factory $BridgeProjectDirectoryEvent_ChangeCopyWith(BridgeProjectDirectoryEvent_Change value, $Res Function(BridgeProjectDirectoryEvent_Change) _then) = _$BridgeProjectDirectoryEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeProjectDirectoryChange value
});




}
/// @nodoc
class _$BridgeProjectDirectoryEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryEvent_ChangeCopyWith<$Res> {
  _$BridgeProjectDirectoryEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryEvent_Change _self;
  final $Res Function(BridgeProjectDirectoryEvent_Change) _then;

/// Create a copy of BridgeProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeProjectDirectoryEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeProjectDirectoryChange,
  ));
}


}

/// @nodoc
mixin _$BridgeProjectDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeProjectDirectoryFrame()';
}


}

/// @nodoc
class $BridgeProjectDirectoryFrameCopyWith<$Res>  {
$BridgeProjectDirectoryFrameCopyWith(BridgeProjectDirectoryFrame _, $Res Function(BridgeProjectDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeProjectDirectoryFrame].
extension BridgeProjectDirectoryFramePatterns on BridgeProjectDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProjectDirectoryFrame_Data value)?  data,TResult Function( BridgeProjectDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeProjectDirectoryFrame_Failure value)?  failure,TResult Function( BridgeProjectDirectoryFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data() when data != null:
return data(_that);case BridgeProjectDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeProjectDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeProjectDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProjectDirectoryFrame_Data value)  data,required TResult Function( BridgeProjectDirectoryFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeProjectDirectoryFrame_Failure value)  failure,required TResult Function( BridgeProjectDirectoryFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data():
return data(_that);case BridgeProjectDirectoryFrame_ResyncRequired():
return resyncRequired(_that);case BridgeProjectDirectoryFrame_Failure():
return failure(_that);case BridgeProjectDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProjectDirectoryFrame_Data value)?  data,TResult? Function( BridgeProjectDirectoryFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeProjectDirectoryFrame_Failure value)?  failure,TResult? Function( BridgeProjectDirectoryFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data() when data != null:
return data(_that);case BridgeProjectDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeProjectDirectoryFrame_Failure() when failure != null:
return failure(_that);case BridgeProjectDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeProjectDirectoryEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeProjectDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeProjectDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeProjectDirectoryFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeProjectDirectoryEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeProjectDirectoryFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeProjectDirectoryFrame_Failure():
return failure(_that.identity,_that.error);case BridgeProjectDirectoryFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeProjectDirectoryEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeProjectDirectoryFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeProjectDirectoryFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeProjectDirectoryFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeProjectDirectoryFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProjectDirectoryFrame_Data extends BridgeProjectDirectoryFrame {
  const BridgeProjectDirectoryFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeProjectDirectoryEvent event;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryFrame_DataCopyWith<BridgeProjectDirectoryFrame_Data> get copyWith => _$BridgeProjectDirectoryFrame_DataCopyWithImpl<BridgeProjectDirectoryFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeProjectDirectoryFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryFrame_DataCopyWith<$Res> implements $BridgeProjectDirectoryFrameCopyWith<$Res> {
  factory $BridgeProjectDirectoryFrame_DataCopyWith(BridgeProjectDirectoryFrame_Data value, $Res Function(BridgeProjectDirectoryFrame_Data) _then) = _$BridgeProjectDirectoryFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeProjectDirectoryEvent event
});


$BridgeProjectDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeProjectDirectoryFrame_DataCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryFrame_DataCopyWith<$Res> {
  _$BridgeProjectDirectoryFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryFrame_Data _self;
  final $Res Function(BridgeProjectDirectoryFrame_Data) _then;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeProjectDirectoryFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeProjectDirectoryEvent,
  ));
}

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryEventCopyWith<$Res> get event {

  return $BridgeProjectDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeProjectDirectoryFrame_ResyncRequired extends BridgeProjectDirectoryFrame {
  const BridgeProjectDirectoryFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryFrame_ResyncRequiredCopyWith<BridgeProjectDirectoryFrame_ResyncRequired> get copyWith => _$BridgeProjectDirectoryFrame_ResyncRequiredCopyWithImpl<BridgeProjectDirectoryFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeProjectDirectoryFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryFrame_ResyncRequiredCopyWith<$Res> implements $BridgeProjectDirectoryFrameCopyWith<$Res> {
  factory $BridgeProjectDirectoryFrame_ResyncRequiredCopyWith(BridgeProjectDirectoryFrame_ResyncRequired value, $Res Function(BridgeProjectDirectoryFrame_ResyncRequired) _then) = _$BridgeProjectDirectoryFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeProjectDirectoryFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeProjectDirectoryFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryFrame_ResyncRequired _self;
  final $Res Function(BridgeProjectDirectoryFrame_ResyncRequired) _then;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeProjectDirectoryFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeProjectDirectoryFrame_Failure extends BridgeProjectDirectoryFrame {
  const BridgeProjectDirectoryFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryFrame_FailureCopyWith<BridgeProjectDirectoryFrame_Failure> get copyWith => _$BridgeProjectDirectoryFrame_FailureCopyWithImpl<BridgeProjectDirectoryFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeProjectDirectoryFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryFrame_FailureCopyWith<$Res> implements $BridgeProjectDirectoryFrameCopyWith<$Res> {
  factory $BridgeProjectDirectoryFrame_FailureCopyWith(BridgeProjectDirectoryFrame_Failure value, $Res Function(BridgeProjectDirectoryFrame_Failure) _then) = _$BridgeProjectDirectoryFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeProjectDirectoryFrame_FailureCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryFrame_FailureCopyWith<$Res> {
  _$BridgeProjectDirectoryFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryFrame_Failure _self;
  final $Res Function(BridgeProjectDirectoryFrame_Failure) _then;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeProjectDirectoryFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeProjectDirectoryFrame_Closed extends BridgeProjectDirectoryFrame {
  const BridgeProjectDirectoryFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProjectDirectoryFrame_ClosedCopyWith<BridgeProjectDirectoryFrame_Closed> get copyWith => _$BridgeProjectDirectoryFrame_ClosedCopyWithImpl<BridgeProjectDirectoryFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProjectDirectoryFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeProjectDirectoryFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeProjectDirectoryFrame_ClosedCopyWith<$Res> implements $BridgeProjectDirectoryFrameCopyWith<$Res> {
  factory $BridgeProjectDirectoryFrame_ClosedCopyWith(BridgeProjectDirectoryFrame_Closed value, $Res Function(BridgeProjectDirectoryFrame_Closed) _then) = _$BridgeProjectDirectoryFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeProjectDirectoryFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeProjectDirectoryFrame_ClosedCopyWith<$Res> {
  _$BridgeProjectDirectoryFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeProjectDirectoryFrame_Closed _self;
  final $Res Function(BridgeProjectDirectoryFrame_Closed) _then;

/// Create a copy of BridgeProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeProjectDirectoryFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
