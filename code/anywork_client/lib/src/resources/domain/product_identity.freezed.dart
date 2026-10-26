// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProductFeedIdentity {

 String get feedId; String get ownerEpoch; int get incarnation; ProductResource get resource;
/// Create a copy of ProductFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<ProductFeedIdentity> get copyWith => _$ProductFeedIdentityCopyWithImpl<ProductFeedIdentity>(this as ProductFeedIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductFeedIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductFeedIdentity&&(identical(other.feedId, _this.feedId) || other.feedId == _this.feedId)&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.resource, _this.resource) || other.resource == _this.resource));
}


@override
int get hashCode {
  final _this = this as ProductFeedIdentity;
  return Object.hash(runtimeType,_this.feedId,_this.ownerEpoch,_this.incarnation,_this.resource);
}

@override
String toString() {
  final _this = this as ProductFeedIdentity;
  return 'ProductFeedIdentity(feedId: ${_this.feedId}, ownerEpoch: ${_this.ownerEpoch}, incarnation: ${_this.incarnation}, resource: ${_this.resource})';
}


}

/// @nodoc
abstract mixin class $ProductFeedIdentityCopyWith<$Res>  {
  factory $ProductFeedIdentityCopyWith(ProductFeedIdentity value, $Res Function(ProductFeedIdentity) _then) = _$ProductFeedIdentityCopyWithImpl;
@useResult
$Res call({
 String feedId, String ownerEpoch, int incarnation, ProductResource resource
});




}
/// @nodoc
class _$ProductFeedIdentityCopyWithImpl<$Res>
    implements $ProductFeedIdentityCopyWith<$Res> {
  _$ProductFeedIdentityCopyWithImpl(this._self, this._then);

  final ProductFeedIdentity _self;
  final $Res Function(ProductFeedIdentity) _then;

/// Create a copy of ProductFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? feedId = null,Object? ownerEpoch = null,Object? incarnation = null,Object? resource = null,}) {
  return _then(ProductFeedIdentity(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as ProductResource,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductFeedIdentity].
extension ProductFeedIdentityPatterns on ProductFeedIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductFeedIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductFeedIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductFeedIdentity value)  $default,){
final _that = this;
switch (_that) {
case _ProductFeedIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductFeedIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _ProductFeedIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String feedId,  String ownerEpoch,  int incarnation,  ProductResource resource)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductFeedIdentity() when $default != null:
return $default(_that.feedId,_that.ownerEpoch,_that.incarnation,_that.resource);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String feedId,  String ownerEpoch,  int incarnation,  ProductResource resource)  $default,) {final _that = this;
switch (_that) {
case _ProductFeedIdentity():
return $default(_that.feedId,_that.ownerEpoch,_that.incarnation,_that.resource);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String feedId,  String ownerEpoch,  int incarnation,  ProductResource resource)?  $default,) {final _that = this;
switch (_that) {
case _ProductFeedIdentity() when $default != null:
return $default(_that.feedId,_that.ownerEpoch,_that.incarnation,_that.resource);case _:
  return null;

}
}

}

/// @nodoc


class _ProductFeedIdentity implements ProductFeedIdentity {
  const _ProductFeedIdentity({required this.feedId, required this.ownerEpoch, required this.incarnation, required this.resource});


@override final  String feedId;
@override final  String ownerEpoch;
@override final  int incarnation;
@override final  ProductResource resource;

/// Create a copy of ProductFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductFeedIdentityCopyWith<_ProductFeedIdentity> get copyWith => __$ProductFeedIdentityCopyWithImpl<_ProductFeedIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductFeedIdentity&&(identical(other.feedId, feedId) || other.feedId == feedId)&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.resource, resource) || other.resource == resource));
}


@override
int get hashCode {
    return Object.hash(runtimeType,feedId,ownerEpoch,incarnation,resource);
}

@override
String toString() {
    return 'ProductFeedIdentity(feedId: $feedId, ownerEpoch: $ownerEpoch, incarnation: $incarnation, resource: $resource)';
}


}

