// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_detail_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineDetailKey {

 String get threadId; int get displayGeneration; String get itemId; ThreadContentFieldView get field; int get revision;
/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDetailKeyCopyWith<TimelineDetailKey> get copyWith => _$TimelineDetailKeyCopyWithImpl<TimelineDetailKey>(this as TimelineDetailKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineDetailKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDetailKey&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.displayGeneration, _this.displayGeneration) || other.displayGeneration == _this.displayGeneration)&&(identical(other.itemId, _this.itemId) || other.itemId == _this.itemId)&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as TimelineDetailKey;
  return Object.hash(runtimeType,_this.threadId,_this.displayGeneration,_this.itemId,_this.field,_this.revision);
}



}

/// @nodoc
abstract mixin class $TimelineDetailKeyCopyWith<$Res>  {
  factory $TimelineDetailKeyCopyWith(TimelineDetailKey value, $Res Function(TimelineDetailKey) _then) = _$TimelineDetailKeyCopyWithImpl;
@useResult
$Res call({
 String threadId, int displayGeneration, String itemId, ThreadContentFieldView field, int revision
});


$ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class _$TimelineDetailKeyCopyWithImpl<$Res>
    implements $TimelineDetailKeyCopyWith<$Res> {
  _$TimelineDetailKeyCopyWithImpl(this._self, this._then);

  final TimelineDetailKey _self;
  final $Res Function(TimelineDetailKey) _then;

/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? displayGeneration = null,Object? itemId = null,Object? field = null,Object? revision = null,}) {
  return _then(TimelineDetailKey(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,displayGeneration: null == displayGeneration ? _self.displayGeneration : displayGeneration // ignore: cast_nullable_to_non_nullable
as int,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineDetailKey].
extension TimelineDetailKeyPatterns on TimelineDetailKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineDetailKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineDetailKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineDetailKey value)  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineDetailKey value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int displayGeneration,  String itemId,  ThreadContentFieldView field,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineDetailKey() when $default != null:
return $default(_that.threadId,_that.displayGeneration,_that.itemId,_that.field,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int displayGeneration,  String itemId,  ThreadContentFieldView field,  int revision)  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailKey():
return $default(_that.threadId,_that.displayGeneration,_that.itemId,_that.field,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int displayGeneration,  String itemId,  ThreadContentFieldView field,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailKey() when $default != null:
return $default(_that.threadId,_that.displayGeneration,_that.itemId,_that.field,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineDetailKey implements TimelineDetailKey {
  const _TimelineDetailKey({required this.threadId, required this.displayGeneration, required this.itemId, required this.field, required this.revision});


@override final  String threadId;
@override final  int displayGeneration;
@override final  String itemId;
@override final  ThreadContentFieldView field;
@override final  int revision;

/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineDetailKeyCopyWith<_TimelineDetailKey> get copyWith => __$TimelineDetailKeyCopyWithImpl<_TimelineDetailKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineDetailKey&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.displayGeneration, displayGeneration) || other.displayGeneration == displayGeneration)&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.field, field) || other.field == field)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,displayGeneration,itemId,field,revision);
}



}

/// @nodoc
abstract mixin class _$TimelineDetailKeyCopyWith<$Res> implements $TimelineDetailKeyCopyWith<$Res> {
  factory _$TimelineDetailKeyCopyWith(_TimelineDetailKey value, $Res Function(_TimelineDetailKey) _then) = __$TimelineDetailKeyCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int displayGeneration, String itemId, ThreadContentFieldView field, int revision
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class __$TimelineDetailKeyCopyWithImpl<$Res>
    implements _$TimelineDetailKeyCopyWith<$Res> {
  __$TimelineDetailKeyCopyWithImpl(this._self, this._then);

  final _TimelineDetailKey _self;
  final $Res Function(_TimelineDetailKey) _then;

/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? displayGeneration = null,Object? itemId = null,Object? field = null,Object? revision = null,}) {
  return _then(_TimelineDetailKey(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,displayGeneration: null == displayGeneration ? _self.displayGeneration : displayGeneration // ignore: cast_nullable_to_non_nullable
as int,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of TimelineDetailKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}

/// @nodoc
mixin _$TimelineDetailViewState {

 TimelineDetailKey get key; String get text; int get loadedBytes; int? get totalBytes; String? get continuation; bool get loading; bool get complete; bool get closing; StudioFailure? get error;
/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDetailViewStateCopyWith<TimelineDetailViewState> get copyWith => _$TimelineDetailViewStateCopyWithImpl<TimelineDetailViewState>(this as TimelineDetailViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineDetailViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDetailViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.loadedBytes, _this.loadedBytes) || other.loadedBytes == _this.loadedBytes)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.complete, _this.complete) || other.complete == _this.complete)&&(identical(other.closing, _this.closing) || other.closing == _this.closing)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as TimelineDetailViewState;
  return Object.hash(runtimeType,_this.key,_this.text,_this.loadedBytes,_this.totalBytes,_this.continuation,_this.loading,_this.complete,_this.closing,_this.error);
}



}

