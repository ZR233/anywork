// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$McpReadRef {

 int get entry; int get revision;
/// Create a copy of McpReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpReadRefCopyWith<McpReadRef> get copyWith => _$McpReadRefCopyWithImpl<McpReadRef>(this as McpReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as McpReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as McpReadRef;
  return 'McpReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $McpReadRefCopyWith<$Res>  {
  factory $McpReadRefCopyWith(McpReadRef value, $Res Function(McpReadRef) _then) = _$McpReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$McpReadRefCopyWithImpl<$Res>
    implements $McpReadRefCopyWith<$Res> {
  _$McpReadRefCopyWithImpl(this._self, this._then);

  final McpReadRef _self;
  final $Res Function(McpReadRef) _then;

/// Create a copy of McpReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(McpReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [McpReadRef].
extension McpReadRefPatterns on McpReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpReadRef value)  $default,){
final _that = this;
switch (_that) {
case _McpReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _McpReadRef() when $default != null:
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
case _McpReadRef() when $default != null:
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
case _McpReadRef():
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
case _McpReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _McpReadRef implements McpReadRef {
  const _McpReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of McpReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpReadRefCopyWith<_McpReadRef> get copyWith => __$McpReadRefCopyWithImpl<_McpReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'McpReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$McpReadRefCopyWith<$Res> implements $McpReadRefCopyWith<$Res> {
  factory _$McpReadRefCopyWith(_McpReadRef value, $Res Function(_McpReadRef) _then) = __$McpReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$McpReadRefCopyWithImpl<$Res>
    implements _$McpReadRefCopyWith<$Res> {
  __$McpReadRefCopyWithImpl(this._self, this._then);

  final _McpReadRef _self;
  final $Res Function(_McpReadRef) _then;

/// Create a copy of McpReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_McpReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$McpReadTarget {

 ProductReadOrigin get origin; McpReadRef get reference;
/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpReadTargetCopyWith<McpReadTarget> get copyWith => _$McpReadTargetCopyWithImpl<McpReadTarget>(this as McpReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as McpReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as McpReadTarget;
  return 'McpReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $McpReadTargetCopyWith<$Res>  {
  factory $McpReadTargetCopyWith(McpReadTarget value, $Res Function(McpReadTarget) _then) = _$McpReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, McpReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$McpReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$McpReadTargetCopyWithImpl<$Res>
    implements $McpReadTargetCopyWith<$Res> {
  _$McpReadTargetCopyWithImpl(this._self, this._then);

  final McpReadTarget _self;
  final $Res Function(McpReadTarget) _then;

/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(McpReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as McpReadRef,
  ));
}
/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpReadRefCopyWith<$Res> get reference {

  return $McpReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpReadTarget].
extension McpReadTargetPatterns on McpReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _McpReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _McpReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  McpReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  McpReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _McpReadTarget():
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  McpReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _McpReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _McpReadTarget implements McpReadTarget {
  const _McpReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  McpReadRef reference;

/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpReadTargetCopyWith<_McpReadTarget> get copyWith => __$McpReadTargetCopyWithImpl<_McpReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'McpReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$McpReadTargetCopyWith<$Res> implements $McpReadTargetCopyWith<$Res> {
  factory _$McpReadTargetCopyWith(_McpReadTarget value, $Res Function(_McpReadTarget) _then) = __$McpReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, McpReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $McpReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$McpReadTargetCopyWithImpl<$Res>
    implements _$McpReadTargetCopyWith<$Res> {
  __$McpReadTargetCopyWithImpl(this._self, this._then);

  final _McpReadTarget _self;
  final $Res Function(_McpReadTarget) _then;

/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_McpReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as McpReadRef,
  ));
}

/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of McpReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpReadRefCopyWith<$Res> get reference {

  return $McpReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$McpHeader {

 ObservedHeader get source; McpReadRef? get reference;
/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpHeaderCopyWith<McpHeader> get copyWith => _$McpHeaderCopyWithImpl<McpHeader>(this as McpHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as McpHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as McpHeader;
  return 'McpHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $McpHeaderCopyWith<$Res>  {
  factory $McpHeaderCopyWith(McpHeader value, $Res Function(McpHeader) _then) = _$McpHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, McpReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$McpReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$McpHeaderCopyWithImpl<$Res>
    implements $McpHeaderCopyWith<$Res> {
  _$McpHeaderCopyWithImpl(this._self, this._then);

  final McpHeader _self;
  final $Res Function(McpHeader) _then;

/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(McpHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as McpReadRef?,
  ));
}
/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $McpReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpHeader].
extension McpHeaderPatterns on McpHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpHeader value)  $default,){
final _that = this;
switch (_that) {
case _McpHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpHeader value)?  $default,){
final _that = this;
switch (_that) {
case _McpHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  McpReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  McpReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _McpHeader():
return $default(_that.source,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  McpReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _McpHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _McpHeader implements McpHeader {
  const _McpHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  McpReadRef? reference;

/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpHeaderCopyWith<_McpHeader> get copyWith => __$McpHeaderCopyWithImpl<_McpHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'McpHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$McpHeaderCopyWith<$Res> implements $McpHeaderCopyWith<$Res> {
  factory _$McpHeaderCopyWith(_McpHeader value, $Res Function(_McpHeader) _then) = __$McpHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, McpReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $McpReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$McpHeaderCopyWithImpl<$Res>
    implements _$McpHeaderCopyWith<$Res> {
  __$McpHeaderCopyWithImpl(this._self, this._then);

  final _McpHeader _self;
  final $Res Function(_McpHeader) _then;

/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_McpHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as McpReadRef?,
  ));
}

/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of McpHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $McpReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$McpState {

 ProductProjection<McpHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<McpServer> get servers; ReadValue<List<String>, McpReadRef>? get activeServerIds; ReadValue<String, McpReadRef>? get desiredConfigFingerprint; ReadValue<String, McpReadRef>? get appliedConfigFingerprint;
/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpStateCopyWith<McpState> get copyWith => _$McpStateCopyWithImpl<McpState>(this as McpState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.servers, _this.servers) || other.servers == _this.servers)&&(identical(other.activeServerIds, _this.activeServerIds) || other.activeServerIds == _this.activeServerIds)&&(identical(other.desiredConfigFingerprint, _this.desiredConfigFingerprint) || other.desiredConfigFingerprint == _this.desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, _this.appliedConfigFingerprint) || other.appliedConfigFingerprint == _this.appliedConfigFingerprint));
}


@override
int get hashCode {
  final _this = this as McpState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.servers,_this.activeServerIds,_this.desiredConfigFingerprint,_this.appliedConfigFingerprint);
}



}

