// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PerformanceSummariesHeader {

 int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; PerformanceSummariesReadRef get reference;
/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<PerformanceSummariesHeader> get copyWith => _$PerformanceSummariesHeaderCopyWithImpl<PerformanceSummariesHeader>(this as PerformanceSummariesHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceSummariesHeader;
  return 'PerformanceSummariesHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsPending: ${_this.statisticsPending}, statisticsGap: ${_this.statisticsGap}, readFailed: ${_this.readFailed}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesHeaderCopyWith<$Res>  {
  factory $PerformanceSummariesHeaderCopyWith(PerformanceSummariesHeader value, $Res Function(PerformanceSummariesHeader) _then) = _$PerformanceSummariesHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef reference
});


$PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceSummariesHeaderCopyWithImpl<$Res>
    implements $PerformanceSummariesHeaderCopyWith<$Res> {
  _$PerformanceSummariesHeaderCopyWithImpl(this._self, this._then);

  final PerformanceSummariesHeader _self;
  final $Res Function(PerformanceSummariesHeader) _then;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(PerformanceSummariesHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}
/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesHeader].
extension PerformanceSummariesHeaderPatterns on PerformanceSummariesHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader():
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesHeader implements PerformanceSummariesHeader {
  const _PerformanceSummariesHeader({required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.reference});


@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  PerformanceSummariesReadRef reference;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesHeaderCopyWith<_PerformanceSummariesHeader> get copyWith => __$PerformanceSummariesHeaderCopyWithImpl<_PerformanceSummariesHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,statisticsPending,statisticsGap,readFailed,reference);
}

@override
String toString() {
    return 'PerformanceSummariesHeader(revision: $revision, updatedAt: $updatedAt, statisticsPending: $statisticsPending, statisticsGap: $statisticsGap, readFailed: $readFailed, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesHeaderCopyWith<$Res> implements $PerformanceSummariesHeaderCopyWith<$Res> {
  factory _$PerformanceSummariesHeaderCopyWith(_PerformanceSummariesHeader value, $Res Function(_PerformanceSummariesHeader) _then) = __$PerformanceSummariesHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef reference
});


@override $PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceSummariesHeaderCopyWithImpl<$Res>
    implements _$PerformanceSummariesHeaderCopyWith<$Res> {
  __$PerformanceSummariesHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesHeader _self;
  final $Res Function(_PerformanceSummariesHeader) _then;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(_PerformanceSummariesHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryHeader {

 int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; PerformanceHistoryReadRef get reference;
/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<PerformanceHistoryHeader> get copyWith => _$PerformanceHistoryHeaderCopyWithImpl<PerformanceHistoryHeader>(this as PerformanceHistoryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceHistoryHeader;
  return 'PerformanceHistoryHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsPending: ${_this.statisticsPending}, statisticsGap: ${_this.statisticsGap}, readFailed: ${_this.readFailed}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryHeaderCopyWith<$Res>  {
  factory $PerformanceHistoryHeaderCopyWith(PerformanceHistoryHeader value, $Res Function(PerformanceHistoryHeader) _then) = _$PerformanceHistoryHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceHistoryReadRef reference
});


$PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceHistoryHeaderCopyWithImpl<$Res>
    implements $PerformanceHistoryHeaderCopyWith<$Res> {
  _$PerformanceHistoryHeaderCopyWithImpl(this._self, this._then);

  final PerformanceHistoryHeader _self;
  final $Res Function(PerformanceHistoryHeader) _then;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(PerformanceHistoryHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}
/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryHeader].
extension PerformanceHistoryHeaderPatterns on PerformanceHistoryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader():
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryHeader implements PerformanceHistoryHeader {
  const _PerformanceHistoryHeader({required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.reference});


@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  PerformanceHistoryReadRef reference;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryHeaderCopyWith<_PerformanceHistoryHeader> get copyWith => __$PerformanceHistoryHeaderCopyWithImpl<_PerformanceHistoryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,statisticsPending,statisticsGap,readFailed,reference);
}

@override
String toString() {
    return 'PerformanceHistoryHeader(revision: $revision, updatedAt: $updatedAt, statisticsPending: $statisticsPending, statisticsGap: $statisticsGap, readFailed: $readFailed, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryHeaderCopyWith<$Res> implements $PerformanceHistoryHeaderCopyWith<$Res> {
  factory _$PerformanceHistoryHeaderCopyWith(_PerformanceHistoryHeader value, $Res Function(_PerformanceHistoryHeader) _then) = __$PerformanceHistoryHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceHistoryReadRef reference
});


@override $PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceHistoryHeaderCopyWithImpl<$Res>
    implements _$PerformanceHistoryHeaderCopyWith<$Res> {
  __$PerformanceHistoryHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryHeader _self;
  final $Res Function(_PerformanceHistoryHeader) _then;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(_PerformanceHistoryHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$StatisticsSnapshot {

 ProductReadOrigin get origin; int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; PerformanceSummariesReadRef get summariesReference; PerformanceHistoryReadRef get historyReference; List<PerformanceSummary> get summaries; List<PerformanceSample> get history;
/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsSnapshotCopyWith<StatisticsSnapshot> get copyWith => _$StatisticsSnapshotCopyWithImpl<StatisticsSnapshot>(this as StatisticsSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsSnapshot&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.summariesReference, _this.summariesReference) || other.summariesReference == _this.summariesReference)&&(identical(other.historyReference, _this.historyReference) || other.historyReference == _this.historyReference)&&const DeepCollectionEquality().equals(other.summaries, _this.summaries)&&const DeepCollectionEquality().equals(other.history, _this.history));
}


