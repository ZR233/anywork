// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeConfigurationEvent {

 BridgeProductProjectionStamp get stamp; Object get value;
/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationEventCopyWith<BridgeConfigurationEvent> get copyWith => _$BridgeConfigurationEventCopyWithImpl<BridgeConfigurationEvent>(this as BridgeConfigurationEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeConfigurationEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeConfigurationEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeConfigurationEvent;
  return 'BridgeConfigurationEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationEventCopyWith<$Res>  {
  factory $BridgeConfigurationEventCopyWith(BridgeConfigurationEvent value, $Res Function(BridgeConfigurationEvent) _then) = _$BridgeConfigurationEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp
});




}
/// @nodoc
class _$BridgeConfigurationEventCopyWithImpl<$Res>
    implements $BridgeConfigurationEventCopyWith<$Res> {
  _$BridgeConfigurationEventCopyWithImpl(this._self, this._then);

  final BridgeConfigurationEvent _self;
  final $Res Function(BridgeConfigurationEvent) _then;

/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeConfigurationEvent].
extension BridgeConfigurationEventPatterns on BridgeConfigurationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConfigurationEvent_Baseline value)?  baseline,TResult Function( BridgeConfigurationEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeConfigurationEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConfigurationEvent_Baseline value)  baseline,required TResult Function( BridgeConfigurationEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline():
return baseline(_that);case BridgeConfigurationEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationEvent_Baseline value)?  baseline,TResult? Function( BridgeConfigurationEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeConfigurationEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeConfigurationBaseline value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeConfigurationChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeConfigurationEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeConfigurationBaseline value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeConfigurationChange value)  change,}) {final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeConfigurationEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeConfigurationBaseline value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeConfigurationChange value)?  change,}) {final _that = this;
switch (_that) {
case BridgeConfigurationEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeConfigurationEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConfigurationEvent_Baseline extends BridgeConfigurationEvent {
  const BridgeConfigurationEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeConfigurationBaseline value;

/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationEvent_BaselineCopyWith<BridgeConfigurationEvent_Baseline> get copyWith => _$BridgeConfigurationEvent_BaselineCopyWithImpl<BridgeConfigurationEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeConfigurationEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationEvent_BaselineCopyWith<$Res> implements $BridgeConfigurationEventCopyWith<$Res> {
  factory $BridgeConfigurationEvent_BaselineCopyWith(BridgeConfigurationEvent_Baseline value, $Res Function(BridgeConfigurationEvent_Baseline) _then) = _$BridgeConfigurationEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeConfigurationBaseline value
});




}
/// @nodoc
class _$BridgeConfigurationEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeConfigurationEvent_BaselineCopyWith<$Res> {
  _$BridgeConfigurationEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeConfigurationEvent_Baseline _self;
  final $Res Function(BridgeConfigurationEvent_Baseline) _then;

/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeConfigurationEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationBaseline,
  ));
}


}

/// @nodoc


class BridgeConfigurationEvent_Change extends BridgeConfigurationEvent {
  const BridgeConfigurationEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeConfigurationChange value;

/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationEvent_ChangeCopyWith<BridgeConfigurationEvent_Change> get copyWith => _$BridgeConfigurationEvent_ChangeCopyWithImpl<BridgeConfigurationEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeConfigurationEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationEvent_ChangeCopyWith<$Res> implements $BridgeConfigurationEventCopyWith<$Res> {
  factory $BridgeConfigurationEvent_ChangeCopyWith(BridgeConfigurationEvent_Change value, $Res Function(BridgeConfigurationEvent_Change) _then) = _$BridgeConfigurationEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeConfigurationChange value
});




}
/// @nodoc
class _$BridgeConfigurationEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeConfigurationEvent_ChangeCopyWith<$Res> {
  _$BridgeConfigurationEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeConfigurationEvent_Change _self;
  final $Res Function(BridgeConfigurationEvent_Change) _then;

/// Create a copy of BridgeConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeConfigurationEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationChange,
  ));
}


}

/// @nodoc
mixin _$BridgeConfigurationFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConfigurationFrame()';
}


}

