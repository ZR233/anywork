// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'general_settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WebSearchDraft {

 String get mode; String? get contextSize; String get domains; String get country; String get region; String get city; String get timezone; Set<WebSearchField> get dirtyFields; Map<WebSearchField, int> get fieldRevisions; int get revision;
/// Create a copy of WebSearchDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSearchDraftCopyWith<WebSearchDraft> get copyWith => _$WebSearchDraftCopyWithImpl<WebSearchDraft>(this as WebSearchDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WebSearchDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSearchDraft&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.contextSize, _this.contextSize) || other.contextSize == _this.contextSize)&&(identical(other.domains, _this.domains) || other.domains == _this.domains)&&(identical(other.country, _this.country) || other.country == _this.country)&&(identical(other.region, _this.region) || other.region == _this.region)&&(identical(other.city, _this.city) || other.city == _this.city)&&(identical(other.timezone, _this.timezone) || other.timezone == _this.timezone)&&const DeepCollectionEquality().equals(other.dirtyFields, _this.dirtyFields)&&const DeepCollectionEquality().equals(other.fieldRevisions, _this.fieldRevisions)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as WebSearchDraft;
  return Object.hash(runtimeType,_this.mode,_this.contextSize,_this.domains,_this.country,_this.region,_this.city,_this.timezone,const DeepCollectionEquality().hash(_this.dirtyFields),const DeepCollectionEquality().hash(_this.fieldRevisions),_this.revision);
}



}

