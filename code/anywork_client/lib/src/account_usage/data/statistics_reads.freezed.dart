// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PerformanceSummariesReadHeader {

 TypedListRef get summaries;
/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesReadHeaderCopyWith<PerformanceSummariesReadHeader> get copyWith => _$PerformanceSummariesReadHeaderCopyWithImpl<PerformanceSummariesReadHeader>(this as PerformanceSummariesReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesReadHeader&&(identical(other.summaries, _this.summaries) || other.summaries == _this.summaries));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesReadHeader;
  return Object.hash(runtimeType,_this.summaries);
}

@override
String toString() {
  final _this = this as PerformanceSummariesReadHeader;
  return 'PerformanceSummariesReadHeader(summaries: ${_this.summaries})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesReadHeaderCopyWith<$Res>  {
  factory $PerformanceSummariesReadHeaderCopyWith(PerformanceSummariesReadHeader value, $Res Function(PerformanceSummariesReadHeader) _then) = _$PerformanceSummariesReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef summaries
});


$TypedListRefCopyWith<$Res> get summaries;

}
/// @nodoc
class _$PerformanceSummariesReadHeaderCopyWithImpl<$Res>
    implements $PerformanceSummariesReadHeaderCopyWith<$Res> {
  _$PerformanceSummariesReadHeaderCopyWithImpl(this._self, this._then);

  final PerformanceSummariesReadHeader _self;
  final $Res Function(PerformanceSummariesReadHeader) _then;

/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summaries = null,}) {
  return _then(PerformanceSummariesReadHeader(
summaries: null == summaries ? _self.summaries : summaries // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get summaries {

  return $TypedListRefCopyWith<$Res>(_self.summaries, (value) {
    return _then(_self.copyWith(summaries: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesReadHeader].
extension PerformanceSummariesReadHeaderPatterns on PerformanceSummariesReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef summaries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader() when $default != null:
return $default(_that.summaries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef summaries)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader():
return $default(_that.summaries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef summaries)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadHeader() when $default != null:
return $default(_that.summaries);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesReadHeader implements PerformanceSummariesReadHeader {
  const _PerformanceSummariesReadHeader({required this.summaries});


@override final  TypedListRef summaries;

/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesReadHeaderCopyWith<_PerformanceSummariesReadHeader> get copyWith => __$PerformanceSummariesReadHeaderCopyWithImpl<_PerformanceSummariesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesReadHeader&&(identical(other.summaries, summaries) || other.summaries == summaries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summaries);
}

@override
String toString() {
    return 'PerformanceSummariesReadHeader(summaries: $summaries)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesReadHeaderCopyWith<$Res> implements $PerformanceSummariesReadHeaderCopyWith<$Res> {
  factory _$PerformanceSummariesReadHeaderCopyWith(_PerformanceSummariesReadHeader value, $Res Function(_PerformanceSummariesReadHeader) _then) = __$PerformanceSummariesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef summaries
});


@override $TypedListRefCopyWith<$Res> get summaries;

}
/// @nodoc
class __$PerformanceSummariesReadHeaderCopyWithImpl<$Res>
    implements _$PerformanceSummariesReadHeaderCopyWith<$Res> {
  __$PerformanceSummariesReadHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesReadHeader _self;
  final $Res Function(_PerformanceSummariesReadHeader) _then;

/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? summaries = null,}) {
  return _then(_PerformanceSummariesReadHeader(
summaries: null == summaries ? _self.summaries : summaries // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of PerformanceSummariesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get summaries {

  return $TypedListRefCopyWith<$Res>(_self.summaries, (value) {
    return _then(_self.copyWith(summaries: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryReadHeader {

 TypedListRef get samples;
/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryReadHeaderCopyWith<PerformanceHistoryReadHeader> get copyWith => _$PerformanceHistoryReadHeaderCopyWithImpl<PerformanceHistoryReadHeader>(this as PerformanceHistoryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryReadHeader&&(identical(other.samples, _this.samples) || other.samples == _this.samples));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryReadHeader;
  return Object.hash(runtimeType,_this.samples);
}

@override
String toString() {
  final _this = this as PerformanceHistoryReadHeader;
  return 'PerformanceHistoryReadHeader(samples: ${_this.samples})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryReadHeaderCopyWith<$Res>  {
  factory $PerformanceHistoryReadHeaderCopyWith(PerformanceHistoryReadHeader value, $Res Function(PerformanceHistoryReadHeader) _then) = _$PerformanceHistoryReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef samples
});


$TypedListRefCopyWith<$Res> get samples;

}
/// @nodoc
class _$PerformanceHistoryReadHeaderCopyWithImpl<$Res>
    implements $PerformanceHistoryReadHeaderCopyWith<$Res> {
  _$PerformanceHistoryReadHeaderCopyWithImpl(this._self, this._then);

  final PerformanceHistoryReadHeader _self;
  final $Res Function(PerformanceHistoryReadHeader) _then;

/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? samples = null,}) {
  return _then(PerformanceHistoryReadHeader(
samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get samples {

  return $TypedListRefCopyWith<$Res>(_self.samples, (value) {
    return _then(_self.copyWith(samples: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryReadHeader].
extension PerformanceHistoryReadHeaderPatterns on PerformanceHistoryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef samples)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader() when $default != null:
return $default(_that.samples);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef samples)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader():
return $default(_that.samples);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef samples)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadHeader() when $default != null:
return $default(_that.samples);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryReadHeader implements PerformanceHistoryReadHeader {
  const _PerformanceHistoryReadHeader({required this.samples});


@override final  TypedListRef samples;

/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryReadHeaderCopyWith<_PerformanceHistoryReadHeader> get copyWith => __$PerformanceHistoryReadHeaderCopyWithImpl<_PerformanceHistoryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryReadHeader&&(identical(other.samples, samples) || other.samples == samples));
}


@override
int get hashCode {
    return Object.hash(runtimeType,samples);
}

@override
String toString() {
    return 'PerformanceHistoryReadHeader(samples: $samples)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryReadHeaderCopyWith<$Res> implements $PerformanceHistoryReadHeaderCopyWith<$Res> {
  factory _$PerformanceHistoryReadHeaderCopyWith(_PerformanceHistoryReadHeader value, $Res Function(_PerformanceHistoryReadHeader) _then) = __$PerformanceHistoryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef samples
});


@override $TypedListRefCopyWith<$Res> get samples;

}
/// @nodoc
class __$PerformanceHistoryReadHeaderCopyWithImpl<$Res>
    implements _$PerformanceHistoryReadHeaderCopyWith<$Res> {
  __$PerformanceHistoryReadHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryReadHeader _self;
  final $Res Function(_PerformanceHistoryReadHeader) _then;

/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? samples = null,}) {
  return _then(_PerformanceHistoryReadHeader(
samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of PerformanceHistoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get samples {

  return $TypedListRefCopyWith<$Res>(_self.samples, (value) {
    return _then(_self.copyWith(samples: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSummaryRead {

 PerformanceSummaryIdentityRef get identity; PerformanceCounters get counters; TypedListRef get effortBreakdowns;
/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryReadCopyWith<PerformanceSummaryRead> get copyWith => _$PerformanceSummaryReadCopyWithImpl<PerformanceSummaryRead>(this as PerformanceSummaryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummaryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummaryRead&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters)&&(identical(other.effortBreakdowns, _this.effortBreakdowns) || other.effortBreakdowns == _this.effortBreakdowns));
}


@override
int get hashCode {
  final _this = this as PerformanceSummaryRead;
  return Object.hash(runtimeType,_this.identity,_this.counters,_this.effortBreakdowns);
}

@override
String toString() {
  final _this = this as PerformanceSummaryRead;
  return 'PerformanceSummaryRead(identity: ${_this.identity}, counters: ${_this.counters}, effortBreakdowns: ${_this.effortBreakdowns})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummaryReadCopyWith<$Res>  {
  factory $PerformanceSummaryReadCopyWith(PerformanceSummaryRead value, $Res Function(PerformanceSummaryRead) _then) = _$PerformanceSummaryReadCopyWithImpl;
@useResult
$Res call({
 PerformanceSummaryIdentityRef identity, PerformanceCounters counters, TypedListRef effortBreakdowns
});


$PerformanceSummaryIdentityRefCopyWith<$Res> get identity;$PerformanceCountersCopyWith<$Res> get counters;$TypedListRefCopyWith<$Res> get effortBreakdowns;

}
/// @nodoc
class _$PerformanceSummaryReadCopyWithImpl<$Res>
    implements $PerformanceSummaryReadCopyWith<$Res> {
  _$PerformanceSummaryReadCopyWithImpl(this._self, this._then);

  final PerformanceSummaryRead _self;
  final $Res Function(PerformanceSummaryRead) _then;

/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,Object? effortBreakdowns = null,}) {
  return _then(PerformanceSummaryRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,effortBreakdowns: null == effortBreakdowns ? _self.effortBreakdowns : effortBreakdowns // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityRefCopyWith<$Res> get identity {

  return $PerformanceSummaryIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get effortBreakdowns {

  return $TypedListRefCopyWith<$Res>(_self.effortBreakdowns, (value) {
    return _then(_self.copyWith(effortBreakdowns: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummaryRead].
extension PerformanceSummaryReadPatterns on PerformanceSummaryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummaryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummaryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummaryRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummaryRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSummaryIdentityRef identity,  PerformanceCounters counters,  TypedListRef effortBreakdowns)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummaryRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSummaryIdentityRef identity,  PerformanceCounters counters,  TypedListRef effortBreakdowns)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSummaryIdentityRef identity,  PerformanceCounters counters,  TypedListRef effortBreakdowns)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryRead() when $default != null:
return $default(_that.identity,_that.counters,_that.effortBreakdowns);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummaryRead implements PerformanceSummaryRead {
  const _PerformanceSummaryRead({required this.identity, required this.counters, required this.effortBreakdowns});


@override final  PerformanceSummaryIdentityRef identity;
@override final  PerformanceCounters counters;
@override final  TypedListRef effortBreakdowns;

/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryReadCopyWith<_PerformanceSummaryRead> get copyWith => __$PerformanceSummaryReadCopyWithImpl<_PerformanceSummaryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummaryRead&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters)&&(identical(other.effortBreakdowns, effortBreakdowns) || other.effortBreakdowns == effortBreakdowns));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters,effortBreakdowns);
}

@override
String toString() {
    return 'PerformanceSummaryRead(identity: $identity, counters: $counters, effortBreakdowns: $effortBreakdowns)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummaryReadCopyWith<$Res> implements $PerformanceSummaryReadCopyWith<$Res> {
  factory _$PerformanceSummaryReadCopyWith(_PerformanceSummaryRead value, $Res Function(_PerformanceSummaryRead) _then) = __$PerformanceSummaryReadCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSummaryIdentityRef identity, PerformanceCounters counters, TypedListRef effortBreakdowns
});


@override $PerformanceSummaryIdentityRefCopyWith<$Res> get identity;@override $PerformanceCountersCopyWith<$Res> get counters;@override $TypedListRefCopyWith<$Res> get effortBreakdowns;

}
/// @nodoc
class __$PerformanceSummaryReadCopyWithImpl<$Res>
    implements _$PerformanceSummaryReadCopyWith<$Res> {
  __$PerformanceSummaryReadCopyWithImpl(this._self, this._then);

  final _PerformanceSummaryRead _self;
  final $Res Function(_PerformanceSummaryRead) _then;

/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,Object? effortBreakdowns = null,}) {
  return _then(_PerformanceSummaryRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,effortBreakdowns: null == effortBreakdowns ? _self.effortBreakdowns : effortBreakdowns // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityRefCopyWith<$Res> get identity {

  return $PerformanceSummaryIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}/// Create a copy of PerformanceSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get effortBreakdowns {

  return $TypedListRefCopyWith<$Res>(_self.effortBreakdowns, (value) {
    return _then(_self.copyWith(effortBreakdowns: value));
  });
}
}

/// @nodoc
mixin _$PerformanceEffortRead {

 PerformanceEffortIdentityRef get identity; PerformanceCounters get counters;
/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortReadCopyWith<PerformanceEffortRead> get copyWith => _$PerformanceEffortReadCopyWithImpl<PerformanceEffortRead>(this as PerformanceEffortRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffortRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffortRead&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters));
}


@override
int get hashCode {
  final _this = this as PerformanceEffortRead;
  return Object.hash(runtimeType,_this.identity,_this.counters);
}

@override
String toString() {
  final _this = this as PerformanceEffortRead;
  return 'PerformanceEffortRead(identity: ${_this.identity}, counters: ${_this.counters})';
}


}

/// @nodoc
abstract mixin class $PerformanceEffortReadCopyWith<$Res>  {
  factory $PerformanceEffortReadCopyWith(PerformanceEffortRead value, $Res Function(PerformanceEffortRead) _then) = _$PerformanceEffortReadCopyWithImpl;
@useResult
$Res call({
 PerformanceEffortIdentityRef identity, PerformanceCounters counters
});


$PerformanceEffortIdentityRefCopyWith<$Res> get identity;$PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class _$PerformanceEffortReadCopyWithImpl<$Res>
    implements $PerformanceEffortReadCopyWith<$Res> {
  _$PerformanceEffortReadCopyWithImpl(this._self, this._then);

  final PerformanceEffortRead _self;
  final $Res Function(PerformanceEffortRead) _then;

/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(PerformanceEffortRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceEffortIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,
  ));
}
/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityRefCopyWith<$Res> get identity {

  return $PerformanceEffortIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceCountersCopyWith<$Res> get counters {

  return $PerformanceCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceEffortRead].
extension PerformanceEffortReadPatterns on PerformanceEffortRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffortRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffortRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffortRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffortRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceEffortIdentityRef identity,  PerformanceCounters counters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceEffortRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceEffortIdentityRef identity,  PerformanceCounters counters)  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceEffortIdentityRef identity,  PerformanceCounters counters)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortRead() when $default != null:
return $default(_that.identity,_that.counters);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffortRead implements PerformanceEffortRead {
  const _PerformanceEffortRead({required this.identity, required this.counters});


@override final  PerformanceEffortIdentityRef identity;
@override final  PerformanceCounters counters;

/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortReadCopyWith<_PerformanceEffortRead> get copyWith => __$PerformanceEffortReadCopyWithImpl<_PerformanceEffortRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffortRead&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters);
}

@override
String toString() {
    return 'PerformanceEffortRead(identity: $identity, counters: $counters)';
}


}

/// @nodoc
abstract mixin class _$PerformanceEffortReadCopyWith<$Res> implements $PerformanceEffortReadCopyWith<$Res> {
  factory _$PerformanceEffortReadCopyWith(_PerformanceEffortRead value, $Res Function(_PerformanceEffortRead) _then) = __$PerformanceEffortReadCopyWithImpl;
@override @useResult
$Res call({
 PerformanceEffortIdentityRef identity, PerformanceCounters counters
});


@override $PerformanceEffortIdentityRefCopyWith<$Res> get identity;@override $PerformanceCountersCopyWith<$Res> get counters;

}
/// @nodoc
class __$PerformanceEffortReadCopyWithImpl<$Res>
    implements _$PerformanceEffortReadCopyWith<$Res> {
  __$PerformanceEffortReadCopyWithImpl(this._self, this._then);

  final _PerformanceEffortRead _self;
  final $Res Function(_PerformanceEffortRead) _then;

/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(_PerformanceEffortRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceEffortIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceCounters,
  ));
}

/// Create a copy of PerformanceEffortRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityRefCopyWith<$Res> get identity {

  return $PerformanceEffortIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceEffortRead
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
mixin _$PerformanceSampleRead {

 PerformanceSampleIdentityRef get identity; PerformanceSampleCounters get counters;
/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleReadCopyWith<PerformanceSampleRead> get copyWith => _$PerformanceSampleReadCopyWithImpl<PerformanceSampleRead>(this as PerformanceSampleRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleRead&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.counters, _this.counters) || other.counters == _this.counters));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleRead;
  return Object.hash(runtimeType,_this.identity,_this.counters);
}

@override
String toString() {
  final _this = this as PerformanceSampleRead;
  return 'PerformanceSampleRead(identity: ${_this.identity}, counters: ${_this.counters})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleReadCopyWith<$Res>  {
  factory $PerformanceSampleReadCopyWith(PerformanceSampleRead value, $Res Function(PerformanceSampleRead) _then) = _$PerformanceSampleReadCopyWithImpl;
@useResult
$Res call({
 PerformanceSampleIdentityRef identity, PerformanceSampleCounters counters
});


$PerformanceSampleIdentityRefCopyWith<$Res> get identity;$PerformanceSampleCountersCopyWith<$Res> get counters;

}
/// @nodoc
class _$PerformanceSampleReadCopyWithImpl<$Res>
    implements $PerformanceSampleReadCopyWith<$Res> {
  _$PerformanceSampleReadCopyWithImpl(this._self, this._then);

  final PerformanceSampleRead _self;
  final $Res Function(PerformanceSampleRead) _then;

/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(PerformanceSampleRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSampleIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceSampleCounters,
  ));
}
/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityRefCopyWith<$Res> get identity {

  return $PerformanceSampleIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleCountersCopyWith<$Res> get counters {

  return $PerformanceSampleCountersCopyWith<$Res>(_self.counters, (value) {
    return _then(_self.copyWith(counters: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSampleRead].
extension PerformanceSampleReadPatterns on PerformanceSampleRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSampleIdentityRef identity,  PerformanceSampleCounters counters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSampleRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSampleIdentityRef identity,  PerformanceSampleCounters counters)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSampleIdentityRef identity,  PerformanceSampleCounters counters)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleRead() when $default != null:
return $default(_that.identity,_that.counters);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleRead implements PerformanceSampleRead {
  const _PerformanceSampleRead({required this.identity, required this.counters});


@override final  PerformanceSampleIdentityRef identity;
@override final  PerformanceSampleCounters counters;

/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleReadCopyWith<_PerformanceSampleRead> get copyWith => __$PerformanceSampleReadCopyWithImpl<_PerformanceSampleRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleRead&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.counters, counters) || other.counters == counters));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,counters);
}

