// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_costs_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionCostsReadHeader {

 SessionCostRead? get cost;
/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsReadHeaderCopyWith<SessionCostsReadHeader> get copyWith => _$SessionCostsReadHeaderCopyWithImpl<SessionCostsReadHeader>(this as SessionCostsReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsReadHeader&&(identical(other.cost, _this.cost) || other.cost == _this.cost));
}


@override
int get hashCode {
  final _this = this as SessionCostsReadHeader;
  return Object.hash(runtimeType,_this.cost);
}



}

/// @nodoc
abstract mixin class $SessionCostsReadHeaderCopyWith<$Res>  {
  factory $SessionCostsReadHeaderCopyWith(SessionCostsReadHeader value, $Res Function(SessionCostsReadHeader) _then) = _$SessionCostsReadHeaderCopyWithImpl;
@useResult
$Res call({
 SessionCostRead? cost
});


$SessionCostReadCopyWith<$Res>? get cost;

}
/// @nodoc
class _$SessionCostsReadHeaderCopyWithImpl<$Res>
    implements $SessionCostsReadHeaderCopyWith<$Res> {
  _$SessionCostsReadHeaderCopyWithImpl(this._self, this._then);

  final SessionCostsReadHeader _self;
  final $Res Function(SessionCostsReadHeader) _then;

/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cost = freezed,}) {
  return _then(SessionCostsReadHeader(
cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as SessionCostRead?,
  ));
}
/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostReadCopyWith<$Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $SessionCostReadCopyWith<$Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostsReadHeader].
extension SessionCostsReadHeaderPatterns on SessionCostsReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostsReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostsReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostsReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostsReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionCostRead? cost)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCostsReadHeader() when $default != null:
return $default(_that.cost);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionCostRead? cost)  $default,) {final _that = this;
switch (_that) {
case _SessionCostsReadHeader():
return $default(_that.cost);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionCostRead? cost)?  $default,) {final _that = this;
switch (_that) {
case _SessionCostsReadHeader() when $default != null:
return $default(_that.cost);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostsReadHeader implements SessionCostsReadHeader {
  const _SessionCostsReadHeader({required this.cost});


@override final  SessionCostRead? cost;

/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostsReadHeaderCopyWith<_SessionCostsReadHeader> get copyWith => __$SessionCostsReadHeaderCopyWithImpl<_SessionCostsReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostsReadHeader&&(identical(other.cost, cost) || other.cost == cost));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cost);
}



}

/// @nodoc
abstract mixin class _$SessionCostsReadHeaderCopyWith<$Res> implements $SessionCostsReadHeaderCopyWith<$Res> {
  factory _$SessionCostsReadHeaderCopyWith(_SessionCostsReadHeader value, $Res Function(_SessionCostsReadHeader) _then) = __$SessionCostsReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 SessionCostRead? cost
});


@override $SessionCostReadCopyWith<$Res>? get cost;

}
/// @nodoc
class __$SessionCostsReadHeaderCopyWithImpl<$Res>
    implements _$SessionCostsReadHeaderCopyWith<$Res> {
  __$SessionCostsReadHeaderCopyWithImpl(this._self, this._then);

  final _SessionCostsReadHeader _self;
  final $Res Function(_SessionCostsReadHeader) _then;

/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cost = freezed,}) {
  return _then(_SessionCostsReadHeader(
cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as SessionCostRead?,
  ));
}

/// Create a copy of SessionCostsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostReadCopyWith<$Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $SessionCostReadCopyWith<$Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}
}

/// @nodoc
mixin _$SessionCostRead {

 ReadText get rootThreadId; TypedListRef get purposeCosts; TypedListRef get estimatedCosts; bool get hasUnpricedUsage;
/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostReadCopyWith<SessionCostRead> get copyWith => _$SessionCostReadCopyWithImpl<SessionCostRead>(this as SessionCostRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostRead&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.purposeCosts, _this.purposeCosts) || other.purposeCosts == _this.purposeCosts)&&(identical(other.estimatedCosts, _this.estimatedCosts) || other.estimatedCosts == _this.estimatedCosts)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage));
}


@override
int get hashCode {
  final _this = this as SessionCostRead;
  return Object.hash(runtimeType,_this.rootThreadId,_this.purposeCosts,_this.estimatedCosts,_this.hasUnpricedUsage);
}



}

