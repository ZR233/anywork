// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'context.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeContextEvent {

 BridgeThreadFacetStamp get stamp; BridgeContextValue get value;
/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextEventCopyWith<BridgeContextEvent> get copyWith => _$BridgeContextEventCopyWithImpl<BridgeContextEvent>(this as BridgeContextEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeContextEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeContextEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeContextEvent;
  return 'BridgeContextEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeContextEventCopyWith<$Res>  {
  factory $BridgeContextEventCopyWith(BridgeContextEvent value, $Res Function(BridgeContextEvent) _then) = _$BridgeContextEventCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeContextValue value
});




}
/// @nodoc
class _$BridgeContextEventCopyWithImpl<$Res>
    implements $BridgeContextEventCopyWith<$Res> {
  _$BridgeContextEventCopyWithImpl(this._self, this._then);

  final BridgeContextEvent _self;
  final $Res Function(BridgeContextEvent) _then;

/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeContextValue,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeContextEvent].
extension BridgeContextEventPatterns on BridgeContextEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContextEvent_Baseline value)?  baseline,TResult Function( BridgeContextEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeContextEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContextEvent_Baseline value)  baseline,required TResult Function( BridgeContextEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline():
return baseline(_that);case BridgeContextEvent_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContextEvent_Baseline value)?  baseline,TResult? Function( BridgeContextEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeContextEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeContextValue value)?  baseline,TResult Function( BridgeThreadFacetStamp stamp,  BridgeContextValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeContextEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeContextValue value)  baseline,required TResult Function( BridgeThreadFacetStamp stamp,  BridgeContextValue value)  replace,}) {final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeContextEvent_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeContextValue value)?  baseline,TResult? Function( BridgeThreadFacetStamp stamp,  BridgeContextValue value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeContextEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeContextEvent_Replace() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContextEvent_Baseline extends BridgeContextEvent {
  const BridgeContextEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeThreadFeedIdentity identity;
@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeContextValue value;

/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextEvent_BaselineCopyWith<BridgeContextEvent_Baseline> get copyWith => _$BridgeContextEvent_BaselineCopyWithImpl<BridgeContextEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeContextEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeContextEvent_BaselineCopyWith<$Res> implements $BridgeContextEventCopyWith<$Res> {
  factory $BridgeContextEvent_BaselineCopyWith(BridgeContextEvent_Baseline value, $Res Function(BridgeContextEvent_Baseline) _then) = _$BridgeContextEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeThreadFacetStamp stamp, BridgeContextValue value
});




}
/// @nodoc
class _$BridgeContextEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeContextEvent_BaselineCopyWith<$Res> {
  _$BridgeContextEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeContextEvent_Baseline _self;
  final $Res Function(BridgeContextEvent_Baseline) _then;

/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeContextEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeContextValue,
  ));
}


}

/// @nodoc


class BridgeContextEvent_Replace extends BridgeContextEvent {
  const BridgeContextEvent_Replace({required this.stamp, required this.value}): super._();


@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeContextValue value;

/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextEvent_ReplaceCopyWith<BridgeContextEvent_Replace> get copyWith => _$BridgeContextEvent_ReplaceCopyWithImpl<BridgeContextEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}

@override
String toString() {
    return 'BridgeContextEvent.replace(stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeContextEvent_ReplaceCopyWith<$Res> implements $BridgeContextEventCopyWith<$Res> {
  factory $BridgeContextEvent_ReplaceCopyWith(BridgeContextEvent_Replace value, $Res Function(BridgeContextEvent_Replace) _then) = _$BridgeContextEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeContextValue value
});




}
/// @nodoc
class _$BridgeContextEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgeContextEvent_ReplaceCopyWith<$Res> {
  _$BridgeContextEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeContextEvent_Replace _self;
  final $Res Function(BridgeContextEvent_Replace) _then;

/// Create a copy of BridgeContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(BridgeContextEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeContextValue,
  ));
}


}

/// @nodoc
mixin _$BridgeContextFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContextFrame()';
}


}

