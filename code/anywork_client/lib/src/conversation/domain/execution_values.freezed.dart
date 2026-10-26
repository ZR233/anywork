// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'execution_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InteractionBrief {

 InteractionReadRef get reference; int get revision; InteractionKind get kind; InteractionStatus get status; int get createdAt; int get updatedAt;
/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionBriefCopyWith<InteractionBrief> get copyWith => _$InteractionBriefCopyWithImpl<InteractionBrief>(this as InteractionBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as InteractionBrief;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.kind,_this.status,_this.createdAt,_this.updatedAt);
}

@override
String toString() {
  final _this = this as InteractionBrief;
  return 'InteractionBrief(reference: ${_this.reference}, revision: ${_this.revision}, kind: ${_this.kind}, status: ${_this.status}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $InteractionBriefCopyWith<$Res>  {
  factory $InteractionBriefCopyWith(InteractionBrief value, $Res Function(InteractionBrief) _then) = _$InteractionBriefCopyWithImpl;
@useResult
$Res call({
 InteractionReadRef reference, int revision, InteractionKind kind, InteractionStatus status, int createdAt, int updatedAt
});


$InteractionReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$InteractionBriefCopyWithImpl<$Res>
    implements $InteractionBriefCopyWith<$Res> {
  _$InteractionBriefCopyWithImpl(this._self, this._then);

  final InteractionBrief _self;
  final $Res Function(InteractionBrief) _then;

/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? kind = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(InteractionBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InteractionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InteractionStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadRefCopyWith<$Res> get reference {

  return $InteractionReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionBrief].
extension InteractionBriefPatterns on InteractionBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionBrief value)  $default,){
final _that = this;
switch (_that) {
case _InteractionBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionBrief value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionReadRef reference,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionReadRef reference,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _InteractionBrief():
return $default(_that.reference,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionReadRef reference,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _InteractionBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionBrief implements InteractionBrief {
  const _InteractionBrief({required this.reference, required this.revision, required this.kind, required this.status, required this.createdAt, required this.updatedAt});


@override final  InteractionReadRef reference;
@override final  int revision;
@override final  InteractionKind kind;
@override final  InteractionStatus status;
@override final  int createdAt;
@override final  int updatedAt;

/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionBriefCopyWith<_InteractionBrief> get copyWith => __$InteractionBriefCopyWithImpl<_InteractionBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,kind,status,createdAt,updatedAt);
}

@override
String toString() {
    return 'InteractionBrief(reference: $reference, revision: $revision, kind: $kind, status: $status, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$InteractionBriefCopyWith<$Res> implements $InteractionBriefCopyWith<$Res> {
  factory _$InteractionBriefCopyWith(_InteractionBrief value, $Res Function(_InteractionBrief) _then) = __$InteractionBriefCopyWithImpl;
@override @useResult
$Res call({
 InteractionReadRef reference, int revision, InteractionKind kind, InteractionStatus status, int createdAt, int updatedAt
});


@override $InteractionReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$InteractionBriefCopyWithImpl<$Res>
    implements _$InteractionBriefCopyWith<$Res> {
  __$InteractionBriefCopyWithImpl(this._self, this._then);

  final _InteractionBrief _self;
  final $Res Function(_InteractionBrief) _then;

/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? kind = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_InteractionBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InteractionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InteractionStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadRefCopyWith<$Res> get reference {

  return $InteractionReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$InteractionIndexHeader {

 InteractionIndexRef get reference; int get total; int get pending;
/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionIndexHeaderCopyWith<InteractionIndexHeader> get copyWith => _$InteractionIndexHeaderCopyWithImpl<InteractionIndexHeader>(this as InteractionIndexHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionIndexHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionIndexHeader&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.pending, _this.pending) || other.pending == _this.pending));
}


@override
int get hashCode {
  final _this = this as InteractionIndexHeader;
  return Object.hash(runtimeType,_this.reference,_this.total,_this.pending);
}

@override
String toString() {
  final _this = this as InteractionIndexHeader;
  return 'InteractionIndexHeader(reference: ${_this.reference}, total: ${_this.total}, pending: ${_this.pending})';
}


}

/// @nodoc
abstract mixin class $InteractionIndexHeaderCopyWith<$Res>  {
  factory $InteractionIndexHeaderCopyWith(InteractionIndexHeader value, $Res Function(InteractionIndexHeader) _then) = _$InteractionIndexHeaderCopyWithImpl;
@useResult
$Res call({
 InteractionIndexRef reference, int total, int pending
});


$InteractionIndexRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$InteractionIndexHeaderCopyWithImpl<$Res>
    implements $InteractionIndexHeaderCopyWith<$Res> {
  _$InteractionIndexHeaderCopyWithImpl(this._self, this._then);

  final InteractionIndexHeader _self;
  final $Res Function(InteractionIndexHeader) _then;

/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? total = null,Object? pending = null,}) {
  return _then(InteractionIndexHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionIndexRef,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexRefCopyWith<$Res> get reference {

  return $InteractionIndexRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionIndexHeader].
extension InteractionIndexHeaderPatterns on InteractionIndexHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionIndexHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionIndexHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionIndexHeader value)  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionIndexHeader value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionIndexRef reference,  int total,  int pending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionIndexHeader() when $default != null:
return $default(_that.reference,_that.total,_that.pending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionIndexRef reference,  int total,  int pending)  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexHeader():
return $default(_that.reference,_that.total,_that.pending);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionIndexRef reference,  int total,  int pending)?  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexHeader() when $default != null:
return $default(_that.reference,_that.total,_that.pending);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionIndexHeader implements InteractionIndexHeader {
  const _InteractionIndexHeader({required this.reference, required this.total, required this.pending});


@override final  InteractionIndexRef reference;
@override final  int total;
@override final  int pending;

/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionIndexHeaderCopyWith<_InteractionIndexHeader> get copyWith => __$InteractionIndexHeaderCopyWithImpl<_InteractionIndexHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionIndexHeader&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.total, total) || other.total == total)&&(identical(other.pending, pending) || other.pending == pending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,total,pending);
}

@override
String toString() {
    return 'InteractionIndexHeader(reference: $reference, total: $total, pending: $pending)';
}


}