/// @nodoc
abstract mixin class $TimelineDetailViewStateCopyWith<$Res>  {
  factory $TimelineDetailViewStateCopyWith(TimelineDetailViewState value, $Res Function(TimelineDetailViewState) _then) = _$TimelineDetailViewStateCopyWithImpl;
@useResult
$Res call({
 TimelineDetailKey key, String text, int loadedBytes, int? totalBytes, String? continuation, bool loading, bool complete, bool closing, StudioFailure? error
});


$TimelineDetailKeyCopyWith<$Res> get key;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$TimelineDetailViewStateCopyWithImpl<$Res>
    implements $TimelineDetailViewStateCopyWith<$Res> {
  _$TimelineDetailViewStateCopyWithImpl(this._self, this._then);

  final TimelineDetailViewState _self;
  final $Res Function(TimelineDetailViewState) _then;

/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? text = null,Object? loadedBytes = null,Object? totalBytes = freezed,Object? continuation = freezed,Object? loading = null,Object? complete = null,Object? closing = null,Object? error = freezed,}) {
  return _then(TimelineDetailViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as TimelineDetailKey,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,loadedBytes: null == loadedBytes ? _self.loadedBytes : loadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimelineDetailKeyCopyWith<$Res> get key {

  return $TimelineDetailKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineDetailViewState].
extension TimelineDetailViewStatePatterns on TimelineDetailViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineDetailViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineDetailViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineDetailViewState value)  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineDetailViewState value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TimelineDetailKey key,  String text,  int loadedBytes,  int? totalBytes,  String? continuation,  bool loading,  bool complete,  bool closing,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineDetailViewState() when $default != null:
return $default(_that.key,_that.text,_that.loadedBytes,_that.totalBytes,_that.continuation,_that.loading,_that.complete,_that.closing,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TimelineDetailKey key,  String text,  int loadedBytes,  int? totalBytes,  String? continuation,  bool loading,  bool complete,  bool closing,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailViewState():
return $default(_that.key,_that.text,_that.loadedBytes,_that.totalBytes,_that.continuation,_that.loading,_that.complete,_that.closing,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TimelineDetailKey key,  String text,  int loadedBytes,  int? totalBytes,  String? continuation,  bool loading,  bool complete,  bool closing,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailViewState() when $default != null:
return $default(_that.key,_that.text,_that.loadedBytes,_that.totalBytes,_that.continuation,_that.loading,_that.complete,_that.closing,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineDetailViewState implements TimelineDetailViewState {
  const _TimelineDetailViewState({required this.key, this.text = '', this.loadedBytes = 0, this.totalBytes, this.continuation, this.loading = false, this.complete = false, this.closing = false, this.error});


@override final  TimelineDetailKey key;
@override@JsonKey() final  String text;
@override@JsonKey() final  int loadedBytes;
@override final  int? totalBytes;
@override final  String? continuation;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool complete;
@override@JsonKey() final  bool closing;
@override final  StudioFailure? error;

/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineDetailViewStateCopyWith<_TimelineDetailViewState> get copyWith => __$TimelineDetailViewStateCopyWithImpl<_TimelineDetailViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineDetailViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.text, text) || other.text == text)&&(identical(other.loadedBytes, loadedBytes) || other.loadedBytes == loadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.continuation, continuation) || other.continuation == continuation)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.complete, complete) || other.complete == complete)&&(identical(other.closing, closing) || other.closing == closing)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,text,loadedBytes,totalBytes,continuation,loading,complete,closing,error);
}



}

/// @nodoc
abstract mixin class _$TimelineDetailViewStateCopyWith<$Res> implements $TimelineDetailViewStateCopyWith<$Res> {
  factory _$TimelineDetailViewStateCopyWith(_TimelineDetailViewState value, $Res Function(_TimelineDetailViewState) _then) = __$TimelineDetailViewStateCopyWithImpl;
@override @useResult
$Res call({
 TimelineDetailKey key, String text, int loadedBytes, int? totalBytes, String? continuation, bool loading, bool complete, bool closing, StudioFailure? error
});


@override $TimelineDetailKeyCopyWith<$Res> get key;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$TimelineDetailViewStateCopyWithImpl<$Res>
    implements _$TimelineDetailViewStateCopyWith<$Res> {
  __$TimelineDetailViewStateCopyWithImpl(this._self, this._then);

  final _TimelineDetailViewState _self;
  final $Res Function(_TimelineDetailViewState) _then;

/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? text = null,Object? loadedBytes = null,Object? totalBytes = freezed,Object? continuation = freezed,Object? loading = null,Object? complete = null,Object? closing = null,Object? error = freezed,}) {
  return _then(_TimelineDetailViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as TimelineDetailKey,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,loadedBytes: null == loadedBytes ? _self.loadedBytes : loadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimelineDetailKeyCopyWith<$Res> get key {

  return $TimelineDetailKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of TimelineDetailViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
