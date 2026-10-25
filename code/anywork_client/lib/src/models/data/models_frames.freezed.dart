// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelCatalogFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ModelCatalogFrameCopyWith<$Res>  {
$ModelCatalogFrameCopyWith(ModelCatalogFrame _, $Res Function(ModelCatalogFrame) __);
}


/// Adds pattern-matching-related methods to [ModelCatalogFrame].
extension ModelCatalogFramePatterns on ModelCatalogFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModelCatalogData value)?  data,TResult Function( ModelCatalogResyncRequired value)?  resyncRequired,TResult Function( ModelCatalogFeedFailure value)?  failure,TResult Function( ModelCatalogClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModelCatalogData() when data != null:
return data(_that);case ModelCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ModelCatalogFeedFailure() when failure != null:
return failure(_that);case ModelCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModelCatalogData value)  data,required TResult Function( ModelCatalogResyncRequired value)  resyncRequired,required TResult Function( ModelCatalogFeedFailure value)  failure,required TResult Function( ModelCatalogClosed value)  closed,}){
final _that = this;
switch (_that) {
case ModelCatalogData():
return data(_that);case ModelCatalogResyncRequired():
return resyncRequired(_that);case ModelCatalogFeedFailure():
return failure(_that);case ModelCatalogClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModelCatalogData value)?  data,TResult? Function( ModelCatalogResyncRequired value)?  resyncRequired,TResult? Function( ModelCatalogFeedFailure value)?  failure,TResult? Function( ModelCatalogClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ModelCatalogData() when data != null:
return data(_that);case ModelCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ModelCatalogFeedFailure() when failure != null:
return failure(_that);case ModelCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ModelCatalogEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModelCatalogData() when data != null:
return data(_that.deliverySequence,_that.event);case ModelCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ModelCatalogFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ModelCatalogClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ModelCatalogEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case ModelCatalogData():
return data(_that.deliverySequence,_that.event);case ModelCatalogResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ModelCatalogFeedFailure():
return failure(_that.identity,_that.error);case ModelCatalogClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ModelCatalogEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ModelCatalogData() when data != null:
return data(_that.deliverySequence,_that.event);case ModelCatalogResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ModelCatalogFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ModelCatalogClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ModelCatalogData implements ModelCatalogFrame {
  const ModelCatalogData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ModelCatalogEvent event;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogDataCopyWith<ModelCatalogData> get copyWith => _$ModelCatalogDataCopyWithImpl<ModelCatalogData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ModelCatalogDataCopyWith<$Res> implements $ModelCatalogFrameCopyWith<$Res> {
  factory $ModelCatalogDataCopyWith(ModelCatalogData value, $Res Function(ModelCatalogData) _then) = _$ModelCatalogDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ModelCatalogEvent event
});


$ModelCatalogEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ModelCatalogDataCopyWithImpl<$Res>
    implements $ModelCatalogDataCopyWith<$Res> {
  _$ModelCatalogDataCopyWithImpl(this._self, this._then);

  final ModelCatalogData _self;
  final $Res Function(ModelCatalogData) _then;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ModelCatalogData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ModelCatalogEvent,
  ));
}

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogEventCopyWith<$Res> get event {

  return $ModelCatalogEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ModelCatalogResyncRequired implements ModelCatalogFrame {
  const ModelCatalogResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogResyncRequiredCopyWith<ModelCatalogResyncRequired> get copyWith => _$ModelCatalogResyncRequiredCopyWithImpl<ModelCatalogResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ModelCatalogResyncRequiredCopyWith<$Res> implements $ModelCatalogFrameCopyWith<$Res> {
  factory $ModelCatalogResyncRequiredCopyWith(ModelCatalogResyncRequired value, $Res Function(ModelCatalogResyncRequired) _then) = _$ModelCatalogResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ModelCatalogResyncRequiredCopyWithImpl<$Res>
    implements $ModelCatalogResyncRequiredCopyWith<$Res> {
  _$ModelCatalogResyncRequiredCopyWithImpl(this._self, this._then);

  final ModelCatalogResyncRequired _self;
  final $Res Function(ModelCatalogResyncRequired) _then;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ModelCatalogResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of ModelCatalogFrame
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


class ModelCatalogFeedFailure implements ModelCatalogFrame {
  const ModelCatalogFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogFeedFailureCopyWith<ModelCatalogFeedFailure> get copyWith => _$ModelCatalogFeedFailureCopyWithImpl<ModelCatalogFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ModelCatalogFeedFailureCopyWith<$Res> implements $ModelCatalogFrameCopyWith<$Res> {
  factory $ModelCatalogFeedFailureCopyWith(ModelCatalogFeedFailure value, $Res Function(ModelCatalogFeedFailure) _then) = _$ModelCatalogFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ModelCatalogFeedFailureCopyWithImpl<$Res>
    implements $ModelCatalogFeedFailureCopyWith<$Res> {
  _$ModelCatalogFeedFailureCopyWithImpl(this._self, this._then);

  final ModelCatalogFeedFailure _self;
  final $Res Function(ModelCatalogFeedFailure) _then;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ModelCatalogFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ModelCatalogFrame
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


class ModelCatalogClosed implements ModelCatalogFrame {
  const ModelCatalogClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogClosedCopyWith<ModelCatalogClosed> get copyWith => _$ModelCatalogClosedCopyWithImpl<ModelCatalogClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ModelCatalogClosedCopyWith<$Res> implements $ModelCatalogFrameCopyWith<$Res> {
  factory $ModelCatalogClosedCopyWith(ModelCatalogClosed value, $Res Function(ModelCatalogClosed) _then) = _$ModelCatalogClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ModelCatalogClosedCopyWithImpl<$Res>
    implements $ModelCatalogClosedCopyWith<$Res> {
  _$ModelCatalogClosedCopyWithImpl(this._self, this._then);

  final ModelCatalogClosed _self;
  final $Res Function(ModelCatalogClosed) _then;

/// Create a copy of ModelCatalogFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ModelCatalogClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of ModelCatalogFrame
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
mixin _$ModelCatalogEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogEventCopyWith<ModelCatalogEvent> get copyWith => _$ModelCatalogEventCopyWithImpl<ModelCatalogEvent>(this as ModelCatalogEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ModelCatalogEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $ModelCatalogEventCopyWith<$Res>  {
  factory $ModelCatalogEventCopyWith(ModelCatalogEvent value, $Res Function(ModelCatalogEvent) _then) = _$ModelCatalogEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ModelCatalogEventCopyWithImpl<$Res>
    implements $ModelCatalogEventCopyWith<$Res> {
  _$ModelCatalogEventCopyWithImpl(this._self, this._then);

  final ModelCatalogEvent _self;
  final $Res Function(ModelCatalogEvent) _then;

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCatalogEvent].
extension ModelCatalogEventPatterns on ModelCatalogEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModelCatalogBaselineEvent value)?  baseline,TResult Function( ModelCatalogChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent() when baseline != null:
return baseline(_that);case ModelCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModelCatalogBaselineEvent value)  baseline,required TResult Function( ModelCatalogChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent():
return baseline(_that);case ModelCatalogChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModelCatalogBaselineEvent value)?  baseline,TResult? Function( ModelCatalogChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent() when baseline != null:
return baseline(_that);case ModelCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModelCatalogBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ModelCatalogChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ModelCatalogChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModelCatalogBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ModelCatalogChange value)  change,}) {final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ModelCatalogChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ModelCatalogBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  ModelCatalogChange value)?  change,}) {final _that = this;
switch (_that) {
case ModelCatalogBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ModelCatalogChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ModelCatalogBaselineEvent implements ModelCatalogEvent {
  const ModelCatalogBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  ModelCatalogBaseline value;

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogBaselineEventCopyWith<ModelCatalogBaselineEvent> get copyWith => _$ModelCatalogBaselineEventCopyWithImpl<ModelCatalogBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ModelCatalogBaselineEventCopyWith<$Res> implements $ModelCatalogEventCopyWith<$Res> {
  factory $ModelCatalogBaselineEventCopyWith(ModelCatalogBaselineEvent value, $Res Function(ModelCatalogBaselineEvent) _then) = _$ModelCatalogBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, ModelCatalogBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$ModelCatalogBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ModelCatalogBaselineEventCopyWithImpl<$Res>
    implements $ModelCatalogBaselineEventCopyWith<$Res> {
  _$ModelCatalogBaselineEventCopyWithImpl(this._self, this._then);

  final ModelCatalogBaselineEvent _self;
  final $Res Function(ModelCatalogBaselineEvent) _then;

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ModelCatalogBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelCatalogBaseline,
  ));
}

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogBaselineCopyWith<$Res> get value {

  return $ModelCatalogBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ModelCatalogChangeEvent implements ModelCatalogEvent {
  const ModelCatalogChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  ModelCatalogChange value;

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogChangeEventCopyWith<ModelCatalogChangeEvent> get copyWith => _$ModelCatalogChangeEventCopyWithImpl<ModelCatalogChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $ModelCatalogChangeEventCopyWith<$Res> implements $ModelCatalogEventCopyWith<$Res> {
  factory $ModelCatalogChangeEventCopyWith(ModelCatalogChangeEvent value, $Res Function(ModelCatalogChangeEvent) _then) = _$ModelCatalogChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, ModelCatalogChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$ModelCatalogChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ModelCatalogChangeEventCopyWithImpl<$Res>
    implements $ModelCatalogChangeEventCopyWith<$Res> {
  _$ModelCatalogChangeEventCopyWithImpl(this._self, this._then);

  final ModelCatalogChangeEvent _self;
  final $Res Function(ModelCatalogChangeEvent) _then;

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ModelCatalogChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelCatalogChange,
  ));
}

/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ModelCatalogEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogChangeCopyWith<$Res> get value {

  return $ModelCatalogChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ModelCatalogBaseline {

 ModelCatalogHeader get header; ProductCollectionRef? get collection;
/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogBaselineCopyWith<ModelCatalogBaseline> get copyWith => _$ModelCatalogBaselineCopyWithImpl<ModelCatalogBaseline>(this as ModelCatalogBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as ModelCatalogBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $ModelCatalogBaselineCopyWith<$Res>  {
  factory $ModelCatalogBaselineCopyWith(ModelCatalogBaseline value, $Res Function(ModelCatalogBaseline) _then) = _$ModelCatalogBaselineCopyWithImpl;
@useResult
$Res call({
 ModelCatalogHeader header, ProductCollectionRef? collection
});


$ModelCatalogHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ModelCatalogBaselineCopyWithImpl<$Res>
    implements $ModelCatalogBaselineCopyWith<$Res> {
  _$ModelCatalogBaselineCopyWithImpl(this._self, this._then);

  final ModelCatalogBaseline _self;
  final $Res Function(ModelCatalogBaseline) _then;

/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(ModelCatalogBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModelCatalogHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogHeaderCopyWith<$Res> get header {

  return $ModelCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModelCatalogBaseline
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


/// Adds pattern-matching-related methods to [ModelCatalogBaseline].
extension ModelCatalogBaselinePatterns on ModelCatalogBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelCatalogHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCatalogBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelCatalogHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelCatalogHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogBaseline implements ModelCatalogBaseline {
  const _ModelCatalogBaseline({required this.header, required this.collection});


@override final  ModelCatalogHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogBaselineCopyWith<_ModelCatalogBaseline> get copyWith => __$ModelCatalogBaselineCopyWithImpl<_ModelCatalogBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$ModelCatalogBaselineCopyWith<$Res> implements $ModelCatalogBaselineCopyWith<$Res> {
  factory _$ModelCatalogBaselineCopyWith(_ModelCatalogBaseline value, $Res Function(_ModelCatalogBaseline) _then) = __$ModelCatalogBaselineCopyWithImpl;
@override @useResult
$Res call({
 ModelCatalogHeader header, ProductCollectionRef? collection
});


@override $ModelCatalogHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ModelCatalogBaselineCopyWithImpl<$Res>
    implements _$ModelCatalogBaselineCopyWith<$Res> {
  __$ModelCatalogBaselineCopyWithImpl(this._self, this._then);

  final _ModelCatalogBaseline _self;
  final $Res Function(_ModelCatalogBaseline) _then;

/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_ModelCatalogBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModelCatalogHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of ModelCatalogBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogHeaderCopyWith<$Res> get header {

  return $ModelCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModelCatalogBaseline
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
mixin _$ModelCatalogChange {


/// Create a copy of ModelCatalogChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogChangeCopyWith<ModelCatalogChange> get copyWith => _$ModelCatalogChangeCopyWithImpl<ModelCatalogChange>(this as ModelCatalogChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as ModelCatalogChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $ModelCatalogChangeCopyWith<$Res>  {
  factory $ModelCatalogChangeCopyWith(ModelCatalogChange value, $Res Function(ModelCatalogChange) _then) = _$ModelCatalogChangeCopyWithImpl;
@useResult
$Res call({
 ModelCatalogHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$ModelCatalogHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ModelCatalogChangeCopyWithImpl<$Res>
    implements $ModelCatalogChangeCopyWith<$Res> {
  _$ModelCatalogChangeCopyWithImpl(this._self, this._then);

  final ModelCatalogChange _self;
  final $Res Function(ModelCatalogChange) _then;

/// Create a copy of ModelCatalogChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(ModelCatalogChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ModelCatalogHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of ModelCatalogChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogHeaderCopyWith<$Res> get header {

  return $ModelCatalogHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ModelCatalogChange
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


/// Adds pattern-matching-related methods to [ModelCatalogChange].
extension ModelCatalogChangePatterns on ModelCatalogChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$AccountTemplatesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AccountTemplatesFrameCopyWith<$Res>  {
$AccountTemplatesFrameCopyWith(AccountTemplatesFrame _, $Res Function(AccountTemplatesFrame) __);
}


/// Adds pattern-matching-related methods to [AccountTemplatesFrame].
extension AccountTemplatesFramePatterns on AccountTemplatesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AccountTemplatesData value)?  data,TResult Function( AccountTemplatesResyncRequired value)?  resyncRequired,TResult Function( AccountTemplatesFeedFailure value)?  failure,TResult Function( AccountTemplatesClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AccountTemplatesData() when data != null:
return data(_that);case AccountTemplatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AccountTemplatesFeedFailure() when failure != null:
return failure(_that);case AccountTemplatesClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AccountTemplatesData value)  data,required TResult Function( AccountTemplatesResyncRequired value)  resyncRequired,required TResult Function( AccountTemplatesFeedFailure value)  failure,required TResult Function( AccountTemplatesClosed value)  closed,}){
final _that = this;
switch (_that) {
case AccountTemplatesData():
return data(_that);case AccountTemplatesResyncRequired():
return resyncRequired(_that);case AccountTemplatesFeedFailure():
return failure(_that);case AccountTemplatesClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AccountTemplatesData value)?  data,TResult? Function( AccountTemplatesResyncRequired value)?  resyncRequired,TResult? Function( AccountTemplatesFeedFailure value)?  failure,TResult? Function( AccountTemplatesClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AccountTemplatesData() when data != null:
return data(_that);case AccountTemplatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AccountTemplatesFeedFailure() when failure != null:
return failure(_that);case AccountTemplatesClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AccountTemplatesEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AccountTemplatesData() when data != null:
return data(_that.deliverySequence,_that.event);case AccountTemplatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AccountTemplatesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AccountTemplatesClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AccountTemplatesEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AccountTemplatesData():
return data(_that.deliverySequence,_that.event);case AccountTemplatesResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AccountTemplatesFeedFailure():
return failure(_that.identity,_that.error);case AccountTemplatesClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AccountTemplatesEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AccountTemplatesData() when data != null:
return data(_that.deliverySequence,_that.event);case AccountTemplatesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AccountTemplatesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AccountTemplatesClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AccountTemplatesData implements AccountTemplatesFrame {
  const AccountTemplatesData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AccountTemplatesEvent event;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesDataCopyWith<AccountTemplatesData> get copyWith => _$AccountTemplatesDataCopyWithImpl<AccountTemplatesData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesDataCopyWith<$Res> implements $AccountTemplatesFrameCopyWith<$Res> {
  factory $AccountTemplatesDataCopyWith(AccountTemplatesData value, $Res Function(AccountTemplatesData) _then) = _$AccountTemplatesDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AccountTemplatesEvent event
});


$AccountTemplatesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AccountTemplatesDataCopyWithImpl<$Res>
    implements $AccountTemplatesDataCopyWith<$Res> {
  _$AccountTemplatesDataCopyWithImpl(this._self, this._then);

  final AccountTemplatesData _self;
  final $Res Function(AccountTemplatesData) _then;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AccountTemplatesData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AccountTemplatesEvent,
  ));
}

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesEventCopyWith<$Res> get event {

  return $AccountTemplatesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AccountTemplatesResyncRequired implements AccountTemplatesFrame {
  const AccountTemplatesResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesResyncRequiredCopyWith<AccountTemplatesResyncRequired> get copyWith => _$AccountTemplatesResyncRequiredCopyWithImpl<AccountTemplatesResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesResyncRequiredCopyWith<$Res> implements $AccountTemplatesFrameCopyWith<$Res> {
  factory $AccountTemplatesResyncRequiredCopyWith(AccountTemplatesResyncRequired value, $Res Function(AccountTemplatesResyncRequired) _then) = _$AccountTemplatesResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AccountTemplatesResyncRequiredCopyWithImpl<$Res>
    implements $AccountTemplatesResyncRequiredCopyWith<$Res> {
  _$AccountTemplatesResyncRequiredCopyWithImpl(this._self, this._then);

  final AccountTemplatesResyncRequired _self;
  final $Res Function(AccountTemplatesResyncRequired) _then;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AccountTemplatesResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AccountTemplatesFrame
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


class AccountTemplatesFeedFailure implements AccountTemplatesFrame {
  const AccountTemplatesFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesFeedFailureCopyWith<AccountTemplatesFeedFailure> get copyWith => _$AccountTemplatesFeedFailureCopyWithImpl<AccountTemplatesFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesFeedFailureCopyWith<$Res> implements $AccountTemplatesFrameCopyWith<$Res> {
  factory $AccountTemplatesFeedFailureCopyWith(AccountTemplatesFeedFailure value, $Res Function(AccountTemplatesFeedFailure) _then) = _$AccountTemplatesFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AccountTemplatesFeedFailureCopyWithImpl<$Res>
    implements $AccountTemplatesFeedFailureCopyWith<$Res> {
  _$AccountTemplatesFeedFailureCopyWithImpl(this._self, this._then);

  final AccountTemplatesFeedFailure _self;
  final $Res Function(AccountTemplatesFeedFailure) _then;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AccountTemplatesFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountTemplatesFrame
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


class AccountTemplatesClosed implements AccountTemplatesFrame {
  const AccountTemplatesClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesClosedCopyWith<AccountTemplatesClosed> get copyWith => _$AccountTemplatesClosedCopyWithImpl<AccountTemplatesClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesClosedCopyWith<$Res> implements $AccountTemplatesFrameCopyWith<$Res> {
  factory $AccountTemplatesClosedCopyWith(AccountTemplatesClosed value, $Res Function(AccountTemplatesClosed) _then) = _$AccountTemplatesClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AccountTemplatesClosedCopyWithImpl<$Res>
    implements $AccountTemplatesClosedCopyWith<$Res> {
  _$AccountTemplatesClosedCopyWithImpl(this._self, this._then);

  final AccountTemplatesClosed _self;
  final $Res Function(AccountTemplatesClosed) _then;

/// Create a copy of AccountTemplatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AccountTemplatesClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AccountTemplatesFrame
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
mixin _$AccountTemplatesEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesEventCopyWith<AccountTemplatesEvent> get copyWith => _$AccountTemplatesEventCopyWithImpl<AccountTemplatesEvent>(this as AccountTemplatesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $AccountTemplatesEventCopyWith<$Res>  {
  factory $AccountTemplatesEventCopyWith(AccountTemplatesEvent value, $Res Function(AccountTemplatesEvent) _then) = _$AccountTemplatesEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$AccountTemplatesEventCopyWithImpl<$Res>
    implements $AccountTemplatesEventCopyWith<$Res> {
  _$AccountTemplatesEventCopyWithImpl(this._self, this._then);

  final AccountTemplatesEvent _self;
  final $Res Function(AccountTemplatesEvent) _then;

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplatesEvent].
extension AccountTemplatesEventPatterns on AccountTemplatesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AccountTemplatesBaselineEvent value)?  baseline,TResult Function( AccountTemplatesChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent() when baseline != null:
return baseline(_that);case AccountTemplatesChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AccountTemplatesBaselineEvent value)  baseline,required TResult Function( AccountTemplatesChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent():
return baseline(_that);case AccountTemplatesChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AccountTemplatesBaselineEvent value)?  baseline,TResult? Function( AccountTemplatesChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent() when baseline != null:
return baseline(_that);case AccountTemplatesChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountTemplatesBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AccountTemplatesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AccountTemplatesChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountTemplatesBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AccountTemplatesChange value)  change,}) {final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case AccountTemplatesChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountTemplatesBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AccountTemplatesChange value)?  change,}) {final _that = this;
switch (_that) {
case AccountTemplatesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AccountTemplatesChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class AccountTemplatesBaselineEvent implements AccountTemplatesEvent {
  const AccountTemplatesBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AccountTemplatesBaseline value;

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesBaselineEventCopyWith<AccountTemplatesBaselineEvent> get copyWith => _$AccountTemplatesBaselineEventCopyWithImpl<AccountTemplatesBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesBaselineEventCopyWith<$Res> implements $AccountTemplatesEventCopyWith<$Res> {
  factory $AccountTemplatesBaselineEventCopyWith(AccountTemplatesBaselineEvent value, $Res Function(AccountTemplatesBaselineEvent) _then) = _$AccountTemplatesBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AccountTemplatesBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$AccountTemplatesBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$AccountTemplatesBaselineEventCopyWithImpl<$Res>
    implements $AccountTemplatesBaselineEventCopyWith<$Res> {
  _$AccountTemplatesBaselineEventCopyWithImpl(this._self, this._then);

  final AccountTemplatesBaselineEvent _self;
  final $Res Function(AccountTemplatesBaselineEvent) _then;

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(AccountTemplatesBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountTemplatesBaseline,
  ));
}

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesBaselineCopyWith<$Res> get value {

  return $AccountTemplatesBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class AccountTemplatesChangeEvent implements AccountTemplatesEvent {
  const AccountTemplatesChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  AccountTemplatesChange value;

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesChangeEventCopyWith<AccountTemplatesChangeEvent> get copyWith => _$AccountTemplatesChangeEventCopyWithImpl<AccountTemplatesChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesChangeEventCopyWith<$Res> implements $AccountTemplatesEventCopyWith<$Res> {
  factory $AccountTemplatesChangeEventCopyWith(AccountTemplatesChangeEvent value, $Res Function(AccountTemplatesChangeEvent) _then) = _$AccountTemplatesChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AccountTemplatesChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$AccountTemplatesChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$AccountTemplatesChangeEventCopyWithImpl<$Res>
    implements $AccountTemplatesChangeEventCopyWith<$Res> {
  _$AccountTemplatesChangeEventCopyWithImpl(this._self, this._then);

  final AccountTemplatesChangeEvent _self;
  final $Res Function(AccountTemplatesChangeEvent) _then;

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(AccountTemplatesChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountTemplatesChange,
  ));
}

/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AccountTemplatesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesChangeCopyWith<$Res> get value {

  return $AccountTemplatesChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplatesBaseline {

 AccountTemplatesHeader get header; ProductCollectionRef? get collection;
/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesBaselineCopyWith<AccountTemplatesBaseline> get copyWith => _$AccountTemplatesBaselineCopyWithImpl<AccountTemplatesBaseline>(this as AccountTemplatesBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesBaselineCopyWith<$Res>  {
  factory $AccountTemplatesBaselineCopyWith(AccountTemplatesBaseline value, $Res Function(AccountTemplatesBaseline) _then) = _$AccountTemplatesBaselineCopyWithImpl;
@useResult
$Res call({
 AccountTemplatesHeader header, ProductCollectionRef? collection
});


$AccountTemplatesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AccountTemplatesBaselineCopyWithImpl<$Res>
    implements $AccountTemplatesBaselineCopyWith<$Res> {
  _$AccountTemplatesBaselineCopyWithImpl(this._self, this._then);

  final AccountTemplatesBaseline _self;
  final $Res Function(AccountTemplatesBaseline) _then;

/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(AccountTemplatesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountTemplatesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesHeaderCopyWith<$Res> get header {

  return $AccountTemplatesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountTemplatesBaseline
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


/// Adds pattern-matching-related methods to [AccountTemplatesBaseline].
extension AccountTemplatesBaselinePatterns on AccountTemplatesBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatesBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatesBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatesBaseline value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatesBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountTemplatesHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplatesBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountTemplatesHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountTemplatesHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatesBaseline implements AccountTemplatesBaseline {
  const _AccountTemplatesBaseline({required this.header, required this.collection});


@override final  AccountTemplatesHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatesBaselineCopyWith<_AccountTemplatesBaseline> get copyWith => __$AccountTemplatesBaselineCopyWithImpl<_AccountTemplatesBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatesBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$AccountTemplatesBaselineCopyWith<$Res> implements $AccountTemplatesBaselineCopyWith<$Res> {
  factory _$AccountTemplatesBaselineCopyWith(_AccountTemplatesBaseline value, $Res Function(_AccountTemplatesBaseline) _then) = __$AccountTemplatesBaselineCopyWithImpl;
@override @useResult
$Res call({
 AccountTemplatesHeader header, ProductCollectionRef? collection
});


@override $AccountTemplatesHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$AccountTemplatesBaselineCopyWithImpl<$Res>
    implements _$AccountTemplatesBaselineCopyWith<$Res> {
  __$AccountTemplatesBaselineCopyWithImpl(this._self, this._then);

  final _AccountTemplatesBaseline _self;
  final $Res Function(_AccountTemplatesBaseline) _then;

/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_AccountTemplatesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountTemplatesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of AccountTemplatesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesHeaderCopyWith<$Res> get header {

  return $AccountTemplatesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountTemplatesBaseline
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
mixin _$AccountTemplatesChange {


/// Create a copy of AccountTemplatesChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesChangeCopyWith<AccountTemplatesChange> get copyWith => _$AccountTemplatesChangeCopyWithImpl<AccountTemplatesChange>(this as AccountTemplatesChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $AccountTemplatesChangeCopyWith<$Res>  {
  factory $AccountTemplatesChangeCopyWith(AccountTemplatesChange value, $Res Function(AccountTemplatesChange) _then) = _$AccountTemplatesChangeCopyWithImpl;
@useResult
$Res call({
 AccountTemplatesHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$AccountTemplatesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AccountTemplatesChangeCopyWithImpl<$Res>
    implements $AccountTemplatesChangeCopyWith<$Res> {
  _$AccountTemplatesChangeCopyWithImpl(this._self, this._then);

  final AccountTemplatesChange _self;
  final $Res Function(AccountTemplatesChange) _then;

/// Create a copy of AccountTemplatesChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(AccountTemplatesChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountTemplatesHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of AccountTemplatesChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesHeaderCopyWith<$Res> get header {

  return $AccountTemplatesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountTemplatesChange
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


/// Adds pattern-matching-related methods to [AccountTemplatesChange].
extension AccountTemplatesChangePatterns on AccountTemplatesChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
