// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'authoring_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TodoBrief {

 TodoReadRef get reference; int get itemCount; bool get hasCallId;
/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<TodoBrief> get copyWith => _$TodoBriefCopyWithImpl<TodoBrief>(this as TodoBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.hasCallId, _this.hasCallId) || other.hasCallId == _this.hasCallId));
}


@override
int get hashCode {
  final _this = this as TodoBrief;
  return Object.hash(runtimeType,_this.reference,_this.itemCount,_this.hasCallId);
}

@override
String toString() {
  final _this = this as TodoBrief;
  return 'TodoBrief(reference: ${_this.reference}, itemCount: ${_this.itemCount}, hasCallId: ${_this.hasCallId})';
}


}

/// @nodoc
abstract mixin class $TodoBriefCopyWith<$Res>  {
  factory $TodoBriefCopyWith(TodoBrief value, $Res Function(TodoBrief) _then) = _$TodoBriefCopyWithImpl;
@useResult
$Res call({
 TodoReadRef reference, int itemCount, bool hasCallId
});


$TodoReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$TodoBriefCopyWithImpl<$Res>
    implements $TodoBriefCopyWith<$Res> {
  _$TodoBriefCopyWithImpl(this._self, this._then);

  final TodoBrief _self;
  final $Res Function(TodoBrief) _then;

/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? itemCount = null,Object? hasCallId = null,}) {
  return _then(TodoBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as TodoReadRef,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,hasCallId: null == hasCallId ? _self.hasCallId : hasCallId // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReadRefCopyWith<$Res> get reference {

  return $TodoReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [TodoBrief].
extension TodoBriefPatterns on TodoBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoBrief value)  $default,){
final _that = this;
switch (_that) {
case _TodoBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoBrief value)?  $default,){
final _that = this;
switch (_that) {
case _TodoBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TodoReadRef reference,  int itemCount,  bool hasCallId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoBrief() when $default != null:
return $default(_that.reference,_that.itemCount,_that.hasCallId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TodoReadRef reference,  int itemCount,  bool hasCallId)  $default,) {final _that = this;
switch (_that) {
case _TodoBrief():
return $default(_that.reference,_that.itemCount,_that.hasCallId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TodoReadRef reference,  int itemCount,  bool hasCallId)?  $default,) {final _that = this;
switch (_that) {
case _TodoBrief() when $default != null:
return $default(_that.reference,_that.itemCount,_that.hasCallId);case _:
  return null;

}
}

}

/// @nodoc


class _TodoBrief implements TodoBrief {
  const _TodoBrief({required this.reference, required this.itemCount, required this.hasCallId});


@override final  TodoReadRef reference;
@override final  int itemCount;
@override final  bool hasCallId;

/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoBriefCopyWith<_TodoBrief> get copyWith => __$TodoBriefCopyWithImpl<_TodoBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.hasCallId, hasCallId) || other.hasCallId == hasCallId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,itemCount,hasCallId);
}

@override
String toString() {
    return 'TodoBrief(reference: $reference, itemCount: $itemCount, hasCallId: $hasCallId)';
}


}

/// @nodoc
abstract mixin class _$TodoBriefCopyWith<$Res> implements $TodoBriefCopyWith<$Res> {
  factory _$TodoBriefCopyWith(_TodoBrief value, $Res Function(_TodoBrief) _then) = __$TodoBriefCopyWithImpl;
@override @useResult
$Res call({
 TodoReadRef reference, int itemCount, bool hasCallId
});


@override $TodoReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$TodoBriefCopyWithImpl<$Res>
    implements _$TodoBriefCopyWith<$Res> {
  __$TodoBriefCopyWithImpl(this._self, this._then);

  final _TodoBrief _self;
  final $Res Function(_TodoBrief) _then;

/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? itemCount = null,Object? hasCallId = null,}) {
  return _then(_TodoBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as TodoReadRef,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,hasCallId: null == hasCallId ? _self.hasCallId : hasCallId // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of TodoBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReadRefCopyWith<$Res> get reference {

  return $TodoReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PlanDocumentRef {

 int get version; String get contentHash;
/// Create a copy of PlanDocumentRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanDocumentRefCopyWith<PlanDocumentRef> get copyWith => _$PlanDocumentRefCopyWithImpl<PlanDocumentRef>(this as PlanDocumentRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanDocumentRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanDocumentRef&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash));
}


@override
int get hashCode {
  final _this = this as PlanDocumentRef;
  return Object.hash(runtimeType,_this.version,_this.contentHash);
}

@override
String toString() {
  final _this = this as PlanDocumentRef;
  return 'PlanDocumentRef(version: ${_this.version}, contentHash: ${_this.contentHash})';
}


}

/// @nodoc
abstract mixin class $PlanDocumentRefCopyWith<$Res>  {
  factory $PlanDocumentRefCopyWith(PlanDocumentRef value, $Res Function(PlanDocumentRef) _then) = _$PlanDocumentRefCopyWithImpl;
@useResult
$Res call({
 int version, String contentHash
});




}
/// @nodoc
class _$PlanDocumentRefCopyWithImpl<$Res>
    implements $PlanDocumentRefCopyWith<$Res> {
  _$PlanDocumentRefCopyWithImpl(this._self, this._then);

  final PlanDocumentRef _self;
  final $Res Function(PlanDocumentRef) _then;

/// Create a copy of PlanDocumentRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? contentHash = null,}) {
  return _then(PlanDocumentRef(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PlanDocumentRef].
extension PlanDocumentRefPatterns on PlanDocumentRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanDocumentRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanDocumentRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanDocumentRef value)  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanDocumentRef value)?  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int version,  String contentHash)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanDocumentRef() when $default != null:
return $default(_that.version,_that.contentHash);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int version,  String contentHash)  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentRef():
return $default(_that.version,_that.contentHash);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int version,  String contentHash)?  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentRef() when $default != null:
return $default(_that.version,_that.contentHash);case _:
  return null;

}
}

}

