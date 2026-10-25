// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRuntimeStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeRuntimeStateRead()';
}


}

/// @nodoc
class $BridgeRuntimeStateReadCopyWith<$Res>  {
$BridgeRuntimeStateReadCopyWith(BridgeRuntimeStateRead _, $Res Function(BridgeRuntimeStateRead) __);
}


/// Adds pattern-matching-related methods to [BridgeRuntimeStateRead].
extension BridgeRuntimeStateReadPatterns on BridgeRuntimeStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRuntimeStateRead_Uninitialized value)?  uninitialized,TResult Function( BridgeRuntimeStateRead_Initializing value)?  initializing,TResult Function( BridgeRuntimeStateRead_Ready value)?  ready,TResult Function( BridgeRuntimeStateRead_ShuttingDown value)?  shuttingDown,TResult Function( BridgeRuntimeStateRead_Stopped value)?  stopped,TResult Function( BridgeRuntimeStateRead_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeRuntimeStateRead_Initializing() when initializing != null:
return initializing(_that);case BridgeRuntimeStateRead_Ready() when ready != null:
return ready(_that);case BridgeRuntimeStateRead_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case BridgeRuntimeStateRead_Stopped() when stopped != null:
return stopped(_that);case BridgeRuntimeStateRead_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRuntimeStateRead_Uninitialized value)  uninitialized,required TResult Function( BridgeRuntimeStateRead_Initializing value)  initializing,required TResult Function( BridgeRuntimeStateRead_Ready value)  ready,required TResult Function( BridgeRuntimeStateRead_ShuttingDown value)  shuttingDown,required TResult Function( BridgeRuntimeStateRead_Stopped value)  stopped,required TResult Function( BridgeRuntimeStateRead_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized():
return uninitialized(_that);case BridgeRuntimeStateRead_Initializing():
return initializing(_that);case BridgeRuntimeStateRead_Ready():
return ready(_that);case BridgeRuntimeStateRead_ShuttingDown():
return shuttingDown(_that);case BridgeRuntimeStateRead_Stopped():
return stopped(_that);case BridgeRuntimeStateRead_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRuntimeStateRead_Uninitialized value)?  uninitialized,TResult? Function( BridgeRuntimeStateRead_Initializing value)?  initializing,TResult? Function( BridgeRuntimeStateRead_Ready value)?  ready,TResult? Function( BridgeRuntimeStateRead_ShuttingDown value)?  shuttingDown,TResult? Function( BridgeRuntimeStateRead_Stopped value)?  stopped,TResult? Function( BridgeRuntimeStateRead_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeRuntimeStateRead_Initializing() when initializing != null:
return initializing(_that);case BridgeRuntimeStateRead_Ready() when ready != null:
return ready(_that);case BridgeRuntimeStateRead_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case BridgeRuntimeStateRead_Stopped() when stopped != null:
return stopped(_that);case BridgeRuntimeStateRead_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 at)?  uninitialized,TResult Function( PlatformInt64 at)?  initializing,TResult Function( PlatformInt64 at)?  ready,TResult Function( PlatformInt64 at)?  shuttingDown,TResult Function( PlatformInt64 at)?  stopped,TResult Function( PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized() when uninitialized != null:
return uninitialized(_that.at);case BridgeRuntimeStateRead_Initializing() when initializing != null:
return initializing(_that.at);case BridgeRuntimeStateRead_Ready() when ready != null:
return ready(_that.at);case BridgeRuntimeStateRead_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that.at);case BridgeRuntimeStateRead_Stopped() when stopped != null:
return stopped(_that.at);case BridgeRuntimeStateRead_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 at)  uninitialized,required TResult Function( PlatformInt64 at)  initializing,required TResult Function( PlatformInt64 at)  ready,required TResult Function( PlatformInt64 at)  shuttingDown,required TResult Function( PlatformInt64 at)  stopped,required TResult Function( PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)  failed,}) {final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized():
return uninitialized(_that.at);case BridgeRuntimeStateRead_Initializing():
return initializing(_that.at);case BridgeRuntimeStateRead_Ready():
return ready(_that.at);case BridgeRuntimeStateRead_ShuttingDown():
return shuttingDown(_that.at);case BridgeRuntimeStateRead_Stopped():
return stopped(_that.at);case BridgeRuntimeStateRead_Failed():
return failed(_that.failedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 at)?  uninitialized,TResult? Function( PlatformInt64 at)?  initializing,TResult? Function( PlatformInt64 at)?  ready,TResult? Function( PlatformInt64 at)?  shuttingDown,TResult? Function( PlatformInt64 at)?  stopped,TResult? Function( PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)?  failed,}) {final _that = this;
switch (_that) {
case BridgeRuntimeStateRead_Uninitialized() when uninitialized != null:
return uninitialized(_that.at);case BridgeRuntimeStateRead_Initializing() when initializing != null:
return initializing(_that.at);case BridgeRuntimeStateRead_Ready() when ready != null:
return ready(_that.at);case BridgeRuntimeStateRead_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that.at);case BridgeRuntimeStateRead_Stopped() when stopped != null:
return stopped(_that.at);case BridgeRuntimeStateRead_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRuntimeStateRead_Uninitialized extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_Uninitialized({required this.at}): super._();


 final  PlatformInt64 at;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_UninitializedCopyWith<BridgeRuntimeStateRead_Uninitialized> get copyWith => _$BridgeRuntimeStateRead_UninitializedCopyWithImpl<BridgeRuntimeStateRead_Uninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_Uninitialized&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.uninitialized(at: $at)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_UninitializedCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_UninitializedCopyWith(BridgeRuntimeStateRead_Uninitialized value, $Res Function(BridgeRuntimeStateRead_Uninitialized) _then) = _$BridgeRuntimeStateRead_UninitializedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 at
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_UninitializedCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_UninitializedCopyWith<$Res> {
  _$BridgeRuntimeStateRead_UninitializedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_Uninitialized _self;
  final $Res Function(BridgeRuntimeStateRead_Uninitialized) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(BridgeRuntimeStateRead_Uninitialized(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeRuntimeStateRead_Initializing extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_Initializing({required this.at}): super._();


 final  PlatformInt64 at;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_InitializingCopyWith<BridgeRuntimeStateRead_Initializing> get copyWith => _$BridgeRuntimeStateRead_InitializingCopyWithImpl<BridgeRuntimeStateRead_Initializing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_Initializing&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.initializing(at: $at)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_InitializingCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_InitializingCopyWith(BridgeRuntimeStateRead_Initializing value, $Res Function(BridgeRuntimeStateRead_Initializing) _then) = _$BridgeRuntimeStateRead_InitializingCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 at
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_InitializingCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_InitializingCopyWith<$Res> {
  _$BridgeRuntimeStateRead_InitializingCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_Initializing _self;
  final $Res Function(BridgeRuntimeStateRead_Initializing) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(BridgeRuntimeStateRead_Initializing(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeRuntimeStateRead_Ready extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_Ready({required this.at}): super._();


 final  PlatformInt64 at;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_ReadyCopyWith<BridgeRuntimeStateRead_Ready> get copyWith => _$BridgeRuntimeStateRead_ReadyCopyWithImpl<BridgeRuntimeStateRead_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_Ready&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.ready(at: $at)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_ReadyCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_ReadyCopyWith(BridgeRuntimeStateRead_Ready value, $Res Function(BridgeRuntimeStateRead_Ready) _then) = _$BridgeRuntimeStateRead_ReadyCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 at
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_ReadyCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_ReadyCopyWith<$Res> {
  _$BridgeRuntimeStateRead_ReadyCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_Ready _self;
  final $Res Function(BridgeRuntimeStateRead_Ready) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(BridgeRuntimeStateRead_Ready(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeRuntimeStateRead_ShuttingDown extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_ShuttingDown({required this.at}): super._();


 final  PlatformInt64 at;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_ShuttingDownCopyWith<BridgeRuntimeStateRead_ShuttingDown> get copyWith => _$BridgeRuntimeStateRead_ShuttingDownCopyWithImpl<BridgeRuntimeStateRead_ShuttingDown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_ShuttingDown&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.shuttingDown(at: $at)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_ShuttingDownCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_ShuttingDownCopyWith(BridgeRuntimeStateRead_ShuttingDown value, $Res Function(BridgeRuntimeStateRead_ShuttingDown) _then) = _$BridgeRuntimeStateRead_ShuttingDownCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 at
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_ShuttingDownCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_ShuttingDownCopyWith<$Res> {
  _$BridgeRuntimeStateRead_ShuttingDownCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_ShuttingDown _self;
  final $Res Function(BridgeRuntimeStateRead_ShuttingDown) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(BridgeRuntimeStateRead_ShuttingDown(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeRuntimeStateRead_Stopped extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_Stopped({required this.at}): super._();


 final  PlatformInt64 at;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_StoppedCopyWith<BridgeRuntimeStateRead_Stopped> get copyWith => _$BridgeRuntimeStateRead_StoppedCopyWithImpl<BridgeRuntimeStateRead_Stopped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_Stopped&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.stopped(at: $at)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_StoppedCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_StoppedCopyWith(BridgeRuntimeStateRead_Stopped value, $Res Function(BridgeRuntimeStateRead_Stopped) _then) = _$BridgeRuntimeStateRead_StoppedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 at
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_StoppedCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_StoppedCopyWith<$Res> {
  _$BridgeRuntimeStateRead_StoppedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_Stopped _self;
  final $Res Function(BridgeRuntimeStateRead_Stopped) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(BridgeRuntimeStateRead_Stopped(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeRuntimeStateRead_Failed extends BridgeRuntimeStateRead {
  const BridgeRuntimeStateRead_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeStateRead_FailedCopyWith<BridgeRuntimeStateRead_Failed> get copyWith => _$BridgeRuntimeStateRead_FailedCopyWithImpl<BridgeRuntimeStateRead_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeStateRead_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeRuntimeStateRead.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeStateRead_FailedCopyWith<$Res> implements $BridgeRuntimeStateReadCopyWith<$Res> {
  factory $BridgeRuntimeStateRead_FailedCopyWith(BridgeRuntimeStateRead_Failed value, $Res Function(BridgeRuntimeStateRead_Failed) _then) = _$BridgeRuntimeStateRead_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeRuntimeStateRead_FailedCopyWithImpl<$Res>
    implements $BridgeRuntimeStateRead_FailedCopyWith<$Res> {
  _$BridgeRuntimeStateRead_FailedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeStateRead_Failed _self;
  final $Res Function(BridgeRuntimeStateRead_Failed) _then;

/// Create a copy of BridgeRuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeRuntimeStateRead_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

// dart format on
