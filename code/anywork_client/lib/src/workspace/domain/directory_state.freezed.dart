// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'directory_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProjectDirectoryReadRef {

 int get entry; int get revision;
/// Create a copy of ProjectDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryReadRefCopyWith<ProjectDirectoryReadRef> get copyWith => _$ProjectDirectoryReadRefCopyWithImpl<ProjectDirectoryReadRef>(this as ProjectDirectoryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ProjectDirectoryReadRef;
  return 'ProjectDirectoryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryReadRefCopyWith<$Res>  {
  factory $ProjectDirectoryReadRefCopyWith(ProjectDirectoryReadRef value, $Res Function(ProjectDirectoryReadRef) _then) = _$ProjectDirectoryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ProjectDirectoryReadRefCopyWithImpl<$Res>
    implements $ProjectDirectoryReadRefCopyWith<$Res> {
  _$ProjectDirectoryReadRefCopyWithImpl(this._self, this._then);

  final ProjectDirectoryReadRef _self;
  final $Res Function(ProjectDirectoryReadRef) _then;

/// Create a copy of ProjectDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ProjectDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectDirectoryReadRef].
extension ProjectDirectoryReadRefPatterns on ProjectDirectoryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadRef() when $default != null:
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
case _ProjectDirectoryReadRef() when $default != null:
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
case _ProjectDirectoryReadRef():
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
case _ProjectDirectoryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryReadRef implements ProjectDirectoryReadRef {
  const _ProjectDirectoryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ProjectDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryReadRefCopyWith<_ProjectDirectoryReadRef> get copyWith => __$ProjectDirectoryReadRefCopyWithImpl<_ProjectDirectoryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ProjectDirectoryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ProjectDirectoryReadRefCopyWith<$Res> implements $ProjectDirectoryReadRefCopyWith<$Res> {
  factory _$ProjectDirectoryReadRefCopyWith(_ProjectDirectoryReadRef value, $Res Function(_ProjectDirectoryReadRef) _then) = __$ProjectDirectoryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ProjectDirectoryReadRefCopyWithImpl<$Res>
    implements _$ProjectDirectoryReadRefCopyWith<$Res> {
  __$ProjectDirectoryReadRefCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryReadRef _self;
  final $Res Function(_ProjectDirectoryReadRef) _then;

/// Create a copy of ProjectDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ProjectDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadDirectoryReadRef {

 int get entry; int get revision;
/// Create a copy of ThreadDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryReadRefCopyWith<ThreadDirectoryReadRef> get copyWith => _$ThreadDirectoryReadRefCopyWithImpl<ThreadDirectoryReadRef>(this as ThreadDirectoryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ThreadDirectoryReadRef;
  return 'ThreadDirectoryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryReadRefCopyWith<$Res>  {
  factory $ThreadDirectoryReadRefCopyWith(ThreadDirectoryReadRef value, $Res Function(ThreadDirectoryReadRef) _then) = _$ThreadDirectoryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ThreadDirectoryReadRefCopyWithImpl<$Res>
    implements $ThreadDirectoryReadRefCopyWith<$Res> {
  _$ThreadDirectoryReadRefCopyWithImpl(this._self, this._then);

  final ThreadDirectoryReadRef _self;
  final $Res Function(ThreadDirectoryReadRef) _then;

/// Create a copy of ThreadDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ThreadDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadDirectoryReadRef].
extension ThreadDirectoryReadRefPatterns on ThreadDirectoryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadRef() when $default != null:
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
case _ThreadDirectoryReadRef() when $default != null:
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
case _ThreadDirectoryReadRef():
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
case _ThreadDirectoryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryReadRef implements ThreadDirectoryReadRef {
  const _ThreadDirectoryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ThreadDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryReadRefCopyWith<_ThreadDirectoryReadRef> get copyWith => __$ThreadDirectoryReadRefCopyWithImpl<_ThreadDirectoryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ThreadDirectoryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ThreadDirectoryReadRefCopyWith<$Res> implements $ThreadDirectoryReadRefCopyWith<$Res> {
  factory _$ThreadDirectoryReadRefCopyWith(_ThreadDirectoryReadRef value, $Res Function(_ThreadDirectoryReadRef) _then) = __$ThreadDirectoryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ThreadDirectoryReadRefCopyWithImpl<$Res>
    implements _$ThreadDirectoryReadRefCopyWith<$Res> {
  __$ThreadDirectoryReadRefCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryReadRef _self;
  final $Res Function(_ThreadDirectoryReadRef) _then;

/// Create a copy of ThreadDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ThreadDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AgentDirectoryReadRef {

 int get entry; int get revision;
/// Create a copy of AgentDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryReadRefCopyWith<AgentDirectoryReadRef> get copyWith => _$AgentDirectoryReadRefCopyWithImpl<AgentDirectoryReadRef>(this as AgentDirectoryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as AgentDirectoryReadRef;
  return 'AgentDirectoryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryReadRefCopyWith<$Res>  {
  factory $AgentDirectoryReadRefCopyWith(AgentDirectoryReadRef value, $Res Function(AgentDirectoryReadRef) _then) = _$AgentDirectoryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$AgentDirectoryReadRefCopyWithImpl<$Res>
    implements $AgentDirectoryReadRefCopyWith<$Res> {
  _$AgentDirectoryReadRefCopyWithImpl(this._self, this._then);

  final AgentDirectoryReadRef _self;
  final $Res Function(AgentDirectoryReadRef) _then;

/// Create a copy of AgentDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(AgentDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentDirectoryReadRef].
extension AgentDirectoryReadRefPatterns on AgentDirectoryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadRef() when $default != null:
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
case _AgentDirectoryReadRef() when $default != null:
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
case _AgentDirectoryReadRef():
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
case _AgentDirectoryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryReadRef implements AgentDirectoryReadRef {
  const _AgentDirectoryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of AgentDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryReadRefCopyWith<_AgentDirectoryReadRef> get copyWith => __$AgentDirectoryReadRefCopyWithImpl<_AgentDirectoryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'AgentDirectoryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$AgentDirectoryReadRefCopyWith<$Res> implements $AgentDirectoryReadRefCopyWith<$Res> {
  factory _$AgentDirectoryReadRefCopyWith(_AgentDirectoryReadRef value, $Res Function(_AgentDirectoryReadRef) _then) = __$AgentDirectoryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$AgentDirectoryReadRefCopyWithImpl<$Res>
    implements _$AgentDirectoryReadRefCopyWith<$Res> {
  __$AgentDirectoryReadRefCopyWithImpl(this._self, this._then);

  final _AgentDirectoryReadRef _self;
  final $Res Function(_AgentDirectoryReadRef) _then;

/// Create a copy of AgentDirectoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_AgentDirectoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProjectDirectoryReadTarget {

 ProductReadOrigin get origin; ProjectDirectoryReadRef get reference;
/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryReadTargetCopyWith<ProjectDirectoryReadTarget> get copyWith => _$ProjectDirectoryReadTargetCopyWithImpl<ProjectDirectoryReadTarget>(this as ProjectDirectoryReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as ProjectDirectoryReadTarget;
  return 'ProjectDirectoryReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryReadTargetCopyWith<$Res>  {
  factory $ProjectDirectoryReadTargetCopyWith(ProjectDirectoryReadTarget value, $Res Function(ProjectDirectoryReadTarget) _then) = _$ProjectDirectoryReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ProjectDirectoryReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$ProjectDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ProjectDirectoryReadTargetCopyWithImpl<$Res>
    implements $ProjectDirectoryReadTargetCopyWith<$Res> {
  _$ProjectDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final ProjectDirectoryReadTarget _self;
  final $Res Function(ProjectDirectoryReadTarget) _then;

/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(ProjectDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryReadRef,
  ));
}
/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryReadRefCopyWith<$Res> get reference {

  return $ProjectDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryReadTarget].
extension ProjectDirectoryReadTargetPatterns on ProjectDirectoryReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ProjectDirectoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ProjectDirectoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ProjectDirectoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryReadTarget implements ProjectDirectoryReadTarget {
  const _ProjectDirectoryReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  ProjectDirectoryReadRef reference;

/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryReadTargetCopyWith<_ProjectDirectoryReadTarget> get copyWith => __$ProjectDirectoryReadTargetCopyWithImpl<_ProjectDirectoryReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'ProjectDirectoryReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ProjectDirectoryReadTargetCopyWith<$Res> implements $ProjectDirectoryReadTargetCopyWith<$Res> {
  factory _$ProjectDirectoryReadTargetCopyWith(_ProjectDirectoryReadTarget value, $Res Function(_ProjectDirectoryReadTarget) _then) = __$ProjectDirectoryReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ProjectDirectoryReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ProjectDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ProjectDirectoryReadTargetCopyWithImpl<$Res>
    implements _$ProjectDirectoryReadTargetCopyWith<$Res> {
  __$ProjectDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryReadTarget _self;
  final $Res Function(_ProjectDirectoryReadTarget) _then;

/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_ProjectDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryReadRef,
  ));
}

/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ProjectDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryReadRefCopyWith<$Res> get reference {

  return $ProjectDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryReadTarget {

 ProductReadOrigin get origin; ThreadDirectoryReadRef get reference;
/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryReadTargetCopyWith<ThreadDirectoryReadTarget> get copyWith => _$ThreadDirectoryReadTargetCopyWithImpl<ThreadDirectoryReadTarget>(this as ThreadDirectoryReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as ThreadDirectoryReadTarget;
  return 'ThreadDirectoryReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryReadTargetCopyWith<$Res>  {
  factory $ThreadDirectoryReadTargetCopyWith(ThreadDirectoryReadTarget value, $Res Function(ThreadDirectoryReadTarget) _then) = _$ThreadDirectoryReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ThreadDirectoryReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$ThreadDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ThreadDirectoryReadTargetCopyWithImpl<$Res>
    implements $ThreadDirectoryReadTargetCopyWith<$Res> {
  _$ThreadDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final ThreadDirectoryReadTarget _self;
  final $Res Function(ThreadDirectoryReadTarget) _then;

/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(ThreadDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryReadRef,
  ));
}
/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryReadRefCopyWith<$Res> get reference {

  return $ThreadDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryReadTarget].
extension ThreadDirectoryReadTargetPatterns on ThreadDirectoryReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ThreadDirectoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ThreadDirectoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ThreadDirectoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryReadTarget implements ThreadDirectoryReadTarget {
  const _ThreadDirectoryReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  ThreadDirectoryReadRef reference;

/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryReadTargetCopyWith<_ThreadDirectoryReadTarget> get copyWith => __$ThreadDirectoryReadTargetCopyWithImpl<_ThreadDirectoryReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'ThreadDirectoryReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ThreadDirectoryReadTargetCopyWith<$Res> implements $ThreadDirectoryReadTargetCopyWith<$Res> {
  factory _$ThreadDirectoryReadTargetCopyWith(_ThreadDirectoryReadTarget value, $Res Function(_ThreadDirectoryReadTarget) _then) = __$ThreadDirectoryReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ThreadDirectoryReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ThreadDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ThreadDirectoryReadTargetCopyWithImpl<$Res>
    implements _$ThreadDirectoryReadTargetCopyWith<$Res> {
  __$ThreadDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryReadTarget _self;
  final $Res Function(_ThreadDirectoryReadTarget) _then;

/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_ThreadDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryReadRef,
  ));
}

/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ThreadDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryReadRefCopyWith<$Res> get reference {

  return $ThreadDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryReadTarget {

 ProductReadOrigin get origin; AgentDirectoryReadRef get reference;
/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryReadTargetCopyWith<AgentDirectoryReadTarget> get copyWith => _$AgentDirectoryReadTargetCopyWithImpl<AgentDirectoryReadTarget>(this as AgentDirectoryReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as AgentDirectoryReadTarget;
  return 'AgentDirectoryReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryReadTargetCopyWith<$Res>  {
  factory $AgentDirectoryReadTargetCopyWith(AgentDirectoryReadTarget value, $Res Function(AgentDirectoryReadTarget) _then) = _$AgentDirectoryReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, AgentDirectoryReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$AgentDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AgentDirectoryReadTargetCopyWithImpl<$Res>
    implements $AgentDirectoryReadTargetCopyWith<$Res> {
  _$AgentDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final AgentDirectoryReadTarget _self;
  final $Res Function(AgentDirectoryReadTarget) _then;

/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(AgentDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentDirectoryReadRef,
  ));
}
/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryReadRefCopyWith<$Res> get reference {

  return $AgentDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryReadTarget].
extension AgentDirectoryReadTargetPatterns on AgentDirectoryReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AgentDirectoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AgentDirectoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  AgentDirectoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryReadTarget implements AgentDirectoryReadTarget {
  const _AgentDirectoryReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  AgentDirectoryReadRef reference;

/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryReadTargetCopyWith<_AgentDirectoryReadTarget> get copyWith => __$AgentDirectoryReadTargetCopyWithImpl<_AgentDirectoryReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'AgentDirectoryReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AgentDirectoryReadTargetCopyWith<$Res> implements $AgentDirectoryReadTargetCopyWith<$Res> {
  factory _$AgentDirectoryReadTargetCopyWith(_AgentDirectoryReadTarget value, $Res Function(_AgentDirectoryReadTarget) _then) = __$AgentDirectoryReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, AgentDirectoryReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $AgentDirectoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AgentDirectoryReadTargetCopyWithImpl<$Res>
    implements _$AgentDirectoryReadTargetCopyWith<$Res> {
  __$AgentDirectoryReadTargetCopyWithImpl(this._self, this._then);

  final _AgentDirectoryReadTarget _self;
  final $Res Function(_AgentDirectoryReadTarget) _then;

/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_AgentDirectoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentDirectoryReadRef,
  ));
}

/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AgentDirectoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryReadRefCopyWith<$Res> get reference {

  return $AgentDirectoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ProjectDirectoryHeader {

 ObservedHeader get source; ProjectDirectoryReadRef? get reference;
/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryHeaderCopyWith<ProjectDirectoryHeader> get copyWith => _$ProjectDirectoryHeaderCopyWithImpl<ProjectDirectoryHeader>(this as ProjectDirectoryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as ProjectDirectoryHeader;
  return 'ProjectDirectoryHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryHeaderCopyWith<$Res>  {
  factory $ProjectDirectoryHeaderCopyWith(ProjectDirectoryHeader value, $Res Function(ProjectDirectoryHeader) _then) = _$ProjectDirectoryHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, ProjectDirectoryReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$ProjectDirectoryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$ProjectDirectoryHeaderCopyWithImpl<$Res>
    implements $ProjectDirectoryHeaderCopyWith<$Res> {
  _$ProjectDirectoryHeaderCopyWithImpl(this._self, this._then);

  final ProjectDirectoryHeader _self;
  final $Res Function(ProjectDirectoryHeader) _then;

/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(ProjectDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryReadRef?,
  ));
}
/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ProjectDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryHeader].
extension ProjectDirectoryHeaderPatterns on ProjectDirectoryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryHeader value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  ProjectDirectoryReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  ProjectDirectoryReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  ProjectDirectoryReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryHeader implements ProjectDirectoryHeader {
  const _ProjectDirectoryHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  ProjectDirectoryReadRef? reference;

/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryHeaderCopyWith<_ProjectDirectoryHeader> get copyWith => __$ProjectDirectoryHeaderCopyWithImpl<_ProjectDirectoryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'ProjectDirectoryHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ProjectDirectoryHeaderCopyWith<$Res> implements $ProjectDirectoryHeaderCopyWith<$Res> {
  factory _$ProjectDirectoryHeaderCopyWith(_ProjectDirectoryHeader value, $Res Function(_ProjectDirectoryHeader) _then) = __$ProjectDirectoryHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, ProjectDirectoryReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $ProjectDirectoryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$ProjectDirectoryHeaderCopyWithImpl<$Res>
    implements _$ProjectDirectoryHeaderCopyWith<$Res> {
  __$ProjectDirectoryHeaderCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryHeader _self;
  final $Res Function(_ProjectDirectoryHeader) _then;

/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_ProjectDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryReadRef?,
  ));
}

/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ProjectDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ProjectDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryHeader {

 ObservedHeader get source; ThreadDirectoryReadRef? get reference; int? get directoryRevision; int? get searchProjectRevision; bool? get hasMore; ReadText? get nextCursor;
/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryHeaderCopyWith<ThreadDirectoryHeader> get copyWith => _$ThreadDirectoryHeaderCopyWithImpl<ThreadDirectoryHeader>(this as ThreadDirectoryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.directoryRevision, _this.directoryRevision) || other.directoryRevision == _this.directoryRevision)&&(identical(other.searchProjectRevision, _this.searchProjectRevision) || other.searchProjectRevision == _this.searchProjectRevision)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryHeader;
  return Object.hash(runtimeType,_this.source,_this.reference,_this.directoryRevision,_this.searchProjectRevision,_this.hasMore,_this.nextCursor);
}

@override
String toString() {
  final _this = this as ThreadDirectoryHeader;
  return 'ThreadDirectoryHeader(source: ${_this.source}, reference: ${_this.reference}, directoryRevision: ${_this.directoryRevision}, searchProjectRevision: ${_this.searchProjectRevision}, hasMore: ${_this.hasMore}, nextCursor: ${_this.nextCursor})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryHeaderCopyWith<$Res>  {
  factory $ThreadDirectoryHeaderCopyWith(ThreadDirectoryHeader value, $Res Function(ThreadDirectoryHeader) _then) = _$ThreadDirectoryHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, ThreadDirectoryReadRef? reference, int? directoryRevision, int? searchProjectRevision, bool? hasMore, ReadText? nextCursor
});


$ObservedHeaderCopyWith<$Res> get source;$ThreadDirectoryReadRefCopyWith<$Res>? get reference;$ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class _$ThreadDirectoryHeaderCopyWithImpl<$Res>
    implements $ThreadDirectoryHeaderCopyWith<$Res> {
  _$ThreadDirectoryHeaderCopyWithImpl(this._self, this._then);

  final ThreadDirectoryHeader _self;
  final $Res Function(ThreadDirectoryHeader) _then;

/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,Object? directoryRevision = freezed,Object? searchProjectRevision = freezed,Object? hasMore = freezed,Object? nextCursor = freezed,}) {
  return _then(ThreadDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryReadRef?,directoryRevision: freezed == directoryRevision ? _self.directoryRevision : directoryRevision // ignore: cast_nullable_to_non_nullable
as int?,searchProjectRevision: freezed == searchProjectRevision ? _self.searchProjectRevision : searchProjectRevision // ignore: cast_nullable_to_non_nullable
as int?,hasMore: freezed == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool?,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ThreadDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryHeader].
extension ThreadDirectoryHeaderPatterns on ThreadDirectoryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryHeader value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  ThreadDirectoryReadRef? reference,  int? directoryRevision,  int? searchProjectRevision,  bool? hasMore,  ReadText? nextCursor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryHeader() when $default != null:
return $default(_that.source,_that.reference,_that.directoryRevision,_that.searchProjectRevision,_that.hasMore,_that.nextCursor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  ThreadDirectoryReadRef? reference,  int? directoryRevision,  int? searchProjectRevision,  bool? hasMore,  ReadText? nextCursor)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryHeader():
return $default(_that.source,_that.reference,_that.directoryRevision,_that.searchProjectRevision,_that.hasMore,_that.nextCursor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  ThreadDirectoryReadRef? reference,  int? directoryRevision,  int? searchProjectRevision,  bool? hasMore,  ReadText? nextCursor)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryHeader() when $default != null:
return $default(_that.source,_that.reference,_that.directoryRevision,_that.searchProjectRevision,_that.hasMore,_that.nextCursor);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryHeader implements ThreadDirectoryHeader {
  const _ThreadDirectoryHeader({required this.source, required this.reference, required this.directoryRevision, required this.searchProjectRevision, required this.hasMore, required this.nextCursor});


@override final  ObservedHeader source;
@override final  ThreadDirectoryReadRef? reference;
@override final  int? directoryRevision;
@override final  int? searchProjectRevision;
@override final  bool? hasMore;
@override final  ReadText? nextCursor;

/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryHeaderCopyWith<_ThreadDirectoryHeader> get copyWith => __$ThreadDirectoryHeaderCopyWithImpl<_ThreadDirectoryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.directoryRevision, directoryRevision) || other.directoryRevision == directoryRevision)&&(identical(other.searchProjectRevision, searchProjectRevision) || other.searchProjectRevision == searchProjectRevision)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference,directoryRevision,searchProjectRevision,hasMore,nextCursor);
}

@override
String toString() {
    return 'ThreadDirectoryHeader(source: $source, reference: $reference, directoryRevision: $directoryRevision, searchProjectRevision: $searchProjectRevision, hasMore: $hasMore, nextCursor: $nextCursor)';
}


}

/// @nodoc
abstract mixin class _$ThreadDirectoryHeaderCopyWith<$Res> implements $ThreadDirectoryHeaderCopyWith<$Res> {
  factory _$ThreadDirectoryHeaderCopyWith(_ThreadDirectoryHeader value, $Res Function(_ThreadDirectoryHeader) _then) = __$ThreadDirectoryHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, ThreadDirectoryReadRef? reference, int? directoryRevision, int? searchProjectRevision, bool? hasMore, ReadText? nextCursor
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $ThreadDirectoryReadRefCopyWith<$Res>? get reference;@override $ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class __$ThreadDirectoryHeaderCopyWithImpl<$Res>
    implements _$ThreadDirectoryHeaderCopyWith<$Res> {
  __$ThreadDirectoryHeaderCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryHeader _self;
  final $Res Function(_ThreadDirectoryHeader) _then;

/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,Object? directoryRevision = freezed,Object? searchProjectRevision = freezed,Object? hasMore = freezed,Object? nextCursor = freezed,}) {
  return _then(_ThreadDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryReadRef?,directoryRevision: freezed == directoryRevision ? _self.directoryRevision : directoryRevision // ignore: cast_nullable_to_non_nullable
as int?,searchProjectRevision: freezed == searchProjectRevision ? _self.searchProjectRevision : searchProjectRevision // ignore: cast_nullable_to_non_nullable
as int?,hasMore: freezed == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool?,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ThreadDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ThreadDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryHeader {

 ObservedHeader get source; AgentDirectoryReadRef? get reference;
/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryHeaderCopyWith<AgentDirectoryHeader> get copyWith => _$AgentDirectoryHeaderCopyWithImpl<AgentDirectoryHeader>(this as AgentDirectoryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as AgentDirectoryHeader;
  return 'AgentDirectoryHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryHeaderCopyWith<$Res>  {
  factory $AgentDirectoryHeaderCopyWith(AgentDirectoryHeader value, $Res Function(AgentDirectoryHeader) _then) = _$AgentDirectoryHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, AgentDirectoryReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$AgentDirectoryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$AgentDirectoryHeaderCopyWithImpl<$Res>
    implements $AgentDirectoryHeaderCopyWith<$Res> {
  _$AgentDirectoryHeaderCopyWithImpl(this._self, this._then);

  final AgentDirectoryHeader _self;
  final $Res Function(AgentDirectoryHeader) _then;

/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(AgentDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentDirectoryReadRef?,
  ));
}
/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AgentDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryHeader].
extension AgentDirectoryHeaderPatterns on AgentDirectoryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryHeader value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  AgentDirectoryReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  AgentDirectoryReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  AgentDirectoryReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryHeader implements AgentDirectoryHeader {
  const _AgentDirectoryHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  AgentDirectoryReadRef? reference;

/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryHeaderCopyWith<_AgentDirectoryHeader> get copyWith => __$AgentDirectoryHeaderCopyWithImpl<_AgentDirectoryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'AgentDirectoryHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AgentDirectoryHeaderCopyWith<$Res> implements $AgentDirectoryHeaderCopyWith<$Res> {
  factory _$AgentDirectoryHeaderCopyWith(_AgentDirectoryHeader value, $Res Function(_AgentDirectoryHeader) _then) = __$AgentDirectoryHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, AgentDirectoryReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $AgentDirectoryReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$AgentDirectoryHeaderCopyWithImpl<$Res>
    implements _$AgentDirectoryHeaderCopyWith<$Res> {
  __$AgentDirectoryHeaderCopyWithImpl(this._self, this._then);

  final _AgentDirectoryHeader _self;
  final $Res Function(_AgentDirectoryHeader) _then;

/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_AgentDirectoryHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentDirectoryReadRef?,
  ));
}

/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentDirectoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AgentDirectoryReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ProjectDirectoryState {

 ProductProjection<ProjectDirectoryHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<ProjectRecord> get projects;
/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryStateCopyWith<ProjectDirectoryState> get copyWith => _$ProjectDirectoryStateCopyWithImpl<ProjectDirectoryState>(this as ProjectDirectoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.projects, _this.projects) || other.projects == _this.projects));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.projects);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryStateCopyWith<$Res>  {
  factory $ProjectDirectoryStateCopyWith(ProjectDirectoryState value, $Res Function(ProjectDirectoryState) _then) = _$ProjectDirectoryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ProjectDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<ProjectRecord> projects
});


$ProductProjectionCopyWith<ProjectDirectoryHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<ProjectRecord, $Res> get projects;

}
/// @nodoc
class _$ProjectDirectoryStateCopyWithImpl<$Res>
    implements $ProjectDirectoryStateCopyWith<$Res> {
  _$ProjectDirectoryStateCopyWithImpl(this._self, this._then);

  final ProjectDirectoryState _self;
  final $Res Function(ProjectDirectoryState) _then;

/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? projects = null,}) {
  return _then(ProjectDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ProjectDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ProjectRecord>,
  ));
}
/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ProjectDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ProjectDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ProjectDirectoryState
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
}/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ProjectRecord, $Res> get projects {

  return $CollectionMirrorCopyWith<ProjectRecord, $Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryState].
