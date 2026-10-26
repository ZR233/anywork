// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeBotsEvent {

 BridgeProductProjectionStamp get stamp; BridgeBotsHeader get header; BridgeBotsStateSnapshot? get state;
/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsEventCopyWith<BridgeBotsEvent> get copyWith => _$BridgeBotsEventCopyWithImpl<BridgeBotsEvent>(this as BridgeBotsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeBotsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as BridgeBotsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.header,_this.state);
}

@override
String toString() {
  final _this = this as BridgeBotsEvent;
  return 'BridgeBotsEvent(stamp: ${_this.stamp}, header: ${_this.header}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $BridgeBotsEventCopyWith<$Res>  {
  factory $BridgeBotsEventCopyWith(BridgeBotsEvent value, $Res Function(BridgeBotsEvent) _then) = _$BridgeBotsEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgeBotsHeader header, BridgeBotsStateSnapshot? state
});




}
/// @nodoc
class _$BridgeBotsEventCopyWithImpl<$Res>
    implements $BridgeBotsEventCopyWith<$Res> {
  _$BridgeBotsEventCopyWithImpl(this._self, this._then);

  final BridgeBotsEvent _self;
  final $Res Function(BridgeBotsEvent) _then;

/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? header = null,Object? state = freezed,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BridgeBotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeBotsStateSnapshot?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeBotsEvent].
extension BridgeBotsEventPatterns on BridgeBotsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotsEvent_Baseline value)?  baseline,TResult Function( BridgeBotsEvent_StateChanged value)?  stateChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeBotsEvent_StateChanged() when stateChanged != null:
return stateChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotsEvent_Baseline value)  baseline,required TResult Function( BridgeBotsEvent_StateChanged value)  stateChanged,}){
final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline():
return baseline(_that);case BridgeBotsEvent_StateChanged():
return stateChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotsEvent_Baseline value)?  baseline,TResult? Function( BridgeBotsEvent_StateChanged value)?  stateChanged,}){
final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeBotsEvent_StateChanged() when stateChanged != null:
return stateChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)?  stateChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BridgeBotsEvent_StateChanged() when stateChanged != null:
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)  stateChanged,}) {final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BridgeBotsEvent_StateChanged():
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeBotsHeader header,  BridgeBotsStateSnapshot? state)?  stateChanged,}) {final _that = this;
switch (_that) {
case BridgeBotsEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BridgeBotsEvent_StateChanged() when stateChanged != null:
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotsEvent_Baseline extends BridgeBotsEvent {
  const BridgeBotsEvent_Baseline({required this.identity, required this.stamp, required this.header, this.state}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeBotsHeader header;
@override final  BridgeBotsStateSnapshot? state;

/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsEvent_BaselineCopyWith<BridgeBotsEvent_Baseline> get copyWith => _$BridgeBotsEvent_BaselineCopyWithImpl<BridgeBotsEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.header, header) || other.header == header)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,header,state);
}

@override
String toString() {
    return 'BridgeBotsEvent.baseline(identity: $identity, stamp: $stamp, header: $header, state: $state)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsEvent_BaselineCopyWith<$Res> implements $BridgeBotsEventCopyWith<$Res> {
  factory $BridgeBotsEvent_BaselineCopyWith(BridgeBotsEvent_Baseline value, $Res Function(BridgeBotsEvent_Baseline) _then) = _$BridgeBotsEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeBotsHeader header, BridgeBotsStateSnapshot? state
});




}
/// @nodoc
class _$BridgeBotsEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeBotsEvent_BaselineCopyWith<$Res> {
  _$BridgeBotsEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeBotsEvent_Baseline _self;
  final $Res Function(BridgeBotsEvent_Baseline) _then;

/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? header = null,Object? state = freezed,}) {
  return _then(BridgeBotsEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BridgeBotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeBotsStateSnapshot?,
  ));
}


}

/// @nodoc


class BridgeBotsEvent_StateChanged extends BridgeBotsEvent {
  const BridgeBotsEvent_StateChanged({required this.stamp, required this.baseRevision, required this.header, this.state}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeBotsHeader header;
@override final  BridgeBotsStateSnapshot? state;

/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsEvent_StateChangedCopyWith<BridgeBotsEvent_StateChanged> get copyWith => _$BridgeBotsEvent_StateChangedCopyWithImpl<BridgeBotsEvent_StateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsEvent_StateChanged&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.header, header) || other.header == header)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,header,state);
}

@override
String toString() {
    return 'BridgeBotsEvent.stateChanged(stamp: $stamp, baseRevision: $baseRevision, header: $header, state: $state)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsEvent_StateChangedCopyWith<$Res> implements $BridgeBotsEventCopyWith<$Res> {
  factory $BridgeBotsEvent_StateChangedCopyWith(BridgeBotsEvent_StateChanged value, $Res Function(BridgeBotsEvent_StateChanged) _then) = _$BridgeBotsEvent_StateChangedCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeBotsHeader header, BridgeBotsStateSnapshot? state
});




}
/// @nodoc
class _$BridgeBotsEvent_StateChangedCopyWithImpl<$Res>
    implements $BridgeBotsEvent_StateChangedCopyWith<$Res> {
  _$BridgeBotsEvent_StateChangedCopyWithImpl(this._self, this._then);

  final BridgeBotsEvent_StateChanged _self;
  final $Res Function(BridgeBotsEvent_StateChanged) _then;

/// Create a copy of BridgeBotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? header = null,Object? state = freezed,}) {
  return _then(BridgeBotsEvent_StateChanged(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BridgeBotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeBotsStateSnapshot?,
  ));
}


}

