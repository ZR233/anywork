// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CustomModelDraft {

 int get rowId; String? get originalModelId; String get modelId; String get displayName; String get wireApi; String get contextWindowRaw; String get maxOutputTokensRaw; bool get dirty; Set<CustomModelField> get dirtyFields; Map<CustomModelField, AccountValidation> get validation;
/// Create a copy of CustomModelDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomModelDraftCopyWith<CustomModelDraft> get copyWith => _$CustomModelDraftCopyWithImpl<CustomModelDraft>(this as CustomModelDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CustomModelDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomModelDraft&&(identical(other.rowId, _this.rowId) || other.rowId == _this.rowId)&&(identical(other.originalModelId, _this.originalModelId) || other.originalModelId == _this.originalModelId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.wireApi, _this.wireApi) || other.wireApi == _this.wireApi)&&(identical(other.contextWindowRaw, _this.contextWindowRaw) || other.contextWindowRaw == _this.contextWindowRaw)&&(identical(other.maxOutputTokensRaw, _this.maxOutputTokensRaw) || other.maxOutputTokensRaw == _this.maxOutputTokensRaw)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&const DeepCollectionEquality().equals(other.dirtyFields, _this.dirtyFields)&&const DeepCollectionEquality().equals(other.validation, _this.validation));
}


@override
int get hashCode {
  final _this = this as CustomModelDraft;
  return Object.hash(runtimeType,_this.rowId,_this.originalModelId,_this.modelId,_this.displayName,_this.wireApi,_this.contextWindowRaw,_this.maxOutputTokensRaw,_this.dirty,const DeepCollectionEquality().hash(_this.dirtyFields),const DeepCollectionEquality().hash(_this.validation));
}



}

/// @nodoc
abstract mixin class $CustomModelDraftCopyWith<$Res>  {
  factory $CustomModelDraftCopyWith(CustomModelDraft value, $Res Function(CustomModelDraft) _then) = _$CustomModelDraftCopyWithImpl;
@useResult
$Res call({
 int rowId, String? originalModelId, String modelId, String displayName, String wireApi, String contextWindowRaw, String maxOutputTokensRaw, bool dirty, Set<CustomModelField> dirtyFields, Map<CustomModelField, AccountValidation> validation
});




}
/// @nodoc
class _$CustomModelDraftCopyWithImpl<$Res>
    implements $CustomModelDraftCopyWith<$Res> {
  _$CustomModelDraftCopyWithImpl(this._self, this._then);

  final CustomModelDraft _self;
  final $Res Function(CustomModelDraft) _then;

/// Create a copy of CustomModelDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rowId = null,Object? originalModelId = freezed,Object? modelId = null,Object? displayName = null,Object? wireApi = null,Object? contextWindowRaw = null,Object? maxOutputTokensRaw = null,Object? dirty = null,Object? dirtyFields = null,Object? validation = null,}) {
  return _then(CustomModelDraft(
rowId: null == rowId ? _self.rowId : rowId // ignore: cast_nullable_to_non_nullable
as int,originalModelId: freezed == originalModelId ? _self.originalModelId : originalModelId // ignore: cast_nullable_to_non_nullable
as String?,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as String,contextWindowRaw: null == contextWindowRaw ? _self.contextWindowRaw : contextWindowRaw // ignore: cast_nullable_to_non_nullable
as String,maxOutputTokensRaw: null == maxOutputTokensRaw ? _self.maxOutputTokensRaw : maxOutputTokensRaw // ignore: cast_nullable_to_non_nullable
as String,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,dirtyFields: null == dirtyFields ? _self.dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<CustomModelField>,validation: null == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as Map<CustomModelField, AccountValidation>,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomModelDraft].
extension CustomModelDraftPatterns on CustomModelDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomModelDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomModelDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomModelDraft value)  $default,){
final _that = this;
switch (_that) {
case _CustomModelDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomModelDraft value)?  $default,){
final _that = this;
switch (_that) {
case _CustomModelDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int rowId,  String? originalModelId,  String modelId,  String displayName,  String wireApi,  String contextWindowRaw,  String maxOutputTokensRaw,  bool dirty,  Set<CustomModelField> dirtyFields,  Map<CustomModelField, AccountValidation> validation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomModelDraft() when $default != null:
return $default(_that.rowId,_that.originalModelId,_that.modelId,_that.displayName,_that.wireApi,_that.contextWindowRaw,_that.maxOutputTokensRaw,_that.dirty,_that.dirtyFields,_that.validation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int rowId,  String? originalModelId,  String modelId,  String displayName,  String wireApi,  String contextWindowRaw,  String maxOutputTokensRaw,  bool dirty,  Set<CustomModelField> dirtyFields,  Map<CustomModelField, AccountValidation> validation)  $default,) {final _that = this;
switch (_that) {
case _CustomModelDraft():
return $default(_that.rowId,_that.originalModelId,_that.modelId,_that.displayName,_that.wireApi,_that.contextWindowRaw,_that.maxOutputTokensRaw,_that.dirty,_that.dirtyFields,_that.validation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int rowId,  String? originalModelId,  String modelId,  String displayName,  String wireApi,  String contextWindowRaw,  String maxOutputTokensRaw,  bool dirty,  Set<CustomModelField> dirtyFields,  Map<CustomModelField, AccountValidation> validation)?  $default,) {final _that = this;
switch (_that) {
case _CustomModelDraft() when $default != null:
return $default(_that.rowId,_that.originalModelId,_that.modelId,_that.displayName,_that.wireApi,_that.contextWindowRaw,_that.maxOutputTokensRaw,_that.dirty,_that.dirtyFields,_that.validation);case _:
  return null;

}
}

}

/// @nodoc


class _CustomModelDraft implements CustomModelDraft {
  const _CustomModelDraft({required this.rowId, required this.originalModelId, required this.modelId, required this.displayName, required this.wireApi, required this.contextWindowRaw, required this.maxOutputTokensRaw, this.dirty = false,  Set<CustomModelField> dirtyFields = const {},  Map<CustomModelField, AccountValidation> validation = const {}}): _dirtyFields = dirtyFields,_validation = validation;


@override final  int rowId;
@override final  String? originalModelId;
@override final  String modelId;
@override final  String displayName;
@override final  String wireApi;
@override final  String contextWindowRaw;
@override final  String maxOutputTokensRaw;
@override@JsonKey() final  bool dirty;
 final  Set<CustomModelField> _dirtyFields;
@override@JsonKey() Set<CustomModelField> get dirtyFields {
  if (_dirtyFields is EqualUnmodifiableSetView) return _dirtyFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dirtyFields);
}

 final  Map<CustomModelField, AccountValidation> _validation;
@override@JsonKey() Map<CustomModelField, AccountValidation> get validation {
  if (_validation is EqualUnmodifiableMapView) return _validation;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_validation);
}