extension ProjectDirectoryStatePatterns on ProjectDirectoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryState value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryState value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<ProjectDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<ProjectRecord> projects)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.projects);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<ProjectDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<ProjectRecord> projects)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryState():
return $default(_that.projection,_that.sourceStatus,_that.projects);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<ProjectDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<ProjectRecord> projects)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.projects);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryState implements ProjectDirectoryState {
  const _ProjectDirectoryState({required this.projection, required this.sourceStatus, required this.projects});


@override final  ProductProjection<ProjectDirectoryHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<ProjectRecord> projects;

/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryStateCopyWith<_ProjectDirectoryState> get copyWith => __$ProjectDirectoryStateCopyWithImpl<_ProjectDirectoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.projects, projects) || other.projects == projects));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,projects);
}



}

/// @nodoc
abstract mixin class _$ProjectDirectoryStateCopyWith<$Res> implements $ProjectDirectoryStateCopyWith<$Res> {
  factory _$ProjectDirectoryStateCopyWith(_ProjectDirectoryState value, $Res Function(_ProjectDirectoryState) _then) = __$ProjectDirectoryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<ProjectDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<ProjectRecord> projects
});


@override $ProductProjectionCopyWith<ProjectDirectoryHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<ProjectRecord, $Res> get projects;

}
/// @nodoc
class __$ProjectDirectoryStateCopyWithImpl<$Res>
    implements _$ProjectDirectoryStateCopyWith<$Res> {
  __$ProjectDirectoryStateCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryState _self;
  final $Res Function(_ProjectDirectoryState) _then;

/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? projects = null,}) {
  return _then(_ProjectDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ProjectDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ProjectRecord>,
  ));
}

