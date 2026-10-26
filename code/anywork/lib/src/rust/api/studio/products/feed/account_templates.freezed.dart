// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_templates.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAccountTemplatesEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesEventCopyWith<BridgeAccountTemplatesEvent> get copyWith => _$BridgeAccountTemplatesEventCopyWithImpl<BridgeAccountTemplatesEvent>(this as BridgeAccountTemplatesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAccountTemplatesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAccountTemplatesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAccountTemplatesEvent;
  return 'BridgeAccountTemplatesEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesEventCopyWith<$Res>  {
  factory $BridgeAccountTemplatesEventCopyWith(BridgeAccountTemplatesEvent value, $Res Function(BridgeAccountTemplatesEvent) _then) = _$BridgeAccountTemplatesEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeAccountTemplatesEventCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesEventCopyWith<$Res> {
  _$BridgeAccountTemplatesEventCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesEvent _self;
  final $Res Function(BridgeAccountTemplatesEvent) _then;

/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAccountTemplatesEvent].
extension BridgeAccountTemplatesEventPatterns on BridgeAccountTemplatesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountTemplatesEvent_Baseline value)?  baseline,TResult Function( BridgeAccountTemplatesEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAccountTemplatesEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountTemplatesEvent_Baseline value)  baseline,required TResult Function( BridgeAccountTemplatesEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline():
return baseline(_that);case BridgeAccountTemplatesEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountTemplatesEvent_Baseline value)?  baseline,TResult? Function( BridgeAccountTemplatesEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAccountTemplatesEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountTemplatesBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountTemplatesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountTemplatesEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountTemplatesBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountTemplatesChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountTemplatesEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAccountTemplatesBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAccountTemplatesChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAccountTemplatesEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountTemplatesEvent_Baseline extends BridgeAccountTemplatesEvent {
  const BridgeAccountTemplatesEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAccountTemplatesBaseline value;

/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesEvent_BaselineCopyWith<BridgeAccountTemplatesEvent_Baseline> get copyWith => _$BridgeAccountTemplatesEvent_BaselineCopyWithImpl<BridgeAccountTemplatesEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAccountTemplatesEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesEvent_BaselineCopyWith<$Res> implements $BridgeAccountTemplatesEventCopyWith<$Res> {
  factory $BridgeAccountTemplatesEvent_BaselineCopyWith(BridgeAccountTemplatesEvent_Baseline value, $Res Function(BridgeAccountTemplatesEvent_Baseline) _then) = _$BridgeAccountTemplatesEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAccountTemplatesBaseline value
});




}
/// @nodoc
class _$BridgeAccountTemplatesEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesEvent_BaselineCopyWith<$Res> {
  _$BridgeAccountTemplatesEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesEvent_Baseline _self;
  final $Res Function(BridgeAccountTemplatesEvent_Baseline) _then;

/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAccountTemplatesEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAccountTemplatesBaseline,
  ));
}


}

/// @nodoc


class BridgeAccountTemplatesEvent_Change extends BridgeAccountTemplatesEvent {
  const BridgeAccountTemplatesEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAccountTemplatesChange value;

/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesEvent_ChangeCopyWith<BridgeAccountTemplatesEvent_Change> get copyWith => _$BridgeAccountTemplatesEvent_ChangeCopyWithImpl<BridgeAccountTemplatesEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAccountTemplatesEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesEvent_ChangeCopyWith<$Res> implements $BridgeAccountTemplatesEventCopyWith<$Res> {
  factory $BridgeAccountTemplatesEvent_ChangeCopyWith(BridgeAccountTemplatesEvent_Change value, $Res Function(BridgeAccountTemplatesEvent_Change) _then) = _$BridgeAccountTemplatesEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAccountTemplatesChange value
});




}
/// @nodoc
class _$BridgeAccountTemplatesEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesEvent_ChangeCopyWith<$Res> {
  _$BridgeAccountTemplatesEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesEvent_Change _self;
  final $Res Function(BridgeAccountTemplatesEvent_Change) _then;

/// Create a copy of BridgeAccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAccountTemplatesEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAccountTemplatesChange,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountTemplatesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountTemplatesFrame()';
}


}

