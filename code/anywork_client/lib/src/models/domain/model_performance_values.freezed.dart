// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_performance_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LocalModelPerformanceSummary {

 int get sampleCount; double? get tokensPerSecond; double? get averageTtftMillis; int get ttftSampleCount; int? get updatedAt;
/// Create a copy of LocalModelPerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalModelPerformanceSummaryCopyWith<LocalModelPerformanceSummary> get copyWith => _$LocalModelPerformanceSummaryCopyWithImpl<LocalModelPerformanceSummary>(this as LocalModelPerformanceSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LocalModelPerformanceSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalModelPerformanceSummary&&(identical(other.sampleCount, _this.sampleCount) || other.sampleCount == _this.sampleCount)&&(identical(other.tokensPerSecond, _this.tokensPerSecond) || other.tokensPerSecond == _this.tokensPerSecond)&&(identical(other.averageTtftMillis, _this.averageTtftMillis) || other.averageTtftMillis == _this.averageTtftMillis)&&(identical(other.ttftSampleCount, _this.ttftSampleCount) || other.ttftSampleCount == _this.ttftSampleCount)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as LocalModelPerformanceSummary;
  return Object.hash(runtimeType,_this.sampleCount,_this.tokensPerSecond,_this.averageTtftMillis,_this.ttftSampleCount,_this.updatedAt);
}

@override
String toString() {
  final _this = this as LocalModelPerformanceSummary;
  return 'LocalModelPerformanceSummary(sampleCount: ${_this.sampleCount}, tokensPerSecond: ${_this.tokensPerSecond}, averageTtftMillis: ${_this.averageTtftMillis}, ttftSampleCount: ${_this.ttftSampleCount}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $LocalModelPerformanceSummaryCopyWith<$Res>  {
  factory $LocalModelPerformanceSummaryCopyWith(LocalModelPerformanceSummary value, $Res Function(LocalModelPerformanceSummary) _then) = _$LocalModelPerformanceSummaryCopyWithImpl;
@useResult
$Res call({
 int sampleCount, double? tokensPerSecond, double? averageTtftMillis, int ttftSampleCount, int? updatedAt
});




}
/// @nodoc
class _$LocalModelPerformanceSummaryCopyWithImpl<$Res>
    implements $LocalModelPerformanceSummaryCopyWith<$Res> {
  _$LocalModelPerformanceSummaryCopyWithImpl(this._self, this._then);

  final LocalModelPerformanceSummary _self;
  final $Res Function(LocalModelPerformanceSummary) _then;

/// Create a copy of LocalModelPerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sampleCount = null,Object? tokensPerSecond = freezed,Object? averageTtftMillis = freezed,Object? ttftSampleCount = null,Object? updatedAt = freezed,}) {
  return _then(LocalModelPerformanceSummary(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [LocalModelPerformanceSummary].
extension LocalModelPerformanceSummaryPatterns on LocalModelPerformanceSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocalModelPerformanceSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocalModelPerformanceSummary value)  $default,){
final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocalModelPerformanceSummary value)?  $default,){
final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int sampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  int ttftSampleCount,  int? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary() when $default != null:
return $default(_that.sampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.ttftSampleCount,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int sampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  int ttftSampleCount,  int? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary():
return $default(_that.sampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.ttftSampleCount,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int sampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  int ttftSampleCount,  int? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _LocalModelPerformanceSummary() when $default != null:
return $default(_that.sampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.ttftSampleCount,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _LocalModelPerformanceSummary implements LocalModelPerformanceSummary {
  const _LocalModelPerformanceSummary({required this.sampleCount, required this.tokensPerSecond, required this.averageTtftMillis, required this.ttftSampleCount, required this.updatedAt});


@override final  int sampleCount;
@override final  double? tokensPerSecond;
@override final  double? averageTtftMillis;
@override final  int ttftSampleCount;
@override final  int? updatedAt;

/// Create a copy of LocalModelPerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocalModelPerformanceSummaryCopyWith<_LocalModelPerformanceSummary> get copyWith => __$LocalModelPerformanceSummaryCopyWithImpl<_LocalModelPerformanceSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocalModelPerformanceSummary&&(identical(other.sampleCount, sampleCount) || other.sampleCount == sampleCount)&&(identical(other.tokensPerSecond, tokensPerSecond) || other.tokensPerSecond == tokensPerSecond)&&(identical(other.averageTtftMillis, averageTtftMillis) || other.averageTtftMillis == averageTtftMillis)&&(identical(other.ttftSampleCount, ttftSampleCount) || other.ttftSampleCount == ttftSampleCount)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sampleCount,tokensPerSecond,averageTtftMillis,ttftSampleCount,updatedAt);
}

@override
String toString() {
    return 'LocalModelPerformanceSummary(sampleCount: $sampleCount, tokensPerSecond: $tokensPerSecond, averageTtftMillis: $averageTtftMillis, ttftSampleCount: $ttftSampleCount, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$LocalModelPerformanceSummaryCopyWith<$Res> implements $LocalModelPerformanceSummaryCopyWith<$Res> {
  factory _$LocalModelPerformanceSummaryCopyWith(_LocalModelPerformanceSummary value, $Res Function(_LocalModelPerformanceSummary) _then) = __$LocalModelPerformanceSummaryCopyWithImpl;
@override @useResult
$Res call({
 int sampleCount, double? tokensPerSecond, double? averageTtftMillis, int ttftSampleCount, int? updatedAt
});




}
/// @nodoc
class __$LocalModelPerformanceSummaryCopyWithImpl<$Res>
    implements _$LocalModelPerformanceSummaryCopyWith<$Res> {
  __$LocalModelPerformanceSummaryCopyWithImpl(this._self, this._then);

  final _LocalModelPerformanceSummary _self;
  final $Res Function(_LocalModelPerformanceSummary) _then;

/// Create a copy of LocalModelPerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sampleCount = null,Object? tokensPerSecond = freezed,Object? averageTtftMillis = freezed,Object? ttftSampleCount = null,Object? updatedAt = freezed,}) {
  return _then(_LocalModelPerformanceSummary(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