/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ProjectDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ProjectDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ProjectDirectoryState
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
}/// Create a copy of ProjectDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ProjectRecord, $Res> get projects {

  return $CollectionMirrorCopyWith<ProjectRecord, $Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryState {

 ProductProjection<ThreadDirectoryHeader> get projection; ThreadDirectoryScope get scope; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<WorkspaceThreadRecord> get threads;
/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryStateCopyWith<ThreadDirectoryState> get copyWith => _$ThreadDirectoryStateCopyWithImpl<ThreadDirectoryState>(this as ThreadDirectoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.threads, _this.threads) || other.threads == _this.threads));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryState;
  return Object.hash(runtimeType,_this.projection,_this.scope,_this.sourceStatus,_this.threads);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryStateCopyWith<$Res>  {
  factory $ThreadDirectoryStateCopyWith(ThreadDirectoryState value, $Res Function(ThreadDirectoryState) _then) = _$ThreadDirectoryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ThreadDirectoryHeader> projection, ThreadDirectoryScope scope, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<WorkspaceThreadRecord> threads
});


$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection;$ThreadDirectoryScopeCopyWith<$Res> get scope;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res> get threads;

}
/// @nodoc
class _$ThreadDirectoryStateCopyWithImpl<$Res>
    implements $ThreadDirectoryStateCopyWith<$Res> {
  _$ThreadDirectoryStateCopyWithImpl(this._self, this._then);

  final ThreadDirectoryState _self;
  final $Res Function(ThreadDirectoryState) _then;

/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? scope = null,Object? sourceStatus = freezed,Object? threads = null,}) {
  return _then(ThreadDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ThreadDirectoryHeader>,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryScope,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as CollectionMirror<WorkspaceThreadRecord>,
  ));
}
/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryScopeCopyWith<$Res> get scope {

  return $ThreadDirectoryScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ThreadDirectoryState
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
}/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res> get threads {

  return $CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryState].