/// @nodoc


class _PlanDocumentRef implements PlanDocumentRef {
  const _PlanDocumentRef({required this.version, required this.contentHash});


@override final  int version;
@override final  String contentHash;

/// Create a copy of PlanDocumentRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanDocumentRefCopyWith<_PlanDocumentRef> get copyWith => __$PlanDocumentRefCopyWithImpl<_PlanDocumentRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanDocumentRef&&(identical(other.version, version) || other.version == version)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version,contentHash);
}

@override
String toString() {
    return 'PlanDocumentRef(version: $version, contentHash: $contentHash)';
}


}

/// @nodoc
abstract mixin class _$PlanDocumentRefCopyWith<$Res> implements $PlanDocumentRefCopyWith<$Res> {
  factory _$PlanDocumentRefCopyWith(_PlanDocumentRef value, $Res Function(_PlanDocumentRef) _then) = __$PlanDocumentRefCopyWithImpl;
@override @useResult
$Res call({
 int version, String contentHash
});




}
/// @nodoc
class __$PlanDocumentRefCopyWithImpl<$Res>
    implements _$PlanDocumentRefCopyWith<$Res> {
  __$PlanDocumentRefCopyWithImpl(this._self, this._then);

  final _PlanDocumentRef _self;
  final $Res Function(_PlanDocumentRef) _then;

/// Create a copy of PlanDocumentRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? contentHash = null,}) {
  return _then(_PlanDocumentRef(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PlanBrief {

 int get revision; PlanPhase get state; PlanDocumentRef? get document; int get updatedAt;
/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<PlanBrief> get copyWith => _$PlanBriefCopyWithImpl<PlanBrief>(this as PlanBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as PlanBrief;
  return Object.hash(runtimeType,_this.revision,_this.state,_this.document,_this.updatedAt);
}

@override
String toString() {
  final _this = this as PlanBrief;
  return 'PlanBrief(revision: ${_this.revision}, state: ${_this.state}, document: ${_this.document}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $PlanBriefCopyWith<$Res>  {
  factory $PlanBriefCopyWith(PlanBrief value, $Res Function(PlanBrief) _then) = _$PlanBriefCopyWithImpl;
@useResult
$Res call({
 int revision, PlanPhase state, PlanDocumentRef? document, int updatedAt
});


$PlanDocumentRefCopyWith<$Res>? get document;

}
/// @nodoc
class _$PlanBriefCopyWithImpl<$Res>
    implements $PlanBriefCopyWith<$Res> {
  _$PlanBriefCopyWithImpl(this._self, this._then);

  final PlanBrief _self;
  final $Res Function(PlanBrief) _then;

/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? state = null,Object? document = freezed,Object? updatedAt = null,}) {
  return _then(PlanBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PlanPhase,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as PlanDocumentRef?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDocumentRefCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $PlanDocumentRefCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlanBrief].
extension PlanBriefPatterns on PlanBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanBrief value)  $default,){
final _that = this;
switch (_that) {
case _PlanBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanBrief value)?  $default,){
final _that = this;
switch (_that) {
case _PlanBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  PlanPhase state,  PlanDocumentRef? document,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanBrief() when $default != null:
return $default(_that.revision,_that.state,_that.document,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  PlanPhase state,  PlanDocumentRef? document,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _PlanBrief():
return $default(_that.revision,_that.state,_that.document,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  PlanPhase state,  PlanDocumentRef? document,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _PlanBrief() when $default != null:
return $default(_that.revision,_that.state,_that.document,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _PlanBrief implements PlanBrief {
  const _PlanBrief({required this.revision, required this.state, required this.document, required this.updatedAt});


@override final  int revision;
@override final  PlanPhase state;
@override final  PlanDocumentRef? document;
@override final  int updatedAt;

/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanBriefCopyWith<_PlanBrief> get copyWith => __$PlanBriefCopyWithImpl<_PlanBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state)&&(identical(other.document, document) || other.document == document)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,state,document,updatedAt);
}

@override
String toString() {
    return 'PlanBrief(revision: $revision, state: $state, document: $document, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$PlanBriefCopyWith<$Res> implements $PlanBriefCopyWith<$Res> {
  factory _$PlanBriefCopyWith(_PlanBrief value, $Res Function(_PlanBrief) _then) = __$PlanBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, PlanPhase state, PlanDocumentRef? document, int updatedAt
});


@override $PlanDocumentRefCopyWith<$Res>? get document;

}
/// @nodoc
class __$PlanBriefCopyWithImpl<$Res>
    implements _$PlanBriefCopyWith<$Res> {
  __$PlanBriefCopyWithImpl(this._self, this._then);

  final _PlanBrief _self;
  final $Res Function(_PlanBrief) _then;

/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? state = null,Object? document = freezed,Object? updatedAt = null,}) {
  return _then(_PlanBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PlanPhase,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as PlanDocumentRef?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of PlanBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDocumentRefCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $PlanDocumentRefCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}

/// @nodoc
mixin _$WorkflowBrief {

 WorkflowReadRef get reference; int get revision; bool get hasCurrentRun; WorkflowLifecycle? get lifecycle; bool? get modeDeleted;
/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<WorkflowBrief> get copyWith => _$WorkflowBriefCopyWithImpl<WorkflowBrief>(this as WorkflowBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.hasCurrentRun, _this.hasCurrentRun) || other.hasCurrentRun == _this.hasCurrentRun)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.modeDeleted, _this.modeDeleted) || other.modeDeleted == _this.modeDeleted));
}