@override
String toString() {
    return 'PerformanceSampleRead(identity: $identity, counters: $counters)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleReadCopyWith<$Res> implements $PerformanceSampleReadCopyWith<$Res> {
  factory _$PerformanceSampleReadCopyWith(_PerformanceSampleRead value, $Res Function(_PerformanceSampleRead) _then) = __$PerformanceSampleReadCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSampleIdentityRef identity, PerformanceSampleCounters counters
});


@override $PerformanceSampleIdentityRefCopyWith<$Res> get identity;@override $PerformanceSampleCountersCopyWith<$Res> get counters;

}
/// @nodoc
class __$PerformanceSampleReadCopyWithImpl<$Res>
    implements _$PerformanceSampleReadCopyWith<$Res> {
  __$PerformanceSampleReadCopyWithImpl(this._self, this._then);

  final _PerformanceSampleRead _self;
  final $Res Function(_PerformanceSampleRead) _then;

/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? counters = null,}) {
  return _then(_PerformanceSampleRead(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as PerformanceSampleIdentityRef,counters: null == counters ? _self.counters : counters // ignore: cast_nullable_to_non_nullable
as PerformanceSampleCounters,
  ));
}

/// Create a copy of PerformanceSampleRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityRefCopyWith<$Res> get identity {

  return $PerformanceSampleIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSampleRead
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
mixin _$PerformanceSummaryIdentityRead {

 ReadText get accountId; ReadText get accountDisplayName; ReadText get modelId;
/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityReadCopyWith<PerformanceSummaryIdentityRead> get copyWith => _$PerformanceSummaryIdentityReadCopyWithImpl<PerformanceSummaryIdentityRead>(this as PerformanceSummaryIdentityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummaryIdentityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummaryIdentityRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.accountDisplayName, _this.accountDisplayName) || other.accountDisplayName == _this.accountDisplayName)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as PerformanceSummaryIdentityRead;
  return Object.hash(runtimeType,_this.accountId,_this.accountDisplayName,_this.modelId);
}



}

