// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StatisticsModelKey {

 String get accountId; String? get modelId;
/// Create a copy of StatisticsModelKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsModelKeyCopyWith<StatisticsModelKey> get copyWith => _$StatisticsModelKeyCopyWithImpl<StatisticsModelKey>(this as StatisticsModelKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsModelKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsModelKey&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as StatisticsModelKey;
  return Object.hash(runtimeType,_this.accountId,_this.modelId);
}

@override
String toString() {
  final _this = this as StatisticsModelKey;
  return 'StatisticsModelKey(accountId: ${_this.accountId}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $StatisticsModelKeyCopyWith<$Res>  {
  factory $StatisticsModelKeyCopyWith(StatisticsModelKey value, $Res Function(StatisticsModelKey) _then) = _$StatisticsModelKeyCopyWithImpl;
@useResult
$Res call({
 String accountId, String? modelId
});




}
/// @nodoc
class _$StatisticsModelKeyCopyWithImpl<$Res>
    implements $StatisticsModelKeyCopyWith<$Res> {
  _$StatisticsModelKeyCopyWithImpl(this._self, this._then);

  final StatisticsModelKey _self;
  final $Res Function(StatisticsModelKey) _then;

/// Create a copy of StatisticsModelKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? modelId = freezed,}) {
  return _then(StatisticsModelKey(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StatisticsModelKey].
extension StatisticsModelKeyPatterns on StatisticsModelKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsModelKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsModelKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsModelKey value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsModelKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsModelKey value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsModelKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String? modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsModelKey() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String? modelId)  $default,) {final _that = this;
switch (_that) {
case _StatisticsModelKey():
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String? modelId)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsModelKey() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsModelKey implements StatisticsModelKey {
  const _StatisticsModelKey({required this.accountId, required this.modelId});


@override final  String accountId;
@override final  String? modelId;

/// Create a copy of StatisticsModelKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsModelKeyCopyWith<_StatisticsModelKey> get copyWith => __$StatisticsModelKeyCopyWithImpl<_StatisticsModelKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsModelKey&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId);
}

@override
String toString() {
    return 'StatisticsModelKey(accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$StatisticsModelKeyCopyWith<$Res> implements $StatisticsModelKeyCopyWith<$Res> {
  factory _$StatisticsModelKeyCopyWith(_StatisticsModelKey value, $Res Function(_StatisticsModelKey) _then) = __$StatisticsModelKeyCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String? modelId
});




}
/// @nodoc
class __$StatisticsModelKeyCopyWithImpl<$Res>
    implements _$StatisticsModelKeyCopyWith<$Res> {
  __$StatisticsModelKeyCopyWithImpl(this._self, this._then);

  final _StatisticsModelKey _self;
  final $Res Function(_StatisticsModelKey) _then;

/// Create a copy of StatisticsModelKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = freezed,}) {
  return _then(_StatisticsModelKey(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$StatisticsEffortFilter {

 String? get value;
/// Create a copy of StatisticsEffortFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsEffortFilterCopyWith<StatisticsEffortFilter> get copyWith => _$StatisticsEffortFilterCopyWithImpl<StatisticsEffortFilter>(this as StatisticsEffortFilter, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsEffortFilter;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsEffortFilter&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as StatisticsEffortFilter;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as StatisticsEffortFilter;
  return 'StatisticsEffortFilter(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $StatisticsEffortFilterCopyWith<$Res>  {
  factory $StatisticsEffortFilterCopyWith(StatisticsEffortFilter value, $Res Function(StatisticsEffortFilter) _then) = _$StatisticsEffortFilterCopyWithImpl;
@useResult
$Res call({
 String? value
});




}
/// @nodoc
class _$StatisticsEffortFilterCopyWithImpl<$Res>
    implements $StatisticsEffortFilterCopyWith<$Res> {
  _$StatisticsEffortFilterCopyWithImpl(this._self, this._then);

  final StatisticsEffortFilter _self;
  final $Res Function(StatisticsEffortFilter) _then;

/// Create a copy of StatisticsEffortFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = freezed,}) {
  return _then(StatisticsEffortFilter(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StatisticsEffortFilter].
extension StatisticsEffortFilterPatterns on StatisticsEffortFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsEffortFilter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsEffortFilter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsEffortFilter value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsEffortFilter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsEffortFilter value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsEffortFilter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsEffortFilter() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? value)  $default,) {final _that = this;
switch (_that) {
case _StatisticsEffortFilter():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? value)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsEffortFilter() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsEffortFilter implements StatisticsEffortFilter {
  const _StatisticsEffortFilter({required this.value});


@override final  String? value;

/// Create a copy of StatisticsEffortFilter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsEffortFilterCopyWith<_StatisticsEffortFilter> get copyWith => __$StatisticsEffortFilterCopyWithImpl<_StatisticsEffortFilter>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsEffortFilter&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'StatisticsEffortFilter(value: $value)';
}


}

/// @nodoc
abstract mixin class _$StatisticsEffortFilterCopyWith<$Res> implements $StatisticsEffortFilterCopyWith<$Res> {
  factory _$StatisticsEffortFilterCopyWith(_StatisticsEffortFilter value, $Res Function(_StatisticsEffortFilter) _then) = __$StatisticsEffortFilterCopyWithImpl;
@override @useResult
$Res call({
 String? value
});




}
/// @nodoc
class __$StatisticsEffortFilterCopyWithImpl<$Res>
    implements _$StatisticsEffortFilterCopyWith<$Res> {
  __$StatisticsEffortFilterCopyWithImpl(this._self, this._then);

  final _StatisticsEffortFilter _self;
  final $Res Function(_StatisticsEffortFilter) _then;

/// Create a copy of StatisticsEffortFilter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(_StatisticsEffortFilter(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$StatisticsModelOption {

 StatisticsModelKey get key; String get accountDisplayName; String get displayModel;
/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsModelOptionCopyWith<StatisticsModelOption> get copyWith => _$StatisticsModelOptionCopyWithImpl<StatisticsModelOption>(this as StatisticsModelOption, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsModelOption;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsModelOption&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.accountDisplayName, _this.accountDisplayName) || other.accountDisplayName == _this.accountDisplayName)&&(identical(other.displayModel, _this.displayModel) || other.displayModel == _this.displayModel));
}


@override
int get hashCode {
  final _this = this as StatisticsModelOption;
  return Object.hash(runtimeType,_this.key,_this.accountDisplayName,_this.displayModel);
}



}