@override
int get hashCode {
  final _this = this as WorkflowBrief;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.hasCurrentRun,_this.lifecycle,_this.modeDeleted);
}

@override
String toString() {
  final _this = this as WorkflowBrief;
  return 'WorkflowBrief(reference: ${_this.reference}, revision: ${_this.revision}, hasCurrentRun: ${_this.hasCurrentRun}, lifecycle: ${_this.lifecycle}, modeDeleted: ${_this.modeDeleted})';
}


}

/// @nodoc
abstract mixin class $WorkflowBriefCopyWith<$Res>  {
  factory $WorkflowBriefCopyWith(WorkflowBrief value, $Res Function(WorkflowBrief) _then) = _$WorkflowBriefCopyWithImpl;
@useResult
$Res call({
 WorkflowReadRef reference, int revision, bool hasCurrentRun, WorkflowLifecycle? lifecycle, bool? modeDeleted
});


$WorkflowReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$WorkflowBriefCopyWithImpl<$Res>
    implements $WorkflowBriefCopyWith<$Res> {
  _$WorkflowBriefCopyWithImpl(this._self, this._then);

  final WorkflowBrief _self;
  final $Res Function(WorkflowBrief) _then;

/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? hasCurrentRun = null,Object? lifecycle = freezed,Object? modeDeleted = freezed,}) {
  return _then(WorkflowBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as WorkflowReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,hasCurrentRun: null == hasCurrentRun ? _self.hasCurrentRun : hasCurrentRun // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: freezed == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as WorkflowLifecycle?,modeDeleted: freezed == modeDeleted ? _self.modeDeleted : modeDeleted // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowReadRefCopyWith<$Res> get reference {

  return $WorkflowReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowBrief].
extension WorkflowBriefPatterns on WorkflowBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowBrief value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowBrief value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkflowReadRef reference,  int revision,  bool hasCurrentRun,  WorkflowLifecycle? lifecycle,  bool? modeDeleted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.hasCurrentRun,_that.lifecycle,_that.modeDeleted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkflowReadRef reference,  int revision,  bool hasCurrentRun,  WorkflowLifecycle? lifecycle,  bool? modeDeleted)  $default,) {final _that = this;
switch (_that) {
case _WorkflowBrief():
return $default(_that.reference,_that.revision,_that.hasCurrentRun,_that.lifecycle,_that.modeDeleted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkflowReadRef reference,  int revision,  bool hasCurrentRun,  WorkflowLifecycle? lifecycle,  bool? modeDeleted)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.hasCurrentRun,_that.lifecycle,_that.modeDeleted);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowBrief implements WorkflowBrief {
  const _WorkflowBrief({required this.reference, required this.revision, required this.hasCurrentRun, required this.lifecycle, required this.modeDeleted});


@override final  WorkflowReadRef reference;
@override final  int revision;
@override final  bool hasCurrentRun;
@override final  WorkflowLifecycle? lifecycle;
@override final  bool? modeDeleted;

/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowBriefCopyWith<_WorkflowBrief> get copyWith => __$WorkflowBriefCopyWithImpl<_WorkflowBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.hasCurrentRun, hasCurrentRun) || other.hasCurrentRun == hasCurrentRun)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.modeDeleted, modeDeleted) || other.modeDeleted == modeDeleted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,hasCurrentRun,lifecycle,modeDeleted);
}

