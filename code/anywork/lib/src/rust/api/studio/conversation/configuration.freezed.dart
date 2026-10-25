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
mixin _$BridgeThreadConfigurationEvent {

 BridgeThreadFacetStamp get stamp; BridgeConfigurationValue get value;
/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationEventCopyWith<BridgeThreadConfigurationEvent> get copyWith => _$BridgeThreadConfigurationEventCopyWithImpl<BridgeThreadConfigurationEvent>(this as BridgeThreadConfigurationEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeThreadConfigurationEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeThreadConfigurationEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeThreadConfigurationEvent;
  return 'BridgeThreadConfigurationEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationEventCopyWith<$Res>  {
  factory $BridgeThreadConfigurationEventCopyWith(BridgeThreadConfigurationEvent value, $Res Function(BridgeThreadConfigurationEvent) _then) = _$BridgeThreadConfigurationEventCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeConfigurationValue value
});




}
/// @nodoc
class _$BridgeThreadConfigurationEventCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationEventCopyWith<$Res> {
  _$BridgeThreadConfigurationEventCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationEvent _self;
  final $Res Function(BridgeThreadConfigurationEvent) _then;

/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationValue,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeThreadConfigurationEvent].
extension BridgeThreadConfigurationEventPatterns on BridgeThreadConfigurationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadConfigurationEvent_Baseline value)?  baseline,TResult Function( BridgeThreadConfigurationEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeThreadConfigurationEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadConfigurationEvent_Baseline value)  baseline,required TResult Function( BridgeThreadConfigurationEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline():
return baseline(_that);case BridgeThreadConfigurationEvent_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadConfigurationEvent_Baseline value)?  baseline,TResult? Function( BridgeThreadConfigurationEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeThreadConfigurationEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)?  baseline,TResult Function( BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadConfigurationEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)  baseline,required TResult Function( BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)  replace,}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadConfigurationEvent_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadFeedIdentity identity,  BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)?  baseline,TResult? Function( BridgeThreadFacetStamp stamp,  BridgeConfigurationValue value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeThreadConfigurationEvent_Replace() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadConfigurationEvent_Baseline extends BridgeThreadConfigurationEvent {
  const BridgeThreadConfigurationEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeThreadFeedIdentity identity;
@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeConfigurationValue value;

/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationEvent_BaselineCopyWith<BridgeThreadConfigurationEvent_Baseline> get copyWith => _$BridgeThreadConfigurationEvent_BaselineCopyWithImpl<BridgeThreadConfigurationEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeThreadConfigurationEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationEvent_BaselineCopyWith<$Res> implements $BridgeThreadConfigurationEventCopyWith<$Res> {
  factory $BridgeThreadConfigurationEvent_BaselineCopyWith(BridgeThreadConfigurationEvent_Baseline value, $Res Function(BridgeThreadConfigurationEvent_Baseline) _then) = _$BridgeThreadConfigurationEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeThreadFacetStamp stamp, BridgeConfigurationValue value
});




}
/// @nodoc
class _$BridgeThreadConfigurationEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationEvent_BaselineCopyWith<$Res> {
  _$BridgeThreadConfigurationEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationEvent_Baseline _self;
  final $Res Function(BridgeThreadConfigurationEvent_Baseline) _then;

/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeThreadConfigurationEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationValue,
  ));
}


}

/// @nodoc


class BridgeThreadConfigurationEvent_Replace extends BridgeThreadConfigurationEvent {
  const BridgeThreadConfigurationEvent_Replace({required this.stamp, required this.value}): super._();


@override final  BridgeThreadFacetStamp stamp;
@override final  BridgeConfigurationValue value;

/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationEvent_ReplaceCopyWith<BridgeThreadConfigurationEvent_Replace> get copyWith => _$BridgeThreadConfigurationEvent_ReplaceCopyWithImpl<BridgeThreadConfigurationEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}