/// @nodoc
abstract mixin class $SessionCostReadCopyWith<$Res>  {
  factory $SessionCostReadCopyWith(SessionCostRead value, $Res Function(SessionCostRead) _then) = _$SessionCostReadCopyWithImpl;
@useResult
$Res call({
 ReadText rootThreadId, TypedListRef purposeCosts, TypedListRef estimatedCosts, bool hasUnpricedUsage
});


$ReadTextCopyWith<$Res> get rootThreadId;$TypedListRefCopyWith<$Res> get purposeCosts;$TypedListRefCopyWith<$Res> get estimatedCosts;

}
/// @nodoc
class _$SessionCostReadCopyWithImpl<$Res>
    implements $SessionCostReadCopyWith<$Res> {
  _$SessionCostReadCopyWithImpl(this._self, this._then);

  final SessionCostRead _self;
  final $Res Function(SessionCostRead) _then;

/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rootThreadId = null,Object? purposeCosts = null,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(SessionCostRead(
rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,purposeCosts: null == purposeCosts ? _self.purposeCosts : purposeCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get purposeCosts {

  return $TypedListRefCopyWith<$Res>(_self.purposeCosts, (value) {
    return _then(_self.copyWith(purposeCosts: value));
  });
}/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get estimatedCosts {

  return $TypedListRefCopyWith<$Res>(_self.estimatedCosts, (value) {
    return _then(_self.copyWith(estimatedCosts: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostRead].
extension SessionCostReadPatterns on SessionCostRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostRead value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostRead value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText rootThreadId,  TypedListRef purposeCosts,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCostRead() when $default != null:
return $default(_that.rootThreadId,_that.purposeCosts,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText rootThreadId,  TypedListRef purposeCosts,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)  $default,) {final _that = this;
switch (_that) {
case _SessionCostRead():
return $default(_that.rootThreadId,_that.purposeCosts,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText rootThreadId,  TypedListRef purposeCosts,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)?  $default,) {final _that = this;
switch (_that) {
case _SessionCostRead() when $default != null:
return $default(_that.rootThreadId,_that.purposeCosts,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostRead implements SessionCostRead {
  const _SessionCostRead({required this.rootThreadId, required this.purposeCosts, required this.estimatedCosts, required this.hasUnpricedUsage});


@override final  ReadText rootThreadId;
@override final  TypedListRef purposeCosts;
@override final  TypedListRef estimatedCosts;
@override final  bool hasUnpricedUsage;

/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostReadCopyWith<_SessionCostRead> get copyWith => __$SessionCostReadCopyWithImpl<_SessionCostRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostRead&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.purposeCosts, purposeCosts) || other.purposeCosts == purposeCosts)&&(identical(other.estimatedCosts, estimatedCosts) || other.estimatedCosts == estimatedCosts)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,rootThreadId,purposeCosts,estimatedCosts,hasUnpricedUsage);
}



}

/// @nodoc
abstract mixin class _$SessionCostReadCopyWith<$Res> implements $SessionCostReadCopyWith<$Res> {
  factory _$SessionCostReadCopyWith(_SessionCostRead value, $Res Function(_SessionCostRead) _then) = __$SessionCostReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText rootThreadId, TypedListRef purposeCosts, TypedListRef estimatedCosts, bool hasUnpricedUsage
});


@override $ReadTextCopyWith<$Res> get rootThreadId;@override $TypedListRefCopyWith<$Res> get purposeCosts;@override $TypedListRefCopyWith<$Res> get estimatedCosts;

}
/// @nodoc
class __$SessionCostReadCopyWithImpl<$Res>
    implements _$SessionCostReadCopyWith<$Res> {
  __$SessionCostReadCopyWithImpl(this._self, this._then);

  final _SessionCostRead _self;
  final $Res Function(_SessionCostRead) _then;

/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rootThreadId = null,Object? purposeCosts = null,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(_SessionCostRead(
rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,purposeCosts: null == purposeCosts ? _self.purposeCosts : purposeCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get purposeCosts {

  return $TypedListRefCopyWith<$Res>(_self.purposeCosts, (value) {
    return _then(_self.copyWith(purposeCosts: value));
  });
}/// Create a copy of SessionCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get estimatedCosts {

  return $TypedListRefCopyWith<$Res>(_self.estimatedCosts, (value) {
    return _then(_self.copyWith(estimatedCosts: value));
  });
}
}

/// @nodoc
mixin _$PurposeCostRead {

 ReadText? get purpose; TypedListRef get estimatedCosts; bool get hasUnpricedUsage;
/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurposeCostReadCopyWith<PurposeCostRead> get copyWith => _$PurposeCostReadCopyWithImpl<PurposeCostRead>(this as PurposeCostRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PurposeCostRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurposeCostRead&&(identical(other.purpose, _this.purpose) || other.purpose == _this.purpose)&&(identical(other.estimatedCosts, _this.estimatedCosts) || other.estimatedCosts == _this.estimatedCosts)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage));
}


@override
int get hashCode {
  final _this = this as PurposeCostRead;
  return Object.hash(runtimeType,_this.purpose,_this.estimatedCosts,_this.hasUnpricedUsage);
}



}

/// @nodoc
abstract mixin class $PurposeCostReadCopyWith<$Res>  {
  factory $PurposeCostReadCopyWith(PurposeCostRead value, $Res Function(PurposeCostRead) _then) = _$PurposeCostReadCopyWithImpl;
@useResult
$Res call({
 ReadText? purpose, TypedListRef estimatedCosts, bool hasUnpricedUsage
});


$ReadTextCopyWith<$Res>? get purpose;$TypedListRefCopyWith<$Res> get estimatedCosts;

}
/// @nodoc
class _$PurposeCostReadCopyWithImpl<$Res>
    implements $PurposeCostReadCopyWith<$Res> {
  _$PurposeCostReadCopyWithImpl(this._self, this._then);

  final PurposeCostRead _self;
  final $Res Function(PurposeCostRead) _then;

/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? purpose = freezed,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(PurposeCostRead(
purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as ReadText?,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get purpose {
    if (_self.purpose == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.purpose!, (value) {
    return _then(_self.copyWith(purpose: value));
  });
}/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get estimatedCosts {

  return $TypedListRefCopyWith<$Res>(_self.estimatedCosts, (value) {
    return _then(_self.copyWith(estimatedCosts: value));
  });
}
}


/// Adds pattern-matching-related methods to [PurposeCostRead].
extension PurposeCostReadPatterns on PurposeCostRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurposeCostRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurposeCostRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurposeCostRead value)  $default,){
final _that = this;
switch (_that) {
case _PurposeCostRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurposeCostRead value)?  $default,){
final _that = this;
switch (_that) {
case _PurposeCostRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText? purpose,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurposeCostRead() when $default != null:
return $default(_that.purpose,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText? purpose,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)  $default,) {final _that = this;
switch (_that) {
case _PurposeCostRead():
return $default(_that.purpose,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText? purpose,  TypedListRef estimatedCosts,  bool hasUnpricedUsage)?  $default,) {final _that = this;
switch (_that) {
case _PurposeCostRead() when $default != null:
return $default(_that.purpose,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
  return null;

}
}

}

/// @nodoc


class _PurposeCostRead implements PurposeCostRead {
  const _PurposeCostRead({required this.purpose, required this.estimatedCosts, required this.hasUnpricedUsage});


@override final  ReadText? purpose;
@override final  TypedListRef estimatedCosts;
@override final  bool hasUnpricedUsage;

/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurposeCostReadCopyWith<_PurposeCostRead> get copyWith => __$PurposeCostReadCopyWithImpl<_PurposeCostRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurposeCostRead&&(identical(other.purpose, purpose) || other.purpose == purpose)&&(identical(other.estimatedCosts, estimatedCosts) || other.estimatedCosts == estimatedCosts)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,purpose,estimatedCosts,hasUnpricedUsage);
}



}

/// @nodoc
abstract mixin class _$PurposeCostReadCopyWith<$Res> implements $PurposeCostReadCopyWith<$Res> {
  factory _$PurposeCostReadCopyWith(_PurposeCostRead value, $Res Function(_PurposeCostRead) _then) = __$PurposeCostReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText? purpose, TypedListRef estimatedCosts, bool hasUnpricedUsage
});


@override $ReadTextCopyWith<$Res>? get purpose;@override $TypedListRefCopyWith<$Res> get estimatedCosts;

}
/// @nodoc
class __$PurposeCostReadCopyWithImpl<$Res>
    implements _$PurposeCostReadCopyWith<$Res> {
  __$PurposeCostReadCopyWithImpl(this._self, this._then);

  final _PurposeCostRead _self;
  final $Res Function(_PurposeCostRead) _then;

/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? purpose = freezed,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(_PurposeCostRead(
purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as ReadText?,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as TypedListRef,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get purpose {
    if (_self.purpose == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.purpose!, (value) {
    return _then(_self.copyWith(purpose: value));
  });
}/// Create a copy of PurposeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get estimatedCosts {

  return $TypedListRefCopyWith<$Res>(_self.estimatedCosts, (value) {
    return _then(_self.copyWith(estimatedCosts: value));
  });
}
}

/// @nodoc
mixin _$RuntimeCostRead {

 ReadText get currency; double get amount;
/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeCostReadCopyWith<RuntimeCostRead> get copyWith => _$RuntimeCostReadCopyWithImpl<RuntimeCostRead>(this as RuntimeCostRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeCostRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeCostRead&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.amount, _this.amount) || other.amount == _this.amount));
}


