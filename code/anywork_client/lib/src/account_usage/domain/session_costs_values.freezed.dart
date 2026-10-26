// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_costs_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionCost {

 String get rootThreadId; List<PurposeCost> get purposeCosts; List<RuntimeCost> get estimatedCosts; bool get hasUnpricedUsage;
/// Create a copy of SessionCost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostCopyWith<SessionCost> get copyWith => _$SessionCostCopyWithImpl<SessionCost>(this as SessionCost, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCost;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCost&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&const DeepCollectionEquality().equals(other.purposeCosts, _this.purposeCosts)&&const DeepCollectionEquality().equals(other.estimatedCosts, _this.estimatedCosts)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage));
}


@override
int get hashCode {
  final _this = this as SessionCost;
  return Object.hash(runtimeType,_this.rootThreadId,const DeepCollectionEquality().hash(_this.purposeCosts),const DeepCollectionEquality().hash(_this.estimatedCosts),_this.hasUnpricedUsage);
}

@override
String toString() {
  final _this = this as SessionCost;
  return 'SessionCost(rootThreadId: ${_this.rootThreadId}, purposeCosts: ${_this.purposeCosts}, estimatedCosts: ${_this.estimatedCosts}, hasUnpricedUsage: ${_this.hasUnpricedUsage})';
}


}

/// @nodoc
abstract mixin class $SessionCostCopyWith<$Res>  {
  factory $SessionCostCopyWith(SessionCost value, $Res Function(SessionCost) _then) = _$SessionCostCopyWithImpl;
@useResult
$Res call({
 String rootThreadId, List<PurposeCost> purposeCosts, List<RuntimeCost> estimatedCosts, bool hasUnpricedUsage
});




}
/// @nodoc
class _$SessionCostCopyWithImpl<$Res>
    implements $SessionCostCopyWith<$Res> {
  _$SessionCostCopyWithImpl(this._self, this._then);

  final SessionCost _self;
  final $Res Function(SessionCost) _then;

/// Create a copy of SessionCost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rootThreadId = null,Object? purposeCosts = null,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(SessionCost(
rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,purposeCosts: null == purposeCosts ? _self.purposeCosts : purposeCosts // ignore: cast_nullable_to_non_nullable
as List<PurposeCost>,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as List<RuntimeCost>,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionCost].
extension SessionCostPatterns on SessionCost {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCost value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCost() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCost value)  $default,){
final _that = this;
switch (_that) {
case _SessionCost():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCost value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCost() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String rootThreadId,  List<PurposeCost> purposeCosts,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCost() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String rootThreadId,  List<PurposeCost> purposeCosts,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)  $default,) {final _that = this;
switch (_that) {
case _SessionCost():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String rootThreadId,  List<PurposeCost> purposeCosts,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)?  $default,) {final _that = this;
switch (_that) {
case _SessionCost() when $default != null:
return $default(_that.rootThreadId,_that.purposeCosts,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCost implements SessionCost {
  const _SessionCost({required this.rootThreadId, required  List<PurposeCost> purposeCosts, required  List<RuntimeCost> estimatedCosts, required this.hasUnpricedUsage}): _purposeCosts = purposeCosts,_estimatedCosts = estimatedCosts;


@override final  String rootThreadId;
 final  List<PurposeCost> _purposeCosts;
@override List<PurposeCost> get purposeCosts {
  if (_purposeCosts is EqualUnmodifiableListView) return _purposeCosts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_purposeCosts);
}

 final  List<RuntimeCost> _estimatedCosts;
@override List<RuntimeCost> get estimatedCosts {
  if (_estimatedCosts is EqualUnmodifiableListView) return _estimatedCosts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_estimatedCosts);
}

@override final  bool hasUnpricedUsage;

/// Create a copy of SessionCost
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostCopyWith<_SessionCost> get copyWith => __$SessionCostCopyWithImpl<_SessionCost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCost&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&const DeepCollectionEquality().equals(other.purposeCosts, _purposeCosts)&&const DeepCollectionEquality().equals(other.estimatedCosts, _estimatedCosts)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,rootThreadId,const DeepCollectionEquality().hash(_purposeCosts),const DeepCollectionEquality().hash(_estimatedCosts),hasUnpricedUsage);
}

@override
String toString() {
    return 'SessionCost(rootThreadId: $rootThreadId, purposeCosts: $purposeCosts, estimatedCosts: $estimatedCosts, hasUnpricedUsage: $hasUnpricedUsage)';
}


}