@override
String toString() {
    return 'WorkflowBrief(reference: $reference, revision: $revision, hasCurrentRun: $hasCurrentRun, lifecycle: $lifecycle, modeDeleted: $modeDeleted)';
}


}

/// @nodoc
abstract mixin class _$WorkflowBriefCopyWith<$Res> implements $WorkflowBriefCopyWith<$Res> {
  factory _$WorkflowBriefCopyWith(_WorkflowBrief value, $Res Function(_WorkflowBrief) _then) = __$WorkflowBriefCopyWithImpl;
@override @useResult
$Res call({
 WorkflowReadRef reference, int revision, bool hasCurrentRun, WorkflowLifecycle? lifecycle, bool? modeDeleted
});


@override $WorkflowReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$WorkflowBriefCopyWithImpl<$Res>
    implements _$WorkflowBriefCopyWith<$Res> {
  __$WorkflowBriefCopyWithImpl(this._self, this._then);

  final _WorkflowBrief _self;
  final $Res Function(_WorkflowBrief) _then;

/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? hasCurrentRun = null,Object? lifecycle = freezed,Object? modeDeleted = freezed,}) {
  return _then(_WorkflowBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as WorkflowReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,hasCurrentRun: null == hasCurrentRun ? _self.hasCurrentRun : hasCurrentRun // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: freezed == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as WorkflowLifecycle?,modeDeleted: freezed == modeDeleted ? _self.modeDeleted : modeDeleted // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of WorkflowBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowReadRefCopyWith<$Res> get reference {

  return $WorkflowReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ThreadAuthoringBaseline {

 TodoBrief? get todo; PlanBrief? get plan; WorkflowBrief? get workflow; ThreadCapabilitySupport get progress;
/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringBaselineCopyWith<ThreadAuthoringBaseline> get copyWith => _$ThreadAuthoringBaselineCopyWithImpl<ThreadAuthoringBaseline>(this as ThreadAuthoringBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAuthoringBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringBaseline&&(identical(other.todo, _this.todo) || other.todo == _this.todo)&&(identical(other.plan, _this.plan) || other.plan == _this.plan)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow)&&(identical(other.progress, _this.progress) || other.progress == _this.progress));
}


@override
int get hashCode {
  final _this = this as ThreadAuthoringBaseline;
  return Object.hash(runtimeType,_this.todo,_this.plan,_this.workflow,_this.progress);
}

@override
String toString() {
  final _this = this as ThreadAuthoringBaseline;
  return 'ThreadAuthoringBaseline(todo: ${_this.todo}, plan: ${_this.plan}, workflow: ${_this.workflow}, progress: ${_this.progress})';
}


}

