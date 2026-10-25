// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ResourceStamp {

 String get resourceKey; String get ownerEpoch; int get revision;
/// Create a copy of ResourceStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceStampCopyWith<ResourceStamp> get copyWith => _$ResourceStampCopyWithImpl<ResourceStamp>(this as ResourceStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ResourceStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceStamp&&(identical(other.resourceKey, _this.resourceKey) || other.resourceKey == _this.resourceKey)&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ResourceStamp;
  return Object.hash(runtimeType,_this.resourceKey,_this.ownerEpoch,_this.revision);
}

@override
String toString() {
  final _this = this as ResourceStamp;
  return 'ResourceStamp(resourceKey: ${_this.resourceKey}, ownerEpoch: ${_this.ownerEpoch}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ResourceStampCopyWith<$Res>  {
  factory $ResourceStampCopyWith(ResourceStamp value, $Res Function(ResourceStamp) _then) = _$ResourceStampCopyWithImpl;
@useResult
$Res call({
 String resourceKey, String ownerEpoch, int revision
});




}
/// @nodoc
class _$ResourceStampCopyWithImpl<$Res>
    implements $ResourceStampCopyWith<$Res> {
  _$ResourceStampCopyWithImpl(this._self, this._then);

  final ResourceStamp _self;
  final $Res Function(ResourceStamp) _then;

/// Create a copy of ResourceStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? resourceKey = null,Object? ownerEpoch = null,Object? revision = null,}) {
  return _then(ResourceStamp(
resourceKey: null == resourceKey ? _self.resourceKey : resourceKey // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ResourceStamp].
extension ResourceStampPatterns on ResourceStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResourceStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResourceStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResourceStamp value)  $default,){
final _that = this;
switch (_that) {
case _ResourceStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResourceStamp value)?  $default,){
final _that = this;
switch (_that) {
case _ResourceStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String resourceKey,  String ownerEpoch,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResourceStamp() when $default != null:
return $default(_that.resourceKey,_that.ownerEpoch,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String resourceKey,  String ownerEpoch,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ResourceStamp():
return $default(_that.resourceKey,_that.ownerEpoch,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String resourceKey,  String ownerEpoch,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ResourceStamp() when $default != null:
return $default(_that.resourceKey,_that.ownerEpoch,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ResourceStamp extends ResourceStamp {
  const _ResourceStamp({required this.resourceKey, required this.ownerEpoch, required this.revision}): assert(revision >= 0),super._();


@override final  String resourceKey;
@override final  String ownerEpoch;
@override final  int revision;

/// Create a copy of ResourceStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResourceStampCopyWith<_ResourceStamp> get copyWith => __$ResourceStampCopyWithImpl<_ResourceStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResourceStamp&&(identical(other.resourceKey, resourceKey) || other.resourceKey == resourceKey)&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,resourceKey,ownerEpoch,revision);
}

@override
String toString() {
    return 'ResourceStamp(resourceKey: $resourceKey, ownerEpoch: $ownerEpoch, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ResourceStampCopyWith<$Res> implements $ResourceStampCopyWith<$Res> {
  factory _$ResourceStampCopyWith(_ResourceStamp value, $Res Function(_ResourceStamp) _then) = __$ResourceStampCopyWithImpl;
@override @useResult
$Res call({
 String resourceKey, String ownerEpoch, int revision
});




}
/// @nodoc
class __$ResourceStampCopyWithImpl<$Res>
    implements _$ResourceStampCopyWith<$Res> {
  __$ResourceStampCopyWithImpl(this._self, this._then);

  final _ResourceStamp _self;
  final $Res Function(_ResourceStamp) _then;

/// Create a copy of ResourceStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? resourceKey = null,Object? ownerEpoch = null,Object? revision = null,}) {
  return _then(_ResourceStamp(
resourceKey: null == resourceKey ? _self.resourceKey : resourceKey // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ViewStamp {

 String get threadId; String get viewId; String get viewEpoch; int get version;
/// Create a copy of ViewStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ViewStampCopyWith<ViewStamp> get copyWith => _$ViewStampCopyWithImpl<ViewStamp>(this as ViewStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ViewStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ViewStamp&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.viewId, _this.viewId) || other.viewId == _this.viewId)&&(identical(other.viewEpoch, _this.viewEpoch) || other.viewEpoch == _this.viewEpoch)&&(identical(other.version, _this.version) || other.version == _this.version));
}


@override
int get hashCode {
  final _this = this as ViewStamp;
  return Object.hash(runtimeType,_this.threadId,_this.viewId,_this.viewEpoch,_this.version);
}

@override
String toString() {
  final _this = this as ViewStamp;
  return 'ViewStamp(threadId: ${_this.threadId}, viewId: ${_this.viewId}, viewEpoch: ${_this.viewEpoch}, version: ${_this.version})';
}


}

/// @nodoc
abstract mixin class $ViewStampCopyWith<$Res>  {
  factory $ViewStampCopyWith(ViewStamp value, $Res Function(ViewStamp) _then) = _$ViewStampCopyWithImpl;
@useResult
$Res call({
 String threadId, String viewId, String viewEpoch, int version
});




}
/// @nodoc
class _$ViewStampCopyWithImpl<$Res>
    implements $ViewStampCopyWith<$Res> {
  _$ViewStampCopyWithImpl(this._self, this._then);

  final ViewStamp _self;
  final $Res Function(ViewStamp) _then;

/// Create a copy of ViewStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? viewId = null,Object? viewEpoch = null,Object? version = null,}) {
  return _then(ViewStamp(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,viewId: null == viewId ? _self.viewId : viewId // ignore: cast_nullable_to_non_nullable
as String,viewEpoch: null == viewEpoch ? _self.viewEpoch : viewEpoch // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ViewStamp].
extension ViewStampPatterns on ViewStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ViewStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ViewStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ViewStamp value)  $default,){
final _that = this;
switch (_that) {
case _ViewStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ViewStamp value)?  $default,){
final _that = this;
switch (_that) {
case _ViewStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String viewId,  String viewEpoch,  int version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ViewStamp() when $default != null:
return $default(_that.threadId,_that.viewId,_that.viewEpoch,_that.version);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String viewId,  String viewEpoch,  int version)  $default,) {final _that = this;
switch (_that) {
case _ViewStamp():
return $default(_that.threadId,_that.viewId,_that.viewEpoch,_that.version);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String viewId,  String viewEpoch,  int version)?  $default,) {final _that = this;
switch (_that) {
case _ViewStamp() when $default != null:
return $default(_that.threadId,_that.viewId,_that.viewEpoch,_that.version);case _:
  return null;

}
}

}

/// @nodoc


class _ViewStamp extends ViewStamp {
  const _ViewStamp({required this.threadId, required this.viewId, required this.viewEpoch, required this.version}): assert(version >= 0),super._();


@override final  String threadId;
@override final  String viewId;
@override final  String viewEpoch;
@override final  int version;

/// Create a copy of ViewStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ViewStampCopyWith<_ViewStamp> get copyWith => __$ViewStampCopyWithImpl<_ViewStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ViewStamp&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.viewId, viewId) || other.viewId == viewId)&&(identical(other.viewEpoch, viewEpoch) || other.viewEpoch == viewEpoch)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,viewId,viewEpoch,version);
}

@override
String toString() {
    return 'ViewStamp(threadId: $threadId, viewId: $viewId, viewEpoch: $viewEpoch, version: $version)';
}


}

/// @nodoc
abstract mixin class _$ViewStampCopyWith<$Res> implements $ViewStampCopyWith<$Res> {
  factory _$ViewStampCopyWith(_ViewStamp value, $Res Function(_ViewStamp) _then) = __$ViewStampCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String viewId, String viewEpoch, int version
});




}
/// @nodoc
class __$ViewStampCopyWithImpl<$Res>
    implements _$ViewStampCopyWith<$Res> {
  __$ViewStampCopyWithImpl(this._self, this._then);

  final _ViewStamp _self;
  final $Res Function(_ViewStamp) _then;

/// Create a copy of ViewStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? viewId = null,Object? viewEpoch = null,Object? version = null,}) {
  return _then(_ViewStamp(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,viewId: null == viewId ? _self.viewId : viewId // ignore: cast_nullable_to_non_nullable
as String,viewEpoch: null == viewEpoch ? _self.viewEpoch : viewEpoch // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AttemptId {

 int get value;
/// Create a copy of AttemptId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttemptIdCopyWith<AttemptId> get copyWith => _$AttemptIdCopyWithImpl<AttemptId>(this as AttemptId, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttemptId;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttemptId&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as AttemptId;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as AttemptId;
  return 'AttemptId(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $AttemptIdCopyWith<$Res>  {
  factory $AttemptIdCopyWith(AttemptId value, $Res Function(AttemptId) _then) = _$AttemptIdCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$AttemptIdCopyWithImpl<$Res>
    implements $AttemptIdCopyWith<$Res> {
  _$AttemptIdCopyWithImpl(this._self, this._then);

  final AttemptId _self;
  final $Res Function(AttemptId) _then;

/// Create a copy of AttemptId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(AttemptId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AttemptId].
extension AttemptIdPatterns on AttemptId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttemptId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttemptId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttemptId value)  $default,){
final _that = this;
switch (_that) {
case _AttemptId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttemptId value)?  $default,){
final _that = this;
switch (_that) {
case _AttemptId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttemptId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int value)  $default,) {final _that = this;
switch (_that) {
case _AttemptId():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int value)?  $default,) {final _that = this;
switch (_that) {
case _AttemptId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _AttemptId implements AttemptId {
  const _AttemptId(this.value);


@override final  int value;

/// Create a copy of AttemptId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttemptIdCopyWith<_AttemptId> get copyWith => __$AttemptIdCopyWithImpl<_AttemptId>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttemptId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'AttemptId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$AttemptIdCopyWith<$Res> implements $AttemptIdCopyWith<$Res> {
  factory _$AttemptIdCopyWith(_AttemptId value, $Res Function(_AttemptId) _then) = __$AttemptIdCopyWithImpl;
@override @useResult
$Res call({
 int value
});




}
/// @nodoc
class __$AttemptIdCopyWithImpl<$Res>
    implements _$AttemptIdCopyWith<$Res> {
  __$AttemptIdCopyWithImpl(this._self, this._then);

  final _AttemptId _self;
  final $Res Function(_AttemptId) _then;

/// Create a copy of AttemptId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_AttemptId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$OperationId {

 String get value;
/// Create a copy of OperationId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationIdCopyWith<OperationId> get copyWith => _$OperationIdCopyWithImpl<OperationId>(this as OperationId, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OperationId;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationId&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as OperationId;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as OperationId;
  return 'OperationId(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $OperationIdCopyWith<$Res>  {
  factory $OperationIdCopyWith(OperationId value, $Res Function(OperationId) _then) = _$OperationIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$OperationIdCopyWithImpl<$Res>
    implements $OperationIdCopyWith<$Res> {
  _$OperationIdCopyWithImpl(this._self, this._then);

  final OperationId _self;
  final $Res Function(OperationId) _then;

/// Create a copy of OperationId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(OperationId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [OperationId].
extension OperationIdPatterns on OperationId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OperationId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OperationId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OperationId value)  $default,){
final _that = this;
switch (_that) {
case _OperationId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OperationId value)?  $default,){
final _that = this;
switch (_that) {
case _OperationId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OperationId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value)  $default,) {final _that = this;
switch (_that) {
case _OperationId():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value)?  $default,) {final _that = this;
switch (_that) {
case _OperationId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _OperationId implements OperationId {
  const _OperationId(this.value);


@override final  String value;

/// Create a copy of OperationId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OperationIdCopyWith<_OperationId> get copyWith => __$OperationIdCopyWithImpl<_OperationId>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OperationId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'OperationId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$OperationIdCopyWith<$Res> implements $OperationIdCopyWith<$Res> {
  factory _$OperationIdCopyWith(_OperationId value, $Res Function(_OperationId) _then) = __$OperationIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$OperationIdCopyWithImpl<$Res>
    implements _$OperationIdCopyWith<$Res> {
  __$OperationIdCopyWithImpl(this._self, this._then);

  final _OperationId _self;
  final $Res Function(_OperationId) _then;

/// Create a copy of OperationId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_OperationId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DraftStamp {

 String get draftId; int get revision;
/// Create a copy of DraftStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftStampCopyWith<DraftStamp> get copyWith => _$DraftStampCopyWithImpl<DraftStamp>(this as DraftStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DraftStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftStamp&&(identical(other.draftId, _this.draftId) || other.draftId == _this.draftId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as DraftStamp;
  return Object.hash(runtimeType,_this.draftId,_this.revision);
}

@override
String toString() {
  final _this = this as DraftStamp;
  return 'DraftStamp(draftId: ${_this.draftId}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $DraftStampCopyWith<$Res>  {
  factory $DraftStampCopyWith(DraftStamp value, $Res Function(DraftStamp) _then) = _$DraftStampCopyWithImpl;
@useResult
$Res call({
 String draftId, int revision
});




}
/// @nodoc
class _$DraftStampCopyWithImpl<$Res>
    implements $DraftStampCopyWith<$Res> {
  _$DraftStampCopyWithImpl(this._self, this._then);

  final DraftStamp _self;
  final $Res Function(DraftStamp) _then;

/// Create a copy of DraftStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draftId = null,Object? revision = null,}) {
  return _then(DraftStamp(
draftId: null == draftId ? _self.draftId : draftId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DraftStamp].
extension DraftStampPatterns on DraftStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DraftStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DraftStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DraftStamp value)  $default,){
final _that = this;
switch (_that) {
case _DraftStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DraftStamp value)?  $default,){
final _that = this;
switch (_that) {
case _DraftStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String draftId,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DraftStamp() when $default != null:
return $default(_that.draftId,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String draftId,  int revision)  $default,) {final _that = this;
switch (_that) {
case _DraftStamp():
return $default(_that.draftId,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String draftId,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _DraftStamp() when $default != null:
return $default(_that.draftId,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _DraftStamp implements DraftStamp {
  const _DraftStamp({required this.draftId, required this.revision}): assert(revision >= 0);


@override final  String draftId;
@override final  int revision;

/// Create a copy of DraftStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DraftStampCopyWith<_DraftStamp> get copyWith => __$DraftStampCopyWithImpl<_DraftStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DraftStamp&&(identical(other.draftId, draftId) || other.draftId == draftId)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draftId,revision);
}

@override
String toString() {
    return 'DraftStamp(draftId: $draftId, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$DraftStampCopyWith<$Res> implements $DraftStampCopyWith<$Res> {
  factory _$DraftStampCopyWith(_DraftStamp value, $Res Function(_DraftStamp) _then) = __$DraftStampCopyWithImpl;
@override @useResult
$Res call({
 String draftId, int revision
});




}
/// @nodoc
class __$DraftStampCopyWithImpl<$Res>
    implements _$DraftStampCopyWith<$Res> {
  __$DraftStampCopyWithImpl(this._self, this._then);

  final _DraftStamp _self;
  final $Res Function(_DraftStamp) _then;

/// Create a copy of DraftStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draftId = null,Object? revision = null,}) {
  return _then(_DraftStamp(
draftId: null == draftId ? _self.draftId : draftId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ReadScopeIdentity {

 String get scopeId; String get runtimeEpoch; int get incarnation; int get sourceRevision;
/// Create a copy of ReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<ReadScopeIdentity> get copyWith => _$ReadScopeIdentityCopyWithImpl<ReadScopeIdentity>(this as ReadScopeIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ReadScopeIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadScopeIdentity&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.sourceRevision, _this.sourceRevision) || other.sourceRevision == _this.sourceRevision));
}


@override
int get hashCode {
  final _this = this as ReadScopeIdentity;
  return Object.hash(runtimeType,_this.scopeId,_this.runtimeEpoch,_this.incarnation,_this.sourceRevision);
}

@override
String toString() {
  final _this = this as ReadScopeIdentity;
  return 'ReadScopeIdentity(scopeId: ${_this.scopeId}, runtimeEpoch: ${_this.runtimeEpoch}, incarnation: ${_this.incarnation}, sourceRevision: ${_this.sourceRevision})';
}


}

/// @nodoc
abstract mixin class $ReadScopeIdentityCopyWith<$Res>  {
  factory $ReadScopeIdentityCopyWith(ReadScopeIdentity value, $Res Function(ReadScopeIdentity) _then) = _$ReadScopeIdentityCopyWithImpl;
@useResult
$Res call({
 String scopeId, String runtimeEpoch, int incarnation, int sourceRevision
});




}
/// @nodoc
class _$ReadScopeIdentityCopyWithImpl<$Res>
    implements $ReadScopeIdentityCopyWith<$Res> {
  _$ReadScopeIdentityCopyWithImpl(this._self, this._then);

  final ReadScopeIdentity _self;
  final $Res Function(ReadScopeIdentity) _then;

/// Create a copy of ReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? sourceRevision = null,}) {
  return _then(ReadScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,sourceRevision: null == sourceRevision ? _self.sourceRevision : sourceRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ReadScopeIdentity].
extension ReadScopeIdentityPatterns on ReadScopeIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadScopeIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadScopeIdentity value)  $default,){
final _that = this;
switch (_that) {
case _ReadScopeIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadScopeIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _ReadScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  String runtimeEpoch,  int incarnation,  int sourceRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.sourceRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  String runtimeEpoch,  int incarnation,  int sourceRevision)  $default,) {final _that = this;
switch (_that) {
case _ReadScopeIdentity():
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.sourceRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  String runtimeEpoch,  int incarnation,  int sourceRevision)?  $default,) {final _that = this;
switch (_that) {
case _ReadScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.sourceRevision);case _:
  return null;

}
}

}

/// @nodoc


class _ReadScopeIdentity implements ReadScopeIdentity {
  const _ReadScopeIdentity({required this.scopeId, required this.runtimeEpoch, required this.incarnation, required this.sourceRevision});


@override final  String scopeId;
@override final  String runtimeEpoch;
@override final  int incarnation;
@override final  int sourceRevision;

/// Create a copy of ReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadScopeIdentityCopyWith<_ReadScopeIdentity> get copyWith => __$ReadScopeIdentityCopyWithImpl<_ReadScopeIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadScopeIdentity&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.sourceRevision, sourceRevision) || other.sourceRevision == sourceRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,runtimeEpoch,incarnation,sourceRevision);
}

@override
String toString() {
    return 'ReadScopeIdentity(scopeId: $scopeId, runtimeEpoch: $runtimeEpoch, incarnation: $incarnation, sourceRevision: $sourceRevision)';
}


}

/// @nodoc
abstract mixin class _$ReadScopeIdentityCopyWith<$Res> implements $ReadScopeIdentityCopyWith<$Res> {
  factory _$ReadScopeIdentityCopyWith(_ReadScopeIdentity value, $Res Function(_ReadScopeIdentity) _then) = __$ReadScopeIdentityCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, String runtimeEpoch, int incarnation, int sourceRevision
});




}
/// @nodoc
class __$ReadScopeIdentityCopyWithImpl<$Res>
    implements _$ReadScopeIdentityCopyWith<$Res> {
  __$ReadScopeIdentityCopyWithImpl(this._self, this._then);

  final _ReadScopeIdentity _self;
  final $Res Function(_ReadScopeIdentity) _then;

/// Create a copy of ReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? sourceRevision = null,}) {
  return _then(_ReadScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,sourceRevision: null == sourceRevision ? _self.sourceRevision : sourceRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
