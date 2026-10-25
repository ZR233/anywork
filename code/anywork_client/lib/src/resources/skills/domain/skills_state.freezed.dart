// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SkillsReadRef {

 int get entry; int get revision;
/// Create a copy of SkillsReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsReadRefCopyWith<SkillsReadRef> get copyWith => _$SkillsReadRefCopyWithImpl<SkillsReadRef>(this as SkillsReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as SkillsReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as SkillsReadRef;
  return 'SkillsReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $SkillsReadRefCopyWith<$Res>  {
  factory $SkillsReadRefCopyWith(SkillsReadRef value, $Res Function(SkillsReadRef) _then) = _$SkillsReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$SkillsReadRefCopyWithImpl<$Res>
    implements $SkillsReadRefCopyWith<$Res> {
  _$SkillsReadRefCopyWithImpl(this._self, this._then);

  final SkillsReadRef _self;
  final $Res Function(SkillsReadRef) _then;

/// Create a copy of SkillsReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(SkillsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillsReadRef].
extension SkillsReadRefPatterns on SkillsReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsReadRef value)  $default,){
final _that = this;
switch (_that) {
case _SkillsReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsReadRef() when $default != null:
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
case _SkillsReadRef() when $default != null:
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
case _SkillsReadRef():
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
case _SkillsReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsReadRef implements SkillsReadRef {
  const _SkillsReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of SkillsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsReadRefCopyWith<_SkillsReadRef> get copyWith => __$SkillsReadRefCopyWithImpl<_SkillsReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'SkillsReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$SkillsReadRefCopyWith<$Res> implements $SkillsReadRefCopyWith<$Res> {
  factory _$SkillsReadRefCopyWith(_SkillsReadRef value, $Res Function(_SkillsReadRef) _then) = __$SkillsReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$SkillsReadRefCopyWithImpl<$Res>
    implements _$SkillsReadRefCopyWith<$Res> {
  __$SkillsReadRefCopyWithImpl(this._self, this._then);

  final _SkillsReadRef _self;
  final $Res Function(_SkillsReadRef) _then;

/// Create a copy of SkillsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_SkillsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$SkillsReadTarget {

 ProductReadOrigin get origin; SkillsReadRef get reference;
/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsReadTargetCopyWith<SkillsReadTarget> get copyWith => _$SkillsReadTargetCopyWithImpl<SkillsReadTarget>(this as SkillsReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as SkillsReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as SkillsReadTarget;
  return 'SkillsReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $SkillsReadTargetCopyWith<$Res>  {
  factory $SkillsReadTargetCopyWith(SkillsReadTarget value, $Res Function(SkillsReadTarget) _then) = _$SkillsReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, SkillsReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$SkillsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$SkillsReadTargetCopyWithImpl<$Res>
    implements $SkillsReadTargetCopyWith<$Res> {
  _$SkillsReadTargetCopyWithImpl(this._self, this._then);

  final SkillsReadTarget _self;
  final $Res Function(SkillsReadTarget) _then;

/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(SkillsReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SkillsReadRef,
  ));
}
/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsReadRefCopyWith<$Res> get reference {

  return $SkillsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsReadTarget].
extension SkillsReadTargetPatterns on SkillsReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _SkillsReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  SkillsReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  SkillsReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _SkillsReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  SkillsReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _SkillsReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsReadTarget implements SkillsReadTarget {
  const _SkillsReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  SkillsReadRef reference;

/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsReadTargetCopyWith<_SkillsReadTarget> get copyWith => __$SkillsReadTargetCopyWithImpl<_SkillsReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'SkillsReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$SkillsReadTargetCopyWith<$Res> implements $SkillsReadTargetCopyWith<$Res> {
  factory _$SkillsReadTargetCopyWith(_SkillsReadTarget value, $Res Function(_SkillsReadTarget) _then) = __$SkillsReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, SkillsReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $SkillsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$SkillsReadTargetCopyWithImpl<$Res>
    implements _$SkillsReadTargetCopyWith<$Res> {
  __$SkillsReadTargetCopyWithImpl(this._self, this._then);

  final _SkillsReadTarget _self;
  final $Res Function(_SkillsReadTarget) _then;

/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_SkillsReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SkillsReadRef,
  ));
}

/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of SkillsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsReadRefCopyWith<$Res> get reference {

  return $SkillsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$SkillsHeader {

 ObservedHeader get source; SkillsReadRef? get reference; int? get catalogRevision; bool? get complete;
/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsHeaderCopyWith<SkillsHeader> get copyWith => _$SkillsHeaderCopyWithImpl<SkillsHeader>(this as SkillsHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.complete, _this.complete) || other.complete == _this.complete));
}


@override
int get hashCode {
  final _this = this as SkillsHeader;
  return Object.hash(runtimeType,_this.source,_this.reference,_this.catalogRevision,_this.complete);
}

@override
String toString() {
  final _this = this as SkillsHeader;
  return 'SkillsHeader(source: ${_this.source}, reference: ${_this.reference}, catalogRevision: ${_this.catalogRevision}, complete: ${_this.complete})';
}


}

/// @nodoc
abstract mixin class $SkillsHeaderCopyWith<$Res>  {
  factory $SkillsHeaderCopyWith(SkillsHeader value, $Res Function(SkillsHeader) _then) = _$SkillsHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, SkillsReadRef? reference, int? catalogRevision, bool? complete
});


