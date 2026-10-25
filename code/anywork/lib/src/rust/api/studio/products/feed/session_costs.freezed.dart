// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_costs.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSessionCostsEvent {

 BridgeProductProjectionStamp get stamp; BridgeSessionCostsHeader get value;
/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsEventCopyWith<BridgeSessionCostsEvent> get copyWith => _$BridgeSessionCostsEventCopyWithImpl<BridgeSessionCostsEvent>(this as BridgeSessionCostsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeSessionCostsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeSessionCostsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeSessionCostsEvent;
  return 'BridgeSessionCostsEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsEventCopyWith<$Res>  {
  factory $BridgeSessionCostsEventCopyWith(BridgeSessionCostsEvent value, $Res Function(BridgeSessionCostsEvent) _then) = _$BridgeSessionCostsEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgeSessionCostsHeader value
});




}
/// @nodoc
class _$BridgeSessionCostsEventCopyWithImpl<$Res>
    implements $BridgeSessionCostsEventCopyWith<$Res> {
  _$BridgeSessionCostsEventCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsEvent _self;
  final $Res Function(BridgeSessionCostsEvent) _then;

/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeSessionCostsHeader,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeSessionCostsEvent].
extension BridgeSessionCostsEventPatterns on BridgeSessionCostsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSessionCostsEvent_Baseline value)?  baseline,TResult Function( BridgeSessionCostsEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeSessionCostsEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSessionCostsEvent_Baseline value)  baseline,required TResult Function( BridgeSessionCostsEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline():
return baseline(_that);case BridgeSessionCostsEvent_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSessionCostsEvent_Baseline value)?  baseline,TResult? Function( BridgeSessionCostsEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeSessionCostsEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSessionCostsHeader value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSessionCostsHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSessionCostsEvent_Replace() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSessionCostsHeader value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSessionCostsHeader value)  replace,}) {final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSessionCostsEvent_Replace():
return replace(_that.stamp,_that.baseRevision,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeSessionCostsHeader value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeSessionCostsHeader value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeSessionCostsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeSessionCostsEvent_Replace() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSessionCostsEvent_Baseline extends BridgeSessionCostsEvent {
  const BridgeSessionCostsEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeSessionCostsHeader value;

/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsEvent_BaselineCopyWith<BridgeSessionCostsEvent_Baseline> get copyWith => _$BridgeSessionCostsEvent_BaselineCopyWithImpl<BridgeSessionCostsEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeSessionCostsEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsEvent_BaselineCopyWith<$Res> implements $BridgeSessionCostsEventCopyWith<$Res> {
  factory $BridgeSessionCostsEvent_BaselineCopyWith(BridgeSessionCostsEvent_Baseline value, $Res Function(BridgeSessionCostsEvent_Baseline) _then) = _$BridgeSessionCostsEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeSessionCostsHeader value
});




}
/// @nodoc
class _$BridgeSessionCostsEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeSessionCostsEvent_BaselineCopyWith<$Res> {
  _$BridgeSessionCostsEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsEvent_Baseline _self;
  final $Res Function(BridgeSessionCostsEvent_Baseline) _then;

/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeSessionCostsEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeSessionCostsHeader,
  ));
}


}

/// @nodoc


class BridgeSessionCostsEvent_Replace extends BridgeSessionCostsEvent {
  const BridgeSessionCostsEvent_Replace({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeSessionCostsHeader value;

/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsEvent_ReplaceCopyWith<BridgeSessionCostsEvent_Replace> get copyWith => _$BridgeSessionCostsEvent_ReplaceCopyWithImpl<BridgeSessionCostsEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeSessionCostsEvent.replace(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsEvent_ReplaceCopyWith<$Res> implements $BridgeSessionCostsEventCopyWith<$Res> {
  factory $BridgeSessionCostsEvent_ReplaceCopyWith(BridgeSessionCostsEvent_Replace value, $Res Function(BridgeSessionCostsEvent_Replace) _then) = _$BridgeSessionCostsEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeSessionCostsHeader value
});




}
/// @nodoc
class _$BridgeSessionCostsEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgeSessionCostsEvent_ReplaceCopyWith<$Res> {
  _$BridgeSessionCostsEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsEvent_Replace _self;
  final $Res Function(BridgeSessionCostsEvent_Replace) _then;

/// Create a copy of BridgeSessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeSessionCostsEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeSessionCostsHeader,
  ));
}


}

/// @nodoc
mixin _$BridgeSessionCostsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSessionCostsFrame()';
}


}

