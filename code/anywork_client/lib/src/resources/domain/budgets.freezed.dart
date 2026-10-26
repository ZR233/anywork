// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'budgets.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ResourceUsage {

 ResourceKind get kind; String get owner; ResourcePhase get phase;
/// Create a copy of ResourceUsage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceUsageCopyWith<ResourceUsage> get copyWith => _$ResourceUsageCopyWithImpl<ResourceUsage>(this as ResourceUsage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ResourceUsage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceUsage&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.phase, _this.phase) || other.phase == _this.phase));
}


@override
int get hashCode {
  final _this = this as ResourceUsage;
  return Object.hash(runtimeType,_this.kind,_this.owner,_this.phase);
}

@override
String toString() {
  final _this = this as ResourceUsage;
  return 'ResourceUsage(kind: ${_this.kind}, owner: ${_this.owner}, phase: ${_this.phase})';
}


}

/// @nodoc
abstract mixin class $ResourceUsageCopyWith<$Res>  {
  factory $ResourceUsageCopyWith(ResourceUsage value, $Res Function(ResourceUsage) _then) = _$ResourceUsageCopyWithImpl;
@useResult
$Res call({
 ResourceKind kind, String owner, ResourcePhase phase
});




}
/// @nodoc
class _$ResourceUsageCopyWithImpl<$Res>
    implements $ResourceUsageCopyWith<$Res> {
  _$ResourceUsageCopyWithImpl(this._self, this._then);

  final ResourceUsage _self;
  final $Res Function(ResourceUsage) _then;

/// Create a copy of ResourceUsage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? owner = null,Object? phase = null,}) {
  return _then(ResourceUsage(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ResourceKind,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ResourcePhase,
  ));
}

}


/// Adds pattern-matching-related methods to [ResourceUsage].
extension ResourceUsagePatterns on ResourceUsage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResourceUsage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResourceUsage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResourceUsage value)  $default,){
final _that = this;
switch (_that) {
case _ResourceUsage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResourceUsage value)?  $default,){
final _that = this;
switch (_that) {
case _ResourceUsage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ResourceKind kind,  String owner,  ResourcePhase phase)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResourceUsage() when $default != null:
return $default(_that.kind,_that.owner,_that.phase);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ResourceKind kind,  String owner,  ResourcePhase phase)  $default,) {final _that = this;
switch (_that) {
case _ResourceUsage():
return $default(_that.kind,_that.owner,_that.phase);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ResourceKind kind,  String owner,  ResourcePhase phase)?  $default,) {final _that = this;
switch (_that) {
case _ResourceUsage() when $default != null:
return $default(_that.kind,_that.owner,_that.phase);case _:
  return null;

}
}

}

/// @nodoc


class _ResourceUsage implements ResourceUsage {
  const _ResourceUsage({required this.kind, required this.owner, required this.phase});


@override final  ResourceKind kind;
@override final  String owner;
@override final  ResourcePhase phase;

/// Create a copy of ResourceUsage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResourceUsageCopyWith<_ResourceUsage> get copyWith => __$ResourceUsageCopyWithImpl<_ResourceUsage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResourceUsage&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,owner,phase);
}

@override
String toString() {
    return 'ResourceUsage(kind: $kind, owner: $owner, phase: $phase)';
}


}

/// @nodoc
abstract mixin class _$ResourceUsageCopyWith<$Res> implements $ResourceUsageCopyWith<$Res> {
  factory _$ResourceUsageCopyWith(_ResourceUsage value, $Res Function(_ResourceUsage) _then) = __$ResourceUsageCopyWithImpl;
@override @useResult
$Res call({
 ResourceKind kind, String owner, ResourcePhase phase
});




}
/// @nodoc
class __$ResourceUsageCopyWithImpl<$Res>
    implements _$ResourceUsageCopyWith<$Res> {
  __$ResourceUsageCopyWithImpl(this._self, this._then);

  final _ResourceUsage _self;
  final $Res Function(_ResourceUsage) _then;

/// Create a copy of ResourceUsage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? owner = null,Object? phase = null,}) {
  return _then(_ResourceUsage(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ResourceKind,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ResourcePhase,
  ));
}


}

/// @nodoc
mixin _$BudgetUsage {

 int get modelSteps; int get toolCalls; int get waitCalls; int get elapsedMs;
/// Create a copy of BudgetUsage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetUsageCopyWith<BudgetUsage> get copyWith => _$BudgetUsageCopyWithImpl<BudgetUsage>(this as BudgetUsage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BudgetUsage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetUsage&&(identical(other.modelSteps, _this.modelSteps) || other.modelSteps == _this.modelSteps)&&(identical(other.toolCalls, _this.toolCalls) || other.toolCalls == _this.toolCalls)&&(identical(other.waitCalls, _this.waitCalls) || other.waitCalls == _this.waitCalls)&&(identical(other.elapsedMs, _this.elapsedMs) || other.elapsedMs == _this.elapsedMs));
}


