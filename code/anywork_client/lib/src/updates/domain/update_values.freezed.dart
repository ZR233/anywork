// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateControls {

 bool get enabled;
/// Create a copy of UpdateControls
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateControlsCopyWith<UpdateControls> get copyWith => _$UpdateControlsCopyWithImpl<UpdateControls>(this as UpdateControls, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateControls;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateControls&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled));
}


@override
int get hashCode {
  final _this = this as UpdateControls;
  return Object.hash(runtimeType,_this.enabled);
}

@override
String toString() {
  final _this = this as UpdateControls;
  return 'UpdateControls(enabled: ${_this.enabled})';
}


}

/// @nodoc
abstract mixin class $UpdateControlsCopyWith<$Res>  {
  factory $UpdateControlsCopyWith(UpdateControls value, $Res Function(UpdateControls) _then) = _$UpdateControlsCopyWithImpl;
@useResult
$Res call({
 bool enabled
});




}
/// @nodoc
class _$UpdateControlsCopyWithImpl<$Res>
    implements $UpdateControlsCopyWith<$Res> {
  _$UpdateControlsCopyWithImpl(this._self, this._then);

  final UpdateControls _self;
  final $Res Function(UpdateControls) _then;

/// Create a copy of UpdateControls
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,}) {
  return _then(UpdateControls(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateControls].
extension UpdateControlsPatterns on UpdateControls {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateControls value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateControls() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateControls value)  $default,){
final _that = this;
switch (_that) {
case _UpdateControls():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateControls value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateControls() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateControls() when $default != null:
return $default(_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled)  $default,) {final _that = this;
switch (_that) {
case _UpdateControls():
return $default(_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _UpdateControls() when $default != null:
return $default(_that.enabled);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateControls implements UpdateControls {
  const _UpdateControls({required this.enabled});


@override final  bool enabled;

/// Create a copy of UpdateControls
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateControlsCopyWith<_UpdateControls> get copyWith => __$UpdateControlsCopyWithImpl<_UpdateControls>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateControls&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled);
}

@override
String toString() {
    return 'UpdateControls(enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$UpdateControlsCopyWith<$Res> implements $UpdateControlsCopyWith<$Res> {
  factory _$UpdateControlsCopyWith(_UpdateControls value, $Res Function(_UpdateControls) _then) = __$UpdateControlsCopyWithImpl;
@override @useResult
$Res call({
 bool enabled
});




}
/// @nodoc
class __$UpdateControlsCopyWithImpl<$Res>
    implements _$UpdateControlsCopyWith<$Res> {
  __$UpdateControlsCopyWithImpl(this._self, this._then);

  final _UpdateControls _self;
  final $Res Function(_UpdateControls) _then;

/// Create a copy of UpdateControls
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,}) {
  return _then(_UpdateControls(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$UpdatePreparationResult {

 String? get readyVersion;
/// Create a copy of UpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatePreparationResultCopyWith<UpdatePreparationResult> get copyWith => _$UpdatePreparationResultCopyWithImpl<UpdatePreparationResult>(this as UpdatePreparationResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatePreparationResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatePreparationResult&&(identical(other.readyVersion, _this.readyVersion) || other.readyVersion == _this.readyVersion));
}


@override
int get hashCode {
  final _this = this as UpdatePreparationResult;
  return Object.hash(runtimeType,_this.readyVersion);
}

@override
String toString() {
  final _this = this as UpdatePreparationResult;
  return 'UpdatePreparationResult(readyVersion: ${_this.readyVersion})';
}


}

/// @nodoc
abstract mixin class $UpdatePreparationResultCopyWith<$Res>  {
  factory $UpdatePreparationResultCopyWith(UpdatePreparationResult value, $Res Function(UpdatePreparationResult) _then) = _$UpdatePreparationResultCopyWithImpl;
@useResult
$Res call({
 String? readyVersion
});




}
/// @nodoc
class _$UpdatePreparationResultCopyWithImpl<$Res>
    implements $UpdatePreparationResultCopyWith<$Res> {
  _$UpdatePreparationResultCopyWithImpl(this._self, this._then);

  final UpdatePreparationResult _self;
  final $Res Function(UpdatePreparationResult) _then;

/// Create a copy of UpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? readyVersion = freezed,}) {
  return _then(UpdatePreparationResult(
readyVersion: freezed == readyVersion ? _self.readyVersion : readyVersion // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdatePreparationResult].
extension UpdatePreparationResultPatterns on UpdatePreparationResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatePreparationResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatePreparationResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatePreparationResult value)  $default,){
final _that = this;
switch (_that) {
case _UpdatePreparationResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatePreparationResult value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatePreparationResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? readyVersion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatePreparationResult() when $default != null:
return $default(_that.readyVersion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? readyVersion)  $default,) {final _that = this;
switch (_that) {
case _UpdatePreparationResult():
return $default(_that.readyVersion);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? readyVersion)?  $default,) {final _that = this;
switch (_that) {
case _UpdatePreparationResult() when $default != null:
return $default(_that.readyVersion);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatePreparationResult implements UpdatePreparationResult {
  const _UpdatePreparationResult({required this.readyVersion});


@override final  String? readyVersion;

/// Create a copy of UpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatePreparationResultCopyWith<_UpdatePreparationResult> get copyWith => __$UpdatePreparationResultCopyWithImpl<_UpdatePreparationResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatePreparationResult&&(identical(other.readyVersion, readyVersion) || other.readyVersion == readyVersion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,readyVersion);
}

@override
String toString() {
    return 'UpdatePreparationResult(readyVersion: $readyVersion)';
}


}

/// @nodoc
abstract mixin class _$UpdatePreparationResultCopyWith<$Res> implements $UpdatePreparationResultCopyWith<$Res> {
  factory _$UpdatePreparationResultCopyWith(_UpdatePreparationResult value, $Res Function(_UpdatePreparationResult) _then) = __$UpdatePreparationResultCopyWithImpl;
@override @useResult
$Res call({
 String? readyVersion
});




}
/// @nodoc
class __$UpdatePreparationResultCopyWithImpl<$Res>
    implements _$UpdatePreparationResultCopyWith<$Res> {
  __$UpdatePreparationResultCopyWithImpl(this._self, this._then);

  final _UpdatePreparationResult _self;
  final $Res Function(_UpdatePreparationResult) _then;

/// Create a copy of UpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? readyVersion = freezed,}) {
  return _then(_UpdatePreparationResult(
readyVersion: freezed == readyVersion ? _self.readyVersion : readyVersion // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$UpdateSummary {

 String get version; int get publishedAt; String get notesUrl;
/// Create a copy of UpdateSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<UpdateSummary> get copyWith => _$UpdateSummaryCopyWithImpl<UpdateSummary>(this as UpdateSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateSummary&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.publishedAt, _this.publishedAt) || other.publishedAt == _this.publishedAt)&&(identical(other.notesUrl, _this.notesUrl) || other.notesUrl == _this.notesUrl));
}


@override
int get hashCode {
  final _this = this as UpdateSummary;
  return Object.hash(runtimeType,_this.version,_this.publishedAt,_this.notesUrl);
}



}

/// @nodoc
abstract mixin class $UpdateSummaryCopyWith<$Res>  {
  factory $UpdateSummaryCopyWith(UpdateSummary value, $Res Function(UpdateSummary) _then) = _$UpdateSummaryCopyWithImpl;
@useResult
$Res call({
 String version, int publishedAt, String notesUrl
});




}
/// @nodoc
class _$UpdateSummaryCopyWithImpl<$Res>
    implements $UpdateSummaryCopyWith<$Res> {
  _$UpdateSummaryCopyWithImpl(this._self, this._then);

  final UpdateSummary _self;
  final $Res Function(UpdateSummary) _then;

/// Create a copy of UpdateSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? publishedAt = null,Object? notesUrl = null,}) {
  return _then(UpdateSummary(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as int,notesUrl: null == notesUrl ? _self.notesUrl : notesUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateSummary].
extension UpdateSummaryPatterns on UpdateSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateSummary value)  $default,){
final _that = this;
switch (_that) {
case _UpdateSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateSummary value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  int publishedAt,  String notesUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateSummary() when $default != null:
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  int publishedAt,  String notesUrl)  $default,) {final _that = this;
switch (_that) {
case _UpdateSummary():
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  int publishedAt,  String notesUrl)?  $default,) {final _that = this;
switch (_that) {
case _UpdateSummary() when $default != null:
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateSummary implements UpdateSummary {
  const _UpdateSummary({required this.version, required this.publishedAt, required this.notesUrl});


@override final  String version;
@override final  int publishedAt;
@override final  String notesUrl;

/// Create a copy of UpdateSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateSummaryCopyWith<_UpdateSummary> get copyWith => __$UpdateSummaryCopyWithImpl<_UpdateSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateSummary&&(identical(other.version, version) || other.version == version)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&(identical(other.notesUrl, notesUrl) || other.notesUrl == notesUrl));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version,publishedAt,notesUrl);
}



}

/// @nodoc
abstract mixin class _$UpdateSummaryCopyWith<$Res> implements $UpdateSummaryCopyWith<$Res> {
  factory _$UpdateSummaryCopyWith(_UpdateSummary value, $Res Function(_UpdateSummary) _then) = __$UpdateSummaryCopyWithImpl;
@override @useResult
$Res call({
 String version, int publishedAt, String notesUrl
});




}
/// @nodoc
class __$UpdateSummaryCopyWithImpl<$Res>
    implements _$UpdateSummaryCopyWith<$Res> {
  __$UpdateSummaryCopyWithImpl(this._self, this._then);

  final _UpdateSummary _self;
  final $Res Function(_UpdateSummary) _then;

/// Create a copy of UpdateSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? publishedAt = null,Object? notesUrl = null,}) {
  return _then(_UpdateSummary(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as int,notesUrl: null == notesUrl ? _self.notesUrl : notesUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$UpdateAsset {

 String get url; int get size; String get sha256; String get signature;
/// Create a copy of UpdateAsset
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateAssetCopyWith<UpdateAsset> get copyWith => _$UpdateAssetCopyWithImpl<UpdateAsset>(this as UpdateAsset, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateAsset;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateAsset&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256)&&(identical(other.signature, _this.signature) || other.signature == _this.signature));
}


@override
int get hashCode {
  final _this = this as UpdateAsset;
  return Object.hash(runtimeType,_this.url,_this.size,_this.sha256,_this.signature);
}



}

/// @nodoc
abstract mixin class $UpdateAssetCopyWith<$Res>  {
  factory $UpdateAssetCopyWith(UpdateAsset value, $Res Function(UpdateAsset) _then) = _$UpdateAssetCopyWithImpl;
@useResult
$Res call({
 String url, int size, String sha256, String signature
});




}
/// @nodoc
class _$UpdateAssetCopyWithImpl<$Res>
    implements $UpdateAssetCopyWith<$Res> {
  _$UpdateAssetCopyWithImpl(this._self, this._then);

  final UpdateAsset _self;
  final $Res Function(UpdateAsset) _then;

/// Create a copy of UpdateAsset
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? size = null,Object? sha256 = null,Object? signature = null,}) {
  return _then(UpdateAsset(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,signature: null == signature ? _self.signature : signature // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateAsset].
extension UpdateAssetPatterns on UpdateAsset {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateAsset value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateAsset() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateAsset value)  $default,){
final _that = this;
switch (_that) {
case _UpdateAsset():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateAsset value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateAsset() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  int size,  String sha256,  String signature)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateAsset() when $default != null:
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  int size,  String sha256,  String signature)  $default,) {final _that = this;
switch (_that) {
case _UpdateAsset():
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  int size,  String sha256,  String signature)?  $default,) {final _that = this;
switch (_that) {
case _UpdateAsset() when $default != null:
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateAsset implements UpdateAsset {
  const _UpdateAsset({required this.url, required this.size, required this.sha256, required this.signature});


@override final  String url;
@override final  int size;
@override final  String sha256;
@override final  String signature;

/// Create a copy of UpdateAsset
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateAssetCopyWith<_UpdateAsset> get copyWith => __$UpdateAssetCopyWithImpl<_UpdateAsset>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateAsset&&(identical(other.url, url) || other.url == url)&&(identical(other.size, size) || other.size == size)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.signature, signature) || other.signature == signature));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url,size,sha256,signature);
}



}

/// @nodoc
abstract mixin class _$UpdateAssetCopyWith<$Res> implements $UpdateAssetCopyWith<$Res> {
  factory _$UpdateAssetCopyWith(_UpdateAsset value, $Res Function(_UpdateAsset) _then) = __$UpdateAssetCopyWithImpl;
@override @useResult
$Res call({
 String url, int size, String sha256, String signature
});




}
/// @nodoc
class __$UpdateAssetCopyWithImpl<$Res>
    implements _$UpdateAssetCopyWith<$Res> {
  __$UpdateAssetCopyWithImpl(this._self, this._then);

  final _UpdateAsset _self;
  final $Res Function(_UpdateAsset) _then;

/// Create a copy of UpdateAsset
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? size = null,Object? sha256 = null,Object? signature = null,}) {
  return _then(_UpdateAsset(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,signature: null == signature ? _self.signature : signature // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$UpdateDetails {

 UpdateSummary get summary; UpdateAsset get installer;
/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDetailsCopyWith<UpdateDetails> get copyWith => _$UpdateDetailsCopyWithImpl<UpdateDetails>(this as UpdateDetails, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateDetails;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDetails&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.installer, _this.installer) || other.installer == _this.installer));
}


@override
int get hashCode {
  final _this = this as UpdateDetails;
  return Object.hash(runtimeType,_this.summary,_this.installer);
}



}

/// @nodoc
abstract mixin class $UpdateDetailsCopyWith<$Res>  {
  factory $UpdateDetailsCopyWith(UpdateDetails value, $Res Function(UpdateDetails) _then) = _$UpdateDetailsCopyWithImpl;
@useResult
$Res call({
 UpdateSummary summary, UpdateAsset installer
});


$UpdateSummaryCopyWith<$Res> get summary;$UpdateAssetCopyWith<$Res> get installer;

}
/// @nodoc
class _$UpdateDetailsCopyWithImpl<$Res>
    implements $UpdateDetailsCopyWith<$Res> {
  _$UpdateDetailsCopyWithImpl(this._self, this._then);

  final UpdateDetails _self;
  final $Res Function(UpdateDetails) _then;

/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? installer = null,}) {
  return _then(UpdateDetails(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummary,installer: null == installer ? _self.installer : installer // ignore: cast_nullable_to_non_nullable
as UpdateAsset,
  ));
}
/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get summary {

  return $UpdateSummaryCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateAssetCopyWith<$Res> get installer {

  return $UpdateAssetCopyWith<$Res>(_self.installer, (value) {
    return _then(_self.copyWith(installer: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateDetails].
extension UpdateDetailsPatterns on UpdateDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateDetails() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateDetails value)  $default,){
final _that = this;
switch (_that) {
case _UpdateDetails():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateDetails value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateDetails() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdateSummary summary,  UpdateAsset installer)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateDetails() when $default != null:
return $default(_that.summary,_that.installer);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdateSummary summary,  UpdateAsset installer)  $default,) {final _that = this;
switch (_that) {
case _UpdateDetails():
return $default(_that.summary,_that.installer);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdateSummary summary,  UpdateAsset installer)?  $default,) {final _that = this;
switch (_that) {
case _UpdateDetails() when $default != null:
return $default(_that.summary,_that.installer);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateDetails implements UpdateDetails {
  const _UpdateDetails({required this.summary, required this.installer});


@override final  UpdateSummary summary;
@override final  UpdateAsset installer;

/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateDetailsCopyWith<_UpdateDetails> get copyWith => __$UpdateDetailsCopyWithImpl<_UpdateDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateDetails&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.installer, installer) || other.installer == installer));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summary,installer);
}



}

/// @nodoc
abstract mixin class _$UpdateDetailsCopyWith<$Res> implements $UpdateDetailsCopyWith<$Res> {
  factory _$UpdateDetailsCopyWith(_UpdateDetails value, $Res Function(_UpdateDetails) _then) = __$UpdateDetailsCopyWithImpl;
@override @useResult
$Res call({
 UpdateSummary summary, UpdateAsset installer
});


@override $UpdateSummaryCopyWith<$Res> get summary;@override $UpdateAssetCopyWith<$Res> get installer;

}
/// @nodoc
class __$UpdateDetailsCopyWithImpl<$Res>
    implements _$UpdateDetailsCopyWith<$Res> {
  __$UpdateDetailsCopyWithImpl(this._self, this._then);

  final _UpdateDetails _self;
  final $Res Function(_UpdateDetails) _then;

/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? summary = null,Object? installer = null,}) {
  return _then(_UpdateDetails(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummary,installer: null == installer ? _self.installer : installer // ignore: cast_nullable_to_non_nullable
as UpdateAsset,
  ));
}

/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get summary {

  return $UpdateSummaryCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdateDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateAssetCopyWith<$Res> get installer {

  return $UpdateAssetCopyWith<$Res>(_self.installer, (value) {
    return _then(_self.copyWith(installer: value));
  });
}
}

/// @nodoc
mixin _$UpdatesValue {

 int get revision;
/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesValueCopyWith<UpdatesValue> get copyWith => _$UpdatesValueCopyWithImpl<UpdatesValue>(this as UpdatesValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesValue&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdatesValue;
  return Object.hash(runtimeType,_this.revision);
}



}

/// @nodoc
abstract mixin class $UpdatesValueCopyWith<$Res>  {
  factory $UpdatesValueCopyWith(UpdatesValue value, $Res Function(UpdatesValue) _then) = _$UpdatesValueCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$UpdatesValueCopyWithImpl<$Res>
    implements $UpdatesValueCopyWith<$Res> {
  _$UpdatesValueCopyWithImpl(this._self, this._then);

  final UpdatesValue _self;
  final $Res Function(UpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdatesValue].
extension UpdatesValuePatterns on UpdatesValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisabledUpdatesValue value)?  disabled,TResult Function( IdleUpdatesValue value)?  idle,TResult Function( CheckingUpdatesValue value)?  checking,TResult Function( UpToDateUpdatesValue value)?  upToDate,TResult Function( AvailableUpdatesValue value)?  available,TResult Function( DownloadingUpdatesValue value)?  downloading,TResult Function( VerifyingUpdatesValue value)?  verifying,TResult Function( ReadyUpdatesValue value)?  ready,TResult Function( InstallerLaunchedUpdatesValue value)?  installerLaunched,TResult Function( CheckFailedUpdatesValue value)?  checkFailed,TResult Function( InstallFailedUpdatesValue value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisabledUpdatesValue() when disabled != null:
return disabled(_that);case IdleUpdatesValue() when idle != null:
return idle(_that);case CheckingUpdatesValue() when checking != null:
return checking(_that);case UpToDateUpdatesValue() when upToDate != null:
return upToDate(_that);case AvailableUpdatesValue() when available != null:
return available(_that);case DownloadingUpdatesValue() when downloading != null:
return downloading(_that);case VerifyingUpdatesValue() when verifying != null:
return verifying(_that);case ReadyUpdatesValue() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesValue() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesValue() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesValue() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisabledUpdatesValue value)  disabled,required TResult Function( IdleUpdatesValue value)  idle,required TResult Function( CheckingUpdatesValue value)  checking,required TResult Function( UpToDateUpdatesValue value)  upToDate,required TResult Function( AvailableUpdatesValue value)  available,required TResult Function( DownloadingUpdatesValue value)  downloading,required TResult Function( VerifyingUpdatesValue value)  verifying,required TResult Function( ReadyUpdatesValue value)  ready,required TResult Function( InstallerLaunchedUpdatesValue value)  installerLaunched,required TResult Function( CheckFailedUpdatesValue value)  checkFailed,required TResult Function( InstallFailedUpdatesValue value)  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesValue():
return disabled(_that);case IdleUpdatesValue():
return idle(_that);case CheckingUpdatesValue():
return checking(_that);case UpToDateUpdatesValue():
return upToDate(_that);case AvailableUpdatesValue():
return available(_that);case DownloadingUpdatesValue():
return downloading(_that);case VerifyingUpdatesValue():
return verifying(_that);case ReadyUpdatesValue():
return ready(_that);case InstallerLaunchedUpdatesValue():
return installerLaunched(_that);case CheckFailedUpdatesValue():
return checkFailed(_that);case InstallFailedUpdatesValue():
return installFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisabledUpdatesValue value)?  disabled,TResult? Function( IdleUpdatesValue value)?  idle,TResult? Function( CheckingUpdatesValue value)?  checking,TResult? Function( UpToDateUpdatesValue value)?  upToDate,TResult? Function( AvailableUpdatesValue value)?  available,TResult? Function( DownloadingUpdatesValue value)?  downloading,TResult? Function( VerifyingUpdatesValue value)?  verifying,TResult? Function( ReadyUpdatesValue value)?  ready,TResult? Function( InstallerLaunchedUpdatesValue value)?  installerLaunched,TResult? Function( CheckFailedUpdatesValue value)?  checkFailed,TResult? Function( InstallFailedUpdatesValue value)?  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesValue() when disabled != null:
return disabled(_that);case IdleUpdatesValue() when idle != null:
return idle(_that);case CheckingUpdatesValue() when checking != null:
return checking(_that);case UpToDateUpdatesValue() when upToDate != null:
return upToDate(_that);case AvailableUpdatesValue() when available != null:
return available(_that);case DownloadingUpdatesValue() when downloading != null:
return downloading(_that);case VerifyingUpdatesValue() when verifying != null:
return verifying(_that);case ReadyUpdatesValue() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesValue() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesValue() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesValue() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  disabled,TResult Function( int revision,  int updatedAt)?  idle,TResult Function( int revision,  String operationId,  int startedAt)?  checking,TResult Function( int revision,  int checkedAt)?  upToDate,TResult Function( int revision,  int checkedAt,  UpdateSummary update)?  available,TResult Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)?  downloading,TResult Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)?  verifying,TResult Function( int revision,  int readyAt,  UpdateSummary update)?  ready,TResult Function( int revision,  int launchedAt,  UpdateSummary update)?  installerLaunched,TResult Function( int revision,  int failedAt,  SourceStateError error)?  checkFailed,TResult Function( int revision,  int failedAt,  UpdateSummary update,  SourceStateError error)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisabledUpdatesValue() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesValue() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesValue() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesValue() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesValue() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesValue() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesValue() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesValue() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesValue() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesValue() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesValue() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  disabled,required TResult Function( int revision,  int updatedAt)  idle,required TResult Function( int revision,  String operationId,  int startedAt)  checking,required TResult Function( int revision,  int checkedAt)  upToDate,required TResult Function( int revision,  int checkedAt,  UpdateSummary update)  available,required TResult Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)  downloading,required TResult Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)  verifying,required TResult Function( int revision,  int readyAt,  UpdateSummary update)  ready,required TResult Function( int revision,  int launchedAt,  UpdateSummary update)  installerLaunched,required TResult Function( int revision,  int failedAt,  SourceStateError error)  checkFailed,required TResult Function( int revision,  int failedAt,  UpdateSummary update,  SourceStateError error)  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesValue():
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesValue():
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesValue():
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesValue():
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesValue():
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesValue():
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesValue():
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesValue():
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesValue():
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesValue():
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesValue():
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  disabled,TResult? Function( int revision,  int updatedAt)?  idle,TResult? Function( int revision,  String operationId,  int startedAt)?  checking,TResult? Function( int revision,  int checkedAt)?  upToDate,TResult? Function( int revision,  int checkedAt,  UpdateSummary update)?  available,TResult? Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)?  downloading,TResult? Function( int revision,  int updatedAt,  UpdateSummary update,  int downloaded,  int total)?  verifying,TResult? Function( int revision,  int readyAt,  UpdateSummary update)?  ready,TResult? Function( int revision,  int launchedAt,  UpdateSummary update)?  installerLaunched,TResult? Function( int revision,  int failedAt,  SourceStateError error)?  checkFailed,TResult? Function( int revision,  int failedAt,  UpdateSummary update,  SourceStateError error)?  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesValue() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesValue() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesValue() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesValue() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesValue() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesValue() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesValue() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesValue() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesValue() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesValue() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesValue() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class DisabledUpdatesValue implements UpdatesValue {
  const DisabledUpdatesValue({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledUpdatesValueCopyWith<DisabledUpdatesValue> get copyWith => _$DisabledUpdatesValueCopyWithImpl<DisabledUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $DisabledUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $DisabledUpdatesValueCopyWith(DisabledUpdatesValue value, $Res Function(DisabledUpdatesValue) _then) = _$DisabledUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$DisabledUpdatesValueCopyWithImpl<$Res>
    implements $DisabledUpdatesValueCopyWith<$Res> {
  _$DisabledUpdatesValueCopyWithImpl(this._self, this._then);

  final DisabledUpdatesValue _self;
  final $Res Function(DisabledUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(DisabledUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class IdleUpdatesValue implements UpdatesValue {
  const IdleUpdatesValue({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdleUpdatesValueCopyWith<IdleUpdatesValue> get copyWith => _$IdleUpdatesValueCopyWithImpl<IdleUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $IdleUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $IdleUpdatesValueCopyWith(IdleUpdatesValue value, $Res Function(IdleUpdatesValue) _then) = _$IdleUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$IdleUpdatesValueCopyWithImpl<$Res>
    implements $IdleUpdatesValueCopyWith<$Res> {
  _$IdleUpdatesValueCopyWithImpl(this._self, this._then);

  final IdleUpdatesValue _self;
  final $Res Function(IdleUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(IdleUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CheckingUpdatesValue implements UpdatesValue {
  const CheckingUpdatesValue({required this.revision, required this.operationId, required this.startedAt});


@override final  int revision;
 final  String operationId;
 final  int startedAt;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingUpdatesValueCopyWith<CheckingUpdatesValue> get copyWith => _$CheckingUpdatesValueCopyWithImpl<CheckingUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operationId,startedAt);
}



}

/// @nodoc
abstract mixin class $CheckingUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $CheckingUpdatesValueCopyWith(CheckingUpdatesValue value, $Res Function(CheckingUpdatesValue) _then) = _$CheckingUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, String operationId, int startedAt
});




}
/// @nodoc
class _$CheckingUpdatesValueCopyWithImpl<$Res>
    implements $CheckingUpdatesValueCopyWith<$Res> {
  _$CheckingUpdatesValueCopyWithImpl(this._self, this._then);

  final CheckingUpdatesValue _self;
  final $Res Function(CheckingUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(CheckingUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class UpToDateUpdatesValue implements UpdatesValue {
  const UpToDateUpdatesValue({required this.revision, required this.checkedAt});


@override final  int revision;
 final  int checkedAt;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpToDateUpdatesValueCopyWith<UpToDateUpdatesValue> get copyWith => _$UpToDateUpdatesValueCopyWithImpl<UpToDateUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpToDateUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}



}

/// @nodoc
abstract mixin class $UpToDateUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $UpToDateUpdatesValueCopyWith(UpToDateUpdatesValue value, $Res Function(UpToDateUpdatesValue) _then) = _$UpToDateUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt
});




}
/// @nodoc
class _$UpToDateUpdatesValueCopyWithImpl<$Res>
    implements $UpToDateUpdatesValueCopyWith<$Res> {
  _$UpToDateUpdatesValueCopyWithImpl(this._self, this._then);

  final UpToDateUpdatesValue _self;
  final $Res Function(UpToDateUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(UpToDateUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AvailableUpdatesValue implements UpdatesValue {
  const AvailableUpdatesValue({required this.revision, required this.checkedAt, required this.update});


@override final  int revision;
 final  int checkedAt;
 final  UpdateSummary update;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableUpdatesValueCopyWith<AvailableUpdatesValue> get copyWith => _$AvailableUpdatesValueCopyWithImpl<AvailableUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt,update);
}



}

/// @nodoc
abstract mixin class $AvailableUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $AvailableUpdatesValueCopyWith(AvailableUpdatesValue value, $Res Function(AvailableUpdatesValue) _then) = _$AvailableUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt, UpdateSummary update
});


$UpdateSummaryCopyWith<$Res> get update;

}
/// @nodoc
class _$AvailableUpdatesValueCopyWithImpl<$Res>
    implements $AvailableUpdatesValueCopyWith<$Res> {
  _$AvailableUpdatesValueCopyWithImpl(this._self, this._then);

  final AvailableUpdatesValue _self;
  final $Res Function(AvailableUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,Object? update = null,}) {
  return _then(AvailableUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class DownloadingUpdatesValue implements UpdatesValue {
  const DownloadingUpdatesValue({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  UpdateSummary update;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadingUpdatesValueCopyWith<DownloadingUpdatesValue> get copyWith => _$DownloadingUpdatesValueCopyWithImpl<DownloadingUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadingUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}



}

/// @nodoc
abstract mixin class $DownloadingUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $DownloadingUpdatesValueCopyWith(DownloadingUpdatesValue value, $Res Function(DownloadingUpdatesValue) _then) = _$DownloadingUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, UpdateSummary update, int downloaded, int total
});


$UpdateSummaryCopyWith<$Res> get update;

}
/// @nodoc
class _$DownloadingUpdatesValueCopyWithImpl<$Res>
    implements $DownloadingUpdatesValueCopyWith<$Res> {
  _$DownloadingUpdatesValueCopyWithImpl(this._self, this._then);

  final DownloadingUpdatesValue _self;
  final $Res Function(DownloadingUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(DownloadingUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class VerifyingUpdatesValue implements UpdatesValue {
  const VerifyingUpdatesValue({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  UpdateSummary update;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VerifyingUpdatesValueCopyWith<VerifyingUpdatesValue> get copyWith => _$VerifyingUpdatesValueCopyWithImpl<VerifyingUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerifyingUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}



}

/// @nodoc
abstract mixin class $VerifyingUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $VerifyingUpdatesValueCopyWith(VerifyingUpdatesValue value, $Res Function(VerifyingUpdatesValue) _then) = _$VerifyingUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, UpdateSummary update, int downloaded, int total
});


$UpdateSummaryCopyWith<$Res> get update;

}
/// @nodoc
class _$VerifyingUpdatesValueCopyWithImpl<$Res>
    implements $VerifyingUpdatesValueCopyWith<$Res> {
  _$VerifyingUpdatesValueCopyWithImpl(this._self, this._then);

  final VerifyingUpdatesValue _self;
  final $Res Function(VerifyingUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(VerifyingUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class ReadyUpdatesValue implements UpdatesValue {
  const ReadyUpdatesValue({required this.revision, required this.readyAt, required this.update});


@override final  int revision;
 final  int readyAt;
 final  UpdateSummary update;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyUpdatesValueCopyWith<ReadyUpdatesValue> get copyWith => _$ReadyUpdatesValueCopyWithImpl<ReadyUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt,update);
}



}

/// @nodoc
abstract mixin class $ReadyUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $ReadyUpdatesValueCopyWith(ReadyUpdatesValue value, $Res Function(ReadyUpdatesValue) _then) = _$ReadyUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int readyAt, UpdateSummary update
});


$UpdateSummaryCopyWith<$Res> get update;

}
/// @nodoc
class _$ReadyUpdatesValueCopyWithImpl<$Res>
    implements $ReadyUpdatesValueCopyWith<$Res> {
  _$ReadyUpdatesValueCopyWithImpl(this._self, this._then);

  final ReadyUpdatesValue _self;
  final $Res Function(ReadyUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,Object? update = null,}) {
  return _then(ReadyUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class InstallerLaunchedUpdatesValue implements UpdatesValue {
  const InstallerLaunchedUpdatesValue({required this.revision, required this.launchedAt, required this.update});


@override final  int revision;
 final  int launchedAt;
 final  UpdateSummary update;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallerLaunchedUpdatesValueCopyWith<InstallerLaunchedUpdatesValue> get copyWith => _$InstallerLaunchedUpdatesValueCopyWithImpl<InstallerLaunchedUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchedUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.launchedAt, launchedAt) || other.launchedAt == launchedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,launchedAt,update);
}



}

/// @nodoc
abstract mixin class $InstallerLaunchedUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $InstallerLaunchedUpdatesValueCopyWith(InstallerLaunchedUpdatesValue value, $Res Function(InstallerLaunchedUpdatesValue) _then) = _$InstallerLaunchedUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int launchedAt, UpdateSummary update
});


