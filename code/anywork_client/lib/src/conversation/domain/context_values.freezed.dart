// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'context_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CacheUsageSummary {

 int get inputTokens; int get cacheReadTokens; double? get hitRate; bool get hasIncompleteUsage;
/// Create a copy of CacheUsageSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CacheUsageSummaryCopyWith<CacheUsageSummary> get copyWith => _$CacheUsageSummaryCopyWithImpl<CacheUsageSummary>(this as CacheUsageSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CacheUsageSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CacheUsageSummary&&(identical(other.inputTokens, _this.inputTokens) || other.inputTokens == _this.inputTokens)&&(identical(other.cacheReadTokens, _this.cacheReadTokens) || other.cacheReadTokens == _this.cacheReadTokens)&&(identical(other.hitRate, _this.hitRate) || other.hitRate == _this.hitRate)&&(identical(other.hasIncompleteUsage, _this.hasIncompleteUsage) || other.hasIncompleteUsage == _this.hasIncompleteUsage));
}


@override
int get hashCode {
  final _this = this as CacheUsageSummary;
  return Object.hash(runtimeType,_this.inputTokens,_this.cacheReadTokens,_this.hitRate,_this.hasIncompleteUsage);
}

@override
String toString() {
  final _this = this as CacheUsageSummary;
  return 'CacheUsageSummary(inputTokens: ${_this.inputTokens}, cacheReadTokens: ${_this.cacheReadTokens}, hitRate: ${_this.hitRate}, hasIncompleteUsage: ${_this.hasIncompleteUsage})';
}


}

/// @nodoc
abstract mixin class $CacheUsageSummaryCopyWith<$Res>  {
  factory $CacheUsageSummaryCopyWith(CacheUsageSummary value, $Res Function(CacheUsageSummary) _then) = _$CacheUsageSummaryCopyWithImpl;
@useResult
$Res call({
 int inputTokens, int cacheReadTokens, double? hitRate, bool hasIncompleteUsage
});




}
/// @nodoc
class _$CacheUsageSummaryCopyWithImpl<$Res>
    implements $CacheUsageSummaryCopyWith<$Res> {
  _$CacheUsageSummaryCopyWithImpl(this._self, this._then);

  final CacheUsageSummary _self;
  final $Res Function(CacheUsageSummary) _then;

/// Create a copy of CacheUsageSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputTokens = null,Object? cacheReadTokens = null,Object? hitRate = freezed,Object? hasIncompleteUsage = null,}) {
  return _then(CacheUsageSummary(
inputTokens: null == inputTokens ? _self.inputTokens : inputTokens // ignore: cast_nullable_to_non_nullable
as int,cacheReadTokens: null == cacheReadTokens ? _self.cacheReadTokens : cacheReadTokens // ignore: cast_nullable_to_non_nullable
as int,hitRate: freezed == hitRate ? _self.hitRate : hitRate // ignore: cast_nullable_to_non_nullable
as double?,hasIncompleteUsage: null == hasIncompleteUsage ? _self.hasIncompleteUsage : hasIncompleteUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CacheUsageSummary].
extension CacheUsageSummaryPatterns on CacheUsageSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CacheUsageSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CacheUsageSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CacheUsageSummary value)  $default,){
final _that = this;
switch (_that) {
case _CacheUsageSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CacheUsageSummary value)?  $default,){
final _that = this;
switch (_that) {
case _CacheUsageSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int inputTokens,  int cacheReadTokens,  double? hitRate,  bool hasIncompleteUsage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CacheUsageSummary() when $default != null:
return $default(_that.inputTokens,_that.cacheReadTokens,_that.hitRate,_that.hasIncompleteUsage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int inputTokens,  int cacheReadTokens,  double? hitRate,  bool hasIncompleteUsage)  $default,) {final _that = this;
switch (_that) {
case _CacheUsageSummary():
return $default(_that.inputTokens,_that.cacheReadTokens,_that.hitRate,_that.hasIncompleteUsage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int inputTokens,  int cacheReadTokens,  double? hitRate,  bool hasIncompleteUsage)?  $default,) {final _that = this;
switch (_that) {
case _CacheUsageSummary() when $default != null:
return $default(_that.inputTokens,_that.cacheReadTokens,_that.hitRate,_that.hasIncompleteUsage);case _:
  return null;

}
}

}

/// @nodoc


class _CacheUsageSummary implements CacheUsageSummary {
  const _CacheUsageSummary({required this.inputTokens, required this.cacheReadTokens, required this.hitRate, required this.hasIncompleteUsage});


@override final  int inputTokens;
@override final  int cacheReadTokens;
@override final  double? hitRate;
@override final  bool hasIncompleteUsage;

/// Create a copy of CacheUsageSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CacheUsageSummaryCopyWith<_CacheUsageSummary> get copyWith => __$CacheUsageSummaryCopyWithImpl<_CacheUsageSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CacheUsageSummary&&(identical(other.inputTokens, inputTokens) || other.inputTokens == inputTokens)&&(identical(other.cacheReadTokens, cacheReadTokens) || other.cacheReadTokens == cacheReadTokens)&&(identical(other.hitRate, hitRate) || other.hitRate == hitRate)&&(identical(other.hasIncompleteUsage, hasIncompleteUsage) || other.hasIncompleteUsage == hasIncompleteUsage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inputTokens,cacheReadTokens,hitRate,hasIncompleteUsage);
}

@override
String toString() {
    return 'CacheUsageSummary(inputTokens: $inputTokens, cacheReadTokens: $cacheReadTokens, hitRate: $hitRate, hasIncompleteUsage: $hasIncompleteUsage)';
}


}