@override
int get hashCode {
  final _this = this as RuntimeCostRead;
  return Object.hash(runtimeType,_this.currency,_this.amount);
}



}

/// @nodoc
abstract mixin class $RuntimeCostReadCopyWith<$Res>  {
  factory $RuntimeCostReadCopyWith(RuntimeCostRead value, $Res Function(RuntimeCostRead) _then) = _$RuntimeCostReadCopyWithImpl;
@useResult
$Res call({
 ReadText currency, double amount
});


$ReadTextCopyWith<$Res> get currency;

}
/// @nodoc
class _$RuntimeCostReadCopyWithImpl<$Res>
    implements $RuntimeCostReadCopyWith<$Res> {
  _$RuntimeCostReadCopyWithImpl(this._self, this._then);

  final RuntimeCostRead _self;
  final $Res Function(RuntimeCostRead) _then;

/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? amount = null,}) {
  return _then(RuntimeCostRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}
/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}
}


/// Adds pattern-matching-related methods to [RuntimeCostRead].
extension RuntimeCostReadPatterns on RuntimeCostRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeCostRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeCostRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeCostRead value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeCostRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeCostRead value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeCostRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText currency,  double amount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeCostRead() when $default != null:
return $default(_that.currency,_that.amount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText currency,  double amount)  $default,) {final _that = this;
switch (_that) {
case _RuntimeCostRead():
return $default(_that.currency,_that.amount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText currency,  double amount)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeCostRead() when $default != null:
return $default(_that.currency,_that.amount);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeCostRead implements RuntimeCostRead {
  const _RuntimeCostRead({required this.currency, required this.amount});


@override final  ReadText currency;
@override final  double amount;

/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeCostReadCopyWith<_RuntimeCostRead> get copyWith => __$RuntimeCostReadCopyWithImpl<_RuntimeCostRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeCostRead&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,amount);
}



}