/// @nodoc
abstract mixin class _$ProductFeedIdentityCopyWith<$Res> implements $ProductFeedIdentityCopyWith<$Res> {
  factory _$ProductFeedIdentityCopyWith(_ProductFeedIdentity value, $Res Function(_ProductFeedIdentity) _then) = __$ProductFeedIdentityCopyWithImpl;
@override @useResult
$Res call({
 String feedId, String ownerEpoch, int incarnation, ProductResource resource
});




}
/// @nodoc
class __$ProductFeedIdentityCopyWithImpl<$Res>
    implements _$ProductFeedIdentityCopyWith<$Res> {
  __$ProductFeedIdentityCopyWithImpl(this._self, this._then);

  final _ProductFeedIdentity _self;
  final $Res Function(_ProductFeedIdentity) _then;

/// Create a copy of ProductFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? feedId = null,Object? ownerEpoch = null,Object? incarnation = null,Object? resource = null,}) {
  return _then(_ProductFeedIdentity(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as ProductResource,
  ));
}


}

/// @nodoc
mixin _$ProductProjectionStamp {

 String get ownerEpoch; int get incarnation; int get revision;
/// Create a copy of ProductProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<ProductProjectionStamp> get copyWith => _$ProductProjectionStampCopyWithImpl<ProductProjectionStamp>(this as ProductProjectionStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductProjectionStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductProjectionStamp&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductProjectionStamp;
  return Object.hash(runtimeType,_this.ownerEpoch,_this.incarnation,_this.revision);
}

