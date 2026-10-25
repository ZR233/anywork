// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_values.dart';

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

/// @nodoc
mixin _$PerformanceCounters {

 int get sampleCount; int get completionTokens; int get totalTtftMillis; int get ttftSampleCount; int get totalResponseMillis; double get tokensPerSecond; double? get averageTtftMillis; double get averageResponseMillis;
/// Create a copy of PerformanceCounters
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<PerformanceCounters> get copyWith => _$PerformanceCountersCopyWithImpl<PerformanceCounters>(this as PerformanceCounters, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceCounters;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceCounters&&(identical(other.sampleCount, _this.sampleCount) || other.sampleCount == _this.sampleCount)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.totalTtftMillis, _this.totalTtftMillis) || other.totalTtftMillis == _this.totalTtftMillis)&&(identical(other.ttftSampleCount, _this.ttftSampleCount) || other.ttftSampleCount == _this.ttftSampleCount)&&(identical(other.totalResponseMillis, _this.totalResponseMillis) || other.totalResponseMillis == _this.totalResponseMillis)&&(identical(other.tokensPerSecond, _this.tokensPerSecond) || other.tokensPerSecond == _this.tokensPerSecond)&&(identical(other.averageTtftMillis, _this.averageTtftMillis) || other.averageTtftMillis == _this.averageTtftMillis)&&(identical(other.averageResponseMillis, _this.averageResponseMillis) || other.averageResponseMillis == _this.averageResponseMillis));
}


@override
int get hashCode {
  final _this = this as PerformanceCounters;
  return Object.hash(runtimeType,_this.sampleCount,_this.completionTokens,_this.totalTtftMillis,_this.ttftSampleCount,_this.totalResponseMillis,_this.tokensPerSecond,_this.averageTtftMillis,_this.averageResponseMillis);
}

@override
String toString() {
  final _this = this as PerformanceCounters;
  return 'PerformanceCounters(sampleCount: ${_this.sampleCount}, completionTokens: ${_this.completionTokens}, totalTtftMillis: ${_this.totalTtftMillis}, ttftSampleCount: ${_this.ttftSampleCount}, totalResponseMillis: ${_this.totalResponseMillis}, tokensPerSecond: ${_this.tokensPerSecond}, averageTtftMillis: ${_this.averageTtftMillis}, averageResponseMillis: ${_this.averageResponseMillis})';
}


}

/// @nodoc
abstract mixin class $PerformanceCountersCopyWith<$Res>  {
  factory $PerformanceCountersCopyWith(PerformanceCounters value, $Res Function(PerformanceCounters) _then) = _$PerformanceCountersCopyWithImpl;
@useResult
$Res call({
 int sampleCount, int completionTokens, int totalTtftMillis, int ttftSampleCount, int totalResponseMillis, double tokensPerSecond, double? averageTtftMillis, double averageResponseMillis
});




}
/// @nodoc
class _$PerformanceCountersCopyWithImpl<$Res>
    implements $PerformanceCountersCopyWith<$Res> {
  _$PerformanceCountersCopyWithImpl(this._self, this._then);

  final PerformanceCounters _self;
  final $Res Function(PerformanceCounters) _then;

/// Create a copy of PerformanceCounters
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sampleCount = null,Object? completionTokens = null,Object? totalTtftMillis = null,Object? ttftSampleCount = null,Object? totalResponseMillis = null,Object? tokensPerSecond = null,Object? averageTtftMillis = freezed,Object? averageResponseMillis = null,}) {
  return _then(PerformanceCounters(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTtftMillis: null == totalTtftMillis ? _self.totalTtftMillis : totalTtftMillis // ignore: cast_nullable_to_non_nullable
as int,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,totalResponseMillis: null == totalResponseMillis ? _self.totalResponseMillis : totalResponseMillis // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: null == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,averageResponseMillis: null == averageResponseMillis ? _self.averageResponseMillis : averageResponseMillis // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceCounters].
extension PerformanceCountersPatterns on PerformanceCounters {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceCounters value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceCounters() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceCounters value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceCounters():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceCounters value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceCounters() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int sampleCount,  int completionTokens,  int totalTtftMillis,  int ttftSampleCount,  int totalResponseMillis,  double tokensPerSecond,  double? averageTtftMillis,  double averageResponseMillis)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceCounters() when $default != null:
return $default(_that.sampleCount,_that.completionTokens,_that.totalTtftMillis,_that.ttftSampleCount,_that.totalResponseMillis,_that.tokensPerSecond,_that.averageTtftMillis,_that.averageResponseMillis);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int sampleCount,  int completionTokens,  int totalTtftMillis,  int ttftSampleCount,  int totalResponseMillis,  double tokensPerSecond,  double? averageTtftMillis,  double averageResponseMillis)  $default,) {final _that = this;
switch (_that) {
case _PerformanceCounters():
return $default(_that.sampleCount,_that.completionTokens,_that.totalTtftMillis,_that.ttftSampleCount,_that.totalResponseMillis,_that.tokensPerSecond,_that.averageTtftMillis,_that.averageResponseMillis);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int sampleCount,  int completionTokens,  int totalTtftMillis,  int ttftSampleCount,  int totalResponseMillis,  double tokensPerSecond,  double? averageTtftMillis,  double averageResponseMillis)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceCounters() when $default != null:
return $default(_that.sampleCount,_that.completionTokens,_that.totalTtftMillis,_that.ttftSampleCount,_that.totalResponseMillis,_that.tokensPerSecond,_that.averageTtftMillis,_that.averageResponseMillis);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceCounters implements PerformanceCounters {
  const _PerformanceCounters({required this.sampleCount, required this.completionTokens, required this.totalTtftMillis, required this.ttftSampleCount, required this.totalResponseMillis, required this.tokensPerSecond, required this.averageTtftMillis, required this.averageResponseMillis});


@override final  int sampleCount;
@override final  int completionTokens;
@override final  int totalTtftMillis;
@override final  int ttftSampleCount;
@override final  int totalResponseMillis;
@override final  double tokensPerSecond;
@override final  double? averageTtftMillis;
@override final  double averageResponseMillis;

/// Create a copy of PerformanceCounters
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceCountersCopyWith<_PerformanceCounters> get copyWith => __$PerformanceCountersCopyWithImpl<_PerformanceCounters>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceCounters&&(identical(other.sampleCount, sampleCount) || other.sampleCount == sampleCount)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTtftMillis, totalTtftMillis) || other.totalTtftMillis == totalTtftMillis)&&(identical(other.ttftSampleCount, ttftSampleCount) || other.ttftSampleCount == ttftSampleCount)&&(identical(other.totalResponseMillis, totalResponseMillis) || other.totalResponseMillis == totalResponseMillis)&&(identical(other.tokensPerSecond, tokensPerSecond) || other.tokensPerSecond == tokensPerSecond)&&(identical(other.averageTtftMillis, averageTtftMillis) || other.averageTtftMillis == averageTtftMillis)&&(identical(other.averageResponseMillis, averageResponseMillis) || other.averageResponseMillis == averageResponseMillis));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sampleCount,completionTokens,totalTtftMillis,ttftSampleCount,totalResponseMillis,tokensPerSecond,averageTtftMillis,averageResponseMillis);
}