/// @nodoc
class $BridgeContextFrameCopyWith<$Res>  {
$BridgeContextFrameCopyWith(BridgeContextFrame _, $Res Function(BridgeContextFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeContextFrame].
extension BridgeContextFramePatterns on BridgeContextFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContextFrame_Data value)?  data,TResult Function( BridgeContextFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeContextFrame_Failure value)?  failure,TResult Function( BridgeContextFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContextFrame_Data() when data != null:
return data(_that);case BridgeContextFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeContextFrame_Failure() when failure != null:
return failure(_that);case BridgeContextFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContextFrame_Data value)  data,required TResult Function( BridgeContextFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeContextFrame_Failure value)  failure,required TResult Function( BridgeContextFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeContextFrame_Data():
return data(_that);case BridgeContextFrame_ResyncRequired():
return resyncRequired(_that);case BridgeContextFrame_Failure():
return failure(_that);case BridgeContextFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContextFrame_Data value)?  data,TResult? Function( BridgeContextFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeContextFrame_Failure value)?  failure,TResult? Function( BridgeContextFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeContextFrame_Data() when data != null:
return data(_that);case BridgeContextFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeContextFrame_Failure() when failure != null:
return failure(_that);case BridgeContextFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeContextEvent event)?  data,TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContextFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeContextFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeContextFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeContextFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeContextEvent event)  data,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)  resyncRequired,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeContextFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeContextFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeContextFrame_Failure():
return failure(_that.identity,_that.error);case BridgeContextFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeContextEvent event)?  data,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeContextFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeContextFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeContextFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeContextFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContextFrame_Data extends BridgeContextFrame {
  const BridgeContextFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeContextEvent event;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextFrame_DataCopyWith<BridgeContextFrame_Data> get copyWith => _$BridgeContextFrame_DataCopyWithImpl<BridgeContextFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeContextFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeContextFrame_DataCopyWith<$Res> implements $BridgeContextFrameCopyWith<$Res> {
  factory $BridgeContextFrame_DataCopyWith(BridgeContextFrame_Data value, $Res Function(BridgeContextFrame_Data) _then) = _$BridgeContextFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeContextEvent event
});


$BridgeContextEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeContextFrame_DataCopyWithImpl<$Res>
    implements $BridgeContextFrame_DataCopyWith<$Res> {
  _$BridgeContextFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeContextFrame_Data _self;
  final $Res Function(BridgeContextFrame_Data) _then;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeContextFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeContextEvent,
  ));
}

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeContextEventCopyWith<$Res> get event {

  return $BridgeContextEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeContextFrame_ResyncRequired extends BridgeContextFrame {
  const BridgeContextFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeResyncReason reason;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextFrame_ResyncRequiredCopyWith<BridgeContextFrame_ResyncRequired> get copyWith => _$BridgeContextFrame_ResyncRequiredCopyWithImpl<BridgeContextFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeContextFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeContextFrame_ResyncRequiredCopyWith<$Res> implements $BridgeContextFrameCopyWith<$Res> {
  factory $BridgeContextFrame_ResyncRequiredCopyWith(BridgeContextFrame_ResyncRequired value, $Res Function(BridgeContextFrame_ResyncRequired) _then) = _$BridgeContextFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeResyncReason reason
});




}
/// @nodoc
class _$BridgeContextFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeContextFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeContextFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeContextFrame_ResyncRequired _self;
  final $Res Function(BridgeContextFrame_ResyncRequired) _then;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeContextFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeResyncReason,
  ));
}


}

/// @nodoc


class BridgeContextFrame_Failure extends BridgeContextFrame {
  const BridgeContextFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextFrame_FailureCopyWith<BridgeContextFrame_Failure> get copyWith => _$BridgeContextFrame_FailureCopyWithImpl<BridgeContextFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeContextFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeContextFrame_FailureCopyWith<$Res> implements $BridgeContextFrameCopyWith<$Res> {
  factory $BridgeContextFrame_FailureCopyWith(BridgeContextFrame_Failure value, $Res Function(BridgeContextFrame_Failure) _then) = _$BridgeContextFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeContextFrame_FailureCopyWithImpl<$Res>
    implements $BridgeContextFrame_FailureCopyWith<$Res> {
  _$BridgeContextFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeContextFrame_Failure _self;
  final $Res Function(BridgeContextFrame_Failure) _then;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeContextFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeContextFrame_Closed extends BridgeContextFrame {
  const BridgeContextFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeFeedClosedReason reason;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContextFrame_ClosedCopyWith<BridgeContextFrame_Closed> get copyWith => _$BridgeContextFrame_ClosedCopyWithImpl<BridgeContextFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContextFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeContextFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeContextFrame_ClosedCopyWith<$Res> implements $BridgeContextFrameCopyWith<$Res> {
  factory $BridgeContextFrame_ClosedCopyWith(BridgeContextFrame_Closed value, $Res Function(BridgeContextFrame_Closed) _then) = _$BridgeContextFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeFeedClosedReason reason
});




}
/// @nodoc
class _$BridgeContextFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeContextFrame_ClosedCopyWith<$Res> {
  _$BridgeContextFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeContextFrame_Closed _self;
  final $Res Function(BridgeContextFrame_Closed) _then;

/// Create a copy of BridgeContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeContextFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeFeedClosedReason,
  ));
}


}

// dart format on