@override
String toString() {
  final _this = this as ProductProjectionStamp;
  return 'ProductProjectionStamp(ownerEpoch: ${_this.ownerEpoch}, incarnation: ${_this.incarnation}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ProductProjectionStampCopyWith<$Res>  {
  factory $ProductProjectionStampCopyWith(ProductProjectionStamp value, $Res Function(ProductProjectionStamp) _then) = _$ProductProjectionStampCopyWithImpl;
@useResult
$Res call({
 String ownerEpoch, int incarnation, int revision
});




}
/// @nodoc
class _$ProductProjectionStampCopyWithImpl<$Res>
    implements $ProductProjectionStampCopyWith<$Res> {
  _$ProductProjectionStampCopyWithImpl(this._self, this._then);

  final ProductProjectionStamp _self;
  final $Res Function(ProductProjectionStamp) _then;

/// Create a copy of ProductProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ownerEpoch = null,Object? incarnation = null,Object? revision = null,}) {
  return _then(ProductProjectionStamp(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductProjectionStamp].
extension ProductProjectionStampPatterns on ProductProjectionStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductProjectionStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductProjectionStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductProjectionStamp value)  $default,){
final _that = this;
switch (_that) {
case _ProductProjectionStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductProjectionStamp value)?  $default,){
final _that = this;
switch (_that) {
case _ProductProjectionStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ownerEpoch,  int incarnation,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductProjectionStamp() when $default != null:
return $default(_that.ownerEpoch,_that.incarnation,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ownerEpoch,  int incarnation,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ProductProjectionStamp():
return $default(_that.ownerEpoch,_that.incarnation,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ownerEpoch,  int incarnation,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ProductProjectionStamp() when $default != null:
return $default(_that.ownerEpoch,_that.incarnation,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ProductProjectionStamp extends ProductProjectionStamp {
  const _ProductProjectionStamp({required this.ownerEpoch, required this.incarnation, required this.revision}): super._();


@override final  String ownerEpoch;
@override final  int incarnation;
@override final  int revision;

/// Create a copy of ProductProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductProjectionStampCopyWith<_ProductProjectionStamp> get copyWith => __$ProductProjectionStampCopyWithImpl<_ProductProjectionStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductProjectionStamp&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ownerEpoch,incarnation,revision);
}

@override
String toString() {
    return 'ProductProjectionStamp(ownerEpoch: $ownerEpoch, incarnation: $incarnation, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ProductProjectionStampCopyWith<$Res> implements $ProductProjectionStampCopyWith<$Res> {
  factory _$ProductProjectionStampCopyWith(_ProductProjectionStamp value, $Res Function(_ProductProjectionStamp) _then) = __$ProductProjectionStampCopyWithImpl;
@override @useResult
$Res call({
 String ownerEpoch, int incarnation, int revision
});




}
/// @nodoc
class __$ProductProjectionStampCopyWithImpl<$Res>
    implements _$ProductProjectionStampCopyWith<$Res> {
  __$ProductProjectionStampCopyWithImpl(this._self, this._then);

  final _ProductProjectionStamp _self;
  final $Res Function(_ProductProjectionStamp) _then;

/// Create a copy of ProductProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ownerEpoch = null,Object? incarnation = null,Object? revision = null,}) {
  return _then(_ProductProjectionStamp(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductReadOrigin {

 String get ownerEpoch; int get incarnation;
/// Create a copy of ProductReadOrigin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<ProductReadOrigin> get copyWith => _$ProductReadOriginCopyWithImpl<ProductReadOrigin>(this as ProductReadOrigin, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductReadOrigin;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductReadOrigin&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation));
}


@override
int get hashCode {
  final _this = this as ProductReadOrigin;
  return Object.hash(runtimeType,_this.ownerEpoch,_this.incarnation);
}

@override
String toString() {
  final _this = this as ProductReadOrigin;
  return 'ProductReadOrigin(ownerEpoch: ${_this.ownerEpoch}, incarnation: ${_this.incarnation})';
}


}

/// @nodoc
abstract mixin class $ProductReadOriginCopyWith<$Res>  {
  factory $ProductReadOriginCopyWith(ProductReadOrigin value, $Res Function(ProductReadOrigin) _then) = _$ProductReadOriginCopyWithImpl;
@useResult
$Res call({
 String ownerEpoch, int incarnation
});




}
/// @nodoc
class _$ProductReadOriginCopyWithImpl<$Res>
    implements $ProductReadOriginCopyWith<$Res> {
  _$ProductReadOriginCopyWithImpl(this._self, this._then);

  final ProductReadOrigin _self;
  final $Res Function(ProductReadOrigin) _then;

/// Create a copy of ProductReadOrigin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ownerEpoch = null,Object? incarnation = null,}) {
  return _then(ProductReadOrigin(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductReadOrigin].
extension ProductReadOriginPatterns on ProductReadOrigin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductReadOrigin value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductReadOrigin() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductReadOrigin value)  $default,){
final _that = this;
switch (_that) {
case _ProductReadOrigin():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductReadOrigin value)?  $default,){
final _that = this;
switch (_that) {
case _ProductReadOrigin() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ownerEpoch,  int incarnation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductReadOrigin() when $default != null:
return $default(_that.ownerEpoch,_that.incarnation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ownerEpoch,  int incarnation)  $default,) {final _that = this;
switch (_that) {
case _ProductReadOrigin():
return $default(_that.ownerEpoch,_that.incarnation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ownerEpoch,  int incarnation)?  $default,) {final _that = this;
switch (_that) {
case _ProductReadOrigin() when $default != null:
return $default(_that.ownerEpoch,_that.incarnation);case _:
  return null;

}
}

}

/// @nodoc


class _ProductReadOrigin implements ProductReadOrigin {
  const _ProductReadOrigin({required this.ownerEpoch, required this.incarnation});


@override final  String ownerEpoch;
@override final  int incarnation;

/// Create a copy of ProductReadOrigin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductReadOriginCopyWith<_ProductReadOrigin> get copyWith => __$ProductReadOriginCopyWithImpl<_ProductReadOrigin>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductReadOrigin&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ownerEpoch,incarnation);
}

@override
String toString() {
    return 'ProductReadOrigin(ownerEpoch: $ownerEpoch, incarnation: $incarnation)';
}


}

/// @nodoc
abstract mixin class _$ProductReadOriginCopyWith<$Res> implements $ProductReadOriginCopyWith<$Res> {
  factory _$ProductReadOriginCopyWith(_ProductReadOrigin value, $Res Function(_ProductReadOrigin) _then) = __$ProductReadOriginCopyWithImpl;
@override @useResult
$Res call({
 String ownerEpoch, int incarnation
});




}
/// @nodoc
class __$ProductReadOriginCopyWithImpl<$Res>
    implements _$ProductReadOriginCopyWith<$Res> {
  __$ProductReadOriginCopyWithImpl(this._self, this._then);

  final _ProductReadOrigin _self;
  final $Res Function(_ProductReadOrigin) _then;

/// Create a copy of ProductReadOrigin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ownerEpoch = null,Object? incarnation = null,}) {
  return _then(_ProductReadOrigin(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductReadVersion {

 int get entry; int get revision;
/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductReadVersionCopyWith<ProductReadVersion> get copyWith => _$ProductReadVersionCopyWithImpl<ProductReadVersion>(this as ProductReadVersion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductReadVersion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductReadVersion&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductReadVersion;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ProductReadVersion;
  return 'ProductReadVersion(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ProductReadVersionCopyWith<$Res>  {
  factory $ProductReadVersionCopyWith(ProductReadVersion value, $Res Function(ProductReadVersion) _then) = _$ProductReadVersionCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProductReadVersionCopyWithImpl<$Res>
    implements $ProductReadVersionCopyWith<$Res> {
  _$ProductReadVersionCopyWithImpl(this._self, this._then);

  final ProductReadVersion _self;
  final $Res Function(ProductReadVersion) _then;

/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_self.copyWith(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductReadVersion].
extension ProductReadVersionPatterns on ProductReadVersion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProductValueReadVersion value)?  value,TResult Function( ProductSourceStatusReadVersion value)?  sourceStatus,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProductValueReadVersion() when value != null:
return value(_that);case ProductSourceStatusReadVersion() when sourceStatus != null:
return sourceStatus(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProductValueReadVersion value)  value,required TResult Function( ProductSourceStatusReadVersion value)  sourceStatus,}){
final _that = this;
switch (_that) {
case ProductValueReadVersion():
return value(_that);case ProductSourceStatusReadVersion():
return sourceStatus(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProductValueReadVersion value)?  value,TResult? Function( ProductSourceStatusReadVersion value)?  sourceStatus,}){
final _that = this;
switch (_that) {
case ProductValueReadVersion() when value != null:
return value(_that);case ProductSourceStatusReadVersion() when sourceStatus != null:
return sourceStatus(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int entry,  int revision)?  value,TResult Function( int entry,  int revision)?  sourceStatus,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ProductValueReadVersion() when value != null:
return value(_that.entry,_that.revision);case ProductSourceStatusReadVersion() when sourceStatus != null:
return sourceStatus(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int entry,  int revision)  value,required TResult Function( int entry,  int revision)  sourceStatus,}) {final _that = this;
switch (_that) {
case ProductValueReadVersion():
return value(_that.entry,_that.revision);case ProductSourceStatusReadVersion():
return sourceStatus(_that.entry,_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int entry,  int revision)?  value,TResult? Function( int entry,  int revision)?  sourceStatus,}) {final _that = this;
switch (_that) {
case ProductValueReadVersion() when value != null:
return value(_that.entry,_that.revision);case ProductSourceStatusReadVersion() when sourceStatus != null:
return sourceStatus(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class ProductValueReadVersion implements ProductReadVersion {
  const ProductValueReadVersion({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductValueReadVersionCopyWith<ProductValueReadVersion> get copyWith => _$ProductValueReadVersionCopyWithImpl<ProductValueReadVersion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductValueReadVersion&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ProductReadVersion.value(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $ProductValueReadVersionCopyWith<$Res> implements $ProductReadVersionCopyWith<$Res> {
  factory $ProductValueReadVersionCopyWith(ProductValueReadVersion value, $Res Function(ProductValueReadVersion) _then) = _$ProductValueReadVersionCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProductValueReadVersionCopyWithImpl<$Res>
    implements $ProductValueReadVersionCopyWith<$Res> {
  _$ProductValueReadVersionCopyWithImpl(this._self, this._then);

  final ProductValueReadVersion _self;
  final $Res Function(ProductValueReadVersion) _then;

/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ProductValueReadVersion(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ProductSourceStatusReadVersion implements ProductReadVersion {
  const ProductSourceStatusReadVersion({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductSourceStatusReadVersionCopyWith<ProductSourceStatusReadVersion> get copyWith => _$ProductSourceStatusReadVersionCopyWithImpl<ProductSourceStatusReadVersion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductSourceStatusReadVersion&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ProductReadVersion.sourceStatus(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $ProductSourceStatusReadVersionCopyWith<$Res> implements $ProductReadVersionCopyWith<$Res> {
  factory $ProductSourceStatusReadVersionCopyWith(ProductSourceStatusReadVersion value, $Res Function(ProductSourceStatusReadVersion) _then) = _$ProductSourceStatusReadVersionCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProductSourceStatusReadVersionCopyWithImpl<$Res>
    implements $ProductSourceStatusReadVersionCopyWith<$Res> {
  _$ProductSourceStatusReadVersionCopyWithImpl(this._self, this._then);

  final ProductSourceStatusReadVersion _self;
  final $Res Function(ProductSourceStatusReadVersion) _then;

/// Create a copy of ProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ProductSourceStatusReadVersion(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductReadScopeIdentity {

 String get scopeId; String get ownerEpoch; int get incarnation; ProductReadVersion get version;
/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductReadScopeIdentityCopyWith<ProductReadScopeIdentity> get copyWith => _$ProductReadScopeIdentityCopyWithImpl<ProductReadScopeIdentity>(this as ProductReadScopeIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductReadScopeIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductReadScopeIdentity&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.version, _this.version) || other.version == _this.version));
}


@override
int get hashCode {
  final _this = this as ProductReadScopeIdentity;
  return Object.hash(runtimeType,_this.scopeId,_this.ownerEpoch,_this.incarnation,_this.version);
}

@override
String toString() {
  final _this = this as ProductReadScopeIdentity;
  return 'ProductReadScopeIdentity(scopeId: ${_this.scopeId}, ownerEpoch: ${_this.ownerEpoch}, incarnation: ${_this.incarnation}, version: ${_this.version})';
}


}

/// @nodoc
abstract mixin class $ProductReadScopeIdentityCopyWith<$Res>  {
  factory $ProductReadScopeIdentityCopyWith(ProductReadScopeIdentity value, $Res Function(ProductReadScopeIdentity) _then) = _$ProductReadScopeIdentityCopyWithImpl;
@useResult
$Res call({
 String scopeId, String ownerEpoch, int incarnation, ProductReadVersion version
});


$ProductReadVersionCopyWith<$Res> get version;

}
/// @nodoc
class _$ProductReadScopeIdentityCopyWithImpl<$Res>
    implements $ProductReadScopeIdentityCopyWith<$Res> {
  _$ProductReadScopeIdentityCopyWithImpl(this._self, this._then);

  final ProductReadScopeIdentity _self;
  final $Res Function(ProductReadScopeIdentity) _then;

/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? ownerEpoch = null,Object? incarnation = null,Object? version = null,}) {
  return _then(ProductReadScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as ProductReadVersion,
  ));
}
/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadVersionCopyWith<$Res> get version {

  return $ProductReadVersionCopyWith<$Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProductReadScopeIdentity].
extension ProductReadScopeIdentityPatterns on ProductReadScopeIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductReadScopeIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductReadScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductReadScopeIdentity value)  $default,){
final _that = this;
switch (_that) {
case _ProductReadScopeIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductReadScopeIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _ProductReadScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  String ownerEpoch,  int incarnation,  ProductReadVersion version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductReadScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.ownerEpoch,_that.incarnation,_that.version);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  String ownerEpoch,  int incarnation,  ProductReadVersion version)  $default,) {final _that = this;
switch (_that) {
case _ProductReadScopeIdentity():
return $default(_that.scopeId,_that.ownerEpoch,_that.incarnation,_that.version);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  String ownerEpoch,  int incarnation,  ProductReadVersion version)?  $default,) {final _that = this;
switch (_that) {
case _ProductReadScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.ownerEpoch,_that.incarnation,_that.version);case _:
  return null;

}
}

}

/// @nodoc


class _ProductReadScopeIdentity implements ProductReadScopeIdentity {
  const _ProductReadScopeIdentity({required this.scopeId, required this.ownerEpoch, required this.incarnation, required this.version});


@override final  String scopeId;
@override final  String ownerEpoch;
@override final  int incarnation;
@override final  ProductReadVersion version;

/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductReadScopeIdentityCopyWith<_ProductReadScopeIdentity> get copyWith => __$ProductReadScopeIdentityCopyWithImpl<_ProductReadScopeIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductReadScopeIdentity&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,ownerEpoch,incarnation,version);
}

@override
String toString() {
    return 'ProductReadScopeIdentity(scopeId: $scopeId, ownerEpoch: $ownerEpoch, incarnation: $incarnation, version: $version)';
}


}

/// @nodoc
abstract mixin class _$ProductReadScopeIdentityCopyWith<$Res> implements $ProductReadScopeIdentityCopyWith<$Res> {
  factory _$ProductReadScopeIdentityCopyWith(_ProductReadScopeIdentity value, $Res Function(_ProductReadScopeIdentity) _then) = __$ProductReadScopeIdentityCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, String ownerEpoch, int incarnation, ProductReadVersion version
});


@override $ProductReadVersionCopyWith<$Res> get version;

}
/// @nodoc
class __$ProductReadScopeIdentityCopyWithImpl<$Res>
    implements _$ProductReadScopeIdentityCopyWith<$Res> {
  __$ProductReadScopeIdentityCopyWithImpl(this._self, this._then);

  final _ProductReadScopeIdentity _self;
  final $Res Function(_ProductReadScopeIdentity) _then;

/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? ownerEpoch = null,Object? incarnation = null,Object? version = null,}) {
  return _then(_ProductReadScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as ProductReadVersion,
  ));
}

/// Create a copy of ProductReadScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadVersionCopyWith<$Res> get version {

  return $ProductReadVersionCopyWith<$Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}
}

/// @nodoc
mixin _$ProductSourceStatusRef {

 int get entry; int get revision;
/// Create a copy of ProductSourceStatusRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductSourceStatusRefCopyWith<ProductSourceStatusRef> get copyWith => _$ProductSourceStatusRefCopyWithImpl<ProductSourceStatusRef>(this as ProductSourceStatusRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductSourceStatusRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductSourceStatusRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductSourceStatusRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ProductSourceStatusRef;
  return 'ProductSourceStatusRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ProductSourceStatusRefCopyWith<$Res>  {
  factory $ProductSourceStatusRefCopyWith(ProductSourceStatusRef value, $Res Function(ProductSourceStatusRef) _then) = _$ProductSourceStatusRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProductSourceStatusRefCopyWithImpl<$Res>
    implements $ProductSourceStatusRefCopyWith<$Res> {
  _$ProductSourceStatusRefCopyWithImpl(this._self, this._then);

  final ProductSourceStatusRef _self;
  final $Res Function(ProductSourceStatusRef) _then;

/// Create a copy of ProductSourceStatusRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ProductSourceStatusRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductSourceStatusRef].
extension ProductSourceStatusRefPatterns on ProductSourceStatusRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductSourceStatusRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductSourceStatusRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductSourceStatusRef value)  $default,){
final _that = this;
switch (_that) {
case _ProductSourceStatusRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductSourceStatusRef value)?  $default,){
final _that = this;
switch (_that) {
case _ProductSourceStatusRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductSourceStatusRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ProductSourceStatusRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ProductSourceStatusRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ProductSourceStatusRef implements ProductSourceStatusRef {
  const _ProductSourceStatusRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ProductSourceStatusRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductSourceStatusRefCopyWith<_ProductSourceStatusRef> get copyWith => __$ProductSourceStatusRefCopyWithImpl<_ProductSourceStatusRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductSourceStatusRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ProductSourceStatusRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ProductSourceStatusRefCopyWith<$Res> implements $ProductSourceStatusRefCopyWith<$Res> {
  factory _$ProductSourceStatusRefCopyWith(_ProductSourceStatusRef value, $Res Function(_ProductSourceStatusRef) _then) = __$ProductSourceStatusRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ProductSourceStatusRefCopyWithImpl<$Res>
    implements _$ProductSourceStatusRefCopyWith<$Res> {
  __$ProductSourceStatusRefCopyWithImpl(this._self, this._then);

  final _ProductSourceStatusRef _self;
  final $Res Function(_ProductSourceStatusRef) _then;

/// Create a copy of ProductSourceStatusRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ProductSourceStatusRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductEntityRef {

 int get entry; int get revision;
/// Create a copy of ProductEntityRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<ProductEntityRef> get copyWith => _$ProductEntityRefCopyWithImpl<ProductEntityRef>(this as ProductEntityRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductEntityRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductEntityRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductEntityRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ProductEntityRef;
  return 'ProductEntityRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ProductEntityRefCopyWith<$Res>  {
  factory $ProductEntityRefCopyWith(ProductEntityRef value, $Res Function(ProductEntityRef) _then) = _$ProductEntityRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProductEntityRefCopyWithImpl<$Res>
    implements $ProductEntityRefCopyWith<$Res> {
  _$ProductEntityRefCopyWithImpl(this._self, this._then);

  final ProductEntityRef _self;
  final $Res Function(ProductEntityRef) _then;

/// Create a copy of ProductEntityRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ProductEntityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductEntityRef].
extension ProductEntityRefPatterns on ProductEntityRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductEntityRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductEntityRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductEntityRef value)  $default,){
final _that = this;
switch (_that) {
case _ProductEntityRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductEntityRef value)?  $default,){
final _that = this;
switch (_that) {
case _ProductEntityRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductEntityRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ProductEntityRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ProductEntityRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ProductEntityRef implements ProductEntityRef {
  const _ProductEntityRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ProductEntityRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductEntityRefCopyWith<_ProductEntityRef> get copyWith => __$ProductEntityRefCopyWithImpl<_ProductEntityRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductEntityRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ProductEntityRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ProductEntityRefCopyWith<$Res> implements $ProductEntityRefCopyWith<$Res> {
  factory _$ProductEntityRefCopyWith(_ProductEntityRef value, $Res Function(_ProductEntityRef) _then) = __$ProductEntityRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ProductEntityRefCopyWithImpl<$Res>
    implements _$ProductEntityRefCopyWith<$Res> {
  __$ProductEntityRefCopyWithImpl(this._self, this._then);

  final _ProductEntityRef _self;
  final $Res Function(_ProductEntityRef) _then;

/// Create a copy of ProductEntityRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ProductEntityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductCollectionRef {

 int get entry; int get revision; int get total;
/// Create a copy of ProductCollectionRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<ProductCollectionRef> get copyWith => _$ProductCollectionRefCopyWithImpl<ProductCollectionRef>(this as ProductCollectionRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductCollectionRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductCollectionRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.total, _this.total) || other.total == _this.total));
}


@override
int get hashCode {
  final _this = this as ProductCollectionRef;
  return Object.hash(runtimeType,_this.entry,_this.revision,_this.total);
}

@override
String toString() {
  final _this = this as ProductCollectionRef;
  return 'ProductCollectionRef(entry: ${_this.entry}, revision: ${_this.revision}, total: ${_this.total})';
}


}

/// @nodoc
abstract mixin class $ProductCollectionRefCopyWith<$Res>  {
  factory $ProductCollectionRefCopyWith(ProductCollectionRef value, $Res Function(ProductCollectionRef) _then) = _$ProductCollectionRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision, int total
});




}
/// @nodoc
class _$ProductCollectionRefCopyWithImpl<$Res>
    implements $ProductCollectionRefCopyWith<$Res> {
  _$ProductCollectionRefCopyWithImpl(this._self, this._then);

  final ProductCollectionRef _self;
  final $Res Function(ProductCollectionRef) _then;

/// Create a copy of ProductCollectionRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,Object? total = null,}) {
  return _then(ProductCollectionRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductCollectionRef].
extension ProductCollectionRefPatterns on ProductCollectionRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductCollectionRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductCollectionRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductCollectionRef value)  $default,){
final _that = this;
switch (_that) {
case _ProductCollectionRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductCollectionRef value)?  $default,){
final _that = this;
switch (_that) {
case _ProductCollectionRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision,  int total)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductCollectionRef() when $default != null:
return $default(_that.entry,_that.revision,_that.total);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision,  int total)  $default,) {final _that = this;
switch (_that) {
case _ProductCollectionRef():
return $default(_that.entry,_that.revision,_that.total);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision,  int total)?  $default,) {final _that = this;
switch (_that) {
case _ProductCollectionRef() when $default != null:
return $default(_that.entry,_that.revision,_that.total);case _:
  return null;

}
}

}

/// @nodoc


class _ProductCollectionRef implements ProductCollectionRef {
  const _ProductCollectionRef({required this.entry, required this.revision, required this.total});


@override final  int entry;
@override final  int revision;
@override final  int total;

/// Create a copy of ProductCollectionRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCollectionRefCopyWith<_ProductCollectionRef> get copyWith => __$ProductCollectionRefCopyWithImpl<_ProductCollectionRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductCollectionRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision,total);
}

@override
String toString() {
    return 'ProductCollectionRef(entry: $entry, revision: $revision, total: $total)';
}


}

/// @nodoc
abstract mixin class _$ProductCollectionRefCopyWith<$Res> implements $ProductCollectionRefCopyWith<$Res> {
  factory _$ProductCollectionRefCopyWith(_ProductCollectionRef value, $Res Function(_ProductCollectionRef) _then) = __$ProductCollectionRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision, int total
});




}
/// @nodoc
class __$ProductCollectionRefCopyWithImpl<$Res>
    implements _$ProductCollectionRefCopyWith<$Res> {
  __$ProductCollectionRefCopyWithImpl(this._self, this._then);

  final _ProductCollectionRef _self;
  final $Res Function(_ProductCollectionRef) _then;

/// Create a copy of ProductCollectionRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,Object? total = null,}) {
  return _then(_ProductCollectionRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