/// @nodoc
abstract mixin class $ThreadAuthoringBaselineCopyWith<$Res>  {
  factory $ThreadAuthoringBaselineCopyWith(ThreadAuthoringBaseline value, $Res Function(ThreadAuthoringBaseline) _then) = _$ThreadAuthoringBaselineCopyWithImpl;
@useResult
$Res call({
 TodoBrief? todo, PlanBrief? plan, WorkflowBrief? workflow, ThreadCapabilitySupport progress
});


$TodoBriefCopyWith<$Res>? get todo;$PlanBriefCopyWith<$Res>? get plan;$WorkflowBriefCopyWith<$Res>? get workflow;

}
/// @nodoc
class _$ThreadAuthoringBaselineCopyWithImpl<$Res>
    implements $ThreadAuthoringBaselineCopyWith<$Res> {
  _$ThreadAuthoringBaselineCopyWithImpl(this._self, this._then);

  final ThreadAuthoringBaseline _self;
  final $Res Function(ThreadAuthoringBaseline) _then;

/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? todo = freezed,Object? plan = freezed,Object? workflow = freezed,Object? progress = null,}) {
  return _then(ThreadAuthoringBaseline(
todo: freezed == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoBrief?,plan: freezed == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanBrief?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowBrief?,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,
  ));
}
/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<$Res>? get todo {
    if (_self.todo == null) {
    return null;
  }

  return $TodoBriefCopyWith<$Res>(_self.todo!, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<$Res>? get plan {
    if (_self.plan == null) {
    return null;
  }

  return $PlanBriefCopyWith<$Res>(_self.plan!, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowBriefCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadAuthoringBaseline].
extension ThreadAuthoringBaselinePatterns on ThreadAuthoringBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadAuthoringBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadAuthoringBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadAuthoringBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TodoBrief? todo,  PlanBrief? plan,  WorkflowBrief? workflow,  ThreadCapabilitySupport progress)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline() when $default != null:
return $default(_that.todo,_that.plan,_that.workflow,_that.progress);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TodoBrief? todo,  PlanBrief? plan,  WorkflowBrief? workflow,  ThreadCapabilitySupport progress)  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline():
return $default(_that.todo,_that.plan,_that.workflow,_that.progress);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TodoBrief? todo,  PlanBrief? plan,  WorkflowBrief? workflow,  ThreadCapabilitySupport progress)?  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringBaseline() when $default != null:
return $default(_that.todo,_that.plan,_that.workflow,_that.progress);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadAuthoringBaseline implements ThreadAuthoringBaseline {
  const _ThreadAuthoringBaseline({required this.todo, required this.plan, required this.workflow, required this.progress});


@override final  TodoBrief? todo;
@override final  PlanBrief? plan;
@override final  WorkflowBrief? workflow;
@override final  ThreadCapabilitySupport progress;

/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadAuthoringBaselineCopyWith<_ThreadAuthoringBaseline> get copyWith => __$ThreadAuthoringBaselineCopyWithImpl<_ThreadAuthoringBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadAuthoringBaseline&&(identical(other.todo, todo) || other.todo == todo)&&(identical(other.plan, plan) || other.plan == plan)&&(identical(other.workflow, workflow) || other.workflow == workflow)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode {
    return Object.hash(runtimeType,todo,plan,workflow,progress);
}

@override
String toString() {
    return 'ThreadAuthoringBaseline(todo: $todo, plan: $plan, workflow: $workflow, progress: $progress)';
}


}

/// @nodoc
abstract mixin class _$ThreadAuthoringBaselineCopyWith<$Res> implements $ThreadAuthoringBaselineCopyWith<$Res> {
  factory _$ThreadAuthoringBaselineCopyWith(_ThreadAuthoringBaseline value, $Res Function(_ThreadAuthoringBaseline) _then) = __$ThreadAuthoringBaselineCopyWithImpl;
@override @useResult
$Res call({
 TodoBrief? todo, PlanBrief? plan, WorkflowBrief? workflow, ThreadCapabilitySupport progress
});


@override $TodoBriefCopyWith<$Res>? get todo;@override $PlanBriefCopyWith<$Res>? get plan;@override $WorkflowBriefCopyWith<$Res>? get workflow;

}
/// @nodoc
class __$ThreadAuthoringBaselineCopyWithImpl<$Res>
    implements _$ThreadAuthoringBaselineCopyWith<$Res> {
  __$ThreadAuthoringBaselineCopyWithImpl(this._self, this._then);

  final _ThreadAuthoringBaseline _self;
  final $Res Function(_ThreadAuthoringBaseline) _then;

/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? todo = freezed,Object? plan = freezed,Object? workflow = freezed,Object? progress = null,}) {
  return _then(_ThreadAuthoringBaseline(
todo: freezed == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoBrief?,plan: freezed == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanBrief?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowBrief?,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ThreadCapabilitySupport,
  ));
}

