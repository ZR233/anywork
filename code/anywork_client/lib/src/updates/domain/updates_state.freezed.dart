// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdatesReadRef {

 int get entry; int get revision;
/// Create a copy of UpdatesReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesReadRefCopyWith<UpdatesReadRef> get copyWith => _$UpdatesReadRefCopyWithImpl<UpdatesReadRef>(this as UpdatesReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdatesReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as UpdatesReadRef;
  return 'UpdatesReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdatesReadRefCopyWith<$Res>  {
  factory $UpdatesReadRefCopyWith(UpdatesReadRef value, $Res Function(UpdatesReadRef) _then) = _$UpdatesReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$UpdatesReadRefCopyWithImpl<$Res>
    implements $UpdatesReadRefCopyWith<$Res> {
  _$UpdatesReadRefCopyWithImpl(this._self, this._then);

  final UpdatesReadRef _self;
  final $Res Function(UpdatesReadRef) _then;

/// Create a copy of UpdatesReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(UpdatesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdatesReadRef].
extension UpdatesReadRefPatterns on UpdatesReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatesReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatesReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatesReadRef value)  $default,){
final _that = this;
switch (_that) {
case _UpdatesReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatesReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatesReadRef() when $default != null:
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
case _UpdatesReadRef() when $default != null:
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
case _UpdatesReadRef():
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
case _UpdatesReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatesReadRef implements UpdatesReadRef {
  const _UpdatesReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of UpdatesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesReadRefCopyWith<_UpdatesReadRef> get copyWith => __$UpdatesReadRefCopyWithImpl<_UpdatesReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'UpdatesReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$UpdatesReadRefCopyWith<$Res> implements $UpdatesReadRefCopyWith<$Res> {
  factory _$UpdatesReadRefCopyWith(_UpdatesReadRef value, $Res Function(_UpdatesReadRef) _then) = __$UpdatesReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$UpdatesReadRefCopyWithImpl<$Res>
    implements _$UpdatesReadRefCopyWith<$Res> {
  __$UpdatesReadRefCopyWithImpl(this._self, this._then);

  final _UpdatesReadRef _self;
  final $Res Function(_UpdatesReadRef) _then;

/// Create a copy of UpdatesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_UpdatesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdatesReadTarget {

 ProductReadOrigin get origin; UpdatesReadRef get reference;
/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesReadTargetCopyWith<UpdatesReadTarget> get copyWith => _$UpdatesReadTargetCopyWithImpl<UpdatesReadTarget>(this as UpdatesReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as UpdatesReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as UpdatesReadTarget;
  return 'UpdatesReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $UpdatesReadTargetCopyWith<$Res>  {
  factory $UpdatesReadTargetCopyWith(UpdatesReadTarget value, $Res Function(UpdatesReadTarget) _then) = _$UpdatesReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, UpdatesReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$UpdatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$UpdatesReadTargetCopyWithImpl<$Res>
    implements $UpdatesReadTargetCopyWith<$Res> {
  _$UpdatesReadTargetCopyWithImpl(this._self, this._then);

  final UpdatesReadTarget _self;
  final $Res Function(UpdatesReadTarget) _then;

/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(UpdatesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as UpdatesReadRef,
  ));
}
/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesReadRefCopyWith<$Res> get reference {

  return $UpdatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatesReadTarget].
extension UpdatesReadTargetPatterns on UpdatesReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatesReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatesReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _UpdatesReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatesReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  UpdatesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  UpdatesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _UpdatesReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  UpdatesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _UpdatesReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatesReadTarget implements UpdatesReadTarget {
  const _UpdatesReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  UpdatesReadRef reference;

/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesReadTargetCopyWith<_UpdatesReadTarget> get copyWith => __$UpdatesReadTargetCopyWithImpl<_UpdatesReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'UpdatesReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$UpdatesReadTargetCopyWith<$Res> implements $UpdatesReadTargetCopyWith<$Res> {
  factory _$UpdatesReadTargetCopyWith(_UpdatesReadTarget value, $Res Function(_UpdatesReadTarget) _then) = __$UpdatesReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, UpdatesReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $UpdatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$UpdatesReadTargetCopyWithImpl<$Res>
    implements _$UpdatesReadTargetCopyWith<$Res> {
  __$UpdatesReadTargetCopyWithImpl(this._self, this._then);

  final _UpdatesReadTarget _self;
  final $Res Function(_UpdatesReadTarget) _then;

/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_UpdatesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as UpdatesReadRef,
  ));
}

/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of UpdatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesReadRefCopyWith<$Res> get reference {

  return $UpdatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$UpdateSummaryReadRef {

 int get entry; int get revision;
/// Create a copy of UpdateSummaryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateSummaryReadRefCopyWith<UpdateSummaryReadRef> get copyWith => _$UpdateSummaryReadRefCopyWithImpl<UpdateSummaryReadRef>(this as UpdateSummaryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateSummaryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateSummaryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdateSummaryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as UpdateSummaryReadRef;
  return 'UpdateSummaryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdateSummaryReadRefCopyWith<$Res>  {
  factory $UpdateSummaryReadRefCopyWith(UpdateSummaryReadRef value, $Res Function(UpdateSummaryReadRef) _then) = _$UpdateSummaryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$UpdateSummaryReadRefCopyWithImpl<$Res>
    implements $UpdateSummaryReadRefCopyWith<$Res> {
  _$UpdateSummaryReadRefCopyWithImpl(this._self, this._then);

  final UpdateSummaryReadRef _self;
  final $Res Function(UpdateSummaryReadRef) _then;

/// Create a copy of UpdateSummaryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(UpdateSummaryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateSummaryReadRef].
extension UpdateSummaryReadRefPatterns on UpdateSummaryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateSummaryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateSummaryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateSummaryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _UpdateSummaryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateSummaryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateSummaryReadRef() when $default != null:
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
case _UpdateSummaryReadRef() when $default != null:
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
case _UpdateSummaryReadRef():
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
case _UpdateSummaryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateSummaryReadRef implements UpdateSummaryReadRef {
  const _UpdateSummaryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of UpdateSummaryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateSummaryReadRefCopyWith<_UpdateSummaryReadRef> get copyWith => __$UpdateSummaryReadRefCopyWithImpl<_UpdateSummaryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateSummaryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'UpdateSummaryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$UpdateSummaryReadRefCopyWith<$Res> implements $UpdateSummaryReadRefCopyWith<$Res> {
  factory _$UpdateSummaryReadRefCopyWith(_UpdateSummaryReadRef value, $Res Function(_UpdateSummaryReadRef) _then) = __$UpdateSummaryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$UpdateSummaryReadRefCopyWithImpl<$Res>
    implements _$UpdateSummaryReadRefCopyWith<$Res> {
  __$UpdateSummaryReadRefCopyWithImpl(this._self, this._then);

  final _UpdateSummaryReadRef _self;
  final $Res Function(_UpdateSummaryReadRef) _then;

/// Create a copy of UpdateSummaryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_UpdateSummaryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdateOperationReadRef {

 int get entry; int get revision;
/// Create a copy of UpdateOperationReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateOperationReadRefCopyWith<UpdateOperationReadRef> get copyWith => _$UpdateOperationReadRefCopyWithImpl<UpdateOperationReadRef>(this as UpdateOperationReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateOperationReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateOperationReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdateOperationReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as UpdateOperationReadRef;
  return 'UpdateOperationReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdateOperationReadRefCopyWith<$Res>  {
  factory $UpdateOperationReadRefCopyWith(UpdateOperationReadRef value, $Res Function(UpdateOperationReadRef) _then) = _$UpdateOperationReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$UpdateOperationReadRefCopyWithImpl<$Res>
    implements $UpdateOperationReadRefCopyWith<$Res> {
  _$UpdateOperationReadRefCopyWithImpl(this._self, this._then);

  final UpdateOperationReadRef _self;
  final $Res Function(UpdateOperationReadRef) _then;

/// Create a copy of UpdateOperationReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(UpdateOperationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateOperationReadRef].
extension UpdateOperationReadRefPatterns on UpdateOperationReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateOperationReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateOperationReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateOperationReadRef value)  $default,){
final _that = this;
switch (_that) {
case _UpdateOperationReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateOperationReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateOperationReadRef() when $default != null:
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
case _UpdateOperationReadRef() when $default != null:
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
case _UpdateOperationReadRef():
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
case _UpdateOperationReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateOperationReadRef implements UpdateOperationReadRef {
  const _UpdateOperationReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of UpdateOperationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateOperationReadRefCopyWith<_UpdateOperationReadRef> get copyWith => __$UpdateOperationReadRefCopyWithImpl<_UpdateOperationReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateOperationReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'UpdateOperationReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$UpdateOperationReadRefCopyWith<$Res> implements $UpdateOperationReadRefCopyWith<$Res> {
  factory _$UpdateOperationReadRefCopyWith(_UpdateOperationReadRef value, $Res Function(_UpdateOperationReadRef) _then) = __$UpdateOperationReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$UpdateOperationReadRefCopyWithImpl<$Res>
    implements _$UpdateOperationReadRefCopyWith<$Res> {
  __$UpdateOperationReadRefCopyWithImpl(this._self, this._then);

  final _UpdateOperationReadRef _self;
  final $Res Function(_UpdateOperationReadRef) _then;

/// Create a copy of UpdateOperationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_UpdateOperationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdateErrorReadRef {

 int get entry; int get revision;
/// Create a copy of UpdateErrorReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateErrorReadRefCopyWith<UpdateErrorReadRef> get copyWith => _$UpdateErrorReadRefCopyWithImpl<UpdateErrorReadRef>(this as UpdateErrorReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateErrorReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateErrorReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdateErrorReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as UpdateErrorReadRef;
  return 'UpdateErrorReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdateErrorReadRefCopyWith<$Res>  {
  factory $UpdateErrorReadRefCopyWith(UpdateErrorReadRef value, $Res Function(UpdateErrorReadRef) _then) = _$UpdateErrorReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$UpdateErrorReadRefCopyWithImpl<$Res>
    implements $UpdateErrorReadRefCopyWith<$Res> {
  _$UpdateErrorReadRefCopyWithImpl(this._self, this._then);

  final UpdateErrorReadRef _self;
  final $Res Function(UpdateErrorReadRef) _then;

/// Create a copy of UpdateErrorReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(UpdateErrorReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateErrorReadRef].
extension UpdateErrorReadRefPatterns on UpdateErrorReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateErrorReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateErrorReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateErrorReadRef value)  $default,){
final _that = this;
switch (_that) {
case _UpdateErrorReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateErrorReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateErrorReadRef() when $default != null:
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
case _UpdateErrorReadRef() when $default != null:
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
case _UpdateErrorReadRef():
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
case _UpdateErrorReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateErrorReadRef implements UpdateErrorReadRef {
  const _UpdateErrorReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of UpdateErrorReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateErrorReadRefCopyWith<_UpdateErrorReadRef> get copyWith => __$UpdateErrorReadRefCopyWithImpl<_UpdateErrorReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateErrorReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'UpdateErrorReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$UpdateErrorReadRefCopyWith<$Res> implements $UpdateErrorReadRefCopyWith<$Res> {
  factory _$UpdateErrorReadRefCopyWith(_UpdateErrorReadRef value, $Res Function(_UpdateErrorReadRef) _then) = __$UpdateErrorReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$UpdateErrorReadRefCopyWithImpl<$Res>
    implements _$UpdateErrorReadRefCopyWith<$Res> {
  __$UpdateErrorReadRefCopyWithImpl(this._self, this._then);

  final _UpdateErrorReadRef _self;
  final $Res Function(_UpdateErrorReadRef) _then;

/// Create a copy of UpdateErrorReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_UpdateErrorReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdateDetailsReadRef {

 int get entry; int get revision;
/// Create a copy of UpdateDetailsReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDetailsReadRefCopyWith<UpdateDetailsReadRef> get copyWith => _$UpdateDetailsReadRefCopyWithImpl<UpdateDetailsReadRef>(this as UpdateDetailsReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateDetailsReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDetailsReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdateDetailsReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as UpdateDetailsReadRef;
  return 'UpdateDetailsReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdateDetailsReadRefCopyWith<$Res>  {
  factory $UpdateDetailsReadRefCopyWith(UpdateDetailsReadRef value, $Res Function(UpdateDetailsReadRef) _then) = _$UpdateDetailsReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$UpdateDetailsReadRefCopyWithImpl<$Res>
    implements $UpdateDetailsReadRefCopyWith<$Res> {
  _$UpdateDetailsReadRefCopyWithImpl(this._self, this._then);

  final UpdateDetailsReadRef _self;
  final $Res Function(UpdateDetailsReadRef) _then;

/// Create a copy of UpdateDetailsReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(UpdateDetailsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateDetailsReadRef].
extension UpdateDetailsReadRefPatterns on UpdateDetailsReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateDetailsReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateDetailsReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateDetailsReadRef value)  $default,){
final _that = this;
switch (_that) {
case _UpdateDetailsReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateDetailsReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateDetailsReadRef() when $default != null:
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
case _UpdateDetailsReadRef() when $default != null:
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
case _UpdateDetailsReadRef():
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
case _UpdateDetailsReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateDetailsReadRef implements UpdateDetailsReadRef {
  const _UpdateDetailsReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of UpdateDetailsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateDetailsReadRefCopyWith<_UpdateDetailsReadRef> get copyWith => __$UpdateDetailsReadRefCopyWithImpl<_UpdateDetailsReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateDetailsReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'UpdateDetailsReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$UpdateDetailsReadRefCopyWith<$Res> implements $UpdateDetailsReadRefCopyWith<$Res> {
  factory _$UpdateDetailsReadRefCopyWith(_UpdateDetailsReadRef value, $Res Function(_UpdateDetailsReadRef) _then) = __$UpdateDetailsReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$UpdateDetailsReadRefCopyWithImpl<$Res>
    implements _$UpdateDetailsReadRefCopyWith<$Res> {
  __$UpdateDetailsReadRefCopyWithImpl(this._self, this._then);

  final _UpdateDetailsReadRef _self;
  final $Res Function(_UpdateDetailsReadRef) _then;

/// Create a copy of UpdateDetailsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_UpdateDetailsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdatesBrief {

 int get revision;
/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesBriefCopyWith<UpdatesBrief> get copyWith => _$UpdatesBriefCopyWithImpl<UpdatesBrief>(this as UpdatesBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdatesBrief;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as UpdatesBrief;
  return 'UpdatesBrief(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $UpdatesBriefCopyWith<$Res>  {
  factory $UpdatesBriefCopyWith(UpdatesBrief value, $Res Function(UpdatesBrief) _then) = _$UpdatesBriefCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$UpdatesBriefCopyWithImpl<$Res>
    implements $UpdatesBriefCopyWith<$Res> {
  _$UpdatesBriefCopyWithImpl(this._self, this._then);

  final UpdatesBrief _self;
  final $Res Function(UpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdatesBrief].
extension UpdatesBriefPatterns on UpdatesBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisabledUpdatesBrief value)?  disabled,TResult Function( IdleUpdatesBrief value)?  idle,TResult Function( CheckingUpdatesBrief value)?  checking,TResult Function( UpToDateUpdatesBrief value)?  upToDate,TResult Function( AvailableUpdatesBrief value)?  available,TResult Function( DownloadingUpdatesBrief value)?  downloading,TResult Function( VerifyingUpdatesBrief value)?  verifying,TResult Function( ReadyUpdatesBrief value)?  ready,TResult Function( InstallerLaunchedUpdatesBrief value)?  installerLaunched,TResult Function( CheckFailedUpdatesBrief value)?  checkFailed,TResult Function( InstallFailedUpdatesBrief value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisabledUpdatesBrief() when disabled != null:
return disabled(_that);case IdleUpdatesBrief() when idle != null:
return idle(_that);case CheckingUpdatesBrief() when checking != null:
return checking(_that);case UpToDateUpdatesBrief() when upToDate != null:
return upToDate(_that);case AvailableUpdatesBrief() when available != null:
return available(_that);case DownloadingUpdatesBrief() when downloading != null:
return downloading(_that);case VerifyingUpdatesBrief() when verifying != null:
return verifying(_that);case ReadyUpdatesBrief() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesBrief() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesBrief() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesBrief() when installFailed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisabledUpdatesBrief value)  disabled,required TResult Function( IdleUpdatesBrief value)  idle,required TResult Function( CheckingUpdatesBrief value)  checking,required TResult Function( UpToDateUpdatesBrief value)  upToDate,required TResult Function( AvailableUpdatesBrief value)  available,required TResult Function( DownloadingUpdatesBrief value)  downloading,required TResult Function( VerifyingUpdatesBrief value)  verifying,required TResult Function( ReadyUpdatesBrief value)  ready,required TResult Function( InstallerLaunchedUpdatesBrief value)  installerLaunched,required TResult Function( CheckFailedUpdatesBrief value)  checkFailed,required TResult Function( InstallFailedUpdatesBrief value)  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesBrief():
return disabled(_that);case IdleUpdatesBrief():
return idle(_that);case CheckingUpdatesBrief():
return checking(_that);case UpToDateUpdatesBrief():
return upToDate(_that);case AvailableUpdatesBrief():
return available(_that);case DownloadingUpdatesBrief():
return downloading(_that);case VerifyingUpdatesBrief():
return verifying(_that);case ReadyUpdatesBrief():
return ready(_that);case InstallerLaunchedUpdatesBrief():
return installerLaunched(_that);case CheckFailedUpdatesBrief():
return checkFailed(_that);case InstallFailedUpdatesBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisabledUpdatesBrief value)?  disabled,TResult? Function( IdleUpdatesBrief value)?  idle,TResult? Function( CheckingUpdatesBrief value)?  checking,TResult? Function( UpToDateUpdatesBrief value)?  upToDate,TResult? Function( AvailableUpdatesBrief value)?  available,TResult? Function( DownloadingUpdatesBrief value)?  downloading,TResult? Function( VerifyingUpdatesBrief value)?  verifying,TResult? Function( ReadyUpdatesBrief value)?  ready,TResult? Function( InstallerLaunchedUpdatesBrief value)?  installerLaunched,TResult? Function( CheckFailedUpdatesBrief value)?  checkFailed,TResult? Function( InstallFailedUpdatesBrief value)?  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesBrief() when disabled != null:
return disabled(_that);case IdleUpdatesBrief() when idle != null:
return idle(_that);case CheckingUpdatesBrief() when checking != null:
return checking(_that);case UpToDateUpdatesBrief() when upToDate != null:
return upToDate(_that);case AvailableUpdatesBrief() when available != null:
return available(_that);case DownloadingUpdatesBrief() when downloading != null:
return downloading(_that);case VerifyingUpdatesBrief() when verifying != null:
return verifying(_that);case ReadyUpdatesBrief() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesBrief() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesBrief() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesBrief() when installFailed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  disabled,TResult Function( int revision,  int updatedAt)?  idle,TResult Function( int revision,  int startedAt)?  checking,TResult Function( int revision,  int checkedAt)?  upToDate,TResult Function( int revision,  int checkedAt)?  available,TResult Function( int revision,  int updatedAt,  int downloaded,  int total)?  downloading,TResult Function( int revision,  int updatedAt,  int downloaded,  int total)?  verifying,TResult Function( int revision,  int readyAt)?  ready,TResult Function( int revision,  int launchedAt)?  installerLaunched,TResult Function( int revision,  int failedAt,  bool retryable)?  checkFailed,TResult Function( int revision,  int failedAt,  bool retryable)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisabledUpdatesBrief() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesBrief() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesBrief() when checking != null:
return checking(_that.revision,_that.startedAt);case UpToDateUpdatesBrief() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesBrief() when available != null:
return available(_that.revision,_that.checkedAt);case DownloadingUpdatesBrief() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case VerifyingUpdatesBrief() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case ReadyUpdatesBrief() when ready != null:
return ready(_that.revision,_that.readyAt);case InstallerLaunchedUpdatesBrief() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt);case CheckFailedUpdatesBrief() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case InstallFailedUpdatesBrief() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  disabled,required TResult Function( int revision,  int updatedAt)  idle,required TResult Function( int revision,  int startedAt)  checking,required TResult Function( int revision,  int checkedAt)  upToDate,required TResult Function( int revision,  int checkedAt)  available,required TResult Function( int revision,  int updatedAt,  int downloaded,  int total)  downloading,required TResult Function( int revision,  int updatedAt,  int downloaded,  int total)  verifying,required TResult Function( int revision,  int readyAt)  ready,required TResult Function( int revision,  int launchedAt)  installerLaunched,required TResult Function( int revision,  int failedAt,  bool retryable)  checkFailed,required TResult Function( int revision,  int failedAt,  bool retryable)  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesBrief():
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesBrief():
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesBrief():
return checking(_that.revision,_that.startedAt);case UpToDateUpdatesBrief():
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesBrief():
return available(_that.revision,_that.checkedAt);case DownloadingUpdatesBrief():
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case VerifyingUpdatesBrief():
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case ReadyUpdatesBrief():
return ready(_that.revision,_that.readyAt);case InstallerLaunchedUpdatesBrief():
return installerLaunched(_that.revision,_that.launchedAt);case CheckFailedUpdatesBrief():
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case InstallFailedUpdatesBrief():
return installFailed(_that.revision,_that.failedAt,_that.retryable);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  disabled,TResult? Function( int revision,  int updatedAt)?  idle,TResult? Function( int revision,  int startedAt)?  checking,TResult? Function( int revision,  int checkedAt)?  upToDate,TResult? Function( int revision,  int checkedAt)?  available,TResult? Function( int revision,  int updatedAt,  int downloaded,  int total)?  downloading,TResult? Function( int revision,  int updatedAt,  int downloaded,  int total)?  verifying,TResult? Function( int revision,  int readyAt)?  ready,TResult? Function( int revision,  int launchedAt)?  installerLaunched,TResult? Function( int revision,  int failedAt,  bool retryable)?  checkFailed,TResult? Function( int revision,  int failedAt,  bool retryable)?  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesBrief() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesBrief() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesBrief() when checking != null:
return checking(_that.revision,_that.startedAt);case UpToDateUpdatesBrief() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesBrief() when available != null:
return available(_that.revision,_that.checkedAt);case DownloadingUpdatesBrief() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case VerifyingUpdatesBrief() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case ReadyUpdatesBrief() when ready != null:
return ready(_that.revision,_that.readyAt);case InstallerLaunchedUpdatesBrief() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt);case CheckFailedUpdatesBrief() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case InstallFailedUpdatesBrief() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class DisabledUpdatesBrief implements UpdatesBrief {
  const DisabledUpdatesBrief({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledUpdatesBriefCopyWith<DisabledUpdatesBrief> get copyWith => _$DisabledUpdatesBriefCopyWithImpl<DisabledUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'UpdatesBrief.disabled(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $DisabledUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $DisabledUpdatesBriefCopyWith(DisabledUpdatesBrief value, $Res Function(DisabledUpdatesBrief) _then) = _$DisabledUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$DisabledUpdatesBriefCopyWithImpl<$Res>
    implements $DisabledUpdatesBriefCopyWith<$Res> {
  _$DisabledUpdatesBriefCopyWithImpl(this._self, this._then);

  final DisabledUpdatesBrief _self;
  final $Res Function(DisabledUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(DisabledUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class IdleUpdatesBrief implements UpdatesBrief {
  const IdleUpdatesBrief({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdleUpdatesBriefCopyWith<IdleUpdatesBrief> get copyWith => _$IdleUpdatesBriefCopyWithImpl<IdleUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'UpdatesBrief.idle(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $IdleUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $IdleUpdatesBriefCopyWith(IdleUpdatesBrief value, $Res Function(IdleUpdatesBrief) _then) = _$IdleUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$IdleUpdatesBriefCopyWithImpl<$Res>
    implements $IdleUpdatesBriefCopyWith<$Res> {
  _$IdleUpdatesBriefCopyWithImpl(this._self, this._then);

  final IdleUpdatesBrief _self;
  final $Res Function(IdleUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(IdleUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CheckingUpdatesBrief implements UpdatesBrief {
  const CheckingUpdatesBrief({required this.revision, required this.startedAt});


@override final  int revision;
 final  int startedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingUpdatesBriefCopyWith<CheckingUpdatesBrief> get copyWith => _$CheckingUpdatesBriefCopyWithImpl<CheckingUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt);
}

@override
String toString() {
    return 'UpdatesBrief.checking(revision: $revision, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $CheckingUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $CheckingUpdatesBriefCopyWith(CheckingUpdatesBrief value, $Res Function(CheckingUpdatesBrief) _then) = _$CheckingUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int startedAt
});




}
/// @nodoc
class _$CheckingUpdatesBriefCopyWithImpl<$Res>
    implements $CheckingUpdatesBriefCopyWith<$Res> {
  _$CheckingUpdatesBriefCopyWithImpl(this._self, this._then);

  final CheckingUpdatesBrief _self;
  final $Res Function(CheckingUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,}) {
  return _then(CheckingUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class UpToDateUpdatesBrief implements UpdatesBrief {
  const UpToDateUpdatesBrief({required this.revision, required this.checkedAt});


@override final  int revision;
 final  int checkedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpToDateUpdatesBriefCopyWith<UpToDateUpdatesBrief> get copyWith => _$UpToDateUpdatesBriefCopyWithImpl<UpToDateUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpToDateUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}

@override
String toString() {
    return 'UpdatesBrief.upToDate(revision: $revision, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class $UpToDateUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $UpToDateUpdatesBriefCopyWith(UpToDateUpdatesBrief value, $Res Function(UpToDateUpdatesBrief) _then) = _$UpToDateUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt
});




}
/// @nodoc
class _$UpToDateUpdatesBriefCopyWithImpl<$Res>
    implements $UpToDateUpdatesBriefCopyWith<$Res> {
  _$UpToDateUpdatesBriefCopyWithImpl(this._self, this._then);

  final UpToDateUpdatesBrief _self;
  final $Res Function(UpToDateUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(UpToDateUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AvailableUpdatesBrief implements UpdatesBrief {
  const AvailableUpdatesBrief({required this.revision, required this.checkedAt});


@override final  int revision;
 final  int checkedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableUpdatesBriefCopyWith<AvailableUpdatesBrief> get copyWith => _$AvailableUpdatesBriefCopyWithImpl<AvailableUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}

@override
String toString() {
    return 'UpdatesBrief.available(revision: $revision, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class $AvailableUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $AvailableUpdatesBriefCopyWith(AvailableUpdatesBrief value, $Res Function(AvailableUpdatesBrief) _then) = _$AvailableUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt
});




}
/// @nodoc
class _$AvailableUpdatesBriefCopyWithImpl<$Res>
    implements $AvailableUpdatesBriefCopyWith<$Res> {
  _$AvailableUpdatesBriefCopyWithImpl(this._self, this._then);

  final AvailableUpdatesBrief _self;
  final $Res Function(AvailableUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(AvailableUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DownloadingUpdatesBrief implements UpdatesBrief {
  const DownloadingUpdatesBrief({required this.revision, required this.updatedAt, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadingUpdatesBriefCopyWith<DownloadingUpdatesBrief> get copyWith => _$DownloadingUpdatesBriefCopyWithImpl<DownloadingUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadingUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,downloaded,total);
}

@override
String toString() {
    return 'UpdatesBrief.downloading(revision: $revision, updatedAt: $updatedAt, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $DownloadingUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $DownloadingUpdatesBriefCopyWith(DownloadingUpdatesBrief value, $Res Function(DownloadingUpdatesBrief) _then) = _$DownloadingUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int downloaded, int total
});




}
/// @nodoc
class _$DownloadingUpdatesBriefCopyWithImpl<$Res>
    implements $DownloadingUpdatesBriefCopyWith<$Res> {
  _$DownloadingUpdatesBriefCopyWithImpl(this._self, this._then);

  final DownloadingUpdatesBrief _self;
  final $Res Function(DownloadingUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? downloaded = null,Object? total = null,}) {
  return _then(DownloadingUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class VerifyingUpdatesBrief implements UpdatesBrief {
  const VerifyingUpdatesBrief({required this.revision, required this.updatedAt, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VerifyingUpdatesBriefCopyWith<VerifyingUpdatesBrief> get copyWith => _$VerifyingUpdatesBriefCopyWithImpl<VerifyingUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerifyingUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,downloaded,total);
}

@override
String toString() {
    return 'UpdatesBrief.verifying(revision: $revision, updatedAt: $updatedAt, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $VerifyingUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $VerifyingUpdatesBriefCopyWith(VerifyingUpdatesBrief value, $Res Function(VerifyingUpdatesBrief) _then) = _$VerifyingUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int downloaded, int total
});




}
/// @nodoc
class _$VerifyingUpdatesBriefCopyWithImpl<$Res>
    implements $VerifyingUpdatesBriefCopyWith<$Res> {
  _$VerifyingUpdatesBriefCopyWithImpl(this._self, this._then);

  final VerifyingUpdatesBrief _self;
  final $Res Function(VerifyingUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? downloaded = null,Object? total = null,}) {
  return _then(VerifyingUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReadyUpdatesBrief implements UpdatesBrief {
  const ReadyUpdatesBrief({required this.revision, required this.readyAt});


@override final  int revision;
 final  int readyAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyUpdatesBriefCopyWith<ReadyUpdatesBrief> get copyWith => _$ReadyUpdatesBriefCopyWithImpl<ReadyUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt);
}

@override
String toString() {
    return 'UpdatesBrief.ready(revision: $revision, readyAt: $readyAt)';
}


}

/// @nodoc
abstract mixin class $ReadyUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $ReadyUpdatesBriefCopyWith(ReadyUpdatesBrief value, $Res Function(ReadyUpdatesBrief) _then) = _$ReadyUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int readyAt
});




}
/// @nodoc
class _$ReadyUpdatesBriefCopyWithImpl<$Res>
    implements $ReadyUpdatesBriefCopyWith<$Res> {
  _$ReadyUpdatesBriefCopyWithImpl(this._self, this._then);

  final ReadyUpdatesBrief _self;
  final $Res Function(ReadyUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,}) {
  return _then(ReadyUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class InstallerLaunchedUpdatesBrief implements UpdatesBrief {
  const InstallerLaunchedUpdatesBrief({required this.revision, required this.launchedAt});


@override final  int revision;
 final  int launchedAt;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallerLaunchedUpdatesBriefCopyWith<InstallerLaunchedUpdatesBrief> get copyWith => _$InstallerLaunchedUpdatesBriefCopyWithImpl<InstallerLaunchedUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchedUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.launchedAt, launchedAt) || other.launchedAt == launchedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,launchedAt);
}

@override
String toString() {
    return 'UpdatesBrief.installerLaunched(revision: $revision, launchedAt: $launchedAt)';
}


}

/// @nodoc
abstract mixin class $InstallerLaunchedUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $InstallerLaunchedUpdatesBriefCopyWith(InstallerLaunchedUpdatesBrief value, $Res Function(InstallerLaunchedUpdatesBrief) _then) = _$InstallerLaunchedUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int launchedAt
});




}
/// @nodoc
class _$InstallerLaunchedUpdatesBriefCopyWithImpl<$Res>
    implements $InstallerLaunchedUpdatesBriefCopyWith<$Res> {
  _$InstallerLaunchedUpdatesBriefCopyWithImpl(this._self, this._then);

  final InstallerLaunchedUpdatesBrief _self;
  final $Res Function(InstallerLaunchedUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? launchedAt = null,}) {
  return _then(InstallerLaunchedUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,launchedAt: null == launchedAt ? _self.launchedAt : launchedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CheckFailedUpdatesBrief implements UpdatesBrief {
  const CheckFailedUpdatesBrief({required this.revision, required this.failedAt, required this.retryable});


@override final  int revision;
 final  int failedAt;
 final  bool retryable;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckFailedUpdatesBriefCopyWith<CheckFailedUpdatesBrief> get copyWith => _$CheckFailedUpdatesBriefCopyWithImpl<CheckFailedUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckFailedUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'UpdatesBrief.checkFailed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $CheckFailedUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $CheckFailedUpdatesBriefCopyWith(CheckFailedUpdatesBrief value, $Res Function(CheckFailedUpdatesBrief) _then) = _$CheckFailedUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, bool retryable
});




}
/// @nodoc
class _$CheckFailedUpdatesBriefCopyWithImpl<$Res>
    implements $CheckFailedUpdatesBriefCopyWith<$Res> {
  _$CheckFailedUpdatesBriefCopyWithImpl(this._self, this._then);

  final CheckFailedUpdatesBrief _self;
  final $Res Function(CheckFailedUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(CheckFailedUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class InstallFailedUpdatesBrief implements UpdatesBrief {
  const InstallFailedUpdatesBrief({required this.revision, required this.failedAt, required this.retryable});


@override final  int revision;
 final  int failedAt;
 final  bool retryable;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallFailedUpdatesBriefCopyWith<InstallFailedUpdatesBrief> get copyWith => _$InstallFailedUpdatesBriefCopyWithImpl<InstallFailedUpdatesBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallFailedUpdatesBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'UpdatesBrief.installFailed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $InstallFailedUpdatesBriefCopyWith<$Res> implements $UpdatesBriefCopyWith<$Res> {
  factory $InstallFailedUpdatesBriefCopyWith(InstallFailedUpdatesBrief value, $Res Function(InstallFailedUpdatesBrief) _then) = _$InstallFailedUpdatesBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, bool retryable
});




}
/// @nodoc
class _$InstallFailedUpdatesBriefCopyWithImpl<$Res>
    implements $InstallFailedUpdatesBriefCopyWith<$Res> {
  _$InstallFailedUpdatesBriefCopyWithImpl(this._self, this._then);

  final InstallFailedUpdatesBrief _self;
  final $Res Function(InstallFailedUpdatesBrief) _then;

/// Create a copy of UpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(InstallFailedUpdatesBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$UpdatesHeader {

 UpdatesReadRef get reference; UpdatesBrief get brief; UpdateSummaryReadRef? get summary; UpdateOperationReadRef? get operation; UpdateErrorReadRef? get error; UpdateDetailsReadRef? get details;
/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesHeaderCopyWith<UpdatesHeader> get copyWith => _$UpdatesHeaderCopyWithImpl<UpdatesHeader>(this as UpdatesHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesHeader&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.brief, _this.brief) || other.brief == _this.brief)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.details, _this.details) || other.details == _this.details));
}


@override
int get hashCode {
  final _this = this as UpdatesHeader;
  return Object.hash(runtimeType,_this.reference,_this.brief,_this.summary,_this.operation,_this.error,_this.details);
}

@override
String toString() {
  final _this = this as UpdatesHeader;
  return 'UpdatesHeader(reference: ${_this.reference}, brief: ${_this.brief}, summary: ${_this.summary}, operation: ${_this.operation}, error: ${_this.error}, details: ${_this.details})';
}


}

/// @nodoc
abstract mixin class $UpdatesHeaderCopyWith<$Res>  {
  factory $UpdatesHeaderCopyWith(UpdatesHeader value, $Res Function(UpdatesHeader) _then) = _$UpdatesHeaderCopyWithImpl;
@useResult
$Res call({
 UpdatesReadRef reference, UpdatesBrief brief, UpdateSummaryReadRef? summary, UpdateOperationReadRef? operation, UpdateErrorReadRef? error, UpdateDetailsReadRef? details
});


$UpdatesReadRefCopyWith<$Res> get reference;$UpdatesBriefCopyWith<$Res> get brief;$UpdateSummaryReadRefCopyWith<$Res>? get summary;$UpdateOperationReadRefCopyWith<$Res>? get operation;$UpdateErrorReadRefCopyWith<$Res>? get error;$UpdateDetailsReadRefCopyWith<$Res>? get details;

}
/// @nodoc
class _$UpdatesHeaderCopyWithImpl<$Res>
    implements $UpdatesHeaderCopyWith<$Res> {
  _$UpdatesHeaderCopyWithImpl(this._self, this._then);

  final UpdatesHeader _self;
  final $Res Function(UpdatesHeader) _then;

/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? brief = null,Object? summary = freezed,Object? operation = freezed,Object? error = freezed,Object? details = freezed,}) {
  return _then(UpdatesHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as UpdatesReadRef,brief: null == brief ? _self.brief : brief // ignore: cast_nullable_to_non_nullable
as UpdatesBrief,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummaryReadRef?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as UpdateOperationReadRef?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as UpdateErrorReadRef?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as UpdateDetailsReadRef?,
  ));
}
/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesReadRefCopyWith<$Res> get reference {

  return $UpdatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesBriefCopyWith<$Res> get brief {

  return $UpdatesBriefCopyWith<$Res>(_self.brief, (value) {
    return _then(_self.copyWith(brief: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadRefCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $UpdateSummaryReadRefCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateOperationReadRefCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $UpdateOperationReadRefCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateErrorReadRefCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $UpdateErrorReadRefCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadRefCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $UpdateDetailsReadRefCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatesHeader].
extension UpdatesHeaderPatterns on UpdatesHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatesHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatesHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatesHeader value)  $default,){
final _that = this;
switch (_that) {
case _UpdatesHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatesHeader value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatesHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdatesReadRef reference,  UpdatesBrief brief,  UpdateSummaryReadRef? summary,  UpdateOperationReadRef? operation,  UpdateErrorReadRef? error,  UpdateDetailsReadRef? details)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatesHeader() when $default != null:
return $default(_that.reference,_that.brief,_that.summary,_that.operation,_that.error,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdatesReadRef reference,  UpdatesBrief brief,  UpdateSummaryReadRef? summary,  UpdateOperationReadRef? operation,  UpdateErrorReadRef? error,  UpdateDetailsReadRef? details)  $default,) {final _that = this;
switch (_that) {
case _UpdatesHeader():
return $default(_that.reference,_that.brief,_that.summary,_that.operation,_that.error,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdatesReadRef reference,  UpdatesBrief brief,  UpdateSummaryReadRef? summary,  UpdateOperationReadRef? operation,  UpdateErrorReadRef? error,  UpdateDetailsReadRef? details)?  $default,) {final _that = this;
switch (_that) {
case _UpdatesHeader() when $default != null:
return $default(_that.reference,_that.brief,_that.summary,_that.operation,_that.error,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatesHeader implements UpdatesHeader {
  const _UpdatesHeader({required this.reference, required this.brief, required this.summary, required this.operation, required this.error, required this.details});


@override final  UpdatesReadRef reference;
@override final  UpdatesBrief brief;
@override final  UpdateSummaryReadRef? summary;
@override final  UpdateOperationReadRef? operation;
@override final  UpdateErrorReadRef? error;
@override final  UpdateDetailsReadRef? details;

/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesHeaderCopyWith<_UpdatesHeader> get copyWith => __$UpdatesHeaderCopyWithImpl<_UpdatesHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesHeader&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.brief, brief) || other.brief == brief)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,brief,summary,operation,error,details);
}

@override
String toString() {
    return 'UpdatesHeader(reference: $reference, brief: $brief, summary: $summary, operation: $operation, error: $error, details: $details)';
}


}

/// @nodoc
abstract mixin class _$UpdatesHeaderCopyWith<$Res> implements $UpdatesHeaderCopyWith<$Res> {
  factory _$UpdatesHeaderCopyWith(_UpdatesHeader value, $Res Function(_UpdatesHeader) _then) = __$UpdatesHeaderCopyWithImpl;
@override @useResult
$Res call({
 UpdatesReadRef reference, UpdatesBrief brief, UpdateSummaryReadRef? summary, UpdateOperationReadRef? operation, UpdateErrorReadRef? error, UpdateDetailsReadRef? details
});


@override $UpdatesReadRefCopyWith<$Res> get reference;@override $UpdatesBriefCopyWith<$Res> get brief;@override $UpdateSummaryReadRefCopyWith<$Res>? get summary;@override $UpdateOperationReadRefCopyWith<$Res>? get operation;@override $UpdateErrorReadRefCopyWith<$Res>? get error;@override $UpdateDetailsReadRefCopyWith<$Res>? get details;

}
/// @nodoc
class __$UpdatesHeaderCopyWithImpl<$Res>
    implements _$UpdatesHeaderCopyWith<$Res> {
  __$UpdatesHeaderCopyWithImpl(this._self, this._then);

  final _UpdatesHeader _self;
  final $Res Function(_UpdatesHeader) _then;

/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? brief = null,Object? summary = freezed,Object? operation = freezed,Object? error = freezed,Object? details = freezed,}) {
  return _then(_UpdatesHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as UpdatesReadRef,brief: null == brief ? _self.brief : brief // ignore: cast_nullable_to_non_nullable
as UpdatesBrief,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummaryReadRef?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as UpdateOperationReadRef?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as UpdateErrorReadRef?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as UpdateDetailsReadRef?,
  ));
}

/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesReadRefCopyWith<$Res> get reference {

  return $UpdatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesBriefCopyWith<$Res> get brief {

  return $UpdatesBriefCopyWith<$Res>(_self.brief, (value) {
    return _then(_self.copyWith(brief: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadRefCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $UpdateSummaryReadRefCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateOperationReadRefCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $UpdateOperationReadRefCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateErrorReadRefCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $UpdateErrorReadRefCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of UpdatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadRefCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $UpdateDetailsReadRefCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

/// @nodoc
mixin _$UpdatesState {

 ProductProjection<UpdatesHeader> get projection; ReadValue<UpdatesValue, UpdatesReadRef>? get value;
/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesStateCopyWith<UpdatesState> get copyWith => _$UpdatesStateCopyWithImpl<UpdatesState>(this as UpdatesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as UpdatesState;
  return Object.hash(runtimeType,_this.projection,_this.value);
}



}

/// @nodoc
abstract mixin class $UpdatesStateCopyWith<$Res>  {
  factory $UpdatesStateCopyWith(UpdatesState value, $Res Function(UpdatesState) _then) = _$UpdatesStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<UpdatesHeader> projection, ReadValue<UpdatesValue, UpdatesReadRef>? value
});


$ProductProjectionCopyWith<UpdatesHeader, $Res> get projection;$ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>? get value;

}
/// @nodoc
class _$UpdatesStateCopyWithImpl<$Res>
    implements $UpdatesStateCopyWith<$Res> {
  _$UpdatesStateCopyWithImpl(this._self, this._then);

  final UpdatesState _self;
  final $Res Function(UpdatesState) _then;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? value = freezed,}) {
  return _then(UpdatesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<UpdatesHeader>,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<UpdatesValue, UpdatesReadRef>?,
  ));
}
/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<UpdatesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<UpdatesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatesState].
extension UpdatesStatePatterns on UpdatesState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatesState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatesState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatesState value)  $default,){
final _that = this;
switch (_that) {
case _UpdatesState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatesState value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatesState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<UpdatesHeader> projection,  ReadValue<UpdatesValue, UpdatesReadRef>? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatesState() when $default != null:
return $default(_that.projection,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<UpdatesHeader> projection,  ReadValue<UpdatesValue, UpdatesReadRef>? value)  $default,) {final _that = this;
switch (_that) {
case _UpdatesState():
return $default(_that.projection,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<UpdatesHeader> projection,  ReadValue<UpdatesValue, UpdatesReadRef>? value)?  $default,) {final _that = this;
switch (_that) {
case _UpdatesState() when $default != null:
return $default(_that.projection,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatesState implements UpdatesState {
  const _UpdatesState({required this.projection, required this.value});


@override final  ProductProjection<UpdatesHeader> projection;
@override final  ReadValue<UpdatesValue, UpdatesReadRef>? value;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesStateCopyWith<_UpdatesState> get copyWith => __$UpdatesStateCopyWithImpl<_UpdatesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,value);
}



}

/// @nodoc
abstract mixin class _$UpdatesStateCopyWith<$Res> implements $UpdatesStateCopyWith<$Res> {
  factory _$UpdatesStateCopyWith(_UpdatesState value, $Res Function(_UpdatesState) _then) = __$UpdatesStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<UpdatesHeader> projection, ReadValue<UpdatesValue, UpdatesReadRef>? value
});


@override $ProductProjectionCopyWith<UpdatesHeader, $Res> get projection;@override $ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>? get value;

}
/// @nodoc
class __$UpdatesStateCopyWithImpl<$Res>
    implements _$UpdatesStateCopyWith<$Res> {
  __$UpdatesStateCopyWithImpl(this._self, this._then);

  final _UpdatesState _self;
  final $Res Function(_UpdatesState) _then;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? value = freezed,}) {
  return _then(_UpdatesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<UpdatesHeader>,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<UpdatesValue, UpdatesReadRef>?,
  ));
}

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<UpdatesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<UpdatesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<UpdatesValue, UpdatesReadRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