/// Create a copy of CustomModelDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomModelDraftCopyWith<_CustomModelDraft> get copyWith => __$CustomModelDraftCopyWithImpl<_CustomModelDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomModelDraft&&(identical(other.rowId, rowId) || other.rowId == rowId)&&(identical(other.originalModelId, originalModelId) || other.originalModelId == originalModelId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.wireApi, wireApi) || other.wireApi == wireApi)&&(identical(other.contextWindowRaw, contextWindowRaw) || other.contextWindowRaw == contextWindowRaw)&&(identical(other.maxOutputTokensRaw, maxOutputTokensRaw) || other.maxOutputTokensRaw == maxOutputTokensRaw)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.dirtyFields, _dirtyFields)&&const DeepCollectionEquality().equals(other.validation, _validation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,rowId,originalModelId,modelId,displayName,wireApi,contextWindowRaw,maxOutputTokensRaw,dirty,const DeepCollectionEquality().hash(_dirtyFields),const DeepCollectionEquality().hash(_validation));
}



}

/// @nodoc
abstract mixin class _$CustomModelDraftCopyWith<$Res> implements $CustomModelDraftCopyWith<$Res> {
  factory _$CustomModelDraftCopyWith(_CustomModelDraft value, $Res Function(_CustomModelDraft) _then) = __$CustomModelDraftCopyWithImpl;
@override @useResult
$Res call({
 int rowId, String? originalModelId, String modelId, String displayName, String wireApi, String contextWindowRaw, String maxOutputTokensRaw, bool dirty, Set<CustomModelField> dirtyFields, Map<CustomModelField, AccountValidation> validation
});




}
/// @nodoc
class __$CustomModelDraftCopyWithImpl<$Res>
    implements _$CustomModelDraftCopyWith<$Res> {
  __$CustomModelDraftCopyWithImpl(this._self, this._then);

  final _CustomModelDraft _self;
  final $Res Function(_CustomModelDraft) _then;

/// Create a copy of CustomModelDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rowId = null,Object? originalModelId = freezed,Object? modelId = null,Object? displayName = null,Object? wireApi = null,Object? contextWindowRaw = null,Object? maxOutputTokensRaw = null,Object? dirty = null,Object? dirtyFields = null,Object? validation = null,}) {
  return _then(_CustomModelDraft(
rowId: null == rowId ? _self.rowId : rowId // ignore: cast_nullable_to_non_nullable
as int,originalModelId: freezed == originalModelId ? _self.originalModelId : originalModelId // ignore: cast_nullable_to_non_nullable
as String?,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as String,contextWindowRaw: null == contextWindowRaw ? _self.contextWindowRaw : contextWindowRaw // ignore: cast_nullable_to_non_nullable
as String,maxOutputTokensRaw: null == maxOutputTokensRaw ? _self.maxOutputTokensRaw : maxOutputTokensRaw // ignore: cast_nullable_to_non_nullable
as String,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,dirtyFields: null == dirtyFields ? _self._dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<CustomModelField>,validation: null == validation ? _self._validation : validation // ignore: cast_nullable_to_non_nullable
as Map<CustomModelField, AccountValidation>,
  ));
}


}