/// @nodoc
abstract mixin class _$InteractionIndexHeaderCopyWith<$Res> implements $InteractionIndexHeaderCopyWith<$Res> {
  factory _$InteractionIndexHeaderCopyWith(_InteractionIndexHeader value, $Res Function(_InteractionIndexHeader) _then) = __$InteractionIndexHeaderCopyWithImpl;
@override @useResult
$Res call({
 InteractionIndexRef reference, int total, int pending
});


@override $InteractionIndexRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$InteractionIndexHeaderCopyWithImpl<$Res>
    implements _$InteractionIndexHeaderCopyWith<$Res> {
  __$InteractionIndexHeaderCopyWithImpl(this._self, this._then);

  final _InteractionIndexHeader _self;
  final $Res Function(_InteractionIndexHeader) _then;

/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? total = null,Object? pending = null,}) {
  return _then(_InteractionIndexHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionIndexRef,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionIndexHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexRefCopyWith<$Res> get reference {

  return $InteractionIndexRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$InteractionDelta {


/// Create a copy of InteractionDelta
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionDeltaCopyWith<InteractionDelta> get copyWith => _$InteractionDeltaCopyWithImpl<InteractionDelta>(this as InteractionDelta, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionDelta;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionDelta&&(identical(other.baseIndexRevision, _this.baseIndexRevision) || other.baseIndexRevision == _this.baseIndexRevision)&&(identical(other.index, _this.index) || other.index == _this.index)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries)&&const DeepCollectionEquality().equals(other.terminalFacts, _this.terminalFacts));
}


@override
int get hashCode {
  final _this = this as InteractionDelta;
  return Object.hash(runtimeType,_this.baseIndexRevision,_this.index,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries),const DeepCollectionEquality().hash(_this.terminalFacts));
}

@override
String toString() {
  final _this = this as InteractionDelta;
  return 'InteractionDelta(baseIndexRevision: ${_this.baseIndexRevision}, index: ${_this.index}, upserted: ${_this.upserted}, removedEntries: ${_this.removedEntries}, terminalFacts: ${_this.terminalFacts})';
}


}

/// @nodoc
abstract mixin class $InteractionDeltaCopyWith<$Res>  {
  factory $InteractionDeltaCopyWith(InteractionDelta value, $Res Function(InteractionDelta) _then) = _$InteractionDeltaCopyWithImpl;
@useResult
$Res call({
 int baseIndexRevision, InteractionIndexHeader index, List<InteractionBrief> upserted, List<int> removedEntries, List<InteractionBrief> terminalFacts
});


$InteractionIndexHeaderCopyWith<$Res> get index;

}
/// @nodoc
class _$InteractionDeltaCopyWithImpl<$Res>
    implements $InteractionDeltaCopyWith<$Res> {
  _$InteractionDeltaCopyWithImpl(this._self, this._then);

  final InteractionDelta _self;
  final $Res Function(InteractionDelta) _then;

/// Create a copy of InteractionDelta
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseIndexRevision = null,Object? index = null,Object? upserted = null,Object? removedEntries = null,Object? terminalFacts = null,}) {
  return _then(InteractionDelta(
baseIndexRevision: null == baseIndexRevision ? _self.baseIndexRevision : baseIndexRevision // ignore: cast_nullable_to_non_nullable
as int,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as InteractionIndexHeader,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<InteractionBrief>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,terminalFacts: null == terminalFacts ? _self.terminalFacts : terminalFacts // ignore: cast_nullable_to_non_nullable
as List<InteractionBrief>,
  ));
}
/// Create a copy of InteractionDelta
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexHeaderCopyWith<$Res> get index {

  return $InteractionIndexHeaderCopyWith<$Res>(_self.index, (value) {
    return _then(_self.copyWith(index: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionDelta].
extension InteractionDeltaPatterns on InteractionDelta {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$ActivityBrief {

 ActivityReadRef get reference; int get revision; ThreadActivityKind get kind; int get toolCount; int get backgroundCount; int get activeCount; bool get hasLatestStarted;
/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityBriefCopyWith<ActivityBrief> get copyWith => _$ActivityBriefCopyWithImpl<ActivityBrief>(this as ActivityBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.toolCount, _this.toolCount) || other.toolCount == _this.toolCount)&&(identical(other.backgroundCount, _this.backgroundCount) || other.backgroundCount == _this.backgroundCount)&&(identical(other.activeCount, _this.activeCount) || other.activeCount == _this.activeCount)&&(identical(other.hasLatestStarted, _this.hasLatestStarted) || other.hasLatestStarted == _this.hasLatestStarted));
}


@override
int get hashCode {
  final _this = this as ActivityBrief;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.kind,_this.toolCount,_this.backgroundCount,_this.activeCount,_this.hasLatestStarted);
}

@override
String toString() {
  final _this = this as ActivityBrief;
  return 'ActivityBrief(reference: ${_this.reference}, revision: ${_this.revision}, kind: ${_this.kind}, toolCount: ${_this.toolCount}, backgroundCount: ${_this.backgroundCount}, activeCount: ${_this.activeCount}, hasLatestStarted: ${_this.hasLatestStarted})';
}


}

/// @nodoc
abstract mixin class $ActivityBriefCopyWith<$Res>  {
  factory $ActivityBriefCopyWith(ActivityBrief value, $Res Function(ActivityBrief) _then) = _$ActivityBriefCopyWithImpl;
@useResult
$Res call({
 ActivityReadRef reference, int revision, ThreadActivityKind kind, int toolCount, int backgroundCount, int activeCount, bool hasLatestStarted
});


$ActivityReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ActivityBriefCopyWithImpl<$Res>
    implements $ActivityBriefCopyWith<$Res> {
  _$ActivityBriefCopyWithImpl(this._self, this._then);

  final ActivityBrief _self;
  final $Res Function(ActivityBrief) _then;

/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? kind = null,Object? toolCount = null,Object? backgroundCount = null,Object? activeCount = null,Object? hasLatestStarted = null,}) {
  return _then(ActivityBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ActivityReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadActivityKind,toolCount: null == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as int,backgroundCount: null == backgroundCount ? _self.backgroundCount : backgroundCount // ignore: cast_nullable_to_non_nullable
as int,activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,hasLatestStarted: null == hasLatestStarted ? _self.hasLatestStarted : hasLatestStarted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityReadRefCopyWith<$Res> get reference {

  return $ActivityReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivityBrief].
extension ActivityBriefPatterns on ActivityBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityBrief value)  $default,){
final _that = this;
switch (_that) {
case _ActivityBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityBrief value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ActivityReadRef reference,  int revision,  ThreadActivityKind kind,  int toolCount,  int backgroundCount,  int activeCount,  bool hasLatestStarted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.kind,_that.toolCount,_that.backgroundCount,_that.activeCount,_that.hasLatestStarted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ActivityReadRef reference,  int revision,  ThreadActivityKind kind,  int toolCount,  int backgroundCount,  int activeCount,  bool hasLatestStarted)  $default,) {final _that = this;
switch (_that) {
case _ActivityBrief():
return $default(_that.reference,_that.revision,_that.kind,_that.toolCount,_that.backgroundCount,_that.activeCount,_that.hasLatestStarted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ActivityReadRef reference,  int revision,  ThreadActivityKind kind,  int toolCount,  int backgroundCount,  int activeCount,  bool hasLatestStarted)?  $default,) {final _that = this;
switch (_that) {
case _ActivityBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.kind,_that.toolCount,_that.backgroundCount,_that.activeCount,_that.hasLatestStarted);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityBrief implements ActivityBrief {
  const _ActivityBrief({required this.reference, required this.revision, required this.kind, required this.toolCount, required this.backgroundCount, required this.activeCount, required this.hasLatestStarted});


@override final  ActivityReadRef reference;
@override final  int revision;
@override final  ThreadActivityKind kind;
@override final  int toolCount;
@override final  int backgroundCount;
@override final  int activeCount;
@override final  bool hasLatestStarted;

/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityBriefCopyWith<_ActivityBrief> get copyWith => __$ActivityBriefCopyWithImpl<_ActivityBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.toolCount, toolCount) || other.toolCount == toolCount)&&(identical(other.backgroundCount, backgroundCount) || other.backgroundCount == backgroundCount)&&(identical(other.activeCount, activeCount) || other.activeCount == activeCount)&&(identical(other.hasLatestStarted, hasLatestStarted) || other.hasLatestStarted == hasLatestStarted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,kind,toolCount,backgroundCount,activeCount,hasLatestStarted);
}

@override
String toString() {
    return 'ActivityBrief(reference: $reference, revision: $revision, kind: $kind, toolCount: $toolCount, backgroundCount: $backgroundCount, activeCount: $activeCount, hasLatestStarted: $hasLatestStarted)';
}


}