/// @nodoc
abstract mixin class _$CacheUsageSummaryCopyWith<$Res> implements $CacheUsageSummaryCopyWith<$Res> {
  factory _$CacheUsageSummaryCopyWith(_CacheUsageSummary value, $Res Function(_CacheUsageSummary) _then) = __$CacheUsageSummaryCopyWithImpl;
@override @useResult
$Res call({
 int inputTokens, int cacheReadTokens, double? hitRate, bool hasIncompleteUsage
});




}
/// @nodoc
class __$CacheUsageSummaryCopyWithImpl<$Res>
    implements _$CacheUsageSummaryCopyWith<$Res> {
  __$CacheUsageSummaryCopyWithImpl(this._self, this._then);

  final _CacheUsageSummary _self;
  final $Res Function(_CacheUsageSummary) _then;

/// Create a copy of CacheUsageSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inputTokens = null,Object? cacheReadTokens = null,Object? hitRate = freezed,Object? hasIncompleteUsage = null,}) {
  return _then(_CacheUsageSummary(
inputTokens: null == inputTokens ? _self.inputTokens : inputTokens // ignore: cast_nullable_to_non_nullable
as int,cacheReadTokens: null == cacheReadTokens ? _self.cacheReadTokens : cacheReadTokens // ignore: cast_nullable_to_non_nullable
as int,hitRate: freezed == hitRate ? _self.hitRate : hitRate // ignore: cast_nullable_to_non_nullable
as double?,hasIncompleteUsage: null == hasIncompleteUsage ? _self.hasIncompleteUsage : hasIncompleteUsage // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ContextUsage {

 bool get hasIncompleteUsage; int? get contextWindow; int? get maxContextWindow; int? get autoCompactLimit; int get latestContextTokens; int get promptTokens; int get completionTokens; int get cachedPromptTokens; int get cacheWriteTokens; int get reasoningTokens; int get inferenceCount; int get totalTokens; CacheUsageSummary get cacheUsage; int get estimatedCostCount; int get estimatedCacheSavingCount; bool get hasUnpricedUsage; int? get promptGeneration; PromptPrefixChangedReason? get prefixChangedReason; int get updatedAt;
/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextUsageCopyWith<ContextUsage> get copyWith => _$ContextUsageCopyWithImpl<ContextUsage>(this as ContextUsage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContextUsage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextUsage&&(identical(other.hasIncompleteUsage, _this.hasIncompleteUsage) || other.hasIncompleteUsage == _this.hasIncompleteUsage)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxContextWindow, _this.maxContextWindow) || other.maxContextWindow == _this.maxContextWindow)&&(identical(other.autoCompactLimit, _this.autoCompactLimit) || other.autoCompactLimit == _this.autoCompactLimit)&&(identical(other.latestContextTokens, _this.latestContextTokens) || other.latestContextTokens == _this.latestContextTokens)&&(identical(other.promptTokens, _this.promptTokens) || other.promptTokens == _this.promptTokens)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.cachedPromptTokens, _this.cachedPromptTokens) || other.cachedPromptTokens == _this.cachedPromptTokens)&&(identical(other.cacheWriteTokens, _this.cacheWriteTokens) || other.cacheWriteTokens == _this.cacheWriteTokens)&&(identical(other.reasoningTokens, _this.reasoningTokens) || other.reasoningTokens == _this.reasoningTokens)&&(identical(other.inferenceCount, _this.inferenceCount) || other.inferenceCount == _this.inferenceCount)&&(identical(other.totalTokens, _this.totalTokens) || other.totalTokens == _this.totalTokens)&&(identical(other.cacheUsage, _this.cacheUsage) || other.cacheUsage == _this.cacheUsage)&&(identical(other.estimatedCostCount, _this.estimatedCostCount) || other.estimatedCostCount == _this.estimatedCostCount)&&(identical(other.estimatedCacheSavingCount, _this.estimatedCacheSavingCount) || other.estimatedCacheSavingCount == _this.estimatedCacheSavingCount)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage)&&(identical(other.promptGeneration, _this.promptGeneration) || other.promptGeneration == _this.promptGeneration)&&(identical(other.prefixChangedReason, _this.prefixChangedReason) || other.prefixChangedReason == _this.prefixChangedReason)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ContextUsage;
  return Object.hashAll([runtimeType,_this.hasIncompleteUsage,_this.contextWindow,_this.maxContextWindow,_this.autoCompactLimit,_this.latestContextTokens,_this.promptTokens,_this.completionTokens,_this.cachedPromptTokens,_this.cacheWriteTokens,_this.reasoningTokens,_this.inferenceCount,_this.totalTokens,_this.cacheUsage,_this.estimatedCostCount,_this.estimatedCacheSavingCount,_this.hasUnpricedUsage,_this.promptGeneration,_this.prefixChangedReason,_this.updatedAt]);
}