/// @nodoc
mixin _$AccountEditorViewState {

 AccountEditorKey get key; String get accountId; ConfigurationState get source; ModelsState get modelSource; TemplatesState get templateSource; AccountTemplatesValue get templates; AccountConfiguration? get canonical; AccountCatalogEntry? get catalog; bool get templatePreview; bool get rebuildModelConfiguration; String? get templateId; String get protocol; String get name; String get baseUrl;/// 新建账号的初始计费类别草稿；`BillingKind.unknown` 表示“未指定”，提交为 null。
///
/// 只在 [create] 为 true 时使用：编辑已有账号的计费改写必须走
/// `setAccountBillingKind` 窄命令，不得借保存覆盖类别。
 BillingKind get initialBillingKind; AccountSecretIntent get secretIntent; String get secretRaw; List<CustomModelDraft> get customModels; List<String> get removedCustomModelIds; Map<String, String> get connectionEdits; Set<AccountEditorField> get dirtyFields; Map<AccountEditorField, AccountValidation> get validation; int get draftRevision; int get formGeneration; bool get saved; bool get verifying; SettingsAction? get saveAction; SettingsAction? get defaultAction;/// 编辑已有账号时 `setAccountBillingKind` 的受理与结果（noCharge 开关）。
 SettingsAction? get billingAction; StudioFailure? get sourceError;
/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEditorViewStateCopyWith<AccountEditorViewState> get copyWith => _$AccountEditorViewStateCopyWithImpl<AccountEditorViewState>(this as AccountEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEditorViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.templateSource, _this.templateSource) || other.templateSource == _this.templateSource)&&(identical(other.templates, _this.templates) || other.templates == _this.templates)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.templatePreview, _this.templatePreview) || other.templatePreview == _this.templatePreview)&&(identical(other.rebuildModelConfiguration, _this.rebuildModelConfiguration) || other.rebuildModelConfiguration == _this.rebuildModelConfiguration)&&(identical(other.templateId, _this.templateId) || other.templateId == _this.templateId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.initialBillingKind, _this.initialBillingKind) || other.initialBillingKind == _this.initialBillingKind)&&(identical(other.secretIntent, _this.secretIntent) || other.secretIntent == _this.secretIntent)&&(identical(other.secretRaw, _this.secretRaw) || other.secretRaw == _this.secretRaw)&&const DeepCollectionEquality().equals(other.customModels, _this.customModels)&&const DeepCollectionEquality().equals(other.removedCustomModelIds, _this.removedCustomModelIds)&&const DeepCollectionEquality().equals(other.connectionEdits, _this.connectionEdits)&&const DeepCollectionEquality().equals(other.dirtyFields, _this.dirtyFields)&&const DeepCollectionEquality().equals(other.validation, _this.validation)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&(identical(other.formGeneration, _this.formGeneration) || other.formGeneration == _this.formGeneration)&&(identical(other.saved, _this.saved) || other.saved == _this.saved)&&(identical(other.verifying, _this.verifying) || other.verifying == _this.verifying)&&(identical(other.saveAction, _this.saveAction) || other.saveAction == _this.saveAction)&&(identical(other.defaultAction, _this.defaultAction) || other.defaultAction == _this.defaultAction)&&(identical(other.billingAction, _this.billingAction) || other.billingAction == _this.billingAction)&&(identical(other.sourceError, _this.sourceError) || other.sourceError == _this.sourceError));
}