/// @nodoc
abstract mixin class $WebSearchDraftCopyWith<$Res>  {
  factory $WebSearchDraftCopyWith(WebSearchDraft value, $Res Function(WebSearchDraft) _then) = _$WebSearchDraftCopyWithImpl;
@useResult
$Res call({
 String mode, String? contextSize, String domains, String country, String region, String city, String timezone, Set<WebSearchField> dirtyFields, Map<WebSearchField, int> fieldRevisions, int revision
});




}
/// @nodoc
class _$WebSearchDraftCopyWithImpl<$Res>
    implements $WebSearchDraftCopyWith<$Res> {
  _$WebSearchDraftCopyWithImpl(this._self, this._then);

  final WebSearchDraft _self;
  final $Res Function(WebSearchDraft) _then;

/// Create a copy of WebSearchDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? contextSize = freezed,Object? domains = null,Object? country = null,Object? region = null,Object? city = null,Object? timezone = null,Object? dirtyFields = null,Object? fieldRevisions = null,Object? revision = null,}) {
  return _then(WebSearchDraft(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,contextSize: freezed == contextSize ? _self.contextSize : contextSize // ignore: cast_nullable_to_non_nullable
as String?,domains: null == domains ? _self.domains : domains // ignore: cast_nullable_to_non_nullable
as String,country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String,region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,timezone: null == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as String,dirtyFields: null == dirtyFields ? _self.dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<WebSearchField>,fieldRevisions: null == fieldRevisions ? _self.fieldRevisions : fieldRevisions // ignore: cast_nullable_to_non_nullable
as Map<WebSearchField, int>,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WebSearchDraft].
extension WebSearchDraftPatterns on WebSearchDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSearchDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSearchDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSearchDraft value)  $default,){
final _that = this;
switch (_that) {
case _WebSearchDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSearchDraft value)?  $default,){
final _that = this;
switch (_that) {
case _WebSearchDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String mode,  String? contextSize,  String domains,  String country,  String region,  String city,  String timezone,  Set<WebSearchField> dirtyFields,  Map<WebSearchField, int> fieldRevisions,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSearchDraft() when $default != null:
return $default(_that.mode,_that.contextSize,_that.domains,_that.country,_that.region,_that.city,_that.timezone,_that.dirtyFields,_that.fieldRevisions,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String mode,  String? contextSize,  String domains,  String country,  String region,  String city,  String timezone,  Set<WebSearchField> dirtyFields,  Map<WebSearchField, int> fieldRevisions,  int revision)  $default,) {final _that = this;
switch (_that) {
case _WebSearchDraft():
return $default(_that.mode,_that.contextSize,_that.domains,_that.country,_that.region,_that.city,_that.timezone,_that.dirtyFields,_that.fieldRevisions,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String mode,  String? contextSize,  String domains,  String country,  String region,  String city,  String timezone,  Set<WebSearchField> dirtyFields,  Map<WebSearchField, int> fieldRevisions,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _WebSearchDraft() when $default != null:
return $default(_that.mode,_that.contextSize,_that.domains,_that.country,_that.region,_that.city,_that.timezone,_that.dirtyFields,_that.fieldRevisions,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _WebSearchDraft implements WebSearchDraft {
  const _WebSearchDraft({required this.mode, required this.contextSize, required this.domains, required this.country, required this.region, required this.city, required this.timezone,  Set<WebSearchField> dirtyFields = const {},  Map<WebSearchField, int> fieldRevisions = const {}, this.revision = 0}): _dirtyFields = dirtyFields,_fieldRevisions = fieldRevisions;


@override final  String mode;
@override final  String? contextSize;
@override final  String domains;
@override final  String country;
@override final  String region;
@override final  String city;
@override final  String timezone;
 final  Set<WebSearchField> _dirtyFields;
@override@JsonKey() Set<WebSearchField> get dirtyFields {
  if (_dirtyFields is EqualUnmodifiableSetView) return _dirtyFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dirtyFields);
}

 final  Map<WebSearchField, int> _fieldRevisions;
@override@JsonKey() Map<WebSearchField, int> get fieldRevisions {
  if (_fieldRevisions is EqualUnmodifiableMapView) return _fieldRevisions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fieldRevisions);
}

@override@JsonKey() final  int revision;

/// Create a copy of WebSearchDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSearchDraftCopyWith<_WebSearchDraft> get copyWith => __$WebSearchDraftCopyWithImpl<_WebSearchDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSearchDraft&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.contextSize, contextSize) || other.contextSize == contextSize)&&(identical(other.domains, domains) || other.domains == domains)&&(identical(other.country, country) || other.country == country)&&(identical(other.region, region) || other.region == region)&&(identical(other.city, city) || other.city == city)&&(identical(other.timezone, timezone) || other.timezone == timezone)&&const DeepCollectionEquality().equals(other.dirtyFields, _dirtyFields)&&const DeepCollectionEquality().equals(other.fieldRevisions, _fieldRevisions)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode,contextSize,domains,country,region,city,timezone,const DeepCollectionEquality().hash(_dirtyFields),const DeepCollectionEquality().hash(_fieldRevisions),revision);
}



}

/// @nodoc
abstract mixin class _$WebSearchDraftCopyWith<$Res> implements $WebSearchDraftCopyWith<$Res> {
  factory _$WebSearchDraftCopyWith(_WebSearchDraft value, $Res Function(_WebSearchDraft) _then) = __$WebSearchDraftCopyWithImpl;
@override @useResult
$Res call({
 String mode, String? contextSize, String domains, String country, String region, String city, String timezone, Set<WebSearchField> dirtyFields, Map<WebSearchField, int> fieldRevisions, int revision
});




}
/// @nodoc
class __$WebSearchDraftCopyWithImpl<$Res>
    implements _$WebSearchDraftCopyWith<$Res> {
  __$WebSearchDraftCopyWithImpl(this._self, this._then);

  final _WebSearchDraft _self;
  final $Res Function(_WebSearchDraft) _then;

/// Create a copy of WebSearchDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? contextSize = freezed,Object? domains = null,Object? country = null,Object? region = null,Object? city = null,Object? timezone = null,Object? dirtyFields = null,Object? fieldRevisions = null,Object? revision = null,}) {
  return _then(_WebSearchDraft(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,contextSize: freezed == contextSize ? _self.contextSize : contextSize // ignore: cast_nullable_to_non_nullable
as String?,domains: null == domains ? _self.domains : domains // ignore: cast_nullable_to_non_nullable
as String,country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String,region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,timezone: null == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as String,dirtyFields: null == dirtyFields ? _self._dirtyFields : dirtyFields // ignore: cast_nullable_to_non_nullable
as Set<WebSearchField>,fieldRevisions: null == fieldRevisions ? _self._fieldRevisions : fieldRevisions // ignore: cast_nullable_to_non_nullable
as Map<WebSearchField, int>,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$GeneralSettingsViewState {

 ConfigurationState get source; ModelsState get modelSource; GeneralSettings? get canonical; DelegationSettings? get delegation; WebSearchConfiguration? get configuredWebSearch; DeepSeekSearchConfiguration? get configuredDeepSeek; WebSearchDraft? get webSearch; EffectiveWebSearch? get effectiveWebSearch; EffectiveDeepSeekSearch? get effectiveDeepSeek; Map<GeneralSettingAction, SettingsAction> get actions; List<SettingsAction> get webSaveActions; Map<WebSearchField, SettingsAction> get webFieldActions; SettingsBatchResult? get webSaveResult; bool get webSaving; int get webSaveIntent; int get latestIntent; List<StudioFailure> get readErrors; Map<GeneralReadField, StudioFailure> get readIssues; bool get readPending; bool get delegationReadPending;
/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GeneralSettingsViewStateCopyWith<GeneralSettingsViewState> get copyWith => _$GeneralSettingsViewStateCopyWithImpl<GeneralSettingsViewState>(this as GeneralSettingsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GeneralSettingsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GeneralSettingsViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.configuredWebSearch, _this.configuredWebSearch) || other.configuredWebSearch == _this.configuredWebSearch)&&(identical(other.configuredDeepSeek, _this.configuredDeepSeek) || other.configuredDeepSeek == _this.configuredDeepSeek)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.effectiveWebSearch, _this.effectiveWebSearch) || other.effectiveWebSearch == _this.effectiveWebSearch)&&(identical(other.effectiveDeepSeek, _this.effectiveDeepSeek) || other.effectiveDeepSeek == _this.effectiveDeepSeek)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&const DeepCollectionEquality().equals(other.webSaveActions, _this.webSaveActions)&&const DeepCollectionEquality().equals(other.webFieldActions, _this.webFieldActions)&&(identical(other.webSaveResult, _this.webSaveResult) || other.webSaveResult == _this.webSaveResult)&&(identical(other.webSaving, _this.webSaving) || other.webSaving == _this.webSaving)&&(identical(other.webSaveIntent, _this.webSaveIntent) || other.webSaveIntent == _this.webSaveIntent)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&const DeepCollectionEquality().equals(other.readErrors, _this.readErrors)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&(identical(other.readPending, _this.readPending) || other.readPending == _this.readPending)&&(identical(other.delegationReadPending, _this.delegationReadPending) || other.delegationReadPending == _this.delegationReadPending));
}


@override
int get hashCode {
  final _this = this as GeneralSettingsViewState;
  return Object.hashAll([runtimeType,_this.source,_this.modelSource,_this.canonical,_this.delegation,_this.configuredWebSearch,_this.configuredDeepSeek,_this.webSearch,_this.effectiveWebSearch,_this.effectiveDeepSeek,const DeepCollectionEquality().hash(_this.actions),const DeepCollectionEquality().hash(_this.webSaveActions),const DeepCollectionEquality().hash(_this.webFieldActions),_this.webSaveResult,_this.webSaving,_this.webSaveIntent,_this.latestIntent,const DeepCollectionEquality().hash(_this.readErrors),const DeepCollectionEquality().hash(_this.readIssues),_this.readPending,_this.delegationReadPending]);
}



}

