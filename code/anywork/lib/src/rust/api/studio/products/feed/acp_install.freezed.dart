// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_install.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpInstallEvent {

 BridgeProductProjectionStamp get stamp; BridgeAcpInstallSnapshot get value;
/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallEventCopyWith<BridgeAcpInstallEvent> get copyWith => _$BridgeAcpInstallEventCopyWithImpl<BridgeAcpInstallEvent>(this as BridgeAcpInstallEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpInstallEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAcpInstallEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeAcpInstallEvent;
  return 'BridgeAcpInstallEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallEventCopyWith<$Res>  {
  factory $BridgeAcpInstallEventCopyWith(BridgeAcpInstallEvent value, $Res Function(BridgeAcpInstallEvent) _then) = _$BridgeAcpInstallEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgeAcpInstallSnapshot value
});




}
/// @nodoc
class _$BridgeAcpInstallEventCopyWithImpl<$Res>
    implements $BridgeAcpInstallEventCopyWith<$Res> {
  _$BridgeAcpInstallEventCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallEvent _self;
  final $Res Function(BridgeAcpInstallEvent) _then;

/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallSnapshot,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAcpInstallEvent].
extension BridgeAcpInstallEventPatterns on BridgeAcpInstallEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpInstallEvent_Baseline value)?  baseline,TResult Function( BridgeAcpInstallEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAcpInstallEvent_Change() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpInstallEvent_Baseline value)  baseline,required TResult Function( BridgeAcpInstallEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline():
return baseline(_that);case BridgeAcpInstallEvent_Change():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpInstallEvent_Baseline value)?  baseline,TResult? Function( BridgeAcpInstallEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeAcpInstallEvent_Change() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpInstallSnapshot value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpInstallSnapshot value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpInstallEvent_Change() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpInstallSnapshot value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpInstallSnapshot value)  change,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpInstallEvent_Change():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeAcpInstallSnapshot value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeAcpInstallSnapshot value)?  change,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeAcpInstallEvent_Change() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpInstallEvent_Baseline extends BridgeAcpInstallEvent {
  const BridgeAcpInstallEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeAcpInstallSnapshot value;

/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallEvent_BaselineCopyWith<BridgeAcpInstallEvent_Baseline> get copyWith => _$BridgeAcpInstallEvent_BaselineCopyWithImpl<BridgeAcpInstallEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeAcpInstallEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallEvent_BaselineCopyWith<$Res> implements $BridgeAcpInstallEventCopyWith<$Res> {
  factory $BridgeAcpInstallEvent_BaselineCopyWith(BridgeAcpInstallEvent_Baseline value, $Res Function(BridgeAcpInstallEvent_Baseline) _then) = _$BridgeAcpInstallEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeAcpInstallSnapshot value
});




}
/// @nodoc
class _$BridgeAcpInstallEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeAcpInstallEvent_BaselineCopyWith<$Res> {
  _$BridgeAcpInstallEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallEvent_Baseline _self;
  final $Res Function(BridgeAcpInstallEvent_Baseline) _then;

/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeAcpInstallEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallSnapshot,
  ));
}


}

/// @nodoc


class BridgeAcpInstallEvent_Change extends BridgeAcpInstallEvent {
  const BridgeAcpInstallEvent_Change({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeAcpInstallSnapshot value;

/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallEvent_ChangeCopyWith<BridgeAcpInstallEvent_Change> get copyWith => _$BridgeAcpInstallEvent_ChangeCopyWithImpl<BridgeAcpInstallEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallEvent_Change&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeAcpInstallEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallEvent_ChangeCopyWith<$Res> implements $BridgeAcpInstallEventCopyWith<$Res> {
  factory $BridgeAcpInstallEvent_ChangeCopyWith(BridgeAcpInstallEvent_Change value, $Res Function(BridgeAcpInstallEvent_Change) _then) = _$BridgeAcpInstallEvent_ChangeCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeAcpInstallSnapshot value
});




}
/// @nodoc
class _$BridgeAcpInstallEvent_ChangeCopyWithImpl<$Res>
    implements $BridgeAcpInstallEvent_ChangeCopyWith<$Res> {
  _$BridgeAcpInstallEvent_ChangeCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallEvent_Change _self;
  final $Res Function(BridgeAcpInstallEvent_Change) _then;

/// Create a copy of BridgeAcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeAcpInstallEvent_Change(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallSnapshot,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpInstallFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallFrame()';
}


}

