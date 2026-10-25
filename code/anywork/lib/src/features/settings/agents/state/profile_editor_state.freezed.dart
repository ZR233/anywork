// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProfileRouteSuggestion {

 ProfileEditorKey get editor; int get intent; ProfileRouteSuggestionKind get kind; ModelCatalogReadTarget? get catalog; AccountModelKey? get model; bool get pending; StudioFailure? get error;
/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileRouteSuggestionCopyWith<ProfileRouteSuggestion> get copyWith => _$ProfileRouteSuggestionCopyWithImpl<ProfileRouteSuggestion>(this as ProfileRouteSuggestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileRouteSuggestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileRouteSuggestion&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ProfileRouteSuggestion;
  return Object.hash(runtimeType,_this.editor,_this.intent,_this.kind,_this.catalog,_this.model,_this.pending,_this.error);
}



}

/// @nodoc
abstract mixin class $ProfileRouteSuggestionCopyWith<$Res>  {
  factory $ProfileRouteSuggestionCopyWith(ProfileRouteSuggestion value, $Res Function(ProfileRouteSuggestion) _then) = _$ProfileRouteSuggestionCopyWithImpl;
@useResult
$Res call({
 ProfileEditorKey editor, int intent, ProfileRouteSuggestionKind kind, ModelCatalogReadTarget? catalog, AccountModelKey? model, bool pending, StudioFailure? error
});


$ProfileEditorKeyCopyWith<$Res> get editor;$ModelCatalogReadTargetCopyWith<$Res>? get catalog;$AccountModelKeyCopyWith<$Res>? get model;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ProfileRouteSuggestionCopyWithImpl<$Res>
    implements $ProfileRouteSuggestionCopyWith<$Res> {
  _$ProfileRouteSuggestionCopyWithImpl(this._self, this._then);

  final ProfileRouteSuggestion _self;
  final $Res Function(ProfileRouteSuggestion) _then;

/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editor = null,Object? intent = null,Object? kind = null,Object? catalog = freezed,Object? model = freezed,Object? pending = null,Object? error = freezed,}) {
  return _then(ProfileRouteSuggestion(
editor: null == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ProfileRouteSuggestionKind,catalog: freezed == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey?,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res> get editor {

  return $ProfileEditorKeyCopyWith<$Res>(_self.editor, (value) {
    return _then(_self.copyWith(editor: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res>? get catalog {
    if (_self.catalog == null) {
    return null;
  }

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog!, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res>? get model {
    if (_self.model == null) {
    return null;
  }

  return $AccountModelKeyCopyWith<$Res>(_self.model!, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfileRouteSuggestion].
extension ProfileRouteSuggestionPatterns on ProfileRouteSuggestion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileRouteSuggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileRouteSuggestion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileRouteSuggestion value)  $default,){
final _that = this;
switch (_that) {
case _ProfileRouteSuggestion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileRouteSuggestion value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileRouteSuggestion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProfileEditorKey editor,  int intent,  ProfileRouteSuggestionKind kind,  ModelCatalogReadTarget? catalog,  AccountModelKey? model,  bool pending,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileRouteSuggestion() when $default != null:
return $default(_that.editor,_that.intent,_that.kind,_that.catalog,_that.model,_that.pending,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProfileEditorKey editor,  int intent,  ProfileRouteSuggestionKind kind,  ModelCatalogReadTarget? catalog,  AccountModelKey? model,  bool pending,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _ProfileRouteSuggestion():
return $default(_that.editor,_that.intent,_that.kind,_that.catalog,_that.model,_that.pending,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProfileEditorKey editor,  int intent,  ProfileRouteSuggestionKind kind,  ModelCatalogReadTarget? catalog,  AccountModelKey? model,  bool pending,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _ProfileRouteSuggestion() when $default != null:
return $default(_that.editor,_that.intent,_that.kind,_that.catalog,_that.model,_that.pending,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileRouteSuggestion implements ProfileRouteSuggestion {
  const _ProfileRouteSuggestion({required this.editor, required this.intent, required this.kind, required this.catalog, required this.model, this.pending = false, this.error});


@override final  ProfileEditorKey editor;
@override final  int intent;
@override final  ProfileRouteSuggestionKind kind;
@override final  ModelCatalogReadTarget? catalog;
@override final  AccountModelKey? model;
@override@JsonKey() final  bool pending;
@override final  StudioFailure? error;

/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileRouteSuggestionCopyWith<_ProfileRouteSuggestion> get copyWith => __$ProfileRouteSuggestionCopyWithImpl<_ProfileRouteSuggestion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileRouteSuggestion&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.model, model) || other.model == model)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editor,intent,kind,catalog,model,pending,error);
}



}

/// @nodoc
abstract mixin class _$ProfileRouteSuggestionCopyWith<$Res> implements $ProfileRouteSuggestionCopyWith<$Res> {
  factory _$ProfileRouteSuggestionCopyWith(_ProfileRouteSuggestion value, $Res Function(_ProfileRouteSuggestion) _then) = __$ProfileRouteSuggestionCopyWithImpl;
@override @useResult
$Res call({
 ProfileEditorKey editor, int intent, ProfileRouteSuggestionKind kind, ModelCatalogReadTarget? catalog, AccountModelKey? model, bool pending, StudioFailure? error
});


@override $ProfileEditorKeyCopyWith<$Res> get editor;@override $ModelCatalogReadTargetCopyWith<$Res>? get catalog;@override $AccountModelKeyCopyWith<$Res>? get model;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ProfileRouteSuggestionCopyWithImpl<$Res>
    implements _$ProfileRouteSuggestionCopyWith<$Res> {
  __$ProfileRouteSuggestionCopyWithImpl(this._self, this._then);

  final _ProfileRouteSuggestion _self;
  final $Res Function(_ProfileRouteSuggestion) _then;

/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editor = null,Object? intent = null,Object? kind = null,Object? catalog = freezed,Object? model = freezed,Object? pending = null,Object? error = freezed,}) {
  return _then(_ProfileRouteSuggestion(
editor: null == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ProfileRouteSuggestionKind,catalog: freezed == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey?,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res> get editor {

  return $ProfileEditorKeyCopyWith<$Res>(_self.editor, (value) {
    return _then(_self.copyWith(editor: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res>? get catalog {
    if (_self.catalog == null) {
    return null;
  }

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog!, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res>? get model {
    if (_self.model == null) {
    return null;
  }

  return $AccountModelKeyCopyWith<$Res>(_self.model!, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ProfileRouteSuggestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$ProfileRouteModel {

 AccountModelKey get model; ModelCatalogReadTarget get catalog; ModelDescriptor get descriptor;
/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileRouteModelCopyWith<ProfileRouteModel> get copyWith => _$ProfileRouteModelCopyWithImpl<ProfileRouteModel>(this as ProfileRouteModel, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileRouteModel;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileRouteModel&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.descriptor, _this.descriptor) || other.descriptor == _this.descriptor));
}


@override
int get hashCode {
  final _this = this as ProfileRouteModel;
  return Object.hash(runtimeType,_this.model,_this.catalog,_this.descriptor);
}



}

/// @nodoc
abstract mixin class $ProfileRouteModelCopyWith<$Res>  {
  factory $ProfileRouteModelCopyWith(ProfileRouteModel value, $Res Function(ProfileRouteModel) _then) = _$ProfileRouteModelCopyWithImpl;
@useResult
$Res call({
 AccountModelKey model, ModelCatalogReadTarget catalog, ModelDescriptor descriptor
});


$AccountModelKeyCopyWith<$Res> get model;$ModelCatalogReadTargetCopyWith<$Res> get catalog;$ModelDescriptorCopyWith<$Res> get descriptor;

}
/// @nodoc
class _$ProfileRouteModelCopyWithImpl<$Res>
    implements $ProfileRouteModelCopyWith<$Res> {
  _$ProfileRouteModelCopyWithImpl(this._self, this._then);

  final ProfileRouteModel _self;
  final $Res Function(ProfileRouteModel) _then;

/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = null,Object? catalog = null,Object? descriptor = null,}) {
  return _then(ProfileRouteModel(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,descriptor: null == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptor,
  ));
}
/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<$Res> get descriptor {

  return $ModelDescriptorCopyWith<$Res>(_self.descriptor, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfileRouteModel].
extension ProfileRouteModelPatterns on ProfileRouteModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileRouteModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileRouteModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileRouteModel value)  $default,){
final _that = this;
switch (_that) {
case _ProfileRouteModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileRouteModel value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileRouteModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountModelKey model,  ModelCatalogReadTarget catalog,  ModelDescriptor descriptor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileRouteModel() when $default != null:
return $default(_that.model,_that.catalog,_that.descriptor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountModelKey model,  ModelCatalogReadTarget catalog,  ModelDescriptor descriptor)  $default,) {final _that = this;
switch (_that) {
case _ProfileRouteModel():
return $default(_that.model,_that.catalog,_that.descriptor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountModelKey model,  ModelCatalogReadTarget catalog,  ModelDescriptor descriptor)?  $default,) {final _that = this;
switch (_that) {
case _ProfileRouteModel() when $default != null:
return $default(_that.model,_that.catalog,_that.descriptor);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileRouteModel implements ProfileRouteModel {
  const _ProfileRouteModel({required this.model, required this.catalog, required this.descriptor});


@override final  AccountModelKey model;
@override final  ModelCatalogReadTarget catalog;
@override final  ModelDescriptor descriptor;

/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileRouteModelCopyWith<_ProfileRouteModel> get copyWith => __$ProfileRouteModelCopyWithImpl<_ProfileRouteModel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileRouteModel&&(identical(other.model, model) || other.model == model)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.descriptor, descriptor) || other.descriptor == descriptor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,catalog,descriptor);
}



}

/// @nodoc
abstract mixin class _$ProfileRouteModelCopyWith<$Res> implements $ProfileRouteModelCopyWith<$Res> {
  factory _$ProfileRouteModelCopyWith(_ProfileRouteModel value, $Res Function(_ProfileRouteModel) _then) = __$ProfileRouteModelCopyWithImpl;
@override @useResult
$Res call({
 AccountModelKey model, ModelCatalogReadTarget catalog, ModelDescriptor descriptor
});


@override $AccountModelKeyCopyWith<$Res> get model;@override $ModelCatalogReadTargetCopyWith<$Res> get catalog;@override $ModelDescriptorCopyWith<$Res> get descriptor;

}
/// @nodoc
class __$ProfileRouteModelCopyWithImpl<$Res>
    implements _$ProfileRouteModelCopyWith<$Res> {
  __$ProfileRouteModelCopyWithImpl(this._self, this._then);

  final _ProfileRouteModel _self;
  final $Res Function(_ProfileRouteModel) _then;

/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = null,Object? catalog = null,Object? descriptor = null,}) {
  return _then(_ProfileRouteModel(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,descriptor: null == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptor,
  ));
}

/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ProfileRouteModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<$Res> get descriptor {

  return $ModelDescriptorCopyWith<$Res>(_self.descriptor, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}
}

/// @nodoc
mixin _$ProfileEditorViewState {

 ProfileEditorKey get key; ProfilesState get source; ModelsState get modelSource; ConfigurationState get configurationSource; AgentProfileSnapshot? get canonical; String get profileId; String get displayName; String get description; String get whenToUse; String get instructions; String get accountId; String get modelId; String? get effort; bool get enabled; AgentWorkspaceMode get workspaceMode; List<AccountCatalogEntry> get models; int get revision; bool get dirty; bool get loadingModels; ProfileRouteSuggestion? get routeSuggestion; ProfileRouteModel? get routeModel; StudioFailure? get routeModelError; Map<ProfileField, ProfileValidation> get validation; SettingsAction? get saveAction; StudioFailure? get sourceError;
/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileEditorViewStateCopyWith<ProfileEditorViewState> get copyWith => _$ProfileEditorViewStateCopyWithImpl<ProfileEditorViewState>(this as ProfileEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileEditorViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.configurationSource, _this.configurationSource) || other.configurationSource == _this.configurationSource)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.whenToUse, _this.whenToUse) || other.whenToUse == _this.whenToUse)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&const DeepCollectionEquality().equals(other.models, _this.models)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.loadingModels, _this.loadingModels) || other.loadingModels == _this.loadingModels)&&(identical(other.routeSuggestion, _this.routeSuggestion) || other.routeSuggestion == _this.routeSuggestion)&&(identical(other.routeModel, _this.routeModel) || other.routeModel == _this.routeModel)&&(identical(other.routeModelError, _this.routeModelError) || other.routeModelError == _this.routeModelError)&&const DeepCollectionEquality().equals(other.validation, _this.validation)&&(identical(other.saveAction, _this.saveAction) || other.saveAction == _this.saveAction)&&(identical(other.sourceError, _this.sourceError) || other.sourceError == _this.sourceError));
}


@override
int get hashCode {
  final _this = this as ProfileEditorViewState;
  return Object.hashAll([runtimeType,_this.key,_this.source,_this.modelSource,_this.configurationSource,_this.canonical,_this.profileId,_this.displayName,_this.description,_this.whenToUse,_this.instructions,_this.accountId,_this.modelId,_this.effort,_this.enabled,_this.workspaceMode,const DeepCollectionEquality().hash(_this.models),_this.revision,_this.dirty,_this.loadingModels,_this.routeSuggestion,_this.routeModel,_this.routeModelError,const DeepCollectionEquality().hash(_this.validation),_this.saveAction,_this.sourceError]);
}



}

/// @nodoc
abstract mixin class $ProfileEditorViewStateCopyWith<$Res>  {
  factory $ProfileEditorViewStateCopyWith(ProfileEditorViewState value, $Res Function(ProfileEditorViewState) _then) = _$ProfileEditorViewStateCopyWithImpl;
@useResult
$Res call({
 ProfileEditorKey key, ProfilesState source, ModelsState modelSource, ConfigurationState configurationSource, AgentProfileSnapshot? canonical, String profileId, String displayName, String description, String whenToUse, String instructions, String accountId, String modelId, String? effort, bool enabled, AgentWorkspaceMode workspaceMode, List<AccountCatalogEntry> models, int revision, bool dirty, bool loadingModels, ProfileRouteSuggestion? routeSuggestion, ProfileRouteModel? routeModel, StudioFailure? routeModelError, Map<ProfileField, ProfileValidation> validation, SettingsAction? saveAction, StudioFailure? sourceError
});


$ProfileEditorKeyCopyWith<$Res> get key;$ProfilesStateCopyWith<$Res> get source;$ModelsStateCopyWith<$Res> get modelSource;$ConfigurationStateCopyWith<$Res> get configurationSource;$AgentProfileSnapshotCopyWith<$Res>? get canonical;$ProfileRouteSuggestionCopyWith<$Res>? get routeSuggestion;$ProfileRouteModelCopyWith<$Res>? get routeModel;$StudioFailureCopyWith<$Res>? get routeModelError;$SettingsActionCopyWith<$Res>? get saveAction;$StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class _$ProfileEditorViewStateCopyWithImpl<$Res>
    implements $ProfileEditorViewStateCopyWith<$Res> {
  _$ProfileEditorViewStateCopyWithImpl(this._self, this._then);

  final ProfileEditorViewState _self;
  final $Res Function(ProfileEditorViewState) _then;

/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? source = null,Object? modelSource = null,Object? configurationSource = null,Object? canonical = freezed,Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? instructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? enabled = null,Object? workspaceMode = null,Object? models = null,Object? revision = null,Object? dirty = null,Object? loadingModels = null,Object? routeSuggestion = freezed,Object? routeModel = freezed,Object? routeModelError = freezed,Object? validation = null,Object? saveAction = freezed,Object? sourceError = freezed,}) {
  return _then(ProfileEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ProfilesState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AgentProfileSnapshot?,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<AccountCatalogEntry>,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,loadingModels: null == loadingModels ? _self.loadingModels : loadingModels // ignore: cast_nullable_to_non_nullable
as bool,routeSuggestion: freezed == routeSuggestion ? _self.routeSuggestion : routeSuggestion // ignore: cast_nullable_to_non_nullable
as ProfileRouteSuggestion?,routeModel: freezed == routeModel ? _self.routeModel : routeModel // ignore: cast_nullable_to_non_nullable
as ProfileRouteModel?,routeModelError: freezed == routeModelError ? _self.routeModelError : routeModelError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,validation: null == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as Map<ProfileField, ProfileValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res> get key {

  return $ProfileEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfilesStateCopyWith<$Res> get source {

  return $ProfilesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfileSnapshotCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $AgentProfileSnapshotCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileRouteSuggestionCopyWith<$Res>? get routeSuggestion {
    if (_self.routeSuggestion == null) {
    return null;
  }

  return $ProfileRouteSuggestionCopyWith<$Res>(_self.routeSuggestion!, (value) {
    return _then(_self.copyWith(routeSuggestion: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileRouteModelCopyWith<$Res>? get routeModel {
    if (_self.routeModel == null) {
    return null;
  }

  return $ProfileRouteModelCopyWith<$Res>(_self.routeModel!, (value) {
    return _then(_self.copyWith(routeModel: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get routeModelError {
    if (_self.routeModelError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.routeModelError!, (value) {
    return _then(_self.copyWith(routeModelError: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get sourceError {
    if (_self.sourceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.sourceError!, (value) {
    return _then(_self.copyWith(sourceError: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfileEditorViewState].
extension ProfileEditorViewStatePatterns on ProfileEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _ProfileEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProfileEditorKey key,  ProfilesState source,  ModelsState modelSource,  ConfigurationState configurationSource,  AgentProfileSnapshot? canonical,  String profileId,  String displayName,  String description,  String whenToUse,  String instructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode,  List<AccountCatalogEntry> models,  int revision,  bool dirty,  bool loadingModels,  ProfileRouteSuggestion? routeSuggestion,  ProfileRouteModel? routeModel,  StudioFailure? routeModelError,  Map<ProfileField, ProfileValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileEditorViewState() when $default != null:
return $default(_that.key,_that.source,_that.modelSource,_that.configurationSource,_that.canonical,_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.instructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode,_that.models,_that.revision,_that.dirty,_that.loadingModels,_that.routeSuggestion,_that.routeModel,_that.routeModelError,_that.validation,_that.saveAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProfileEditorKey key,  ProfilesState source,  ModelsState modelSource,  ConfigurationState configurationSource,  AgentProfileSnapshot? canonical,  String profileId,  String displayName,  String description,  String whenToUse,  String instructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode,  List<AccountCatalogEntry> models,  int revision,  bool dirty,  bool loadingModels,  ProfileRouteSuggestion? routeSuggestion,  ProfileRouteModel? routeModel,  StudioFailure? routeModelError,  Map<ProfileField, ProfileValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)  $default,) {final _that = this;
switch (_that) {
case _ProfileEditorViewState():
return $default(_that.key,_that.source,_that.modelSource,_that.configurationSource,_that.canonical,_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.instructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode,_that.models,_that.revision,_that.dirty,_that.loadingModels,_that.routeSuggestion,_that.routeModel,_that.routeModelError,_that.validation,_that.saveAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProfileEditorKey key,  ProfilesState source,  ModelsState modelSource,  ConfigurationState configurationSource,  AgentProfileSnapshot? canonical,  String profileId,  String displayName,  String description,  String whenToUse,  String instructions,  String accountId,  String modelId,  String? effort,  bool enabled,  AgentWorkspaceMode workspaceMode,  List<AccountCatalogEntry> models,  int revision,  bool dirty,  bool loadingModels,  ProfileRouteSuggestion? routeSuggestion,  ProfileRouteModel? routeModel,  StudioFailure? routeModelError,  Map<ProfileField, ProfileValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)?  $default,) {final _that = this;
switch (_that) {
case _ProfileEditorViewState() when $default != null:
return $default(_that.key,_that.source,_that.modelSource,_that.configurationSource,_that.canonical,_that.profileId,_that.displayName,_that.description,_that.whenToUse,_that.instructions,_that.accountId,_that.modelId,_that.effort,_that.enabled,_that.workspaceMode,_that.models,_that.revision,_that.dirty,_that.loadingModels,_that.routeSuggestion,_that.routeModel,_that.routeModelError,_that.validation,_that.saveAction,_that.sourceError);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileEditorViewState implements ProfileEditorViewState {
  const _ProfileEditorViewState({required this.key, required this.source, required this.modelSource, required this.configurationSource, this.canonical, required this.profileId, required this.displayName, required this.description, required this.whenToUse, required this.instructions, required this.accountId, required this.modelId, this.effort, required this.enabled, required this.workspaceMode,  List<AccountCatalogEntry> models = const [], this.revision = 0, this.dirty = false, this.loadingModels = false, this.routeSuggestion, this.routeModel, this.routeModelError,  Map<ProfileField, ProfileValidation> validation = const {}, this.saveAction, this.sourceError}): _models = models,_validation = validation;


@override final  ProfileEditorKey key;
@override final  ProfilesState source;
@override final  ModelsState modelSource;
@override final  ConfigurationState configurationSource;
@override final  AgentProfileSnapshot? canonical;
@override final  String profileId;
@override final  String displayName;
@override final  String description;
@override final  String whenToUse;
@override final  String instructions;
@override final  String accountId;
@override final  String modelId;
@override final  String? effort;
@override final  bool enabled;
@override final  AgentWorkspaceMode workspaceMode;
 final  List<AccountCatalogEntry> _models;
@override@JsonKey() List<AccountCatalogEntry> get models {
  if (_models is EqualUnmodifiableListView) return _models;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_models);
}

@override@JsonKey() final  int revision;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool loadingModels;
@override final  ProfileRouteSuggestion? routeSuggestion;
@override final  ProfileRouteModel? routeModel;
@override final  StudioFailure? routeModelError;
 final  Map<ProfileField, ProfileValidation> _validation;
@override@JsonKey() Map<ProfileField, ProfileValidation> get validation {
  if (_validation is EqualUnmodifiableMapView) return _validation;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_validation);
}

@override final  SettingsAction? saveAction;
@override final  StudioFailure? sourceError;

/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileEditorViewStateCopyWith<_ProfileEditorViewState> get copyWith => __$ProfileEditorViewStateCopyWithImpl<_ProfileEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileEditorViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.source, source) || other.source == source)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.configurationSource, configurationSource) || other.configurationSource == configurationSource)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.whenToUse, whenToUse) || other.whenToUse == whenToUse)&&(identical(other.instructions, instructions) || other.instructions == instructions)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&const DeepCollectionEquality().equals(other.models, _models)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.loadingModels, loadingModels) || other.loadingModels == loadingModels)&&(identical(other.routeSuggestion, routeSuggestion) || other.routeSuggestion == routeSuggestion)&&(identical(other.routeModel, routeModel) || other.routeModel == routeModel)&&(identical(other.routeModelError, routeModelError) || other.routeModelError == routeModelError)&&const DeepCollectionEquality().equals(other.validation, _validation)&&(identical(other.saveAction, saveAction) || other.saveAction == saveAction)&&(identical(other.sourceError, sourceError) || other.sourceError == sourceError));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,key,source,modelSource,configurationSource,canonical,profileId,displayName,description,whenToUse,instructions,accountId,modelId,effort,enabled,workspaceMode,const DeepCollectionEquality().hash(_models),revision,dirty,loadingModels,routeSuggestion,routeModel,routeModelError,const DeepCollectionEquality().hash(_validation),saveAction,sourceError]);
}



}

/// @nodoc
abstract mixin class _$ProfileEditorViewStateCopyWith<$Res> implements $ProfileEditorViewStateCopyWith<$Res> {
  factory _$ProfileEditorViewStateCopyWith(_ProfileEditorViewState value, $Res Function(_ProfileEditorViewState) _then) = __$ProfileEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 ProfileEditorKey key, ProfilesState source, ModelsState modelSource, ConfigurationState configurationSource, AgentProfileSnapshot? canonical, String profileId, String displayName, String description, String whenToUse, String instructions, String accountId, String modelId, String? effort, bool enabled, AgentWorkspaceMode workspaceMode, List<AccountCatalogEntry> models, int revision, bool dirty, bool loadingModels, ProfileRouteSuggestion? routeSuggestion, ProfileRouteModel? routeModel, StudioFailure? routeModelError, Map<ProfileField, ProfileValidation> validation, SettingsAction? saveAction, StudioFailure? sourceError
});


@override $ProfileEditorKeyCopyWith<$Res> get key;@override $ProfilesStateCopyWith<$Res> get source;@override $ModelsStateCopyWith<$Res> get modelSource;@override $ConfigurationStateCopyWith<$Res> get configurationSource;@override $AgentProfileSnapshotCopyWith<$Res>? get canonical;@override $ProfileRouteSuggestionCopyWith<$Res>? get routeSuggestion;@override $ProfileRouteModelCopyWith<$Res>? get routeModel;@override $StudioFailureCopyWith<$Res>? get routeModelError;@override $SettingsActionCopyWith<$Res>? get saveAction;@override $StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class __$ProfileEditorViewStateCopyWithImpl<$Res>
    implements _$ProfileEditorViewStateCopyWith<$Res> {
  __$ProfileEditorViewStateCopyWithImpl(this._self, this._then);

  final _ProfileEditorViewState _self;
  final $Res Function(_ProfileEditorViewState) _then;

/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? source = null,Object? modelSource = null,Object? configurationSource = null,Object? canonical = freezed,Object? profileId = null,Object? displayName = null,Object? description = null,Object? whenToUse = null,Object? instructions = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? enabled = null,Object? workspaceMode = null,Object? models = null,Object? revision = null,Object? dirty = null,Object? loadingModels = null,Object? routeSuggestion = freezed,Object? routeModel = freezed,Object? routeModelError = freezed,Object? validation = null,Object? saveAction = freezed,Object? sourceError = freezed,}) {
  return _then(_ProfileEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ProfileEditorKey,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ProfilesState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AgentProfileSnapshot?,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,whenToUse: null == whenToUse ? _self.whenToUse : whenToUse // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceMode,models: null == models ? _self._models : models // ignore: cast_nullable_to_non_nullable
as List<AccountCatalogEntry>,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,loadingModels: null == loadingModels ? _self.loadingModels : loadingModels // ignore: cast_nullable_to_non_nullable
as bool,routeSuggestion: freezed == routeSuggestion ? _self.routeSuggestion : routeSuggestion // ignore: cast_nullable_to_non_nullable
as ProfileRouteSuggestion?,routeModel: freezed == routeModel ? _self.routeModel : routeModel // ignore: cast_nullable_to_non_nullable
as ProfileRouteModel?,routeModelError: freezed == routeModelError ? _self.routeModelError : routeModelError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,validation: null == validation ? _self._validation : validation // ignore: cast_nullable_to_non_nullable
as Map<ProfileField, ProfileValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<$Res> get key {

  return $ProfileEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfilesStateCopyWith<$Res> get source {

  return $ProfilesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfileSnapshotCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $AgentProfileSnapshotCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileRouteSuggestionCopyWith<$Res>? get routeSuggestion {
    if (_self.routeSuggestion == null) {
    return null;
  }

  return $ProfileRouteSuggestionCopyWith<$Res>(_self.routeSuggestion!, (value) {
    return _then(_self.copyWith(routeSuggestion: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileRouteModelCopyWith<$Res>? get routeModel {
    if (_self.routeModel == null) {
    return null;
  }

  return $ProfileRouteModelCopyWith<$Res>(_self.routeModel!, (value) {
    return _then(_self.copyWith(routeModel: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get routeModelError {
    if (_self.routeModelError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.routeModelError!, (value) {
    return _then(_self.copyWith(routeModelError: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of ProfileEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get sourceError {
    if (_self.sourceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.sourceError!, (value) {
    return _then(_self.copyWith(sourceError: value));
  });
}
}

// dart format on