@override
String toString() {
    return 'PerformanceCounters(sampleCount: $sampleCount, completionTokens: $completionTokens, totalTtftMillis: $totalTtftMillis, ttftSampleCount: $ttftSampleCount, totalResponseMillis: $totalResponseMillis, tokensPerSecond: $tokensPerSecond, averageTtftMillis: $averageTtftMillis, averageResponseMillis: $averageResponseMillis)';
}


}

/// @nodoc
abstract mixin class _$PerformanceCountersCopyWith<$Res> implements $PerformanceCountersCopyWith<$Res> {
  factory _$PerformanceCountersCopyWith(_PerformanceCounters value, $Res Function(_PerformanceCounters) _then) = __$PerformanceCountersCopyWithImpl;
@override @useResult
$Res call({
 int sampleCount, int completionTokens, int totalTtftMillis, int ttftSampleCount, int totalResponseMillis, double tokensPerSecond, double? averageTtftMillis, double averageResponseMillis
});




}
/// @nodoc
class __$PerformanceCountersCopyWithImpl<$Res>
    implements _$PerformanceCountersCopyWith<$Res> {
  __$PerformanceCountersCopyWithImpl(this._self, this._then);

  final _PerformanceCounters _self;
  final $Res Function(_PerformanceCounters) _then;

/// Create a copy of PerformanceCounters
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sampleCount = null,Object? completionTokens = null,Object? totalTtftMillis = null,Object? ttftSampleCount = null,Object? totalResponseMillis = null,Object? tokensPerSecond = null,Object? averageTtftMillis = freezed,Object? averageResponseMillis = null,}) {
  return _then(_PerformanceCounters(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTtftMillis: null == totalTtftMillis ? _self.totalTtftMillis : totalTtftMillis // ignore: cast_nullable_to_non_nullable
as int,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,totalResponseMillis: null == totalResponseMillis ? _self.totalResponseMillis : totalResponseMillis // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: null == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,averageResponseMillis: null == averageResponseMillis ? _self.averageResponseMillis : averageResponseMillis // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$PerformanceSummaryIdentity {

 String get accountId; String get accountDisplayName; String get modelId;
/// Create a copy of PerformanceSummaryIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityCopyWith<PerformanceSummaryIdentity> get copyWith => _$PerformanceSummaryIdentityCopyWithImpl<PerformanceSummaryIdentity>(this as PerformanceSummaryIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummaryIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummaryIdentity&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.accountDisplayName, _this.accountDisplayName) || other.accountDisplayName == _this.accountDisplayName)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as PerformanceSummaryIdentity;
  return Object.hash(runtimeType,_this.accountId,_this.accountDisplayName,_this.modelId);
}

@override
String toString() {
  final _this = this as PerformanceSummaryIdentity;
  return 'PerformanceSummaryIdentity(accountId: ${_this.accountId}, accountDisplayName: ${_this.accountDisplayName}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummaryIdentityCopyWith<$Res>  {
  factory $PerformanceSummaryIdentityCopyWith(PerformanceSummaryIdentity value, $Res Function(PerformanceSummaryIdentity) _then) = _$PerformanceSummaryIdentityCopyWithImpl;
@useResult
$Res call({
 String accountId, String accountDisplayName, String modelId
});




}
/// @nodoc
class _$PerformanceSummaryIdentityCopyWithImpl<$Res>
    implements $PerformanceSummaryIdentityCopyWith<$Res> {
  _$PerformanceSummaryIdentityCopyWithImpl(this._self, this._then);

  final PerformanceSummaryIdentity _self;
  final $Res Function(PerformanceSummaryIdentity) _then;

/// Create a copy of PerformanceSummaryIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = null,}) {
  return _then(PerformanceSummaryIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSummaryIdentity].
extension PerformanceSummaryIdentityPatterns on PerformanceSummaryIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentity value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummaryIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String accountDisplayName,  String modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String accountDisplayName,  String modelId)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity():
return $default(_that.accountId,_that.accountDisplayName,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String accountDisplayName,  String modelId)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentity() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummaryIdentity implements PerformanceSummaryIdentity {
  const _PerformanceSummaryIdentity({required this.accountId, required this.accountDisplayName, required this.modelId});


@override final  String accountId;
@override final  String accountDisplayName;
@override final  String modelId;

/// Create a copy of PerformanceSummaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryIdentityCopyWith<_PerformanceSummaryIdentity> get copyWith => __$PerformanceSummaryIdentityCopyWithImpl<_PerformanceSummaryIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummaryIdentity&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.accountDisplayName, accountDisplayName) || other.accountDisplayName == accountDisplayName)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,accountDisplayName,modelId);
}

@override
String toString() {
    return 'PerformanceSummaryIdentity(accountId: $accountId, accountDisplayName: $accountDisplayName, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummaryIdentityCopyWith<$Res> implements $PerformanceSummaryIdentityCopyWith<$Res> {
  factory _$PerformanceSummaryIdentityCopyWith(_PerformanceSummaryIdentity value, $Res Function(_PerformanceSummaryIdentity) _then) = __$PerformanceSummaryIdentityCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String accountDisplayName, String modelId
});




}
/// @nodoc
class __$PerformanceSummaryIdentityCopyWithImpl<$Res>
    implements _$PerformanceSummaryIdentityCopyWith<$Res> {
  __$PerformanceSummaryIdentityCopyWithImpl(this._self, this._then);

  final _PerformanceSummaryIdentity _self;
  final $Res Function(_PerformanceSummaryIdentity) _then;

/// Create a copy of PerformanceSummaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = null,}) {
  return _then(_PerformanceSummaryIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PerformanceEffortIdentity {

 String? get effort;
/// Create a copy of PerformanceEffortIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityCopyWith<PerformanceEffortIdentity> get copyWith => _$PerformanceEffortIdentityCopyWithImpl<PerformanceEffortIdentity>(this as PerformanceEffortIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffortIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffortIdentity&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as PerformanceEffortIdentity;
  return Object.hash(runtimeType,_this.effort);
}

@override
String toString() {
  final _this = this as PerformanceEffortIdentity;
  return 'PerformanceEffortIdentity(effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $PerformanceEffortIdentityCopyWith<$Res>  {
  factory $PerformanceEffortIdentityCopyWith(PerformanceEffortIdentity value, $Res Function(PerformanceEffortIdentity) _then) = _$PerformanceEffortIdentityCopyWithImpl;
@useResult
$Res call({
 String? effort
});




}
/// @nodoc
class _$PerformanceEffortIdentityCopyWithImpl<$Res>
    implements $PerformanceEffortIdentityCopyWith<$Res> {
  _$PerformanceEffortIdentityCopyWithImpl(this._self, this._then);

  final PerformanceEffortIdentity _self;
  final $Res Function(PerformanceEffortIdentity) _then;

/// Create a copy of PerformanceEffortIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effort = freezed,}) {
  return _then(PerformanceEffortIdentity(
effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceEffortIdentity].
extension PerformanceEffortIdentityPatterns on PerformanceEffortIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffortIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffortIdentity value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffortIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentity() when $default != null:
return $default(_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? effort)  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentity():
return $default(_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? effort)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentity() when $default != null:
return $default(_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffortIdentity implements PerformanceEffortIdentity {
  const _PerformanceEffortIdentity({required this.effort});


@override final  String? effort;

/// Create a copy of PerformanceEffortIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortIdentityCopyWith<_PerformanceEffortIdentity> get copyWith => __$PerformanceEffortIdentityCopyWithImpl<_PerformanceEffortIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffortIdentity&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effort);
}

@override
String toString() {
    return 'PerformanceEffortIdentity(effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$PerformanceEffortIdentityCopyWith<$Res> implements $PerformanceEffortIdentityCopyWith<$Res> {
  factory _$PerformanceEffortIdentityCopyWith(_PerformanceEffortIdentity value, $Res Function(_PerformanceEffortIdentity) _then) = __$PerformanceEffortIdentityCopyWithImpl;
@override @useResult
$Res call({
 String? effort
});




}
/// @nodoc
class __$PerformanceEffortIdentityCopyWithImpl<$Res>
    implements _$PerformanceEffortIdentityCopyWith<$Res> {
  __$PerformanceEffortIdentityCopyWithImpl(this._self, this._then);

  final _PerformanceEffortIdentity _self;
  final $Res Function(_PerformanceEffortIdentity) _then;

/// Create a copy of PerformanceEffortIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effort = freezed,}) {
  return _then(_PerformanceEffortIdentity(
effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$PerformanceSampleIdentity {

 String get accountId; String get accountDisplayName; String? get modelId; String? get sentModel; String? get reportedModel; ModelMatchState get modelMatchState; String? get effort;
/// Create a copy of PerformanceSampleIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityCopyWith<PerformanceSampleIdentity> get copyWith => _$PerformanceSampleIdentityCopyWithImpl<PerformanceSampleIdentity>(this as PerformanceSampleIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleIdentity&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.accountDisplayName, _this.accountDisplayName) || other.accountDisplayName == _this.accountDisplayName)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.sentModel, _this.sentModel) || other.sentModel == _this.sentModel)&&(identical(other.reportedModel, _this.reportedModel) || other.reportedModel == _this.reportedModel)&&(identical(other.modelMatchState, _this.modelMatchState) || other.modelMatchState == _this.modelMatchState)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleIdentity;
  return Object.hash(runtimeType,_this.accountId,_this.accountDisplayName,_this.modelId,_this.sentModel,_this.reportedModel,_this.modelMatchState,_this.effort);
}

@override
String toString() {
  final _this = this as PerformanceSampleIdentity;
  return 'PerformanceSampleIdentity(accountId: ${_this.accountId}, accountDisplayName: ${_this.accountDisplayName}, modelId: ${_this.modelId}, sentModel: ${_this.sentModel}, reportedModel: ${_this.reportedModel}, modelMatchState: ${_this.modelMatchState}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleIdentityCopyWith<$Res>  {
  factory $PerformanceSampleIdentityCopyWith(PerformanceSampleIdentity value, $Res Function(PerformanceSampleIdentity) _then) = _$PerformanceSampleIdentityCopyWithImpl;
@useResult
$Res call({
 String accountId, String accountDisplayName, String? modelId, String? sentModel, String? reportedModel, ModelMatchState modelMatchState, String? effort
});




}
/// @nodoc
class _$PerformanceSampleIdentityCopyWithImpl<$Res>
    implements $PerformanceSampleIdentityCopyWith<$Res> {
  _$PerformanceSampleIdentityCopyWithImpl(this._self, this._then);

  final PerformanceSampleIdentity _self;
  final $Res Function(PerformanceSampleIdentity) _then;

/// Create a copy of PerformanceSampleIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = freezed,Object? sentModel = freezed,Object? reportedModel = freezed,Object? modelMatchState = null,Object? effort = freezed,}) {
  return _then(PerformanceSampleIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,sentModel: freezed == sentModel ? _self.sentModel : sentModel // ignore: cast_nullable_to_non_nullable
as String?,reportedModel: freezed == reportedModel ? _self.reportedModel : reportedModel // ignore: cast_nullable_to_non_nullable
as String?,modelMatchState: null == modelMatchState ? _self.modelMatchState : modelMatchState // ignore: cast_nullable_to_non_nullable
as ModelMatchState,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSampleIdentity].
extension PerformanceSampleIdentityPatterns on PerformanceSampleIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleIdentity value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String accountDisplayName,  String? modelId,  String? sentModel,  String? reportedModel,  ModelMatchState modelMatchState,  String? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentity() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId,_that.sentModel,_that.reportedModel,_that.modelMatchState,_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String accountDisplayName,  String? modelId,  String? sentModel,  String? reportedModel,  ModelMatchState modelMatchState,  String? effort)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentity():
return $default(_that.accountId,_that.accountDisplayName,_that.modelId,_that.sentModel,_that.reportedModel,_that.modelMatchState,_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String accountDisplayName,  String? modelId,  String? sentModel,  String? reportedModel,  ModelMatchState modelMatchState,  String? effort)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentity() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId,_that.sentModel,_that.reportedModel,_that.modelMatchState,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleIdentity implements PerformanceSampleIdentity {
  const _PerformanceSampleIdentity({required this.accountId, required this.accountDisplayName, required this.modelId, required this.sentModel, required this.reportedModel, required this.modelMatchState, required this.effort});


@override final  String accountId;
@override final  String accountDisplayName;
@override final  String? modelId;
@override final  String? sentModel;
@override final  String? reportedModel;
@override final  ModelMatchState modelMatchState;
@override final  String? effort;

/// Create a copy of PerformanceSampleIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleIdentityCopyWith<_PerformanceSampleIdentity> get copyWith => __$PerformanceSampleIdentityCopyWithImpl<_PerformanceSampleIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleIdentity&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.accountDisplayName, accountDisplayName) || other.accountDisplayName == accountDisplayName)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.sentModel, sentModel) || other.sentModel == sentModel)&&(identical(other.reportedModel, reportedModel) || other.reportedModel == reportedModel)&&(identical(other.modelMatchState, modelMatchState) || other.modelMatchState == modelMatchState)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,accountDisplayName,modelId,sentModel,reportedModel,modelMatchState,effort);
}

@override
String toString() {
    return 'PerformanceSampleIdentity(accountId: $accountId, accountDisplayName: $accountDisplayName, modelId: $modelId, sentModel: $sentModel, reportedModel: $reportedModel, modelMatchState: $modelMatchState, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleIdentityCopyWith<$Res> implements $PerformanceSampleIdentityCopyWith<$Res> {
  factory _$PerformanceSampleIdentityCopyWith(_PerformanceSampleIdentity value, $Res Function(_PerformanceSampleIdentity) _then) = __$PerformanceSampleIdentityCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String accountDisplayName, String? modelId, String? sentModel, String? reportedModel, ModelMatchState modelMatchState, String? effort
});




}
/// @nodoc
class __$PerformanceSampleIdentityCopyWithImpl<$Res>
    implements _$PerformanceSampleIdentityCopyWith<$Res> {
  __$PerformanceSampleIdentityCopyWithImpl(this._self, this._then);

  final _PerformanceSampleIdentity _self;
  final $Res Function(_PerformanceSampleIdentity) _then;

/// Create a copy of PerformanceSampleIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = freezed,Object? sentModel = freezed,Object? reportedModel = freezed,Object? modelMatchState = null,Object? effort = freezed,}) {
  return _then(_PerformanceSampleIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,sentModel: freezed == sentModel ? _self.sentModel : sentModel // ignore: cast_nullable_to_non_nullable
as String?,reportedModel: freezed == reportedModel ? _self.reportedModel : reportedModel // ignore: cast_nullable_to_non_nullable
as String?,modelMatchState: null == modelMatchState ? _self.modelMatchState : modelMatchState // ignore: cast_nullable_to_non_nullable
as ModelMatchState,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$PerformanceSampleCounters {

 int get completedAt; int get completionTokens; int? get ttftMillis; int? get decodeMillis; int? get totalResponseMillis; double? get tokensPerSecond;
/// Create a copy of PerformanceSampleCounters
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleCountersCopyWith<PerformanceSampleCounters> get copyWith => _$PerformanceSampleCountersCopyWithImpl<PerformanceSampleCounters>(this as PerformanceSampleCounters, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleCounters;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleCounters&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.ttftMillis, _this.ttftMillis) || other.ttftMillis == _this.ttftMillis)&&(identical(other.decodeMillis, _this.decodeMillis) || other.decodeMillis == _this.decodeMillis)&&(identical(other.totalResponseMillis, _this.totalResponseMillis) || other.totalResponseMillis == _this.totalResponseMillis)&&(identical(other.tokensPerSecond, _this.tokensPerSecond) || other.tokensPerSecond == _this.tokensPerSecond));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleCounters;
  return Object.hash(runtimeType,_this.completedAt,_this.completionTokens,_this.ttftMillis,_this.decodeMillis,_this.totalResponseMillis,_this.tokensPerSecond);
}

@override
String toString() {
  final _this = this as PerformanceSampleCounters;
  return 'PerformanceSampleCounters(completedAt: ${_this.completedAt}, completionTokens: ${_this.completionTokens}, ttftMillis: ${_this.ttftMillis}, decodeMillis: ${_this.decodeMillis}, totalResponseMillis: ${_this.totalResponseMillis}, tokensPerSecond: ${_this.tokensPerSecond})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleCountersCopyWith<$Res>  {
  factory $PerformanceSampleCountersCopyWith(PerformanceSampleCounters value, $Res Function(PerformanceSampleCounters) _then) = _$PerformanceSampleCountersCopyWithImpl;
@useResult
$Res call({
 int completedAt, int completionTokens, int? ttftMillis, int? decodeMillis, int? totalResponseMillis, double? tokensPerSecond
});




}
/// @nodoc
class _$PerformanceSampleCountersCopyWithImpl<$Res>
    implements $PerformanceSampleCountersCopyWith<$Res> {
  _$PerformanceSampleCountersCopyWithImpl(this._self, this._then);

  final PerformanceSampleCounters _self;
  final $Res Function(PerformanceSampleCounters) _then;

/// Create a copy of PerformanceSampleCounters
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? completedAt = null,Object? completionTokens = null,Object? ttftMillis = freezed,Object? decodeMillis = freezed,Object? totalResponseMillis = freezed,Object? tokensPerSecond = freezed,}) {
  return _then(PerformanceSampleCounters(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,ttftMillis: freezed == ttftMillis ? _self.ttftMillis : ttftMillis // ignore: cast_nullable_to_non_nullable
as int?,decodeMillis: freezed == decodeMillis ? _self.decodeMillis : decodeMillis // ignore: cast_nullable_to_non_nullable
as int?,totalResponseMillis: freezed == totalResponseMillis ? _self.totalResponseMillis : totalResponseMillis // ignore: cast_nullable_to_non_nullable
as int?,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSampleCounters].
extension PerformanceSampleCountersPatterns on PerformanceSampleCounters {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleCounters value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleCounters() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleCounters value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleCounters():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleCounters value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleCounters() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int completedAt,  int completionTokens,  int? ttftMillis,  int? decodeMillis,  int? totalResponseMillis,  double? tokensPerSecond)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSampleCounters() when $default != null:
return $default(_that.completedAt,_that.completionTokens,_that.ttftMillis,_that.decodeMillis,_that.totalResponseMillis,_that.tokensPerSecond);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int completedAt,  int completionTokens,  int? ttftMillis,  int? decodeMillis,  int? totalResponseMillis,  double? tokensPerSecond)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleCounters():
return $default(_that.completedAt,_that.completionTokens,_that.ttftMillis,_that.decodeMillis,_that.totalResponseMillis,_that.tokensPerSecond);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int completedAt,  int completionTokens,  int? ttftMillis,  int? decodeMillis,  int? totalResponseMillis,  double? tokensPerSecond)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleCounters() when $default != null:
return $default(_that.completedAt,_that.completionTokens,_that.ttftMillis,_that.decodeMillis,_that.totalResponseMillis,_that.tokensPerSecond);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleCounters implements PerformanceSampleCounters {
  const _PerformanceSampleCounters({required this.completedAt, required this.completionTokens, required this.ttftMillis, required this.decodeMillis, required this.totalResponseMillis, required this.tokensPerSecond});


@override final  int completedAt;
@override final  int completionTokens;
@override final  int? ttftMillis;
@override final  int? decodeMillis;
@override final  int? totalResponseMillis;
@override final  double? tokensPerSecond;

/// Create a copy of PerformanceSampleCounters
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleCountersCopyWith<_PerformanceSampleCounters> get copyWith => __$PerformanceSampleCountersCopyWithImpl<_PerformanceSampleCounters>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleCounters&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.ttftMillis, ttftMillis) || other.ttftMillis == ttftMillis)&&(identical(other.decodeMillis, decodeMillis) || other.decodeMillis == decodeMillis)&&(identical(other.totalResponseMillis, totalResponseMillis) || other.totalResponseMillis == totalResponseMillis)&&(identical(other.tokensPerSecond, tokensPerSecond) || other.tokensPerSecond == tokensPerSecond));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,completionTokens,ttftMillis,decodeMillis,totalResponseMillis,tokensPerSecond);
}

@override
String toString() {
    return 'PerformanceSampleCounters(completedAt: $completedAt, completionTokens: $completionTokens, ttftMillis: $ttftMillis, decodeMillis: $decodeMillis, totalResponseMillis: $totalResponseMillis, tokensPerSecond: $tokensPerSecond)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleCountersCopyWith<$Res> implements $PerformanceSampleCountersCopyWith<$Res> {
  factory _$PerformanceSampleCountersCopyWith(_PerformanceSampleCounters value, $Res Function(_PerformanceSampleCounters) _then) = __$PerformanceSampleCountersCopyWithImpl;
@override @useResult
$Res call({
 int completedAt, int completionTokens, int? ttftMillis, int? decodeMillis, int? totalResponseMillis, double? tokensPerSecond
});




}
/// @nodoc
class __$PerformanceSampleCountersCopyWithImpl<$Res>
    implements _$PerformanceSampleCountersCopyWith<$Res> {
  __$PerformanceSampleCountersCopyWithImpl(this._self, this._then);

  final _PerformanceSampleCounters _self;
  final $Res Function(_PerformanceSampleCounters) _then;

/// Create a copy of PerformanceSampleCounters
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? completionTokens = null,Object? ttftMillis = freezed,Object? decodeMillis = freezed,Object? totalResponseMillis = freezed,Object? tokensPerSecond = freezed,}) {
  return _then(_PerformanceSampleCounters(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,ttftMillis: freezed == ttftMillis ? _self.ttftMillis : ttftMillis // ignore: cast_nullable_to_non_nullable
as int?,decodeMillis: freezed == decodeMillis ? _self.decodeMillis : decodeMillis // ignore: cast_nullable_to_non_nullable
as int?,totalResponseMillis: freezed == totalResponseMillis ? _self.totalResponseMillis : totalResponseMillis // ignore: cast_nullable_to_non_nullable
as int?,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$PerformanceSummary {

 PerformanceSummaryIdentity get identity; PerformanceCounters get counters; List<PerformanceEffort> get effortBreakdowns;
/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryCopyWith<PerformanceSummary> get copyWith => _$PerformanceSummaryCopyWithImpl<PerformanceSummary>(this as PerformanceSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummary&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters)&&const DeepCollectionEquality().equals(other.effortBreakdowns, _this.effortBreakdowns));
}


@override
int get hashCode {
  final _this = this as PerformanceSummary;
  return Object.hash(runtimeType,_this.identity,_this.counters,const DeepCollectionEquality().hash(_this.effortBreakdowns));
}

@override
String toString() {
  final _this = this as PerformanceSummary;
  return 'PerformanceSummary(identity: ${_this.identity}, counters: ${_this.counters}, effortBreakdowns: ${_this.effortBreakdowns})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummaryCopyWith<$Res>  {
  factory $PerformanceSummaryCopyWith(PerformanceSummary value, $Res Function(PerformanceSummary) _then) = _$PerformanceSummaryCopyWithImpl;
@useResult
$Res call({
 PerformanceSummaryIdentity identity, PerformanceCounters counters, List<PerformanceEffort> effortBreakdowns
});


$PerformanceSummaryIdentityCopyWith<$Res> get identity;$PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class _$PerformanceSummaryCopyWithImpl<$Res>
    implements $PerformanceSummaryCopyWith<$Res> {
  _$PerformanceSummaryCopyWithImpl(this._self, this._then);

  final PerformanceSummary _self;
  final $Res Function(PerformanceSummary) _then;

/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,Object? effortBreakdowns = null,}) {
  return _then(PerformanceSummary(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,effortBreakdowns: null == effortBreakdowns ? _self.effortBreakdowns : effortBreakdowns // ignore: cast_nullable_to_non_nullable
as List<PerformanceEffort>,
  ));
}
/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityCopyWith<$Res> get identity {

  return $PerformanceSummaryIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummary].
extension PerformanceSummaryPatterns on PerformanceSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummary value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummary value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSummaryIdentity identity,  PerformanceCounters counters,  List<PerformanceEffort> effortBreakdowns)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummary() when $default != null:
return $default(_that.identity,_that.counters,_that.effortBreakdowns);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSummaryIdentity identity,  PerformanceCounters counters,  List<PerformanceEffort> effortBreakdowns)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummary():
return $default(_that.identity,_that.counters,_that.effortBreakdowns);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSummaryIdentity identity,  PerformanceCounters counters,  List<PerformanceEffort> effortBreakdowns)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummary() when $default != null:
return $default(_that.identity,_that.counters,_that.effortBreakdowns);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummary implements PerformanceSummary {
  const _PerformanceSummary({required this.identity, required this.counters, required  List<PerformanceEffort> effortBreakdowns}): _effortBreakdowns = effortBreakdowns;


@override final  PerformanceSummaryIdentity identity;
@override final  PerformanceCounters counters;
 final  List<PerformanceEffort> _effortBreakdowns;
@override List<PerformanceEffort> get effortBreakdowns {
  if (_effortBreakdowns is EqualUnmodifiableListView) return _effortBreakdowns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_effortBreakdowns);
}