/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<$Res>? get todo {
    if (_self.todo == null) {
    return null;
  }

  return $TodoBriefCopyWith<$Res>(_self.todo!, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<$Res>? get plan {
    if (_self.plan == null) {
    return null;
  }

  return $PlanBriefCopyWith<$Res>(_self.plan!, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of ThreadAuthoringBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowBriefCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}

/// @nodoc
mixin _$TodoReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TodoReplacement()';
}


}

/// @nodoc
class $TodoReplacementCopyWith<$Res>  {
$TodoReplacementCopyWith(TodoReplacement _, $Res Function(TodoReplacement) __);
}


/// Adds pattern-matching-related methods to [TodoReplacement].
extension TodoReplacementPatterns on TodoReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedTodo value)?  unchanged,TResult Function( ReplacedTodo value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedTodo() when unchanged != null:
return unchanged(_that);case ReplacedTodo() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedTodo value)  unchanged,required TResult Function( ReplacedTodo value)  replace,}){
final _that = this;
switch (_that) {
case UnchangedTodo():
return unchanged(_that);case ReplacedTodo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedTodo value)?  unchanged,TResult? Function( ReplacedTodo value)?  replace,}){
final _that = this;
switch (_that) {
case UnchangedTodo() when unchanged != null:
return unchanged(_that);case ReplacedTodo() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( TodoBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnchangedTodo() when unchanged != null:
return unchanged();case ReplacedTodo() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( TodoBrief? value)  replace,}) {final _that = this;
switch (_that) {
case UnchangedTodo():
return unchanged();case ReplacedTodo():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( TodoBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case UnchangedTodo() when unchanged != null:
return unchanged();case ReplacedTodo() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UnchangedTodo implements TodoReplacement {
  const UnchangedTodo();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedTodo);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TodoReplacement.unchanged()';
}


}




/// @nodoc


class ReplacedTodo implements TodoReplacement {
  const ReplacedTodo({required this.value});


 final  TodoBrief? value;

/// Create a copy of TodoReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplacedTodoCopyWith<ReplacedTodo> get copyWith => _$ReplacedTodoCopyWithImpl<ReplacedTodo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplacedTodo&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'TodoReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $ReplacedTodoCopyWith<$Res> implements $TodoReplacementCopyWith<$Res> {
  factory $ReplacedTodoCopyWith(ReplacedTodo value, $Res Function(ReplacedTodo) _then) = _$ReplacedTodoCopyWithImpl;
@useResult
$Res call({
 TodoBrief? value
});


$TodoBriefCopyWith<$Res>? get value;

}
/// @nodoc
class _$ReplacedTodoCopyWithImpl<$Res>
    implements $ReplacedTodoCopyWith<$Res> {
  _$ReplacedTodoCopyWithImpl(this._self, this._then);

  final ReplacedTodo _self;
  final $Res Function(ReplacedTodo) _then;

/// Create a copy of TodoReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(ReplacedTodo(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as TodoBrief?,
  ));
}

/// Create a copy of TodoReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $TodoBriefCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PlanReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlanReplacement()';
}


}

/// @nodoc
class $PlanReplacementCopyWith<$Res>  {
$PlanReplacementCopyWith(PlanReplacement _, $Res Function(PlanReplacement) __);
}


/// Adds pattern-matching-related methods to [PlanReplacement].
extension PlanReplacementPatterns on PlanReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedPlan value)?  unchanged,TResult Function( ReplacedPlan value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedPlan() when unchanged != null:
return unchanged(_that);case ReplacedPlan() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedPlan value)  unchanged,required TResult Function( ReplacedPlan value)  replace,}){
final _that = this;
switch (_that) {
case UnchangedPlan():
return unchanged(_that);case ReplacedPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedPlan value)?  unchanged,TResult? Function( ReplacedPlan value)?  replace,}){
final _that = this;
switch (_that) {
case UnchangedPlan() when unchanged != null:
return unchanged(_that);case ReplacedPlan() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( PlanBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnchangedPlan() when unchanged != null:
return unchanged();case ReplacedPlan() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( PlanBrief? value)  replace,}) {final _that = this;
switch (_that) {
case UnchangedPlan():
return unchanged();case ReplacedPlan():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( PlanBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case UnchangedPlan() when unchanged != null:
return unchanged();case ReplacedPlan() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UnchangedPlan implements PlanReplacement {
  const UnchangedPlan();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedPlan);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlanReplacement.unchanged()';
}


}




/// @nodoc


class ReplacedPlan implements PlanReplacement {
  const ReplacedPlan({required this.value});


 final  PlanBrief? value;

/// Create a copy of PlanReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplacedPlanCopyWith<ReplacedPlan> get copyWith => _$ReplacedPlanCopyWithImpl<ReplacedPlan>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplacedPlan&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'PlanReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $ReplacedPlanCopyWith<$Res> implements $PlanReplacementCopyWith<$Res> {
  factory $ReplacedPlanCopyWith(ReplacedPlan value, $Res Function(ReplacedPlan) _then) = _$ReplacedPlanCopyWithImpl;
@useResult
$Res call({
 PlanBrief? value
});


$PlanBriefCopyWith<$Res>? get value;

}
/// @nodoc
class _$ReplacedPlanCopyWithImpl<$Res>
    implements $ReplacedPlanCopyWith<$Res> {
  _$ReplacedPlanCopyWithImpl(this._self, this._then);

  final ReplacedPlan _self;
  final $Res Function(ReplacedPlan) _then;

/// Create a copy of PlanReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(ReplacedPlan(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlanBrief?,
  ));
}