/// @nodoc
abstract mixin class $PerformanceSummaryIdentityReadCopyWith<$Res>  {
  factory $PerformanceSummaryIdentityReadCopyWith(PerformanceSummaryIdentityRead value, $Res Function(PerformanceSummaryIdentityRead) _then) = _$PerformanceSummaryIdentityReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, ReadText accountDisplayName, ReadText modelId
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get accountDisplayName;$ReadTextCopyWith<$Res> get modelId;

}
/// @nodoc
class _$PerformanceSummaryIdentityReadCopyWithImpl<$Res>
    implements $PerformanceSummaryIdentityReadCopyWith<$Res> {
  _$PerformanceSummaryIdentityReadCopyWithImpl(this._self, this._then);

  final PerformanceSummaryIdentityRead _self;
  final $Res Function(PerformanceSummaryIdentityRead) _then;

/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = null,}) {
  return _then(PerformanceSummaryIdentityRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountDisplayName {

  return $ReadTextCopyWith<$Res>(_self.accountDisplayName, (value) {
    return _then(_self.copyWith(accountDisplayName: value));
  });
}/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummaryIdentityRead].
extension PerformanceSummaryIdentityReadPatterns on PerformanceSummaryIdentityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentityRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummaryIdentityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText accountDisplayName,  ReadText modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText accountDisplayName,  ReadText modelId)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  ReadText accountDisplayName,  ReadText modelId)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRead() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummaryIdentityRead implements PerformanceSummaryIdentityRead {
  const _PerformanceSummaryIdentityRead({required this.accountId, required this.accountDisplayName, required this.modelId});


@override final  ReadText accountId;
@override final  ReadText accountDisplayName;
@override final  ReadText modelId;

/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryIdentityReadCopyWith<_PerformanceSummaryIdentityRead> get copyWith => __$PerformanceSummaryIdentityReadCopyWithImpl<_PerformanceSummaryIdentityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummaryIdentityRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.accountDisplayName, accountDisplayName) || other.accountDisplayName == accountDisplayName)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,accountDisplayName,modelId);
}



}