/// @nodoc
abstract mixin class $StatisticsModelOptionCopyWith<$Res>  {
  factory $StatisticsModelOptionCopyWith(StatisticsModelOption value, $Res Function(StatisticsModelOption) _then) = _$StatisticsModelOptionCopyWithImpl;
@useResult
$Res call({
 StatisticsModelKey key, String accountDisplayName, String displayModel
});


$StatisticsModelKeyCopyWith<$Res> get key;

}
/// @nodoc
class _$StatisticsModelOptionCopyWithImpl<$Res>
    implements $StatisticsModelOptionCopyWith<$Res> {
  _$StatisticsModelOptionCopyWithImpl(this._self, this._then);

  final StatisticsModelOption _self;
  final $Res Function(StatisticsModelOption) _then;

/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? accountDisplayName = null,Object? displayModel = null,}) {
  return _then(StatisticsModelOption(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as StatisticsModelKey,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,displayModel: null == displayModel ? _self.displayModel : displayModel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsModelKeyCopyWith<$Res> get key {

  return $StatisticsModelKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsModelOption].
extension StatisticsModelOptionPatterns on StatisticsModelOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsModelOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsModelOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsModelOption value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsModelOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsModelOption value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsModelOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StatisticsModelKey key,  String accountDisplayName,  String displayModel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsModelOption() when $default != null:
return $default(_that.key,_that.accountDisplayName,_that.displayModel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StatisticsModelKey key,  String accountDisplayName,  String displayModel)  $default,) {final _that = this;
switch (_that) {
case _StatisticsModelOption():
return $default(_that.key,_that.accountDisplayName,_that.displayModel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StatisticsModelKey key,  String accountDisplayName,  String displayModel)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsModelOption() when $default != null:
return $default(_that.key,_that.accountDisplayName,_that.displayModel);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsModelOption implements StatisticsModelOption {
  const _StatisticsModelOption({required this.key, required this.accountDisplayName, required this.displayModel});


@override final  StatisticsModelKey key;
@override final  String accountDisplayName;
@override final  String displayModel;

/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsModelOptionCopyWith<_StatisticsModelOption> get copyWith => __$StatisticsModelOptionCopyWithImpl<_StatisticsModelOption>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsModelOption&&(identical(other.key, key) || other.key == key)&&(identical(other.accountDisplayName, accountDisplayName) || other.accountDisplayName == accountDisplayName)&&(identical(other.displayModel, displayModel) || other.displayModel == displayModel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,accountDisplayName,displayModel);
}



}

/// @nodoc
abstract mixin class _$StatisticsModelOptionCopyWith<$Res> implements $StatisticsModelOptionCopyWith<$Res> {
  factory _$StatisticsModelOptionCopyWith(_StatisticsModelOption value, $Res Function(_StatisticsModelOption) _then) = __$StatisticsModelOptionCopyWithImpl;
@override @useResult
$Res call({
 StatisticsModelKey key, String accountDisplayName, String displayModel
});


@override $StatisticsModelKeyCopyWith<$Res> get key;

}
/// @nodoc
class __$StatisticsModelOptionCopyWithImpl<$Res>
    implements _$StatisticsModelOptionCopyWith<$Res> {
  __$StatisticsModelOptionCopyWithImpl(this._self, this._then);

  final _StatisticsModelOption _self;
  final $Res Function(_StatisticsModelOption) _then;

/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? accountDisplayName = null,Object? displayModel = null,}) {
  return _then(_StatisticsModelOption(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as StatisticsModelKey,accountDisplayName: null == accountDisplayName ? _self.accountDisplayName : accountDisplayName // ignore: cast_nullable_to_non_nullable
as String,displayModel: null == displayModel ? _self.displayModel : displayModel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of StatisticsModelOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsModelKeyCopyWith<$Res> get key {

  return $StatisticsModelKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}
}

/// @nodoc
mixin _$StatisticsViewState {

 StatisticsState get source; bool get visible; StatisticsModelKey? get modelFilter; StatisticsEffortFilter? get effortFilter; bool get mismatchesOnly; List<PerformanceSample> get filteredHistory; List<StatisticsModelOption> get modelOptions; List<StatisticsEffortFilter> get effortOptions;
/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsViewStateCopyWith<StatisticsViewState> get copyWith => _$StatisticsViewStateCopyWithImpl<StatisticsViewState>(this as StatisticsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&(identical(other.modelFilter, _this.modelFilter) || other.modelFilter == _this.modelFilter)&&(identical(other.effortFilter, _this.effortFilter) || other.effortFilter == _this.effortFilter)&&(identical(other.mismatchesOnly, _this.mismatchesOnly) || other.mismatchesOnly == _this.mismatchesOnly)&&const DeepCollectionEquality().equals(other.filteredHistory, _this.filteredHistory)&&const DeepCollectionEquality().equals(other.modelOptions, _this.modelOptions)&&const DeepCollectionEquality().equals(other.effortOptions, _this.effortOptions));
}


@override
int get hashCode {
  final _this = this as StatisticsViewState;
  return Object.hash(runtimeType,_this.source,_this.visible,_this.modelFilter,_this.effortFilter,_this.mismatchesOnly,const DeepCollectionEquality().hash(_this.filteredHistory),const DeepCollectionEquality().hash(_this.modelOptions),const DeepCollectionEquality().hash(_this.effortOptions));
}



}

/// @nodoc
abstract mixin class $StatisticsViewStateCopyWith<$Res>  {
  factory $StatisticsViewStateCopyWith(StatisticsViewState value, $Res Function(StatisticsViewState) _then) = _$StatisticsViewStateCopyWithImpl;
@useResult
$Res call({
 StatisticsState source, bool visible, StatisticsModelKey? modelFilter, StatisticsEffortFilter? effortFilter, bool mismatchesOnly, List<PerformanceSample> filteredHistory, List<StatisticsModelOption> modelOptions, List<StatisticsEffortFilter> effortOptions
});


$StatisticsStateCopyWith<$Res> get source;$StatisticsModelKeyCopyWith<$Res>? get modelFilter;$StatisticsEffortFilterCopyWith<$Res>? get effortFilter;

}
/// @nodoc
class _$StatisticsViewStateCopyWithImpl<$Res>
    implements $StatisticsViewStateCopyWith<$Res> {
  _$StatisticsViewStateCopyWithImpl(this._self, this._then);

  final StatisticsViewState _self;
  final $Res Function(StatisticsViewState) _then;

/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? visible = null,Object? modelFilter = freezed,Object? effortFilter = freezed,Object? mismatchesOnly = null,Object? filteredHistory = null,Object? modelOptions = null,Object? effortOptions = null,}) {
  return _then(StatisticsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as StatisticsState,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,modelFilter: freezed == modelFilter ? _self.modelFilter : modelFilter // ignore: cast_nullable_to_non_nullable
as StatisticsModelKey?,effortFilter: freezed == effortFilter ? _self.effortFilter : effortFilter // ignore: cast_nullable_to_non_nullable
as StatisticsEffortFilter?,mismatchesOnly: null == mismatchesOnly ? _self.mismatchesOnly : mismatchesOnly // ignore: cast_nullable_to_non_nullable
as bool,filteredHistory: null == filteredHistory ? _self.filteredHistory : filteredHistory // ignore: cast_nullable_to_non_nullable
as List<PerformanceSample>,modelOptions: null == modelOptions ? _self.modelOptions : modelOptions // ignore: cast_nullable_to_non_nullable
as List<StatisticsModelOption>,effortOptions: null == effortOptions ? _self.effortOptions : effortOptions // ignore: cast_nullable_to_non_nullable
as List<StatisticsEffortFilter>,
  ));
}
/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsStateCopyWith<$Res> get source {

  return $StatisticsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsModelKeyCopyWith<$Res>? get modelFilter {
    if (_self.modelFilter == null) {
    return null;
  }

  return $StatisticsModelKeyCopyWith<$Res>(_self.modelFilter!, (value) {
    return _then(_self.copyWith(modelFilter: value));
  });
}/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsEffortFilterCopyWith<$Res>? get effortFilter {
    if (_self.effortFilter == null) {
    return null;
  }

  return $StatisticsEffortFilterCopyWith<$Res>(_self.effortFilter!, (value) {
    return _then(_self.copyWith(effortFilter: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsViewState].
extension StatisticsViewStatePatterns on StatisticsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsViewState value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StatisticsState source,  bool visible,  StatisticsModelKey? modelFilter,  StatisticsEffortFilter? effortFilter,  bool mismatchesOnly,  List<PerformanceSample> filteredHistory,  List<StatisticsModelOption> modelOptions,  List<StatisticsEffortFilter> effortOptions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsViewState() when $default != null:
return $default(_that.source,_that.visible,_that.modelFilter,_that.effortFilter,_that.mismatchesOnly,_that.filteredHistory,_that.modelOptions,_that.effortOptions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StatisticsState source,  bool visible,  StatisticsModelKey? modelFilter,  StatisticsEffortFilter? effortFilter,  bool mismatchesOnly,  List<PerformanceSample> filteredHistory,  List<StatisticsModelOption> modelOptions,  List<StatisticsEffortFilter> effortOptions)  $default,) {final _that = this;
switch (_that) {
case _StatisticsViewState():
return $default(_that.source,_that.visible,_that.modelFilter,_that.effortFilter,_that.mismatchesOnly,_that.filteredHistory,_that.modelOptions,_that.effortOptions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StatisticsState source,  bool visible,  StatisticsModelKey? modelFilter,  StatisticsEffortFilter? effortFilter,  bool mismatchesOnly,  List<PerformanceSample> filteredHistory,  List<StatisticsModelOption> modelOptions,  List<StatisticsEffortFilter> effortOptions)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsViewState() when $default != null:
return $default(_that.source,_that.visible,_that.modelFilter,_that.effortFilter,_that.mismatchesOnly,_that.filteredHistory,_that.modelOptions,_that.effortOptions);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsViewState extends StatisticsViewState {
  const _StatisticsViewState({required this.source, required this.visible, this.modelFilter, this.effortFilter, this.mismatchesOnly = false,  List<PerformanceSample> filteredHistory = const <PerformanceSample>[],  List<StatisticsModelOption> modelOptions = const <StatisticsModelOption>[],  List<StatisticsEffortFilter> effortOptions = const <StatisticsEffortFilter>[]}): _filteredHistory = filteredHistory,_modelOptions = modelOptions,_effortOptions = effortOptions,super._();


@override final  StatisticsState source;
@override final  bool visible;
@override final  StatisticsModelKey? modelFilter;
@override final  StatisticsEffortFilter? effortFilter;
@override@JsonKey() final  bool mismatchesOnly;
 final  List<PerformanceSample> _filteredHistory;
@override@JsonKey() List<PerformanceSample> get filteredHistory {
  if (_filteredHistory is EqualUnmodifiableListView) return _filteredHistory;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_filteredHistory);
}

 final  List<StatisticsModelOption> _modelOptions;
@override@JsonKey() List<StatisticsModelOption> get modelOptions {
  if (_modelOptions is EqualUnmodifiableListView) return _modelOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modelOptions);
}

 final  List<StatisticsEffortFilter> _effortOptions;
@override@JsonKey() List<StatisticsEffortFilter> get effortOptions {
  if (_effortOptions is EqualUnmodifiableListView) return _effortOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_effortOptions);
}


/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsViewStateCopyWith<_StatisticsViewState> get copyWith => __$StatisticsViewStateCopyWithImpl<_StatisticsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.modelFilter, modelFilter) || other.modelFilter == modelFilter)&&(identical(other.effortFilter, effortFilter) || other.effortFilter == effortFilter)&&(identical(other.mismatchesOnly, mismatchesOnly) || other.mismatchesOnly == mismatchesOnly)&&const DeepCollectionEquality().equals(other.filteredHistory, _filteredHistory)&&const DeepCollectionEquality().equals(other.modelOptions, _modelOptions)&&const DeepCollectionEquality().equals(other.effortOptions, _effortOptions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,visible,modelFilter,effortFilter,mismatchesOnly,const DeepCollectionEquality().hash(_filteredHistory),const DeepCollectionEquality().hash(_modelOptions),const DeepCollectionEquality().hash(_effortOptions));
}



}

/// @nodoc
abstract mixin class _$StatisticsViewStateCopyWith<$Res> implements $StatisticsViewStateCopyWith<$Res> {
  factory _$StatisticsViewStateCopyWith(_StatisticsViewState value, $Res Function(_StatisticsViewState) _then) = __$StatisticsViewStateCopyWithImpl;
@override @useResult
$Res call({
 StatisticsState source, bool visible, StatisticsModelKey? modelFilter, StatisticsEffortFilter? effortFilter, bool mismatchesOnly, List<PerformanceSample> filteredHistory, List<StatisticsModelOption> modelOptions, List<StatisticsEffortFilter> effortOptions
});


@override $StatisticsStateCopyWith<$Res> get source;@override $StatisticsModelKeyCopyWith<$Res>? get modelFilter;@override $StatisticsEffortFilterCopyWith<$Res>? get effortFilter;

}
/// @nodoc
class __$StatisticsViewStateCopyWithImpl<$Res>
    implements _$StatisticsViewStateCopyWith<$Res> {
  __$StatisticsViewStateCopyWithImpl(this._self, this._then);

  final _StatisticsViewState _self;
  final $Res Function(_StatisticsViewState) _then;

/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? visible = null,Object? modelFilter = freezed,Object? effortFilter = freezed,Object? mismatchesOnly = null,Object? filteredHistory = null,Object? modelOptions = null,Object? effortOptions = null,}) {
  return _then(_StatisticsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as StatisticsState,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,modelFilter: freezed == modelFilter ? _self.modelFilter : modelFilter // ignore: cast_nullable_to_non_nullable
as StatisticsModelKey?,effortFilter: freezed == effortFilter ? _self.effortFilter : effortFilter // ignore: cast_nullable_to_non_nullable
as StatisticsEffortFilter?,mismatchesOnly: null == mismatchesOnly ? _self.mismatchesOnly : mismatchesOnly // ignore: cast_nullable_to_non_nullable
as bool,filteredHistory: null == filteredHistory ? _self._filteredHistory : filteredHistory // ignore: cast_nullable_to_non_nullable
as List<PerformanceSample>,modelOptions: null == modelOptions ? _self._modelOptions : modelOptions // ignore: cast_nullable_to_non_nullable
as List<StatisticsModelOption>,effortOptions: null == effortOptions ? _self._effortOptions : effortOptions // ignore: cast_nullable_to_non_nullable
as List<StatisticsEffortFilter>,
  ));
}

/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsStateCopyWith<$Res> get source {

  return $StatisticsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsModelKeyCopyWith<$Res>? get modelFilter {
    if (_self.modelFilter == null) {
    return null;
  }

  return $StatisticsModelKeyCopyWith<$Res>(_self.modelFilter!, (value) {
    return _then(_self.copyWith(modelFilter: value));
  });
}/// Create a copy of StatisticsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatisticsEffortFilterCopyWith<$Res>? get effortFilter {
    if (_self.effortFilter == null) {
    return null;
  }

  return $StatisticsEffortFilterCopyWith<$Res>(_self.effortFilter!, (value) {
    return _then(_self.copyWith(effortFilter: value));
  });
}
}

// dart format on