/// @nodoc
class $BridgeAccountTemplatesFrameCopyWith<$Res>  {
$BridgeAccountTemplatesFrameCopyWith(BridgeAccountTemplatesFrame _, $Res Function(BridgeAccountTemplatesFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountTemplatesFrame].
extension BridgeAccountTemplatesFramePatterns on BridgeAccountTemplatesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountTemplatesFrame_Data value)?  data,TResult Function( BridgeAccountTemplatesFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAccountTemplatesFrame_Failure value)?  failure,TResult Function( BridgeAccountTemplatesFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data() when data != null:
return data(_that);case BridgeAccountTemplatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAccountTemplatesFrame_Failure() when failure != null:
return failure(_that);case BridgeAccountTemplatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountTemplatesFrame_Data value)  data,required TResult Function( BridgeAccountTemplatesFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAccountTemplatesFrame_Failure value)  failure,required TResult Function( BridgeAccountTemplatesFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data():
return data(_that);case BridgeAccountTemplatesFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAccountTemplatesFrame_Failure():
return failure(_that);case BridgeAccountTemplatesFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountTemplatesFrame_Data value)?  data,TResult? Function( BridgeAccountTemplatesFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAccountTemplatesFrame_Failure value)?  failure,TResult? Function( BridgeAccountTemplatesFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data() when data != null:
return data(_that);case BridgeAccountTemplatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAccountTemplatesFrame_Failure() when failure != null:
return failure(_that);case BridgeAccountTemplatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAccountTemplatesEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAccountTemplatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAccountTemplatesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAccountTemplatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAccountTemplatesEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAccountTemplatesFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAccountTemplatesFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAccountTemplatesFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAccountTemplatesEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAccountTemplatesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAccountTemplatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAccountTemplatesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAccountTemplatesFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountTemplatesFrame_Data extends BridgeAccountTemplatesFrame {
  const BridgeAccountTemplatesFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAccountTemplatesEvent event;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesFrame_DataCopyWith<BridgeAccountTemplatesFrame_Data> get copyWith => _$BridgeAccountTemplatesFrame_DataCopyWithImpl<BridgeAccountTemplatesFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAccountTemplatesFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesFrame_DataCopyWith<$Res> implements $BridgeAccountTemplatesFrameCopyWith<$Res> {
  factory $BridgeAccountTemplatesFrame_DataCopyWith(BridgeAccountTemplatesFrame_Data value, $Res Function(BridgeAccountTemplatesFrame_Data) _then) = _$BridgeAccountTemplatesFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAccountTemplatesEvent event
});


$BridgeAccountTemplatesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAccountTemplatesFrame_DataCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesFrame_DataCopyWith<$Res> {
  _$BridgeAccountTemplatesFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesFrame_Data _self;
  final $Res Function(BridgeAccountTemplatesFrame_Data) _then;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAccountTemplatesFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAccountTemplatesEvent,
  ));
}

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesEventCopyWith<$Res> get event {

  return $BridgeAccountTemplatesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAccountTemplatesFrame_ResyncRequired extends BridgeAccountTemplatesFrame {
  const BridgeAccountTemplatesFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesFrame_ResyncRequiredCopyWith<BridgeAccountTemplatesFrame_ResyncRequired> get copyWith => _$BridgeAccountTemplatesFrame_ResyncRequiredCopyWithImpl<BridgeAccountTemplatesFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAccountTemplatesFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAccountTemplatesFrameCopyWith<$Res> {
  factory $BridgeAccountTemplatesFrame_ResyncRequiredCopyWith(BridgeAccountTemplatesFrame_ResyncRequired value, $Res Function(BridgeAccountTemplatesFrame_ResyncRequired) _then) = _$BridgeAccountTemplatesFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAccountTemplatesFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAccountTemplatesFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesFrame_ResyncRequired _self;
  final $Res Function(BridgeAccountTemplatesFrame_ResyncRequired) _then;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAccountTemplatesFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAccountTemplatesFrame_Failure extends BridgeAccountTemplatesFrame {
  const BridgeAccountTemplatesFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesFrame_FailureCopyWith<BridgeAccountTemplatesFrame_Failure> get copyWith => _$BridgeAccountTemplatesFrame_FailureCopyWithImpl<BridgeAccountTemplatesFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAccountTemplatesFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesFrame_FailureCopyWith<$Res> implements $BridgeAccountTemplatesFrameCopyWith<$Res> {
  factory $BridgeAccountTemplatesFrame_FailureCopyWith(BridgeAccountTemplatesFrame_Failure value, $Res Function(BridgeAccountTemplatesFrame_Failure) _then) = _$BridgeAccountTemplatesFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAccountTemplatesFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesFrame_FailureCopyWith<$Res> {
  _$BridgeAccountTemplatesFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesFrame_Failure _self;
  final $Res Function(BridgeAccountTemplatesFrame_Failure) _then;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAccountTemplatesFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAccountTemplatesFrame_Closed extends BridgeAccountTemplatesFrame {
  const BridgeAccountTemplatesFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTemplatesFrame_ClosedCopyWith<BridgeAccountTemplatesFrame_Closed> get copyWith => _$BridgeAccountTemplatesFrame_ClosedCopyWithImpl<BridgeAccountTemplatesFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTemplatesFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAccountTemplatesFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTemplatesFrame_ClosedCopyWith<$Res> implements $BridgeAccountTemplatesFrameCopyWith<$Res> {
  factory $BridgeAccountTemplatesFrame_ClosedCopyWith(BridgeAccountTemplatesFrame_Closed value, $Res Function(BridgeAccountTemplatesFrame_Closed) _then) = _$BridgeAccountTemplatesFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAccountTemplatesFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAccountTemplatesFrame_ClosedCopyWith<$Res> {
  _$BridgeAccountTemplatesFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAccountTemplatesFrame_Closed _self;
  final $Res Function(BridgeAccountTemplatesFrame_Closed) _then;

/// Create a copy of BridgeAccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAccountTemplatesFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
