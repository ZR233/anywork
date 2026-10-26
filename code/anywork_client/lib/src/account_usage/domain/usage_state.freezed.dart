// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usage_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageReadRef {

 int get entry; int get revision;
/// Create a copy of AccountUsageReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageReadRefCopyWith<AccountUsageReadRef> get copyWith => _$AccountUsageReadRefCopyWithImpl<AccountUsageReadRef>(this as AccountUsageReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as AccountUsageReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as AccountUsageReadRef;
  return 'AccountUsageReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $AccountUsageReadRefCopyWith<$Res>  {
  factory $AccountUsageReadRefCopyWith(AccountUsageReadRef value, $Res Function(AccountUsageReadRef) _then) = _$AccountUsageReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$AccountUsageReadRefCopyWithImpl<$Res>
    implements $AccountUsageReadRefCopyWith<$Res> {
  _$AccountUsageReadRefCopyWithImpl(this._self, this._then);

  final AccountUsageReadRef _self;
  final $Res Function(AccountUsageReadRef) _then;

/// Create a copy of AccountUsageReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(AccountUsageReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountUsageReadRef].
extension AccountUsageReadRefPatterns on AccountUsageReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageReadRef value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadRef() when $default != null:
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
case _AccountUsageReadRef() when $default != null:
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
case _AccountUsageReadRef():
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
case _AccountUsageReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageReadRef implements AccountUsageReadRef {
  const _AccountUsageReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of AccountUsageReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageReadRefCopyWith<_AccountUsageReadRef> get copyWith => __$AccountUsageReadRefCopyWithImpl<_AccountUsageReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'AccountUsageReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageReadRefCopyWith<$Res> implements $AccountUsageReadRefCopyWith<$Res> {
  factory _$AccountUsageReadRefCopyWith(_AccountUsageReadRef value, $Res Function(_AccountUsageReadRef) _then) = __$AccountUsageReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$AccountUsageReadRefCopyWithImpl<$Res>
    implements _$AccountUsageReadRefCopyWith<$Res> {
  __$AccountUsageReadRefCopyWithImpl(this._self, this._then);

  final _AccountUsageReadRef _self;
  final $Res Function(_AccountUsageReadRef) _then;

/// Create a copy of AccountUsageReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_AccountUsageReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AccountUsageReadTarget {

 ProductReadOrigin get origin; AccountUsageReadRef get reference;
/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageReadTargetCopyWith<AccountUsageReadTarget> get copyWith => _$AccountUsageReadTargetCopyWithImpl<AccountUsageReadTarget>(this as AccountUsageReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AccountUsageReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as AccountUsageReadTarget;
  return 'AccountUsageReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AccountUsageReadTargetCopyWith<$Res>  {
  factory $AccountUsageReadTargetCopyWith(AccountUsageReadTarget value, $Res Function(AccountUsageReadTarget) _then) = _$AccountUsageReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, AccountUsageReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$AccountUsageReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AccountUsageReadTargetCopyWithImpl<$Res>
    implements $AccountUsageReadTargetCopyWith<$Res> {
  _$AccountUsageReadTargetCopyWithImpl(this._self, this._then);

  final AccountUsageReadTarget _self;
  final $Res Function(AccountUsageReadTarget) _then;

/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(AccountUsageReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountUsageReadRef,
  ));
}
/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadRefCopyWith<$Res> get reference {

  return $AccountUsageReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageReadTarget].
extension AccountUsageReadTargetPatterns on AccountUsageReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AccountUsageReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AccountUsageReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  AccountUsageReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageReadTarget implements AccountUsageReadTarget {
  const _AccountUsageReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  AccountUsageReadRef reference;

/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageReadTargetCopyWith<_AccountUsageReadTarget> get copyWith => __$AccountUsageReadTargetCopyWithImpl<_AccountUsageReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'AccountUsageReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageReadTargetCopyWith<$Res> implements $AccountUsageReadTargetCopyWith<$Res> {
  factory _$AccountUsageReadTargetCopyWith(_AccountUsageReadTarget value, $Res Function(_AccountUsageReadTarget) _then) = __$AccountUsageReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, AccountUsageReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $AccountUsageReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AccountUsageReadTargetCopyWithImpl<$Res>
    implements _$AccountUsageReadTargetCopyWith<$Res> {
  __$AccountUsageReadTargetCopyWithImpl(this._self, this._then);

  final _AccountUsageReadTarget _self;
  final $Res Function(_AccountUsageReadTarget) _then;

/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_AccountUsageReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountUsageReadRef,
  ));
}

/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AccountUsageReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadRefCopyWith<$Res> get reference {

  return $AccountUsageReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageHeader {

 ObservedHeader get source; AccountUsageReadRef? get reference;
/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageHeaderCopyWith<AccountUsageHeader> get copyWith => _$AccountUsageHeaderCopyWithImpl<AccountUsageHeader>(this as AccountUsageHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AccountUsageHeader;
  return Object.hash(runtimeType,_this.source,_this.reference);
}

@override
String toString() {
  final _this = this as AccountUsageHeader;
  return 'AccountUsageHeader(source: ${_this.source}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AccountUsageHeaderCopyWith<$Res>  {
  factory $AccountUsageHeaderCopyWith(AccountUsageHeader value, $Res Function(AccountUsageHeader) _then) = _$AccountUsageHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, AccountUsageReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$AccountUsageReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$AccountUsageHeaderCopyWithImpl<$Res>
    implements $AccountUsageHeaderCopyWith<$Res> {
  _$AccountUsageHeaderCopyWithImpl(this._self, this._then);

  final AccountUsageHeader _self;
  final $Res Function(AccountUsageHeader) _then;

/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(AccountUsageHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountUsageReadRef?,
  ));
}
/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AccountUsageReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageHeader].
extension AccountUsageHeaderPatterns on AccountUsageHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageHeader value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  AccountUsageReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  AccountUsageReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  AccountUsageReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageHeader() when $default != null:
return $default(_that.source,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageHeader implements AccountUsageHeader {
  const _AccountUsageHeader({required this.source, required this.reference});


@override final  ObservedHeader source;
@override final  AccountUsageReadRef? reference;

/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageHeaderCopyWith<_AccountUsageHeader> get copyWith => __$AccountUsageHeaderCopyWithImpl<_AccountUsageHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,reference);
}

@override
String toString() {
    return 'AccountUsageHeader(source: $source, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageHeaderCopyWith<$Res> implements $AccountUsageHeaderCopyWith<$Res> {
  factory _$AccountUsageHeaderCopyWith(_AccountUsageHeader value, $Res Function(_AccountUsageHeader) _then) = __$AccountUsageHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, AccountUsageReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $AccountUsageReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$AccountUsageHeaderCopyWithImpl<$Res>
    implements _$AccountUsageHeaderCopyWith<$Res> {
  __$AccountUsageHeaderCopyWithImpl(this._self, this._then);

  final _AccountUsageHeader _self;
  final $Res Function(_AccountUsageHeader) _then;

/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? reference = freezed,}) {
  return _then(_AccountUsageHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountUsageReadRef?,
  ));
}

/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountUsageHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AccountUsageReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageState {

 ProductProjection<AccountUsageHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<AccountUsageRecord> get usages; ReadValue<String, AccountUsageReadRef>? get configFingerprint;
/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageStateCopyWith<AccountUsageState> get copyWith => _$AccountUsageStateCopyWithImpl<AccountUsageState>(this as AccountUsageState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.usages, _this.usages) || other.usages == _this.usages)&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint));
}


