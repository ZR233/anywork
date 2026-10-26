// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LspReadRef {

 int get entry; int get revision;
/// Create a copy of LspReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspReadRefCopyWith<LspReadRef> get copyWith => _$LspReadRefCopyWithImpl<LspReadRef>(this as LspReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as LspReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as LspReadRef;
  return 'LspReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $LspReadRefCopyWith<$Res>  {
  factory $LspReadRefCopyWith(LspReadRef value, $Res Function(LspReadRef) _then) = _$LspReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$LspReadRefCopyWithImpl<$Res>
    implements $LspReadRefCopyWith<$Res> {
  _$LspReadRefCopyWithImpl(this._self, this._then);

  final LspReadRef _self;
  final $Res Function(LspReadRef) _then;

/// Create a copy of LspReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(LspReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [LspReadRef].
extension LspReadRefPatterns on LspReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspReadRef value)  $default,){
final _that = this;
switch (_that) {
case _LspReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _LspReadRef() when $default != null:
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
case _LspReadRef() when $default != null:
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
case _LspReadRef():
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
case _LspReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _LspReadRef implements LspReadRef {
  const _LspReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of LspReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspReadRefCopyWith<_LspReadRef> get copyWith => __$LspReadRefCopyWithImpl<_LspReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'LspReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$LspReadRefCopyWith<$Res> implements $LspReadRefCopyWith<$Res> {
  factory _$LspReadRefCopyWith(_LspReadRef value, $Res Function(_LspReadRef) _then) = __$LspReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$LspReadRefCopyWithImpl<$Res>
    implements _$LspReadRefCopyWith<$Res> {
  __$LspReadRefCopyWithImpl(this._self, this._then);

  final _LspReadRef _self;
  final $Res Function(_LspReadRef) _then;

/// Create a copy of LspReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_LspReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$LspReadTarget {

 ProductReadOrigin get origin; LspReadRef get reference;
/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspReadTargetCopyWith<LspReadTarget> get copyWith => _$LspReadTargetCopyWithImpl<LspReadTarget>(this as LspReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as LspReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as LspReadTarget;
  return 'LspReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $LspReadTargetCopyWith<$Res>  {
  factory $LspReadTargetCopyWith(LspReadTarget value, $Res Function(LspReadTarget) _then) = _$LspReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, LspReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$LspReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$LspReadTargetCopyWithImpl<$Res>
    implements $LspReadTargetCopyWith<$Res> {
  _$LspReadTargetCopyWithImpl(this._self, this._then);

  final LspReadTarget _self;
  final $Res Function(LspReadTarget) _then;

/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(LspReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as LspReadRef,
  ));
}
/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspReadRefCopyWith<$Res> get reference {

  return $LspReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspReadTarget].
extension LspReadTargetPatterns on LspReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _LspReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _LspReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  LspReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  LspReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _LspReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  LspReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _LspReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _LspReadTarget implements LspReadTarget {
  const _LspReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  LspReadRef reference;

/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspReadTargetCopyWith<_LspReadTarget> get copyWith => __$LspReadTargetCopyWithImpl<_LspReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'LspReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$LspReadTargetCopyWith<$Res> implements $LspReadTargetCopyWith<$Res> {
  factory _$LspReadTargetCopyWith(_LspReadTarget value, $Res Function(_LspReadTarget) _then) = __$LspReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, LspReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $LspReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$LspReadTargetCopyWithImpl<$Res>
    implements _$LspReadTargetCopyWith<$Res> {
  __$LspReadTargetCopyWithImpl(this._self, this._then);

  final _LspReadTarget _self;
  final $Res Function(_LspReadTarget) _then;

/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_LspReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as LspReadRef,
  ));
}

/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of LspReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspReadRefCopyWith<$Res> get reference {

  return $LspReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$LspHeader {

 ObservedHeader get source; LspReadRef? get reference;
/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspHeaderCopyWith<LspHeader> get copyWith => _$LspHeaderCopyWithImpl<LspHeader>(this as LspHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as LspHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as LspHeader;
  return 'LspHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $LspHeaderCopyWith<$Res>  {
  factory $LspHeaderCopyWith(LspHeader value, $Res Function(LspHeader) _then) = _$LspHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, LspReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$LspReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$LspHeaderCopyWithImpl<$Res>
    implements $LspHeaderCopyWith<$Res> {
  _$LspHeaderCopyWithImpl(this._self, this._then);

  final LspHeader _self;
  final $Res Function(LspHeader) _then;

/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(LspHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as LspReadRef?,
  ));
}
/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $LspReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspHeader].
extension LspHeaderPatterns on LspHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspHeader value)  $default,){
final _that = this;
switch (_that) {
case _LspHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspHeader value)?  $default,){
final _that = this;
switch (_that) {
case _LspHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  LspReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  LspReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _LspHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  LspReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _LspHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _LspHeader implements LspHeader {
  const _LspHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  LspReadRef? reference;

/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspHeaderCopyWith<_LspHeader> get copyWith => __$LspHeaderCopyWithImpl<_LspHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'LspHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$LspHeaderCopyWith<$Res> implements $LspHeaderCopyWith<$Res> {
  factory _$LspHeaderCopyWith(_LspHeader value, $Res Function(_LspHeader) _then) = __$LspHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, LspReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $LspReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$LspHeaderCopyWithImpl<$Res>
    implements _$LspHeaderCopyWith<$Res> {
  __$LspHeaderCopyWithImpl(this._self, this._then);

  final _LspHeader _self;
  final $Res Function(_LspHeader) _then;

/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_LspHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as LspReadRef?,
  ));
}

/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of LspHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $LspReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$LspState {

 ProductProjection<LspHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<LspServer> get servers; ReadValue<List<String>, LspReadRef>? get activeServerIds;
/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspStateCopyWith<LspState> get copyWith => _$LspStateCopyWithImpl<LspState>(this as LspState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.servers, _this.servers) || other.servers == _this.servers)&&(identical(other.activeServerIds, _this.activeServerIds) || other.activeServerIds == _this.activeServerIds));
}


@override
int get hashCode {
  final _this = this as LspState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.servers,_this.activeServerIds);
}



}