@override
int get hashCode {
  final _this = this as AccountEditorViewState;
  return Object.hashAll([runtimeType,_this.key,_this.accountId,_this.source,_this.modelSource,_this.templateSource,_this.templates,_this.canonical,_this.catalog,_this.templatePreview,_this.rebuildModelConfiguration,_this.templateId,_this.protocol,_this.name,_this.baseUrl,_this.initialBillingKind,_this.secretIntent,_this.secretRaw,const DeepCollectionEquality().hash(_this.customModels),const DeepCollectionEquality().hash(_this.removedCustomModelIds),const DeepCollectionEquality().hash(_this.connectionEdits),const DeepCollectionEquality().hash(_this.dirtyFields),const DeepCollectionEquality().hash(_this.validation),_this.draftRevision,_this.formGeneration,_this.saved,_this.verifying,_this.saveAction,_this.defaultAction,_this.billingAction,_this.sourceError]);
}



}

/// @nodoc
abstract mixin class $AccountEditorViewStateCopyWith<$Res>  {
  factory $AccountEditorViewStateCopyWith(AccountEditorViewState value, $Res Function(AccountEditorViewState) _then) = _$AccountEditorViewStateCopyWithImpl;
@useResult
$Res call({
 AccountEditorKey key, String accountId, ConfigurationState source, ModelsState modelSource, TemplatesState templateSource, AccountTemplatesValue templates, AccountConfiguration? canonical, AccountCatalogEntry? catalog, bool templatePreview, bool rebuildModelConfiguration, String? templateId, String protocol, String name, String baseUrl, BillingKind initialBillingKind, AccountSecretIntent secretIntent, String secretRaw, List<CustomModelDraft> customModels, List<String> removedCustomModelIds, Map<String, String> connectionEdits, Set<AccountEditorField> dirtyFields, Map<AccountEditorField, AccountValidation> validation, int draftRevision, int formGeneration, bool saved, bool verifying, SettingsAction? saveAction, SettingsAction? defaultAction, SettingsAction? billingAction, StudioFailure? sourceError
});


$AccountEditorKeyCopyWith<$Res> get key;$ConfigurationStateCopyWith<$Res> get source;$ModelsStateCopyWith<$Res> get modelSource;$TemplatesStateCopyWith<$Res> get templateSource;$AccountTemplatesValueCopyWith<$Res> get templates;$AccountConfigurationCopyWith<$Res>? get canonical;$AccountCatalogEntryCopyWith<$Res>? get catalog;$SettingsActionCopyWith<$Res>? get saveAction;$SettingsActionCopyWith<$Res>? get defaultAction;$SettingsActionCopyWith<$Res>? get billingAction;$StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class _$AccountEditorViewStateCopyWithImpl<$Res>
    implements $AccountEditorViewStateCopyWith<$Res> {
  _$AccountEditorViewStateCopyWithImpl(this._self, this._then);

  final AccountEditorViewState _self;
  final $Res Function(AccountEditorViewState) _then;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? accountId = null,Object? source = null,Object? modelSource = null,Object? templateSource = null,Object? templates = null,Object? canonical = freezed,Object? catalog = freezed,Object? templatePreview = null,Object? rebuildModelConfiguration = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? initialBillingKind = null,Object? secretIntent = null,Object? secretRaw = null,Object? customModels = null,Object? removedCustomModelIds = null,Object? connectionEdits = null,Object? dirtyFields = null,Object? validation = null,Object? draftRevision = null,Object? formGeneration = null,Object? saved = null,Object? verifying = null,Object? saveAction = freezed,Object? defaultAction = freezed,Object? billingAction = freezed,Object? sourceError = freezed,}) {
  return _then(AccountEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountEditorKey,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,templateSource: null == templateSource ? _self.templateSource : templateSource // ignore: cast_nullable_to_non_nullable
as TemplatesState,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as AccountTemplatesValue,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AccountConfiguration?,catalog: freezed == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogEntry?,templatePreview: null == templatePreview ? _self.templatePreview : templatePreview // ignore: cast_nullable_to_non_nullable
as bool,rebuildModelConfiguration: null == rebuildModelConfiguration ? _self.rebuildModelConfiguration : rebuildModelConfiguration // ignore: cast_nullable_to_non_nullable
as bool,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as String?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,initialBillingKind: null == initialBillingKind ? _self.initialBillingKind : initialBillingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,secretIntent: null == secretIntent ? _self.secretIntent : secretIntent // ignore: cast_nullable_to_non_nullable
as AccountSecretIntent,secretRaw: null == secretRaw ? _self.secretRaw : secretRaw // ignore: cast_nullable_to_non_nullable
as String,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as List<CustomModelDraft>,removedCustomModelIds: null == removedCustomModelIds ? _self.removedCustomModelIds : removedCustomModelIds // ignore: cast_nullable_to_non_nullable
as List<String>,connectionEdits: null == connectionEdits ? _self.connectionEdits : connectionEdits // ignore: cast_nullable_to_non_nullable
as Map<String, String>,dirtyFields: null == dirtyFields ? _self.dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<AccountEditorField>,validation: null == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as Map<AccountEditorField, AccountValidation>,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,formGeneration: null == formGeneration ? _self.formGeneration : formGeneration // ignore: cast_nullable_to_non_nullable
as int,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,verifying: null == verifying ? _self.verifying : verifying // ignore: cast_nullable_to_non_nullable
as bool,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,defaultAction: freezed == defaultAction ? _self.defaultAction : defaultAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,billingAction: freezed == billingAction ? _self.billingAction : billingAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res> get key {

  return $AccountEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TemplatesStateCopyWith<$Res> get templateSource {

  return $TemplatesStateCopyWith<$Res>(_self.templateSource, (value) {
    return _then(_self.copyWith(templateSource: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesValueCopyWith<$Res> get templates {

  return $AccountTemplatesValueCopyWith<$Res>(_self.templates, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $AccountConfigurationCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogEntryCopyWith<$Res>? get catalog {
    if (_self.catalog == null) {
    return null;
  }

  return $AccountCatalogEntryCopyWith<$Res>(_self.catalog!, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of AccountEditorViewState
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
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get defaultAction {
    if (_self.defaultAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.defaultAction!, (value) {
    return _then(_self.copyWith(defaultAction: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get billingAction {
    if (_self.billingAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.billingAction!, (value) {
    return _then(_self.copyWith(billingAction: value));
  });
}/// Create a copy of AccountEditorViewState
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


/// Adds pattern-matching-related methods to [AccountEditorViewState].
extension AccountEditorViewStatePatterns on AccountEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountEditorKey key,  String accountId,  ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountTemplatesValue templates,  AccountConfiguration? canonical,  AccountCatalogEntry? catalog,  bool templatePreview,  bool rebuildModelConfiguration,  String? templateId,  String protocol,  String name,  String baseUrl,  BillingKind initialBillingKind,  AccountSecretIntent secretIntent,  String secretRaw,  List<CustomModelDraft> customModels,  List<String> removedCustomModelIds,  Map<String, String> connectionEdits,  Set<AccountEditorField> dirtyFields,  Map<AccountEditorField, AccountValidation> validation,  int draftRevision,  int formGeneration,  bool saved,  bool verifying,  SettingsAction? saveAction,  SettingsAction? defaultAction,  SettingsAction? billingAction,  StudioFailure? sourceError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
return $default(_that.key,_that.accountId,_that.source,_that.modelSource,_that.templateSource,_that.templates,_that.canonical,_that.catalog,_that.templatePreview,_that.rebuildModelConfiguration,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.initialBillingKind,_that.secretIntent,_that.secretRaw,_that.customModels,_that.removedCustomModelIds,_that.connectionEdits,_that.dirtyFields,_that.validation,_that.draftRevision,_that.formGeneration,_that.saved,_that.verifying,_that.saveAction,_that.defaultAction,_that.billingAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountEditorKey key,  String accountId,  ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountTemplatesValue templates,  AccountConfiguration? canonical,  AccountCatalogEntry? catalog,  bool templatePreview,  bool rebuildModelConfiguration,  String? templateId,  String protocol,  String name,  String baseUrl,  BillingKind initialBillingKind,  AccountSecretIntent secretIntent,  String secretRaw,  List<CustomModelDraft> customModels,  List<String> removedCustomModelIds,  Map<String, String> connectionEdits,  Set<AccountEditorField> dirtyFields,  Map<AccountEditorField, AccountValidation> validation,  int draftRevision,  int formGeneration,  bool saved,  bool verifying,  SettingsAction? saveAction,  SettingsAction? defaultAction,  SettingsAction? billingAction,  StudioFailure? sourceError)  $default,) {final _that = this;
switch (_that) {
case _AccountEditorViewState():
return $default(_that.key,_that.accountId,_that.source,_that.modelSource,_that.templateSource,_that.templates,_that.canonical,_that.catalog,_that.templatePreview,_that.rebuildModelConfiguration,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.initialBillingKind,_that.secretIntent,_that.secretRaw,_that.customModels,_that.removedCustomModelIds,_that.connectionEdits,_that.dirtyFields,_that.validation,_that.draftRevision,_that.formGeneration,_that.saved,_that.verifying,_that.saveAction,_that.defaultAction,_that.billingAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountEditorKey key,  String accountId,  ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountTemplatesValue templates,  AccountConfiguration? canonical,  AccountCatalogEntry? catalog,  bool templatePreview,  bool rebuildModelConfiguration,  String? templateId,  String protocol,  String name,  String baseUrl,  BillingKind initialBillingKind,  AccountSecretIntent secretIntent,  String secretRaw,  List<CustomModelDraft> customModels,  List<String> removedCustomModelIds,  Map<String, String> connectionEdits,  Set<AccountEditorField> dirtyFields,  Map<AccountEditorField, AccountValidation> validation,  int draftRevision,  int formGeneration,  bool saved,  bool verifying,  SettingsAction? saveAction,  SettingsAction? defaultAction,  SettingsAction? billingAction,  StudioFailure? sourceError)?  $default,) {final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
return $default(_that.key,_that.accountId,_that.source,_that.modelSource,_that.templateSource,_that.templates,_that.canonical,_that.catalog,_that.templatePreview,_that.rebuildModelConfiguration,_that.templateId,_that.protocol,_that.name,_that.baseUrl,_that.initialBillingKind,_that.secretIntent,_that.secretRaw,_that.customModels,_that.removedCustomModelIds,_that.connectionEdits,_that.dirtyFields,_that.validation,_that.draftRevision,_that.formGeneration,_that.saved,_that.verifying,_that.saveAction,_that.defaultAction,_that.billingAction,_that.sourceError);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEditorViewState extends AccountEditorViewState {
  const _AccountEditorViewState({required this.key, required this.accountId, required this.source, required this.modelSource, required this.templateSource, required this.templates, this.canonical, this.catalog, this.templatePreview = false, this.rebuildModelConfiguration = false, this.templateId, required this.protocol, required this.name, required this.baseUrl, this.initialBillingKind = BillingKind.unknown, this.secretIntent = AccountSecretIntent.preserve, this.secretRaw = '',  List<CustomModelDraft> customModels = const [],  List<String> removedCustomModelIds = const [],  Map<String, String> connectionEdits = const {},  Set<AccountEditorField> dirtyFields = const {},  Map<AccountEditorField, AccountValidation> validation = const {}, this.draftRevision = 0, this.formGeneration = 0, this.saved = false, this.verifying = false, this.saveAction, this.defaultAction, this.billingAction, this.sourceError}): _customModels = customModels,_removedCustomModelIds = removedCustomModelIds,_connectionEdits = connectionEdits,_dirtyFields = dirtyFields,_validation = validation,super._();


@override final  AccountEditorKey key;
@override final  String accountId;
@override final  ConfigurationState source;
@override final  ModelsState modelSource;
@override final  TemplatesState templateSource;
@override final  AccountTemplatesValue templates;
@override final  AccountConfiguration? canonical;
@override final  AccountCatalogEntry? catalog;
@override@JsonKey() final  bool templatePreview;
@override@JsonKey() final  bool rebuildModelConfiguration;
@override final  String? templateId;
@override final  String protocol;
@override final  String name;
@override final  String baseUrl;
/// 新建账号的初始计费类别草稿；`BillingKind.unknown` 表示“未指定”，提交为 null。
///
/// 只在 [create] 为 true 时使用：编辑已有账号的计费改写必须走
/// `setAccountBillingKind` 窄命令，不得借保存覆盖类别。
@override@JsonKey() final  BillingKind initialBillingKind;
@override@JsonKey() final  AccountSecretIntent secretIntent;
@override@JsonKey() final  String secretRaw;
 final  List<CustomModelDraft> _customModels;
@override@JsonKey() List<CustomModelDraft> get customModels {
  if (_customModels is EqualUnmodifiableListView) return _customModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_customModels);
}

 final  List<String> _removedCustomModelIds;
@override@JsonKey() List<String> get removedCustomModelIds {
  if (_removedCustomModelIds is EqualUnmodifiableListView) return _removedCustomModelIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_removedCustomModelIds);
}

 final  Map<String, String> _connectionEdits;
@override@JsonKey() Map<String, String> get connectionEdits {
  if (_connectionEdits is EqualUnmodifiableMapView) return _connectionEdits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_connectionEdits);
}

 final  Set<AccountEditorField> _dirtyFields;
@override@JsonKey() Set<AccountEditorField> get dirtyFields {
  if (_dirtyFields is EqualUnmodifiableSetView) return _dirtyFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dirtyFields);
}

 final  Map<AccountEditorField, AccountValidation> _validation;
@override@JsonKey() Map<AccountEditorField, AccountValidation> get validation {
  if (_validation is EqualUnmodifiableMapView) return _validation;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_validation);
}

@override@JsonKey() final  int draftRevision;
@override@JsonKey() final  int formGeneration;
@override@JsonKey() final  bool saved;
@override@JsonKey() final  bool verifying;
@override final  SettingsAction? saveAction;
@override final  SettingsAction? defaultAction;
/// 编辑已有账号时 `setAccountBillingKind` 的受理与结果（noCharge 开关）。
@override final  SettingsAction? billingAction;
@override final  StudioFailure? sourceError;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEditorViewStateCopyWith<_AccountEditorViewState> get copyWith => __$AccountEditorViewStateCopyWithImpl<_AccountEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEditorViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.source, source) || other.source == source)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.templateSource, templateSource) || other.templateSource == templateSource)&&(identical(other.templates, templates) || other.templates == templates)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.templatePreview, templatePreview) || other.templatePreview == templatePreview)&&(identical(other.rebuildModelConfiguration, rebuildModelConfiguration) || other.rebuildModelConfiguration == rebuildModelConfiguration)&&(identical(other.templateId, templateId) || other.templateId == templateId)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.name, name) || other.name == name)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.initialBillingKind, initialBillingKind) || other.initialBillingKind == initialBillingKind)&&(identical(other.secretIntent, secretIntent) || other.secretIntent == secretIntent)&&(identical(other.secretRaw, secretRaw) || other.secretRaw == secretRaw)&&const DeepCollectionEquality().equals(other.customModels, _customModels)&&const DeepCollectionEquality().equals(other.removedCustomModelIds, _removedCustomModelIds)&&const DeepCollectionEquality().equals(other.connectionEdits, _connectionEdits)&&const DeepCollectionEquality().equals(other.dirtyFields, _dirtyFields)&&const DeepCollectionEquality().equals(other.validation, _validation)&&(identical(other.draftRevision, draftRevision) || other.draftRevision == draftRevision)&&(identical(other.formGeneration, formGeneration) || other.formGeneration == formGeneration)&&(identical(other.saved, saved) || other.saved == saved)&&(identical(other.verifying, verifying) || other.verifying == verifying)&&(identical(other.saveAction, saveAction) || other.saveAction == saveAction)&&(identical(other.defaultAction, defaultAction) || other.defaultAction == defaultAction)&&(identical(other.billingAction, billingAction) || other.billingAction == billingAction)&&(identical(other.sourceError, sourceError) || other.sourceError == sourceError));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,key,accountId,source,modelSource,templateSource,templates,canonical,catalog,templatePreview,rebuildModelConfiguration,templateId,protocol,name,baseUrl,initialBillingKind,secretIntent,secretRaw,const DeepCollectionEquality().hash(_customModels),const DeepCollectionEquality().hash(_removedCustomModelIds),const DeepCollectionEquality().hash(_connectionEdits),const DeepCollectionEquality().hash(_dirtyFields),const DeepCollectionEquality().hash(_validation),draftRevision,formGeneration,saved,verifying,saveAction,defaultAction,billingAction,sourceError]);
}



}