/// @nodoc
class $BridgeSessionCostsFrameCopyWith<$Res>  {
$BridgeSessionCostsFrameCopyWith(BridgeSessionCostsFrame _, $Res Function(BridgeSessionCostsFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeSessionCostsFrame].
extension BridgeSessionCostsFramePatterns on BridgeSessionCostsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSessionCostsFrame_Data value)?  data,TResult Function( BridgeSessionCostsFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeSessionCostsFrame_Failure value)?  failure,TResult Function( BridgeSessionCostsFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data() when data != null:
return data(_that);case BridgeSessionCostsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeSessionCostsFrame_Failure() when failure != null:
return failure(_that);case BridgeSessionCostsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSessionCostsFrame_Data value)  data,required TResult Function( BridgeSessionCostsFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeSessionCostsFrame_Failure value)  failure,required TResult Function( BridgeSessionCostsFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data():
return data(_that);case BridgeSessionCostsFrame_ResyncRequired():
return resyncRequired(_that);case BridgeSessionCostsFrame_Failure():
return failure(_that);case BridgeSessionCostsFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSessionCostsFrame_Data value)?  data,TResult? Function( BridgeSessionCostsFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeSessionCostsFrame_Failure value)?  failure,TResult? Function( BridgeSessionCostsFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data() when data != null:
return data(_that);case BridgeSessionCostsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeSessionCostsFrame_Failure() when failure != null:
return failure(_that);case BridgeSessionCostsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeSessionCostsEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeSessionCostsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeSessionCostsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeSessionCostsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeSessionCostsEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeSessionCostsFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeSessionCostsFrame_Failure():
return failure(_that.identity,_that.error);case BridgeSessionCostsFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeSessionCostsEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeSessionCostsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeSessionCostsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeSessionCostsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeSessionCostsFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSessionCostsFrame_Data extends BridgeSessionCostsFrame {
  const BridgeSessionCostsFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeSessionCostsEvent event;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsFrame_DataCopyWith<BridgeSessionCostsFrame_Data> get copyWith => _$BridgeSessionCostsFrame_DataCopyWithImpl<BridgeSessionCostsFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeSessionCostsFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsFrame_DataCopyWith<$Res> implements $BridgeSessionCostsFrameCopyWith<$Res> {
  factory $BridgeSessionCostsFrame_DataCopyWith(BridgeSessionCostsFrame_Data value, $Res Function(BridgeSessionCostsFrame_Data) _then) = _$BridgeSessionCostsFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeSessionCostsEvent event
});


$BridgeSessionCostsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeSessionCostsFrame_DataCopyWithImpl<$Res>
    implements $BridgeSessionCostsFrame_DataCopyWith<$Res> {
  _$BridgeSessionCostsFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsFrame_Data _self;
  final $Res Function(BridgeSessionCostsFrame_Data) _then;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeSessionCostsFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeSessionCostsEvent,
  ));
}

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSessionCostsEventCopyWith<$Res> get event {

  return $BridgeSessionCostsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeSessionCostsFrame_ResyncRequired extends BridgeSessionCostsFrame {
  const BridgeSessionCostsFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsFrame_ResyncRequiredCopyWith<BridgeSessionCostsFrame_ResyncRequired> get copyWith => _$BridgeSessionCostsFrame_ResyncRequiredCopyWithImpl<BridgeSessionCostsFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeSessionCostsFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsFrame_ResyncRequiredCopyWith<$Res> implements $BridgeSessionCostsFrameCopyWith<$Res> {
  factory $BridgeSessionCostsFrame_ResyncRequiredCopyWith(BridgeSessionCostsFrame_ResyncRequired value, $Res Function(BridgeSessionCostsFrame_ResyncRequired) _then) = _$BridgeSessionCostsFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeSessionCostsFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeSessionCostsFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeSessionCostsFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsFrame_ResyncRequired _self;
  final $Res Function(BridgeSessionCostsFrame_ResyncRequired) _then;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeSessionCostsFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeSessionCostsFrame_Failure extends BridgeSessionCostsFrame {
  const BridgeSessionCostsFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsFrame_FailureCopyWith<BridgeSessionCostsFrame_Failure> get copyWith => _$BridgeSessionCostsFrame_FailureCopyWithImpl<BridgeSessionCostsFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeSessionCostsFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsFrame_FailureCopyWith<$Res> implements $BridgeSessionCostsFrameCopyWith<$Res> {
  factory $BridgeSessionCostsFrame_FailureCopyWith(BridgeSessionCostsFrame_Failure value, $Res Function(BridgeSessionCostsFrame_Failure) _then) = _$BridgeSessionCostsFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeSessionCostsFrame_FailureCopyWithImpl<$Res>
    implements $BridgeSessionCostsFrame_FailureCopyWith<$Res> {
  _$BridgeSessionCostsFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsFrame_Failure _self;
  final $Res Function(BridgeSessionCostsFrame_Failure) _then;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeSessionCostsFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeSessionCostsFrame_Closed extends BridgeSessionCostsFrame {
  const BridgeSessionCostsFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionCostsFrame_ClosedCopyWith<BridgeSessionCostsFrame_Closed> get copyWith => _$BridgeSessionCostsFrame_ClosedCopyWithImpl<BridgeSessionCostsFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionCostsFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeSessionCostsFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionCostsFrame_ClosedCopyWith<$Res> implements $BridgeSessionCostsFrameCopyWith<$Res> {
  factory $BridgeSessionCostsFrame_ClosedCopyWith(BridgeSessionCostsFrame_Closed value, $Res Function(BridgeSessionCostsFrame_Closed) _then) = _$BridgeSessionCostsFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeSessionCostsFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeSessionCostsFrame_ClosedCopyWith<$Res> {
  _$BridgeSessionCostsFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeSessionCostsFrame_Closed _self;
  final $Res Function(BridgeSessionCostsFrame_Closed) _then;

/// Create a copy of BridgeSessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeSessionCostsFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