@override
int get hashCode {
  final _this = this as BudgetUsage;
  return Object.hash(runtimeType,_this.modelSteps,_this.toolCalls,_this.waitCalls,_this.elapsedMs);
}

@override
String toString() {
  final _this = this as BudgetUsage;
  return 'BudgetUsage(modelSteps: ${_this.modelSteps}, toolCalls: ${_this.toolCalls}, waitCalls: ${_this.waitCalls}, elapsedMs: ${_this.elapsedMs})';
}


}

/// @nodoc
abstract mixin class $BudgetUsageCopyWith<$Res>  {
  factory $BudgetUsageCopyWith(BudgetUsage value, $Res Function(BudgetUsage) _then) = _$BudgetUsageCopyWithImpl;
@useResult
$Res call({
 int modelSteps, int toolCalls, int waitCalls, int elapsedMs
});




}
/// @nodoc
class _$BudgetUsageCopyWithImpl<$Res>
    implements $BudgetUsageCopyWith<$Res> {
  _$BudgetUsageCopyWithImpl(this._self, this._then);

  final BudgetUsage _self;
  final $Res Function(BudgetUsage) _then;

/// Create a copy of BudgetUsage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelSteps = null,Object? toolCalls = null,Object? waitCalls = null,Object? elapsedMs = null,}) {
  return _then(BudgetUsage(
modelSteps: null == modelSteps ? _self.modelSteps : modelSteps // ignore: cast_nullable_to_non_nullable
as int,toolCalls: null == toolCalls ? _self.toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as int,waitCalls: null == waitCalls ? _self.waitCalls : waitCalls // ignore: cast_nullable_to_non_nullable
as int,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [BudgetUsage].
extension BudgetUsagePatterns on BudgetUsage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BudgetUsage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BudgetUsage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BudgetUsage value)  $default,){
final _that = this;
switch (_that) {
case _BudgetUsage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BudgetUsage value)?  $default,){
final _that = this;
switch (_that) {
case _BudgetUsage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int modelSteps,  int toolCalls,  int waitCalls,  int elapsedMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BudgetUsage() when $default != null:
return $default(_that.modelSteps,_that.toolCalls,_that.waitCalls,_that.elapsedMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int modelSteps,  int toolCalls,  int waitCalls,  int elapsedMs)  $default,) {final _that = this;
switch (_that) {
case _BudgetUsage():
return $default(_that.modelSteps,_that.toolCalls,_that.waitCalls,_that.elapsedMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int modelSteps,  int toolCalls,  int waitCalls,  int elapsedMs)?  $default,) {final _that = this;
switch (_that) {
case _BudgetUsage() when $default != null:
return $default(_that.modelSteps,_that.toolCalls,_that.waitCalls,_that.elapsedMs);case _:
  return null;

}
}

}

/// @nodoc


class _BudgetUsage implements BudgetUsage {
  const _BudgetUsage({required this.modelSteps, required this.toolCalls, required this.waitCalls, required this.elapsedMs});


@override final  int modelSteps;
@override final  int toolCalls;
@override final  int waitCalls;
@override final  int elapsedMs;

/// Create a copy of BudgetUsage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BudgetUsageCopyWith<_BudgetUsage> get copyWith => __$BudgetUsageCopyWithImpl<_BudgetUsage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BudgetUsage&&(identical(other.modelSteps, modelSteps) || other.modelSteps == modelSteps)&&(identical(other.toolCalls, toolCalls) || other.toolCalls == toolCalls)&&(identical(other.waitCalls, waitCalls) || other.waitCalls == waitCalls)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelSteps,toolCalls,waitCalls,elapsedMs);
}

@override
String toString() {
    return 'BudgetUsage(modelSteps: $modelSteps, toolCalls: $toolCalls, waitCalls: $waitCalls, elapsedMs: $elapsedMs)';
}


}

/// @nodoc
abstract mixin class _$BudgetUsageCopyWith<$Res> implements $BudgetUsageCopyWith<$Res> {
  factory _$BudgetUsageCopyWith(_BudgetUsage value, $Res Function(_BudgetUsage) _then) = __$BudgetUsageCopyWithImpl;
@override @useResult
$Res call({
 int modelSteps, int toolCalls, int waitCalls, int elapsedMs
});




}
/// @nodoc
class __$BudgetUsageCopyWithImpl<$Res>
    implements _$BudgetUsageCopyWith<$Res> {
  __$BudgetUsageCopyWithImpl(this._self, this._then);

  final _BudgetUsage _self;
  final $Res Function(_BudgetUsage) _then;

/// Create a copy of BudgetUsage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelSteps = null,Object? toolCalls = null,Object? waitCalls = null,Object? elapsedMs = null,}) {
  return _then(_BudgetUsage(
modelSteps: null == modelSteps ? _self.modelSteps : modelSteps // ignore: cast_nullable_to_non_nullable
as int,toolCalls: null == toolCalls ? _self.toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as int,waitCalls: null == waitCalls ? _self.waitCalls : waitCalls // ignore: cast_nullable_to_non_nullable
as int,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$BudgetLimitSnapshot {

 BudgetLimitKind get kind; BudgetUsage get usage;
/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<BudgetLimitSnapshot> get copyWith => _$BudgetLimitSnapshotCopyWithImpl<BudgetLimitSnapshot>(this as BudgetLimitSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BudgetLimitSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetLimitSnapshot&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.usage, _this.usage) || other.usage == _this.usage));
}


@override
int get hashCode {
  final _this = this as BudgetLimitSnapshot;
  return Object.hash(runtimeType,_this.kind,_this.usage);
}

@override
String toString() {
  final _this = this as BudgetLimitSnapshot;
  return 'BudgetLimitSnapshot(kind: ${_this.kind}, usage: ${_this.usage})';
}


}

/// @nodoc
abstract mixin class $BudgetLimitSnapshotCopyWith<$Res>  {
  factory $BudgetLimitSnapshotCopyWith(BudgetLimitSnapshot value, $Res Function(BudgetLimitSnapshot) _then) = _$BudgetLimitSnapshotCopyWithImpl;
@useResult
$Res call({
 BudgetLimitKind kind, BudgetUsage usage
});


$BudgetUsageCopyWith<$Res> get usage;

}
/// @nodoc
class _$BudgetLimitSnapshotCopyWithImpl<$Res>
    implements $BudgetLimitSnapshotCopyWith<$Res> {
  _$BudgetLimitSnapshotCopyWithImpl(this._self, this._then);

  final BudgetLimitSnapshot _self;
  final $Res Function(BudgetLimitSnapshot) _then;

/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? usage = null,}) {
  return _then(BudgetLimitSnapshot(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BudgetLimitKind,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as BudgetUsage,
  ));
}
/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetUsageCopyWith<$Res> get usage {

  return $BudgetUsageCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}