/// Create a copy of PlanReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $PlanBriefCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$WorkflowReplacement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowReplacement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WorkflowReplacement()';
}


}

/// @nodoc
class $WorkflowReplacementCopyWith<$Res>  {
$WorkflowReplacementCopyWith(WorkflowReplacement _, $Res Function(WorkflowReplacement) __);
}


/// Adds pattern-matching-related methods to [WorkflowReplacement].
extension WorkflowReplacementPatterns on WorkflowReplacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedWorkflow value)?  unchanged,TResult Function( ReplacedWorkflow value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedWorkflow() when unchanged != null:
return unchanged(_that);case ReplacedWorkflow() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedWorkflow value)  unchanged,required TResult Function( ReplacedWorkflow value)  replace,}){
final _that = this;
switch (_that) {
case UnchangedWorkflow():
return unchanged(_that);case ReplacedWorkflow():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedWorkflow value)?  unchanged,TResult? Function( ReplacedWorkflow value)?  replace,}){
final _that = this;
switch (_that) {
case UnchangedWorkflow() when unchanged != null:
return unchanged(_that);case ReplacedWorkflow() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( WorkflowBrief? value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnchangedWorkflow() when unchanged != null:
return unchanged();case ReplacedWorkflow() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( WorkflowBrief? value)  replace,}) {final _that = this;
switch (_that) {
case UnchangedWorkflow():
return unchanged();case ReplacedWorkflow():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( WorkflowBrief? value)?  replace,}) {final _that = this;
switch (_that) {
case UnchangedWorkflow() when unchanged != null:
return unchanged();case ReplacedWorkflow() when replace != null:
return replace(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class UnchangedWorkflow implements WorkflowReplacement {
  const UnchangedWorkflow();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedWorkflow);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WorkflowReplacement.unchanged()';
}


}




/// @nodoc


class ReplacedWorkflow implements WorkflowReplacement {
  const ReplacedWorkflow({required this.value});


 final  WorkflowBrief? value;

/// Create a copy of WorkflowReplacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplacedWorkflowCopyWith<ReplacedWorkflow> get copyWith => _$ReplacedWorkflowCopyWithImpl<ReplacedWorkflow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplacedWorkflow&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'WorkflowReplacement.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $ReplacedWorkflowCopyWith<$Res> implements $WorkflowReplacementCopyWith<$Res> {
  factory $ReplacedWorkflowCopyWith(ReplacedWorkflow value, $Res Function(ReplacedWorkflow) _then) = _$ReplacedWorkflowCopyWithImpl;
@useResult
$Res call({
 WorkflowBrief? value
});


$WorkflowBriefCopyWith<$Res>? get value;

}
/// @nodoc
class _$ReplacedWorkflowCopyWithImpl<$Res>
    implements $ReplacedWorkflowCopyWith<$Res> {
  _$ReplacedWorkflowCopyWithImpl(this._self, this._then);

  final ReplacedWorkflow _self;
  final $Res Function(ReplacedWorkflow) _then;

/// Create a copy of WorkflowReplacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(ReplacedWorkflow(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkflowBrief?,
  ));
}

/// Create a copy of WorkflowReplacement
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $WorkflowBriefCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadAuthoringChange {

 TodoReplacement get todo; PlanReplacement get plan; WorkflowReplacement get workflow;
/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringChangeCopyWith<ThreadAuthoringChange> get copyWith => _$ThreadAuthoringChangeCopyWithImpl<ThreadAuthoringChange>(this as ThreadAuthoringChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAuthoringChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringChange&&(identical(other.todo, _this.todo) || other.todo == _this.todo)&&(identical(other.plan, _this.plan) || other.plan == _this.plan)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow));
}


@override
int get hashCode {
  final _this = this as ThreadAuthoringChange;
  return Object.hash(runtimeType,_this.todo,_this.plan,_this.workflow);
}

@override
String toString() {
  final _this = this as ThreadAuthoringChange;
  return 'ThreadAuthoringChange(todo: ${_this.todo}, plan: ${_this.plan}, workflow: ${_this.workflow})';
}


}