/// @nodoc
mixin _$BridgeBotsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotsFrame()';
}


}

/// @nodoc
class $BridgeBotsFrameCopyWith<$Res>  {
$BridgeBotsFrameCopyWith(BridgeBotsFrame _, $Res Function(BridgeBotsFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeBotsFrame].
extension BridgeBotsFramePatterns on BridgeBotsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotsFrame_Data value)?  data,TResult Function( BridgeBotsFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeBotsFrame_Failure value)?  failure,TResult Function( BridgeBotsFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotsFrame_Data() when data != null:
return data(_that);case BridgeBotsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeBotsFrame_Failure() when failure != null:
return failure(_that);case BridgeBotsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotsFrame_Data value)  data,required TResult Function( BridgeBotsFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeBotsFrame_Failure value)  failure,required TResult Function( BridgeBotsFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeBotsFrame_Data():
return data(_that);case BridgeBotsFrame_ResyncRequired():
return resyncRequired(_that);case BridgeBotsFrame_Failure():
return failure(_that);case BridgeBotsFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotsFrame_Data value)?  data,TResult? Function( BridgeBotsFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeBotsFrame_Failure value)?  failure,TResult? Function( BridgeBotsFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeBotsFrame_Data() when data != null:
return data(_that);case BridgeBotsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeBotsFrame_Failure() when failure != null:
return failure(_that);case BridgeBotsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeBotsEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeBotsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeBotsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeBotsFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeBotsEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeBotsFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeBotsFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeBotsFrame_Failure():
return failure(_that.identity,_that.error);case BridgeBotsFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeBotsEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeBotsFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeBotsFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeBotsFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeBotsFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotsFrame_Data extends BridgeBotsFrame {
  const BridgeBotsFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeBotsEvent event;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsFrame_DataCopyWith<BridgeBotsFrame_Data> get copyWith => _$BridgeBotsFrame_DataCopyWithImpl<BridgeBotsFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeBotsFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsFrame_DataCopyWith<$Res> implements $BridgeBotsFrameCopyWith<$Res> {
  factory $BridgeBotsFrame_DataCopyWith(BridgeBotsFrame_Data value, $Res Function(BridgeBotsFrame_Data) _then) = _$BridgeBotsFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeBotsEvent event
});


$BridgeBotsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeBotsFrame_DataCopyWithImpl<$Res>
    implements $BridgeBotsFrame_DataCopyWith<$Res> {
  _$BridgeBotsFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeBotsFrame_Data _self;
  final $Res Function(BridgeBotsFrame_Data) _then;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeBotsFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeBotsEvent,
  ));
}

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBotsEventCopyWith<$Res> get event {

  return $BridgeBotsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeBotsFrame_ResyncRequired extends BridgeBotsFrame {
  const BridgeBotsFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsFrame_ResyncRequiredCopyWith<BridgeBotsFrame_ResyncRequired> get copyWith => _$BridgeBotsFrame_ResyncRequiredCopyWithImpl<BridgeBotsFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeBotsFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsFrame_ResyncRequiredCopyWith<$Res> implements $BridgeBotsFrameCopyWith<$Res> {
  factory $BridgeBotsFrame_ResyncRequiredCopyWith(BridgeBotsFrame_ResyncRequired value, $Res Function(BridgeBotsFrame_ResyncRequired) _then) = _$BridgeBotsFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeBotsFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeBotsFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeBotsFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeBotsFrame_ResyncRequired _self;
  final $Res Function(BridgeBotsFrame_ResyncRequired) _then;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeBotsFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeBotsFrame_Failure extends BridgeBotsFrame {
  const BridgeBotsFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsFrame_FailureCopyWith<BridgeBotsFrame_Failure> get copyWith => _$BridgeBotsFrame_FailureCopyWithImpl<BridgeBotsFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeBotsFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsFrame_FailureCopyWith<$Res> implements $BridgeBotsFrameCopyWith<$Res> {
  factory $BridgeBotsFrame_FailureCopyWith(BridgeBotsFrame_Failure value, $Res Function(BridgeBotsFrame_Failure) _then) = _$BridgeBotsFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeBotsFrame_FailureCopyWithImpl<$Res>
    implements $BridgeBotsFrame_FailureCopyWith<$Res> {
  _$BridgeBotsFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeBotsFrame_Failure _self;
  final $Res Function(BridgeBotsFrame_Failure) _then;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeBotsFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeBotsFrame_Closed extends BridgeBotsFrame {
  const BridgeBotsFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotsFrame_ClosedCopyWith<BridgeBotsFrame_Closed> get copyWith => _$BridgeBotsFrame_ClosedCopyWithImpl<BridgeBotsFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotsFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeBotsFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotsFrame_ClosedCopyWith<$Res> implements $BridgeBotsFrameCopyWith<$Res> {
  factory $BridgeBotsFrame_ClosedCopyWith(BridgeBotsFrame_Closed value, $Res Function(BridgeBotsFrame_Closed) _then) = _$BridgeBotsFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeBotsFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeBotsFrame_ClosedCopyWith<$Res> {
  _$BridgeBotsFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeBotsFrame_Closed _self;
  final $Res Function(BridgeBotsFrame_Closed) _then;

/// Create a copy of BridgeBotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeBotsFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
