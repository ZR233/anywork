// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message_payload.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineMessagePayload {

 ThreadItemView get item; StudioTimelineItemSource get source; bool get saved; StudioTimelineLifecycle get lifecycle; int get omittedBytes; List<StudioTimelineDetailRef> get details;
/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineMessagePayloadCopyWith<TimelineMessagePayload> get copyWith => _$TimelineMessagePayloadCopyWithImpl<TimelineMessagePayload>(this as TimelineMessagePayload, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineMessagePayload;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineMessagePayload&&(identical(other.item, _this.item) || other.item == _this.item)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.saved, _this.saved) || other.saved == _this.saved)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.omittedBytes, _this.omittedBytes) || other.omittedBytes == _this.omittedBytes)&&const DeepCollectionEquality().equals(other.details, _this.details));
}


@override
int get hashCode {
  final _this = this as TimelineMessagePayload;
  return Object.hash(runtimeType,_this.item,_this.source,_this.saved,_this.lifecycle,_this.omittedBytes,const DeepCollectionEquality().hash(_this.details));
}



}

/// @nodoc
abstract mixin class $TimelineMessagePayloadCopyWith<$Res>  {
  factory $TimelineMessagePayloadCopyWith(TimelineMessagePayload value, $Res Function(TimelineMessagePayload) _then) = _$TimelineMessagePayloadCopyWithImpl;
@useResult
$Res call({
 ThreadItemView item, StudioTimelineItemSource source, bool saved, StudioTimelineLifecycle lifecycle, int omittedBytes, List<StudioTimelineDetailRef> details
});


$ThreadItemViewCopyWith<$Res> get item;$StudioTimelineItemSourceCopyWith<$Res> get source;

}
/// @nodoc
class _$TimelineMessagePayloadCopyWithImpl<$Res>
    implements $TimelineMessagePayloadCopyWith<$Res> {
  _$TimelineMessagePayloadCopyWithImpl(this._self, this._then);

  final TimelineMessagePayload _self;
  final $Res Function(TimelineMessagePayload) _then;

/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? item = null,Object? source = null,Object? saved = null,Object? lifecycle = null,Object? omittedBytes = null,Object? details = null,}) {
  return _then(TimelineMessagePayload(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as ThreadItemView,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as StudioTimelineItemSource,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as StudioTimelineLifecycle,omittedBytes: null == omittedBytes ? _self.omittedBytes : omittedBytes // ignore: cast_nullable_to_non_nullable
as int,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineDetailRef>,
  ));
}
/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemViewCopyWith<$Res> get item {

  return $ThreadItemViewCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineItemSourceCopyWith<$Res> get source {

  return $StudioTimelineItemSourceCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineMessagePayload].
extension TimelineMessagePayloadPatterns on TimelineMessagePayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineMessagePayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineMessagePayload() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineMessagePayload value)  $default,){
final _that = this;
switch (_that) {
case _TimelineMessagePayload():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineMessagePayload value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineMessagePayload() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadItemView item,  StudioTimelineItemSource source,  bool saved,  StudioTimelineLifecycle lifecycle,  int omittedBytes,  List<StudioTimelineDetailRef> details)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineMessagePayload() when $default != null:
return $default(_that.item,_that.source,_that.saved,_that.lifecycle,_that.omittedBytes,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadItemView item,  StudioTimelineItemSource source,  bool saved,  StudioTimelineLifecycle lifecycle,  int omittedBytes,  List<StudioTimelineDetailRef> details)  $default,) {final _that = this;
switch (_that) {
case _TimelineMessagePayload():
return $default(_that.item,_that.source,_that.saved,_that.lifecycle,_that.omittedBytes,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadItemView item,  StudioTimelineItemSource source,  bool saved,  StudioTimelineLifecycle lifecycle,  int omittedBytes,  List<StudioTimelineDetailRef> details)?  $default,) {final _that = this;
switch (_that) {
case _TimelineMessagePayload() when $default != null:
return $default(_that.item,_that.source,_that.saved,_that.lifecycle,_that.omittedBytes,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineMessagePayload extends TimelineMessagePayload {
  const _TimelineMessagePayload({required this.item, required this.source, required this.saved, required this.lifecycle, required this.omittedBytes, required  List<StudioTimelineDetailRef> details}): _details = details,super._();


@override final  ThreadItemView item;
@override final  StudioTimelineItemSource source;
@override final  bool saved;
@override final  StudioTimelineLifecycle lifecycle;
@override final  int omittedBytes;
 final  List<StudioTimelineDetailRef> _details;
@override List<StudioTimelineDetailRef> get details {
  if (_details is EqualUnmodifiableListView) return _details;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_details);
}


/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineMessagePayloadCopyWith<_TimelineMessagePayload> get copyWith => __$TimelineMessagePayloadCopyWithImpl<_TimelineMessagePayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineMessagePayload&&(identical(other.item, item) || other.item == item)&&(identical(other.source, source) || other.source == source)&&(identical(other.saved, saved) || other.saved == saved)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.omittedBytes, omittedBytes) || other.omittedBytes == omittedBytes)&&const DeepCollectionEquality().equals(other.details, _details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,item,source,saved,lifecycle,omittedBytes,const DeepCollectionEquality().hash(_details));
}



}

/// @nodoc
abstract mixin class _$TimelineMessagePayloadCopyWith<$Res> implements $TimelineMessagePayloadCopyWith<$Res> {
  factory _$TimelineMessagePayloadCopyWith(_TimelineMessagePayload value, $Res Function(_TimelineMessagePayload) _then) = __$TimelineMessagePayloadCopyWithImpl;
@override @useResult
$Res call({
 ThreadItemView item, StudioTimelineItemSource source, bool saved, StudioTimelineLifecycle lifecycle, int omittedBytes, List<StudioTimelineDetailRef> details
});


@override $ThreadItemViewCopyWith<$Res> get item;@override $StudioTimelineItemSourceCopyWith<$Res> get source;

}
/// @nodoc
class __$TimelineMessagePayloadCopyWithImpl<$Res>
    implements _$TimelineMessagePayloadCopyWith<$Res> {
  __$TimelineMessagePayloadCopyWithImpl(this._self, this._then);

  final _TimelineMessagePayload _self;
  final $Res Function(_TimelineMessagePayload) _then;

/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? item = null,Object? source = null,Object? saved = null,Object? lifecycle = null,Object? omittedBytes = null,Object? details = null,}) {
  return _then(_TimelineMessagePayload(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as ThreadItemView,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as StudioTimelineItemSource,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as StudioTimelineLifecycle,omittedBytes: null == omittedBytes ? _self.omittedBytes : omittedBytes // ignore: cast_nullable_to_non_nullable
as int,details: null == details ? _self._details : details // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineDetailRef>,
  ));
}

/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemViewCopyWith<$Res> get item {

  return $ThreadItemViewCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}/// Create a copy of TimelineMessagePayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineItemSourceCopyWith<$Res> get source {

  return $StudioTimelineItemSourceCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

// dart format on
