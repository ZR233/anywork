// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_repository.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsBatchResult {


/// Create a copy of SettingsBatchResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsBatchResultCopyWith<SettingsBatchResult> get copyWith => _$SettingsBatchResultCopyWithImpl<SettingsBatchResult>(this as SettingsBatchResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsBatchResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsBatchResult&&const DeepCollectionEquality().equals(other.steps, _this.steps));
}


@override
int get hashCode {
  final _this = this as SettingsBatchResult;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.steps));
}



}

/// @nodoc
abstract mixin class $SettingsBatchResultCopyWith<$Res>  {
  factory $SettingsBatchResultCopyWith(SettingsBatchResult value, $Res Function(SettingsBatchResult) _then) = _$SettingsBatchResultCopyWithImpl;
@useResult
$Res call({
 List<SettingsFieldResult> steps
});




}
/// @nodoc
class _$SettingsBatchResultCopyWithImpl<$Res>
    implements $SettingsBatchResultCopyWith<$Res> {
  _$SettingsBatchResultCopyWithImpl(this._self, this._then);

  final SettingsBatchResult _self;
  final $Res Function(SettingsBatchResult) _then;

/// Create a copy of SettingsBatchResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? steps = null,}) {
  return _then(SettingsBatchResult(
steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<SettingsFieldResult>,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsBatchResult].
extension SettingsBatchResultPatterns on SettingsBatchResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$SettingsFieldResult {

 int get index; OperationId get operationId;
/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsFieldResultCopyWith<SettingsFieldResult> get copyWith => _$SettingsFieldResultCopyWithImpl<SettingsFieldResult>(this as SettingsFieldResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsFieldResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsFieldResult&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as SettingsFieldResult;
  return Object.hash(runtimeType,_this.index,_this.operationId);
}



}

/// @nodoc
abstract mixin class $SettingsFieldResultCopyWith<$Res>  {
  factory $SettingsFieldResultCopyWith(SettingsFieldResult value, $Res Function(SettingsFieldResult) _then) = _$SettingsFieldResultCopyWithImpl;
@useResult
$Res call({
 int index, OperationId operationId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SettingsFieldResultCopyWithImpl<$Res>
    implements $SettingsFieldResultCopyWith<$Res> {
  _$SettingsFieldResultCopyWithImpl(this._self, this._then);

  final SettingsFieldResult _self;
  final $Res Function(SettingsFieldResult) _then;

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? operationId = null,}) {
  return _then(_self.copyWith(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}
/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsFieldResult].
extension SettingsFieldResultPatterns on SettingsFieldResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FinishedSettingsField value)?  finished,TResult Function( NotStartedSettingsField value)?  notStarted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FinishedSettingsField() when finished != null:
return finished(_that);case NotStartedSettingsField() when notStarted != null:
return notStarted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FinishedSettingsField value)  finished,required TResult Function( NotStartedSettingsField value)  notStarted,}){
final _that = this;
switch (_that) {
case FinishedSettingsField():
return finished(_that);case NotStartedSettingsField():
return notStarted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FinishedSettingsField value)?  finished,TResult? Function( NotStartedSettingsField value)?  notStarted,}){
final _that = this;
switch (_that) {
case FinishedSettingsField() when finished != null:
return finished(_that);case NotStartedSettingsField() when notStarted != null:
return notStarted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int index,  OperationId operationId,  CommandResult<Unit> result)?  finished,TResult Function( int index,  OperationId operationId,  StudioFailure error)?  notStarted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FinishedSettingsField() when finished != null:
return finished(_that.index,_that.operationId,_that.result);case NotStartedSettingsField() when notStarted != null:
return notStarted(_that.index,_that.operationId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int index,  OperationId operationId,  CommandResult<Unit> result)  finished,required TResult Function( int index,  OperationId operationId,  StudioFailure error)  notStarted,}) {final _that = this;
switch (_that) {
case FinishedSettingsField():
return finished(_that.index,_that.operationId,_that.result);case NotStartedSettingsField():
return notStarted(_that.index,_that.operationId,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int index,  OperationId operationId,  CommandResult<Unit> result)?  finished,TResult? Function( int index,  OperationId operationId,  StudioFailure error)?  notStarted,}) {final _that = this;
switch (_that) {
case FinishedSettingsField() when finished != null:
return finished(_that.index,_that.operationId,_that.result);case NotStartedSettingsField() when notStarted != null:
return notStarted(_that.index,_that.operationId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class FinishedSettingsField implements SettingsFieldResult {
  const FinishedSettingsField({required this.index, required this.operationId, required this.result});


@override final  int index;
@override final  OperationId operationId;
 final  CommandResult<Unit> result;

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FinishedSettingsFieldCopyWith<FinishedSettingsField> get copyWith => _$FinishedSettingsFieldCopyWithImpl<FinishedSettingsField>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FinishedSettingsField&&(identical(other.index, index) || other.index == index)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,operationId,result);
}



}

/// @nodoc
abstract mixin class $FinishedSettingsFieldCopyWith<$Res> implements $SettingsFieldResultCopyWith<$Res> {
  factory $FinishedSettingsFieldCopyWith(FinishedSettingsField value, $Res Function(FinishedSettingsField) _then) = _$FinishedSettingsFieldCopyWithImpl;
@override @useResult
$Res call({
 int index, OperationId operationId, CommandResult<Unit> result
});


@override $OperationIdCopyWith<$Res> get operationId;$CommandResultCopyWith<Unit, $Res> get result;

}
/// @nodoc
class _$FinishedSettingsFieldCopyWithImpl<$Res>
    implements $FinishedSettingsFieldCopyWith<$Res> {
  _$FinishedSettingsFieldCopyWithImpl(this._self, this._then);

  final FinishedSettingsField _self;
  final $Res Function(FinishedSettingsField) _then;

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? operationId = null,Object? result = null,}) {
  return _then(FinishedSettingsField(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<Unit>,
  ));
}

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<Unit, $Res> get result {

  return $CommandResultCopyWith<Unit, $Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class NotStartedSettingsField implements SettingsFieldResult {
  const NotStartedSettingsField({required this.index, required this.operationId, required this.error});


@override final  int index;
@override final  OperationId operationId;
 final  StudioFailure error;

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotStartedSettingsFieldCopyWith<NotStartedSettingsField> get copyWith => _$NotStartedSettingsFieldCopyWithImpl<NotStartedSettingsField>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NotStartedSettingsField&&(identical(other.index, index) || other.index == index)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,operationId,error);
}



}

/// @nodoc
abstract mixin class $NotStartedSettingsFieldCopyWith<$Res> implements $SettingsFieldResultCopyWith<$Res> {
  factory $NotStartedSettingsFieldCopyWith(NotStartedSettingsField value, $Res Function(NotStartedSettingsField) _then) = _$NotStartedSettingsFieldCopyWithImpl;
@override @useResult
$Res call({
 int index, OperationId operationId, StudioFailure error
});


@override $OperationIdCopyWith<$Res> get operationId;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$NotStartedSettingsFieldCopyWithImpl<$Res>
    implements $NotStartedSettingsFieldCopyWith<$Res> {
  _$NotStartedSettingsFieldCopyWithImpl(this._self, this._then);

  final NotStartedSettingsField _self;
  final $Res Function(NotStartedSettingsField) _then;

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? operationId = null,Object? error = null,}) {
  return _then(NotStartedSettingsField(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SettingsFieldResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