/// @nodoc
abstract mixin class _$AccountEditorViewStateCopyWith<$Res> implements $AccountEditorViewStateCopyWith<$Res> {
  factory _$AccountEditorViewStateCopyWith(_AccountEditorViewState value, $Res Function(_AccountEditorViewState) _then) = __$AccountEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountEditorKey key, String accountId, ConfigurationState source, ModelsState modelSource, TemplatesState templateSource, AccountTemplatesValue templates, AccountConfiguration? canonical, AccountCatalogEntry? catalog, bool templatePreview, bool rebuildModelConfiguration, String? templateId, String protocol, String name, String baseUrl, BillingKind initialBillingKind, AccountSecretIntent secretIntent, String secretRaw, List<CustomModelDraft> customModels, List<String> removedCustomModelIds, Map<String, String> connectionEdits, Set<AccountEditorField> dirtyFields, Map<AccountEditorField, AccountValidation> validation, int draftRevision, int formGeneration, bool saved, bool verifying, SettingsAction? saveAction, SettingsAction? defaultAction, SettingsAction? billingAction, StudioFailure? sourceError
});


@override $AccountEditorKeyCopyWith<$Res> get key;@override $ConfigurationStateCopyWith<$Res> get source;@override $ModelsStateCopyWith<$Res> get modelSource;@override $TemplatesStateCopyWith<$Res> get templateSource;@override $AccountTemplatesValueCopyWith<$Res> get templates;@override $AccountConfigurationCopyWith<$Res>? get canonical;@override $AccountCatalogEntryCopyWith<$Res>? get catalog;@override $SettingsActionCopyWith<$Res>? get saveAction;@override $SettingsActionCopyWith<$Res>? get defaultAction;@override $SettingsActionCopyWith<$Res>? get billingAction;@override $StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class __$AccountEditorViewStateCopyWithImpl<$Res>
    implements _$AccountEditorViewStateCopyWith<$Res> {
  __$AccountEditorViewStateCopyWithImpl(this._self, this._then);

  final _AccountEditorViewState _self;
  final $Res Function(_AccountEditorViewState) _then;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? accountId = null,Object? source = null,Object? modelSource = null,Object? templateSource = null,Object? templates = null,Object? canonical = freezed,Object? catalog = freezed,Object? templatePreview = null,Object? rebuildModelConfiguration = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? initialBillingKind = null,Object? secretIntent = null,Object? secretRaw = null,Object? customModels = null,Object? removedCustomModelIds = null,Object? connectionEdits = null,Object? dirtyFields = null,Object? validation = null,Object? draftRevision = null,Object? formGeneration = null,Object? saved = null,Object? verifying = null,Object? saveAction = freezed,Object? defaultAction = freezed,Object? billingAction = freezed,Object? sourceError = freezed,}) {
  return _then(_AccountEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountEditorKey,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,templateSource: null == templateSource ? _self.templateSource : templateSource // ignore: cast_nullable_to_non_nullable
as TemplatesState,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as AccountTemplatesValue,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AccountConfiguration?,catalog: freezed == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogEntry?,templatePreview: null == templatePreview ? _self.templatePreview : templatePreview // ignore: cast_nullable_to_non_nullable
as bool,rebuildModelConfiguration: null == rebuildModelConfiguration ? _self.rebuildModelConfiguration : rebuildModelConfiguration // ignore: cast_nullable_to_non_nullable
as bool,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as String?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,initialBillingKind: null == initialBillingKind ? _self.initialBillingKind : initialBillingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,secretIntent: null == secretIntent ? _self.secretIntent : secretIntent // ignore: cast_nullable_to_non_nullable
as AccountSecretIntent,secretRaw: null == secretRaw ? _self.secretRaw : secretRaw // ignore: cast_nullable_to_non_nullable
as String,customModels: null == customModels ? _self._customModels : customModels // ignore: cast_nullable_to_non_nullable
as List<CustomModelDraft>,removedCustomModelIds: null == removedCustomModelIds ? _self._removedCustomModelIds : removedCustomModelIds // ignore: cast_nullable_to_non_nullable
as List<String>,connectionEdits: null == connectionEdits ? _self._connectionEdits : connectionEdits // ignore: cast_nullable_to_non_nullable
as Map<String, String>,dirtyFields: null == dirtyFields ? _self._dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<AccountEditorField>,validation: null == validation ? _self._validation : validation // ignore: cast_nullable_to_non_nullable
as Map<AccountEditorField, AccountValidation>,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,formGeneration: null == formGeneration ? _self.formGeneration : formGeneration // ignore: cast_nullable_to_non_nullable
as int,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,verifying: null == verifying ? _self.verifying : verifying // ignore: cast_nullable_to_non_nullable
as bool,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,defaultAction: freezed == defaultAction ? _self.defaultAction : defaultAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,billingAction: freezed == billingAction ? _self.billingAction : billingAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res> get key {

  return $AccountEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TemplatesStateCopyWith<$Res> get templateSource {

  return $TemplatesStateCopyWith<$Res>(_self.templateSource, (value) {
    return _then(_self.copyWith(templateSource: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesValueCopyWith<$Res> get templates {

  return $AccountTemplatesValueCopyWith<$Res>(_self.templates, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $AccountConfigurationCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogEntryCopyWith<$Res>? get catalog {
    if (_self.catalog == null) {
    return null;
  }

  return $AccountCatalogEntryCopyWith<$Res>(_self.catalog!, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of AccountEditorViewState
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
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get defaultAction {
    if (_self.defaultAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.defaultAction!, (value) {
    return _then(_self.copyWith(defaultAction: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get billingAction {
    if (_self.billingAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.billingAction!, (value) {
    return _then(_self.copyWith(billingAction: value));
  });
}/// Create a copy of AccountEditorViewState
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