/// @nodoc
abstract mixin class _$SessionCostCopyWith<$Res> implements $SessionCostCopyWith<$Res> {
  factory _$SessionCostCopyWith(_SessionCost value, $Res Function(_SessionCost) _then) = __$SessionCostCopyWithImpl;
@override @useResult
$Res call({
 String rootThreadId, List<PurposeCost> purposeCosts, List<RuntimeCost> estimatedCosts, bool hasUnpricedUsage
});




}
/// @nodoc
class __$SessionCostCopyWithImpl<$Res>
    implements _$SessionCostCopyWith<$Res> {
  __$SessionCostCopyWithImpl(this._self, this._then);

  final _SessionCost _self;
  final $Res Function(_SessionCost) _then;

/// Create a copy of SessionCost
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rootThreadId = null,Object? purposeCosts = null,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(_SessionCost(
rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,purposeCosts: null == purposeCosts ? _self._purposeCosts : purposeCosts // ignore: cast_nullable_to_non_nullable
as List<PurposeCost>,estimatedCosts: null == estimatedCosts ? _self._estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as List<RuntimeCost>,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$PurposeCost {

 String? get purpose; List<RuntimeCost> get estimatedCosts; bool get hasUnpricedUsage;
/// Create a copy of PurposeCost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurposeCostCopyWith<PurposeCost> get copyWith => _$PurposeCostCopyWithImpl<PurposeCost>(this as PurposeCost, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PurposeCost;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurposeCost&&(identical(other.purpose, _this.purpose) || other.purpose == _this.purpose)&&const DeepCollectionEquality().equals(other.estimatedCosts, _this.estimatedCosts)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage));
}


@override
int get hashCode {
  final _this = this as PurposeCost;
  return Object.hash(runtimeType,_this.purpose,const DeepCollectionEquality().hash(_this.estimatedCosts),_this.hasUnpricedUsage);
}

@override
String toString() {
  final _this = this as PurposeCost;
  return 'PurposeCost(purpose: ${_this.purpose}, estimatedCosts: ${_this.estimatedCosts}, hasUnpricedUsage: ${_this.hasUnpricedUsage})';
}


}

/// @nodoc
abstract mixin class $PurposeCostCopyWith<$Res>  {
  factory $PurposeCostCopyWith(PurposeCost value, $Res Function(PurposeCost) _then) = _$PurposeCostCopyWithImpl;
@useResult
$Res call({
 String? purpose, List<RuntimeCost> estimatedCosts, bool hasUnpricedUsage
});




}
/// @nodoc
class _$PurposeCostCopyWithImpl<$Res>
    implements $PurposeCostCopyWith<$Res> {
  _$PurposeCostCopyWithImpl(this._self, this._then);

  final PurposeCost _self;
  final $Res Function(PurposeCost) _then;

/// Create a copy of PurposeCost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? purpose = freezed,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(PurposeCost(
purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as String?,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as List<RuntimeCost>,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [PurposeCost].
extension PurposeCostPatterns on PurposeCost {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurposeCost value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurposeCost() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurposeCost value)  $default,){
final _that = this;
switch (_that) {
case _PurposeCost():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurposeCost value)?  $default,){
final _that = this;
switch (_that) {
case _PurposeCost() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? purpose,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurposeCost() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? purpose,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)  $default,) {final _that = this;
switch (_that) {
case _PurposeCost():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? purpose,  List<RuntimeCost> estimatedCosts,  bool hasUnpricedUsage)?  $default,) {final _that = this;
switch (_that) {
case _PurposeCost() when $default != null:
return $default(_that.purpose,_that.estimatedCosts,_that.hasUnpricedUsage);case _:
  return null;

}
}

}

/// @nodoc


class _PurposeCost implements PurposeCost {
  const _PurposeCost({required this.purpose, required  List<RuntimeCost> estimatedCosts, required this.hasUnpricedUsage}): _estimatedCosts = estimatedCosts;


@override final  String? purpose;
 final  List<RuntimeCost> _estimatedCosts;
@override List<RuntimeCost> get estimatedCosts {
  if (_estimatedCosts is EqualUnmodifiableListView) return _estimatedCosts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_estimatedCosts);
}

@override final  bool hasUnpricedUsage;

/// Create a copy of PurposeCost
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurposeCostCopyWith<_PurposeCost> get copyWith => __$PurposeCostCopyWithImpl<_PurposeCost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurposeCost&&(identical(other.purpose, purpose) || other.purpose == purpose)&&const DeepCollectionEquality().equals(other.estimatedCosts, _estimatedCosts)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,purpose,const DeepCollectionEquality().hash(_estimatedCosts),hasUnpricedUsage);
}