/// @nodoc
abstract mixin class _$ActivityBriefCopyWith<$Res> implements $ActivityBriefCopyWith<$Res> {
  factory _$ActivityBriefCopyWith(_ActivityBrief value, $Res Function(_ActivityBrief) _then) = __$ActivityBriefCopyWithImpl;
@override @useResult
$Res call({
 ActivityReadRef reference, int revision, ThreadActivityKind kind, int toolCount, int backgroundCount, int activeCount, bool hasLatestStarted
});


@override $ActivityReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ActivityBriefCopyWithImpl<$Res>
    implements _$ActivityBriefCopyWith<$Res> {
  __$ActivityBriefCopyWithImpl(this._self, this._then);

  final _ActivityBrief _self;
  final $Res Function(_ActivityBrief) _then;

/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? kind = null,Object? toolCount = null,Object? backgroundCount = null,Object? activeCount = null,Object? hasLatestStarted = null,}) {
  return _then(_ActivityBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ActivityReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadActivityKind,toolCount: null == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as int,backgroundCount: null == backgroundCount ? _self.backgroundCount : backgroundCount // ignore: cast_nullable_to_non_nullable
as int,activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,hasLatestStarted: null == hasLatestStarted ? _self.hasLatestStarted : hasLatestStarted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ActivityBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityReadRefCopyWith<$Res> get reference {

  return $ActivityReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$StorageBrief {

 StorageReadRef get reference; HistoryFault? get fault; int get faultGeneration; int? get acceptedSequence; int? get durableSequence; ThreadStorageExecution get execution; bool get pressurePaused; bool get resumeRequired; bool get canResume; bool get hasLastError;
/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StorageBriefCopyWith<StorageBrief> get copyWith => _$StorageBriefCopyWithImpl<StorageBrief>(this as StorageBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StorageBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StorageBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.fault, _this.fault) || other.fault == _this.fault)&&(identical(other.faultGeneration, _this.faultGeneration) || other.faultGeneration == _this.faultGeneration)&&(identical(other.acceptedSequence, _this.acceptedSequence) || other.acceptedSequence == _this.acceptedSequence)&&(identical(other.durableSequence, _this.durableSequence) || other.durableSequence == _this.durableSequence)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused)&&(identical(other.resumeRequired, _this.resumeRequired) || other.resumeRequired == _this.resumeRequired)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume)&&(identical(other.hasLastError, _this.hasLastError) || other.hasLastError == _this.hasLastError));
}


@override
int get hashCode {
  final _this = this as StorageBrief;
  return Object.hash(runtimeType,_this.reference,_this.fault,_this.faultGeneration,_this.acceptedSequence,_this.durableSequence,_this.execution,_this.pressurePaused,_this.resumeRequired,_this.canResume,_this.hasLastError);
}

@override
String toString() {
  final _this = this as StorageBrief;
  return 'StorageBrief(reference: ${_this.reference}, fault: ${_this.fault}, faultGeneration: ${_this.faultGeneration}, acceptedSequence: ${_this.acceptedSequence}, durableSequence: ${_this.durableSequence}, execution: ${_this.execution}, pressurePaused: ${_this.pressurePaused}, resumeRequired: ${_this.resumeRequired}, canResume: ${_this.canResume}, hasLastError: ${_this.hasLastError})';
}


}