/// @nodoc
abstract mixin class $ThreadAuthoringChangeCopyWith<$Res>  {
  factory $ThreadAuthoringChangeCopyWith(ThreadAuthoringChange value, $Res Function(ThreadAuthoringChange) _then) = _$ThreadAuthoringChangeCopyWithImpl;
@useResult
$Res call({
 TodoReplacement todo, PlanReplacement plan, WorkflowReplacement workflow
});


$TodoReplacementCopyWith<$Res> get todo;$PlanReplacementCopyWith<$Res> get plan;$WorkflowReplacementCopyWith<$Res> get workflow;

}
/// @nodoc
class _$ThreadAuthoringChangeCopyWithImpl<$Res>
    implements $ThreadAuthoringChangeCopyWith<$Res> {
  _$ThreadAuthoringChangeCopyWithImpl(this._self, this._then);

  final ThreadAuthoringChange _self;
  final $Res Function(ThreadAuthoringChange) _then;

/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? todo = null,Object? plan = null,Object? workflow = null,}) {
  return _then(ThreadAuthoringChange(
todo: null == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoReplacement,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanReplacement,workflow: null == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowReplacement,
  ));
}
/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReplacementCopyWith<$Res> get todo {

  return $TodoReplacementCopyWith<$Res>(_self.todo, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanReplacementCopyWith<$Res> get plan {

  return $PlanReplacementCopyWith<$Res>(_self.plan, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowReplacementCopyWith<$Res> get workflow {

  return $WorkflowReplacementCopyWith<$Res>(_self.workflow, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadAuthoringChange].
extension ThreadAuthoringChangePatterns on ThreadAuthoringChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadAuthoringChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadAuthoringChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadAuthoringChange value)  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadAuthoringChange value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TodoReplacement todo,  PlanReplacement plan,  WorkflowReplacement workflow)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadAuthoringChange() when $default != null:
return $default(_that.todo,_that.plan,_that.workflow);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TodoReplacement todo,  PlanReplacement plan,  WorkflowReplacement workflow)  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringChange():
return $default(_that.todo,_that.plan,_that.workflow);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TodoReplacement todo,  PlanReplacement plan,  WorkflowReplacement workflow)?  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringChange() when $default != null:
return $default(_that.todo,_that.plan,_that.workflow);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadAuthoringChange implements ThreadAuthoringChange {
  const _ThreadAuthoringChange({required this.todo, required this.plan, required this.workflow});


@override final  TodoReplacement todo;
@override final  PlanReplacement plan;
@override final  WorkflowReplacement workflow;

/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadAuthoringChangeCopyWith<_ThreadAuthoringChange> get copyWith => __$ThreadAuthoringChangeCopyWithImpl<_ThreadAuthoringChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadAuthoringChange&&(identical(other.todo, todo) || other.todo == todo)&&(identical(other.plan, plan) || other.plan == plan)&&(identical(other.workflow, workflow) || other.workflow == workflow));
}


@override
int get hashCode {
    return Object.hash(runtimeType,todo,plan,workflow);
}

@override
String toString() {
    return 'ThreadAuthoringChange(todo: $todo, plan: $plan, workflow: $workflow)';
}


}

/// @nodoc
abstract mixin class _$ThreadAuthoringChangeCopyWith<$Res> implements $ThreadAuthoringChangeCopyWith<$Res> {
  factory _$ThreadAuthoringChangeCopyWith(_ThreadAuthoringChange value, $Res Function(_ThreadAuthoringChange) _then) = __$ThreadAuthoringChangeCopyWithImpl;
@override @useResult
$Res call({
 TodoReplacement todo, PlanReplacement plan, WorkflowReplacement workflow
});


@override $TodoReplacementCopyWith<$Res> get todo;@override $PlanReplacementCopyWith<$Res> get plan;@override $WorkflowReplacementCopyWith<$Res> get workflow;

}
/// @nodoc
class __$ThreadAuthoringChangeCopyWithImpl<$Res>
    implements _$ThreadAuthoringChangeCopyWith<$Res> {
  __$ThreadAuthoringChangeCopyWithImpl(this._self, this._then);

  final _ThreadAuthoringChange _self;
  final $Res Function(_ThreadAuthoringChange) _then;

/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? todo = null,Object? plan = null,Object? workflow = null,}) {
  return _then(_ThreadAuthoringChange(
todo: null == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoReplacement,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanReplacement,workflow: null == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowReplacement,
  ));
}

/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReplacementCopyWith<$Res> get todo {

  return $TodoReplacementCopyWith<$Res>(_self.todo, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanReplacementCopyWith<$Res> get plan {

  return $PlanReplacementCopyWith<$Res>(_self.plan, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of ThreadAuthoringChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowReplacementCopyWith<$Res> get workflow {

  return $WorkflowReplacementCopyWith<$Res>(_self.workflow, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}

// dart format on