/// @nodoc
abstract mixin class $McpStateCopyWith<$Res>  {
  factory $McpStateCopyWith(McpState value, $Res Function(McpState) _then) = _$McpStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<McpHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<McpServer> servers, ReadValue<List<String>, McpReadRef>? activeServerIds, ReadValue<String, McpReadRef>? desiredConfigFingerprint, ReadValue<String, McpReadRef>? appliedConfigFingerprint
});


$ProductProjectionCopyWith<McpHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<McpServer, $Res> get servers;$ReadValueCopyWith<List<String>, McpReadRef, $Res>? get activeServerIds;$ReadValueCopyWith<String, McpReadRef, $Res>? get desiredConfigFingerprint;$ReadValueCopyWith<String, McpReadRef, $Res>? get appliedConfigFingerprint;

}
/// @nodoc
class _$McpStateCopyWithImpl<$Res>
    implements $McpStateCopyWith<$Res> {
  _$McpStateCopyWithImpl(this._self, this._then);

  final McpState _self;
  final $Res Function(McpState) _then;

/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? servers = null,Object? activeServerIds = freezed,Object? desiredConfigFingerprint = freezed,Object? appliedConfigFingerprint = freezed,}) {
  return _then(McpState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<McpHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,servers: null == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as CollectionMirror<McpServer>,activeServerIds: freezed == activeServerIds ? _self.activeServerIds : activeServerIds // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, McpReadRef>?,desiredConfigFingerprint: freezed == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, McpReadRef>?,appliedConfigFingerprint: freezed == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, McpReadRef>?,
  ));
}
/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<McpHeader, $Res> get projection {

  return $ProductProjectionCopyWith<McpHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<McpServer, $Res> get servers {

  return $CollectionMirrorCopyWith<McpServer, $Res>(_self.servers, (value) {
    return _then(_self.copyWith(servers: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, McpReadRef, $Res>? get activeServerIds {
    if (_self.activeServerIds == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, McpReadRef, $Res>(_self.activeServerIds!, (value) {
    return _then(_self.copyWith(activeServerIds: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, McpReadRef, $Res>? get desiredConfigFingerprint {
    if (_self.desiredConfigFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, McpReadRef, $Res>(_self.desiredConfigFingerprint!, (value) {
    return _then(_self.copyWith(desiredConfigFingerprint: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, McpReadRef, $Res>? get appliedConfigFingerprint {
    if (_self.appliedConfigFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, McpReadRef, $Res>(_self.appliedConfigFingerprint!, (value) {
    return _then(_self.copyWith(appliedConfigFingerprint: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpState].
extension McpStatePatterns on McpState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpState value)  $default,){
final _that = this;
switch (_that) {
case _McpState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpState value)?  $default,){
final _that = this;
switch (_that) {
case _McpState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<McpHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<McpServer> servers,  ReadValue<List<String>, McpReadRef>? activeServerIds,  ReadValue<String, McpReadRef>? desiredConfigFingerprint,  ReadValue<String, McpReadRef>? appliedConfigFingerprint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds,_that.desiredConfigFingerprint,_that.appliedConfigFingerprint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<McpHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<McpServer> servers,  ReadValue<List<String>, McpReadRef>? activeServerIds,  ReadValue<String, McpReadRef>? desiredConfigFingerprint,  ReadValue<String, McpReadRef>? appliedConfigFingerprint)  $default,) {final _that = this;
switch (_that) {
case _McpState():
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds,_that.desiredConfigFingerprint,_that.appliedConfigFingerprint);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<McpHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<McpServer> servers,  ReadValue<List<String>, McpReadRef>? activeServerIds,  ReadValue<String, McpReadRef>? desiredConfigFingerprint,  ReadValue<String, McpReadRef>? appliedConfigFingerprint)?  $default,) {final _that = this;
switch (_that) {
case _McpState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds,_that.desiredConfigFingerprint,_that.appliedConfigFingerprint);case _:
  return null;

}
}

}

/// @nodoc


class _McpState implements McpState {
  const _McpState({required this.projection, required this.sourceStatus, required this.servers, required this.activeServerIds, required this.desiredConfigFingerprint, required this.appliedConfigFingerprint});


@override final  ProductProjection<McpHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<McpServer> servers;
@override final  ReadValue<List<String>, McpReadRef>? activeServerIds;
@override final  ReadValue<String, McpReadRef>? desiredConfigFingerprint;
@override final  ReadValue<String, McpReadRef>? appliedConfigFingerprint;

/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpStateCopyWith<_McpState> get copyWith => __$McpStateCopyWithImpl<_McpState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.servers, servers) || other.servers == servers)&&(identical(other.activeServerIds, activeServerIds) || other.activeServerIds == activeServerIds)&&(identical(other.desiredConfigFingerprint, desiredConfigFingerprint) || other.desiredConfigFingerprint == desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, appliedConfigFingerprint) || other.appliedConfigFingerprint == appliedConfigFingerprint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,servers,activeServerIds,desiredConfigFingerprint,appliedConfigFingerprint);
}



}

/// @nodoc
abstract mixin class _$McpStateCopyWith<$Res> implements $McpStateCopyWith<$Res> {
  factory _$McpStateCopyWith(_McpState value, $Res Function(_McpState) _then) = __$McpStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<McpHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<McpServer> servers, ReadValue<List<String>, McpReadRef>? activeServerIds, ReadValue<String, McpReadRef>? desiredConfigFingerprint, ReadValue<String, McpReadRef>? appliedConfigFingerprint
});


@override $ProductProjectionCopyWith<McpHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<McpServer, $Res> get servers;@override $ReadValueCopyWith<List<String>, McpReadRef, $Res>? get activeServerIds;@override $ReadValueCopyWith<String, McpReadRef, $Res>? get desiredConfigFingerprint;@override $ReadValueCopyWith<String, McpReadRef, $Res>? get appliedConfigFingerprint;

}
/// @nodoc
class __$McpStateCopyWithImpl<$Res>
    implements _$McpStateCopyWith<$Res> {
  __$McpStateCopyWithImpl(this._self, this._then);

  final _McpState _self;
  final $Res Function(_McpState) _then;

/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? servers = null,Object? activeServerIds = freezed,Object? desiredConfigFingerprint = freezed,Object? appliedConfigFingerprint = freezed,}) {
  return _then(_McpState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<McpHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,servers: null == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as CollectionMirror<McpServer>,activeServerIds: freezed == activeServerIds ? _self.activeServerIds : activeServerIds // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, McpReadRef>?,desiredConfigFingerprint: freezed == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, McpReadRef>?,appliedConfigFingerprint: freezed == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, McpReadRef>?,
  ));
}

/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<McpHeader, $Res> get projection {

  return $ProductProjectionCopyWith<McpHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<McpServer, $Res> get servers {

  return $CollectionMirrorCopyWith<McpServer, $Res>(_self.servers, (value) {
    return _then(_self.copyWith(servers: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, McpReadRef, $Res>? get activeServerIds {
    if (_self.activeServerIds == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, McpReadRef, $Res>(_self.activeServerIds!, (value) {
    return _then(_self.copyWith(activeServerIds: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, McpReadRef, $Res>? get desiredConfigFingerprint {
    if (_self.desiredConfigFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, McpReadRef, $Res>(_self.desiredConfigFingerprint!, (value) {
    return _then(_self.copyWith(desiredConfigFingerprint: value));
  });
}/// Create a copy of McpState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, McpReadRef, $Res>? get appliedConfigFingerprint {
    if (_self.appliedConfigFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, McpReadRef, $Res>(_self.appliedConfigFingerprint!, (value) {
    return _then(_self.copyWith(appliedConfigFingerprint: value));
  });
}
}

// dart format on