/// @nodoc
abstract mixin class $StorageBriefCopyWith<$Res>  {
  factory $StorageBriefCopyWith(StorageBrief value, $Res Function(StorageBrief) _then) = _$StorageBriefCopyWithImpl;
@useResult
$Res call({
 StorageReadRef reference, HistoryFault? fault, int faultGeneration, int? acceptedSequence, int? durableSequence, ThreadStorageExecution execution, bool pressurePaused, bool resumeRequired, bool canResume, bool hasLastError
});


$StorageReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$StorageBriefCopyWithImpl<$Res>
    implements $StorageBriefCopyWith<$Res> {
  _$StorageBriefCopyWithImpl(this._self, this._then);

  final StorageBrief _self;
  final $Res Function(StorageBrief) _then;

/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? fault = freezed,Object? faultGeneration = null,Object? acceptedSequence = freezed,Object? durableSequence = freezed,Object? execution = null,Object? pressurePaused = null,Object? resumeRequired = null,Object? canResume = null,Object? hasLastError = null,}) {
  return _then(StorageBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as StorageReadRef,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,acceptedSequence: freezed == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int?,durableSequence: freezed == durableSequence ? _self.durableSequence : durableSequence // ignore: cast_nullable_to_non_nullable
as int?,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadStorageExecution,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,resumeRequired: null == resumeRequired ? _self.resumeRequired : resumeRequired // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,hasLastError: null == hasLastError ? _self.hasLastError : hasLastError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageReadRefCopyWith<$Res> get reference {

  return $StorageReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [StorageBrief].
extension StorageBriefPatterns on StorageBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StorageBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StorageBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StorageBrief value)  $default,){
final _that = this;
switch (_that) {
case _StorageBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StorageBrief value)?  $default,){
final _that = this;
switch (_that) {
case _StorageBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StorageReadRef reference,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  bool hasLastError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StorageBrief() when $default != null:
return $default(_that.reference,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.hasLastError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StorageReadRef reference,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  bool hasLastError)  $default,) {final _that = this;
switch (_that) {
case _StorageBrief():
return $default(_that.reference,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.hasLastError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StorageReadRef reference,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  bool hasLastError)?  $default,) {final _that = this;
switch (_that) {
case _StorageBrief() when $default != null:
return $default(_that.reference,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.hasLastError);case _:
  return null;

}
}

}

/// @nodoc


class _StorageBrief implements StorageBrief {
  const _StorageBrief({required this.reference, required this.fault, required this.faultGeneration, required this.acceptedSequence, required this.durableSequence, required this.execution, required this.pressurePaused, required this.resumeRequired, required this.canResume, required this.hasLastError});


@override final  StorageReadRef reference;
@override final  HistoryFault? fault;
@override final  int faultGeneration;
@override final  int? acceptedSequence;
@override final  int? durableSequence;
@override final  ThreadStorageExecution execution;
@override final  bool pressurePaused;
@override final  bool resumeRequired;
@override final  bool canResume;
@override final  bool hasLastError;

/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StorageBriefCopyWith<_StorageBrief> get copyWith => __$StorageBriefCopyWithImpl<_StorageBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StorageBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.fault, fault) || other.fault == fault)&&(identical(other.faultGeneration, faultGeneration) || other.faultGeneration == faultGeneration)&&(identical(other.acceptedSequence, acceptedSequence) || other.acceptedSequence == acceptedSequence)&&(identical(other.durableSequence, durableSequence) || other.durableSequence == durableSequence)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused)&&(identical(other.resumeRequired, resumeRequired) || other.resumeRequired == resumeRequired)&&(identical(other.canResume, canResume) || other.canResume == canResume)&&(identical(other.hasLastError, hasLastError) || other.hasLastError == hasLastError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,fault,faultGeneration,acceptedSequence,durableSequence,execution,pressurePaused,resumeRequired,canResume,hasLastError);
}

@override
String toString() {
    return 'StorageBrief(reference: $reference, fault: $fault, faultGeneration: $faultGeneration, acceptedSequence: $acceptedSequence, durableSequence: $durableSequence, execution: $execution, pressurePaused: $pressurePaused, resumeRequired: $resumeRequired, canResume: $canResume, hasLastError: $hasLastError)';
}


}

/// @nodoc
abstract mixin class _$StorageBriefCopyWith<$Res> implements $StorageBriefCopyWith<$Res> {
  factory _$StorageBriefCopyWith(_StorageBrief value, $Res Function(_StorageBrief) _then) = __$StorageBriefCopyWithImpl;
@override @useResult
$Res call({
 StorageReadRef reference, HistoryFault? fault, int faultGeneration, int? acceptedSequence, int? durableSequence, ThreadStorageExecution execution, bool pressurePaused, bool resumeRequired, bool canResume, bool hasLastError
});


@override $StorageReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$StorageBriefCopyWithImpl<$Res>
    implements _$StorageBriefCopyWith<$Res> {
  __$StorageBriefCopyWithImpl(this._self, this._then);

  final _StorageBrief _self;
  final $Res Function(_StorageBrief) _then;

/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? fault = freezed,Object? faultGeneration = null,Object? acceptedSequence = freezed,Object? durableSequence = freezed,Object? execution = null,Object? pressurePaused = null,Object? resumeRequired = null,Object? canResume = null,Object? hasLastError = null,}) {
  return _then(_StorageBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as StorageReadRef,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,acceptedSequence: freezed == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int?,durableSequence: freezed == durableSequence ? _self.durableSequence : durableSequence // ignore: cast_nullable_to_non_nullable
as int?,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadStorageExecution,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,resumeRequired: null == resumeRequired ? _self.resumeRequired : resumeRequired // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,hasLastError: null == hasLastError ? _self.hasLastError : hasLastError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of StorageBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageReadRefCopyWith<$Res> get reference {

  return $StorageReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ThreadExecutionBaseline {

 ThreadStatus get status; TurnBrief? get activeTurn; TurnBrief? get recentTerminalTurn; InteractionIndexHeader get interactions; ActivityBrief? get activity; StorageBrief? get storage;
/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionBaselineCopyWith<ThreadExecutionBaseline> get copyWith => _$ThreadExecutionBaselineCopyWithImpl<ThreadExecutionBaseline>(this as ThreadExecutionBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadExecutionBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionBaseline&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.activeTurn, _this.activeTurn) || other.activeTurn == _this.activeTurn)&&(identical(other.recentTerminalTurn, _this.recentTerminalTurn) || other.recentTerminalTurn == _this.recentTerminalTurn)&&(identical(other.interactions, _this.interactions) || other.interactions == _this.interactions)&&(identical(other.activity, _this.activity) || other.activity == _this.activity)&&(identical(other.storage, _this.storage) || other.storage == _this.storage));
}


@override
int get hashCode {
  final _this = this as ThreadExecutionBaseline;
  return Object.hash(runtimeType,_this.status,_this.activeTurn,_this.recentTerminalTurn,_this.interactions,_this.activity,_this.storage);
}

@override
String toString() {
  final _this = this as ThreadExecutionBaseline;
  return 'ThreadExecutionBaseline(status: ${_this.status}, activeTurn: ${_this.activeTurn}, recentTerminalTurn: ${_this.recentTerminalTurn}, interactions: ${_this.interactions}, activity: ${_this.activity}, storage: ${_this.storage})';
}


}