/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryCopyWith<_PerformanceSummary> get copyWith => __$PerformanceSummaryCopyWithImpl<_PerformanceSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummary&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters)&&const DeepCollectionEquality().equals(other.effortBreakdowns, _effortBreakdowns));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters,const DeepCollectionEquality().hash(_effortBreakdowns));
}

@override
String toString() {
    return 'PerformanceSummary(identity: $identity, counters: $counters, effortBreakdowns: $effortBreakdowns)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummaryCopyWith<$Res> implements $PerformanceSummaryCopyWith<$Res> {
  factory _$PerformanceSummaryCopyWith(_PerformanceSummary value, $Res Function(_PerformanceSummary) _then) = __$PerformanceSummaryCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSummaryIdentity identity, PerformanceCounters counters, List<PerformanceEffort> effortBreakdowns
});


@override $PerformanceSummaryIdentityCopyWith<$Res> get identity;@override $PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class __$PerformanceSummaryCopyWithImpl<$Res>
    implements _$PerformanceSummaryCopyWith<$Res> {
  __$PerformanceSummaryCopyWithImpl(this._self, this._then);

  final _PerformanceSummary _self;
  final $Res Function(_PerformanceSummary) _then;

/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,Object? effortBreakdowns = null,}) {
  return _then(_PerformanceSummary(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,effortBreakdowns: null == effortBreakdowns ? _self._effortBreakdowns : effortBreakdowns // ignore: cast_nullable_to_non_nullable
as List<PerformanceEffort>,
  ));
}

