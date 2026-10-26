// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeLspEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspEventCopyWith<BridgeLspEvent> get copyWith => _$BridgeLspEventCopyWithImpl<BridgeLspEvent>(this as BridgeLspEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeLspEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeLspEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeLspEvent;
  return 'BridgeLspEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeLspEventCopyWith<$Res>  {
  factory $BridgeLspEventCopyWith(BridgeLspEvent value, $Res Function(BridgeLspEvent) _then) = _$BridgeLspEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeLspEventCopyWithImpl<$Res>
    implements $BridgeLspEventCopyWith<$Res> {
  _$BridgeLspEventCopyWithImpl(this._self, this._then);

  final BridgeLspEvent _self;
  final $Res Function(BridgeLspEvent) _then;

/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeLspEvent].
extension BridgeLspEventPatterns on BridgeLspEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspEvent_Baseline value)?  baseline,TResult Function( BridgeLspEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeLspEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspEvent_Baseline value)  baseline,required TResult Function( BridgeLspEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline():
return baseline(_that);case BridgeLspEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspEvent_Baseline value)?  baseline,TResult? Function( BridgeLspEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeLspEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeLspBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeLspChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeLspEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeLspBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeLspChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeLspEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeLspBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeLspChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeLspEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeLspEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspEvent_Baseline extends BridgeLspEvent {
  const BridgeLspEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeLspBaseline value;

/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspEvent_BaselineCopyWith<BridgeLspEvent_Baseline> get copyWith => _$BridgeLspEvent_BaselineCopyWithImpl<BridgeLspEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeLspEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeLspEvent_BaselineCopyWith<$Res> implements $BridgeLspEventCopyWith<$Res> {
  factory $BridgeLspEvent_BaselineCopyWith(BridgeLspEvent_Baseline value, $Res Function(BridgeLspEvent_Baseline) _then) = _$BridgeLspEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeLspBaseline value
});




}
/// @nodoc
class _$BridgeLspEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeLspEvent_BaselineCopyWith<$Res> {
  _$BridgeLspEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeLspEvent_Baseline _self;
  final $Res Function(BridgeLspEvent_Baseline) _then;

/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeLspEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeLspBaseline,
  ));
}


}

/// @nodoc


class BridgeLspEvent_Change extends BridgeLspEvent {
  const BridgeLspEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeLspChange value;

/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspEvent_ChangeCopyWith<BridgeLspEvent_Change> get copyWith => _$BridgeLspEvent_ChangeCopyWithImpl<BridgeLspEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeLspEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeLspEvent_ChangeCopyWith<$Res> implements $BridgeLspEventCopyWith<$Res> {
  factory $BridgeLspEvent_ChangeCopyWith(BridgeLspEvent_Change value, $Res Function(BridgeLspEvent_Change) _then) = _$BridgeLspEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeLspChange value
});




}
/// @nodoc
class _$BridgeLspEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeLspEvent_ChangeCopyWith<$Res> {
  _$BridgeLspEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeLspEvent_Change _self;
  final $Res Function(BridgeLspEvent_Change) _then;

/// Create a copy of BridgeLspEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeLspEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeLspChange,
  ));
}


}

/// @nodoc
mixin _$BridgeLspFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspFrame()';
}


}