/// @nodoc
class $BridgeConfigurationFrameCopyWith<$Res>  {
$BridgeConfigurationFrameCopyWith(BridgeConfigurationFrame _, $Res Function(BridgeConfigurationFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeConfigurationFrame].
extension BridgeConfigurationFramePatterns on BridgeConfigurationFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConfigurationFrame_Data value)?  data,TResult Function( BridgeConfigurationFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeConfigurationFrame_Failure value)?  failure,TResult Function( BridgeConfigurationFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data() when data != null:
return data(_that);case BridgeConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeConfigurationFrame_Failure() when failure != null:
return failure(_that);case BridgeConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConfigurationFrame_Data value)  data,required TResult Function( BridgeConfigurationFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeConfigurationFrame_Failure value)  failure,required TResult Function( BridgeConfigurationFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data():
return data(_that);case BridgeConfigurationFrame_ResyncRequired():
return resyncRequired(_that);case BridgeConfigurationFrame_Failure():
return failure(_that);case BridgeConfigurationFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationFrame_Data value)?  data,TResult? Function( BridgeConfigurationFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeConfigurationFrame_Failure value)?  failure,TResult? Function( BridgeConfigurationFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data() when data != null:
return data(_that);case BridgeConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeConfigurationFrame_Failure() when failure != null:
return failure(_that);case BridgeConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeConfigurationEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeConfigurationFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeConfigurationEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeConfigurationFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeConfigurationFrame_Failure():
return failure(_that.identity,_that.error);case BridgeConfigurationFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeConfigurationEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeConfigurationFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeConfigurationFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeConfigurationFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConfigurationFrame_Data extends BridgeConfigurationFrame {
  const BridgeConfigurationFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeConfigurationEvent event;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationFrame_DataCopyWith<BridgeConfigurationFrame_Data> get copyWith => _$BridgeConfigurationFrame_DataCopyWithImpl<BridgeConfigurationFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeConfigurationFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationFrame_DataCopyWith<$Res> implements $BridgeConfigurationFrameCopyWith<$Res> {
  factory $BridgeConfigurationFrame_DataCopyWith(BridgeConfigurationFrame_Data value, $Res Function(BridgeConfigurationFrame_Data) _then) = _$BridgeConfigurationFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeConfigurationEvent event
});


$BridgeConfigurationEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeConfigurationFrame_DataCopyWithImpl<$Res>
    implements $BridgeConfigurationFrame_DataCopyWith<$Res> {
  _$BridgeConfigurationFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeConfigurationFrame_Data _self;
  final $Res Function(BridgeConfigurationFrame_Data) _then;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeConfigurationFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationEvent,
  ));
}

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeConfigurationEventCopyWith<$Res> get event {

  return $BridgeConfigurationEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeConfigurationFrame_ResyncRequired extends BridgeConfigurationFrame {
  const BridgeConfigurationFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationFrame_ResyncRequiredCopyWith<BridgeConfigurationFrame_ResyncRequired> get copyWith => _$BridgeConfigurationFrame_ResyncRequiredCopyWithImpl<BridgeConfigurationFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeConfigurationFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationFrame_ResyncRequiredCopyWith<$Res> implements $BridgeConfigurationFrameCopyWith<$Res> {
  factory $BridgeConfigurationFrame_ResyncRequiredCopyWith(BridgeConfigurationFrame_ResyncRequired value, $Res Function(BridgeConfigurationFrame_ResyncRequired) _then) = _$BridgeConfigurationFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeConfigurationFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeConfigurationFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeConfigurationFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeConfigurationFrame_ResyncRequired _self;
  final $Res Function(BridgeConfigurationFrame_ResyncRequired) _then;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeConfigurationFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeConfigurationFrame_Failure extends BridgeConfigurationFrame {
  const BridgeConfigurationFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationFrame_FailureCopyWith<BridgeConfigurationFrame_Failure> get copyWith => _$BridgeConfigurationFrame_FailureCopyWithImpl<BridgeConfigurationFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeConfigurationFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationFrame_FailureCopyWith<$Res> implements $BridgeConfigurationFrameCopyWith<$Res> {
  factory $BridgeConfigurationFrame_FailureCopyWith(BridgeConfigurationFrame_Failure value, $Res Function(BridgeConfigurationFrame_Failure) _then) = _$BridgeConfigurationFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationFrame_FailureCopyWithImpl<$Res>
    implements $BridgeConfigurationFrame_FailureCopyWith<$Res> {
  _$BridgeConfigurationFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeConfigurationFrame_Failure _self;
  final $Res Function(BridgeConfigurationFrame_Failure) _then;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeConfigurationFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConfigurationFrame_Closed extends BridgeConfigurationFrame {
  const BridgeConfigurationFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationFrame_ClosedCopyWith<BridgeConfigurationFrame_Closed> get copyWith => _$BridgeConfigurationFrame_ClosedCopyWithImpl<BridgeConfigurationFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeConfigurationFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationFrame_ClosedCopyWith<$Res> implements $BridgeConfigurationFrameCopyWith<$Res> {
  factory $BridgeConfigurationFrame_ClosedCopyWith(BridgeConfigurationFrame_Closed value, $Res Function(BridgeConfigurationFrame_Closed) _then) = _$BridgeConfigurationFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeConfigurationFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeConfigurationFrame_ClosedCopyWith<$Res> {
  _$BridgeConfigurationFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationFrame_Closed _self;
  final $Res Function(BridgeConfigurationFrame_Closed) _then;

/// Create a copy of BridgeConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeConfigurationFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