/// @nodoc
abstract mixin class _$PerformanceSummaryIdentityReadCopyWith<$Res> implements $PerformanceSummaryIdentityReadCopyWith<$Res> {
  factory _$PerformanceSummaryIdentityReadCopyWith(_PerformanceSummaryIdentityRead value, $Res Function(_PerformanceSummaryIdentityRead) _then) = __$PerformanceSummaryIdentityReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, ReadText accountDisplayName, ReadText modelId
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get accountDisplayName;@override $ReadTextCopyWith<$Res> get modelId;

}
/// @nodoc
class __$PerformanceSummaryIdentityReadCopyWithImpl<$Res>
    implements _$PerformanceSummaryIdentityReadCopyWith<$Res> {
  __$PerformanceSummaryIdentityReadCopyWithImpl(this._self, this._then);

  final _PerformanceSummaryIdentityRead _self;
  final $Res Function(_PerformanceSummaryIdentityRead) _then;

/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = null,}) {
  return _then(_PerformanceSummaryIdentityRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountDisplayName {

  return $ReadTextCopyWith<$Res>(_self.accountDisplayName, (value) {
    return _then(_self.copyWith(accountDisplayName: value));
  });
}/// Create a copy of PerformanceSummaryIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}

/// @nodoc
mixin _$PerformanceEffortIdentityRead {

 ReadText? get effort;
/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityReadCopyWith<PerformanceEffortIdentityRead> get copyWith => _$PerformanceEffortIdentityReadCopyWithImpl<PerformanceEffortIdentityRead>(this as PerformanceEffortIdentityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffortIdentityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffortIdentityRead&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as PerformanceEffortIdentityRead;
  return Object.hash(runtimeType,_this.effort);
}



}

/// @nodoc
abstract mixin class $PerformanceEffortIdentityReadCopyWith<$Res>  {
  factory $PerformanceEffortIdentityReadCopyWith(PerformanceEffortIdentityRead value, $Res Function(PerformanceEffortIdentityRead) _then) = _$PerformanceEffortIdentityReadCopyWithImpl;
@useResult
$Res call({
 ReadText? effort
});


$ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class _$PerformanceEffortIdentityReadCopyWithImpl<$Res>
    implements $PerformanceEffortIdentityReadCopyWith<$Res> {
  _$PerformanceEffortIdentityReadCopyWithImpl(this._self, this._then);

  final PerformanceEffortIdentityRead _self;
  final $Res Function(PerformanceEffortIdentityRead) _then;

/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effort = freezed,}) {
  return _then(PerformanceEffortIdentityRead(
effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceEffortIdentityRead].
extension PerformanceEffortIdentityReadPatterns on PerformanceEffortIdentityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffortIdentityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffortIdentityRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffortIdentityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText? effort)  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText? effort)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRead() when $default != null:
return $default(_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffortIdentityRead implements PerformanceEffortIdentityRead {
  const _PerformanceEffortIdentityRead({required this.effort});


@override final  ReadText? effort;

/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortIdentityReadCopyWith<_PerformanceEffortIdentityRead> get copyWith => __$PerformanceEffortIdentityReadCopyWithImpl<_PerformanceEffortIdentityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffortIdentityRead&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effort);
}



}

/// @nodoc
abstract mixin class _$PerformanceEffortIdentityReadCopyWith<$Res> implements $PerformanceEffortIdentityReadCopyWith<$Res> {
  factory _$PerformanceEffortIdentityReadCopyWith(_PerformanceEffortIdentityRead value, $Res Function(_PerformanceEffortIdentityRead) _then) = __$PerformanceEffortIdentityReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText? effort
});