@override
int get hashCode {
  final _this = this as AccountUsageState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.usages,_this.configFingerprint);
}



}

/// @nodoc
abstract mixin class $AccountUsageStateCopyWith<$Res>  {
  factory $AccountUsageStateCopyWith(AccountUsageState value, $Res Function(AccountUsageState) _then) = _$AccountUsageStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<AccountUsageHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AccountUsageRecord> usages, ReadValue<String, AccountUsageReadRef>? configFingerprint
});


$ProductProjectionCopyWith<AccountUsageHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<AccountUsageRecord, $Res> get usages;$ReadValueCopyWith<String, AccountUsageReadRef, $Res>? get configFingerprint;

}
/// @nodoc
class _$AccountUsageStateCopyWithImpl<$Res>
    implements $AccountUsageStateCopyWith<$Res> {
  _$AccountUsageStateCopyWithImpl(this._self, this._then);

  final AccountUsageState _self;
  final $Res Function(AccountUsageState) _then;

/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? usages = null,Object? configFingerprint = freezed,}) {
  return _then(AccountUsageState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AccountUsageHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,usages: null == usages ? _self.usages : usages // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountUsageRecord>,configFingerprint: freezed == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, AccountUsageReadRef>?,
  ));
}
/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AccountUsageHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AccountUsageHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AccountUsageState
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
}/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountUsageRecord, $Res> get usages {

  return $CollectionMirrorCopyWith<AccountUsageRecord, $Res>(_self.usages, (value) {
    return _then(_self.copyWith(usages: value));
  });
}/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, AccountUsageReadRef, $Res>? get configFingerprint {
    if (_self.configFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, AccountUsageReadRef, $Res>(_self.configFingerprint!, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageState].
extension AccountUsageStatePatterns on AccountUsageState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageState value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<AccountUsageHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountUsageRecord> usages,  ReadValue<String, AccountUsageReadRef>? configFingerprint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.usages,_that.configFingerprint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<AccountUsageHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountUsageRecord> usages,  ReadValue<String, AccountUsageReadRef>? configFingerprint)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageState():
return $default(_that.projection,_that.sourceStatus,_that.usages,_that.configFingerprint);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<AccountUsageHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountUsageRecord> usages,  ReadValue<String, AccountUsageReadRef>? configFingerprint)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.usages,_that.configFingerprint);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageState implements AccountUsageState {
  const _AccountUsageState({required this.projection, required this.sourceStatus, required this.usages, required this.configFingerprint});


@override final  ProductProjection<AccountUsageHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<AccountUsageRecord> usages;
@override final  ReadValue<String, AccountUsageReadRef>? configFingerprint;

/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageStateCopyWith<_AccountUsageState> get copyWith => __$AccountUsageStateCopyWithImpl<_AccountUsageState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.usages, usages) || other.usages == usages)&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,usages,configFingerprint);
}



}