extension ThreadDirectoryStatePatterns on ThreadDirectoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<ThreadDirectoryHeader> projection,  ThreadDirectoryScope scope,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<WorkspaceThreadRecord> threads)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryState() when $default != null:
return $default(_that.projection,_that.scope,_that.sourceStatus,_that.threads);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<ThreadDirectoryHeader> projection,  ThreadDirectoryScope scope,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<WorkspaceThreadRecord> threads)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryState():
return $default(_that.projection,_that.scope,_that.sourceStatus,_that.threads);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<ThreadDirectoryHeader> projection,  ThreadDirectoryScope scope,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<WorkspaceThreadRecord> threads)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryState() when $default != null:
return $default(_that.projection,_that.scope,_that.sourceStatus,_that.threads);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryState implements ThreadDirectoryState {
  const _ThreadDirectoryState({required this.projection, required this.scope, required this.sourceStatus, required this.threads});


@override final  ProductProjection<ThreadDirectoryHeader> projection;
@override final  ThreadDirectoryScope scope;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<WorkspaceThreadRecord> threads;

/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryStateCopyWith<_ThreadDirectoryState> get copyWith => __$ThreadDirectoryStateCopyWithImpl<_ThreadDirectoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.threads, threads) || other.threads == threads));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,scope,sourceStatus,threads);
}



}