/// @nodoc
abstract mixin class $GeneralSettingsViewStateCopyWith<$Res>  {
  factory $GeneralSettingsViewStateCopyWith(GeneralSettingsViewState value, $Res Function(GeneralSettingsViewState) _then) = _$GeneralSettingsViewStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState source, ModelsState modelSource, GeneralSettings? canonical, DelegationSettings? delegation, WebSearchConfiguration? configuredWebSearch, DeepSeekSearchConfiguration? configuredDeepSeek, WebSearchDraft? webSearch, EffectiveWebSearch? effectiveWebSearch, EffectiveDeepSeekSearch? effectiveDeepSeek, Map<GeneralSettingAction, SettingsAction> actions, List<SettingsAction> webSaveActions, Map<WebSearchField, SettingsAction> webFieldActions, SettingsBatchResult? webSaveResult, bool webSaving, int webSaveIntent, int latestIntent, List<StudioFailure> readErrors, Map<GeneralReadField, StudioFailure> readIssues, bool readPending, bool delegationReadPending
});


$ConfigurationStateCopyWith<$Res> get source;$ModelsStateCopyWith<$Res> get modelSource;$GeneralSettingsCopyWith<$Res>? get canonical;$DelegationSettingsCopyWith<$Res>? get delegation;$WebSearchConfigurationCopyWith<$Res>? get configuredWebSearch;$DeepSeekSearchConfigurationCopyWith<$Res>? get configuredDeepSeek;$WebSearchDraftCopyWith<$Res>? get webSearch;$EffectiveWebSearchCopyWith<$Res>? get effectiveWebSearch;$EffectiveDeepSeekSearchCopyWith<$Res>? get effectiveDeepSeek;$SettingsBatchResultCopyWith<$Res>? get webSaveResult;

}
/// @nodoc
class _$GeneralSettingsViewStateCopyWithImpl<$Res>
    implements $GeneralSettingsViewStateCopyWith<$Res> {
  _$GeneralSettingsViewStateCopyWithImpl(this._self, this._then);

  final GeneralSettingsViewState _self;
  final $Res Function(GeneralSettingsViewState) _then;

/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? modelSource = null,Object? canonical = freezed,Object? delegation = freezed,Object? configuredWebSearch = freezed,Object? configuredDeepSeek = freezed,Object? webSearch = freezed,Object? effectiveWebSearch = freezed,Object? effectiveDeepSeek = freezed,Object? actions = null,Object? webSaveActions = null,Object? webFieldActions = null,Object? webSaveResult = freezed,Object? webSaving = null,Object? webSaveIntent = null,Object? latestIntent = null,Object? readErrors = null,Object? readIssues = null,Object? readPending = null,Object? delegationReadPending = null,}) {
  return _then(GeneralSettingsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as GeneralSettings?,delegation: freezed == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings?,configuredWebSearch: freezed == configuredWebSearch ? _self.configuredWebSearch : configuredWebSearch // ignore: cast_nullable_to_non_nullable
as WebSearchConfiguration?,configuredDeepSeek: freezed == configuredDeepSeek ? _self.configuredDeepSeek : configuredDeepSeek // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfiguration?,webSearch: freezed == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchDraft?,effectiveWebSearch: freezed == effectiveWebSearch ? _self.effectiveWebSearch : effectiveWebSearch // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearch?,effectiveDeepSeek: freezed == effectiveDeepSeek ? _self.effectiveDeepSeek : effectiveDeepSeek // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearch?,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<GeneralSettingAction, SettingsAction>,webSaveActions: null == webSaveActions ? _self.webSaveActions : webSaveActions // ignore: cast_nullable_to_non_nullable
as List<SettingsAction>,webFieldActions: null == webFieldActions ? _self.webFieldActions : webFieldActions // ignore: cast_nullable_to_non_nullable
as Map<WebSearchField, SettingsAction>,webSaveResult: freezed == webSaveResult ? _self.webSaveResult : webSaveResult // ignore: cast_nullable_to_non_nullable
as SettingsBatchResult?,webSaving: null == webSaving ? _self.webSaving : webSaving // ignore: cast_nullable_to_non_nullable
as bool,webSaveIntent: null == webSaveIntent ? _self.webSaveIntent : webSaveIntent // ignore: cast_nullable_to_non_nullable
as int,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readErrors: null == readErrors ? _self.readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<GeneralReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,delegationReadPending: null == delegationReadPending ? _self.delegationReadPending : delegationReadPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $GeneralSettingsCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res>? get delegation {
    if (_self.delegation == null) {
    return null;
  }

  return $DelegationSettingsCopyWith<$Res>(_self.delegation!, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationCopyWith<$Res>? get configuredWebSearch {
    if (_self.configuredWebSearch == null) {
    return null;
  }

  return $WebSearchConfigurationCopyWith<$Res>(_self.configuredWebSearch!, (value) {
    return _then(_self.copyWith(configuredWebSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationCopyWith<$Res>? get configuredDeepSeek {
    if (_self.configuredDeepSeek == null) {
    return null;
  }

  return $DeepSeekSearchConfigurationCopyWith<$Res>(_self.configuredDeepSeek!, (value) {
    return _then(_self.copyWith(configuredDeepSeek: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchDraftCopyWith<$Res>? get webSearch {
    if (_self.webSearch == null) {
    return null;
  }

  return $WebSearchDraftCopyWith<$Res>(_self.webSearch!, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchCopyWith<$Res>? get effectiveWebSearch {
    if (_self.effectiveWebSearch == null) {
    return null;
  }

  return $EffectiveWebSearchCopyWith<$Res>(_self.effectiveWebSearch!, (value) {
    return _then(_self.copyWith(effectiveWebSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchCopyWith<$Res>? get effectiveDeepSeek {
    if (_self.effectiveDeepSeek == null) {
    return null;
  }

  return $EffectiveDeepSeekSearchCopyWith<$Res>(_self.effectiveDeepSeek!, (value) {
    return _then(_self.copyWith(effectiveDeepSeek: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsBatchResultCopyWith<$Res>? get webSaveResult {
    if (_self.webSaveResult == null) {
    return null;
  }

  return $SettingsBatchResultCopyWith<$Res>(_self.webSaveResult!, (value) {
    return _then(_self.copyWith(webSaveResult: value));
  });
}
}


/// Adds pattern-matching-related methods to [GeneralSettingsViewState].
extension GeneralSettingsViewStatePatterns on GeneralSettingsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GeneralSettingsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GeneralSettingsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GeneralSettingsViewState value)  $default,){
final _that = this;
switch (_that) {
case _GeneralSettingsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GeneralSettingsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _GeneralSettingsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState source,  ModelsState modelSource,  GeneralSettings? canonical,  DelegationSettings? delegation,  WebSearchConfiguration? configuredWebSearch,  DeepSeekSearchConfiguration? configuredDeepSeek,  WebSearchDraft? webSearch,  EffectiveWebSearch? effectiveWebSearch,  EffectiveDeepSeekSearch? effectiveDeepSeek,  Map<GeneralSettingAction, SettingsAction> actions,  List<SettingsAction> webSaveActions,  Map<WebSearchField, SettingsAction> webFieldActions,  SettingsBatchResult? webSaveResult,  bool webSaving,  int webSaveIntent,  int latestIntent,  List<StudioFailure> readErrors,  Map<GeneralReadField, StudioFailure> readIssues,  bool readPending,  bool delegationReadPending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GeneralSettingsViewState() when $default != null:
return $default(_that.source,_that.modelSource,_that.canonical,_that.delegation,_that.configuredWebSearch,_that.configuredDeepSeek,_that.webSearch,_that.effectiveWebSearch,_that.effectiveDeepSeek,_that.actions,_that.webSaveActions,_that.webFieldActions,_that.webSaveResult,_that.webSaving,_that.webSaveIntent,_that.latestIntent,_that.readErrors,_that.readIssues,_that.readPending,_that.delegationReadPending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState source,  ModelsState modelSource,  GeneralSettings? canonical,  DelegationSettings? delegation,  WebSearchConfiguration? configuredWebSearch,  DeepSeekSearchConfiguration? configuredDeepSeek,  WebSearchDraft? webSearch,  EffectiveWebSearch? effectiveWebSearch,  EffectiveDeepSeekSearch? effectiveDeepSeek,  Map<GeneralSettingAction, SettingsAction> actions,  List<SettingsAction> webSaveActions,  Map<WebSearchField, SettingsAction> webFieldActions,  SettingsBatchResult? webSaveResult,  bool webSaving,  int webSaveIntent,  int latestIntent,  List<StudioFailure> readErrors,  Map<GeneralReadField, StudioFailure> readIssues,  bool readPending,  bool delegationReadPending)  $default,) {final _that = this;
switch (_that) {
case _GeneralSettingsViewState():
return $default(_that.source,_that.modelSource,_that.canonical,_that.delegation,_that.configuredWebSearch,_that.configuredDeepSeek,_that.webSearch,_that.effectiveWebSearch,_that.effectiveDeepSeek,_that.actions,_that.webSaveActions,_that.webFieldActions,_that.webSaveResult,_that.webSaving,_that.webSaveIntent,_that.latestIntent,_that.readErrors,_that.readIssues,_that.readPending,_that.delegationReadPending);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState source,  ModelsState modelSource,  GeneralSettings? canonical,  DelegationSettings? delegation,  WebSearchConfiguration? configuredWebSearch,  DeepSeekSearchConfiguration? configuredDeepSeek,  WebSearchDraft? webSearch,  EffectiveWebSearch? effectiveWebSearch,  EffectiveDeepSeekSearch? effectiveDeepSeek,  Map<GeneralSettingAction, SettingsAction> actions,  List<SettingsAction> webSaveActions,  Map<WebSearchField, SettingsAction> webFieldActions,  SettingsBatchResult? webSaveResult,  bool webSaving,  int webSaveIntent,  int latestIntent,  List<StudioFailure> readErrors,  Map<GeneralReadField, StudioFailure> readIssues,  bool readPending,  bool delegationReadPending)?  $default,) {final _that = this;
switch (_that) {
case _GeneralSettingsViewState() when $default != null:
return $default(_that.source,_that.modelSource,_that.canonical,_that.delegation,_that.configuredWebSearch,_that.configuredDeepSeek,_that.webSearch,_that.effectiveWebSearch,_that.effectiveDeepSeek,_that.actions,_that.webSaveActions,_that.webFieldActions,_that.webSaveResult,_that.webSaving,_that.webSaveIntent,_that.latestIntent,_that.readErrors,_that.readIssues,_that.readPending,_that.delegationReadPending);case _:
  return null;

}
}

}

/// @nodoc


class _GeneralSettingsViewState implements GeneralSettingsViewState {
  const _GeneralSettingsViewState({required this.source, required this.modelSource, required this.canonical, required this.delegation, required this.configuredWebSearch, required this.configuredDeepSeek, required this.webSearch, this.effectiveWebSearch, this.effectiveDeepSeek,  Map<GeneralSettingAction, SettingsAction> actions = const {},  List<SettingsAction> webSaveActions = const [],  Map<WebSearchField, SettingsAction> webFieldActions = const {}, this.webSaveResult, this.webSaving = false, this.webSaveIntent = 0, this.latestIntent = 0,  List<StudioFailure> readErrors = const [],  Map<GeneralReadField, StudioFailure> readIssues = const {}, this.readPending = false, this.delegationReadPending = false}): _actions = actions,_webSaveActions = webSaveActions,_webFieldActions = webFieldActions,_readErrors = readErrors,_readIssues = readIssues;


@override final  ConfigurationState source;
@override final  ModelsState modelSource;
@override final  GeneralSettings? canonical;
@override final  DelegationSettings? delegation;
@override final  WebSearchConfiguration? configuredWebSearch;
@override final  DeepSeekSearchConfiguration? configuredDeepSeek;
@override final  WebSearchDraft? webSearch;
@override final  EffectiveWebSearch? effectiveWebSearch;
@override final  EffectiveDeepSeekSearch? effectiveDeepSeek;
 final  Map<GeneralSettingAction, SettingsAction> _actions;
@override@JsonKey() Map<GeneralSettingAction, SettingsAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

 final  List<SettingsAction> _webSaveActions;
@override@JsonKey() List<SettingsAction> get webSaveActions {
  if (_webSaveActions is EqualUnmodifiableListView) return _webSaveActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_webSaveActions);
}

 final  Map<WebSearchField, SettingsAction> _webFieldActions;
@override@JsonKey() Map<WebSearchField, SettingsAction> get webFieldActions {
  if (_webFieldActions is EqualUnmodifiableMapView) return _webFieldActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_webFieldActions);
}

@override final  SettingsBatchResult? webSaveResult;
@override@JsonKey() final  bool webSaving;
@override@JsonKey() final  int webSaveIntent;
@override@JsonKey() final  int latestIntent;
 final  List<StudioFailure> _readErrors;
@override@JsonKey() List<StudioFailure> get readErrors {
  if (_readErrors is EqualUnmodifiableListView) return _readErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_readErrors);
}

 final  Map<GeneralReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<GeneralReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

@override@JsonKey() final  bool readPending;
@override@JsonKey() final  bool delegationReadPending;

/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GeneralSettingsViewStateCopyWith<_GeneralSettingsViewState> get copyWith => __$GeneralSettingsViewStateCopyWithImpl<_GeneralSettingsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GeneralSettingsViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.delegation, delegation) || other.delegation == delegation)&&(identical(other.configuredWebSearch, configuredWebSearch) || other.configuredWebSearch == configuredWebSearch)&&(identical(other.configuredDeepSeek, configuredDeepSeek) || other.configuredDeepSeek == configuredDeepSeek)&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.effectiveWebSearch, effectiveWebSearch) || other.effectiveWebSearch == effectiveWebSearch)&&(identical(other.effectiveDeepSeek, effectiveDeepSeek) || other.effectiveDeepSeek == effectiveDeepSeek)&&const DeepCollectionEquality().equals(other.actions, _actions)&&const DeepCollectionEquality().equals(other.webSaveActions, _webSaveActions)&&const DeepCollectionEquality().equals(other.webFieldActions, _webFieldActions)&&(identical(other.webSaveResult, webSaveResult) || other.webSaveResult == webSaveResult)&&(identical(other.webSaving, webSaving) || other.webSaving == webSaving)&&(identical(other.webSaveIntent, webSaveIntent) || other.webSaveIntent == webSaveIntent)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&const DeepCollectionEquality().equals(other.readErrors, _readErrors)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&(identical(other.readPending, readPending) || other.readPending == readPending)&&(identical(other.delegationReadPending, delegationReadPending) || other.delegationReadPending == delegationReadPending));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,source,modelSource,canonical,delegation,configuredWebSearch,configuredDeepSeek,webSearch,effectiveWebSearch,effectiveDeepSeek,const DeepCollectionEquality().hash(_actions),const DeepCollectionEquality().hash(_webSaveActions),const DeepCollectionEquality().hash(_webFieldActions),webSaveResult,webSaving,webSaveIntent,latestIntent,const DeepCollectionEquality().hash(_readErrors),const DeepCollectionEquality().hash(_readIssues),readPending,delegationReadPending]);
}



}

/// @nodoc
abstract mixin class _$GeneralSettingsViewStateCopyWith<$Res> implements $GeneralSettingsViewStateCopyWith<$Res> {
  factory _$GeneralSettingsViewStateCopyWith(_GeneralSettingsViewState value, $Res Function(_GeneralSettingsViewState) _then) = __$GeneralSettingsViewStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState source, ModelsState modelSource, GeneralSettings? canonical, DelegationSettings? delegation, WebSearchConfiguration? configuredWebSearch, DeepSeekSearchConfiguration? configuredDeepSeek, WebSearchDraft? webSearch, EffectiveWebSearch? effectiveWebSearch, EffectiveDeepSeekSearch? effectiveDeepSeek, Map<GeneralSettingAction, SettingsAction> actions, List<SettingsAction> webSaveActions, Map<WebSearchField, SettingsAction> webFieldActions, SettingsBatchResult? webSaveResult, bool webSaving, int webSaveIntent, int latestIntent, List<StudioFailure> readErrors, Map<GeneralReadField, StudioFailure> readIssues, bool readPending, bool delegationReadPending
});


@override $ConfigurationStateCopyWith<$Res> get source;@override $ModelsStateCopyWith<$Res> get modelSource;@override $GeneralSettingsCopyWith<$Res>? get canonical;@override $DelegationSettingsCopyWith<$Res>? get delegation;@override $WebSearchConfigurationCopyWith<$Res>? get configuredWebSearch;@override $DeepSeekSearchConfigurationCopyWith<$Res>? get configuredDeepSeek;@override $WebSearchDraftCopyWith<$Res>? get webSearch;@override $EffectiveWebSearchCopyWith<$Res>? get effectiveWebSearch;@override $EffectiveDeepSeekSearchCopyWith<$Res>? get effectiveDeepSeek;@override $SettingsBatchResultCopyWith<$Res>? get webSaveResult;

}
/// @nodoc
class __$GeneralSettingsViewStateCopyWithImpl<$Res>
    implements _$GeneralSettingsViewStateCopyWith<$Res> {
  __$GeneralSettingsViewStateCopyWithImpl(this._self, this._then);

  final _GeneralSettingsViewState _self;
  final $Res Function(_GeneralSettingsViewState) _then;

/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? modelSource = null,Object? canonical = freezed,Object? delegation = freezed,Object? configuredWebSearch = freezed,Object? configuredDeepSeek = freezed,Object? webSearch = freezed,Object? effectiveWebSearch = freezed,Object? effectiveDeepSeek = freezed,Object? actions = null,Object? webSaveActions = null,Object? webFieldActions = null,Object? webSaveResult = freezed,Object? webSaving = null,Object? webSaveIntent = null,Object? latestIntent = null,Object? readErrors = null,Object? readIssues = null,Object? readPending = null,Object? delegationReadPending = null,}) {
  return _then(_GeneralSettingsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as GeneralSettings?,delegation: freezed == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettings?,configuredWebSearch: freezed == configuredWebSearch ? _self.configuredWebSearch : configuredWebSearch // ignore: cast_nullable_to_non_nullable
as WebSearchConfiguration?,configuredDeepSeek: freezed == configuredDeepSeek ? _self.configuredDeepSeek : configuredDeepSeek // ignore: cast_nullable_to_non_nullable
as DeepSeekSearchConfiguration?,webSearch: freezed == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchDraft?,effectiveWebSearch: freezed == effectiveWebSearch ? _self.effectiveWebSearch : effectiveWebSearch // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearch?,effectiveDeepSeek: freezed == effectiveDeepSeek ? _self.effectiveDeepSeek : effectiveDeepSeek // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearch?,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<GeneralSettingAction, SettingsAction>,webSaveActions: null == webSaveActions ? _self._webSaveActions : webSaveActions // ignore: cast_nullable_to_non_nullable
as List<SettingsAction>,webFieldActions: null == webFieldActions ? _self._webFieldActions : webFieldActions // ignore: cast_nullable_to_non_nullable
as Map<WebSearchField, SettingsAction>,webSaveResult: freezed == webSaveResult ? _self.webSaveResult : webSaveResult // ignore: cast_nullable_to_non_nullable
as SettingsBatchResult?,webSaving: null == webSaving ? _self.webSaving : webSaving // ignore: cast_nullable_to_non_nullable
as bool,webSaveIntent: null == webSaveIntent ? _self.webSaveIntent : webSaveIntent // ignore: cast_nullable_to_non_nullable
as int,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readErrors: null == readErrors ? _self._readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<GeneralReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,delegationReadPending: null == delegationReadPending ? _self.delegationReadPending : delegationReadPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeneralSettingsCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $GeneralSettingsCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res>? get delegation {
    if (_self.delegation == null) {
    return null;
  }

  return $DelegationSettingsCopyWith<$Res>(_self.delegation!, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchConfigurationCopyWith<$Res>? get configuredWebSearch {
    if (_self.configuredWebSearch == null) {
    return null;
  }

  return $WebSearchConfigurationCopyWith<$Res>(_self.configuredWebSearch!, (value) {
    return _then(_self.copyWith(configuredWebSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeepSeekSearchConfigurationCopyWith<$Res>? get configuredDeepSeek {
    if (_self.configuredDeepSeek == null) {
    return null;
  }

  return $DeepSeekSearchConfigurationCopyWith<$Res>(_self.configuredDeepSeek!, (value) {
    return _then(_self.copyWith(configuredDeepSeek: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchDraftCopyWith<$Res>? get webSearch {
    if (_self.webSearch == null) {
    return null;
  }

  return $WebSearchDraftCopyWith<$Res>(_self.webSearch!, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchCopyWith<$Res>? get effectiveWebSearch {
    if (_self.effectiveWebSearch == null) {
    return null;
  }

  return $EffectiveWebSearchCopyWith<$Res>(_self.effectiveWebSearch!, (value) {
    return _then(_self.copyWith(effectiveWebSearch: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchCopyWith<$Res>? get effectiveDeepSeek {
    if (_self.effectiveDeepSeek == null) {
    return null;
  }

  return $EffectiveDeepSeekSearchCopyWith<$Res>(_self.effectiveDeepSeek!, (value) {
    return _then(_self.copyWith(effectiveDeepSeek: value));
  });
}/// Create a copy of GeneralSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsBatchResultCopyWith<$Res>? get webSaveResult {
    if (_self.webSaveResult == null) {
    return null;
  }

  return $SettingsBatchResultCopyWith<$Res>(_self.webSaveResult!, (value) {
    return _then(_self.copyWith(webSaveResult: value));
  });
}
}

// dart format on
