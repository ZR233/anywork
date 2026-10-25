// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryReadRef {

 int get entry; int get revision;
/// Create a copy of RecoveryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryReadRefCopyWith<RecoveryReadRef> get copyWith => _$RecoveryReadRefCopyWithImpl<RecoveryReadRef>(this as RecoveryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as RecoveryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as RecoveryReadRef;
  return 'RecoveryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $RecoveryReadRefCopyWith<$Res>  {
  factory $RecoveryReadRefCopyWith(RecoveryReadRef value, $Res Function(RecoveryReadRef) _then) = _$RecoveryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$RecoveryReadRefCopyWithImpl<$Res>
    implements $RecoveryReadRefCopyWith<$Res> {
  _$RecoveryReadRefCopyWithImpl(this._self, this._then);

  final RecoveryReadRef _self;
  final $Res Function(RecoveryReadRef) _then;

/// Create a copy of RecoveryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(RecoveryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RecoveryReadRef].
extension RecoveryReadRefPatterns on RecoveryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadRef() when $default != null:
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
case _RecoveryReadRef() when $default != null:
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
case _RecoveryReadRef():
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
case _RecoveryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryReadRef implements RecoveryReadRef {
  const _RecoveryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of RecoveryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryReadRefCopyWith<_RecoveryReadRef> get copyWith => __$RecoveryReadRefCopyWithImpl<_RecoveryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'RecoveryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$RecoveryReadRefCopyWith<$Res> implements $RecoveryReadRefCopyWith<$Res> {
  factory _$RecoveryReadRefCopyWith(_RecoveryReadRef value, $Res Function(_RecoveryReadRef) _then) = __$RecoveryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$RecoveryReadRefCopyWithImpl<$Res>
    implements _$RecoveryReadRefCopyWith<$Res> {
  __$RecoveryReadRefCopyWithImpl(this._self, this._then);

  final _RecoveryReadRef _self;
  final $Res Function(_RecoveryReadRef) _then;

/// Create a copy of RecoveryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_RecoveryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RecoveryReadTarget {

 ProductReadOrigin get origin; RecoveryReadRef get reference;
/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryReadTargetCopyWith<RecoveryReadTarget> get copyWith => _$RecoveryReadTargetCopyWithImpl<RecoveryReadTarget>(this as RecoveryReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as RecoveryReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as RecoveryReadTarget;
  return 'RecoveryReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $RecoveryReadTargetCopyWith<$Res>  {
  factory $RecoveryReadTargetCopyWith(RecoveryReadTarget value, $Res Function(RecoveryReadTarget) _then) = _$RecoveryReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, RecoveryReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$RecoveryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$RecoveryReadTargetCopyWithImpl<$Res>
    implements $RecoveryReadTargetCopyWith<$Res> {
  _$RecoveryReadTargetCopyWithImpl(this._self, this._then);

  final RecoveryReadTarget _self;
  final $Res Function(RecoveryReadTarget) _then;

/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(RecoveryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RecoveryReadRef,
  ));
}
/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryReadRefCopyWith<$Res> get reference {

  return $RecoveryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryReadTarget].
extension RecoveryReadTargetPatterns on RecoveryReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  RecoveryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  RecoveryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _RecoveryReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  RecoveryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryReadTarget implements RecoveryReadTarget {
  const _RecoveryReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  RecoveryReadRef reference;

/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryReadTargetCopyWith<_RecoveryReadTarget> get copyWith => __$RecoveryReadTargetCopyWithImpl<_RecoveryReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'RecoveryReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$RecoveryReadTargetCopyWith<$Res> implements $RecoveryReadTargetCopyWith<$Res> {
  factory _$RecoveryReadTargetCopyWith(_RecoveryReadTarget value, $Res Function(_RecoveryReadTarget) _then) = __$RecoveryReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, RecoveryReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $RecoveryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$RecoveryReadTargetCopyWithImpl<$Res>
    implements _$RecoveryReadTargetCopyWith<$Res> {
  __$RecoveryReadTargetCopyWithImpl(this._self, this._then);

  final _RecoveryReadTarget _self;
  final $Res Function(_RecoveryReadTarget) _then;

/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_RecoveryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RecoveryReadRef,
  ));
}

/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of RecoveryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryReadRefCopyWith<$Res> get reference {

  return $RecoveryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$RecoveryHeader {

 ObservedHeader get source; RecoveryReadRef? get reference;
/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryHeaderCopyWith<RecoveryHeader> get copyWith => _$RecoveryHeaderCopyWithImpl<RecoveryHeader>(this as RecoveryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as RecoveryHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as RecoveryHeader;
  return 'RecoveryHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $RecoveryHeaderCopyWith<$Res>  {
  factory $RecoveryHeaderCopyWith(RecoveryHeader value, $Res Function(RecoveryHeader) _then) = _$RecoveryHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, RecoveryReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$RecoveryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$RecoveryHeaderCopyWithImpl<$Res>
    implements $RecoveryHeaderCopyWith<$Res> {
  _$RecoveryHeaderCopyWithImpl(this._self, this._then);

  final RecoveryHeader _self;
  final $Res Function(RecoveryHeader) _then;

/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(RecoveryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RecoveryReadRef?,
  ));
}
/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $RecoveryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryHeader].
extension RecoveryHeaderPatterns on RecoveryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryHeader value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  RecoveryReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  RecoveryReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _RecoveryHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  RecoveryReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryHeader implements RecoveryHeader {
  const _RecoveryHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  RecoveryReadRef? reference;

/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryHeaderCopyWith<_RecoveryHeader> get copyWith => __$RecoveryHeaderCopyWithImpl<_RecoveryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'RecoveryHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$RecoveryHeaderCopyWith<$Res> implements $RecoveryHeaderCopyWith<$Res> {
  factory _$RecoveryHeaderCopyWith(_RecoveryHeader value, $Res Function(_RecoveryHeader) _then) = __$RecoveryHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, RecoveryReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $RecoveryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$RecoveryHeaderCopyWithImpl<$Res>
    implements _$RecoveryHeaderCopyWith<$Res> {
  __$RecoveryHeaderCopyWithImpl(this._self, this._then);

  final _RecoveryHeader _self;
  final $Res Function(_RecoveryHeader) _then;

/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_RecoveryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RecoveryReadRef?,
  ));
}

/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of RecoveryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $RecoveryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$RecoveryState {

 ProductProjection<RecoveryHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<RecoveryIssue> get issues;
/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<RecoveryState> get copyWith => _$RecoveryStateCopyWithImpl<RecoveryState>(this as RecoveryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.issues, _this.issues) || other.issues == _this.issues));
}