@override
String toString() {
  final _this = this as ContextUsage;
  return 'ContextUsage(hasIncompleteUsage: ${_this.hasIncompleteUsage}, contextWindow: ${_this.contextWindow}, maxContextWindow: ${_this.maxContextWindow}, autoCompactLimit: ${_this.autoCompactLimit}, latestContextTokens: ${_this.latestContextTokens}, promptTokens: ${_this.promptTokens}, completionTokens: ${_this.completionTokens}, cachedPromptTokens: ${_this.cachedPromptTokens}, cacheWriteTokens: ${_this.cacheWriteTokens}, reasoningTokens: ${_this.reasoningTokens}, inferenceCount: ${_this.inferenceCount}, totalTokens: ${_this.totalTokens}, cacheUsage: ${_this.cacheUsage}, estimatedCostCount: ${_this.estimatedCostCount}, estimatedCacheSavingCount: ${_this.estimatedCacheSavingCount}, hasUnpricedUsage: ${_this.hasUnpricedUsage}, promptGeneration: ${_this.promptGeneration}, prefixChangedReason: ${_this.prefixChangedReason}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $ContextUsageCopyWith<$Res>  {
  factory $ContextUsageCopyWith(ContextUsage value, $Res Function(ContextUsage) _then) = _$ContextUsageCopyWithImpl;
@useResult
$Res call({
 bool hasIncompleteUsage, int? contextWindow, int? maxContextWindow, int? autoCompactLimit, int latestContextTokens, int promptTokens, int completionTokens, int cachedPromptTokens, int cacheWriteTokens, int reasoningTokens, int inferenceCount, int totalTokens, CacheUsageSummary cacheUsage, int estimatedCostCount, int estimatedCacheSavingCount, bool hasUnpricedUsage, int? promptGeneration, PromptPrefixChangedReason? prefixChangedReason, int updatedAt
});


$CacheUsageSummaryCopyWith<$Res> get cacheUsage;

}
/// @nodoc
class _$ContextUsageCopyWithImpl<$Res>
    implements $ContextUsageCopyWith<$Res> {
  _$ContextUsageCopyWithImpl(this._self, this._then);

  final ContextUsage _self;
  final $Res Function(ContextUsage) _then;

/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hasIncompleteUsage = null,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? autoCompactLimit = freezed,Object? latestContextTokens = null,Object? promptTokens = null,Object? completionTokens = null,Object? cachedPromptTokens = null,Object? cacheWriteTokens = null,Object? reasoningTokens = null,Object? inferenceCount = null,Object? totalTokens = null,Object? cacheUsage = null,Object? estimatedCostCount = null,Object? estimatedCacheSavingCount = null,Object? hasUnpricedUsage = null,Object? promptGeneration = freezed,Object? prefixChangedReason = freezed,Object? updatedAt = null,}) {
  return _then(ContextUsage(
hasIncompleteUsage: null == hasIncompleteUsage ? _self.hasIncompleteUsage : hasIncompleteUsage // ignore: cast_nullable_to_non_nullable
as bool,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,latestContextTokens: null == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,cacheWriteTokens: null == cacheWriteTokens ? _self.cacheWriteTokens : cacheWriteTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningTokens: null == reasoningTokens ? _self.reasoningTokens : reasoningTokens // ignore: cast_nullable_to_non_nullable
as int,inferenceCount: null == inferenceCount ? _self.inferenceCount : inferenceCount // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,cacheUsage: null == cacheUsage ? _self.cacheUsage : cacheUsage // ignore: cast_nullable_to_non_nullable
as CacheUsageSummary,estimatedCostCount: null == estimatedCostCount ? _self.estimatedCostCount : estimatedCostCount // ignore: cast_nullable_to_non_nullable
as int,estimatedCacheSavingCount: null == estimatedCacheSavingCount ? _self.estimatedCacheSavingCount : estimatedCacheSavingCount // ignore: cast_nullable_to_non_nullable
as int,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,promptGeneration: freezed == promptGeneration ? _self.promptGeneration : promptGeneration // ignore: cast_nullable_to_non_nullable
as int?,prefixChangedReason: freezed == prefixChangedReason ? _self.prefixChangedReason : prefixChangedReason // ignore: cast_nullable_to_non_nullable
as PromptPrefixChangedReason?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CacheUsageSummaryCopyWith<$Res> get cacheUsage {

  return $CacheUsageSummaryCopyWith<$Res>(_self.cacheUsage, (value) {
    return _then(_self.copyWith(cacheUsage: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContextUsage].
extension ContextUsagePatterns on ContextUsage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextUsage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextUsage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextUsage value)  $default,){
final _that = this;
switch (_that) {
case _ContextUsage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextUsage value)?  $default,){
final _that = this;
switch (_that) {
case _ContextUsage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool hasIncompleteUsage,  int? contextWindow,  int? maxContextWindow,  int? autoCompactLimit,  int latestContextTokens,  int promptTokens,  int completionTokens,  int cachedPromptTokens,  int cacheWriteTokens,  int reasoningTokens,  int inferenceCount,  int totalTokens,  CacheUsageSummary cacheUsage,  int estimatedCostCount,  int estimatedCacheSavingCount,  bool hasUnpricedUsage,  int? promptGeneration,  PromptPrefixChangedReason? prefixChangedReason,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextUsage() when $default != null:
return $default(_that.hasIncompleteUsage,_that.contextWindow,_that.maxContextWindow,_that.autoCompactLimit,_that.latestContextTokens,_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.cacheWriteTokens,_that.reasoningTokens,_that.inferenceCount,_that.totalTokens,_that.cacheUsage,_that.estimatedCostCount,_that.estimatedCacheSavingCount,_that.hasUnpricedUsage,_that.promptGeneration,_that.prefixChangedReason,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool hasIncompleteUsage,  int? contextWindow,  int? maxContextWindow,  int? autoCompactLimit,  int latestContextTokens,  int promptTokens,  int completionTokens,  int cachedPromptTokens,  int cacheWriteTokens,  int reasoningTokens,  int inferenceCount,  int totalTokens,  CacheUsageSummary cacheUsage,  int estimatedCostCount,  int estimatedCacheSavingCount,  bool hasUnpricedUsage,  int? promptGeneration,  PromptPrefixChangedReason? prefixChangedReason,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ContextUsage():
return $default(_that.hasIncompleteUsage,_that.contextWindow,_that.maxContextWindow,_that.autoCompactLimit,_that.latestContextTokens,_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.cacheWriteTokens,_that.reasoningTokens,_that.inferenceCount,_that.totalTokens,_that.cacheUsage,_that.estimatedCostCount,_that.estimatedCacheSavingCount,_that.hasUnpricedUsage,_that.promptGeneration,_that.prefixChangedReason,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool hasIncompleteUsage,  int? contextWindow,  int? maxContextWindow,  int? autoCompactLimit,  int latestContextTokens,  int promptTokens,  int completionTokens,  int cachedPromptTokens,  int cacheWriteTokens,  int reasoningTokens,  int inferenceCount,  int totalTokens,  CacheUsageSummary cacheUsage,  int estimatedCostCount,  int estimatedCacheSavingCount,  bool hasUnpricedUsage,  int? promptGeneration,  PromptPrefixChangedReason? prefixChangedReason,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ContextUsage() when $default != null:
return $default(_that.hasIncompleteUsage,_that.contextWindow,_that.maxContextWindow,_that.autoCompactLimit,_that.latestContextTokens,_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.cacheWriteTokens,_that.reasoningTokens,_that.inferenceCount,_that.totalTokens,_that.cacheUsage,_that.estimatedCostCount,_that.estimatedCacheSavingCount,_that.hasUnpricedUsage,_that.promptGeneration,_that.prefixChangedReason,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ContextUsage implements ContextUsage {
  const _ContextUsage({required this.hasIncompleteUsage, required this.contextWindow, required this.maxContextWindow, required this.autoCompactLimit, required this.latestContextTokens, required this.promptTokens, required this.completionTokens, required this.cachedPromptTokens, required this.cacheWriteTokens, required this.reasoningTokens, required this.inferenceCount, required this.totalTokens, required this.cacheUsage, required this.estimatedCostCount, required this.estimatedCacheSavingCount, required this.hasUnpricedUsage, required this.promptGeneration, required this.prefixChangedReason, required this.updatedAt});


@override final  bool hasIncompleteUsage;
@override final  int? contextWindow;
@override final  int? maxContextWindow;
@override final  int? autoCompactLimit;
@override final  int latestContextTokens;
@override final  int promptTokens;
@override final  int completionTokens;
@override final  int cachedPromptTokens;
@override final  int cacheWriteTokens;
@override final  int reasoningTokens;
@override final  int inferenceCount;
@override final  int totalTokens;
@override final  CacheUsageSummary cacheUsage;
@override final  int estimatedCostCount;
@override final  int estimatedCacheSavingCount;
@override final  bool hasUnpricedUsage;
@override final  int? promptGeneration;
@override final  PromptPrefixChangedReason? prefixChangedReason;
@override final  int updatedAt;

/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextUsageCopyWith<_ContextUsage> get copyWith => __$ContextUsageCopyWithImpl<_ContextUsage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextUsage&&(identical(other.hasIncompleteUsage, hasIncompleteUsage) || other.hasIncompleteUsage == hasIncompleteUsage)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxContextWindow, maxContextWindow) || other.maxContextWindow == maxContextWindow)&&(identical(other.autoCompactLimit, autoCompactLimit) || other.autoCompactLimit == autoCompactLimit)&&(identical(other.latestContextTokens, latestContextTokens) || other.latestContextTokens == latestContextTokens)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.cachedPromptTokens, cachedPromptTokens) || other.cachedPromptTokens == cachedPromptTokens)&&(identical(other.cacheWriteTokens, cacheWriteTokens) || other.cacheWriteTokens == cacheWriteTokens)&&(identical(other.reasoningTokens, reasoningTokens) || other.reasoningTokens == reasoningTokens)&&(identical(other.inferenceCount, inferenceCount) || other.inferenceCount == inferenceCount)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.cacheUsage, cacheUsage) || other.cacheUsage == cacheUsage)&&(identical(other.estimatedCostCount, estimatedCostCount) || other.estimatedCostCount == estimatedCostCount)&&(identical(other.estimatedCacheSavingCount, estimatedCacheSavingCount) || other.estimatedCacheSavingCount == estimatedCacheSavingCount)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage)&&(identical(other.promptGeneration, promptGeneration) || other.promptGeneration == promptGeneration)&&(identical(other.prefixChangedReason, prefixChangedReason) || other.prefixChangedReason == prefixChangedReason)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,hasIncompleteUsage,contextWindow,maxContextWindow,autoCompactLimit,latestContextTokens,promptTokens,completionTokens,cachedPromptTokens,cacheWriteTokens,reasoningTokens,inferenceCount,totalTokens,cacheUsage,estimatedCostCount,estimatedCacheSavingCount,hasUnpricedUsage,promptGeneration,prefixChangedReason,updatedAt]);
}

@override
String toString() {
    return 'ContextUsage(hasIncompleteUsage: $hasIncompleteUsage, contextWindow: $contextWindow, maxContextWindow: $maxContextWindow, autoCompactLimit: $autoCompactLimit, latestContextTokens: $latestContextTokens, promptTokens: $promptTokens, completionTokens: $completionTokens, cachedPromptTokens: $cachedPromptTokens, cacheWriteTokens: $cacheWriteTokens, reasoningTokens: $reasoningTokens, inferenceCount: $inferenceCount, totalTokens: $totalTokens, cacheUsage: $cacheUsage, estimatedCostCount: $estimatedCostCount, estimatedCacheSavingCount: $estimatedCacheSavingCount, hasUnpricedUsage: $hasUnpricedUsage, promptGeneration: $promptGeneration, prefixChangedReason: $prefixChangedReason, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ContextUsageCopyWith<$Res> implements $ContextUsageCopyWith<$Res> {
  factory _$ContextUsageCopyWith(_ContextUsage value, $Res Function(_ContextUsage) _then) = __$ContextUsageCopyWithImpl;
@override @useResult
$Res call({
 bool hasIncompleteUsage, int? contextWindow, int? maxContextWindow, int? autoCompactLimit, int latestContextTokens, int promptTokens, int completionTokens, int cachedPromptTokens, int cacheWriteTokens, int reasoningTokens, int inferenceCount, int totalTokens, CacheUsageSummary cacheUsage, int estimatedCostCount, int estimatedCacheSavingCount, bool hasUnpricedUsage, int? promptGeneration, PromptPrefixChangedReason? prefixChangedReason, int updatedAt
});


@override $CacheUsageSummaryCopyWith<$Res> get cacheUsage;

}
/// @nodoc
class __$ContextUsageCopyWithImpl<$Res>
    implements _$ContextUsageCopyWith<$Res> {
  __$ContextUsageCopyWithImpl(this._self, this._then);

  final _ContextUsage _self;
  final $Res Function(_ContextUsage) _then;

/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hasIncompleteUsage = null,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? autoCompactLimit = freezed,Object? latestContextTokens = null,Object? promptTokens = null,Object? completionTokens = null,Object? cachedPromptTokens = null,Object? cacheWriteTokens = null,Object? reasoningTokens = null,Object? inferenceCount = null,Object? totalTokens = null,Object? cacheUsage = null,Object? estimatedCostCount = null,Object? estimatedCacheSavingCount = null,Object? hasUnpricedUsage = null,Object? promptGeneration = freezed,Object? prefixChangedReason = freezed,Object? updatedAt = null,}) {
  return _then(_ContextUsage(
hasIncompleteUsage: null == hasIncompleteUsage ? _self.hasIncompleteUsage : hasIncompleteUsage // ignore: cast_nullable_to_non_nullable
as bool,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,latestContextTokens: null == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,cacheWriteTokens: null == cacheWriteTokens ? _self.cacheWriteTokens : cacheWriteTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningTokens: null == reasoningTokens ? _self.reasoningTokens : reasoningTokens // ignore: cast_nullable_to_non_nullable
as int,inferenceCount: null == inferenceCount ? _self.inferenceCount : inferenceCount // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,cacheUsage: null == cacheUsage ? _self.cacheUsage : cacheUsage // ignore: cast_nullable_to_non_nullable
as CacheUsageSummary,estimatedCostCount: null == estimatedCostCount ? _self.estimatedCostCount : estimatedCostCount // ignore: cast_nullable_to_non_nullable
as int,estimatedCacheSavingCount: null == estimatedCacheSavingCount ? _self.estimatedCacheSavingCount : estimatedCacheSavingCount // ignore: cast_nullable_to_non_nullable
as int,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,promptGeneration: freezed == promptGeneration ? _self.promptGeneration : promptGeneration // ignore: cast_nullable_to_non_nullable
as int?,prefixChangedReason: freezed == prefixChangedReason ? _self.prefixChangedReason : prefixChangedReason // ignore: cast_nullable_to_non_nullable
as PromptPrefixChangedReason?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ContextUsage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CacheUsageSummaryCopyWith<$Res> get cacheUsage {

  return $CacheUsageSummaryCopyWith<$Res>(_self.cacheUsage, (value) {
    return _then(_self.copyWith(cacheUsage: value));
  });
}
}

/// @nodoc
mixin _$LiveContext {

 MetricsIdentityRef get identity; int? get latestContextTokens; TurnObservationState get state;
/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveContextCopyWith<LiveContext> get copyWith => _$LiveContextCopyWithImpl<LiveContext>(this as LiveContext, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LiveContext;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveContext&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.latestContextTokens, _this.latestContextTokens) || other.latestContextTokens == _this.latestContextTokens)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as LiveContext;
  return Object.hash(runtimeType,_this.identity,_this.latestContextTokens,_this.state);
}

@override
String toString() {
  final _this = this as LiveContext;
  return 'LiveContext(identity: ${_this.identity}, latestContextTokens: ${_this.latestContextTokens}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $LiveContextCopyWith<$Res>  {
  factory $LiveContextCopyWith(LiveContext value, $Res Function(LiveContext) _then) = _$LiveContextCopyWithImpl;
@useResult
$Res call({
 MetricsIdentityRef identity, int? latestContextTokens, TurnObservationState state
});


$MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class _$LiveContextCopyWithImpl<$Res>
    implements $LiveContextCopyWith<$Res> {
  _$LiveContextCopyWithImpl(this._self, this._then);

  final LiveContext _self;
  final $Res Function(LiveContext) _then;

/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? latestContextTokens = freezed,Object? state = null,}) {
  return _then(LiveContext(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,latestContextTokens: freezed == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnObservationState,
  ));
}
/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}