$ObservedHeaderCopyWith<$Res> get source;$SkillsReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$SkillsHeaderCopyWithImpl<$Res>
    implements $SkillsHeaderCopyWith<$Res> {
  _$SkillsHeaderCopyWithImpl(this._self, this._then);

  final SkillsHeader _self;
  final $Res Function(SkillsHeader) _then;

/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,Object? catalogRevision = freezed,Object? complete = freezed,}) {
  return _then(SkillsHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SkillsReadRef?,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,complete: freezed == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $SkillsReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsHeader].
extension SkillsHeaderPatterns on SkillsHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsHeader value)  $default,){
final _that = this;
switch (_that) {
case _SkillsHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsHeader value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  SkillsReadRef? reference,  int? catalogRevision,  bool? complete)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsHeader() when $default != null:
return $default(_that.source,_that.reference,_that.catalogRevision,_that.complete);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  SkillsReadRef? reference,  int? catalogRevision,  bool? complete)  $default,) {final _that = this;
switch (_that) {
case _SkillsHeader():
return $default(_that.source,_that.reference,_that.catalogRevision,_that.complete);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  SkillsReadRef? reference,  int? catalogRevision,  bool? complete)?  $default,) {final _that = this;
switch (_that) {
case _SkillsHeader() when $default != null:
return $default(_that.source,_that.reference,_that.catalogRevision,_that.complete);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsHeader implements SkillsHeader {
  const _SkillsHeader({required this.source, required this.reference, required this.catalogRevision, required this.complete});


@override final  ObservedHeader source;
@override final  SkillsReadRef? reference;
@override final  int? catalogRevision;
@override final  bool? complete;

/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsHeaderCopyWith<_SkillsHeader> get copyWith => __$SkillsHeaderCopyWithImpl<_SkillsHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.catalogRevision, catalogRevision) || other.catalogRevision == catalogRevision)&&(identical(other.complete, complete) || other.complete == complete));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference,catalogRevision,complete);
}

@override
String toString() {
    return 'SkillsHeader(source: $source, reference: $reference, catalogRevision: $catalogRevision, complete: $complete)';
}


}

/// @nodoc
abstract mixin class _$SkillsHeaderCopyWith<$Res> implements $SkillsHeaderCopyWith<$Res> {
  factory _$SkillsHeaderCopyWith(_SkillsHeader value, $Res Function(_SkillsHeader) _then) = __$SkillsHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, SkillsReadRef? reference, int? catalogRevision, bool? complete
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $SkillsReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$SkillsHeaderCopyWithImpl<$Res>
    implements _$SkillsHeaderCopyWith<$Res> {
  __$SkillsHeaderCopyWithImpl(this._self, this._then);

  final _SkillsHeader _self;
  final $Res Function(_SkillsHeader) _then;

/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,Object? catalogRevision = freezed,Object? complete = freezed,}) {
  return _then(_SkillsHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SkillsReadRef?,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,complete: freezed == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $SkillsReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$SkillsState {

 ProductProjection<SkillsHeader> get projection; String get projectId; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<SkillSummary> get skills; ReadValue<List<String>, SkillsReadRef>? get warnings; ReadValue<String, SkillsReadRef>? get projectDirectory; ReadValue<String, SkillsReadRef>? get configFingerprint;
/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsStateCopyWith<SkillsState> get copyWith => _$SkillsStateCopyWithImpl<SkillsState>(this as SkillsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.skills, _this.skills) || other.skills == _this.skills)&&(identical(other.warnings, _this.warnings) || other.warnings == _this.warnings)&&(identical(other.projectDirectory, _this.projectDirectory) || other.projectDirectory == _this.projectDirectory)&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint));
}