/// @nodoc
abstract mixin class $LspStateCopyWith<$Res>  {
  factory $LspStateCopyWith(LspState value, $Res Function(LspState) _then) = _$LspStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<LspHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<LspServer> servers, ReadValue<List<String>, LspReadRef>? activeServerIds
});


$ProductProjectionCopyWith<LspHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<LspServer, $Res> get servers;$ReadValueCopyWith<List<String>, LspReadRef, $Res>? get activeServerIds;

}
/// @nodoc
class _$LspStateCopyWithImpl<$Res>
    implements $LspStateCopyWith<$Res> {
  _$LspStateCopyWithImpl(this._self, this._then);

  final LspState _self;
  final $Res Function(LspState) _then;

/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? servers = null,Object? activeServerIds = freezed,}) {
  return _then(LspState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<LspHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,servers: null == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as CollectionMirror<LspServer>,activeServerIds: freezed == activeServerIds ? _self.activeServerIds : activeServerIds // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, LspReadRef>?,
  ));
}
/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<LspHeader, $Res> get projection {

  return $ProductProjectionCopyWith<LspHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of LspState
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
}/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<LspServer, $Res> get servers {

  return $CollectionMirrorCopyWith<LspServer, $Res>(_self.servers, (value) {
    return _then(_self.copyWith(servers: value));
  });
}/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, LspReadRef, $Res>? get activeServerIds {
    if (_self.activeServerIds == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, LspReadRef, $Res>(_self.activeServerIds!, (value) {
    return _then(_self.copyWith(activeServerIds: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspState].
extension LspStatePatterns on LspState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspState value)  $default,){
final _that = this;
switch (_that) {
case _LspState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspState value)?  $default,){
final _that = this;
switch (_that) {
case _LspState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<LspHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<LspServer> servers,  ReadValue<List<String>, LspReadRef>? activeServerIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<LspHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<LspServer> servers,  ReadValue<List<String>, LspReadRef>? activeServerIds)  $default,) {final _that = this;
switch (_that) {
case _LspState():
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<LspHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<LspServer> servers,  ReadValue<List<String>, LspReadRef>? activeServerIds)?  $default,) {final _that = this;
switch (_that) {
case _LspState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.servers,_that.activeServerIds);case _:
  return null;

}
}

}

/// @nodoc


class _LspState implements LspState {
  const _LspState({required this.projection, required this.sourceStatus, required this.servers, required this.activeServerIds});


@override final  ProductProjection<LspHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<LspServer> servers;
@override final  ReadValue<List<String>, LspReadRef>? activeServerIds;

/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspStateCopyWith<_LspState> get copyWith => __$LspStateCopyWithImpl<_LspState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.servers, servers) || other.servers == servers)&&(identical(other.activeServerIds, activeServerIds) || other.activeServerIds == activeServerIds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,servers,activeServerIds);
}



}

/// @nodoc
abstract mixin class _$LspStateCopyWith<$Res> implements $LspStateCopyWith<$Res> {
  factory _$LspStateCopyWith(_LspState value, $Res Function(_LspState) _then) = __$LspStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<LspHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<LspServer> servers, ReadValue<List<String>, LspReadRef>? activeServerIds
});


@override $ProductProjectionCopyWith<LspHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<LspServer, $Res> get servers;@override $ReadValueCopyWith<List<String>, LspReadRef, $Res>? get activeServerIds;

}
/// @nodoc
class __$LspStateCopyWithImpl<$Res>
    implements _$LspStateCopyWith<$Res> {
  __$LspStateCopyWithImpl(this._self, this._then);

  final _LspState _self;
  final $Res Function(_LspState) _then;

/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? servers = null,Object? activeServerIds = freezed,}) {
  return _then(_LspState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<LspHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,servers: null == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as CollectionMirror<LspServer>,activeServerIds: freezed == activeServerIds ? _self.activeServerIds : activeServerIds // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, LspReadRef>?,
  ));
}

/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<LspHeader, $Res> get projection {

  return $ProductProjectionCopyWith<LspHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of LspState
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
}/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<LspServer, $Res> get servers {

  return $CollectionMirrorCopyWith<LspServer, $Res>(_self.servers, (value) {
    return _then(_self.copyWith(servers: value));
  });
}/// Create a copy of LspState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, LspReadRef, $Res>? get activeServerIds {
    if (_self.activeServerIds == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, LspReadRef, $Res>(_self.activeServerIds!, (value) {
    return _then(_self.copyWith(activeServerIds: value));
  });
}
}

// dart format on