/// Adds pattern-matching-related methods to [BudgetLimitSnapshot].
extension BudgetLimitSnapshotPatterns on BudgetLimitSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BudgetLimitSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BudgetLimitSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BudgetLimitSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _BudgetLimitSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BudgetLimitSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _BudgetLimitSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( BudgetLimitKind kind,  BudgetUsage usage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BudgetLimitSnapshot() when $default != null:
return $default(_that.kind,_that.usage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( BudgetLimitKind kind,  BudgetUsage usage)  $default,) {final _that = this;
switch (_that) {
case _BudgetLimitSnapshot():
return $default(_that.kind,_that.usage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( BudgetLimitKind kind,  BudgetUsage usage)?  $default,) {final _that = this;
switch (_that) {
case _BudgetLimitSnapshot() when $default != null:
return $default(_that.kind,_that.usage);case _:
  return null;

}
}

}

/// @nodoc


class _BudgetLimitSnapshot implements BudgetLimitSnapshot {
  const _BudgetLimitSnapshot({required this.kind, required this.usage});


@override final  BudgetLimitKind kind;
@override final  BudgetUsage usage;

/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BudgetLimitSnapshotCopyWith<_BudgetLimitSnapshot> get copyWith => __$BudgetLimitSnapshotCopyWithImpl<_BudgetLimitSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BudgetLimitSnapshot&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,usage);
}

@override
String toString() {
    return 'BudgetLimitSnapshot(kind: $kind, usage: $usage)';
}


}

/// @nodoc
abstract mixin class _$BudgetLimitSnapshotCopyWith<$Res> implements $BudgetLimitSnapshotCopyWith<$Res> {
  factory _$BudgetLimitSnapshotCopyWith(_BudgetLimitSnapshot value, $Res Function(_BudgetLimitSnapshot) _then) = __$BudgetLimitSnapshotCopyWithImpl;
@override @useResult
$Res call({
 BudgetLimitKind kind, BudgetUsage usage
});


@override $BudgetUsageCopyWith<$Res> get usage;

}
/// @nodoc
class __$BudgetLimitSnapshotCopyWithImpl<$Res>
    implements _$BudgetLimitSnapshotCopyWith<$Res> {
  __$BudgetLimitSnapshotCopyWithImpl(this._self, this._then);

  final _BudgetLimitSnapshot _self;
  final $Res Function(_BudgetLimitSnapshot) _then;

/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? usage = null,}) {
  return _then(_BudgetLimitSnapshot(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BudgetLimitKind,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as BudgetUsage,
  ));
}

/// Create a copy of BudgetLimitSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetUsageCopyWith<$Res> get usage {

  return $BudgetUsageCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}

// dart format on