@override
int get hashCode {
  final _this = this as StatisticsSnapshot;
  return Object.hash(runtimeType,_this.origin,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.summariesReference,_this.historyReference,const DeepCollectionEquality().hash(_this.summaries),const DeepCollectionEquality().hash(_this.history));
}



}

/// @nodoc
abstract mixin class $StatisticsSnapshotCopyWith<$Res>  {
  factory $StatisticsSnapshotCopyWith(StatisticsSnapshot value, $Res Function(StatisticsSnapshot) _then) = _$StatisticsSnapshotCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef summariesReference, PerformanceHistoryReadRef historyReference, List<PerformanceSummary> summaries, List<PerformanceSample> history
});


$ProductReadOriginCopyWith<$Res> get origin;$PerformanceSummariesReadRefCopyWith<$Res> get summariesReference;$PerformanceHistoryReadRefCopyWith<$Res> get historyReference;

}
/// @nodoc
class _$StatisticsSnapshotCopyWithImpl<$Res>
    implements $StatisticsSnapshotCopyWith<$Res> {
  _$StatisticsSnapshotCopyWithImpl(this._self, this._then);

  final StatisticsSnapshot _self;
  final $Res Function(StatisticsSnapshot) _then;

/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? summariesReference = null,Object? historyReference = null,Object? summaries = null,Object? history = null,}) {
  return _then(StatisticsSnapshot(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,summariesReference: null == summariesReference ? _self.summariesReference : summariesReference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,historyReference: null == historyReference ? _self.historyReference : historyReference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,summaries: null == summaries ? _self.summaries : summaries // ignore: cast_nullable_to_non_nullable
as List<PerformanceSummary>,history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as List<PerformanceSample>,
  ));
}
/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get summariesReference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.summariesReference, (value) {
    return _then(_self.copyWith(summariesReference: value));
  });
}/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get historyReference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.historyReference, (value) {
    return _then(_self.copyWith(historyReference: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsSnapshot].
extension StatisticsSnapshotPatterns on StatisticsSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef summariesReference,  PerformanceHistoryReadRef historyReference,  List<PerformanceSummary> summaries,  List<PerformanceSample> history)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsSnapshot() when $default != null:
return $default(_that.origin,_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.summariesReference,_that.historyReference,_that.summaries,_that.history);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef summariesReference,  PerformanceHistoryReadRef historyReference,  List<PerformanceSummary> summaries,  List<PerformanceSample> history)  $default,) {final _that = this;
switch (_that) {
case _StatisticsSnapshot():
return $default(_that.origin,_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.summariesReference,_that.historyReference,_that.summaries,_that.history);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef summariesReference,  PerformanceHistoryReadRef historyReference,  List<PerformanceSummary> summaries,  List<PerformanceSample> history)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsSnapshot() when $default != null:
return $default(_that.origin,_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.summariesReference,_that.historyReference,_that.summaries,_that.history);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsSnapshot implements StatisticsSnapshot {
  const _StatisticsSnapshot({required this.origin, required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.summariesReference, required this.historyReference, required  List<PerformanceSummary> summaries, required  List<PerformanceSample> history}): _summaries = summaries,_history = history;


@override final  ProductReadOrigin origin;
@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  PerformanceSummariesReadRef summariesReference;
@override final  PerformanceHistoryReadRef historyReference;
 final  List<PerformanceSummary> _summaries;
@override List<PerformanceSummary> get summaries {
  if (_summaries is EqualUnmodifiableListView) return _summaries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_summaries);
}

 final  List<PerformanceSample> _history;
@override List<PerformanceSample> get history {
  if (_history is EqualUnmodifiableListView) return _history;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_history);
}


/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsSnapshotCopyWith<_StatisticsSnapshot> get copyWith => __$StatisticsSnapshotCopyWithImpl<_StatisticsSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsSnapshot&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.summariesReference, summariesReference) || other.summariesReference == summariesReference)&&(identical(other.historyReference, historyReference) || other.historyReference == historyReference)&&const DeepCollectionEquality().equals(other.summaries, _summaries)&&const DeepCollectionEquality().equals(other.history, _history));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,revision,updatedAt,statisticsPending,statisticsGap,readFailed,summariesReference,historyReference,const DeepCollectionEquality().hash(_summaries),const DeepCollectionEquality().hash(_history));
}



}