/// Adds pattern-matching-related methods to [LiveContext].
extension LiveContextPatterns on LiveContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LiveContext value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LiveContext() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LiveContext value)  $default,){
final _that = this;
switch (_that) {
case _LiveContext():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LiveContext value)?  $default,){
final _that = this;
switch (_that) {
case _LiveContext() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int? latestContextTokens,  TurnObservationState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LiveContext() when $default != null:
return $default(_that.identity,_that.latestContextTokens,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int? latestContextTokens,  TurnObservationState state)  $default,) {final _that = this;
switch (_that) {
case _LiveContext():
return $default(_that.identity,_that.latestContextTokens,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( MetricsIdentityRef identity,  int? latestContextTokens,  TurnObservationState state)?  $default,) {final _that = this;
switch (_that) {
case _LiveContext() when $default != null:
return $default(_that.identity,_that.latestContextTokens,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _LiveContext implements LiveContext {
  const _LiveContext({required this.identity, required this.latestContextTokens, required this.state});


@override final  MetricsIdentityRef identity;
@override final  int? latestContextTokens;
@override final  TurnObservationState state;

/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveContextCopyWith<_LiveContext> get copyWith => __$LiveContextCopyWithImpl<_LiveContext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveContext&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.latestContextTokens, latestContextTokens) || other.latestContextTokens == latestContextTokens)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,latestContextTokens,state);
}

@override
String toString() {
    return 'LiveContext(identity: $identity, latestContextTokens: $latestContextTokens, state: $state)';
}


}

/// @nodoc
abstract mixin class _$LiveContextCopyWith<$Res> implements $LiveContextCopyWith<$Res> {
  factory _$LiveContextCopyWith(_LiveContext value, $Res Function(_LiveContext) _then) = __$LiveContextCopyWithImpl;
@override @useResult
$Res call({
 MetricsIdentityRef identity, int? latestContextTokens, TurnObservationState state
});


@override $MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class __$LiveContextCopyWithImpl<$Res>
    implements _$LiveContextCopyWith<$Res> {
  __$LiveContextCopyWithImpl(this._self, this._then);

  final _LiveContext _self;
  final $Res Function(_LiveContext) _then;

/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? latestContextTokens = freezed,Object? state = null,}) {
  return _then(_LiveContext(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,latestContextTokens: freezed == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnObservationState,
  ));
}

/// Create a copy of LiveContext
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$CurrentContextPolicy {

 ConfigProjectionStamp get sources; int get modeRevision; int get routeRevision; int? get contextWindow; int? get maxContextWindow; int? get inputTokenLimit; int? get autoCompactLimit; ModelContextUnavailable? get unavailable; ModelContextAdjustment? get adjustment;
/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CurrentContextPolicyCopyWith<CurrentContextPolicy> get copyWith => _$CurrentContextPolicyCopyWithImpl<CurrentContextPolicy>(this as CurrentContextPolicy, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CurrentContextPolicy;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CurrentContextPolicy&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.modeRevision, _this.modeRevision) || other.modeRevision == _this.modeRevision)&&(identical(other.routeRevision, _this.routeRevision) || other.routeRevision == _this.routeRevision)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxContextWindow, _this.maxContextWindow) || other.maxContextWindow == _this.maxContextWindow)&&(identical(other.inputTokenLimit, _this.inputTokenLimit) || other.inputTokenLimit == _this.inputTokenLimit)&&(identical(other.autoCompactLimit, _this.autoCompactLimit) || other.autoCompactLimit == _this.autoCompactLimit)&&(identical(other.unavailable, _this.unavailable) || other.unavailable == _this.unavailable)&&(identical(other.adjustment, _this.adjustment) || other.adjustment == _this.adjustment));
}


