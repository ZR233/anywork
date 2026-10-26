// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'modes_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeCatalogFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ModeCatalogFrameCopyWith<$Res>  {
$ModeCatalogFrameCopyWith(ModeCatalogFrame _, $Res Function(ModeCatalogFrame) __);
}


/// Adds pattern-matching-related methods to [ModeCatalogFrame].
extension ModeCatalogFramePatterns on ModeCatalogFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModeCatalogData value)?  data,TResult Function( ModeCatalogResyncRequired value)?  resyncRequired,TResult Function( ModeCatalogFeedFailure value)?  failure,TResult Function( ModeCatalogClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModeCatalogData() when data != null:
return data(_that);case ModeCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ModeCatalogFeedFailure() when failure != null:
return failure(_that);case ModeCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModeCatalogData value)  data,required TResult Function( ModeCatalogResyncRequired value)  resyncRequired,required TResult Function( ModeCatalogFeedFailure value)  failure,required TResult Function( ModeCatalogClosed value)  closed,}){
final _that = this;
switch (_that) {
case ModeCatalogData():
return data(_that);case ModeCatalogResyncRequired():
return resyncRequired(_that);case ModeCatalogFeedFailure():
return failure(_that);case ModeCatalogClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModeCatalogData value)?  data,TResult? Function( ModeCatalogResyncRequired value)?  resyncRequired,TResult? Function( ModeCatalogFeedFailure value)?  failure,TResult? Function( ModeCatalogClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ModeCatalogData() when data != null:
return data(_that);case ModeCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ModeCatalogFeedFailure() when failure != null:
return failure(_that);case ModeCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ModeCatalogEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModeCatalogData() when data != null:
return data(_that.deliverySequence,_that.event);case ModeCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ModeCatalogFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ModeCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ModeCatalogEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case ModeCatalogData():
return data(_that.deliverySequence,_that.event);case ModeCatalogResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ModeCatalogFeedFailure():
return failure(_that.identity,_that.error);case ModeCatalogClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ModeCatalogEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ModeCatalogData() when data != null:
return data(_that.deliverySequence,_that.event);case ModeCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ModeCatalogFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ModeCatalogClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ModeCatalogData implements ModeCatalogFrame {
  const ModeCatalogData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ModeCatalogEvent event;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogDataCopyWith<ModeCatalogData> get copyWith => _$ModeCatalogDataCopyWithImpl<ModeCatalogData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ModeCatalogDataCopyWith<$Res> implements $ModeCatalogFrameCopyWith<$Res> {
  factory $ModeCatalogDataCopyWith(ModeCatalogData value, $Res Function(ModeCatalogData) _then) = _$ModeCatalogDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ModeCatalogEvent event
});


$ModeCatalogEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ModeCatalogDataCopyWithImpl<$Res>
    implements $ModeCatalogDataCopyWith<$Res> {
  _$ModeCatalogDataCopyWithImpl(this._self, this._then);

  final ModeCatalogData _self;
  final $Res Function(ModeCatalogData) _then;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ModeCatalogData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ModeCatalogEvent,
  ));
}

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogEventCopyWith<$Res> get event {

  return $ModeCatalogEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ModeCatalogResyncRequired implements ModeCatalogFrame {
  const ModeCatalogResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogResyncRequiredCopyWith<ModeCatalogResyncRequired> get copyWith => _$ModeCatalogResyncRequiredCopyWithImpl<ModeCatalogResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ModeCatalogResyncRequiredCopyWith<$Res> implements $ModeCatalogFrameCopyWith<$Res> {
  factory $ModeCatalogResyncRequiredCopyWith(ModeCatalogResyncRequired value, $Res Function(ModeCatalogResyncRequired) _then) = _$ModeCatalogResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ModeCatalogResyncRequiredCopyWithImpl<$Res>
    implements $ModeCatalogResyncRequiredCopyWith<$Res> {
  _$ModeCatalogResyncRequiredCopyWithImpl(this._self, this._then);

  final ModeCatalogResyncRequired _self;
  final $Res Function(ModeCatalogResyncRequired) _then;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ModeCatalogResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of ModeCatalogFrame
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


class ModeCatalogFeedFailure implements ModeCatalogFrame {
  const ModeCatalogFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogFeedFailureCopyWith<ModeCatalogFeedFailure> get copyWith => _$ModeCatalogFeedFailureCopyWithImpl<ModeCatalogFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ModeCatalogFeedFailureCopyWith<$Res> implements $ModeCatalogFrameCopyWith<$Res> {
  factory $ModeCatalogFeedFailureCopyWith(ModeCatalogFeedFailure value, $Res Function(ModeCatalogFeedFailure) _then) = _$ModeCatalogFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ModeCatalogFeedFailureCopyWithImpl<$Res>
    implements $ModeCatalogFeedFailureCopyWith<$Res> {
  _$ModeCatalogFeedFailureCopyWithImpl(this._self, this._then);

  final ModeCatalogFeedFailure _self;
  final $Res Function(ModeCatalogFeedFailure) _then;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ModeCatalogFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ModeCatalogFrame
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


class ModeCatalogClosed implements ModeCatalogFrame {
  const ModeCatalogClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogClosedCopyWith<ModeCatalogClosed> get copyWith => _$ModeCatalogClosedCopyWithImpl<ModeCatalogClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ModeCatalogClosedCopyWith<$Res> implements $ModeCatalogFrameCopyWith<$Res> {
  factory $ModeCatalogClosedCopyWith(ModeCatalogClosed value, $Res Function(ModeCatalogClosed) _then) = _$ModeCatalogClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ModeCatalogClosedCopyWithImpl<$Res>
    implements $ModeCatalogClosedCopyWith<$Res> {
  _$ModeCatalogClosedCopyWithImpl(this._self, this._then);

  final ModeCatalogClosed _self;
  final $Res Function(ModeCatalogClosed) _then;

/// Create a copy of ModeCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ModeCatalogClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of ModeCatalogFrame
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
mixin _$ModeCatalogEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogEventCopyWith<ModeCatalogEvent> get copyWith => _$ModeCatalogEventCopyWithImpl<ModeCatalogEvent>(this as ModeCatalogEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ModeCatalogEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $ModeCatalogEventCopyWith<$Res>  {
  factory $ModeCatalogEventCopyWith(ModeCatalogEvent value, $Res Function(ModeCatalogEvent) _then) = _$ModeCatalogEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ModeCatalogEventCopyWithImpl<$Res>
    implements $ModeCatalogEventCopyWith<$Res> {
  _$ModeCatalogEventCopyWithImpl(this._self, this._then);

  final ModeCatalogEvent _self;
  final $Res Function(ModeCatalogEvent) _then;

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogEvent].
extension ModeCatalogEventPatterns on ModeCatalogEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModeCatalogBaselineEvent value)?  baseline,TResult Function( ModeCatalogChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent() when baseline != null:
return baseline(_that);case ModeCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModeCatalogBaselineEvent value)  baseline,required TResult Function( ModeCatalogChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent():
return baseline(_that);case ModeCatalogChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModeCatalogBaselineEvent value)?  baseline,TResult? Function( ModeCatalogChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent() when baseline != null:
return baseline(_that);case ModeCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModeCatalogBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ModeCatalogChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ModeCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModeCatalogBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ModeCatalogChange value)  change,}) {final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ModeCatalogChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModeCatalogBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  ModeCatalogChange value)?  change,}) {final _that = this;
switch (_that) {
case ModeCatalogBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ModeCatalogChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ModeCatalogBaselineEvent implements ModeCatalogEvent {
  const ModeCatalogBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  ModeCatalogBaseline value;

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogBaselineEventCopyWith<ModeCatalogBaselineEvent> get copyWith => _$ModeCatalogBaselineEventCopyWithImpl<ModeCatalogBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ModeCatalogBaselineEventCopyWith<$Res> implements $ModeCatalogEventCopyWith<$Res> {
  factory $ModeCatalogBaselineEventCopyWith(ModeCatalogBaselineEvent value, $Res Function(ModeCatalogBaselineEvent) _then) = _$ModeCatalogBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, ModeCatalogBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$ModeCatalogBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ModeCatalogBaselineEventCopyWithImpl<$Res>
    implements $ModeCatalogBaselineEventCopyWith<$Res> {
  _$ModeCatalogBaselineEventCopyWithImpl(this._self, this._then);

  final ModeCatalogBaselineEvent _self;
  final $Res Function(ModeCatalogBaselineEvent) _then;

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ModeCatalogBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModeCatalogBaseline,
  ));
}

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogBaselineCopyWith<$Res> get value {

  return $ModeCatalogBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ModeCatalogChangeEvent implements ModeCatalogEvent {
  const ModeCatalogChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  ModeCatalogChange value;

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogChangeEventCopyWith<ModeCatalogChangeEvent> get copyWith => _$ModeCatalogChangeEventCopyWithImpl<ModeCatalogChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $ModeCatalogChangeEventCopyWith<$Res> implements $ModeCatalogEventCopyWith<$Res> {
  factory $ModeCatalogChangeEventCopyWith(ModeCatalogChangeEvent value, $Res Function(ModeCatalogChangeEvent) _then) = _$ModeCatalogChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, ModeCatalogChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$ModeCatalogChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ModeCatalogChangeEventCopyWithImpl<$Res>
    implements $ModeCatalogChangeEventCopyWith<$Res> {
  _$ModeCatalogChangeEventCopyWithImpl(this._self, this._then);

  final ModeCatalogChangeEvent _self;
  final $Res Function(ModeCatalogChangeEvent) _then;

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ModeCatalogChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModeCatalogChange,
  ));
}

/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ModeCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogChangeCopyWith<$Res> get value {

  return $ModeCatalogChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogBaseline {

 ModeCatalogHeader get header; ProductCollectionRef? get collection;
/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogBaselineCopyWith<ModeCatalogBaseline> get copyWith => _$ModeCatalogBaselineCopyWithImpl<ModeCatalogBaseline>(this as ModeCatalogBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as ModeCatalogBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $ModeCatalogBaselineCopyWith<$Res>  {
  factory $ModeCatalogBaselineCopyWith(ModeCatalogBaseline value, $Res Function(ModeCatalogBaseline) _then) = _$ModeCatalogBaselineCopyWithImpl;
@useResult
$Res call({
 ModeCatalogHeader header, ProductCollectionRef? collection
});


$ModeCatalogHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ModeCatalogBaselineCopyWithImpl<$Res>
    implements $ModeCatalogBaselineCopyWith<$Res> {
  _$ModeCatalogBaselineCopyWithImpl(this._self, this._then);

  final ModeCatalogBaseline _self;
  final $Res Function(ModeCatalogBaseline) _then;

/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(ModeCatalogBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModeCatalogHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogHeaderCopyWith<$Res> get header {

  return $ModeCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogBaseline].
extension ModeCatalogBaselinePatterns on ModeCatalogBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogBaseline() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogBaseline():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogBaseline() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeCatalogHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeCatalogHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogBaseline():
return $default(_that.header,_that.collection);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeCatalogHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogBaseline implements ModeCatalogBaseline {
  const _ModeCatalogBaseline({required this.header, required this.collection});


@override final  ModeCatalogHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogBaselineCopyWith<_ModeCatalogBaseline> get copyWith => __$ModeCatalogBaselineCopyWithImpl<_ModeCatalogBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$ModeCatalogBaselineCopyWith<$Res> implements $ModeCatalogBaselineCopyWith<$Res> {
  factory _$ModeCatalogBaselineCopyWith(_ModeCatalogBaseline value, $Res Function(_ModeCatalogBaseline) _then) = __$ModeCatalogBaselineCopyWithImpl;
@override @useResult
$Res call({
 ModeCatalogHeader header, ProductCollectionRef? collection
});


@override $ModeCatalogHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ModeCatalogBaselineCopyWithImpl<$Res>
    implements _$ModeCatalogBaselineCopyWith<$Res> {
  __$ModeCatalogBaselineCopyWithImpl(this._self, this._then);

  final _ModeCatalogBaseline _self;
  final $Res Function(_ModeCatalogBaseline) _then;

/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_ModeCatalogBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModeCatalogHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogHeaderCopyWith<$Res> get header {

  return $ModeCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModeCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogChange {

 ModeCatalogHeader get header; int? get baseCollectionRevision; ProductCollectionRef? get collection; List<ProductEntityRef> get upserted; List<int> get removedEntries;
/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogChangeCopyWith<ModeCatalogChange> get copyWith => _$ModeCatalogChangeCopyWithImpl<ModeCatalogChange>(this as ModeCatalogChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as ModeCatalogChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $ModeCatalogChangeCopyWith<$Res>  {
  factory $ModeCatalogChangeCopyWith(ModeCatalogChange value, $Res Function(ModeCatalogChange) _then) = _$ModeCatalogChangeCopyWithImpl;
@useResult
$Res call({
 ModeCatalogHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$ModeCatalogHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ModeCatalogChangeCopyWithImpl<$Res>
    implements $ModeCatalogChangeCopyWith<$Res> {
  _$ModeCatalogChangeCopyWithImpl(this._self, this._then);

  final ModeCatalogChange _self;
  final $Res Function(ModeCatalogChange) _then;

/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(ModeCatalogChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModeCatalogHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogHeaderCopyWith<$Res> get header {

  return $ModeCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogChange].
extension ModeCatalogChangePatterns on ModeCatalogChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogChange value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogChange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogChange value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeCatalogHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeCatalogHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogChange():
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeCatalogHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogChange implements ModeCatalogChange {
  const _ModeCatalogChange({required this.header, required this.baseCollectionRevision, required this.collection, required  List<ProductEntityRef> upserted, required  List<int> removedEntries}): _upserted = upserted,_removedEntries = removedEntries;


@override final  ModeCatalogHeader header;
@override final  int? baseCollectionRevision;
@override final  ProductCollectionRef? collection;
 final  List<ProductEntityRef> _upserted;
@override List<ProductEntityRef> get upserted {
  if (_upserted is EqualUnmodifiableListView) return _upserted;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_upserted);
}

 final  List<int> _removedEntries;
@override List<int> get removedEntries {
  if (_removedEntries is EqualUnmodifiableListView) return _removedEntries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_removedEntries);
}


/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogChangeCopyWith<_ModeCatalogChange> get copyWith => __$ModeCatalogChangeCopyWithImpl<_ModeCatalogChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogChange&&(identical(other.header, header) || other.header == header)&&(identical(other.baseCollectionRevision, baseCollectionRevision) || other.baseCollectionRevision == baseCollectionRevision)&&(identical(other.collection, collection) || other.collection == collection)&&const DeepCollectionEquality().equals(other.upserted, _upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _removedEntries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,baseCollectionRevision,collection,const DeepCollectionEquality().hash(_upserted),const DeepCollectionEquality().hash(_removedEntries));
}



}

/// @nodoc
abstract mixin class _$ModeCatalogChangeCopyWith<$Res> implements $ModeCatalogChangeCopyWith<$Res> {
  factory _$ModeCatalogChangeCopyWith(_ModeCatalogChange value, $Res Function(_ModeCatalogChange) _then) = __$ModeCatalogChangeCopyWithImpl;
@override @useResult
$Res call({
 ModeCatalogHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


@override $ModeCatalogHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ModeCatalogChangeCopyWithImpl<$Res>
    implements _$ModeCatalogChangeCopyWith<$Res> {
  __$ModeCatalogChangeCopyWithImpl(this._self, this._then);

  final _ModeCatalogChange _self;
  final $Res Function(_ModeCatalogChange) _then;

/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(_ModeCatalogChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModeCatalogHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self._upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self._removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogHeaderCopyWith<$Res> get header {

  return $ModeCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModeCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

// dart format on
