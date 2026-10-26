// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'accounts_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageCheckPresentation {

 AccountUsageQueryIdentity? get identity; OperationState get operation; bool get preparing; StudioFailure? get observationError;
/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageCheckPresentationCopyWith<AccountUsageCheckPresentation> get copyWith => _$AccountUsageCheckPresentationCopyWithImpl<AccountUsageCheckPresentation>(this as AccountUsageCheckPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageCheckPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageCheckPresentation&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.preparing, _this.preparing) || other.preparing == _this.preparing)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as AccountUsageCheckPresentation;
  return Object.hash(runtimeType,_this.identity,_this.operation,_this.preparing,_this.observationError);
}

@override
String toString() {
  final _this = this as AccountUsageCheckPresentation;
  return 'AccountUsageCheckPresentation(identity: ${_this.identity}, operation: ${_this.operation}, preparing: ${_this.preparing}, observationError: ${_this.observationError})';
}


}

/// @nodoc
abstract mixin class $AccountUsageCheckPresentationCopyWith<$Res>  {
  factory $AccountUsageCheckPresentationCopyWith(AccountUsageCheckPresentation value, $Res Function(AccountUsageCheckPresentation) _then) = _$AccountUsageCheckPresentationCopyWithImpl;
@useResult
$Res call({
 AccountUsageQueryIdentity? identity, OperationState operation, bool preparing, StudioFailure? observationError
});


$AccountUsageQueryIdentityCopyWith<$Res>? get identity;$OperationStateCopyWith<$Res> get operation;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$AccountUsageCheckPresentationCopyWithImpl<$Res>
    implements $AccountUsageCheckPresentationCopyWith<$Res> {
  _$AccountUsageCheckPresentationCopyWithImpl(this._self, this._then);

  final AccountUsageCheckPresentation _self;
  final $Res Function(AccountUsageCheckPresentation) _then;

/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = freezed,Object? operation = null,Object? preparing = null,Object? observationError = freezed,}) {
  return _then(AccountUsageCheckPresentation(
identity: freezed == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as AccountUsageQueryIdentity?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState,preparing: null == preparing ? _self.preparing : preparing // ignore: cast_nullable_to_non_nullable
as bool,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageQueryIdentityCopyWith<$Res>? get identity {
    if (_self.identity == null) {
    return null;
  }

  return $AccountUsageQueryIdentityCopyWith<$Res>(_self.identity!, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res> get operation {

  return $OperationStateCopyWith<$Res>(_self.operation, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageCheckPresentation].
extension AccountUsageCheckPresentationPatterns on AccountUsageCheckPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageCheckPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageCheckPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageCheckPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountUsageQueryIdentity? identity,  OperationState operation,  bool preparing,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation() when $default != null:
return $default(_that.identity,_that.operation,_that.preparing,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountUsageQueryIdentity? identity,  OperationState operation,  bool preparing,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation():
return $default(_that.identity,_that.operation,_that.preparing,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountUsageQueryIdentity? identity,  OperationState operation,  bool preparing,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageCheckPresentation() when $default != null:
return $default(_that.identity,_that.operation,_that.preparing,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageCheckPresentation implements AccountUsageCheckPresentation {
  const _AccountUsageCheckPresentation({required this.identity, required this.operation, required this.preparing, this.observationError});


@override final  AccountUsageQueryIdentity? identity;
@override final  OperationState operation;
@override final  bool preparing;
@override final  StudioFailure? observationError;

/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageCheckPresentationCopyWith<_AccountUsageCheckPresentation> get copyWith => __$AccountUsageCheckPresentationCopyWithImpl<_AccountUsageCheckPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageCheckPresentation&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.preparing, preparing) || other.preparing == preparing)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,operation,preparing,observationError);
}

@override
String toString() {
    return 'AccountUsageCheckPresentation(identity: $identity, operation: $operation, preparing: $preparing, observationError: $observationError)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageCheckPresentationCopyWith<$Res> implements $AccountUsageCheckPresentationCopyWith<$Res> {
  factory _$AccountUsageCheckPresentationCopyWith(_AccountUsageCheckPresentation value, $Res Function(_AccountUsageCheckPresentation) _then) = __$AccountUsageCheckPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountUsageQueryIdentity? identity, OperationState operation, bool preparing, StudioFailure? observationError
});


@override $AccountUsageQueryIdentityCopyWith<$Res>? get identity;@override $OperationStateCopyWith<$Res> get operation;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$AccountUsageCheckPresentationCopyWithImpl<$Res>
    implements _$AccountUsageCheckPresentationCopyWith<$Res> {
  __$AccountUsageCheckPresentationCopyWithImpl(this._self, this._then);

  final _AccountUsageCheckPresentation _self;
  final $Res Function(_AccountUsageCheckPresentation) _then;

/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = freezed,Object? operation = null,Object? preparing = null,Object? observationError = freezed,}) {
  return _then(_AccountUsageCheckPresentation(
identity: freezed == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as AccountUsageQueryIdentity?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState,preparing: null == preparing ? _self.preparing : preparing // ignore: cast_nullable_to_non_nullable
as bool,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageQueryIdentityCopyWith<$Res>? get identity {
    if (_self.identity == null) {
    return null;
  }

  return $AccountUsageQueryIdentityCopyWith<$Res>(_self.identity!, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res> get operation {

  return $OperationStateCopyWith<$Res>(_self.operation, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of AccountUsageCheckPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}

/// @nodoc
mixin _$AccountsViewState {

 ConfigurationState get source; ModelsState get modelSource; TemplatesState get templateSource; AccountUsageState get usageSource; AccountTemplatesValue? get templates; String get query; List<String> get matchingAccountIds;/// 与查询匹配的 ACP 接入身份；与 [matchingAccountIds] 各自独立的顺序来源。
 List<String> get matchingAcpAccountIds; String? get selectedAccountId; bool get showDetails; AccountEditorKey? get editor; String? get editorAccountId; int get navigationIntent; int get latestIntent; Map<(String, AccountRowAction,), SettingsAction> get rowActions; Set<String> get preparingRemovalIds; Map<(String, String,), SettingsAction> get modelActions; Map<String, SettingsAction> get usageActions; Map<String, OperationId> get usageActionIds; Map<String, AccountUsageCheckPresentation> get usageChecks; bool get refreshingAll; Map<AccountsReadField, StudioFailure> get readIssues; Set<AccountsReadField> get reading; StudioFailure? get editorError;/// Settings canonical 快照里的 ACP 接入集合；null 表示尚未读到事实。
 AcpAccountDirectory? get acpAccounts;/// ACP 接入模板目录；null 表示尚未读取，空目录表示后端未声明模板。
 AcpAccountCatalog? get acpCatalog;/// `acpAuth` 最近一次 canonical 快照；null 表示领域尚未观察。
 AcpAuthSnapshot? get acpAuth;/// Native + ACP 的 typed 目录投影；null 表示素材尚未齐备。
 AccountDirectoryView? get directory;/// 当前选中的 ACP 接入身份（与 Native 选择互斥）。
 String? get selectedAcpAccountId;/// 当前 ACP 编辑目标（新建/编辑）；null 表示没有 ACP 表单。
 AcpAccountEditorTarget? get acpEditor;/// 已保存接入的 canonical 回执明确“需要准备/安装不合格”：编辑表单要给出准备动作。
 bool get acpNeedsPreparation;/// 按目标接入记账的命令失败通知：只出现在目标行/目标详情。
 Map<String, AcpCommandNotice> get acpNotices;/// 按目标接入记账的删除受理与结果。
 Map<String, SettingsAction> get acpRemovals;
/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountsViewStateCopyWith<AccountsViewState> get copyWith => _$AccountsViewStateCopyWithImpl<AccountsViewState>(this as AccountsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountsViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.templateSource, _this.templateSource) || other.templateSource == _this.templateSource)&&(identical(other.usageSource, _this.usageSource) || other.usageSource == _this.usageSource)&&(identical(other.templates, _this.templates) || other.templates == _this.templates)&&(identical(other.query, _this.query) || other.query == _this.query)&&const DeepCollectionEquality().equals(other.matchingAccountIds, _this.matchingAccountIds)&&const DeepCollectionEquality().equals(other.matchingAcpAccountIds, _this.matchingAcpAccountIds)&&(identical(other.selectedAccountId, _this.selectedAccountId) || other.selectedAccountId == _this.selectedAccountId)&&(identical(other.showDetails, _this.showDetails) || other.showDetails == _this.showDetails)&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.editorAccountId, _this.editorAccountId) || other.editorAccountId == _this.editorAccountId)&&(identical(other.navigationIntent, _this.navigationIntent) || other.navigationIntent == _this.navigationIntent)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&const DeepCollectionEquality().equals(other.rowActions, _this.rowActions)&&const DeepCollectionEquality().equals(other.preparingRemovalIds, _this.preparingRemovalIds)&&const DeepCollectionEquality().equals(other.modelActions, _this.modelActions)&&const DeepCollectionEquality().equals(other.usageActions, _this.usageActions)&&const DeepCollectionEquality().equals(other.usageActionIds, _this.usageActionIds)&&const DeepCollectionEquality().equals(other.usageChecks, _this.usageChecks)&&(identical(other.refreshingAll, _this.refreshingAll) || other.refreshingAll == _this.refreshingAll)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&(identical(other.editorError, _this.editorError) || other.editorError == _this.editorError)&&(identical(other.acpAccounts, _this.acpAccounts) || other.acpAccounts == _this.acpAccounts)&&(identical(other.acpCatalog, _this.acpCatalog) || other.acpCatalog == _this.acpCatalog)&&(identical(other.acpAuth, _this.acpAuth) || other.acpAuth == _this.acpAuth)&&(identical(other.directory, _this.directory) || other.directory == _this.directory)&&(identical(other.selectedAcpAccountId, _this.selectedAcpAccountId) || other.selectedAcpAccountId == _this.selectedAcpAccountId)&&(identical(other.acpEditor, _this.acpEditor) || other.acpEditor == _this.acpEditor)&&(identical(other.acpNeedsPreparation, _this.acpNeedsPreparation) || other.acpNeedsPreparation == _this.acpNeedsPreparation)&&const DeepCollectionEquality().equals(other.acpNotices, _this.acpNotices)&&const DeepCollectionEquality().equals(other.acpRemovals, _this.acpRemovals));
}


@override
int get hashCode {
  final _this = this as AccountsViewState;
  return Object.hashAll([runtimeType,_this.source,_this.modelSource,_this.templateSource,_this.usageSource,_this.templates,_this.query,const DeepCollectionEquality().hash(_this.matchingAccountIds),const DeepCollectionEquality().hash(_this.matchingAcpAccountIds),_this.selectedAccountId,_this.showDetails,_this.editor,_this.editorAccountId,_this.navigationIntent,_this.latestIntent,const DeepCollectionEquality().hash(_this.rowActions),const DeepCollectionEquality().hash(_this.preparingRemovalIds),const DeepCollectionEquality().hash(_this.modelActions),const DeepCollectionEquality().hash(_this.usageActions),const DeepCollectionEquality().hash(_this.usageActionIds),const DeepCollectionEquality().hash(_this.usageChecks),_this.refreshingAll,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading),_this.editorError,_this.acpAccounts,_this.acpCatalog,_this.acpAuth,_this.directory,_this.selectedAcpAccountId,_this.acpEditor,_this.acpNeedsPreparation,const DeepCollectionEquality().hash(_this.acpNotices),const DeepCollectionEquality().hash(_this.acpRemovals)]);
}

@override
String toString() {
  final _this = this as AccountsViewState;
  return 'AccountsViewState(source: ${_this.source}, modelSource: ${_this.modelSource}, templateSource: ${_this.templateSource}, usageSource: ${_this.usageSource}, templates: ${_this.templates}, query: ${_this.query}, matchingAccountIds: ${_this.matchingAccountIds}, matchingAcpAccountIds: ${_this.matchingAcpAccountIds}, selectedAccountId: ${_this.selectedAccountId}, showDetails: ${_this.showDetails}, editor: ${_this.editor}, editorAccountId: ${_this.editorAccountId}, navigationIntent: ${_this.navigationIntent}, latestIntent: ${_this.latestIntent}, rowActions: ${_this.rowActions}, preparingRemovalIds: ${_this.preparingRemovalIds}, modelActions: ${_this.modelActions}, usageActions: ${_this.usageActions}, usageActionIds: ${_this.usageActionIds}, usageChecks: ${_this.usageChecks}, refreshingAll: ${_this.refreshingAll}, readIssues: ${_this.readIssues}, reading: ${_this.reading}, editorError: ${_this.editorError}, acpAccounts: ${_this.acpAccounts}, acpCatalog: ${_this.acpCatalog}, acpAuth: ${_this.acpAuth}, directory: ${_this.directory}, selectedAcpAccountId: ${_this.selectedAcpAccountId}, acpEditor: ${_this.acpEditor}, acpNeedsPreparation: ${_this.acpNeedsPreparation}, acpNotices: ${_this.acpNotices}, acpRemovals: ${_this.acpRemovals})';
}


}

/// @nodoc
abstract mixin class $AccountsViewStateCopyWith<$Res>  {
  factory $AccountsViewStateCopyWith(AccountsViewState value, $Res Function(AccountsViewState) _then) = _$AccountsViewStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState source, ModelsState modelSource, TemplatesState templateSource, AccountUsageState usageSource, AccountTemplatesValue? templates, String query, List<String> matchingAccountIds, List<String> matchingAcpAccountIds, String? selectedAccountId, bool showDetails, AccountEditorKey? editor, String? editorAccountId, int navigationIntent, int latestIntent, Map<(String, AccountRowAction,), SettingsAction> rowActions, Set<String> preparingRemovalIds, Map<(String, String,), SettingsAction> modelActions, Map<String, SettingsAction> usageActions, Map<String, OperationId> usageActionIds, Map<String, AccountUsageCheckPresentation> usageChecks, bool refreshingAll, Map<AccountsReadField, StudioFailure> readIssues, Set<AccountsReadField> reading, StudioFailure? editorError, AcpAccountDirectory? acpAccounts, AcpAccountCatalog? acpCatalog, AcpAuthSnapshot? acpAuth, AccountDirectoryView? directory, String? selectedAcpAccountId, AcpAccountEditorTarget? acpEditor, bool acpNeedsPreparation, Map<String, AcpCommandNotice> acpNotices, Map<String, SettingsAction> acpRemovals
});


$ConfigurationStateCopyWith<$Res> get source;$ModelsStateCopyWith<$Res> get modelSource;$TemplatesStateCopyWith<$Res> get templateSource;$AccountUsageStateCopyWith<$Res> get usageSource;$AccountTemplatesValueCopyWith<$Res>? get templates;$AccountEditorKeyCopyWith<$Res>? get editor;$StudioFailureCopyWith<$Res>? get editorError;$AcpAccountDirectoryCopyWith<$Res>? get acpAccounts;$AcpAccountCatalogCopyWith<$Res>? get acpCatalog;$AcpAuthSnapshotCopyWith<$Res>? get acpAuth;$AccountDirectoryViewCopyWith<$Res>? get directory;

}
/// @nodoc
class _$AccountsViewStateCopyWithImpl<$Res>
    implements $AccountsViewStateCopyWith<$Res> {
  _$AccountsViewStateCopyWithImpl(this._self, this._then);

  final AccountsViewState _self;
  final $Res Function(AccountsViewState) _then;

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? modelSource = null,Object? templateSource = null,Object? usageSource = null,Object? templates = freezed,Object? query = null,Object? matchingAccountIds = null,Object? matchingAcpAccountIds = null,Object? selectedAccountId = freezed,Object? showDetails = null,Object? editor = freezed,Object? editorAccountId = freezed,Object? navigationIntent = null,Object? latestIntent = null,Object? rowActions = null,Object? preparingRemovalIds = null,Object? modelActions = null,Object? usageActions = null,Object? usageActionIds = null,Object? usageChecks = null,Object? refreshingAll = null,Object? readIssues = null,Object? reading = null,Object? editorError = freezed,Object? acpAccounts = freezed,Object? acpCatalog = freezed,Object? acpAuth = freezed,Object? directory = freezed,Object? selectedAcpAccountId = freezed,Object? acpEditor = freezed,Object? acpNeedsPreparation = null,Object? acpNotices = null,Object? acpRemovals = null,}) {
  return _then(AccountsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,templateSource: null == templateSource ? _self.templateSource : templateSource // ignore: cast_nullable_to_non_nullable
as TemplatesState,usageSource: null == usageSource ? _self.usageSource : usageSource // ignore: cast_nullable_to_non_nullable
as AccountUsageState,templates: freezed == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as AccountTemplatesValue?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,matchingAccountIds: null == matchingAccountIds ? _self.matchingAccountIds : matchingAccountIds // ignore: cast_nullable_to_non_nullable
as List<String>,matchingAcpAccountIds: null == matchingAcpAccountIds ? _self.matchingAcpAccountIds : matchingAcpAccountIds // ignore: cast_nullable_to_non_nullable
as List<String>,selectedAccountId: freezed == selectedAccountId ? _self.selectedAccountId : selectedAccountId // ignore: cast_nullable_to_non_nullable
as String?,showDetails: null == showDetails ? _self.showDetails : showDetails // ignore: cast_nullable_to_non_nullable
as bool,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as AccountEditorKey?,editorAccountId: freezed == editorAccountId ? _self.editorAccountId : editorAccountId // ignore: cast_nullable_to_non_nullable
as String?,navigationIntent: null == navigationIntent ? _self.navigationIntent : navigationIntent // ignore: cast_nullable_to_non_nullable
as int,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,rowActions: null == rowActions ? _self.rowActions : rowActions // ignore: cast_nullable_to_non_nullable
as Map<(String, AccountRowAction,), SettingsAction>,preparingRemovalIds: null == preparingRemovalIds ? _self.preparingRemovalIds : preparingRemovalIds // ignore: cast_nullable_to_non_nullable
as Set<String>,modelActions: null == modelActions ? _self.modelActions : modelActions // ignore: cast_nullable_to_non_nullable
as Map<(String, String,), SettingsAction>,usageActions: null == usageActions ? _self.usageActions : usageActions // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,usageActionIds: null == usageActionIds ? _self.usageActionIds : usageActionIds // ignore: cast_nullable_to_non_nullable
as Map<String, OperationId>,usageChecks: null == usageChecks ? _self.usageChecks : usageChecks // ignore: cast_nullable_to_non_nullable
as Map<String, AccountUsageCheckPresentation>,refreshingAll: null == refreshingAll ? _self.refreshingAll : refreshingAll // ignore: cast_nullable_to_non_nullable
as bool,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<AccountsReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<AccountsReadField>,editorError: freezed == editorError ? _self.editorError : editorError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,acpAccounts: freezed == acpAccounts ? _self.acpAccounts : acpAccounts // ignore: cast_nullable_to_non_nullable
as AcpAccountDirectory?,acpCatalog: freezed == acpCatalog ? _self.acpCatalog : acpCatalog // ignore: cast_nullable_to_non_nullable
as AcpAccountCatalog?,acpAuth: freezed == acpAuth ? _self.acpAuth : acpAuth // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot?,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as AccountDirectoryView?,selectedAcpAccountId: freezed == selectedAcpAccountId ? _self.selectedAcpAccountId : selectedAcpAccountId // ignore: cast_nullable_to_non_nullable
as String?,acpEditor: freezed == acpEditor ? _self.acpEditor : acpEditor // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorTarget?,acpNeedsPreparation: null == acpNeedsPreparation ? _self.acpNeedsPreparation : acpNeedsPreparation // ignore: cast_nullable_to_non_nullable
as bool,acpNotices: null == acpNotices ? _self.acpNotices : acpNotices // ignore: cast_nullable_to_non_nullable
as Map<String, AcpCommandNotice>,acpRemovals: null == acpRemovals ? _self.acpRemovals : acpRemovals // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,
  ));
}
/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TemplatesStateCopyWith<$Res> get templateSource {

  return $TemplatesStateCopyWith<$Res>(_self.templateSource, (value) {
    return _then(_self.copyWith(templateSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageStateCopyWith<$Res> get usageSource {

  return $AccountUsageStateCopyWith<$Res>(_self.usageSource, (value) {
    return _then(_self.copyWith(usageSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesValueCopyWith<$Res>? get templates {
    if (_self.templates == null) {
    return null;
  }

  return $AccountTemplatesValueCopyWith<$Res>(_self.templates!, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $AccountEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get editorError {
    if (_self.editorError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.editorError!, (value) {
    return _then(_self.copyWith(editorError: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountDirectoryCopyWith<$Res>? get acpAccounts {
    if (_self.acpAccounts == null) {
    return null;
  }

  return $AcpAccountDirectoryCopyWith<$Res>(_self.acpAccounts!, (value) {
    return _then(_self.copyWith(acpAccounts: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountCatalogCopyWith<$Res>? get acpCatalog {
    if (_self.acpCatalog == null) {
    return null;
  }

  return $AcpAccountCatalogCopyWith<$Res>(_self.acpCatalog!, (value) {
    return _then(_self.copyWith(acpCatalog: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res>? get acpAuth {
    if (_self.acpAuth == null) {
    return null;
  }

  return $AcpAuthSnapshotCopyWith<$Res>(_self.acpAuth!, (value) {
    return _then(_self.copyWith(acpAuth: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDirectoryViewCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $AccountDirectoryViewCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountsViewState].
extension AccountsViewStatePatterns on AccountsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountUsageState usageSource,  AccountTemplatesValue? templates,  String query,  List<String> matchingAccountIds,  List<String> matchingAcpAccountIds,  String? selectedAccountId,  bool showDetails,  AccountEditorKey? editor,  String? editorAccountId,  int navigationIntent,  int latestIntent,  Map<(String, AccountRowAction,), SettingsAction> rowActions,  Set<String> preparingRemovalIds,  Map<(String, String,), SettingsAction> modelActions,  Map<String, SettingsAction> usageActions,  Map<String, OperationId> usageActionIds,  Map<String, AccountUsageCheckPresentation> usageChecks,  bool refreshingAll,  Map<AccountsReadField, StudioFailure> readIssues,  Set<AccountsReadField> reading,  StudioFailure? editorError,  AcpAccountDirectory? acpAccounts,  AcpAccountCatalog? acpCatalog,  AcpAuthSnapshot? acpAuth,  AccountDirectoryView? directory,  String? selectedAcpAccountId,  AcpAccountEditorTarget? acpEditor,  bool acpNeedsPreparation,  Map<String, AcpCommandNotice> acpNotices,  Map<String, SettingsAction> acpRemovals)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
return $default(_that.source,_that.modelSource,_that.templateSource,_that.usageSource,_that.templates,_that.query,_that.matchingAccountIds,_that.matchingAcpAccountIds,_that.selectedAccountId,_that.showDetails,_that.editor,_that.editorAccountId,_that.navigationIntent,_that.latestIntent,_that.rowActions,_that.preparingRemovalIds,_that.modelActions,_that.usageActions,_that.usageActionIds,_that.usageChecks,_that.refreshingAll,_that.readIssues,_that.reading,_that.editorError,_that.acpAccounts,_that.acpCatalog,_that.acpAuth,_that.directory,_that.selectedAcpAccountId,_that.acpEditor,_that.acpNeedsPreparation,_that.acpNotices,_that.acpRemovals);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountUsageState usageSource,  AccountTemplatesValue? templates,  String query,  List<String> matchingAccountIds,  List<String> matchingAcpAccountIds,  String? selectedAccountId,  bool showDetails,  AccountEditorKey? editor,  String? editorAccountId,  int navigationIntent,  int latestIntent,  Map<(String, AccountRowAction,), SettingsAction> rowActions,  Set<String> preparingRemovalIds,  Map<(String, String,), SettingsAction> modelActions,  Map<String, SettingsAction> usageActions,  Map<String, OperationId> usageActionIds,  Map<String, AccountUsageCheckPresentation> usageChecks,  bool refreshingAll,  Map<AccountsReadField, StudioFailure> readIssues,  Set<AccountsReadField> reading,  StudioFailure? editorError,  AcpAccountDirectory? acpAccounts,  AcpAccountCatalog? acpCatalog,  AcpAuthSnapshot? acpAuth,  AccountDirectoryView? directory,  String? selectedAcpAccountId,  AcpAccountEditorTarget? acpEditor,  bool acpNeedsPreparation,  Map<String, AcpCommandNotice> acpNotices,  Map<String, SettingsAction> acpRemovals)  $default,) {final _that = this;
switch (_that) {
case _AccountsViewState():
return $default(_that.source,_that.modelSource,_that.templateSource,_that.usageSource,_that.templates,_that.query,_that.matchingAccountIds,_that.matchingAcpAccountIds,_that.selectedAccountId,_that.showDetails,_that.editor,_that.editorAccountId,_that.navigationIntent,_that.latestIntent,_that.rowActions,_that.preparingRemovalIds,_that.modelActions,_that.usageActions,_that.usageActionIds,_that.usageChecks,_that.refreshingAll,_that.readIssues,_that.reading,_that.editorError,_that.acpAccounts,_that.acpCatalog,_that.acpAuth,_that.directory,_that.selectedAcpAccountId,_that.acpEditor,_that.acpNeedsPreparation,_that.acpNotices,_that.acpRemovals);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState source,  ModelsState modelSource,  TemplatesState templateSource,  AccountUsageState usageSource,  AccountTemplatesValue? templates,  String query,  List<String> matchingAccountIds,  List<String> matchingAcpAccountIds,  String? selectedAccountId,  bool showDetails,  AccountEditorKey? editor,  String? editorAccountId,  int navigationIntent,  int latestIntent,  Map<(String, AccountRowAction,), SettingsAction> rowActions,  Set<String> preparingRemovalIds,  Map<(String, String,), SettingsAction> modelActions,  Map<String, SettingsAction> usageActions,  Map<String, OperationId> usageActionIds,  Map<String, AccountUsageCheckPresentation> usageChecks,  bool refreshingAll,  Map<AccountsReadField, StudioFailure> readIssues,  Set<AccountsReadField> reading,  StudioFailure? editorError,  AcpAccountDirectory? acpAccounts,  AcpAccountCatalog? acpCatalog,  AcpAuthSnapshot? acpAuth,  AccountDirectoryView? directory,  String? selectedAcpAccountId,  AcpAccountEditorTarget? acpEditor,  bool acpNeedsPreparation,  Map<String, AcpCommandNotice> acpNotices,  Map<String, SettingsAction> acpRemovals)?  $default,) {final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
return $default(_that.source,_that.modelSource,_that.templateSource,_that.usageSource,_that.templates,_that.query,_that.matchingAccountIds,_that.matchingAcpAccountIds,_that.selectedAccountId,_that.showDetails,_that.editor,_that.editorAccountId,_that.navigationIntent,_that.latestIntent,_that.rowActions,_that.preparingRemovalIds,_that.modelActions,_that.usageActions,_that.usageActionIds,_that.usageChecks,_that.refreshingAll,_that.readIssues,_that.reading,_that.editorError,_that.acpAccounts,_that.acpCatalog,_that.acpAuth,_that.directory,_that.selectedAcpAccountId,_that.acpEditor,_that.acpNeedsPreparation,_that.acpNotices,_that.acpRemovals);case _:
  return null;

}
}

}

/// @nodoc


class _AccountsViewState implements AccountsViewState {
  const _AccountsViewState({required this.source, required this.modelSource, required this.templateSource, required this.usageSource, this.templates, this.query = '',  List<String> matchingAccountIds = const [],  List<String> matchingAcpAccountIds = const [], this.selectedAccountId, this.showDetails = false, this.editor, this.editorAccountId, this.navigationIntent = 0, this.latestIntent = 0,  Map<(String, AccountRowAction,), SettingsAction> rowActions = const {},  Set<String> preparingRemovalIds = const {},  Map<(String, String,), SettingsAction> modelActions = const {},  Map<String, SettingsAction> usageActions = const {},  Map<String, OperationId> usageActionIds = const {},  Map<String, AccountUsageCheckPresentation> usageChecks = const {}, this.refreshingAll = false,  Map<AccountsReadField, StudioFailure> readIssues = const {},  Set<AccountsReadField> reading = const {}, this.editorError, this.acpAccounts, this.acpCatalog, this.acpAuth, this.directory, this.selectedAcpAccountId, this.acpEditor, this.acpNeedsPreparation = false,  Map<String, AcpCommandNotice> acpNotices = const {},  Map<String, SettingsAction> acpRemovals = const {}}): _matchingAccountIds = matchingAccountIds,_matchingAcpAccountIds = matchingAcpAccountIds,_rowActions = rowActions,_preparingRemovalIds = preparingRemovalIds,_modelActions = modelActions,_usageActions = usageActions,_usageActionIds = usageActionIds,_usageChecks = usageChecks,_readIssues = readIssues,_reading = reading,_acpNotices = acpNotices,_acpRemovals = acpRemovals;


@override final  ConfigurationState source;
@override final  ModelsState modelSource;
@override final  TemplatesState templateSource;
@override final  AccountUsageState usageSource;
@override final  AccountTemplatesValue? templates;
@override@JsonKey() final  String query;
 final  List<String> _matchingAccountIds;
@override@JsonKey() List<String> get matchingAccountIds {
  if (_matchingAccountIds is EqualUnmodifiableListView) return _matchingAccountIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_matchingAccountIds);
}

/// 与查询匹配的 ACP 接入身份；与 [matchingAccountIds] 各自独立的顺序来源。
 final  List<String> _matchingAcpAccountIds;
/// 与查询匹配的 ACP 接入身份；与 [matchingAccountIds] 各自独立的顺序来源。
@override@JsonKey() List<String> get matchingAcpAccountIds {
  if (_matchingAcpAccountIds is EqualUnmodifiableListView) return _matchingAcpAccountIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_matchingAcpAccountIds);
}

@override final  String? selectedAccountId;
@override@JsonKey() final  bool showDetails;
@override final  AccountEditorKey? editor;
@override final  String? editorAccountId;
@override@JsonKey() final  int navigationIntent;
@override@JsonKey() final  int latestIntent;
 final  Map<(String, AccountRowAction,), SettingsAction> _rowActions;
@override@JsonKey() Map<(String, AccountRowAction,), SettingsAction> get rowActions {
  if (_rowActions is EqualUnmodifiableMapView) return _rowActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_rowActions);
}

 final  Set<String> _preparingRemovalIds;
@override@JsonKey() Set<String> get preparingRemovalIds {
  if (_preparingRemovalIds is EqualUnmodifiableSetView) return _preparingRemovalIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_preparingRemovalIds);
}

 final  Map<(String, String,), SettingsAction> _modelActions;
@override@JsonKey() Map<(String, String,), SettingsAction> get modelActions {
  if (_modelActions is EqualUnmodifiableMapView) return _modelActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_modelActions);
}

 final  Map<String, SettingsAction> _usageActions;
@override@JsonKey() Map<String, SettingsAction> get usageActions {
  if (_usageActions is EqualUnmodifiableMapView) return _usageActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_usageActions);
}

 final  Map<String, OperationId> _usageActionIds;
@override@JsonKey() Map<String, OperationId> get usageActionIds {
  if (_usageActionIds is EqualUnmodifiableMapView) return _usageActionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_usageActionIds);
}

 final  Map<String, AccountUsageCheckPresentation> _usageChecks;
@override@JsonKey() Map<String, AccountUsageCheckPresentation> get usageChecks {
  if (_usageChecks is EqualUnmodifiableMapView) return _usageChecks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_usageChecks);
}

@override@JsonKey() final  bool refreshingAll;
 final  Map<AccountsReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<AccountsReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<AccountsReadField> _reading;
@override@JsonKey() Set<AccountsReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

@override final  StudioFailure? editorError;
/// Settings canonical 快照里的 ACP 接入集合；null 表示尚未读到事实。
@override final  AcpAccountDirectory? acpAccounts;
/// ACP 接入模板目录；null 表示尚未读取，空目录表示后端未声明模板。
@override final  AcpAccountCatalog? acpCatalog;
/// `acpAuth` 最近一次 canonical 快照；null 表示领域尚未观察。
@override final  AcpAuthSnapshot? acpAuth;
/// Native + ACP 的 typed 目录投影；null 表示素材尚未齐备。
@override final  AccountDirectoryView? directory;
/// 当前选中的 ACP 接入身份（与 Native 选择互斥）。
@override final  String? selectedAcpAccountId;
/// 当前 ACP 编辑目标（新建/编辑）；null 表示没有 ACP 表单。
@override final  AcpAccountEditorTarget? acpEditor;
/// 已保存接入的 canonical 回执明确“需要准备/安装不合格”：编辑表单要给出准备动作。
@override@JsonKey() final  bool acpNeedsPreparation;
/// 按目标接入记账的命令失败通知：只出现在目标行/目标详情。
 final  Map<String, AcpCommandNotice> _acpNotices;
/// 按目标接入记账的命令失败通知：只出现在目标行/目标详情。
@override@JsonKey() Map<String, AcpCommandNotice> get acpNotices {
  if (_acpNotices is EqualUnmodifiableMapView) return _acpNotices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_acpNotices);
}

/// 按目标接入记账的删除受理与结果。
 final  Map<String, SettingsAction> _acpRemovals;
/// 按目标接入记账的删除受理与结果。
@override@JsonKey() Map<String, SettingsAction> get acpRemovals {
  if (_acpRemovals is EqualUnmodifiableMapView) return _acpRemovals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_acpRemovals);
}


/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountsViewStateCopyWith<_AccountsViewState> get copyWith => __$AccountsViewStateCopyWithImpl<_AccountsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountsViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.templateSource, templateSource) || other.templateSource == templateSource)&&(identical(other.usageSource, usageSource) || other.usageSource == usageSource)&&(identical(other.templates, templates) || other.templates == templates)&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.matchingAccountIds, _matchingAccountIds)&&const DeepCollectionEquality().equals(other.matchingAcpAccountIds, _matchingAcpAccountIds)&&(identical(other.selectedAccountId, selectedAccountId) || other.selectedAccountId == selectedAccountId)&&(identical(other.showDetails, showDetails) || other.showDetails == showDetails)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.editorAccountId, editorAccountId) || other.editorAccountId == editorAccountId)&&(identical(other.navigationIntent, navigationIntent) || other.navigationIntent == navigationIntent)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&const DeepCollectionEquality().equals(other.rowActions, _rowActions)&&const DeepCollectionEquality().equals(other.preparingRemovalIds, _preparingRemovalIds)&&const DeepCollectionEquality().equals(other.modelActions, _modelActions)&&const DeepCollectionEquality().equals(other.usageActions, _usageActions)&&const DeepCollectionEquality().equals(other.usageActionIds, _usageActionIds)&&const DeepCollectionEquality().equals(other.usageChecks, _usageChecks)&&(identical(other.refreshingAll, refreshingAll) || other.refreshingAll == refreshingAll)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading)&&(identical(other.editorError, editorError) || other.editorError == editorError)&&(identical(other.acpAccounts, acpAccounts) || other.acpAccounts == acpAccounts)&&(identical(other.acpCatalog, acpCatalog) || other.acpCatalog == acpCatalog)&&(identical(other.acpAuth, acpAuth) || other.acpAuth == acpAuth)&&(identical(other.directory, directory) || other.directory == directory)&&(identical(other.selectedAcpAccountId, selectedAcpAccountId) || other.selectedAcpAccountId == selectedAcpAccountId)&&(identical(other.acpEditor, acpEditor) || other.acpEditor == acpEditor)&&(identical(other.acpNeedsPreparation, acpNeedsPreparation) || other.acpNeedsPreparation == acpNeedsPreparation)&&const DeepCollectionEquality().equals(other.acpNotices, _acpNotices)&&const DeepCollectionEquality().equals(other.acpRemovals, _acpRemovals));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,source,modelSource,templateSource,usageSource,templates,query,const DeepCollectionEquality().hash(_matchingAccountIds),const DeepCollectionEquality().hash(_matchingAcpAccountIds),selectedAccountId,showDetails,editor,editorAccountId,navigationIntent,latestIntent,const DeepCollectionEquality().hash(_rowActions),const DeepCollectionEquality().hash(_preparingRemovalIds),const DeepCollectionEquality().hash(_modelActions),const DeepCollectionEquality().hash(_usageActions),const DeepCollectionEquality().hash(_usageActionIds),const DeepCollectionEquality().hash(_usageChecks),refreshingAll,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading),editorError,acpAccounts,acpCatalog,acpAuth,directory,selectedAcpAccountId,acpEditor,acpNeedsPreparation,const DeepCollectionEquality().hash(_acpNotices),const DeepCollectionEquality().hash(_acpRemovals)]);
}

@override
String toString() {
    return 'AccountsViewState(source: $source, modelSource: $modelSource, templateSource: $templateSource, usageSource: $usageSource, templates: $templates, query: $query, matchingAccountIds: $matchingAccountIds, matchingAcpAccountIds: $matchingAcpAccountIds, selectedAccountId: $selectedAccountId, showDetails: $showDetails, editor: $editor, editorAccountId: $editorAccountId, navigationIntent: $navigationIntent, latestIntent: $latestIntent, rowActions: $rowActions, preparingRemovalIds: $preparingRemovalIds, modelActions: $modelActions, usageActions: $usageActions, usageActionIds: $usageActionIds, usageChecks: $usageChecks, refreshingAll: $refreshingAll, readIssues: $readIssues, reading: $reading, editorError: $editorError, acpAccounts: $acpAccounts, acpCatalog: $acpCatalog, acpAuth: $acpAuth, directory: $directory, selectedAcpAccountId: $selectedAcpAccountId, acpEditor: $acpEditor, acpNeedsPreparation: $acpNeedsPreparation, acpNotices: $acpNotices, acpRemovals: $acpRemovals)';
}


}

/// @nodoc
abstract mixin class _$AccountsViewStateCopyWith<$Res> implements $AccountsViewStateCopyWith<$Res> {
  factory _$AccountsViewStateCopyWith(_AccountsViewState value, $Res Function(_AccountsViewState) _then) = __$AccountsViewStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState source, ModelsState modelSource, TemplatesState templateSource, AccountUsageState usageSource, AccountTemplatesValue? templates, String query, List<String> matchingAccountIds, List<String> matchingAcpAccountIds, String? selectedAccountId, bool showDetails, AccountEditorKey? editor, String? editorAccountId, int navigationIntent, int latestIntent, Map<(String, AccountRowAction,), SettingsAction> rowActions, Set<String> preparingRemovalIds, Map<(String, String,), SettingsAction> modelActions, Map<String, SettingsAction> usageActions, Map<String, OperationId> usageActionIds, Map<String, AccountUsageCheckPresentation> usageChecks, bool refreshingAll, Map<AccountsReadField, StudioFailure> readIssues, Set<AccountsReadField> reading, StudioFailure? editorError, AcpAccountDirectory? acpAccounts, AcpAccountCatalog? acpCatalog, AcpAuthSnapshot? acpAuth, AccountDirectoryView? directory, String? selectedAcpAccountId, AcpAccountEditorTarget? acpEditor, bool acpNeedsPreparation, Map<String, AcpCommandNotice> acpNotices, Map<String, SettingsAction> acpRemovals
});


@override $ConfigurationStateCopyWith<$Res> get source;@override $ModelsStateCopyWith<$Res> get modelSource;@override $TemplatesStateCopyWith<$Res> get templateSource;@override $AccountUsageStateCopyWith<$Res> get usageSource;@override $AccountTemplatesValueCopyWith<$Res>? get templates;@override $AccountEditorKeyCopyWith<$Res>? get editor;@override $StudioFailureCopyWith<$Res>? get editorError;@override $AcpAccountDirectoryCopyWith<$Res>? get acpAccounts;@override $AcpAccountCatalogCopyWith<$Res>? get acpCatalog;@override $AcpAuthSnapshotCopyWith<$Res>? get acpAuth;@override $AccountDirectoryViewCopyWith<$Res>? get directory;

}
/// @nodoc
class __$AccountsViewStateCopyWithImpl<$Res>
    implements _$AccountsViewStateCopyWith<$Res> {
  __$AccountsViewStateCopyWithImpl(this._self, this._then);

  final _AccountsViewState _self;
  final $Res Function(_AccountsViewState) _then;

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? modelSource = null,Object? templateSource = null,Object? usageSource = null,Object? templates = freezed,Object? query = null,Object? matchingAccountIds = null,Object? matchingAcpAccountIds = null,Object? selectedAccountId = freezed,Object? showDetails = null,Object? editor = freezed,Object? editorAccountId = freezed,Object? navigationIntent = null,Object? latestIntent = null,Object? rowActions = null,Object? preparingRemovalIds = null,Object? modelActions = null,Object? usageActions = null,Object? usageActionIds = null,Object? usageChecks = null,Object? refreshingAll = null,Object? readIssues = null,Object? reading = null,Object? editorError = freezed,Object? acpAccounts = freezed,Object? acpCatalog = freezed,Object? acpAuth = freezed,Object? directory = freezed,Object? selectedAcpAccountId = freezed,Object? acpEditor = freezed,Object? acpNeedsPreparation = null,Object? acpNotices = null,Object? acpRemovals = null,}) {
  return _then(_AccountsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,templateSource: null == templateSource ? _self.templateSource : templateSource // ignore: cast_nullable_to_non_nullable
as TemplatesState,usageSource: null == usageSource ? _self.usageSource : usageSource // ignore: cast_nullable_to_non_nullable
as AccountUsageState,templates: freezed == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as AccountTemplatesValue?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,matchingAccountIds: null == matchingAccountIds ? _self._matchingAccountIds : matchingAccountIds // ignore: cast_nullable_to_non_nullable
as List<String>,matchingAcpAccountIds: null == matchingAcpAccountIds ? _self._matchingAcpAccountIds : matchingAcpAccountIds // ignore: cast_nullable_to_non_nullable
as List<String>,selectedAccountId: freezed == selectedAccountId ? _self.selectedAccountId : selectedAccountId // ignore: cast_nullable_to_non_nullable
as String?,showDetails: null == showDetails ? _self.showDetails : showDetails // ignore: cast_nullable_to_non_nullable
as bool,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as AccountEditorKey?,editorAccountId: freezed == editorAccountId ? _self.editorAccountId : editorAccountId // ignore: cast_nullable_to_non_nullable
as String?,navigationIntent: null == navigationIntent ? _self.navigationIntent : navigationIntent // ignore: cast_nullable_to_non_nullable
as int,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,rowActions: null == rowActions ? _self._rowActions : rowActions // ignore: cast_nullable_to_non_nullable
as Map<(String, AccountRowAction,), SettingsAction>,preparingRemovalIds: null == preparingRemovalIds ? _self._preparingRemovalIds : preparingRemovalIds // ignore: cast_nullable_to_non_nullable
as Set<String>,modelActions: null == modelActions ? _self._modelActions : modelActions // ignore: cast_nullable_to_non_nullable
as Map<(String, String,), SettingsAction>,usageActions: null == usageActions ? _self._usageActions : usageActions // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,usageActionIds: null == usageActionIds ? _self._usageActionIds : usageActionIds // ignore: cast_nullable_to_non_nullable
as Map<String, OperationId>,usageChecks: null == usageChecks ? _self._usageChecks : usageChecks // ignore: cast_nullable_to_non_nullable
as Map<String, AccountUsageCheckPresentation>,refreshingAll: null == refreshingAll ? _self.refreshingAll : refreshingAll // ignore: cast_nullable_to_non_nullable
as bool,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<AccountsReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<AccountsReadField>,editorError: freezed == editorError ? _self.editorError : editorError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,acpAccounts: freezed == acpAccounts ? _self.acpAccounts : acpAccounts // ignore: cast_nullable_to_non_nullable
as AcpAccountDirectory?,acpCatalog: freezed == acpCatalog ? _self.acpCatalog : acpCatalog // ignore: cast_nullable_to_non_nullable
as AcpAccountCatalog?,acpAuth: freezed == acpAuth ? _self.acpAuth : acpAuth // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot?,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as AccountDirectoryView?,selectedAcpAccountId: freezed == selectedAcpAccountId ? _self.selectedAcpAccountId : selectedAcpAccountId // ignore: cast_nullable_to_non_nullable
as String?,acpEditor: freezed == acpEditor ? _self.acpEditor : acpEditor // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorTarget?,acpNeedsPreparation: null == acpNeedsPreparation ? _self.acpNeedsPreparation : acpNeedsPreparation // ignore: cast_nullable_to_non_nullable
as bool,acpNotices: null == acpNotices ? _self._acpNotices : acpNotices // ignore: cast_nullable_to_non_nullable
as Map<String, AcpCommandNotice>,acpRemovals: null == acpRemovals ? _self._acpRemovals : acpRemovals // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,
  ));
}

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TemplatesStateCopyWith<$Res> get templateSource {

  return $TemplatesStateCopyWith<$Res>(_self.templateSource, (value) {
    return _then(_self.copyWith(templateSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageStateCopyWith<$Res> get usageSource {

  return $AccountUsageStateCopyWith<$Res>(_self.usageSource, (value) {
    return _then(_self.copyWith(usageSource: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesValueCopyWith<$Res>? get templates {
    if (_self.templates == null) {
    return null;
  }

  return $AccountTemplatesValueCopyWith<$Res>(_self.templates!, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $AccountEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get editorError {
    if (_self.editorError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.editorError!, (value) {
    return _then(_self.copyWith(editorError: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountDirectoryCopyWith<$Res>? get acpAccounts {
    if (_self.acpAccounts == null) {
    return null;
  }

  return $AcpAccountDirectoryCopyWith<$Res>(_self.acpAccounts!, (value) {
    return _then(_self.copyWith(acpAccounts: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountCatalogCopyWith<$Res>? get acpCatalog {
    if (_self.acpCatalog == null) {
    return null;
  }

  return $AcpAccountCatalogCopyWith<$Res>(_self.acpCatalog!, (value) {
    return _then(_self.copyWith(acpCatalog: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res>? get acpAuth {
    if (_self.acpAuth == null) {
    return null;
  }

  return $AcpAuthSnapshotCopyWith<$Res>(_self.acpAuth!, (value) {
    return _then(_self.copyWith(acpAuth: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDirectoryViewCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $AccountDirectoryViewCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}
}

// dart format on