/// @nodoc
abstract mixin class _$ThreadDirectoryStateCopyWith<$Res> implements $ThreadDirectoryStateCopyWith<$Res> {
  factory _$ThreadDirectoryStateCopyWith(_ThreadDirectoryState value, $Res Function(_ThreadDirectoryState) _then) = __$ThreadDirectoryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<ThreadDirectoryHeader> projection, ThreadDirectoryScope scope, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<WorkspaceThreadRecord> threads
});


@override $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection;@override $ThreadDirectoryScopeCopyWith<$Res> get scope;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res> get threads;

}
/// @nodoc
class __$ThreadDirectoryStateCopyWithImpl<$Res>
    implements _$ThreadDirectoryStateCopyWith<$Res> {
  __$ThreadDirectoryStateCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryState _self;
  final $Res Function(_ThreadDirectoryState) _then;

/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? scope = null,Object? sourceStatus = freezed,Object? threads = null,}) {
  return _then(_ThreadDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ThreadDirectoryHeader>,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryScope,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as CollectionMirror<WorkspaceThreadRecord>,
  ));
}

/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryScopeCopyWith<$Res> get scope {

  return $ThreadDirectoryScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ThreadDirectoryState
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
}/// Create a copy of ThreadDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res> get threads {

  return $CollectionMirrorCopyWith<WorkspaceThreadRecord, $Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryState {

 ProductProjection<AgentDirectoryHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<AgentDirectoryEntry> get agents;
/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryStateCopyWith<AgentDirectoryState> get copyWith => _$AgentDirectoryStateCopyWithImpl<AgentDirectoryState>(this as AgentDirectoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.agents, _this.agents) || other.agents == _this.agents));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.agents);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryStateCopyWith<$Res>  {
  factory $AgentDirectoryStateCopyWith(AgentDirectoryState value, $Res Function(AgentDirectoryState) _then) = _$AgentDirectoryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<AgentDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AgentDirectoryEntry> agents
});