@override
int get hashCode {
  final _this = this as CurrentContextPolicy;
  return Object.hash(runtimeType,_this.sources,_this.modeRevision,_this.routeRevision,_this.contextWindow,_this.maxContextWindow,_this.inputTokenLimit,_this.autoCompactLimit,_this.unavailable,_this.adjustment);
}

@override
String toString() {
  final _this = this as CurrentContextPolicy;
  return 'CurrentContextPolicy(sources: ${_this.sources}, modeRevision: ${_this.modeRevision}, routeRevision: ${_this.routeRevision}, contextWindow: ${_this.contextWindow}, maxContextWindow: ${_this.maxContextWindow}, inputTokenLimit: ${_this.inputTokenLimit}, autoCompactLimit: ${_this.autoCompactLimit}, unavailable: ${_this.unavailable}, adjustment: ${_this.adjustment})';
}


}

/// @nodoc
abstract mixin class $CurrentContextPolicyCopyWith<$Res>  {
  factory $CurrentContextPolicyCopyWith(CurrentContextPolicy value, $Res Function(CurrentContextPolicy) _then) = _$CurrentContextPolicyCopyWithImpl;
@useResult
$Res call({
 ConfigProjectionStamp sources, int modeRevision, int routeRevision, int? contextWindow, int? maxContextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextUnavailable? unavailable, ModelContextAdjustment? adjustment
});


$ConfigProjectionStampCopyWith<$Res> get sources;

}
/// @nodoc
class _$CurrentContextPolicyCopyWithImpl<$Res>
    implements $CurrentContextPolicyCopyWith<$Res> {
  _$CurrentContextPolicyCopyWithImpl(this._self, this._then);

  final CurrentContextPolicy _self;
  final $Res Function(CurrentContextPolicy) _then;

/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sources = null,Object? modeRevision = null,Object? routeRevision = null,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? unavailable = freezed,Object? adjustment = freezed,}) {
  return _then(CurrentContextPolicy(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,modeRevision: null == modeRevision ? _self.modeRevision : modeRevision // ignore: cast_nullable_to_non_nullable
as int,routeRevision: null == routeRevision ? _self.routeRevision : routeRevision // ignore: cast_nullable_to_non_nullable
as int,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,inputTokenLimit: freezed == inputTokenLimit ? _self.inputTokenLimit : inputTokenLimit // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,unavailable: freezed == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as ModelContextUnavailable?,adjustment: freezed == adjustment ? _self.adjustment : adjustment // ignore: cast_nullable_to_non_nullable
as ModelContextAdjustment?,
  ));
}
/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get sources {

  return $ConfigProjectionStampCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}
}