/// @nodoc
abstract mixin class _$AccountUsageStateCopyWith<$Res> implements $AccountUsageStateCopyWith<$Res> {
  factory _$AccountUsageStateCopyWith(_AccountUsageState value, $Res Function(_AccountUsageState) _then) = __$AccountUsageStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<AccountUsageHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AccountUsageRecord> usages, ReadValue<String, AccountUsageReadRef>? configFingerprint
});


@override $ProductProjectionCopyWith<AccountUsageHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<AccountUsageRecord, $Res> get usages;@override $ReadValueCopyWith<String, AccountUsageReadRef, $Res>? get configFingerprint;

}
/// @nodoc
class __$AccountUsageStateCopyWithImpl<$Res>
    implements _$AccountUsageStateCopyWith<$Res> {
  __$AccountUsageStateCopyWithImpl(this._self, this._then);

  final _AccountUsageState _self;
  final $Res Function(_AccountUsageState) _then;

/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? usages = null,Object? configFingerprint = freezed,}) {
  return _then(_AccountUsageState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AccountUsageHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,usages: null == usages ? _self.usages : usages // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountUsageRecord>,configFingerprint: freezed == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadValue<String, AccountUsageReadRef>?,
  ));
}

/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AccountUsageHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AccountUsageHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AccountUsageState
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
}/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountUsageRecord, $Res> get usages {

  return $CollectionMirrorCopyWith<AccountUsageRecord, $Res>(_self.usages, (value) {
    return _then(_self.copyWith(usages: value));
  });
}/// Create a copy of AccountUsageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, AccountUsageReadRef, $Res>? get configFingerprint {
    if (_self.configFingerprint == null) {
    return null;
  }

  return $ReadValueCopyWith<String, AccountUsageReadRef, $Res>(_self.configFingerprint!, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}
}

// dart format on
