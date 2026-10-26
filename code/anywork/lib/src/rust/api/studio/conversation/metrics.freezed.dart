// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metrics.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMetricsEvent {

 BridgeThreadFacetStamp get stamp; BridgeMetricsValue get value;
/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsEventCopyWith<BridgeMetricsEvent> get copyWith => _$BridgeMetricsEventCopyWithImpl<BridgeMetricsEvent>(this as BridgeMetricsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeMetricsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeMetricsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeMetricsEvent;
  return 'BridgeMetricsEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsEventCopyWith<$Res>  {
  factory $BridgeMetricsEventCopyWith(BridgeMetricsEvent value, $Res Function(BridgeMetricsEvent) _then) = _$BridgeMetricsEventCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeMetricsValue value
});




}
/// @nodoc
class _$BridgeMetricsEventCopyWithImpl<$Res>
    implements $BridgeMetricsEventCopyWith<$Res> {
  _$BridgeMetricsEventCopyWithImpl(this._self, this._then);

  final BridgeMetricsEvent _self;
  final $Res Function(BridgeMetricsEvent) _then;

/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeMetricsValue,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeMetricsEvent].
extension BridgeMetricsEventPatterns on BridgeMetricsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMetricsEvent_Baseline value)?  baseline,TResult Function( BridgeMetricsEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeMetricsEvent_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMetricsEvent_Baseline value)  baseline,required TResult Function( BridgeMetricsEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline():
return baseline(_that);case BridgeMetricsEvent_Replace():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMetricsEvent_Baseline value)?  baseline,TResult? Function( BridgeMetricsEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeMetricsEvent_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)?  baseline,TResult Function( BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMetricsEvent_Replace() when replace != null:
return replace(_that.stamp,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)  baseline,required TResult Function( BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)  replace,}) {final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMetricsEvent_Replace():
return replace(_that.stamp,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)?  baseline,TResult? Function( BridgeThreadFacetStamp stamp,  BridgeMetricsValue value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeMetricsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeMetricsEvent_Replace() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMetricsEvent_Baseline extends BridgeMetricsEvent {
  const BridgeMetricsEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeThreadFeedIdentity identity;
@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeMetricsValue value;

/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsEvent_BaselineCopyWith<BridgeMetricsEvent_Baseline> get copyWith => _$BridgeMetricsEvent_BaselineCopyWithImpl<BridgeMetricsEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeMetricsEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsEvent_BaselineCopyWith<$Res> implements $BridgeMetricsEventCopyWith<$Res> {
  factory $BridgeMetricsEvent_BaselineCopyWith(BridgeMetricsEvent_Baseline value, $Res Function(BridgeMetricsEvent_Baseline) _then) = _$BridgeMetricsEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeThreadFacetStamp stamp, BridgeMetricsValue value
});




}
/// @nodoc
class _$BridgeMetricsEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeMetricsEvent_BaselineCopyWith<$Res> {
  _$BridgeMetricsEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeMetricsEvent_Baseline _self;
  final $Res Function(BridgeMetricsEvent_Baseline) _then;

/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeMetricsEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeMetricsValue,
  ));
}


}

/// @nodoc


class BridgeMetricsEvent_Replace extends BridgeMetricsEvent {
  const BridgeMetricsEvent_Replace({required this.stamp, required this.value}): super._();


@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeMetricsValue value;

/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsEvent_ReplaceCopyWith<BridgeMetricsEvent_Replace> get copyWith => _$BridgeMetricsEvent_ReplaceCopyWithImpl<BridgeMetricsEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}

@override
String toString() {
    return 'BridgeMetricsEvent.replace(stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsEvent_ReplaceCopyWith<$Res> implements $BridgeMetricsEventCopyWith<$Res> {
  factory $BridgeMetricsEvent_ReplaceCopyWith(BridgeMetricsEvent_Replace value, $Res Function(BridgeMetricsEvent_Replace) _then) = _$BridgeMetricsEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeMetricsValue value
});




}
/// @nodoc
class _$BridgeMetricsEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgeMetricsEvent_ReplaceCopyWith<$Res> {
  _$BridgeMetricsEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeMetricsEvent_Replace _self;
  final $Res Function(BridgeMetricsEvent_Replace) _then;

/// Create a copy of BridgeMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(BridgeMetricsEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeMetricsValue,
  ));
}


}

/// @nodoc
mixin _$BridgeMetricsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMetricsFrame()';
}


}