/// @nodoc
abstract mixin class _$StatisticsSnapshotCopyWith<$Res> implements $StatisticsSnapshotCopyWith<$Res> {
  factory _$StatisticsSnapshotCopyWith(_StatisticsSnapshot value, $Res Function(_StatisticsSnapshot) _then) = __$StatisticsSnapshotCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef summariesReference, PerformanceHistoryReadRef historyReference, List<PerformanceSummary> summaries, List<PerformanceSample> history
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $PerformanceSummariesReadRefCopyWith<$Res> get summariesReference;@override $PerformanceHistoryReadRefCopyWith<$Res> get historyReference;

}
/// @nodoc
class __$StatisticsSnapshotCopyWithImpl<$Res>
    implements _$StatisticsSnapshotCopyWith<$Res> {
  __$StatisticsSnapshotCopyWithImpl(this._self, this._then);

  final _StatisticsSnapshot _self;
  final $Res Function(_StatisticsSnapshot) _then;

/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? summariesReference = null,Object? historyReference = null,Object? summaries = null,Object? history = null,}) {
  return _then(_StatisticsSnapshot(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,summariesReference: null == summariesReference ? _self.summariesReference : summariesReference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,historyReference: null == historyReference ? _self.historyReference : historyReference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,summaries: null == summaries ? _self._summaries : summaries // ignore: cast_nullable_to_non_nullable
as List<PerformanceSummary>,history: null == history ? _self._history : history // ignore: cast_nullable_to_non_nullable
as List<PerformanceSample>,
  ));
}

/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get summariesReference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.summariesReference, (value) {
    return _then(_self.copyWith(summariesReference: value));
  });
}/// Create a copy of StatisticsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get historyReference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.historyReference, (value) {
    return _then(_self.copyWith(historyReference: value));
  });
}
}

/// @nodoc
mixin _$StatisticsState {

 StatisticsSnapshot? get snapshot; ResourceSyncState get sync;
/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsStateCopyWith<StatisticsState> get copyWith => _$StatisticsStateCopyWithImpl<StatisticsState>(this as StatisticsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsState&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as StatisticsState;
  return Object.hash(runtimeType,_this.snapshot,_this.sync);
}



}

/// @nodoc
abstract mixin class $StatisticsStateCopyWith<$Res>  {
  factory $StatisticsStateCopyWith(StatisticsState value, $Res Function(StatisticsState) _then) = _$StatisticsStateCopyWithImpl;
@useResult
$Res call({
 StatisticsSnapshot? snapshot, ResourceSyncState sync
});


$StatisticsSnapshotCopyWith<$Res>? get snapshot;$ResourceSyncStateCopyWith<$Res> get sync;

}
/// @nodoc
class _$StatisticsStateCopyWithImpl<$Res>
    implements $StatisticsStateCopyWith<$Res> {
  _$StatisticsStateCopyWithImpl(this._self, this._then);

  final StatisticsState _self;
  final $Res Function(StatisticsState) _then;

/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? snapshot = freezed,Object? sync = null,}) {
  return _then(StatisticsState(
snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as StatisticsSnapshot?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as ResourceSyncState,
  ));
}
/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsSnapshotCopyWith<$Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $StatisticsSnapshotCopyWith<$Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceSyncStateCopyWith<$Res> get sync {

  return $ResourceSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsState].
extension StatisticsStatePatterns on StatisticsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsState value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsState value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StatisticsSnapshot? snapshot,  ResourceSyncState sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsState() when $default != null:
return $default(_that.snapshot,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StatisticsSnapshot? snapshot,  ResourceSyncState sync)  $default,) {final _that = this;
switch (_that) {
case _StatisticsState():
return $default(_that.snapshot,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StatisticsSnapshot? snapshot,  ResourceSyncState sync)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsState() when $default != null:
return $default(_that.snapshot,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsState implements StatisticsState {
  const _StatisticsState({required this.snapshot, required this.sync});


@override final  StatisticsSnapshot? snapshot;
@override final  ResourceSyncState sync;

/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsStateCopyWith<_StatisticsState> get copyWith => __$StatisticsStateCopyWithImpl<_StatisticsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsState&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,snapshot,sync);
}



}

/// @nodoc
abstract mixin class _$StatisticsStateCopyWith<$Res> implements $StatisticsStateCopyWith<$Res> {
  factory _$StatisticsStateCopyWith(_StatisticsState value, $Res Function(_StatisticsState) _then) = __$StatisticsStateCopyWithImpl;
@override @useResult
$Res call({
 StatisticsSnapshot? snapshot, ResourceSyncState sync
});


@override $StatisticsSnapshotCopyWith<$Res>? get snapshot;@override $ResourceSyncStateCopyWith<$Res> get sync;

}
/// @nodoc
class __$StatisticsStateCopyWithImpl<$Res>
    implements _$StatisticsStateCopyWith<$Res> {
  __$StatisticsStateCopyWithImpl(this._self, this._then);

  final _StatisticsState _self;
  final $Res Function(_StatisticsState) _then;

/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? snapshot = freezed,Object? sync = null,}) {
  return _then(_StatisticsState(
snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as StatisticsSnapshot?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as ResourceSyncState,
  ));
}

/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsSnapshotCopyWith<$Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $StatisticsSnapshotCopyWith<$Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}/// Create a copy of StatisticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceSyncStateCopyWith<$Res> get sync {

  return $ResourceSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}

// dart format on
