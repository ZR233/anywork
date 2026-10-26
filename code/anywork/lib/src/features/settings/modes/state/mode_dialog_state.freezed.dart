// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_dialog_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeDialogDraft {

 int get generation; ModeDialogKind get kind; String get id; String get name; ModeTemplateKind get template; String? get originalStateId; String? get sourceId; String? get targetId; String get guard; ModeDialogValidation? get validation;
/// Create a copy of ModeDialogDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDialogDraftCopyWith<ModeDialogDraft> get copyWith => _$ModeDialogDraftCopyWithImpl<ModeDialogDraft>(this as ModeDialogDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDialogDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDialogDraft&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.template, _this.template) || other.template == _this.template)&&(identical(other.originalStateId, _this.originalStateId) || other.originalStateId == _this.originalStateId)&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.targetId, _this.targetId) || other.targetId == _this.targetId)&&(identical(other.guard, _this.guard) || other.guard == _this.guard)&&(identical(other.validation, _this.validation) || other.validation == _this.validation));
}


@override
int get hashCode {
  final _this = this as ModeDialogDraft;
  return Object.hash(runtimeType,_this.generation,_this.kind,_this.id,_this.name,_this.template,_this.originalStateId,_this.sourceId,_this.targetId,_this.guard,_this.validation);
}



}

/// @nodoc
abstract mixin class $ModeDialogDraftCopyWith<$Res>  {
  factory $ModeDialogDraftCopyWith(ModeDialogDraft value, $Res Function(ModeDialogDraft) _then) = _$ModeDialogDraftCopyWithImpl;
@useResult
$Res call({
 int generation, ModeDialogKind kind, String id, String name, ModeTemplateKind template, String? originalStateId, String? sourceId, String? targetId, String guard, ModeDialogValidation? validation
});




}
/// @nodoc
class _$ModeDialogDraftCopyWithImpl<$Res>
    implements $ModeDialogDraftCopyWith<$Res> {
  _$ModeDialogDraftCopyWithImpl(this._self, this._then);

  final ModeDialogDraft _self;
  final $Res Function(ModeDialogDraft) _then;

/// Create a copy of ModeDialogDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? kind = null,Object? id = null,Object? name = null,Object? template = null,Object? originalStateId = freezed,Object? sourceId = freezed,Object? targetId = freezed,Object? guard = null,Object? validation = freezed,}) {
  return _then(ModeDialogDraft(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModeDialogKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,template: null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as ModeTemplateKind,originalStateId: freezed == originalStateId ? _self.originalStateId : originalStateId // ignore: cast_nullable_to_non_nullable
as String?,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,targetId: freezed == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String?,guard: null == guard ? _self.guard : guard // ignore: cast_nullable_to_non_nullable
as String,validation: freezed == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as ModeDialogValidation?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModeDialogDraft].
extension ModeDialogDraftPatterns on ModeDialogDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDialogDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDialogDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDialogDraft value)  $default,){
final _that = this;
switch (_that) {
case _ModeDialogDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDialogDraft value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDialogDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  ModeDialogKind kind,  String id,  String name,  ModeTemplateKind template,  String? originalStateId,  String? sourceId,  String? targetId,  String guard,  ModeDialogValidation? validation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDialogDraft() when $default != null:
return $default(_that.generation,_that.kind,_that.id,_that.name,_that.template,_that.originalStateId,_that.sourceId,_that.targetId,_that.guard,_that.validation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  ModeDialogKind kind,  String id,  String name,  ModeTemplateKind template,  String? originalStateId,  String? sourceId,  String? targetId,  String guard,  ModeDialogValidation? validation)  $default,) {final _that = this;
switch (_that) {
case _ModeDialogDraft():
return $default(_that.generation,_that.kind,_that.id,_that.name,_that.template,_that.originalStateId,_that.sourceId,_that.targetId,_that.guard,_that.validation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  ModeDialogKind kind,  String id,  String name,  ModeTemplateKind template,  String? originalStateId,  String? sourceId,  String? targetId,  String guard,  ModeDialogValidation? validation)?  $default,) {final _that = this;
switch (_that) {
case _ModeDialogDraft() when $default != null:
return $default(_that.generation,_that.kind,_that.id,_that.name,_that.template,_that.originalStateId,_that.sourceId,_that.targetId,_that.guard,_that.validation);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDialogDraft implements ModeDialogDraft {
  const _ModeDialogDraft({required this.generation, required this.kind, this.id = '', this.name = '', this.template = ModeTemplateKind.minimal, this.originalStateId, this.sourceId, this.targetId, this.guard = '', this.validation});


@override final  int generation;
@override final  ModeDialogKind kind;
@override@JsonKey() final  String id;
@override@JsonKey() final  String name;
@override@JsonKey() final  ModeTemplateKind template;
@override final  String? originalStateId;
@override final  String? sourceId;
@override final  String? targetId;
@override@JsonKey() final  String guard;
@override final  ModeDialogValidation? validation;

/// Create a copy of ModeDialogDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDialogDraftCopyWith<_ModeDialogDraft> get copyWith => __$ModeDialogDraftCopyWithImpl<_ModeDialogDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDialogDraft&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.template, template) || other.template == template)&&(identical(other.originalStateId, originalStateId) || other.originalStateId == originalStateId)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.guard, guard) || other.guard == guard)&&(identical(other.validation, validation) || other.validation == validation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,kind,id,name,template,originalStateId,sourceId,targetId,guard,validation);
}



}

/// @nodoc
abstract mixin class _$ModeDialogDraftCopyWith<$Res> implements $ModeDialogDraftCopyWith<$Res> {
  factory _$ModeDialogDraftCopyWith(_ModeDialogDraft value, $Res Function(_ModeDialogDraft) _then) = __$ModeDialogDraftCopyWithImpl;
@override @useResult
$Res call({
 int generation, ModeDialogKind kind, String id, String name, ModeTemplateKind template, String? originalStateId, String? sourceId, String? targetId, String guard, ModeDialogValidation? validation
});




}
/// @nodoc
class __$ModeDialogDraftCopyWithImpl<$Res>
    implements _$ModeDialogDraftCopyWith<$Res> {
  __$ModeDialogDraftCopyWithImpl(this._self, this._then);

  final _ModeDialogDraft _self;
  final $Res Function(_ModeDialogDraft) _then;

/// Create a copy of ModeDialogDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? kind = null,Object? id = null,Object? name = null,Object? template = null,Object? originalStateId = freezed,Object? sourceId = freezed,Object? targetId = freezed,Object? guard = null,Object? validation = freezed,}) {
  return _then(_ModeDialogDraft(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModeDialogKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,template: null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as ModeTemplateKind,originalStateId: freezed == originalStateId ? _self.originalStateId : originalStateId // ignore: cast_nullable_to_non_nullable
as String?,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,targetId: freezed == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String?,guard: null == guard ? _self.guard : guard // ignore: cast_nullable_to_non_nullable
as String,validation: freezed == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as ModeDialogValidation?,
  ));
}


}

// dart format on