@override
String toString() {
    return 'PurposeCost(purpose: $purpose, estimatedCosts: $estimatedCosts, hasUnpricedUsage: $hasUnpricedUsage)';
}


}

/// @nodoc
abstract mixin class _$PurposeCostCopyWith<$Res> implements $PurposeCostCopyWith<$Res> {
  factory _$PurposeCostCopyWith(_PurposeCost value, $Res Function(_PurposeCost) _then) = __$PurposeCostCopyWithImpl;
@override @useResult
$Res call({
 String? purpose, List<RuntimeCost> estimatedCosts, bool hasUnpricedUsage
});




}
/// @nodoc
class __$PurposeCostCopyWithImpl<$Res>
    implements _$PurposeCostCopyWith<$Res> {
  __$PurposeCostCopyWithImpl(this._self, this._then);

  final _PurposeCost _self;
  final $Res Function(_PurposeCost) _then;

/// Create a copy of PurposeCost
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? purpose = freezed,Object? estimatedCosts = null,Object? hasUnpricedUsage = null,}) {
  return _then(_PurposeCost(
purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as String?,estimatedCosts: null == estimatedCosts ? _self._estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as List<RuntimeCost>,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$RuntimeCost {

 String get currency; double get amount;
/// Create a copy of RuntimeCost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeCostCopyWith<RuntimeCost> get copyWith => _$RuntimeCostCopyWithImpl<RuntimeCost>(this as RuntimeCost, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeCost;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeCost&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.amount, _this.amount) || other.amount == _this.amount));
}


@override
int get hashCode {
  final _this = this as RuntimeCost;
  return Object.hash(runtimeType,_this.currency,_this.amount);
}

@override
String toString() {
  final _this = this as RuntimeCost;
  return 'RuntimeCost(currency: ${_this.currency}, amount: ${_this.amount})';
}


}

/// @nodoc
abstract mixin class $RuntimeCostCopyWith<$Res>  {
  factory $RuntimeCostCopyWith(RuntimeCost value, $Res Function(RuntimeCost) _then) = _$RuntimeCostCopyWithImpl;
@useResult
$Res call({
 String currency, double amount
});




}
/// @nodoc
class _$RuntimeCostCopyWithImpl<$Res>
    implements $RuntimeCostCopyWith<$Res> {
  _$RuntimeCostCopyWithImpl(this._self, this._then);

  final RuntimeCost _self;
  final $Res Function(RuntimeCost) _then;

/// Create a copy of RuntimeCost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? amount = null,}) {
  return _then(RuntimeCost(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeCost].
extension RuntimeCostPatterns on RuntimeCost {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeCost value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeCost() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeCost value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeCost():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeCost value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeCost() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String currency,  double amount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeCost() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String currency,  double amount)  $default,) {final _that = this;
switch (_that) {
case _RuntimeCost():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String currency,  double amount)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeCost() when $default != null:
return $default(_that.currency,_that.amount);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeCost implements RuntimeCost {
  const _RuntimeCost({required this.currency, required this.amount});


@override final  String currency;
@override final  double amount;

/// Create a copy of RuntimeCost
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeCostCopyWith<_RuntimeCost> get copyWith => __$RuntimeCostCopyWithImpl<_RuntimeCost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeCost&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,amount);
}

@override
String toString() {
    return 'RuntimeCost(currency: $currency, amount: $amount)';
}


}

/// @nodoc
abstract mixin class _$RuntimeCostCopyWith<$Res> implements $RuntimeCostCopyWith<$Res> {
  factory _$RuntimeCostCopyWith(_RuntimeCost value, $Res Function(_RuntimeCost) _then) = __$RuntimeCostCopyWithImpl;
@override @useResult
$Res call({
 String currency, double amount
});




}
/// @nodoc
class __$RuntimeCostCopyWithImpl<$Res>
    implements _$RuntimeCostCopyWith<$Res> {
  __$RuntimeCostCopyWithImpl(this._self, this._then);

  final _RuntimeCost _self;
  final $Res Function(_RuntimeCost) _then;

/// Create a copy of RuntimeCost
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? amount = null,}) {
  return _then(_RuntimeCost(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