/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityCopyWith<$Res> get identity {

  return $PerformanceSummaryIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}

/// @nodoc
mixin _$PerformanceEffort {

 PerformanceEffortIdentity get identity; PerformanceCounters get counters;
/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortCopyWith<PerformanceEffort> get copyWith => _$PerformanceEffortCopyWithImpl<PerformanceEffort>(this as PerformanceEffort, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffort;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffort&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters));
}


@override
int get hashCode {
  final _this = this as PerformanceEffort;
  return Object.hash(runtimeType,_this.identity,_this.counters);
}

@override
String toString() {
  final _this = this as PerformanceEffort;
  return 'PerformanceEffort(identity: ${_this.identity}, counters: ${_this.counters})';
}


}

/// @nodoc
abstract mixin class $PerformanceEffortCopyWith<$Res>  {
  factory $PerformanceEffortCopyWith(PerformanceEffort value, $Res Function(PerformanceEffort) _then) = _$PerformanceEffortCopyWithImpl;
@useResult
$Res call({
 PerformanceEffortIdentity identity, PerformanceCounters counters
});


$PerformanceEffortIdentityCopyWith<$Res> get identity;$PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class _$PerformanceEffortCopyWithImpl<$Res>
    implements $PerformanceEffortCopyWith<$Res> {
  _$PerformanceEffortCopyWithImpl(this._self, this._then);

  final PerformanceEffort _self;
  final $Res Function(PerformanceEffort) _then;

/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(PerformanceEffort(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceEffortIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,
  ));
}
/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityCopyWith<$Res> get identity {

  return $PerformanceEffortIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceEffort].
extension PerformanceEffortPatterns on PerformanceEffort {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffort value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffort() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffort value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffort():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffort value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffort() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceEffortIdentity identity,  PerformanceCounters counters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceEffort() when $default != null:
return $default(_that.identity,_that.counters);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceEffortIdentity identity,  PerformanceCounters counters)  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffort():
return $default(_that.identity,_that.counters);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceEffortIdentity identity,  PerformanceCounters counters)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffort() when $default != null:
return $default(_that.identity,_that.counters);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffort implements PerformanceEffort {
  const _PerformanceEffort({required this.identity, required this.counters});


@override final  PerformanceEffortIdentity identity;
@override final  PerformanceCounters counters;

/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortCopyWith<_PerformanceEffort> get copyWith => __$PerformanceEffortCopyWithImpl<_PerformanceEffort>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffort&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters);
}