@override $ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class __$PerformanceEffortIdentityReadCopyWithImpl<$Res>
    implements _$PerformanceEffortIdentityReadCopyWith<$Res> {
  __$PerformanceEffortIdentityReadCopyWithImpl(this._self, this._then);

  final _PerformanceEffortIdentityRead _self;
  final $Res Function(_PerformanceEffortIdentityRead) _then;

/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effort = freezed,}) {
  return _then(_PerformanceEffortIdentityRead(
effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of PerformanceEffortIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSampleIdentityRead {

 ReadText get accountId; ReadText get accountDisplayName; ReadText? get modelId; ReadText? get sentModel; ReadText? get reportedModel; ModelMatchState get modelMatchState; ReadText? get effort;
/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityReadCopyWith<PerformanceSampleIdentityRead> get copyWith => _$PerformanceSampleIdentityReadCopyWithImpl<PerformanceSampleIdentityRead>(this as PerformanceSampleIdentityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleIdentityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleIdentityRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.accountDisplayName, _this.accountDisplayName) || other.accountDisplayName == _this.accountDisplayName)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.sentModel, _this.sentModel) || other.sentModel == _this.sentModel)&&(identical(other.reportedModel, _this.reportedModel) || other.reportedModel == _this.reportedModel)&&(identical(other.modelMatchState, _this.modelMatchState) || other.modelMatchState == _this.modelMatchState)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleIdentityRead;
  return Object.hash(runtimeType,_this.accountId,_this.accountDisplayName,_this.modelId,_this.sentModel,_this.reportedModel,_this.modelMatchState,_this.effort);
}



}