$ProductProjectionCopyWith<AgentDirectoryHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<AgentDirectoryEntry, $Res> get agents;

}
/// @nodoc
class _$AgentDirectoryStateCopyWithImpl<$Res>
    implements $AgentDirectoryStateCopyWith<$Res> {
  _$AgentDirectoryStateCopyWithImpl(this._self, this._then);

  final AgentDirectoryState _self;
  final $Res Function(AgentDirectoryState) _then;

/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? agents = null,}) {
  return _then(AgentDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AgentDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AgentDirectoryEntry>,
  ));
}
/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AgentDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AgentDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AgentDirectoryState
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
}/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AgentDirectoryEntry, $Res> get agents {

  return $CollectionMirrorCopyWith<AgentDirectoryEntry, $Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryState].
extension AgentDirectoryStatePatterns on AgentDirectoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryState value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryState value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<AgentDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AgentDirectoryEntry> agents)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.agents);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<AgentDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AgentDirectoryEntry> agents)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryState():
return $default(_that.projection,_that.sourceStatus,_that.agents);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<AgentDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AgentDirectoryEntry> agents)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.agents);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryState implements AgentDirectoryState {
  const _AgentDirectoryState({required this.projection, required this.sourceStatus, required this.agents});


@override final  ProductProjection<AgentDirectoryHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<AgentDirectoryEntry> agents;

/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryStateCopyWith<_AgentDirectoryState> get copyWith => __$AgentDirectoryStateCopyWithImpl<_AgentDirectoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.agents, agents) || other.agents == agents));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,agents);
}



}