@override
int get hashCode {
  final _this = this as SkillsState;
  return Object.hash(runtimeType,_this.projection,_this.projectId,_this.sourceStatus,_this.skills,_this.warnings,_this.projectDirectory,_this.configFingerprint);
}



}

/// @nodoc
abstract mixin class $SkillsStateCopyWith<$Res>  {
  factory $SkillsStateCopyWith(SkillsState value, $Res Function(SkillsState) _then) = _$SkillsStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<SkillsHeader> projection, String projectId, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<SkillSummary> skills, ReadValue<List<String>, SkillsReadRef>? warnings, ReadValue<String, SkillsReadRef>? projectDirectory, ReadValue<String, SkillsReadRef>? configFingerprint
});


$ProductProjectionCopyWith<SkillsHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<SkillSummary, $Res> get skills;$ReadValueCopyWith<List<String>, SkillsReadRef, $Res>? get warnings;$ReadValueCopyWith<String, SkillsReadRef, $Res>? get projectDirectory;$ReadValueCopyWith<String, SkillsReadRef, $Res>? get configFingerprint;

}
/// @nodoc
class _$SkillsStateCopyWithImpl<$Res>
    implements $SkillsStateCopyWith<$Res> {
  _$SkillsStateCopyWithImpl(this._self, this._then);

  final SkillsState _self;
  final $Res Function(SkillsState) _then;

/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? projectId = null,Object? sourceStatus = freezed,Object? skills = null,Object? warnings = freezed,Object? projectDirectory = freezed,Object? configFingerprint = freezed,}) {
  return _then(SkillsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<SkillsHeader>,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as CollectionMirror<SkillSummary>,warnings: freezed == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, SkillsReadRef>?,projectDirectory: freezed == projectDirectory ? _self.projectDirectory : projectDirectory // ignore: cast_nullable_to_non_nullable
as ReadValue<String, SkillsReadRef>?,configFingerprint: freezed == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, SkillsReadRef>?,
  ));
}
/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<SkillsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<SkillsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of SkillsState
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
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<SkillSummary, $Res> get skills {

  return $CollectionMirrorCopyWith<SkillSummary, $Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, SkillsReadRef, $Res>? get warnings {
    if (_self.warnings == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, SkillsReadRef, $Res>(_self.warnings!, (value) {
    return _then(_self.copyWith(warnings: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, SkillsReadRef, $Res>? get projectDirectory {
    if (_self.projectDirectory == null) {
    return null;
  }

  return $ReadValueCopyWith<String, SkillsReadRef, $Res>(_self.projectDirectory!, (value) {
    return _then(_self.copyWith(projectDirectory: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, SkillsReadRef, $Res>? get configFingerprint {
    if (_self.configFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, SkillsReadRef, $Res>(_self.configFingerprint!, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsState].
extension SkillsStatePatterns on SkillsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsState value)  $default,){
final _that = this;
switch (_that) {
case _SkillsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsState value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<SkillsHeader> projection,  String projectId,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<SkillSummary> skills,  ReadValue<List<String>, SkillsReadRef>? warnings,  ReadValue<String, SkillsReadRef>? projectDirectory,  ReadValue<String, SkillsReadRef>? configFingerprint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsState() when $default != null:
return $default(_that.projection,_that.projectId,_that.sourceStatus,_that.skills,_that.warnings,_that.projectDirectory,_that.configFingerprint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<SkillsHeader> projection,  String projectId,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<SkillSummary> skills,  ReadValue<List<String>, SkillsReadRef>? warnings,  ReadValue<String, SkillsReadRef>? projectDirectory,  ReadValue<String, SkillsReadRef>? configFingerprint)  $default,) {final _that = this;
switch (_that) {
case _SkillsState():
return $default(_that.projection,_that.projectId,_that.sourceStatus,_that.skills,_that.warnings,_that.projectDirectory,_that.configFingerprint);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<SkillsHeader> projection,  String projectId,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<SkillSummary> skills,  ReadValue<List<String>, SkillsReadRef>? warnings,  ReadValue<String, SkillsReadRef>? projectDirectory,  ReadValue<String, SkillsReadRef>? configFingerprint)?  $default,) {final _that = this;
switch (_that) {
case _SkillsState() when $default != null:
return $default(_that.projection,_that.projectId,_that.sourceStatus,_that.skills,_that.warnings,_that.projectDirectory,_that.configFingerprint);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsState implements SkillsState {
  const _SkillsState({required this.projection, required this.projectId, required this.sourceStatus, required this.skills, required this.warnings, required this.projectDirectory, required this.configFingerprint});


@override final  ProductProjection<SkillsHeader> projection;
@override final  String projectId;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<SkillSummary> skills;
@override final  ReadValue<List<String>, SkillsReadRef>? warnings;
@override final  ReadValue<String, SkillsReadRef>? projectDirectory;
@override final  ReadValue<String, SkillsReadRef>? configFingerprint;

/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsStateCopyWith<_SkillsState> get copyWith => __$SkillsStateCopyWithImpl<_SkillsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.skills, skills) || other.skills == skills)&&(identical(other.warnings, warnings) || other.warnings == warnings)&&(identical(other.projectDirectory, projectDirectory) || other.projectDirectory == projectDirectory)&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,projectId,sourceStatus,skills,warnings,projectDirectory,configFingerprint);
}



}

/// @nodoc
abstract mixin class _$SkillsStateCopyWith<$Res> implements $SkillsStateCopyWith<$Res> {
  factory _$SkillsStateCopyWith(_SkillsState value, $Res Function(_SkillsState) _then) = __$SkillsStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<SkillsHeader> projection, String projectId, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<SkillSummary> skills, ReadValue<List<String>, SkillsReadRef>? warnings, ReadValue<String, SkillsReadRef>? projectDirectory, ReadValue<String, SkillsReadRef>? configFingerprint
});


@override $ProductProjectionCopyWith<SkillsHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<SkillSummary, $Res> get skills;@override $ReadValueCopyWith<List<String>, SkillsReadRef, $Res>? get warnings;@override $ReadValueCopyWith<String, SkillsReadRef, $Res>? get projectDirectory;@override $ReadValueCopyWith<String, SkillsReadRef, $Res>? get configFingerprint;

}
/// @nodoc
class __$SkillsStateCopyWithImpl<$Res>
    implements _$SkillsStateCopyWith<$Res> {
  __$SkillsStateCopyWithImpl(this._self, this._then);

  final _SkillsState _self;
  final $Res Function(_SkillsState) _then;

/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? projectId = null,Object? sourceStatus = freezed,Object? skills = null,Object? warnings = freezed,Object? projectDirectory = freezed,Object? configFingerprint = freezed,}) {
  return _then(_SkillsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<SkillsHeader>,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as CollectionMirror<SkillSummary>,warnings: freezed == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as ReadValue<List<String>, SkillsReadRef>?,projectDirectory: freezed == projectDirectory ? _self.projectDirectory : projectDirectory // ignore: cast_nullable_to_non_nullable
as ReadValue<String, SkillsReadRef>?,configFingerprint: freezed == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, SkillsReadRef>?,
  ));
}

/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<SkillsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<SkillsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of SkillsState
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
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<SkillSummary, $Res> get skills {

  return $CollectionMirrorCopyWith<SkillSummary, $Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<String>, SkillsReadRef, $Res>? get warnings {
    if (_self.warnings == null) {
    return null;
  }

  return $ReadValueCopyWith<List<String>, SkillsReadRef, $Res>(_self.warnings!, (value) {
    return _then(_self.copyWith(warnings: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, SkillsReadRef, $Res>? get projectDirectory {
    if (_self.projectDirectory == null) {
    return null;
  }

  return $ReadValueCopyWith<String, SkillsReadRef, $Res>(_self.projectDirectory!, (value) {
    return _then(_self.copyWith(projectDirectory: value));
  });
}/// Create a copy of SkillsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, SkillsReadRef, $Res>? get configFingerprint {
    if (_self.configFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, SkillsReadRef, $Res>(_self.configFingerprint!, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}
}

// dart format on