/// @nodoc
class $BridgeLspFrameCopyWith<$Res>  {
$BridgeLspFrameCopyWith(BridgeLspFrame _, $Res Function(BridgeLspFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeLspFrame].
extension BridgeLspFramePatterns on BridgeLspFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspFrame_Data value)?  data,TResult Function( BridgeLspFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeLspFrame_Failure value)?  failure,TResult Function( BridgeLspFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspFrame_Data() when data != null:
return data(_that);case BridgeLspFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeLspFrame_Failure() when failure != null:
return failure(_that);case BridgeLspFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspFrame_Data value)  data,required TResult Function( BridgeLspFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeLspFrame_Failure value)  failure,required TResult Function( BridgeLspFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeLspFrame_Data():
return data(_that);case BridgeLspFrame_ResyncRequired():
return resyncRequired(_that);case BridgeLspFrame_Failure():
return failure(_that);case BridgeLspFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspFrame_Data value)?  data,TResult? Function( BridgeLspFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeLspFrame_Failure value)?  failure,TResult? Function( BridgeLspFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeLspFrame_Data() when data != null:
return data(_that);case BridgeLspFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeLspFrame_Failure() when failure != null:
return failure(_that);case BridgeLspFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeLspEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeLspFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeLspFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeLspFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeLspEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeLspFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeLspFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeLspFrame_Failure():
return failure(_that.identity,_that.error);case BridgeLspFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeLspEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeLspFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeLspFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeLspFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeLspFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspFrame_Data extends BridgeLspFrame {
  const BridgeLspFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeLspEvent event;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspFrame_DataCopyWith<BridgeLspFrame_Data> get copyWith => _$BridgeLspFrame_DataCopyWithImpl<BridgeLspFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeLspFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeLspFrame_DataCopyWith<$Res> implements $BridgeLspFrameCopyWith<$Res> {
  factory $BridgeLspFrame_DataCopyWith(BridgeLspFrame_Data value, $Res Function(BridgeLspFrame_Data) _then) = _$BridgeLspFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeLspEvent event
});


$BridgeLspEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeLspFrame_DataCopyWithImpl<$Res>
    implements $BridgeLspFrame_DataCopyWith<$Res> {
  _$BridgeLspFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeLspFrame_Data _self;
  final $Res Function(BridgeLspFrame_Data) _then;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeLspFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeLspEvent,
  ));
}

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeLspEventCopyWith<$Res> get event {

  return $BridgeLspEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeLspFrame_ResyncRequired extends BridgeLspFrame {
  const BridgeLspFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspFrame_ResyncRequiredCopyWith<BridgeLspFrame_ResyncRequired> get copyWith => _$BridgeLspFrame_ResyncRequiredCopyWithImpl<BridgeLspFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeLspFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeLspFrame_ResyncRequiredCopyWith<$Res> implements $BridgeLspFrameCopyWith<$Res> {
  factory $BridgeLspFrame_ResyncRequiredCopyWith(BridgeLspFrame_ResyncRequired value, $Res Function(BridgeLspFrame_ResyncRequired) _then) = _$BridgeLspFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeLspFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeLspFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeLspFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeLspFrame_ResyncRequired _self;
  final $Res Function(BridgeLspFrame_ResyncRequired) _then;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeLspFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeLspFrame_Failure extends BridgeLspFrame {
  const BridgeLspFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspFrame_FailureCopyWith<BridgeLspFrame_Failure> get copyWith => _$BridgeLspFrame_FailureCopyWithImpl<BridgeLspFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeLspFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeLspFrame_FailureCopyWith<$Res> implements $BridgeLspFrameCopyWith<$Res> {
  factory $BridgeLspFrame_FailureCopyWith(BridgeLspFrame_Failure value, $Res Function(BridgeLspFrame_Failure) _then) = _$BridgeLspFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeLspFrame_FailureCopyWithImpl<$Res>
    implements $BridgeLspFrame_FailureCopyWith<$Res> {
  _$BridgeLspFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeLspFrame_Failure _self;
  final $Res Function(BridgeLspFrame_Failure) _then;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeLspFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeLspFrame_Closed extends BridgeLspFrame {
  const BridgeLspFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspFrame_ClosedCopyWith<BridgeLspFrame_Closed> get copyWith => _$BridgeLspFrame_ClosedCopyWithImpl<BridgeLspFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeLspFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeLspFrame_ClosedCopyWith<$Res> implements $BridgeLspFrameCopyWith<$Res> {
  factory $BridgeLspFrame_ClosedCopyWith(BridgeLspFrame_Closed value, $Res Function(BridgeLspFrame_Closed) _then) = _$BridgeLspFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeLspFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeLspFrame_ClosedCopyWith<$Res> {
  _$BridgeLspFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeLspFrame_Closed _self;
  final $Res Function(BridgeLspFrame_Closed) _then;

/// Create a copy of BridgeLspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeLspFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