/// @nodoc
abstract mixin class _$AgentDirectoryStateCopyWith<$Res> implements $AgentDirectoryStateCopyWith<$Res> {
  factory _$AgentDirectoryStateCopyWith(_AgentDirectoryState value, $Res Function(_AgentDirectoryState) _then) = __$AgentDirectoryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<AgentDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AgentDirectoryEntry> agents
});


@override $ProductProjectionCopyWith<AgentDirectoryHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<AgentDirectoryEntry, $Res> get agents;

}
/// @nodoc
class __$AgentDirectoryStateCopyWithImpl<$Res>
    implements _$AgentDirectoryStateCopyWith<$Res> {
  __$AgentDirectoryStateCopyWithImpl(this._self, this._then);

  final _AgentDirectoryState _self;
  final $Res Function(_AgentDirectoryState) _then;

/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? agents = null,}) {
  return _then(_AgentDirectoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AgentDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AgentDirectoryEntry>,
  ));
}

/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AgentDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AgentDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AgentDirectoryState
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
}/// Create a copy of AgentDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AgentDirectoryEntry, $Res> get agents {

  return $CollectionMirrorCopyWith<AgentDirectoryEntry, $Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}
}

/// @nodoc
mixin _$ThreadMetadataState {

 ProductProjection<ThreadDirectoryHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; ReadValue<WorkspaceThreadRecord, ProductEntityRef>? get value; StudioFailure? get readError;
/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<ThreadMetadataState> get copyWith => _$ThreadMetadataStateCopyWithImpl<ThreadMetadataState>(this as ThreadMetadataState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMetadataState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetadataState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.readError, _this.readError) || other.readError == _this.readError));
}