/// @nodoc
abstract mixin class $ThreadExecutionBaselineCopyWith<$Res>  {
  factory $ThreadExecutionBaselineCopyWith(ThreadExecutionBaseline value, $Res Function(ThreadExecutionBaseline) _then) = _$ThreadExecutionBaselineCopyWithImpl;
@useResult
$Res call({
 ThreadStatus status, TurnBrief? activeTurn, TurnBrief? recentTerminalTurn, InteractionIndexHeader interactions, ActivityBrief? activity, StorageBrief? storage
});


$TurnBriefCopyWith<$Res>? get activeTurn;$TurnBriefCopyWith<$Res>? get recentTerminalTurn;$InteractionIndexHeaderCopyWith<$Res> get interactions;$ActivityBriefCopyWith<$Res>? get activity;$StorageBriefCopyWith<$Res>? get storage;

}
/// @nodoc
class _$ThreadExecutionBaselineCopyWithImpl<$Res>
    implements $ThreadExecutionBaselineCopyWith<$Res> {
  _$ThreadExecutionBaselineCopyWithImpl(this._self, this._then);

  final ThreadExecutionBaseline _self;
  final $Res Function(ThreadExecutionBaseline) _then;

/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? activeTurn = freezed,Object? recentTerminalTurn = freezed,Object? interactions = null,Object? activity = freezed,Object? storage = freezed,}) {
  return _then(ThreadExecutionBaseline(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,activeTurn: freezed == activeTurn ? _self.activeTurn : activeTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,recentTerminalTurn: freezed == recentTerminalTurn ? _self.recentTerminalTurn : recentTerminalTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,interactions: null == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionIndexHeader,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivityBrief?,storage: freezed == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as StorageBrief?,
  ));
}
/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get activeTurn {
    if (_self.activeTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.activeTurn!, (value) {
    return _then(_self.copyWith(activeTurn: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get recentTerminalTurn {
    if (_self.recentTerminalTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.recentTerminalTurn!, (value) {
    return _then(_self.copyWith(recentTerminalTurn: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexHeaderCopyWith<$Res> get interactions {

  return $InteractionIndexHeaderCopyWith<$Res>(_self.interactions, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityBriefCopyWith<$Res>? get activity {
    if (_self.activity == null) {
    return null;
  }

  return $ActivityBriefCopyWith<$Res>(_self.activity!, (value) {
    return _then(_self.copyWith(activity: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageBriefCopyWith<$Res>? get storage {
    if (_self.storage == null) {
    return null;
  }

  return $StorageBriefCopyWith<$Res>(_self.storage!, (value) {
    return _then(_self.copyWith(storage: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadExecutionBaseline].
extension ThreadExecutionBaselinePatterns on ThreadExecutionBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadExecutionBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadExecutionBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadExecutionBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadExecutionBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadStatus status,  TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn,  InteractionIndexHeader interactions,  ActivityBrief? activity,  StorageBrief? storage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadExecutionBaseline() when $default != null:
return $default(_that.status,_that.activeTurn,_that.recentTerminalTurn,_that.interactions,_that.activity,_that.storage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadStatus status,  TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn,  InteractionIndexHeader interactions,  ActivityBrief? activity,  StorageBrief? storage)  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionBaseline():
return $default(_that.status,_that.activeTurn,_that.recentTerminalTurn,_that.interactions,_that.activity,_that.storage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadStatus status,  TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn,  InteractionIndexHeader interactions,  ActivityBrief? activity,  StorageBrief? storage)?  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionBaseline() when $default != null:
return $default(_that.status,_that.activeTurn,_that.recentTerminalTurn,_that.interactions,_that.activity,_that.storage);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadExecutionBaseline implements ThreadExecutionBaseline {
  const _ThreadExecutionBaseline({required this.status, required this.activeTurn, required this.recentTerminalTurn, required this.interactions, required this.activity, required this.storage});


@override final  ThreadStatus status;
@override final  TurnBrief? activeTurn;
@override final  TurnBrief? recentTerminalTurn;
@override final  InteractionIndexHeader interactions;
@override final  ActivityBrief? activity;
@override final  StorageBrief? storage;

/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadExecutionBaselineCopyWith<_ThreadExecutionBaseline> get copyWith => __$ThreadExecutionBaselineCopyWithImpl<_ThreadExecutionBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadExecutionBaseline&&(identical(other.status, status) || other.status == status)&&(identical(other.activeTurn, activeTurn) || other.activeTurn == activeTurn)&&(identical(other.recentTerminalTurn, recentTerminalTurn) || other.recentTerminalTurn == recentTerminalTurn)&&(identical(other.interactions, interactions) || other.interactions == interactions)&&(identical(other.activity, activity) || other.activity == activity)&&(identical(other.storage, storage) || other.storage == storage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,activeTurn,recentTerminalTurn,interactions,activity,storage);
}

@override
String toString() {
    return 'ThreadExecutionBaseline(status: $status, activeTurn: $activeTurn, recentTerminalTurn: $recentTerminalTurn, interactions: $interactions, activity: $activity, storage: $storage)';
}


}

/// @nodoc
abstract mixin class _$ThreadExecutionBaselineCopyWith<$Res> implements $ThreadExecutionBaselineCopyWith<$Res> {
  factory _$ThreadExecutionBaselineCopyWith(_ThreadExecutionBaseline value, $Res Function(_ThreadExecutionBaseline) _then) = __$ThreadExecutionBaselineCopyWithImpl;
@override @useResult
$Res call({
 ThreadStatus status, TurnBrief? activeTurn, TurnBrief? recentTerminalTurn, InteractionIndexHeader interactions, ActivityBrief? activity, StorageBrief? storage
});


@override $TurnBriefCopyWith<$Res>? get activeTurn;@override $TurnBriefCopyWith<$Res>? get recentTerminalTurn;@override $InteractionIndexHeaderCopyWith<$Res> get interactions;@override $ActivityBriefCopyWith<$Res>? get activity;@override $StorageBriefCopyWith<$Res>? get storage;

}
/// @nodoc
class __$ThreadExecutionBaselineCopyWithImpl<$Res>
    implements _$ThreadExecutionBaselineCopyWith<$Res> {
  __$ThreadExecutionBaselineCopyWithImpl(this._self, this._then);

  final _ThreadExecutionBaseline _self;
  final $Res Function(_ThreadExecutionBaseline) _then;

/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? activeTurn = freezed,Object? recentTerminalTurn = freezed,Object? interactions = null,Object? activity = freezed,Object? storage = freezed,}) {
  return _then(_ThreadExecutionBaseline(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,activeTurn: freezed == activeTurn ? _self.activeTurn : activeTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,recentTerminalTurn: freezed == recentTerminalTurn ? _self.recentTerminalTurn : recentTerminalTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,interactions: null == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionIndexHeader,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivityBrief?,storage: freezed == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as StorageBrief?,
  ));
}

/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get activeTurn {
    if (_self.activeTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.activeTurn!, (value) {
    return _then(_self.copyWith(activeTurn: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get recentTerminalTurn {
    if (_self.recentTerminalTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.recentTerminalTurn!, (value) {
    return _then(_self.copyWith(recentTerminalTurn: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexHeaderCopyWith<$Res> get interactions {

  return $InteractionIndexHeaderCopyWith<$Res>(_self.interactions, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityBriefCopyWith<$Res>? get activity {
    if (_self.activity == null) {
    return null;
  }

  return $ActivityBriefCopyWith<$Res>(_self.activity!, (value) {
    return _then(_self.copyWith(activity: value));
  });
}/// Create a copy of ThreadExecutionBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageBriefCopyWith<$Res>? get storage {
    if (_self.storage == null) {
    return null;
  }

  return $StorageBriefCopyWith<$Res>(_self.storage!, (value) {
    return _then(_self.copyWith(storage: value));
  });
}
}

/// @nodoc
mixin _$TurnsReplacement {

 TurnBrief? get activeTurn; TurnBrief? get recentTerminalTurn;
/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnsReplacementCopyWith<TurnsReplacement> get copyWith => _$TurnsReplacementCopyWithImpl<TurnsReplacement>(this as TurnsReplacement, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnsReplacement;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnsReplacement&&(identical(other.activeTurn, _this.activeTurn) || other.activeTurn == _this.activeTurn)&&(identical(other.recentTerminalTurn, _this.recentTerminalTurn) || other.recentTerminalTurn == _this.recentTerminalTurn));
}


@override
int get hashCode {
  final _this = this as TurnsReplacement;
  return Object.hash(runtimeType,_this.activeTurn,_this.recentTerminalTurn);
}

@override
String toString() {
  final _this = this as TurnsReplacement;
  return 'TurnsReplacement(activeTurn: ${_this.activeTurn}, recentTerminalTurn: ${_this.recentTerminalTurn})';
}


}

/// @nodoc
abstract mixin class $TurnsReplacementCopyWith<$Res>  {
  factory $TurnsReplacementCopyWith(TurnsReplacement value, $Res Function(TurnsReplacement) _then) = _$TurnsReplacementCopyWithImpl;
@useResult
$Res call({
 TurnBrief? activeTurn, TurnBrief? recentTerminalTurn
});


$TurnBriefCopyWith<$Res>? get activeTurn;$TurnBriefCopyWith<$Res>? get recentTerminalTurn;

}
/// @nodoc
class _$TurnsReplacementCopyWithImpl<$Res>
    implements $TurnsReplacementCopyWith<$Res> {
  _$TurnsReplacementCopyWithImpl(this._self, this._then);

  final TurnsReplacement _self;
  final $Res Function(TurnsReplacement) _then;

/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? activeTurn = freezed,Object? recentTerminalTurn = freezed,}) {
  return _then(TurnsReplacement(
activeTurn: freezed == activeTurn ? _self.activeTurn : activeTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,recentTerminalTurn: freezed == recentTerminalTurn ? _self.recentTerminalTurn : recentTerminalTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,
  ));
}
/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get activeTurn {
    if (_self.activeTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.activeTurn!, (value) {
    return _then(_self.copyWith(activeTurn: value));
  });
}/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get recentTerminalTurn {
    if (_self.recentTerminalTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.recentTerminalTurn!, (value) {
    return _then(_self.copyWith(recentTerminalTurn: value));
  });
}
}


/// Adds pattern-matching-related methods to [TurnsReplacement].
extension TurnsReplacementPatterns on TurnsReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnsReplacement value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnsReplacement() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnsReplacement value)  $default,){
final _that = this;
switch (_that) {
case _TurnsReplacement():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnsReplacement value)?  $default,){
final _that = this;
switch (_that) {
case _TurnsReplacement() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnsReplacement() when $default != null:
return $default(_that.activeTurn,_that.recentTerminalTurn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn)  $default,) {final _that = this;
switch (_that) {
case _TurnsReplacement():
return $default(_that.activeTurn,_that.recentTerminalTurn);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TurnBrief? activeTurn,  TurnBrief? recentTerminalTurn)?  $default,) {final _that = this;
switch (_that) {
case _TurnsReplacement() when $default != null:
return $default(_that.activeTurn,_that.recentTerminalTurn);case _:
  return null;

}
}

}

/// @nodoc


class _TurnsReplacement implements TurnsReplacement {
  const _TurnsReplacement({required this.activeTurn, required this.recentTerminalTurn});


@override final  TurnBrief? activeTurn;
@override final  TurnBrief? recentTerminalTurn;

/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnsReplacementCopyWith<_TurnsReplacement> get copyWith => __$TurnsReplacementCopyWithImpl<_TurnsReplacement>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnsReplacement&&(identical(other.activeTurn, activeTurn) || other.activeTurn == activeTurn)&&(identical(other.recentTerminalTurn, recentTerminalTurn) || other.recentTerminalTurn == recentTerminalTurn));
}


@override
int get hashCode {
    return Object.hash(runtimeType,activeTurn,recentTerminalTurn);
}

@override
String toString() {
    return 'TurnsReplacement(activeTurn: $activeTurn, recentTerminalTurn: $recentTerminalTurn)';
}


}

/// @nodoc
abstract mixin class _$TurnsReplacementCopyWith<$Res> implements $TurnsReplacementCopyWith<$Res> {
  factory _$TurnsReplacementCopyWith(_TurnsReplacement value, $Res Function(_TurnsReplacement) _then) = __$TurnsReplacementCopyWithImpl;
@override @useResult
$Res call({
 TurnBrief? activeTurn, TurnBrief? recentTerminalTurn
});


@override $TurnBriefCopyWith<$Res>? get activeTurn;@override $TurnBriefCopyWith<$Res>? get recentTerminalTurn;

}
/// @nodoc
class __$TurnsReplacementCopyWithImpl<$Res>
    implements _$TurnsReplacementCopyWith<$Res> {
  __$TurnsReplacementCopyWithImpl(this._self, this._then);

  final _TurnsReplacement _self;
  final $Res Function(_TurnsReplacement) _then;

/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? activeTurn = freezed,Object? recentTerminalTurn = freezed,}) {
  return _then(_TurnsReplacement(
activeTurn: freezed == activeTurn ? _self.activeTurn : activeTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,recentTerminalTurn: freezed == recentTerminalTurn ? _self.recentTerminalTurn : recentTerminalTurn // ignore: cast_nullable_to_non_nullable
as TurnBrief?,
  ));
}

/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get activeTurn {
    if (_self.activeTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.activeTurn!, (value) {
    return _then(_self.copyWith(activeTurn: value));
  });
}/// Create a copy of TurnsReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<$Res>? get recentTerminalTurn {
    if (_self.recentTerminalTurn == null) {
    return null;
  }

  return $TurnBriefCopyWith<$Res>(_self.recentTerminalTurn!, (value) {
    return _then(_self.copyWith(recentTerminalTurn: value));
  });
}
}

/// @nodoc
mixin _$ActivityReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityReplacement()';
}


}

/// @nodoc
class $ActivityReplacementCopyWith<$Res>  {
$ActivityReplacementCopyWith(ActivityReplacement _, $Res Function(ActivityReplacement) __);
}


/// Adds pattern-matching-related methods to [ActivityReplacement].
extension ActivityReplacementPatterns on ActivityReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedActivity value)?  unchanged,TResult Function( ReplacedActivity value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedActivity() when unchanged != null:
return unchanged(_that);case ReplacedActivity() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedActivity value)  unchanged,required TResult Function( ReplacedActivity value)  replace,}){
final _that = this;
switch (_that) {
case UnchangedActivity():
return unchanged(_that);case ReplacedActivity():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedActivity value)?  unchanged,TResult? Function( ReplacedActivity value)?  replace,}){
final _that = this;
switch (_that) {
case UnchangedActivity() when unchanged != null:
return unchanged(_that);case ReplacedActivity() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( ActivityBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnchangedActivity() when unchanged != null:
return unchanged();case ReplacedActivity() when replace != null:
return replace(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( ActivityBrief? value)  replace,}) {final _that = this;
switch (_that) {
case UnchangedActivity():
return unchanged();case ReplacedActivity():
return replace(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( ActivityBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case UnchangedActivity() when unchanged != null:
return unchanged();case ReplacedActivity() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UnchangedActivity implements ActivityReplacement {
  const UnchangedActivity();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedActivity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityReplacement.unchanged()';
}


}




/// @nodoc


class ReplacedActivity implements ActivityReplacement {
  const ReplacedActivity({required this.value});


 final  ActivityBrief? value;

/// Create a copy of ActivityReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplacedActivityCopyWith<ReplacedActivity> get copyWith => _$ReplacedActivityCopyWithImpl<ReplacedActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplacedActivity&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'ActivityReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $ReplacedActivityCopyWith<$Res> implements $ActivityReplacementCopyWith<$Res> {
  factory $ReplacedActivityCopyWith(ReplacedActivity value, $Res Function(ReplacedActivity) _then) = _$ReplacedActivityCopyWithImpl;
@useResult
$Res call({
 ActivityBrief? value
});


$ActivityBriefCopyWith<$Res>? get value;

}
/// @nodoc
class _$ReplacedActivityCopyWithImpl<$Res>
    implements $ReplacedActivityCopyWith<$Res> {
  _$ReplacedActivityCopyWithImpl(this._self, this._then);

  final ReplacedActivity _self;
  final $Res Function(ReplacedActivity) _then;

/// Create a copy of ActivityReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(ReplacedActivity(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ActivityBrief?,
  ));
}

/// Create a copy of ActivityReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityBriefCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ActivityBriefCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$StorageReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StorageReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StorageReplacement()';
}


}

/// @nodoc
class $StorageReplacementCopyWith<$Res>  {
$StorageReplacementCopyWith(StorageReplacement _, $Res Function(StorageReplacement) __);
}


/// Adds pattern-matching-related methods to [StorageReplacement].
extension StorageReplacementPatterns on StorageReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedStorage value)?  unchanged,TResult Function( ReplacedStorage value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedStorage() when unchanged != null:
return unchanged(_that);case ReplacedStorage() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedStorage value)  unchanged,required TResult Function( ReplacedStorage value)  replace,}){
final _that = this;
switch (_that) {
case UnchangedStorage():
return unchanged(_that);case ReplacedStorage():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedStorage value)?  unchanged,TResult? Function( ReplacedStorage value)?  replace,}){
final _that = this;
switch (_that) {
case UnchangedStorage() when unchanged != null:
return unchanged(_that);case ReplacedStorage() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( StorageBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnchangedStorage() when unchanged != null:
return unchanged();case ReplacedStorage() when replace != null:
return replace(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( StorageBrief? value)  replace,}) {final _that = this;
switch (_that) {
case UnchangedStorage():
return unchanged();case ReplacedStorage():
return replace(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( StorageBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case UnchangedStorage() when unchanged != null:
return unchanged();case ReplacedStorage() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UnchangedStorage implements StorageReplacement {
  const UnchangedStorage();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedStorage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StorageReplacement.unchanged()';
}


}




/// @nodoc


class ReplacedStorage implements StorageReplacement {
  const ReplacedStorage({required this.value});


 final  StorageBrief? value;

/// Create a copy of StorageReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplacedStorageCopyWith<ReplacedStorage> get copyWith => _$ReplacedStorageCopyWithImpl<ReplacedStorage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplacedStorage&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'StorageReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $ReplacedStorageCopyWith<$Res> implements $StorageReplacementCopyWith<$Res> {
  factory $ReplacedStorageCopyWith(ReplacedStorage value, $Res Function(ReplacedStorage) _then) = _$ReplacedStorageCopyWithImpl;
@useResult
$Res call({
 StorageBrief? value
});


$StorageBriefCopyWith<$Res>? get value;

}
/// @nodoc
class _$ReplacedStorageCopyWithImpl<$Res>
    implements $ReplacedStorageCopyWith<$Res> {
  _$ReplacedStorageCopyWithImpl(this._self, this._then);

  final ReplacedStorage _self;
  final $Res Function(ReplacedStorage) _then;

/// Create a copy of StorageReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(ReplacedStorage(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as StorageBrief?,
  ));
}

/// Create a copy of StorageReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageBriefCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $StorageBriefCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadExecutionChange {

 ThreadStatus? get status; TurnsReplacement? get turns; InteractionDelta? get interactions; ActivityReplacement get activity; StorageReplacement get storage;
/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionChangeCopyWith<ThreadExecutionChange> get copyWith => _$ThreadExecutionChangeCopyWithImpl<ThreadExecutionChange>(this as ThreadExecutionChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadExecutionChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionChange&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.turns, _this.turns) || other.turns == _this.turns)&&(identical(other.interactions, _this.interactions) || other.interactions == _this.interactions)&&(identical(other.activity, _this.activity) || other.activity == _this.activity)&&(identical(other.storage, _this.storage) || other.storage == _this.storage));
}


@override
int get hashCode {
  final _this = this as ThreadExecutionChange;
  return Object.hash(runtimeType,_this.status,_this.turns,_this.interactions,_this.activity,_this.storage);
}

@override
String toString() {
  final _this = this as ThreadExecutionChange;
  return 'ThreadExecutionChange(status: ${_this.status}, turns: ${_this.turns}, interactions: ${_this.interactions}, activity: ${_this.activity}, storage: ${_this.storage})';
}


}

/// @nodoc
abstract mixin class $ThreadExecutionChangeCopyWith<$Res>  {
  factory $ThreadExecutionChangeCopyWith(ThreadExecutionChange value, $Res Function(ThreadExecutionChange) _then) = _$ThreadExecutionChangeCopyWithImpl;
@useResult
$Res call({
 ThreadStatus? status, TurnsReplacement? turns, InteractionDelta? interactions, ActivityReplacement activity, StorageReplacement storage
});


$TurnsReplacementCopyWith<$Res>? get turns;$InteractionDeltaCopyWith<$Res>? get interactions;$ActivityReplacementCopyWith<$Res> get activity;$StorageReplacementCopyWith<$Res> get storage;

}
/// @nodoc
class _$ThreadExecutionChangeCopyWithImpl<$Res>
    implements $ThreadExecutionChangeCopyWith<$Res> {
  _$ThreadExecutionChangeCopyWithImpl(this._self, this._then);

  final ThreadExecutionChange _self;
  final $Res Function(ThreadExecutionChange) _then;

/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = freezed,Object? turns = freezed,Object? interactions = freezed,Object? activity = null,Object? storage = null,}) {
  return _then(ThreadExecutionChange(
status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus?,turns: freezed == turns ? _self.turns : turns // ignore: cast_nullable_to_non_nullable
as TurnsReplacement?,interactions: freezed == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionDelta?,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivityReplacement,storage: null == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as StorageReplacement,
  ));
}
/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnsReplacementCopyWith<$Res>? get turns {
    if (_self.turns == null) {
    return null;
  }

  return $TurnsReplacementCopyWith<$Res>(_self.turns!, (value) {
    return _then(_self.copyWith(turns: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionDeltaCopyWith<$Res>? get interactions {
    if (_self.interactions == null) {
    return null;
  }

  return $InteractionDeltaCopyWith<$Res>(_self.interactions!, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityReplacementCopyWith<$Res> get activity {

  return $ActivityReplacementCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageReplacementCopyWith<$Res> get storage {

  return $StorageReplacementCopyWith<$Res>(_self.storage, (value) {
    return _then(_self.copyWith(storage: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadExecutionChange].
extension ThreadExecutionChangePatterns on ThreadExecutionChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadExecutionChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadExecutionChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadExecutionChange value)  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadExecutionChange value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadStatus? status,  TurnsReplacement? turns,  InteractionDelta? interactions,  ActivityReplacement activity,  StorageReplacement storage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadExecutionChange() when $default != null:
return $default(_that.status,_that.turns,_that.interactions,_that.activity,_that.storage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadStatus? status,  TurnsReplacement? turns,  InteractionDelta? interactions,  ActivityReplacement activity,  StorageReplacement storage)  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionChange():
return $default(_that.status,_that.turns,_that.interactions,_that.activity,_that.storage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadStatus? status,  TurnsReplacement? turns,  InteractionDelta? interactions,  ActivityReplacement activity,  StorageReplacement storage)?  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionChange() when $default != null:
return $default(_that.status,_that.turns,_that.interactions,_that.activity,_that.storage);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadExecutionChange implements ThreadExecutionChange {
  const _ThreadExecutionChange({required this.status, required this.turns, required this.interactions, required this.activity, required this.storage});


@override final  ThreadStatus? status;
@override final  TurnsReplacement? turns;
@override final  InteractionDelta? interactions;
@override final  ActivityReplacement activity;
@override final  StorageReplacement storage;

/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadExecutionChangeCopyWith<_ThreadExecutionChange> get copyWith => __$ThreadExecutionChangeCopyWithImpl<_ThreadExecutionChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadExecutionChange&&(identical(other.status, status) || other.status == status)&&(identical(other.turns, turns) || other.turns == turns)&&(identical(other.interactions, interactions) || other.interactions == interactions)&&(identical(other.activity, activity) || other.activity == activity)&&(identical(other.storage, storage) || other.storage == storage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,turns,interactions,activity,storage);
}

@override
String toString() {
    return 'ThreadExecutionChange(status: $status, turns: $turns, interactions: $interactions, activity: $activity, storage: $storage)';
}


}

/// @nodoc
abstract mixin class _$ThreadExecutionChangeCopyWith<$Res> implements $ThreadExecutionChangeCopyWith<$Res> {
  factory _$ThreadExecutionChangeCopyWith(_ThreadExecutionChange value, $Res Function(_ThreadExecutionChange) _then) = __$ThreadExecutionChangeCopyWithImpl;
@override @useResult
$Res call({
 ThreadStatus? status, TurnsReplacement? turns, InteractionDelta? interactions, ActivityReplacement activity, StorageReplacement storage
});


@override $TurnsReplacementCopyWith<$Res>? get turns;@override $InteractionDeltaCopyWith<$Res>? get interactions;@override $ActivityReplacementCopyWith<$Res> get activity;@override $StorageReplacementCopyWith<$Res> get storage;

}
/// @nodoc
class __$ThreadExecutionChangeCopyWithImpl<$Res>
    implements _$ThreadExecutionChangeCopyWith<$Res> {
  __$ThreadExecutionChangeCopyWithImpl(this._self, this._then);

  final _ThreadExecutionChange _self;
  final $Res Function(_ThreadExecutionChange) _then;

/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = freezed,Object? turns = freezed,Object? interactions = freezed,Object? activity = null,Object? storage = null,}) {
  return _then(_ThreadExecutionChange(
status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus?,turns: freezed == turns ? _self.turns : turns // ignore: cast_nullable_to_non_nullable
as TurnsReplacement?,interactions: freezed == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionDelta?,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivityReplacement,storage: null == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as StorageReplacement,
  ));
}

/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnsReplacementCopyWith<$Res>? get turns {
    if (_self.turns == null) {
    return null;
  }

  return $TurnsReplacementCopyWith<$Res>(_self.turns!, (value) {
    return _then(_self.copyWith(turns: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionDeltaCopyWith<$Res>? get interactions {
    if (_self.interactions == null) {
    return null;
  }

  return $InteractionDeltaCopyWith<$Res>(_self.interactions!, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityReplacementCopyWith<$Res> get activity {

  return $ActivityReplacementCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}/// Create a copy of ThreadExecutionChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StorageReplacementCopyWith<$Res> get storage {

  return $StorageReplacementCopyWith<$Res>(_self.storage, (value) {
    return _then(_self.copyWith(storage: value));
  });
}
}

// dart format on