@override
int get hashCode {
  final _this = this as RecoveryState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.issues);
}



}

/// @nodoc
abstract mixin class $RecoveryStateCopyWith<$Res>  {
  factory $RecoveryStateCopyWith(RecoveryState value, $Res Function(RecoveryState) _then) = _$RecoveryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<RecoveryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<RecoveryIssue> issues
});


$ProductProjectionCopyWith<RecoveryHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<RecoveryIssue, $Res> get issues;

}
/// @nodoc
class _$RecoveryStateCopyWithImpl<$Res>
    implements $RecoveryStateCopyWith<$Res> {
  _$RecoveryStateCopyWithImpl(this._self, this._then);

  final RecoveryState _self;
  final $Res Function(RecoveryState) _then;

/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? issues = null,}) {
  return _then(RecoveryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<RecoveryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as CollectionMirror<RecoveryIssue>,
  ));
}
/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<RecoveryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<RecoveryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of RecoveryState
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
}/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<RecoveryIssue, $Res> get issues {

  return $CollectionMirrorCopyWith<RecoveryIssue, $Res>(_self.issues, (value) {
    return _then(_self.copyWith(issues: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryState].
extension RecoveryStatePatterns on RecoveryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryState value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryState value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<RecoveryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<RecoveryIssue> issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<RecoveryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<RecoveryIssue> issues)  $default,) {final _that = this;
switch (_that) {
case _RecoveryState():
return $default(_that.projection,_that.sourceStatus,_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<RecoveryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<RecoveryIssue> issues)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryState implements RecoveryState {
  const _RecoveryState({required this.projection, required this.sourceStatus, required this.issues});


@override final  ProductProjection<RecoveryHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<RecoveryIssue> issues;

/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryStateCopyWith<_RecoveryState> get copyWith => __$RecoveryStateCopyWithImpl<_RecoveryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.issues, issues) || other.issues == issues));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,issues);
}



}

/// @nodoc
abstract mixin class _$RecoveryStateCopyWith<$Res> implements $RecoveryStateCopyWith<$Res> {
  factory _$RecoveryStateCopyWith(_RecoveryState value, $Res Function(_RecoveryState) _then) = __$RecoveryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<RecoveryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<RecoveryIssue> issues
});


@override $ProductProjectionCopyWith<RecoveryHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<RecoveryIssue, $Res> get issues;

}
/// @nodoc
class __$RecoveryStateCopyWithImpl<$Res>
    implements _$RecoveryStateCopyWith<$Res> {
  __$RecoveryStateCopyWithImpl(this._self, this._then);

  final _RecoveryState _self;
  final $Res Function(_RecoveryState) _then;

/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? issues = null,}) {
  return _then(_RecoveryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<RecoveryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as CollectionMirror<RecoveryIssue>,
  ));
}

/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<RecoveryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<RecoveryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of RecoveryState
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
}/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<RecoveryIssue, $Res> get issues {

  return $CollectionMirrorCopyWith<RecoveryIssue, $Res>(_self.issues, (value) {
    return _then(_self.copyWith(issues: value));
  });
}
}

// dart format on