@override
String toString() {
    return 'PerformanceEffort(identity: $identity, counters: $counters)';
}


}

/// @nodoc
abstract mixin class _$PerformanceEffortCopyWith<$Res> implements $PerformanceEffortCopyWith<$Res> {
  factory _$PerformanceEffortCopyWith(_PerformanceEffort value, $Res Function(_PerformanceEffort) _then) = __$PerformanceEffortCopyWithImpl;
@override @useResult
$Res call({
 PerformanceEffortIdentity identity, PerformanceCounters counters
});


@override $PerformanceEffortIdentityCopyWith<$Res> get identity;@override $PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class __$PerformanceEffortCopyWithImpl<$Res>
    implements _$PerformanceEffortCopyWith<$Res> {
  __$PerformanceEffortCopyWithImpl(this._self, this._then);

  final _PerformanceEffort _self;
  final $Res Function(_PerformanceEffort) _then;

/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(_PerformanceEffort(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceEffortIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,
  ));
}

/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityCopyWith<$Res> get identity {

  return $PerformanceEffortIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceEffort
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSample {

 PerformanceSampleIdentity get identity; PerformanceSampleCounters get counters;
/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleCopyWith<PerformanceSample> get copyWith => _$PerformanceSampleCopyWithImpl<PerformanceSample>(this as PerformanceSample, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSample;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSample&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters));
}


@override
int get hashCode {
  final _this = this as PerformanceSample;
  return Object.hash(runtimeType,_this.identity,_this.counters);
}

@override
String toString() {
  final _this = this as PerformanceSample;
  return 'PerformanceSample(identity: ${_this.identity}, counters: ${_this.counters})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleCopyWith<$Res>  {
  factory $PerformanceSampleCopyWith(PerformanceSample value, $Res Function(PerformanceSample) _then) = _$PerformanceSampleCopyWithImpl;
@useResult
$Res call({
 PerformanceSampleIdentity identity, PerformanceSampleCounters counters
});


$PerformanceSampleIdentityCopyWith<$Res> get identity;$PerformanceSampleCountersCopyWith<$Res> get counters;

}
/// @nodoc
class _$PerformanceSampleCopyWithImpl<$Res>
    implements $PerformanceSampleCopyWith<$Res> {
  _$PerformanceSampleCopyWithImpl(this._self, this._then);

  final PerformanceSample _self;
  final $Res Function(PerformanceSample) _then;

/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(PerformanceSample(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSampleIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceSampleCounters,
  ));
}
/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityCopyWith<$Res> get identity {

  return $PerformanceSampleIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleCountersCopyWith<$Res> get counters {

  return $PerformanceSampleCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSample].
extension PerformanceSamplePatterns on PerformanceSample {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSample value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSample() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSample value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSample():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSample value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSample() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSampleIdentity identity,  PerformanceSampleCounters counters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSample() when $default != null:
return $default(_that.identity,_that.counters);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSampleIdentity identity,  PerformanceSampleCounters counters)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSample():
return $default(_that.identity,_that.counters);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSampleIdentity identity,  PerformanceSampleCounters counters)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSample() when $default != null:
return $default(_that.identity,_that.counters);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSample implements PerformanceSample {
  const _PerformanceSample({required this.identity, required this.counters});


@override final  PerformanceSampleIdentity identity;
@override final  PerformanceSampleCounters counters;

/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleCopyWith<_PerformanceSample> get copyWith => __$PerformanceSampleCopyWithImpl<_PerformanceSample>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSample&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters);
}

@override
String toString() {
    return 'PerformanceSample(identity: $identity, counters: $counters)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleCopyWith<$Res> implements $PerformanceSampleCopyWith<$Res> {
  factory _$PerformanceSampleCopyWith(_PerformanceSample value, $Res Function(_PerformanceSample) _then) = __$PerformanceSampleCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSampleIdentity identity, PerformanceSampleCounters counters
});


@override $PerformanceSampleIdentityCopyWith<$Res> get identity;@override $PerformanceSampleCountersCopyWith<$Res> get counters;

}
/// @nodoc
class __$PerformanceSampleCopyWithImpl<$Res>
    implements _$PerformanceSampleCopyWith<$Res> {
  __$PerformanceSampleCopyWithImpl(this._self, this._then);

  final _PerformanceSample _self;
  final $Res Function(_PerformanceSample) _then;

/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(_PerformanceSample(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSampleIdentity,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceSampleCounters,
  ));
}

/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityCopyWith<$Res> get identity {

  return $PerformanceSampleIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSample
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleCountersCopyWith<$Res> get counters {

  return $PerformanceSampleCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}

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