$UpdateSummaryCopyWith<$Res> get update;

}
/// @nodoc
class _$InstallerLaunchedUpdatesValueCopyWithImpl<$Res>
    implements $InstallerLaunchedUpdatesValueCopyWith<$Res> {
  _$InstallerLaunchedUpdatesValueCopyWithImpl(this._self, this._then);

  final InstallerLaunchedUpdatesValue _self;
  final $Res Function(InstallerLaunchedUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? launchedAt = null,Object? update = null,}) {
  return _then(InstallerLaunchedUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,launchedAt: null == launchedAt ? _self.launchedAt : launchedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class CheckFailedUpdatesValue implements UpdatesValue {
  const CheckFailedUpdatesValue({required this.revision, required this.failedAt, required this.error});


@override final  int revision;
 final  int failedAt;
 final  SourceStateError error;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckFailedUpdatesValueCopyWith<CheckFailedUpdatesValue> get copyWith => _$CheckFailedUpdatesValueCopyWithImpl<CheckFailedUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckFailedUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,error);
}



}

/// @nodoc
abstract mixin class $CheckFailedUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $CheckFailedUpdatesValueCopyWith(CheckFailedUpdatesValue value, $Res Function(CheckFailedUpdatesValue) _then) = _$CheckFailedUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$CheckFailedUpdatesValueCopyWithImpl<$Res>
    implements $CheckFailedUpdatesValueCopyWith<$Res> {
  _$CheckFailedUpdatesValueCopyWithImpl(this._self, this._then);

  final CheckFailedUpdatesValue _self;
  final $Res Function(CheckFailedUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? error = null,}) {
  return _then(CheckFailedUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class InstallFailedUpdatesValue implements UpdatesValue {
  const InstallFailedUpdatesValue({required this.revision, required this.failedAt, required this.update, required this.error});


@override final  int revision;
 final  int failedAt;
 final  UpdateSummary update;
 final  SourceStateError error;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallFailedUpdatesValueCopyWith<InstallFailedUpdatesValue> get copyWith => _$InstallFailedUpdatesValueCopyWithImpl<InstallFailedUpdatesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallFailedUpdatesValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,update,error);
}



}

/// @nodoc
abstract mixin class $InstallFailedUpdatesValueCopyWith<$Res> implements $UpdatesValueCopyWith<$Res> {
  factory $InstallFailedUpdatesValueCopyWith(InstallFailedUpdatesValue value, $Res Function(InstallFailedUpdatesValue) _then) = _$InstallFailedUpdatesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, UpdateSummary update, SourceStateError error
});


$UpdateSummaryCopyWith<$Res> get update;$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$InstallFailedUpdatesValueCopyWithImpl<$Res>
    implements $InstallFailedUpdatesValueCopyWith<$Res> {
  _$InstallFailedUpdatesValueCopyWithImpl(this._self, this._then);

  final InstallFailedUpdatesValue _self;
  final $Res Function(InstallFailedUpdatesValue) _then;

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? update = null,Object? error = null,}) {
  return _then(InstallFailedUpdatesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateSummary,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res> get update {

  return $UpdateSummaryCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}/// Create a copy of UpdatesValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