@override
String toString() {
    return 'BridgeThreadConfigurationEvent.replace(stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationEvent_ReplaceCopyWith<$Res> implements $BridgeThreadConfigurationEventCopyWith<$Res> {
  factory $BridgeThreadConfigurationEvent_ReplaceCopyWith(BridgeThreadConfigurationEvent_Replace value, $Res Function(BridgeThreadConfigurationEvent_Replace) _then) = _$BridgeThreadConfigurationEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeThreadFacetStamp stamp, BridgeConfigurationValue value
});




}
/// @nodoc
class _$BridgeThreadConfigurationEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationEvent_ReplaceCopyWith<$Res> {
  _$BridgeThreadConfigurationEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationEvent_Replace _self;
  final $Res Function(BridgeThreadConfigurationEvent_Replace) _then;

/// Create a copy of BridgeThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(BridgeThreadConfigurationEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationValue,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadConfigurationFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadConfigurationFrame()';
}


}

/// @nodoc
class $BridgeThreadConfigurationFrameCopyWith<$Res>  {
$BridgeThreadConfigurationFrameCopyWith(BridgeThreadConfigurationFrame _, $Res Function(BridgeThreadConfigurationFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadConfigurationFrame].
extension BridgeThreadConfigurationFramePatterns on BridgeThreadConfigurationFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadConfigurationFrame_Data value)?  data,TResult Function( BridgeThreadConfigurationFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeThreadConfigurationFrame_Failure value)?  failure,TResult Function( BridgeThreadConfigurationFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data() when data != null:
return data(_that);case BridgeThreadConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeThreadConfigurationFrame_Failure() when failure != null:
return failure(_that);case BridgeThreadConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadConfigurationFrame_Data value)  data,required TResult Function( BridgeThreadConfigurationFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeThreadConfigurationFrame_Failure value)  failure,required TResult Function( BridgeThreadConfigurationFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data():
return data(_that);case BridgeThreadConfigurationFrame_ResyncRequired():
return resyncRequired(_that);case BridgeThreadConfigurationFrame_Failure():
return failure(_that);case BridgeThreadConfigurationFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadConfigurationFrame_Data value)?  data,TResult? Function( BridgeThreadConfigurationFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeThreadConfigurationFrame_Failure value)?  failure,TResult? Function( BridgeThreadConfigurationFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data() when data != null:
return data(_that);case BridgeThreadConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeThreadConfigurationFrame_Failure() when failure != null:
return failure(_that);case BridgeThreadConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeThreadConfigurationEvent event)?  data,TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeThreadConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeThreadConfigurationFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeThreadConfigurationFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeThreadConfigurationEvent event)  data,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)  resyncRequired,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeThreadConfigurationFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeThreadConfigurationFrame_Failure():
return failure(_that.identity,_that.error);case BridgeThreadConfigurationFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeThreadConfigurationEvent event)?  data,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeResyncReason reason)?  resyncRequired,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeThreadFeedIdentity identity,  BridgeFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeThreadConfigurationFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeThreadConfigurationFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeThreadConfigurationFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeThreadConfigurationFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadConfigurationFrame_Data extends BridgeThreadConfigurationFrame {
  const BridgeThreadConfigurationFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeThreadConfigurationEvent event;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationFrame_DataCopyWith<BridgeThreadConfigurationFrame_Data> get copyWith => _$BridgeThreadConfigurationFrame_DataCopyWithImpl<BridgeThreadConfigurationFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeThreadConfigurationFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationFrame_DataCopyWith<$Res> implements $BridgeThreadConfigurationFrameCopyWith<$Res> {
  factory $BridgeThreadConfigurationFrame_DataCopyWith(BridgeThreadConfigurationFrame_Data value, $Res Function(BridgeThreadConfigurationFrame_Data) _then) = _$BridgeThreadConfigurationFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeThreadConfigurationEvent event
});


$BridgeThreadConfigurationEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeThreadConfigurationFrame_DataCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationFrame_DataCopyWith<$Res> {
  _$BridgeThreadConfigurationFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationFrame_Data _self;
  final $Res Function(BridgeThreadConfigurationFrame_Data) _then;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeThreadConfigurationFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeThreadConfigurationEvent,
  ));
}

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationEventCopyWith<$Res> get event {

  return $BridgeThreadConfigurationEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeThreadConfigurationFrame_ResyncRequired extends BridgeThreadConfigurationFrame {
  const BridgeThreadConfigurationFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeResyncReason reason;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationFrame_ResyncRequiredCopyWith<BridgeThreadConfigurationFrame_ResyncRequired> get copyWith => _$BridgeThreadConfigurationFrame_ResyncRequiredCopyWithImpl<BridgeThreadConfigurationFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeThreadConfigurationFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationFrame_ResyncRequiredCopyWith<$Res> implements $BridgeThreadConfigurationFrameCopyWith<$Res> {
  factory $BridgeThreadConfigurationFrame_ResyncRequiredCopyWith(BridgeThreadConfigurationFrame_ResyncRequired value, $Res Function(BridgeThreadConfigurationFrame_ResyncRequired) _then) = _$BridgeThreadConfigurationFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeResyncReason reason
});




}
/// @nodoc
class _$BridgeThreadConfigurationFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeThreadConfigurationFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationFrame_ResyncRequired _self;
  final $Res Function(BridgeThreadConfigurationFrame_ResyncRequired) _then;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeThreadConfigurationFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeResyncReason,
  ));
}


}

/// @nodoc


class BridgeThreadConfigurationFrame_Failure extends BridgeThreadConfigurationFrame {
  const BridgeThreadConfigurationFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationFrame_FailureCopyWith<BridgeThreadConfigurationFrame_Failure> get copyWith => _$BridgeThreadConfigurationFrame_FailureCopyWithImpl<BridgeThreadConfigurationFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeThreadConfigurationFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationFrame_FailureCopyWith<$Res> implements $BridgeThreadConfigurationFrameCopyWith<$Res> {
  factory $BridgeThreadConfigurationFrame_FailureCopyWith(BridgeThreadConfigurationFrame_Failure value, $Res Function(BridgeThreadConfigurationFrame_Failure) _then) = _$BridgeThreadConfigurationFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeThreadConfigurationFrame_FailureCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationFrame_FailureCopyWith<$Res> {
  _$BridgeThreadConfigurationFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationFrame_Failure _self;
  final $Res Function(BridgeThreadConfigurationFrame_Failure) _then;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeThreadConfigurationFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeThreadConfigurationFrame_Closed extends BridgeThreadConfigurationFrame {
  const BridgeThreadConfigurationFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeThreadFeedIdentity identity;
 final  BridgeFeedClosedReason reason;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadConfigurationFrame_ClosedCopyWith<BridgeThreadConfigurationFrame_Closed> get copyWith => _$BridgeThreadConfigurationFrame_ClosedCopyWithImpl<BridgeThreadConfigurationFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadConfigurationFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeThreadConfigurationFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadConfigurationFrame_ClosedCopyWith<$Res> implements $BridgeThreadConfigurationFrameCopyWith<$Res> {
  factory $BridgeThreadConfigurationFrame_ClosedCopyWith(BridgeThreadConfigurationFrame_Closed value, $Res Function(BridgeThreadConfigurationFrame_Closed) _then) = _$BridgeThreadConfigurationFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeThreadFeedIdentity identity, BridgeFeedClosedReason reason
});




}
/// @nodoc
class _$BridgeThreadConfigurationFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeThreadConfigurationFrame_ClosedCopyWith<$Res> {
  _$BridgeThreadConfigurationFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeThreadConfigurationFrame_Closed _self;
  final $Res Function(BridgeThreadConfigurationFrame_Closed) _then;

/// Create a copy of BridgeThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeThreadConfigurationFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeFeedClosedReason,
  ));
}


}

// dart format on