/// Adds pattern-matching-related methods to [CurrentContextPolicy].
extension CurrentContextPolicyPatterns on CurrentContextPolicy {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CurrentContextPolicy value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CurrentContextPolicy() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CurrentContextPolicy value)  $default,){
final _that = this;
switch (_that) {
case _CurrentContextPolicy():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CurrentContextPolicy value)?  $default,){
final _that = this;
switch (_that) {
case _CurrentContextPolicy() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigProjectionStamp sources,  int modeRevision,  int routeRevision,  int? contextWindow,  int? maxContextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextUnavailable? unavailable,  ModelContextAdjustment? adjustment)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CurrentContextPolicy() when $default != null:
return $default(_that.sources,_that.modeRevision,_that.routeRevision,_that.contextWindow,_that.maxContextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.unavailable,_that.adjustment);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigProjectionStamp sources,  int modeRevision,  int routeRevision,  int? contextWindow,  int? maxContextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextUnavailable? unavailable,  ModelContextAdjustment? adjustment)  $default,) {final _that = this;
switch (_that) {
case _CurrentContextPolicy():
return $default(_that.sources,_that.modeRevision,_that.routeRevision,_that.contextWindow,_that.maxContextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.unavailable,_that.adjustment);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigProjectionStamp sources,  int modeRevision,  int routeRevision,  int? contextWindow,  int? maxContextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextUnavailable? unavailable,  ModelContextAdjustment? adjustment)?  $default,) {final _that = this;
switch (_that) {
case _CurrentContextPolicy() when $default != null:
return $default(_that.sources,_that.modeRevision,_that.routeRevision,_that.contextWindow,_that.maxContextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.unavailable,_that.adjustment);case _:
  return null;

}
}

}

/// @nodoc