/// @nodoc
class $BridgeAcpInstallFrameCopyWith<$Res>  {
$BridgeAcpInstallFrameCopyWith(BridgeAcpInstallFrame _, $Res Function(BridgeAcpInstallFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpInstallFrame].
extension BridgeAcpInstallFramePatterns on BridgeAcpInstallFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpInstallFrame_Data value)?  data,TResult Function( BridgeAcpInstallFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeAcpInstallFrame_Failure value)?  failure,TResult Function( BridgeAcpInstallFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data() when data != null:
return data(_that);case BridgeAcpInstallFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAcpInstallFrame_Failure() when failure != null:
return failure(_that);case BridgeAcpInstallFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpInstallFrame_Data value)  data,required TResult Function( BridgeAcpInstallFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeAcpInstallFrame_Failure value)  failure,required TResult Function( BridgeAcpInstallFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data():
return data(_that);case BridgeAcpInstallFrame_ResyncRequired():
return resyncRequired(_that);case BridgeAcpInstallFrame_Failure():
return failure(_that);case BridgeAcpInstallFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpInstallFrame_Data value)?  data,TResult? Function( BridgeAcpInstallFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeAcpInstallFrame_Failure value)?  failure,TResult? Function( BridgeAcpInstallFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data() when data != null:
return data(_that);case BridgeAcpInstallFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeAcpInstallFrame_Failure() when failure != null:
return failure(_that);case BridgeAcpInstallFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeAcpInstallEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAcpInstallFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAcpInstallFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAcpInstallFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeAcpInstallEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeAcpInstallFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeAcpInstallFrame_Failure():
return failure(_that.identity,_that.error);case BridgeAcpInstallFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeAcpInstallEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeAcpInstallFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeAcpInstallFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeAcpInstallFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpInstallFrame_Data extends BridgeAcpInstallFrame {
  const BridgeAcpInstallFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeAcpInstallEvent event;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallFrame_DataCopyWith<BridgeAcpInstallFrame_Data> get copyWith => _$BridgeAcpInstallFrame_DataCopyWithImpl<BridgeAcpInstallFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeAcpInstallFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallFrame_DataCopyWith<$Res> implements $BridgeAcpInstallFrameCopyWith<$Res> {
  factory $BridgeAcpInstallFrame_DataCopyWith(BridgeAcpInstallFrame_Data value, $Res Function(BridgeAcpInstallFrame_Data) _then) = _$BridgeAcpInstallFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeAcpInstallEvent event
});


$BridgeAcpInstallEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAcpInstallFrame_DataCopyWithImpl<$Res>
    implements $BridgeAcpInstallFrame_DataCopyWith<$Res> {
  _$BridgeAcpInstallFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallFrame_Data _self;
  final $Res Function(BridgeAcpInstallFrame_Data) _then;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeAcpInstallFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallEvent,
  ));
}

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpInstallEventCopyWith<$Res> get event {

  return $BridgeAcpInstallEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeAcpInstallFrame_ResyncRequired extends BridgeAcpInstallFrame {
  const BridgeAcpInstallFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallFrame_ResyncRequiredCopyWith<BridgeAcpInstallFrame_ResyncRequired> get copyWith => _$BridgeAcpInstallFrame_ResyncRequiredCopyWithImpl<BridgeAcpInstallFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAcpInstallFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallFrame_ResyncRequiredCopyWith<$Res> implements $BridgeAcpInstallFrameCopyWith<$Res> {
  factory $BridgeAcpInstallFrame_ResyncRequiredCopyWith(BridgeAcpInstallFrame_ResyncRequired value, $Res Function(BridgeAcpInstallFrame_ResyncRequired) _then) = _$BridgeAcpInstallFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeAcpInstallFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeAcpInstallFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeAcpInstallFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallFrame_ResyncRequired _self;
  final $Res Function(BridgeAcpInstallFrame_ResyncRequired) _then;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAcpInstallFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeAcpInstallFrame_Failure extends BridgeAcpInstallFrame {
  const BridgeAcpInstallFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallFrame_FailureCopyWith<BridgeAcpInstallFrame_Failure> get copyWith => _$BridgeAcpInstallFrame_FailureCopyWithImpl<BridgeAcpInstallFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeAcpInstallFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallFrame_FailureCopyWith<$Res> implements $BridgeAcpInstallFrameCopyWith<$Res> {
  factory $BridgeAcpInstallFrame_FailureCopyWith(BridgeAcpInstallFrame_Failure value, $Res Function(BridgeAcpInstallFrame_Failure) _then) = _$BridgeAcpInstallFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeAcpInstallFrame_FailureCopyWithImpl<$Res>
    implements $BridgeAcpInstallFrame_FailureCopyWith<$Res> {
  _$BridgeAcpInstallFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallFrame_Failure _self;
  final $Res Function(BridgeAcpInstallFrame_Failure) _then;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeAcpInstallFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAcpInstallFrame_Closed extends BridgeAcpInstallFrame {
  const BridgeAcpInstallFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallFrame_ClosedCopyWith<BridgeAcpInstallFrame_Closed> get copyWith => _$BridgeAcpInstallFrame_ClosedCopyWithImpl<BridgeAcpInstallFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeAcpInstallFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallFrame_ClosedCopyWith<$Res> implements $BridgeAcpInstallFrameCopyWith<$Res> {
  factory $BridgeAcpInstallFrame_ClosedCopyWith(BridgeAcpInstallFrame_Closed value, $Res Function(BridgeAcpInstallFrame_Closed) _then) = _$BridgeAcpInstallFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeAcpInstallFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeAcpInstallFrame_ClosedCopyWith<$Res> {
  _$BridgeAcpInstallFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallFrame_Closed _self;
  final $Res Function(BridgeAcpInstallFrame_Closed) _then;

/// Create a copy of BridgeAcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeAcpInstallFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
