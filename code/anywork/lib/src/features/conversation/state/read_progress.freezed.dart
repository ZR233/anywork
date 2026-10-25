// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'read_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TextReadProgress {

 int get fieldId; int get totalUtf8Bytes; int get loadedUtf8Bytes; String get text; bool get complete; bool get loading; StudioFailure? get error;
/// Create a copy of TextReadProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextReadProgressCopyWith<TextReadProgress> get copyWith => _$TextReadProgressCopyWithImpl<TextReadProgress>(this as TextReadProgress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TextReadProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextReadProgress&&(identical(other.fieldId, _this.fieldId) || other.fieldId == _this.fieldId)&&(identical(other.totalUtf8Bytes, _this.totalUtf8Bytes) || other.totalUtf8Bytes == _this.totalUtf8Bytes)&&(identical(other.loadedUtf8Bytes, _this.loadedUtf8Bytes) || other.loadedUtf8Bytes == _this.loadedUtf8Bytes)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.complete, _this.complete) || other.complete == _this.complete)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as TextReadProgress;
  return Object.hash(runtimeType,_this.fieldId,_this.totalUtf8Bytes,_this.loadedUtf8Bytes,_this.text,_this.complete,_this.loading,_this.error);
}



}

/// @nodoc
abstract mixin class $TextReadProgressCopyWith<$Res>  {
  factory $TextReadProgressCopyWith(TextReadProgress value, $Res Function(TextReadProgress) _then) = _$TextReadProgressCopyWithImpl;
@useResult
$Res call({
 int fieldId, int totalUtf8Bytes, int loadedUtf8Bytes, String text, bool complete, bool loading, StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$TextReadProgressCopyWithImpl<$Res>
    implements $TextReadProgressCopyWith<$Res> {
  _$TextReadProgressCopyWithImpl(this._self, this._then);

  final TextReadProgress _self;
  final $Res Function(TextReadProgress) _then;

/// Create a copy of TextReadProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fieldId = null,Object? totalUtf8Bytes = null,Object? loadedUtf8Bytes = null,Object? text = null,Object? complete = null,Object? loading = null,Object? error = freezed,}) {
  return _then(TextReadProgress(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int,totalUtf8Bytes: null == totalUtf8Bytes ? _self.totalUtf8Bytes : totalUtf8Bytes // ignore: cast_nullable_to_non_nullable
as int,loadedUtf8Bytes: null == loadedUtf8Bytes ? _self.loadedUtf8Bytes : loadedUtf8Bytes // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of TextReadProgress
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


/// Adds pattern-matching-related methods to [TextReadProgress].
extension TextReadProgressPatterns on TextReadProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TextReadProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TextReadProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TextReadProgress value)  $default,){
final _that = this;
switch (_that) {
case _TextReadProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TextReadProgress value)?  $default,){
final _that = this;
switch (_that) {
case _TextReadProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int fieldId,  int totalUtf8Bytes,  int loadedUtf8Bytes,  String text,  bool complete,  bool loading,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TextReadProgress() when $default != null:
return $default(_that.fieldId,_that.totalUtf8Bytes,_that.loadedUtf8Bytes,_that.text,_that.complete,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int fieldId,  int totalUtf8Bytes,  int loadedUtf8Bytes,  String text,  bool complete,  bool loading,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _TextReadProgress():
return $default(_that.fieldId,_that.totalUtf8Bytes,_that.loadedUtf8Bytes,_that.text,_that.complete,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int fieldId,  int totalUtf8Bytes,  int loadedUtf8Bytes,  String text,  bool complete,  bool loading,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _TextReadProgress() when $default != null:
return $default(_that.fieldId,_that.totalUtf8Bytes,_that.loadedUtf8Bytes,_that.text,_that.complete,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TextReadProgress implements TextReadProgress {
  const _TextReadProgress({required this.fieldId, required this.totalUtf8Bytes, this.loadedUtf8Bytes = 0, this.text = '', this.complete = false, this.loading = false, this.error});


@override final  int fieldId;
@override final  int totalUtf8Bytes;
@override@JsonKey() final  int loadedUtf8Bytes;
@override@JsonKey() final  String text;
@override@JsonKey() final  bool complete;
@override@JsonKey() final  bool loading;
@override final  StudioFailure? error;

/// Create a copy of TextReadProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TextReadProgressCopyWith<_TextReadProgress> get copyWith => __$TextReadProgressCopyWithImpl<_TextReadProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TextReadProgress&&(identical(other.fieldId, fieldId) || other.fieldId == fieldId)&&(identical(other.totalUtf8Bytes, totalUtf8Bytes) || other.totalUtf8Bytes == totalUtf8Bytes)&&(identical(other.loadedUtf8Bytes, loadedUtf8Bytes) || other.loadedUtf8Bytes == loadedUtf8Bytes)&&(identical(other.text, text) || other.text == text)&&(identical(other.complete, complete) || other.complete == complete)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fieldId,totalUtf8Bytes,loadedUtf8Bytes,text,complete,loading,error);
}



}

/// @nodoc
abstract mixin class _$TextReadProgressCopyWith<$Res> implements $TextReadProgressCopyWith<$Res> {
  factory _$TextReadProgressCopyWith(_TextReadProgress value, $Res Function(_TextReadProgress) _then) = __$TextReadProgressCopyWithImpl;
@override @useResult
$Res call({
 int fieldId, int totalUtf8Bytes, int loadedUtf8Bytes, String text, bool complete, bool loading, StudioFailure? error
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$TextReadProgressCopyWithImpl<$Res>
    implements _$TextReadProgressCopyWith<$Res> {
  __$TextReadProgressCopyWithImpl(this._self, this._then);

  final _TextReadProgress _self;
  final $Res Function(_TextReadProgress) _then;

/// Create a copy of TextReadProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fieldId = null,Object? totalUtf8Bytes = null,Object? loadedUtf8Bytes = null,Object? text = null,Object? complete = null,Object? loading = null,Object? error = freezed,}) {
  return _then(_TextReadProgress(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int,totalUtf8Bytes: null == totalUtf8Bytes ? _self.totalUtf8Bytes : totalUtf8Bytes // ignore: cast_nullable_to_non_nullable
as int,loadedUtf8Bytes: null == loadedUtf8Bytes ? _self.loadedUtf8Bytes : loadedUtf8Bytes // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of TextReadProgress
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