class _CurrentContextPolicy implements CurrentContextPolicy {
  const _CurrentContextPolicy({required this.sources, required this.modeRevision, required this.routeRevision, required this.contextWindow, required this.maxContextWindow, required this.inputTokenLimit, required this.autoCompactLimit, required this.unavailable, required this.adjustment});


@override final  ConfigProjectionStamp sources;
@override final  int modeRevision;
@override final  int routeRevision;
@override final  int? contextWindow;
@override final  int? maxContextWindow;
@override final  int? inputTokenLimit;
@override final  int? autoCompactLimit;
@override final  ModelContextUnavailable? unavailable;
@override final  ModelContextAdjustment? adjustment;

/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CurrentContextPolicyCopyWith<_CurrentContextPolicy> get copyWith => __$CurrentContextPolicyCopyWithImpl<_CurrentContextPolicy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CurrentContextPolicy&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.modeRevision, modeRevision) || other.modeRevision == modeRevision)&&(identical(other.routeRevision, routeRevision) || other.routeRevision == routeRevision)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxContextWindow, maxContextWindow) || other.maxContextWindow == maxContextWindow)&&(identical(other.inputTokenLimit, inputTokenLimit) || other.inputTokenLimit == inputTokenLimit)&&(identical(other.autoCompactLimit, autoCompactLimit) || other.autoCompactLimit == autoCompactLimit)&&(identical(other.unavailable, unavailable) || other.unavailable == unavailable)&&(identical(other.adjustment, adjustment) || other.adjustment == adjustment));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,modeRevision,routeRevision,contextWindow,maxContextWindow,inputTokenLimit,autoCompactLimit,unavailable,adjustment);
}

@override
String toString() {
    return 'CurrentContextPolicy(sources: $sources, modeRevision: $modeRevision, routeRevision: $routeRevision, contextWindow: $contextWindow, maxContextWindow: $maxContextWindow, inputTokenLimit: $inputTokenLimit, autoCompactLimit: $autoCompactLimit, unavailable: $unavailable, adjustment: $adjustment)';
}


}

/// @nodoc
abstract mixin class _$CurrentContextPolicyCopyWith<$Res> implements $CurrentContextPolicyCopyWith<$Res> {
  factory _$CurrentContextPolicyCopyWith(_CurrentContextPolicy value, $Res Function(_CurrentContextPolicy) _then) = __$CurrentContextPolicyCopyWithImpl;
@override @useResult
$Res call({
 ConfigProjectionStamp sources, int modeRevision, int routeRevision, int? contextWindow, int? maxContextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextUnavailable? unavailable, ModelContextAdjustment? adjustment
});


@override $ConfigProjectionStampCopyWith<$Res> get sources;

}
/// @nodoc
class __$CurrentContextPolicyCopyWithImpl<$Res>
    implements _$CurrentContextPolicyCopyWith<$Res> {
  __$CurrentContextPolicyCopyWithImpl(this._self, this._then);

  final _CurrentContextPolicy _self;
  final $Res Function(_CurrentContextPolicy) _then;

/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? modeRevision = null,Object? routeRevision = null,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? unavailable = freezed,Object? adjustment = freezed,}) {
  return _then(_CurrentContextPolicy(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,modeRevision: null == modeRevision ? _self.modeRevision : modeRevision // ignore: cast_nullable_to_non_nullable
as int,routeRevision: null == routeRevision ? _self.routeRevision : routeRevision // ignore: cast_nullable_to_non_nullable
as int,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,inputTokenLimit: freezed == inputTokenLimit ? _self.inputTokenLimit : inputTokenLimit // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,unavailable: freezed == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as ModelContextUnavailable?,adjustment: freezed == adjustment ? _self.adjustment : adjustment // ignore: cast_nullable_to_non_nullable
as ModelContextAdjustment?,
  ));
}

/// Create a copy of CurrentContextPolicy
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get sources {

  return $ConfigProjectionStampCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}
}

/// @nodoc
mixin _$ThreadContextValue {

 ContextUsage? get usage; LiveContext? get liveContext; CurrentContextPolicy? get currentPolicy; ContextReadRef get details;
/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<ThreadContextValue> get copyWith => _$ThreadContextValueCopyWithImpl<ThreadContextValue>(this as ThreadContextValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadContextValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextValue&&(identical(other.usage, _this.usage) || other.usage == _this.usage)&&(identical(other.liveContext, _this.liveContext) || other.liveContext == _this.liveContext)&&(identical(other.currentPolicy, _this.currentPolicy) || other.currentPolicy == _this.currentPolicy)&&(identical(other.details, _this.details) || other.details == _this.details));
}


@override
int get hashCode {
  final _this = this as ThreadContextValue;
  return Object.hash(runtimeType,_this.usage,_this.liveContext,_this.currentPolicy,_this.details);
}

@override
String toString() {
  final _this = this as ThreadContextValue;
  return 'ThreadContextValue(usage: ${_this.usage}, liveContext: ${_this.liveContext}, currentPolicy: ${_this.currentPolicy}, details: ${_this.details})';
}


}