/// @nodoc
abstract mixin class $PerformanceSampleIdentityReadCopyWith<$Res>  {
  factory $PerformanceSampleIdentityReadCopyWith(PerformanceSampleIdentityRead value, $Res Function(PerformanceSampleIdentityRead) _then) = _$PerformanceSampleIdentityReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, ReadText accountDisplayName, ReadText? modelId, ReadText? sentModel, ReadText? reportedModel, ModelMatchState modelMatchState, ReadText? effort
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get accountDisplayName;$ReadTextCopyWith<$Res>? get modelId;$ReadTextCopyWith<$Res>? get sentModel;$ReadTextCopyWith<$Res>? get reportedModel;$ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class _$PerformanceSampleIdentityReadCopyWithImpl<$Res>
    implements $PerformanceSampleIdentityReadCopyWith<$Res> {
  _$PerformanceSampleIdentityReadCopyWithImpl(this._self, this._then);

  final PerformanceSampleIdentityRead _self;
  final $Res Function(PerformanceSampleIdentityRead) _then;

/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = freezed,Object? sentModel = freezed,Object? reportedModel = freezed,Object? modelMatchState = null,Object? effort = freezed,}) {
  return _then(PerformanceSampleIdentityRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText?,sentModel: freezed == sentModel ? _self.sentModel : sentModel // ignore: cast_nullable_to_non_nullable
as ReadText?,reportedModel: freezed == reportedModel ? _self.reportedModel : reportedModel // ignore: cast_nullable_to_non_nullable
as ReadText?,modelMatchState: null == modelMatchState ? _self.modelMatchState : modelMatchState // ignore: cast_nullable_to_non_nullable
as ModelMatchState,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountDisplayName {

  return $ReadTextCopyWith<$Res>(_self.accountDisplayName, (value) {
    return _then(_self.copyWith(accountDisplayName: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get modelId {
    if (_self.modelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.modelId!, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get sentModel {
    if (_self.sentModel == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.sentModel!, (value) {
    return _then(_self.copyWith(sentModel: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get reportedModel {
    if (_self.reportedModel == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.reportedModel!, (value) {
    return _then(_self.copyWith(reportedModel: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSampleIdentityRead].
extension PerformanceSampleIdentityReadPatterns on PerformanceSampleIdentityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleIdentityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleIdentityRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleIdentityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText accountDisplayName,  ReadText? modelId,  ReadText? sentModel,  ReadText? reportedModel,  ModelMatchState modelMatchState,  ReadText? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText accountDisplayName,  ReadText? modelId,  ReadText? sentModel,  ReadText? reportedModel,  ModelMatchState modelMatchState,  ReadText? effort)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  ReadText accountDisplayName,  ReadText? modelId,  ReadText? sentModel,  ReadText? reportedModel,  ModelMatchState modelMatchState,  ReadText? effort)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRead() when $default != null:
return $default(_that.accountId,_that.accountDisplayName,_that.modelId,_that.sentModel,_that.reportedModel,_that.modelMatchState,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleIdentityRead implements PerformanceSampleIdentityRead {
  const _PerformanceSampleIdentityRead({required this.accountId, required this.accountDisplayName, required this.modelId, required this.sentModel, required this.reportedModel, required this.modelMatchState, required this.effort});


@override final  ReadText accountId;
@override final  ReadText accountDisplayName;
@override final  ReadText? modelId;
@override final  ReadText? sentModel;
@override final  ReadText? reportedModel;
@override final  ModelMatchState modelMatchState;
@override final  ReadText? effort;

/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleIdentityReadCopyWith<_PerformanceSampleIdentityRead> get copyWith => __$PerformanceSampleIdentityReadCopyWithImpl<_PerformanceSampleIdentityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleIdentityRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.accountDisplayName, accountDisplayName) || other.accountDisplayName == accountDisplayName)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.sentModel, sentModel) || other.sentModel == sentModel)&&(identical(other.reportedModel, reportedModel) || other.reportedModel == reportedModel)&&(identical(other.modelMatchState, modelMatchState) || other.modelMatchState == modelMatchState)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,accountDisplayName,modelId,sentModel,reportedModel,modelMatchState,effort);
}



}

/// @nodoc
abstract mixin class _$PerformanceSampleIdentityReadCopyWith<$Res> implements $PerformanceSampleIdentityReadCopyWith<$Res> {
  factory _$PerformanceSampleIdentityReadCopyWith(_PerformanceSampleIdentityRead value, $Res Function(_PerformanceSampleIdentityRead) _then) = __$PerformanceSampleIdentityReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, ReadText accountDisplayName, ReadText? modelId, ReadText? sentModel, ReadText? reportedModel, ModelMatchState modelMatchState, ReadText? effort
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get accountDisplayName;@override $ReadTextCopyWith<$Res>? get modelId;@override $ReadTextCopyWith<$Res>? get sentModel;@override $ReadTextCopyWith<$Res>? get reportedModel;@override $ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class __$PerformanceSampleIdentityReadCopyWithImpl<$Res>
    implements _$PerformanceSampleIdentityReadCopyWith<$Res> {
  __$PerformanceSampleIdentityReadCopyWithImpl(this._self, this._then);

  final _PerformanceSampleIdentityRead _self;
  final $Res Function(_PerformanceSampleIdentityRead) _then;

/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? accountDisplayName = null,Object? modelId = freezed,Object? sentModel = freezed,Object? reportedModel = freezed,Object? modelMatchState = null,Object? effort = freezed,}) {
  return _then(_PerformanceSampleIdentityRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText?,sentModel: freezed == sentModel ? _self.sentModel : sentModel // ignore: cast_nullable_to_non_nullable
as ReadText?,reportedModel: freezed == reportedModel ? _self.reportedModel : reportedModel // ignore: cast_nullable_to_non_nullable
as ReadText?,modelMatchState: null == modelMatchState ? _self.modelMatchState : modelMatchState // ignore: cast_nullable_to_non_nullable
as ModelMatchState,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountDisplayName {

  return $ReadTextCopyWith<$Res>(_self.accountDisplayName, (value) {
    return _then(_self.copyWith(accountDisplayName: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get modelId {
    if (_self.modelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.modelId!, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get sentModel {
    if (_self.sentModel == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.sentModel!, (value) {
    return _then(_self.copyWith(sentModel: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get reportedModel {
    if (_self.reportedModel == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.reportedModel!, (value) {
    return _then(_self.copyWith(reportedModel: value));
  });
}/// Create a copy of PerformanceSampleIdentityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}

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
mixin _$PerformanceSummariesEntryPage {

 ProductCollectionRef get collection; int get offset; List<ProductEntityRef> get items; int? get nextOffset;
/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesEntryPageCopyWith<PerformanceSummariesEntryPage> get copyWith => _$PerformanceSummariesEntryPageCopyWithImpl<PerformanceSummariesEntryPage>(this as PerformanceSummariesEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PerformanceSummariesEntryPage;
  return 'PerformanceSummariesEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesEntryPageCopyWith<$Res>  {
  factory $PerformanceSummariesEntryPageCopyWith(PerformanceSummariesEntryPage value, $Res Function(PerformanceSummariesEntryPage) _then) = _$PerformanceSummariesEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$PerformanceSummariesEntryPageCopyWithImpl<$Res>
    implements $PerformanceSummariesEntryPageCopyWith<$Res> {
  _$PerformanceSummariesEntryPageCopyWithImpl(this._self, this._then);

  final PerformanceSummariesEntryPage _self;
  final $Res Function(PerformanceSummariesEntryPage) _then;

/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PerformanceSummariesEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesEntryPage].
extension PerformanceSummariesEntryPagePatterns on PerformanceSummariesEntryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesEntryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesEntryPage value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesEntryPage value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage():
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesEntryPage implements PerformanceSummariesEntryPage {
  const _PerformanceSummariesEntryPage({required this.collection, required this.offset, required  List<ProductEntityRef> items, required this.nextOffset}): _items = items;


@override final  ProductCollectionRef collection;
@override final  int offset;
 final  List<ProductEntityRef> _items;
@override List<ProductEntityRef> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesEntryPageCopyWith<_PerformanceSummariesEntryPage> get copyWith => __$PerformanceSummariesEntryPageCopyWithImpl<_PerformanceSummariesEntryPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesEntryPage&&(identical(other.collection, collection) || other.collection == collection)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,collection,offset,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'PerformanceSummariesEntryPage(collection: $collection, offset: $offset, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesEntryPageCopyWith<$Res> implements $PerformanceSummariesEntryPageCopyWith<$Res> {
  factory _$PerformanceSummariesEntryPageCopyWith(_PerformanceSummariesEntryPage value, $Res Function(_PerformanceSummariesEntryPage) _then) = __$PerformanceSummariesEntryPageCopyWithImpl;
@override @useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


@override $ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class __$PerformanceSummariesEntryPageCopyWithImpl<$Res>
    implements _$PerformanceSummariesEntryPageCopyWith<$Res> {
  __$PerformanceSummariesEntryPageCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesEntryPage _self;
  final $Res Function(_PerformanceSummariesEntryPage) _then;

/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PerformanceSummariesEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of PerformanceSummariesEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSummariesEntityRead {

 ProductEntityRef get reference; PerformanceSummaryRead get value;
/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesEntityReadCopyWith<PerformanceSummariesEntityRead> get copyWith => _$PerformanceSummariesEntityReadCopyWithImpl<PerformanceSummariesEntityRead>(this as PerformanceSummariesEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}

@override
String toString() {
  final _this = this as PerformanceSummariesEntityRead;
  return 'PerformanceSummariesEntityRead(reference: ${_this.reference}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesEntityReadCopyWith<$Res>  {
  factory $PerformanceSummariesEntityReadCopyWith(PerformanceSummariesEntityRead value, $Res Function(PerformanceSummariesEntityRead) _then) = _$PerformanceSummariesEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, PerformanceSummaryRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$PerformanceSummaryReadCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceSummariesEntityReadCopyWithImpl<$Res>
    implements $PerformanceSummariesEntityReadCopyWith<$Res> {
  _$PerformanceSummariesEntityReadCopyWithImpl(this._self, this._then);

  final PerformanceSummariesEntityRead _self;
  final $Res Function(PerformanceSummariesEntityRead) _then;

/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(PerformanceSummariesEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryRead,
  ));
}
/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryReadCopyWith<$Res> get value {

  return $PerformanceSummaryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesEntityRead].
extension PerformanceSummariesEntityReadPatterns on PerformanceSummariesEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  PerformanceSummaryRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  PerformanceSummaryRead value)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  PerformanceSummaryRead value)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesEntityRead implements PerformanceSummariesEntityRead {
  const _PerformanceSummariesEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  PerformanceSummaryRead value;

/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesEntityReadCopyWith<_PerformanceSummariesEntityRead> get copyWith => __$PerformanceSummariesEntityReadCopyWithImpl<_PerformanceSummariesEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}

@override
String toString() {
    return 'PerformanceSummariesEntityRead(reference: $reference, value: $value)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesEntityReadCopyWith<$Res> implements $PerformanceSummariesEntityReadCopyWith<$Res> {
  factory _$PerformanceSummariesEntityReadCopyWith(_PerformanceSummariesEntityRead value, $Res Function(_PerformanceSummariesEntityRead) _then) = __$PerformanceSummariesEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, PerformanceSummaryRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $PerformanceSummaryReadCopyWith<$Res> get value;

}
/// @nodoc
class __$PerformanceSummariesEntityReadCopyWithImpl<$Res>
    implements _$PerformanceSummariesEntityReadCopyWith<$Res> {
  __$PerformanceSummariesEntityReadCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesEntityRead _self;
  final $Res Function(_PerformanceSummariesEntityRead) _then;

/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_PerformanceSummariesEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSummaryRead,
  ));
}

/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PerformanceSummariesEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummaryReadCopyWith<$Res> get value {

  return $PerformanceSummaryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryEntryPage {

 ProductCollectionRef get collection; int get offset; List<ProductEntityRef> get items; int? get nextOffset;
/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryEntryPageCopyWith<PerformanceHistoryEntryPage> get copyWith => _$PerformanceHistoryEntryPageCopyWithImpl<PerformanceHistoryEntryPage>(this as PerformanceHistoryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PerformanceHistoryEntryPage;
  return 'PerformanceHistoryEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryEntryPageCopyWith<$Res>  {
  factory $PerformanceHistoryEntryPageCopyWith(PerformanceHistoryEntryPage value, $Res Function(PerformanceHistoryEntryPage) _then) = _$PerformanceHistoryEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$PerformanceHistoryEntryPageCopyWithImpl<$Res>
    implements $PerformanceHistoryEntryPageCopyWith<$Res> {
  _$PerformanceHistoryEntryPageCopyWithImpl(this._self, this._then);

  final PerformanceHistoryEntryPage _self;
  final $Res Function(PerformanceHistoryEntryPage) _then;

/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PerformanceHistoryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryEntryPage].
extension PerformanceHistoryEntryPagePatterns on PerformanceHistoryEntryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryEntryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryEntryPage value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryEntryPage value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage():
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryEntryPage implements PerformanceHistoryEntryPage {
  const _PerformanceHistoryEntryPage({required this.collection, required this.offset, required  List<ProductEntityRef> items, required this.nextOffset}): _items = items;


@override final  ProductCollectionRef collection;
@override final  int offset;
 final  List<ProductEntityRef> _items;
@override List<ProductEntityRef> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryEntryPageCopyWith<_PerformanceHistoryEntryPage> get copyWith => __$PerformanceHistoryEntryPageCopyWithImpl<_PerformanceHistoryEntryPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryEntryPage&&(identical(other.collection, collection) || other.collection == collection)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,collection,offset,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'PerformanceHistoryEntryPage(collection: $collection, offset: $offset, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryEntryPageCopyWith<$Res> implements $PerformanceHistoryEntryPageCopyWith<$Res> {
  factory _$PerformanceHistoryEntryPageCopyWith(_PerformanceHistoryEntryPage value, $Res Function(_PerformanceHistoryEntryPage) _then) = __$PerformanceHistoryEntryPageCopyWithImpl;
@override @useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


@override $ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class __$PerformanceHistoryEntryPageCopyWithImpl<$Res>
    implements _$PerformanceHistoryEntryPageCopyWith<$Res> {
  __$PerformanceHistoryEntryPageCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryEntryPage _self;
  final $Res Function(_PerformanceHistoryEntryPage) _then;

/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PerformanceHistoryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of PerformanceHistoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryEntityRead {

 ProductEntityRef get reference; PerformanceSampleRead get value;
/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryEntityReadCopyWith<PerformanceHistoryEntityRead> get copyWith => _$PerformanceHistoryEntityReadCopyWithImpl<PerformanceHistoryEntityRead>(this as PerformanceHistoryEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}

@override
String toString() {
  final _this = this as PerformanceHistoryEntityRead;
  return 'PerformanceHistoryEntityRead(reference: ${_this.reference}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryEntityReadCopyWith<$Res>  {
  factory $PerformanceHistoryEntityReadCopyWith(PerformanceHistoryEntityRead value, $Res Function(PerformanceHistoryEntityRead) _then) = _$PerformanceHistoryEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, PerformanceSampleRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$PerformanceSampleReadCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceHistoryEntityReadCopyWithImpl<$Res>
    implements $PerformanceHistoryEntityReadCopyWith<$Res> {
  _$PerformanceHistoryEntityReadCopyWithImpl(this._self, this._then);

  final PerformanceHistoryEntityRead _self;
  final $Res Function(PerformanceHistoryEntityRead) _then;

/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(PerformanceHistoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSampleRead,
  ));
}
/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleReadCopyWith<$Res> get value {

  return $PerformanceSampleReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryEntityRead].
extension PerformanceHistoryEntityReadPatterns on PerformanceHistoryEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  PerformanceSampleRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  PerformanceSampleRead value)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  PerformanceSampleRead value)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryEntityRead implements PerformanceHistoryEntityRead {
  const _PerformanceHistoryEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  PerformanceSampleRead value;

/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryEntityReadCopyWith<_PerformanceHistoryEntityRead> get copyWith => __$PerformanceHistoryEntityReadCopyWithImpl<_PerformanceHistoryEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}

@override
String toString() {
    return 'PerformanceHistoryEntityRead(reference: $reference, value: $value)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryEntityReadCopyWith<$Res> implements $PerformanceHistoryEntityReadCopyWith<$Res> {
  factory _$PerformanceHistoryEntityReadCopyWith(_PerformanceHistoryEntityRead value, $Res Function(_PerformanceHistoryEntityRead) _then) = __$PerformanceHistoryEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, PerformanceSampleRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $PerformanceSampleReadCopyWith<$Res> get value;

}
/// @nodoc
class __$PerformanceHistoryEntityReadCopyWithImpl<$Res>
    implements _$PerformanceHistoryEntityReadCopyWith<$Res> {
  __$PerformanceHistoryEntityReadCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryEntityRead _self;
  final $Res Function(_PerformanceHistoryEntityRead) _then;

/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_PerformanceHistoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSampleRead,
  ));
}

/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PerformanceHistoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSampleReadCopyWith<$Res> get value {

  return $PerformanceSampleReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSummaryReadPage {

 int get listId; int get offset; int get total; List<PerformanceSummaryRead> get items; int? get nextOffset;
/// Create a copy of PerformanceSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryReadPageCopyWith<PerformanceSummaryReadPage> get copyWith => _$PerformanceSummaryReadPageCopyWithImpl<PerformanceSummaryReadPage>(this as PerformanceSummaryReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummaryReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummaryReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PerformanceSummaryReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PerformanceSummaryReadPage;
  return 'PerformanceSummaryReadPage(listId: ${_this.listId}, offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummaryReadPageCopyWith<$Res>  {
  factory $PerformanceSummaryReadPageCopyWith(PerformanceSummaryReadPage value, $Res Function(PerformanceSummaryReadPage) _then) = _$PerformanceSummaryReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<PerformanceSummaryRead> items, int? nextOffset
});




}
/// @nodoc
class _$PerformanceSummaryReadPageCopyWithImpl<$Res>
    implements $PerformanceSummaryReadPageCopyWith<$Res> {
  _$PerformanceSummaryReadPageCopyWithImpl(this._self, this._then);

  final PerformanceSummaryReadPage _self;
  final $Res Function(PerformanceSummaryReadPage) _then;

/// Create a copy of PerformanceSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PerformanceSummaryReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceSummaryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSummaryReadPage].
extension PerformanceSummaryReadPagePatterns on PerformanceSummaryReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummaryReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummaryReadPage value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummaryReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceSummaryRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceSummaryRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<PerformanceSummaryRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummaryReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummaryReadPage implements PerformanceSummaryReadPage {
  const _PerformanceSummaryReadPage({required this.listId, required this.offset, required this.total, required  List<PerformanceSummaryRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<PerformanceSummaryRead> _items;
@override List<PerformanceSummaryRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PerformanceSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryReadPageCopyWith<_PerformanceSummaryReadPage> get copyWith => __$PerformanceSummaryReadPageCopyWithImpl<_PerformanceSummaryReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummaryReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'PerformanceSummaryReadPage(listId: $listId, offset: $offset, total: $total, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummaryReadPageCopyWith<$Res> implements $PerformanceSummaryReadPageCopyWith<$Res> {
  factory _$PerformanceSummaryReadPageCopyWith(_PerformanceSummaryReadPage value, $Res Function(_PerformanceSummaryReadPage) _then) = __$PerformanceSummaryReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<PerformanceSummaryRead> items, int? nextOffset
});




}
/// @nodoc
class __$PerformanceSummaryReadPageCopyWithImpl<$Res>
    implements _$PerformanceSummaryReadPageCopyWith<$Res> {
  __$PerformanceSummaryReadPageCopyWithImpl(this._self, this._then);

  final _PerformanceSummaryReadPage _self;
  final $Res Function(_PerformanceSummaryReadPage) _then;

/// Create a copy of PerformanceSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PerformanceSummaryReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceSummaryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$PerformanceEffortReadPage {

 int get listId; int get offset; int get total; List<PerformanceEffortRead> get items; int? get nextOffset;
/// Create a copy of PerformanceEffortReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortReadPageCopyWith<PerformanceEffortReadPage> get copyWith => _$PerformanceEffortReadPageCopyWithImpl<PerformanceEffortReadPage>(this as PerformanceEffortReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffortReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffortReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PerformanceEffortReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PerformanceEffortReadPage;
  return 'PerformanceEffortReadPage(listId: ${_this.listId}, offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PerformanceEffortReadPageCopyWith<$Res>  {
  factory $PerformanceEffortReadPageCopyWith(PerformanceEffortReadPage value, $Res Function(PerformanceEffortReadPage) _then) = _$PerformanceEffortReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<PerformanceEffortRead> items, int? nextOffset
});




}
/// @nodoc
class _$PerformanceEffortReadPageCopyWithImpl<$Res>
    implements $PerformanceEffortReadPageCopyWith<$Res> {
  _$PerformanceEffortReadPageCopyWithImpl(this._self, this._then);

  final PerformanceEffortReadPage _self;
  final $Res Function(PerformanceEffortReadPage) _then;

/// Create a copy of PerformanceEffortReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PerformanceEffortReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceEffortRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceEffortReadPage].
extension PerformanceEffortReadPagePatterns on PerformanceEffortReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffortReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffortReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffortReadPage value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffortReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceEffortRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceEffortReadPage() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceEffortRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortReadPage():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<PerformanceEffortRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceEffortReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffortReadPage implements PerformanceEffortReadPage {
  const _PerformanceEffortReadPage({required this.listId, required this.offset, required this.total, required  List<PerformanceEffortRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<PerformanceEffortRead> _items;
@override List<PerformanceEffortRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PerformanceEffortReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortReadPageCopyWith<_PerformanceEffortReadPage> get copyWith => __$PerformanceEffortReadPageCopyWithImpl<_PerformanceEffortReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffortReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'PerformanceEffortReadPage(listId: $listId, offset: $offset, total: $total, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$PerformanceEffortReadPageCopyWith<$Res> implements $PerformanceEffortReadPageCopyWith<$Res> {
  factory _$PerformanceEffortReadPageCopyWith(_PerformanceEffortReadPage value, $Res Function(_PerformanceEffortReadPage) _then) = __$PerformanceEffortReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<PerformanceEffortRead> items, int? nextOffset
});




}
/// @nodoc
class __$PerformanceEffortReadPageCopyWithImpl<$Res>
    implements _$PerformanceEffortReadPageCopyWith<$Res> {
  __$PerformanceEffortReadPageCopyWithImpl(this._self, this._then);

  final _PerformanceEffortReadPage _self;
  final $Res Function(_PerformanceEffortReadPage) _then;

/// Create a copy of PerformanceEffortReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PerformanceEffortReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceEffortRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$PerformanceSampleReadPage {

 int get listId; int get offset; int get total; List<PerformanceSampleRead> get items; int? get nextOffset;
/// Create a copy of PerformanceSampleReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleReadPageCopyWith<PerformanceSampleReadPage> get copyWith => _$PerformanceSampleReadPageCopyWithImpl<PerformanceSampleReadPage>(this as PerformanceSampleReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PerformanceSampleReadPage;
  return 'PerformanceSampleReadPage(listId: ${_this.listId}, offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleReadPageCopyWith<$Res>  {
  factory $PerformanceSampleReadPageCopyWith(PerformanceSampleReadPage value, $Res Function(PerformanceSampleReadPage) _then) = _$PerformanceSampleReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<PerformanceSampleRead> items, int? nextOffset
});




}
/// @nodoc
class _$PerformanceSampleReadPageCopyWithImpl<$Res>
    implements $PerformanceSampleReadPageCopyWith<$Res> {
  _$PerformanceSampleReadPageCopyWithImpl(this._self, this._then);

  final PerformanceSampleReadPage _self;
  final $Res Function(PerformanceSampleReadPage) _then;

/// Create a copy of PerformanceSampleReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PerformanceSampleReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceSampleRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSampleReadPage].
extension PerformanceSampleReadPagePatterns on PerformanceSampleReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleReadPage value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceSampleRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSampleReadPage() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<PerformanceSampleRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleReadPage():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<PerformanceSampleRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSampleReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleReadPage implements PerformanceSampleReadPage {
  const _PerformanceSampleReadPage({required this.listId, required this.offset, required this.total, required  List<PerformanceSampleRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<PerformanceSampleRead> _items;
@override List<PerformanceSampleRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of PerformanceSampleReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleReadPageCopyWith<_PerformanceSampleReadPage> get copyWith => __$PerformanceSampleReadPageCopyWithImpl<_PerformanceSampleReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'PerformanceSampleReadPage(listId: $listId, offset: $offset, total: $total, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleReadPageCopyWith<$Res> implements $PerformanceSampleReadPageCopyWith<$Res> {
  factory _$PerformanceSampleReadPageCopyWith(_PerformanceSampleReadPage value, $Res Function(_PerformanceSampleReadPage) _then) = __$PerformanceSampleReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<PerformanceSampleRead> items, int? nextOffset
});




}
/// @nodoc
class __$PerformanceSampleReadPageCopyWithImpl<$Res>
    implements _$PerformanceSampleReadPageCopyWith<$Res> {
  __$PerformanceSampleReadPageCopyWithImpl(this._self, this._then);

  final _PerformanceSampleReadPage _self;
  final $Res Function(_PerformanceSampleReadPage) _then;

/// Create a copy of PerformanceSampleReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_PerformanceSampleReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PerformanceSampleRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
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