/// @nodoc
class $BridgeMetricsFrameCopyWith<$Res>  {
$BridgeMetricsFrameCopyWith(BridgeMetricsFrame _, $Res Function(BridgeMetricsFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeMetricsFrame].
extension BridgeMetricsFramePatterns on BridgeMetricsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMetricsFrame_Data value)?  data,TResult Function( BridgeMetricsFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeMetricsFrame_Failure value)?  failure,TResult Function( BridgeMetricsFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data() when data != null:
return data(_that);case BridgeMetricsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeMetricsFrame_Failure() when failure != null:
return failure(_that);case BridgeMetricsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMetricsFrame_Data value)  data,required TResult Function( BridgeMetricsFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeMetricsFrame_Failure value)  failure,required TResult Function( BridgeMetricsFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data():
return data(_that);case BridgeMetricsFrame_ResyncRequired():
return resyncRequired(_that);case BridgeMetricsFrame_Failure():
return failure(_that);case BridgeMetricsFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMetricsFrame_Data value)?  data,TResult? Function( BridgeMetricsFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeMetricsFrame_Failure value)?  failure,TResult? Function( BridgeMetricsFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data() when data != null:
return data(_that);case BridgeMetricsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeMetricsFrame_Failure() when failure != null:
return failure(_that);case BridgeMetricsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeMetricsEvent event)?  data,TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeMetricsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeMetricsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeMetricsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeMetricsEvent event)  data,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)  resyncRequired,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeMetricsFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeMetricsFrame_Failure():
return failure(_that.identity,_that.error);case BridgeMetricsFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeMetricsEvent event)?  data,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeMetricsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeMetricsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeMetricsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeMetricsFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMetricsFrame_Data extends BridgeMetricsFrame {
  const BridgeMetricsFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeMetricsEvent event;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsFrame_DataCopyWith<BridgeMetricsFrame_Data> get copyWith => _$BridgeMetricsFrame_DataCopyWithImpl<BridgeMetricsFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeMetricsFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsFrame_DataCopyWith<$Res> implements $BridgeMetricsFrameCopyWith<$Res> {
  factory $BridgeMetricsFrame_DataCopyWith(BridgeMetricsFrame_Data value, $Res Function(BridgeMetricsFrame_Data) _then) = _$BridgeMetricsFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeMetricsEvent event
});


$BridgeMetricsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeMetricsFrame_DataCopyWithImpl<$Res>
    implements $BridgeMetricsFrame_DataCopyWith<$Res> {
  _$BridgeMetricsFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeMetricsFrame_Data _self;
  final $Res Function(BridgeMetricsFrame_Data) _then;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeMetricsFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeMetricsEvent,
  ));
}

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeMetricsEventCopyWith<$Res> get event {

  return $BridgeMetricsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeMetricsFrame_ResyncRequired extends BridgeMetricsFrame {
  const BridgeMetricsFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeResyncReason reason;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsFrame_ResyncRequiredCopyWith<BridgeMetricsFrame_ResyncRequired> get copyWith => _$BridgeMetricsFrame_ResyncRequiredCopyWithImpl<BridgeMetricsFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeMetricsFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsFrame_ResyncRequiredCopyWith<$Res> implements $BridgeMetricsFrameCopyWith<$Res> {
  factory $BridgeMetricsFrame_ResyncRequiredCopyWith(BridgeMetricsFrame_ResyncRequired value, $Res Function(BridgeMetricsFrame_ResyncRequired) _then) = _$BridgeMetricsFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeResyncReason reason
});




}
/// @nodoc
class _$BridgeMetricsFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeMetricsFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeMetricsFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeMetricsFrame_ResyncRequired _self;
  final $Res Function(BridgeMetricsFrame_ResyncRequired) _then;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeMetricsFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeResyncReason,
  ));
}


}

/// @nodoc


class BridgeMetricsFrame_Failure extends BridgeMetricsFrame {
  const BridgeMetricsFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsFrame_FailureCopyWith<BridgeMetricsFrame_Failure> get copyWith => _$BridgeMetricsFrame_FailureCopyWithImpl<BridgeMetricsFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeMetricsFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsFrame_FailureCopyWith<$Res> implements $BridgeMetricsFrameCopyWith<$Res> {
  factory $BridgeMetricsFrame_FailureCopyWith(BridgeMetricsFrame_Failure value, $Res Function(BridgeMetricsFrame_Failure) _then) = _$BridgeMetricsFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeMetricsFrame_FailureCopyWithImpl<$Res>
    implements $BridgeMetricsFrame_FailureCopyWith<$Res> {
  _$BridgeMetricsFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeMetricsFrame_Failure _self;
  final $Res Function(BridgeMetricsFrame_Failure) _then;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeMetricsFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeMetricsFrame_Closed extends BridgeMetricsFrame {
  const BridgeMetricsFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeFeedClosedReason reason;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMetricsFrame_ClosedCopyWith<BridgeMetricsFrame_Closed> get copyWith => _$BridgeMetricsFrame_ClosedCopyWithImpl<BridgeMetricsFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMetricsFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeMetricsFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeMetricsFrame_ClosedCopyWith<$Res> implements $BridgeMetricsFrameCopyWith<$Res> {
  factory $BridgeMetricsFrame_ClosedCopyWith(BridgeMetricsFrame_Closed value, $Res Function(BridgeMetricsFrame_Closed) _then) = _$BridgeMetricsFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeFeedClosedReason reason
});




}
/// @nodoc
class _$BridgeMetricsFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeMetricsFrame_ClosedCopyWith<$Res> {
  _$BridgeMetricsFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeMetricsFrame_Closed _self;
  final $Res Function(BridgeMetricsFrame_Closed) _then;

/// Create a copy of BridgeMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeMetricsFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeFeedClosedReason,
  ));
}


}

// dart format on