/// @nodoc
abstract mixin class _$RuntimeCostReadCopyWith<$Res> implements $RuntimeCostReadCopyWith<$Res> {
  factory _$RuntimeCostReadCopyWith(_RuntimeCostRead value, $Res Function(_RuntimeCostRead) _then) = __$RuntimeCostReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText currency, double amount
});


@override $ReadTextCopyWith<$Res> get currency;

}
/// @nodoc
class __$RuntimeCostReadCopyWithImpl<$Res>
    implements _$RuntimeCostReadCopyWith<$Res> {
  __$RuntimeCostReadCopyWithImpl(this._self, this._then);

  final _RuntimeCostRead _self;
  final $Res Function(_RuntimeCostRead) _then;

/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? amount = null,}) {
  return _then(_RuntimeCostRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

/// Create a copy of RuntimeCostRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}
}

/// @nodoc
mixin _$PurposeCostReadPage {

 int get listId; int get offset; int get total; List<PurposeCostRead> get items; int? get nextOffset;
/// Create a copy of PurposeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurposeCostReadPageCopyWith<PurposeCostReadPage> get copyWith => _$PurposeCostReadPageCopyWithImpl<PurposeCostReadPage>(this as PurposeCostReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PurposeCostReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurposeCostReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PurposeCostReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $PurposeCostReadPageCopyWith<$Res>  {
  factory $PurposeCostReadPageCopyWith(PurposeCostReadPage value, $Res Function(PurposeCostReadPage) _then) = _$PurposeCostReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<PurposeCostRead> items, int? nextOffset
});




}
/// @nodoc
class _$PurposeCostReadPageCopyWithImpl<$Res>
    implements $PurposeCostReadPageCopyWith<$Res> {
  _$PurposeCostReadPageCopyWithImpl(this._self, this._then);

  final PurposeCostReadPage _self;
  final $Res Function(PurposeCostReadPage) _then;

/// Create a copy of PurposeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PurposeCostReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PurposeCostRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PurposeCostReadPage].
extension PurposeCostReadPagePatterns on PurposeCostReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurposeCostReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurposeCostReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurposeCostReadPage value)  $default,){
final _that = this;
switch (_that) {
case _PurposeCostReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurposeCostReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _PurposeCostReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PurposeCostRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurposeCostReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PurposeCostRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PurposeCostReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<PurposeCostRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PurposeCostReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PurposeCostReadPage implements PurposeCostReadPage {
  const _PurposeCostReadPage({required this.listId, required this.offset, required this.total, required  List<PurposeCostRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<PurposeCostRead> _items;
@override List<PurposeCostRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PurposeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurposeCostReadPageCopyWith<_PurposeCostReadPage> get copyWith => __$PurposeCostReadPageCopyWithImpl<_PurposeCostReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurposeCostReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$PurposeCostReadPageCopyWith<$Res> implements $PurposeCostReadPageCopyWith<$Res> {
  factory _$PurposeCostReadPageCopyWith(_PurposeCostReadPage value, $Res Function(_PurposeCostReadPage) _then) = __$PurposeCostReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<PurposeCostRead> items, int? nextOffset
});




}
/// @nodoc
class __$PurposeCostReadPageCopyWithImpl<$Res>
    implements _$PurposeCostReadPageCopyWith<$Res> {
  __$PurposeCostReadPageCopyWithImpl(this._self, this._then);

  final _PurposeCostReadPage _self;
  final $Res Function(_PurposeCostReadPage) _then;

/// Create a copy of PurposeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PurposeCostReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PurposeCostRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$RuntimeCostReadPage {

 int get listId; int get offset; int get total; List<RuntimeCostRead> get items; int? get nextOffset;
/// Create a copy of RuntimeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeCostReadPageCopyWith<RuntimeCostReadPage> get copyWith => _$RuntimeCostReadPageCopyWithImpl<RuntimeCostReadPage>(this as RuntimeCostReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeCostReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeCostReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as RuntimeCostReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $RuntimeCostReadPageCopyWith<$Res>  {
  factory $RuntimeCostReadPageCopyWith(RuntimeCostReadPage value, $Res Function(RuntimeCostReadPage) _then) = _$RuntimeCostReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<RuntimeCostRead> items, int? nextOffset
});




}
/// @nodoc
class _$RuntimeCostReadPageCopyWithImpl<$Res>
    implements $RuntimeCostReadPageCopyWith<$Res> {
  _$RuntimeCostReadPageCopyWithImpl(this._self, this._then);

  final RuntimeCostReadPage _self;
  final $Res Function(RuntimeCostReadPage) _then;

/// Create a copy of RuntimeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(RuntimeCostReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<RuntimeCostRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeCostReadPage].
extension RuntimeCostReadPagePatterns on RuntimeCostReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeCostReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeCostReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeCostReadPage value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeCostReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeCostReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeCostReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<RuntimeCostRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeCostReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<RuntimeCostRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _RuntimeCostReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<RuntimeCostRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeCostReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeCostReadPage implements RuntimeCostReadPage {
  const _RuntimeCostReadPage({required this.listId, required this.offset, required this.total, required  List<RuntimeCostRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<RuntimeCostRead> _items;
@override List<RuntimeCostRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of RuntimeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeCostReadPageCopyWith<_RuntimeCostReadPage> get copyWith => __$RuntimeCostReadPageCopyWithImpl<_RuntimeCostReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeCostReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$RuntimeCostReadPageCopyWith<$Res> implements $RuntimeCostReadPageCopyWith<$Res> {
  factory _$RuntimeCostReadPageCopyWith(_RuntimeCostReadPage value, $Res Function(_RuntimeCostReadPage) _then) = __$RuntimeCostReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<RuntimeCostRead> items, int? nextOffset
});




}
/// @nodoc
class __$RuntimeCostReadPageCopyWithImpl<$Res>
    implements _$RuntimeCostReadPageCopyWith<$Res> {
  __$RuntimeCostReadPageCopyWithImpl(this._self, this._then);

  final _RuntimeCostReadPage _self;
  final $Res Function(_RuntimeCostReadPage) _then;

/// Create a copy of RuntimeCostReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_RuntimeCostReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<RuntimeCostRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