@override
int get hashCode {
  final _this = this as ThreadMetadataState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.value,_this.readError);
}



}

/// @nodoc
abstract mixin class $ThreadMetadataStateCopyWith<$Res>  {
  factory $ThreadMetadataStateCopyWith(ThreadMetadataState value, $Res Function(ThreadMetadataState) _then) = _$ThreadMetadataStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ThreadDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value, StudioFailure? readError
});


$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>? get value;$StudioFailureCopyWith<$Res>? get readError;

}
/// @nodoc
class _$ThreadMetadataStateCopyWithImpl<$Res>
    implements $ThreadMetadataStateCopyWith<$Res> {
  _$ThreadMetadataStateCopyWithImpl(this._self, this._then);

  final ThreadMetadataState _self;
  final $Res Function(ThreadMetadataState) _then;

/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? value = freezed,Object? readError = freezed,}) {
  return _then(ThreadMetadataState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ThreadDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<WorkspaceThreadRecord, ProductEntityRef>?,readError: freezed == readError ? _self.readError : readError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ThreadMetadataState
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
}/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get readError {
    if (_self.readError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.readError!, (value) {
    return _then(_self.copyWith(readError: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadMetadataState].
extension ThreadMetadataStatePatterns on ThreadMetadataState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadMetadataState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadMetadataState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadMetadataState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadMetadataState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadMetadataState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadMetadataState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<ThreadDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value,  StudioFailure? readError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadMetadataState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.value,_that.readError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<ThreadDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value,  StudioFailure? readError)  $default,) {final _that = this;
switch (_that) {
case _ThreadMetadataState():
return $default(_that.projection,_that.sourceStatus,_that.value,_that.readError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<ThreadDirectoryHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value,  StudioFailure? readError)?  $default,) {final _that = this;
switch (_that) {
case _ThreadMetadataState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.value,_that.readError);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadMetadataState implements ThreadMetadataState {
  const _ThreadMetadataState({required this.projection, required this.sourceStatus, required this.value, this.readError});


@override final  ProductProjection<ThreadDirectoryHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value;
@override final  StudioFailure? readError;

/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadMetadataStateCopyWith<_ThreadMetadataState> get copyWith => __$ThreadMetadataStateCopyWithImpl<_ThreadMetadataState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadMetadataState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.value, value) || other.value == value)&&(identical(other.readError, readError) || other.readError == readError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,value,readError);
}



}

/// @nodoc
abstract mixin class _$ThreadMetadataStateCopyWith<$Res> implements $ThreadMetadataStateCopyWith<$Res> {
  factory _$ThreadMetadataStateCopyWith(_ThreadMetadataState value, $Res Function(_ThreadMetadataState) _then) = __$ThreadMetadataStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<ThreadDirectoryHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value, StudioFailure? readError
});


@override $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>? get value;@override $StudioFailureCopyWith<$Res>? get readError;

}
/// @nodoc
class __$ThreadMetadataStateCopyWithImpl<$Res>
    implements _$ThreadMetadataStateCopyWith<$Res> {
  __$ThreadMetadataStateCopyWithImpl(this._self, this._then);

  final _ThreadMetadataState _self;
  final $Res Function(_ThreadMetadataState) _then;

/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? value = freezed,Object? readError = freezed,}) {
  return _then(_ThreadMetadataState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ThreadDirectoryHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<WorkspaceThreadRecord, ProductEntityRef>?,readError: freezed == readError ? _self.readError : readError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ThreadDirectoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ThreadDirectoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ThreadMetadataState
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
}/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<WorkspaceThreadRecord, ProductEntityRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}/// Create a copy of ThreadMetadataState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get readError {
    if (_self.readError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.readError!, (value) {
    return _then(_self.copyWith(readError: value));
  });
}
}

// dart format on
