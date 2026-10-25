// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdatesEvent {

 ProductProjectionStamp get stamp; UpdatesHeader get value;
/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesEventCopyWith<UpdatesEvent> get copyWith => _$UpdatesEventCopyWithImpl<UpdatesEvent>(this as UpdatesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as UpdatesEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as UpdatesEvent;
  return 'UpdatesEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $UpdatesEventCopyWith<$Res>  {
  factory $UpdatesEventCopyWith(UpdatesEvent value, $Res Function(UpdatesEvent) _then) = _$UpdatesEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, UpdatesHeader value
});


$ProductProjectionStampCopyWith<$Res> get stamp;$UpdatesHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$UpdatesEventCopyWithImpl<$Res>
    implements $UpdatesEventCopyWith<$Res> {
  _$UpdatesEventCopyWithImpl(this._self, this._then);

  final UpdatesEvent _self;
  final $Res Function(UpdatesEvent) _then;

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as UpdatesHeader,
  ));
}
/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesHeaderCopyWith<$Res> get value {

  return $UpdatesHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatesEvent].
extension UpdatesEventPatterns on UpdatesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UpdatesBaselineEvent value)?  baseline,TResult Function( UpdatesReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UpdatesBaselineEvent() when baseline != null:
return baseline(_that);case UpdatesReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UpdatesBaselineEvent value)  baseline,required TResult Function( UpdatesReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case UpdatesBaselineEvent():
return baseline(_that);case UpdatesReplaceEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UpdatesBaselineEvent value)?  baseline,TResult? Function( UpdatesReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case UpdatesBaselineEvent() when baseline != null:
return baseline(_that);case UpdatesReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  UpdatesHeader value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  UpdatesHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UpdatesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case UpdatesReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  UpdatesHeader value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  UpdatesHeader value)  replace,}) {final _that = this;
switch (_that) {
case UpdatesBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case UpdatesReplaceEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  UpdatesHeader value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  UpdatesHeader value)?  replace,}) {final _that = this;
switch (_that) {
case UpdatesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case UpdatesReplaceEvent() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UpdatesBaselineEvent implements UpdatesEvent {
  const UpdatesBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  UpdatesHeader value;

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesBaselineEventCopyWith<UpdatesBaselineEvent> get copyWith => _$UpdatesBaselineEventCopyWithImpl<UpdatesBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'UpdatesEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $UpdatesBaselineEventCopyWith<$Res> implements $UpdatesEventCopyWith<$Res> {
  factory $UpdatesBaselineEventCopyWith(UpdatesBaselineEvent value, $Res Function(UpdatesBaselineEvent) _then) = _$UpdatesBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, UpdatesHeader value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $UpdatesHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$UpdatesBaselineEventCopyWithImpl<$Res>
    implements $UpdatesBaselineEventCopyWith<$Res> {
  _$UpdatesBaselineEventCopyWithImpl(this._self, this._then);

  final UpdatesBaselineEvent _self;
  final $Res Function(UpdatesBaselineEvent) _then;

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(UpdatesBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as UpdatesHeader,
  ));
}

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesHeaderCopyWith<$Res> get value {

  return $UpdatesHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class UpdatesReplaceEvent implements UpdatesEvent {
  const UpdatesReplaceEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  UpdatesHeader value;

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesReplaceEventCopyWith<UpdatesReplaceEvent> get copyWith => _$UpdatesReplaceEventCopyWithImpl<UpdatesReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'UpdatesEvent.replace(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $UpdatesReplaceEventCopyWith<$Res> implements $UpdatesEventCopyWith<$Res> {
  factory $UpdatesReplaceEventCopyWith(UpdatesReplaceEvent value, $Res Function(UpdatesReplaceEvent) _then) = _$UpdatesReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, UpdatesHeader value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $UpdatesHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$UpdatesReplaceEventCopyWithImpl<$Res>
    implements $UpdatesReplaceEventCopyWith<$Res> {
  _$UpdatesReplaceEventCopyWithImpl(this._self, this._then);

  final UpdatesReplaceEvent _self;
  final $Res Function(UpdatesReplaceEvent) _then;

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(UpdatesReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as UpdatesHeader,
  ));
}

/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of UpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesHeaderCopyWith<$Res> get value {

  return $UpdatesHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$UpdatesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $UpdatesFrameCopyWith<$Res>  {
$UpdatesFrameCopyWith(UpdatesFrame _, $Res Function(UpdatesFrame) __);
}


/// Adds pattern-matching-related methods to [UpdatesFrame].
extension UpdatesFramePatterns on UpdatesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UpdatesData value)?  data,TResult Function( UpdatesResyncRequired value)?  resyncRequired,TResult Function( UpdatesFeedFailure value)?  failure,TResult Function( UpdatesClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UpdatesData() when data != null:
return data(_that);case UpdatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case UpdatesFeedFailure() when failure != null:
return failure(_that);case UpdatesClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UpdatesData value)  data,required TResult Function( UpdatesResyncRequired value)  resyncRequired,required TResult Function( UpdatesFeedFailure value)  failure,required TResult Function( UpdatesClosed value)  closed,}){
final _that = this;
switch (_that) {
case UpdatesData():
return data(_that);case UpdatesResyncRequired():
return resyncRequired(_that);case UpdatesFeedFailure():
return failure(_that);case UpdatesClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UpdatesData value)?  data,TResult? Function( UpdatesResyncRequired value)?  resyncRequired,TResult? Function( UpdatesFeedFailure value)?  failure,TResult? Function( UpdatesClosed value)?  closed,}){
final _that = this;
switch (_that) {
case UpdatesData() when data != null:
return data(_that);case UpdatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case UpdatesFeedFailure() when failure != null:
return failure(_that);case UpdatesClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  UpdatesEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UpdatesData() when data != null:
return data(_that.deliverySequence,_that.event);case UpdatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case UpdatesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case UpdatesClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  UpdatesEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case UpdatesData():
return data(_that.deliverySequence,_that.event);case UpdatesResyncRequired():
return resyncRequired(_that.identity,_that.reason);case UpdatesFeedFailure():
return failure(_that.identity,_that.error);case UpdatesClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  UpdatesEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case UpdatesData() when data != null:
return data(_that.deliverySequence,_that.event);case UpdatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case UpdatesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case UpdatesClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class UpdatesData implements UpdatesFrame {
  const UpdatesData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  UpdatesEvent event;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesDataCopyWith<UpdatesData> get copyWith => _$UpdatesDataCopyWithImpl<UpdatesData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $UpdatesDataCopyWith<$Res> implements $UpdatesFrameCopyWith<$Res> {
  factory $UpdatesDataCopyWith(UpdatesData value, $Res Function(UpdatesData) _then) = _$UpdatesDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, UpdatesEvent event
});


$UpdatesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$UpdatesDataCopyWithImpl<$Res>
    implements $UpdatesDataCopyWith<$Res> {
  _$UpdatesDataCopyWithImpl(this._self, this._then);

  final UpdatesData _self;
  final $Res Function(UpdatesData) _then;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(UpdatesData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as UpdatesEvent,
  ));
}

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesEventCopyWith<$Res> get event {

  return $UpdatesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class UpdatesResyncRequired implements UpdatesFrame {
  const UpdatesResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesResyncRequiredCopyWith<UpdatesResyncRequired> get copyWith => _$UpdatesResyncRequiredCopyWithImpl<UpdatesResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $UpdatesResyncRequiredCopyWith<$Res> implements $UpdatesFrameCopyWith<$Res> {
  factory $UpdatesResyncRequiredCopyWith(UpdatesResyncRequired value, $Res Function(UpdatesResyncRequired) _then) = _$UpdatesResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$UpdatesResyncRequiredCopyWithImpl<$Res>
    implements $UpdatesResyncRequiredCopyWith<$Res> {
  _$UpdatesResyncRequiredCopyWithImpl(this._self, this._then);

  final UpdatesResyncRequired _self;
  final $Res Function(UpdatesResyncRequired) _then;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(UpdatesResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class UpdatesFeedFailure implements UpdatesFrame {
  const UpdatesFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesFeedFailureCopyWith<UpdatesFeedFailure> get copyWith => _$UpdatesFeedFailureCopyWithImpl<UpdatesFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $UpdatesFeedFailureCopyWith<$Res> implements $UpdatesFrameCopyWith<$Res> {
  factory $UpdatesFeedFailureCopyWith(UpdatesFeedFailure value, $Res Function(UpdatesFeedFailure) _then) = _$UpdatesFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$UpdatesFeedFailureCopyWithImpl<$Res>
    implements $UpdatesFeedFailureCopyWith<$Res> {
  _$UpdatesFeedFailureCopyWithImpl(this._self, this._then);

  final UpdatesFeedFailure _self;
  final $Res Function(UpdatesFeedFailure) _then;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(UpdatesFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class UpdatesClosed implements UpdatesFrame {
  const UpdatesClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesClosedCopyWith<UpdatesClosed> get copyWith => _$UpdatesClosedCopyWithImpl<UpdatesClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $UpdatesClosedCopyWith<$Res> implements $UpdatesFrameCopyWith<$Res> {
  factory $UpdatesClosedCopyWith(UpdatesClosed value, $Res Function(UpdatesClosed) _then) = _$UpdatesClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$UpdatesClosedCopyWithImpl<$Res>
    implements $UpdatesClosedCopyWith<$Res> {
  _$UpdatesClosedCopyWithImpl(this._self, this._then);

  final UpdatesClosed _self;
  final $Res Function(UpdatesClosed) _then;

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(UpdatesClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of UpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

// dart format on