/// @nodoc
abstract mixin class $ThreadContextValueCopyWith<$Res>  {
  factory $ThreadContextValueCopyWith(ThreadContextValue value, $Res Function(ThreadContextValue) _then) = _$ThreadContextValueCopyWithImpl;
@useResult
$Res call({
 ContextUsage? usage, LiveContext? liveContext, CurrentContextPolicy? currentPolicy, ContextReadRef details
});


$ContextUsageCopyWith<$Res>? get usage;$LiveContextCopyWith<$Res>? get liveContext;$CurrentContextPolicyCopyWith<$Res>? get currentPolicy;$ContextReadRefCopyWith<$Res> get details;

}
/// @nodoc
class _$ThreadContextValueCopyWithImpl<$Res>
    implements $ThreadContextValueCopyWith<$Res> {
  _$ThreadContextValueCopyWithImpl(this._self, this._then);

  final ThreadContextValue _self;
  final $Res Function(ThreadContextValue) _then;

/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? usage = freezed,Object? liveContext = freezed,Object? currentPolicy = freezed,Object? details = null,}) {
  return _then(ThreadContextValue(
usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as ContextUsage?,liveContext: freezed == liveContext ? _self.liveContext : liveContext // ignore: cast_nullable_to_non_nullable
as LiveContext?,currentPolicy: freezed == currentPolicy ? _self.currentPolicy : currentPolicy // ignore: cast_nullable_to_non_nullable
as CurrentContextPolicy?,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as ContextReadRef,
  ));
}
/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextUsageCopyWith<$Res>? get usage {
    if (_self.usage == null) {
    return null;
  }

  return $ContextUsageCopyWith<$Res>(_self.usage!, (value) {
    return _then(_self.copyWith(usage: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveContextCopyWith<$Res>? get liveContext {
    if (_self.liveContext == null) {
    return null;
  }

  return $LiveContextCopyWith<$Res>(_self.liveContext!, (value) {
    return _then(_self.copyWith(liveContext: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CurrentContextPolicyCopyWith<$Res>? get currentPolicy {
    if (_self.currentPolicy == null) {
    return null;
  }

  return $CurrentContextPolicyCopyWith<$Res>(_self.currentPolicy!, (value) {
    return _then(_self.copyWith(currentPolicy: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextReadRefCopyWith<$Res> get details {

  return $ContextReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadContextValue].
extension ThreadContextValuePatterns on ThreadContextValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadContextValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadContextValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadContextValue value)  $default,){
final _that = this;
switch (_that) {
case _ThreadContextValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadContextValue value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadContextValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ContextUsage? usage,  LiveContext? liveContext,  CurrentContextPolicy? currentPolicy,  ContextReadRef details)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadContextValue() when $default != null:
return $default(_that.usage,_that.liveContext,_that.currentPolicy,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ContextUsage? usage,  LiveContext? liveContext,  CurrentContextPolicy? currentPolicy,  ContextReadRef details)  $default,) {final _that = this;
switch (_that) {
case _ThreadContextValue():
return $default(_that.usage,_that.liveContext,_that.currentPolicy,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ContextUsage? usage,  LiveContext? liveContext,  CurrentContextPolicy? currentPolicy,  ContextReadRef details)?  $default,) {final _that = this;
switch (_that) {
case _ThreadContextValue() when $default != null:
return $default(_that.usage,_that.liveContext,_that.currentPolicy,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadContextValue implements ThreadContextValue {
  const _ThreadContextValue({required this.usage, required this.liveContext, required this.currentPolicy, required this.details});


@override final  ContextUsage? usage;
@override final  LiveContext? liveContext;
@override final  CurrentContextPolicy? currentPolicy;
@override final  ContextReadRef details;

/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadContextValueCopyWith<_ThreadContextValue> get copyWith => __$ThreadContextValueCopyWithImpl<_ThreadContextValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadContextValue&&(identical(other.usage, usage) || other.usage == usage)&&(identical(other.liveContext, liveContext) || other.liveContext == liveContext)&&(identical(other.currentPolicy, currentPolicy) || other.currentPolicy == currentPolicy)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,usage,liveContext,currentPolicy,details);
}

@override
String toString() {
    return 'ThreadContextValue(usage: $usage, liveContext: $liveContext, currentPolicy: $currentPolicy, details: $details)';
}


}

/// @nodoc
abstract mixin class _$ThreadContextValueCopyWith<$Res> implements $ThreadContextValueCopyWith<$Res> {
  factory _$ThreadContextValueCopyWith(_ThreadContextValue value, $Res Function(_ThreadContextValue) _then) = __$ThreadContextValueCopyWithImpl;
@override @useResult
$Res call({
 ContextUsage? usage, LiveContext? liveContext, CurrentContextPolicy? currentPolicy, ContextReadRef details
});


@override $ContextUsageCopyWith<$Res>? get usage;@override $LiveContextCopyWith<$Res>? get liveContext;@override $CurrentContextPolicyCopyWith<$Res>? get currentPolicy;@override $ContextReadRefCopyWith<$Res> get details;

}
/// @nodoc
class __$ThreadContextValueCopyWithImpl<$Res>
    implements _$ThreadContextValueCopyWith<$Res> {
  __$ThreadContextValueCopyWithImpl(this._self, this._then);

  final _ThreadContextValue _self;
  final $Res Function(_ThreadContextValue) _then;

/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? usage = freezed,Object? liveContext = freezed,Object? currentPolicy = freezed,Object? details = null,}) {
  return _then(_ThreadContextValue(
usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as ContextUsage?,liveContext: freezed == liveContext ? _self.liveContext : liveContext // ignore: cast_nullable_to_non_nullable
as LiveContext?,currentPolicy: freezed == currentPolicy ? _self.currentPolicy : currentPolicy // ignore: cast_nullable_to_non_nullable
as CurrentContextPolicy?,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as ContextReadRef,
  ));
}

/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextUsageCopyWith<$Res>? get usage {
    if (_self.usage == null) {
    return null;
  }

  return $ContextUsageCopyWith<$Res>(_self.usage!, (value) {
    return _then(_self.copyWith(usage: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveContextCopyWith<$Res>? get liveContext {
    if (_self.liveContext == null) {
    return null;
  }

  return $LiveContextCopyWith<$Res>(_self.liveContext!, (value) {
    return _then(_self.copyWith(liveContext: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CurrentContextPolicyCopyWith<$Res>? get currentPolicy {
    if (_self.currentPolicy == null) {
    return null;
  }

  return $CurrentContextPolicyCopyWith<$Res>(_self.currentPolicy!, (value) {
    return _then(_self.copyWith(currentPolicy: value));
  });
}/// Create a copy of ThreadContextValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextReadRefCopyWith<$Res> get details {

  return $ContextReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

// dart format on
