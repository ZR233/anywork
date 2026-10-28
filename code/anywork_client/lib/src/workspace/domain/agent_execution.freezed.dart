// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_execution.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentExecution {

 String get id; AgentExecutionPhase get phase; String? get turnId;
/// Create a copy of AgentExecution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentExecutionCopyWith<AgentExecution> get copyWith => _$AgentExecutionCopyWithImpl<AgentExecution>(this as AgentExecution, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentExecution;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentExecution&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId));
}


@override
int get hashCode {
  final _this = this as AgentExecution;
  return Object.hash(runtimeType,_this.id,_this.phase,_this.turnId);
}

@override
String toString() {
  final _this = this as AgentExecution;
  return 'AgentExecution(id: ${_this.id}, phase: ${_this.phase}, turnId: ${_this.turnId})';
}


}

/// @nodoc
abstract mixin class $AgentExecutionCopyWith<$Res>  {
  factory $AgentExecutionCopyWith(AgentExecution value, $Res Function(AgentExecution) _then) = _$AgentExecutionCopyWithImpl;
@useResult
$Res call({
 String id, AgentExecutionPhase phase, String? turnId
});




}
/// @nodoc
class _$AgentExecutionCopyWithImpl<$Res>
    implements $AgentExecutionCopyWith<$Res> {
  _$AgentExecutionCopyWithImpl(this._self, this._then);

  final AgentExecution _self;
  final $Res Function(AgentExecution) _then;

/// Create a copy of AgentExecution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? phase = null,Object? turnId = freezed,}) {
  return _then(AgentExecution(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AgentExecutionPhase,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentExecution].
extension AgentExecutionPatterns on AgentExecution {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentExecution value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentExecution() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentExecution value)  $default,){
final _that = this;
switch (_that) {
case _AgentExecution():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentExecution value)?  $default,){
final _that = this;
switch (_that) {
case _AgentExecution() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  AgentExecutionPhase phase,  String? turnId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentExecution() when $default != null:
return $default(_that.id,_that.phase,_that.turnId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  AgentExecutionPhase phase,  String? turnId)  $default,) {final _that = this;
switch (_that) {
case _AgentExecution():
return $default(_that.id,_that.phase,_that.turnId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  AgentExecutionPhase phase,  String? turnId)?  $default,) {final _that = this;
switch (_that) {
case _AgentExecution() when $default != null:
return $default(_that.id,_that.phase,_that.turnId);case _:
  return null;

}
}

}

/// @nodoc


class _AgentExecution implements AgentExecution {
  const _AgentExecution({required this.id, required this.phase, required this.turnId});


@override final  String id;
@override final  AgentExecutionPhase phase;
@override final  String? turnId;

/// Create a copy of AgentExecution
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentExecutionCopyWith<_AgentExecution> get copyWith => __$AgentExecutionCopyWithImpl<_AgentExecution>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentExecution&&(identical(other.id, id) || other.id == id)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,phase,turnId);
}

@override
String toString() {
    return 'AgentExecution(id: $id, phase: $phase, turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class _$AgentExecutionCopyWith<$Res> implements $AgentExecutionCopyWith<$Res> {
  factory _$AgentExecutionCopyWith(_AgentExecution value, $Res Function(_AgentExecution) _then) = __$AgentExecutionCopyWithImpl;
@override @useResult
$Res call({
 String id, AgentExecutionPhase phase, String? turnId
});




}
/// @nodoc
class __$AgentExecutionCopyWithImpl<$Res>
    implements _$AgentExecutionCopyWith<$Res> {
  __$AgentExecutionCopyWithImpl(this._self, this._then);

  final _AgentExecution _self;
  final $Res Function(_AgentExecution) _then;

/// Create a copy of AgentExecution
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? phase = null,Object? turnId = freezed,}) {
  return _then(_AgentExecution(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AgentExecutionPhase,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ContinuationView {

 String get id; String? get sourceTurnId; ContinuationReason? get reason; int get createdAt; bool get claimed;
/// Create a copy of ContinuationView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContinuationViewCopyWith<ContinuationView> get copyWith => _$ContinuationViewCopyWithImpl<ContinuationView>(this as ContinuationView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContinuationView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContinuationView&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sourceTurnId, _this.sourceTurnId) || other.sourceTurnId == _this.sourceTurnId)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.claimed, _this.claimed) || other.claimed == _this.claimed));
}


@override
int get hashCode {
  final _this = this as ContinuationView;
  return Object.hash(runtimeType,_this.id,_this.sourceTurnId,_this.reason,_this.createdAt,_this.claimed);
}

@override
String toString() {
  final _this = this as ContinuationView;
  return 'ContinuationView(id: ${_this.id}, sourceTurnId: ${_this.sourceTurnId}, reason: ${_this.reason}, createdAt: ${_this.createdAt}, claimed: ${_this.claimed})';
}


}

/// @nodoc
abstract mixin class $ContinuationViewCopyWith<$Res>  {
  factory $ContinuationViewCopyWith(ContinuationView value, $Res Function(ContinuationView) _then) = _$ContinuationViewCopyWithImpl;
@useResult
$Res call({
 String id, String? sourceTurnId, ContinuationReason? reason, int createdAt, bool claimed
});




}
/// @nodoc
class _$ContinuationViewCopyWithImpl<$Res>
    implements $ContinuationViewCopyWith<$Res> {
  _$ContinuationViewCopyWithImpl(this._self, this._then);

  final ContinuationView _self;
  final $Res Function(ContinuationView) _then;

/// Create a copy of ContinuationView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sourceTurnId = freezed,Object? reason = freezed,Object? createdAt = null,Object? claimed = null,}) {
  return _then(ContinuationView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceTurnId: freezed == sourceTurnId ? _self.sourceTurnId : sourceTurnId // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ContinuationReason?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,claimed: null == claimed ? _self.claimed : claimed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ContinuationView].
extension ContinuationViewPatterns on ContinuationView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContinuationView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContinuationView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContinuationView value)  $default,){
final _that = this;
switch (_that) {
case _ContinuationView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContinuationView value)?  $default,){
final _that = this;
switch (_that) {
case _ContinuationView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? sourceTurnId,  ContinuationReason? reason,  int createdAt,  bool claimed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContinuationView() when $default != null:
return $default(_that.id,_that.sourceTurnId,_that.reason,_that.createdAt,_that.claimed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? sourceTurnId,  ContinuationReason? reason,  int createdAt,  bool claimed)  $default,) {final _that = this;
switch (_that) {
case _ContinuationView():
return $default(_that.id,_that.sourceTurnId,_that.reason,_that.createdAt,_that.claimed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? sourceTurnId,  ContinuationReason? reason,  int createdAt,  bool claimed)?  $default,) {final _that = this;
switch (_that) {
case _ContinuationView() when $default != null:
return $default(_that.id,_that.sourceTurnId,_that.reason,_that.createdAt,_that.claimed);case _:
  return null;

}
}

}

/// @nodoc


class _ContinuationView implements ContinuationView {
  const _ContinuationView({required this.id, required this.sourceTurnId, required this.reason, required this.createdAt, required this.claimed});


@override final  String id;
@override final  String? sourceTurnId;
@override final  ContinuationReason? reason;
@override final  int createdAt;
@override final  bool claimed;

/// Create a copy of ContinuationView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContinuationViewCopyWith<_ContinuationView> get copyWith => __$ContinuationViewCopyWithImpl<_ContinuationView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContinuationView&&(identical(other.id, id) || other.id == id)&&(identical(other.sourceTurnId, sourceTurnId) || other.sourceTurnId == sourceTurnId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.claimed, claimed) || other.claimed == claimed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,sourceTurnId,reason,createdAt,claimed);
}

@override
String toString() {
    return 'ContinuationView(id: $id, sourceTurnId: $sourceTurnId, reason: $reason, createdAt: $createdAt, claimed: $claimed)';
}


}

/// @nodoc
abstract mixin class _$ContinuationViewCopyWith<$Res> implements $ContinuationViewCopyWith<$Res> {
  factory _$ContinuationViewCopyWith(_ContinuationView value, $Res Function(_ContinuationView) _then) = __$ContinuationViewCopyWithImpl;
@override @useResult
$Res call({
 String id, String? sourceTurnId, ContinuationReason? reason, int createdAt, bool claimed
});




}
/// @nodoc
class __$ContinuationViewCopyWithImpl<$Res>
    implements _$ContinuationViewCopyWith<$Res> {
  __$ContinuationViewCopyWithImpl(this._self, this._then);

  final _ContinuationView _self;
  final $Res Function(_ContinuationView) _then;

/// Create a copy of ContinuationView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sourceTurnId = freezed,Object? reason = freezed,Object? createdAt = null,Object? claimed = null,}) {
  return _then(_ContinuationView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceTurnId: freezed == sourceTurnId ? _self.sourceTurnId : sourceTurnId // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ContinuationReason?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,claimed: null == claimed ? _self.claimed : claimed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
