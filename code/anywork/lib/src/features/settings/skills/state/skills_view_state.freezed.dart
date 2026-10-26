// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SkillsPreferencesState {

 ConfigurationState get source; String get queryRaw; Map<SkillsPreferencesReadField, StudioFailure> get readIssues; Set<SkillsPreferencesReadField> get reading; SettingsAction? get disabledAction;
/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsPreferencesStateCopyWith<SkillsPreferencesState> get copyWith => _$SkillsPreferencesStateCopyWithImpl<SkillsPreferencesState>(this as SkillsPreferencesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsPreferencesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsPreferencesState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.queryRaw, _this.queryRaw) || other.queryRaw == _this.queryRaw)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&(identical(other.disabledAction, _this.disabledAction) || other.disabledAction == _this.disabledAction));
}


@override
int get hashCode {
  final _this = this as SkillsPreferencesState;
  return Object.hash(runtimeType,_this.source,_this.queryRaw,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading),_this.disabledAction);
}



}

/// @nodoc
abstract mixin class $SkillsPreferencesStateCopyWith<$Res>  {
  factory $SkillsPreferencesStateCopyWith(SkillsPreferencesState value, $Res Function(SkillsPreferencesState) _then) = _$SkillsPreferencesStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState source, String queryRaw, Map<SkillsPreferencesReadField, StudioFailure> readIssues, Set<SkillsPreferencesReadField> reading, SettingsAction? disabledAction
});


$ConfigurationStateCopyWith<$Res> get source;$SettingsActionCopyWith<$Res>? get disabledAction;

}
/// @nodoc
class _$SkillsPreferencesStateCopyWithImpl<$Res>
    implements $SkillsPreferencesStateCopyWith<$Res> {
  _$SkillsPreferencesStateCopyWithImpl(this._self, this._then);

  final SkillsPreferencesState _self;
  final $Res Function(SkillsPreferencesState) _then;

/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? queryRaw = null,Object? readIssues = null,Object? reading = null,Object? disabledAction = freezed,}) {
  return _then(SkillsPreferencesState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,queryRaw: null == queryRaw ? _self.queryRaw : queryRaw // ignore: cast_nullable_to_non_nullable
as String,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<SkillsPreferencesReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SkillsPreferencesReadField>,disabledAction: freezed == disabledAction ? _self.disabledAction : disabledAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get disabledAction {
    if (_self.disabledAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.disabledAction!, (value) {
    return _then(_self.copyWith(disabledAction: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsPreferencesState].
extension SkillsPreferencesStatePatterns on SkillsPreferencesState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsPreferencesState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsPreferencesState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsPreferencesState value)  $default,){
final _that = this;
switch (_that) {
case _SkillsPreferencesState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsPreferencesState value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsPreferencesState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState source,  String queryRaw,  Map<SkillsPreferencesReadField, StudioFailure> readIssues,  Set<SkillsPreferencesReadField> reading,  SettingsAction? disabledAction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsPreferencesState() when $default != null:
return $default(_that.source,_that.queryRaw,_that.readIssues,_that.reading,_that.disabledAction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState source,  String queryRaw,  Map<SkillsPreferencesReadField, StudioFailure> readIssues,  Set<SkillsPreferencesReadField> reading,  SettingsAction? disabledAction)  $default,) {final _that = this;
switch (_that) {
case _SkillsPreferencesState():
return $default(_that.source,_that.queryRaw,_that.readIssues,_that.reading,_that.disabledAction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState source,  String queryRaw,  Map<SkillsPreferencesReadField, StudioFailure> readIssues,  Set<SkillsPreferencesReadField> reading,  SettingsAction? disabledAction)?  $default,) {final _that = this;
switch (_that) {
case _SkillsPreferencesState() when $default != null:
return $default(_that.source,_that.queryRaw,_that.readIssues,_that.reading,_that.disabledAction);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsPreferencesState implements SkillsPreferencesState {
  const _SkillsPreferencesState({required this.source, this.queryRaw = '',  Map<SkillsPreferencesReadField, StudioFailure> readIssues = const {},  Set<SkillsPreferencesReadField> reading = const {}, this.disabledAction}): _readIssues = readIssues,_reading = reading;


@override final  ConfigurationState source;
@override@JsonKey() final  String queryRaw;
 final  Map<SkillsPreferencesReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<SkillsPreferencesReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<SkillsPreferencesReadField> _reading;
@override@JsonKey() Set<SkillsPreferencesReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

@override final  SettingsAction? disabledAction;

/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsPreferencesStateCopyWith<_SkillsPreferencesState> get copyWith => __$SkillsPreferencesStateCopyWithImpl<_SkillsPreferencesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsPreferencesState&&(identical(other.source, source) || other.source == source)&&(identical(other.queryRaw, queryRaw) || other.queryRaw == queryRaw)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading)&&(identical(other.disabledAction, disabledAction) || other.disabledAction == disabledAction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,queryRaw,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading),disabledAction);
}



}

/// @nodoc
abstract mixin class _$SkillsPreferencesStateCopyWith<$Res> implements $SkillsPreferencesStateCopyWith<$Res> {
  factory _$SkillsPreferencesStateCopyWith(_SkillsPreferencesState value, $Res Function(_SkillsPreferencesState) _then) = __$SkillsPreferencesStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState source, String queryRaw, Map<SkillsPreferencesReadField, StudioFailure> readIssues, Set<SkillsPreferencesReadField> reading, SettingsAction? disabledAction
});


@override $ConfigurationStateCopyWith<$Res> get source;@override $SettingsActionCopyWith<$Res>? get disabledAction;

}
/// @nodoc
class __$SkillsPreferencesStateCopyWithImpl<$Res>
    implements _$SkillsPreferencesStateCopyWith<$Res> {
  __$SkillsPreferencesStateCopyWithImpl(this._self, this._then);

  final _SkillsPreferencesState _self;
  final $Res Function(_SkillsPreferencesState) _then;

/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? queryRaw = null,Object? readIssues = null,Object? reading = null,Object? disabledAction = freezed,}) {
  return _then(_SkillsPreferencesState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,queryRaw: null == queryRaw ? _self.queryRaw : queryRaw // ignore: cast_nullable_to_non_nullable
as String,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<SkillsPreferencesReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SkillsPreferencesReadField>,disabledAction: freezed == disabledAction ? _self.disabledAction : disabledAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsPreferencesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get disabledAction {
    if (_self.disabledAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.disabledAction!, (value) {
    return _then(_self.copyWith(disabledAction: value));
  });
}
}

/// @nodoc
mixin _$ActiveSkillNames {

 String get threadId; ThreadFacetStamp get origin; ThreadConfigurationReadRef get reference; List<String> get names;
/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveSkillNamesCopyWith<ActiveSkillNames> get copyWith => _$ActiveSkillNamesCopyWithImpl<ActiveSkillNames>(this as ActiveSkillNames, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActiveSkillNames;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveSkillNames&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&const DeepCollectionEquality().equals(other.names, _this.names));
}


@override
int get hashCode {
  final _this = this as ActiveSkillNames;
  return Object.hash(runtimeType,_this.threadId,_this.origin,_this.reference,const DeepCollectionEquality().hash(_this.names));
}



}

/// @nodoc
abstract mixin class $ActiveSkillNamesCopyWith<$Res>  {
  factory $ActiveSkillNamesCopyWith(ActiveSkillNames value, $Res Function(ActiveSkillNames) _then) = _$ActiveSkillNamesCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadFacetStamp origin, ThreadConfigurationReadRef reference, List<String> names
});


$ThreadFacetStampCopyWith<$Res> get origin;$ThreadConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ActiveSkillNamesCopyWithImpl<$Res>
    implements $ActiveSkillNamesCopyWith<$Res> {
  _$ActiveSkillNamesCopyWithImpl(this._self, this._then);

  final ActiveSkillNames _self;
  final $Res Function(ActiveSkillNames) _then;

/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? origin = null,Object? reference = null,Object? names = null,}) {
  return _then(ActiveSkillNames(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationReadRef,names: null == names ? _self.names : names // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}
/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get origin {

  return $ThreadFacetStampCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationReadRefCopyWith<$Res> get reference {

  return $ThreadConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActiveSkillNames].
extension ActiveSkillNamesPatterns on ActiveSkillNames {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveSkillNames value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveSkillNames() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveSkillNames value)  $default,){
final _that = this;
switch (_that) {
case _ActiveSkillNames():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveSkillNames value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveSkillNames() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp origin,  ThreadConfigurationReadRef reference,  List<String> names)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveSkillNames() when $default != null:
return $default(_that.threadId,_that.origin,_that.reference,_that.names);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp origin,  ThreadConfigurationReadRef reference,  List<String> names)  $default,) {final _that = this;
switch (_that) {
case _ActiveSkillNames():
return $default(_that.threadId,_that.origin,_that.reference,_that.names);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadFacetStamp origin,  ThreadConfigurationReadRef reference,  List<String> names)?  $default,) {final _that = this;
switch (_that) {
case _ActiveSkillNames() when $default != null:
return $default(_that.threadId,_that.origin,_that.reference,_that.names);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveSkillNames implements ActiveSkillNames {
  const _ActiveSkillNames({required this.threadId, required this.origin, required this.reference, required  List<String> names}): _names = names;


@override final  String threadId;
@override final  ThreadFacetStamp origin;
@override final  ThreadConfigurationReadRef reference;
 final  List<String> _names;
@override List<String> get names {
  if (_names is EqualUnmodifiableListView) return _names;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_names);
}


/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveSkillNamesCopyWith<_ActiveSkillNames> get copyWith => __$ActiveSkillNamesCopyWithImpl<_ActiveSkillNames>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveSkillNames&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference)&&const DeepCollectionEquality().equals(other.names, _names));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,origin,reference,const DeepCollectionEquality().hash(_names));
}



}

/// @nodoc
abstract mixin class _$ActiveSkillNamesCopyWith<$Res> implements $ActiveSkillNamesCopyWith<$Res> {
  factory _$ActiveSkillNamesCopyWith(_ActiveSkillNames value, $Res Function(_ActiveSkillNames) _then) = __$ActiveSkillNamesCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadFacetStamp origin, ThreadConfigurationReadRef reference, List<String> names
});


@override $ThreadFacetStampCopyWith<$Res> get origin;@override $ThreadConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ActiveSkillNamesCopyWithImpl<$Res>
    implements _$ActiveSkillNamesCopyWith<$Res> {
  __$ActiveSkillNamesCopyWithImpl(this._self, this._then);

  final _ActiveSkillNames _self;
  final $Res Function(_ActiveSkillNames) _then;

/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? origin = null,Object? reference = null,Object? names = null,}) {
  return _then(_ActiveSkillNames(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationReadRef,names: null == names ? _self._names : names // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get origin {

  return $ThreadFacetStampCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ActiveSkillNames
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationReadRefCopyWith<$Res> get reference {

  return $ThreadConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$SkillsViewState {

 String get projectId; SkillsState get source; String get searchQuery; int get searchGeneration; SkillSearchResult? get search; bool get searching; StudioFailure? get searchError; ActiveSkillNames? get activeNames; Map<SkillsReadField, StudioFailure> get readIssues; Set<SkillsReadField> get reading; List<CloseReport> get cleanupReports; List<StudioFailure> get cleanupErrors; SettingsAction? get discoverAction;
/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsViewStateCopyWith<SkillsViewState> get copyWith => _$SkillsViewStateCopyWithImpl<SkillsViewState>(this as SkillsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsViewState&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.searchQuery, _this.searchQuery) || other.searchQuery == _this.searchQuery)&&(identical(other.searchGeneration, _this.searchGeneration) || other.searchGeneration == _this.searchGeneration)&&(identical(other.search, _this.search) || other.search == _this.search)&&(identical(other.searching, _this.searching) || other.searching == _this.searching)&&(identical(other.searchError, _this.searchError) || other.searchError == _this.searchError)&&(identical(other.activeNames, _this.activeNames) || other.activeNames == _this.activeNames)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&const DeepCollectionEquality().equals(other.cleanupReports, _this.cleanupReports)&&const DeepCollectionEquality().equals(other.cleanupErrors, _this.cleanupErrors)&&(identical(other.discoverAction, _this.discoverAction) || other.discoverAction == _this.discoverAction));
}


@override
int get hashCode {
  final _this = this as SkillsViewState;
  return Object.hash(runtimeType,_this.projectId,_this.source,_this.searchQuery,_this.searchGeneration,_this.search,_this.searching,_this.searchError,_this.activeNames,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading),const DeepCollectionEquality().hash(_this.cleanupReports),const DeepCollectionEquality().hash(_this.cleanupErrors),_this.discoverAction);
}



}

/// @nodoc
abstract mixin class $SkillsViewStateCopyWith<$Res>  {
  factory $SkillsViewStateCopyWith(SkillsViewState value, $Res Function(SkillsViewState) _then) = _$SkillsViewStateCopyWithImpl;
@useResult
$Res call({
 String projectId, SkillsState source, String searchQuery, int searchGeneration, SkillSearchResult? search, bool searching, StudioFailure? searchError, ActiveSkillNames? activeNames, Map<SkillsReadField, StudioFailure> readIssues, Set<SkillsReadField> reading, List<CloseReport> cleanupReports, List<StudioFailure> cleanupErrors, SettingsAction? discoverAction
});


$SkillsStateCopyWith<$Res> get source;$SkillSearchResultCopyWith<$Res>? get search;$StudioFailureCopyWith<$Res>? get searchError;$ActiveSkillNamesCopyWith<$Res>? get activeNames;$SettingsActionCopyWith<$Res>? get discoverAction;

}
/// @nodoc
class _$SkillsViewStateCopyWithImpl<$Res>
    implements $SkillsViewStateCopyWith<$Res> {
  _$SkillsViewStateCopyWithImpl(this._self, this._then);

  final SkillsViewState _self;
  final $Res Function(SkillsViewState) _then;

/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? source = null,Object? searchQuery = null,Object? searchGeneration = null,Object? search = freezed,Object? searching = null,Object? searchError = freezed,Object? activeNames = freezed,Object? readIssues = null,Object? reading = null,Object? cleanupReports = null,Object? cleanupErrors = null,Object? discoverAction = freezed,}) {
  return _then(SkillsViewState(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SkillsState,searchQuery: null == searchQuery ? _self.searchQuery : searchQuery // ignore: cast_nullable_to_non_nullable
as String,searchGeneration: null == searchGeneration ? _self.searchGeneration : searchGeneration // ignore: cast_nullable_to_non_nullable
as int,search: freezed == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as SkillSearchResult?,searching: null == searching ? _self.searching : searching // ignore: cast_nullable_to_non_nullable
as bool,searchError: freezed == searchError ? _self.searchError : searchError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,activeNames: freezed == activeNames ? _self.activeNames : activeNames // ignore: cast_nullable_to_non_nullable
as ActiveSkillNames?,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<SkillsReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SkillsReadField>,cleanupReports: null == cleanupReports ? _self.cleanupReports : cleanupReports // ignore: cast_nullable_to_non_nullable
as List<CloseReport>,cleanupErrors: null == cleanupErrors ? _self.cleanupErrors : cleanupErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,discoverAction: freezed == discoverAction ? _self.discoverAction : discoverAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsStateCopyWith<$Res> get source {

  return $SkillsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillSearchResultCopyWith<$Res>? get search {
    if (_self.search == null) {
    return null;
  }

  return $SkillSearchResultCopyWith<$Res>(_self.search!, (value) {
    return _then(_self.copyWith(search: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get searchError {
    if (_self.searchError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.searchError!, (value) {
    return _then(_self.copyWith(searchError: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveSkillNamesCopyWith<$Res>? get activeNames {
    if (_self.activeNames == null) {
    return null;
  }

  return $ActiveSkillNamesCopyWith<$Res>(_self.activeNames!, (value) {
    return _then(_self.copyWith(activeNames: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get discoverAction {
    if (_self.discoverAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.discoverAction!, (value) {
    return _then(_self.copyWith(discoverAction: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsViewState].
extension SkillsViewStatePatterns on SkillsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsViewState value)  $default,){
final _that = this;
switch (_that) {
case _SkillsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  SkillsState source,  String searchQuery,  int searchGeneration,  SkillSearchResult? search,  bool searching,  StudioFailure? searchError,  ActiveSkillNames? activeNames,  Map<SkillsReadField, StudioFailure> readIssues,  Set<SkillsReadField> reading,  List<CloseReport> cleanupReports,  List<StudioFailure> cleanupErrors,  SettingsAction? discoverAction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsViewState() when $default != null:
return $default(_that.projectId,_that.source,_that.searchQuery,_that.searchGeneration,_that.search,_that.searching,_that.searchError,_that.activeNames,_that.readIssues,_that.reading,_that.cleanupReports,_that.cleanupErrors,_that.discoverAction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  SkillsState source,  String searchQuery,  int searchGeneration,  SkillSearchResult? search,  bool searching,  StudioFailure? searchError,  ActiveSkillNames? activeNames,  Map<SkillsReadField, StudioFailure> readIssues,  Set<SkillsReadField> reading,  List<CloseReport> cleanupReports,  List<StudioFailure> cleanupErrors,  SettingsAction? discoverAction)  $default,) {final _that = this;
switch (_that) {
case _SkillsViewState():
return $default(_that.projectId,_that.source,_that.searchQuery,_that.searchGeneration,_that.search,_that.searching,_that.searchError,_that.activeNames,_that.readIssues,_that.reading,_that.cleanupReports,_that.cleanupErrors,_that.discoverAction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  SkillsState source,  String searchQuery,  int searchGeneration,  SkillSearchResult? search,  bool searching,  StudioFailure? searchError,  ActiveSkillNames? activeNames,  Map<SkillsReadField, StudioFailure> readIssues,  Set<SkillsReadField> reading,  List<CloseReport> cleanupReports,  List<StudioFailure> cleanupErrors,  SettingsAction? discoverAction)?  $default,) {final _that = this;
switch (_that) {
case _SkillsViewState() when $default != null:
return $default(_that.projectId,_that.source,_that.searchQuery,_that.searchGeneration,_that.search,_that.searching,_that.searchError,_that.activeNames,_that.readIssues,_that.reading,_that.cleanupReports,_that.cleanupErrors,_that.discoverAction);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsViewState implements SkillsViewState {
  const _SkillsViewState({required this.projectId, required this.source, this.searchQuery = '', this.searchGeneration = 0, this.search, this.searching = false, this.searchError, this.activeNames,  Map<SkillsReadField, StudioFailure> readIssues = const {},  Set<SkillsReadField> reading = const {},  List<CloseReport> cleanupReports = const [],  List<StudioFailure> cleanupErrors = const [], this.discoverAction}): _readIssues = readIssues,_reading = reading,_cleanupReports = cleanupReports,_cleanupErrors = cleanupErrors;


@override final  String projectId;
@override final  SkillsState source;
@override@JsonKey() final  String searchQuery;
@override@JsonKey() final  int searchGeneration;
@override final  SkillSearchResult? search;
@override@JsonKey() final  bool searching;
@override final  StudioFailure? searchError;
@override final  ActiveSkillNames? activeNames;
 final  Map<SkillsReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<SkillsReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<SkillsReadField> _reading;
@override@JsonKey() Set<SkillsReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

 final  List<CloseReport> _cleanupReports;
@override@JsonKey() List<CloseReport> get cleanupReports {
  if (_cleanupReports is EqualUnmodifiableListView) return _cleanupReports;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_cleanupReports);
}

 final  List<StudioFailure> _cleanupErrors;
@override@JsonKey() List<StudioFailure> get cleanupErrors {
  if (_cleanupErrors is EqualUnmodifiableListView) return _cleanupErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_cleanupErrors);
}

@override final  SettingsAction? discoverAction;

/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsViewStateCopyWith<_SkillsViewState> get copyWith => __$SkillsViewStateCopyWithImpl<_SkillsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsViewState&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.source, source) || other.source == source)&&(identical(other.searchQuery, searchQuery) || other.searchQuery == searchQuery)&&(identical(other.searchGeneration, searchGeneration) || other.searchGeneration == searchGeneration)&&(identical(other.search, search) || other.search == search)&&(identical(other.searching, searching) || other.searching == searching)&&(identical(other.searchError, searchError) || other.searchError == searchError)&&(identical(other.activeNames, activeNames) || other.activeNames == activeNames)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading)&&const DeepCollectionEquality().equals(other.cleanupReports, _cleanupReports)&&const DeepCollectionEquality().equals(other.cleanupErrors, _cleanupErrors)&&(identical(other.discoverAction, discoverAction) || other.discoverAction == discoverAction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,source,searchQuery,searchGeneration,search,searching,searchError,activeNames,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading),const DeepCollectionEquality().hash(_cleanupReports),const DeepCollectionEquality().hash(_cleanupErrors),discoverAction);
}



}

/// @nodoc
abstract mixin class _$SkillsViewStateCopyWith<$Res> implements $SkillsViewStateCopyWith<$Res> {
  factory _$SkillsViewStateCopyWith(_SkillsViewState value, $Res Function(_SkillsViewState) _then) = __$SkillsViewStateCopyWithImpl;
@override @useResult
$Res call({
 String projectId, SkillsState source, String searchQuery, int searchGeneration, SkillSearchResult? search, bool searching, StudioFailure? searchError, ActiveSkillNames? activeNames, Map<SkillsReadField, StudioFailure> readIssues, Set<SkillsReadField> reading, List<CloseReport> cleanupReports, List<StudioFailure> cleanupErrors, SettingsAction? discoverAction
});


@override $SkillsStateCopyWith<$Res> get source;@override $SkillSearchResultCopyWith<$Res>? get search;@override $StudioFailureCopyWith<$Res>? get searchError;@override $ActiveSkillNamesCopyWith<$Res>? get activeNames;@override $SettingsActionCopyWith<$Res>? get discoverAction;

}
/// @nodoc
class __$SkillsViewStateCopyWithImpl<$Res>
    implements _$SkillsViewStateCopyWith<$Res> {
  __$SkillsViewStateCopyWithImpl(this._self, this._then);

  final _SkillsViewState _self;
  final $Res Function(_SkillsViewState) _then;

/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? source = null,Object? searchQuery = null,Object? searchGeneration = null,Object? search = freezed,Object? searching = null,Object? searchError = freezed,Object? activeNames = freezed,Object? readIssues = null,Object? reading = null,Object? cleanupReports = null,Object? cleanupErrors = null,Object? discoverAction = freezed,}) {
  return _then(_SkillsViewState(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SkillsState,searchQuery: null == searchQuery ? _self.searchQuery : searchQuery // ignore: cast_nullable_to_non_nullable
as String,searchGeneration: null == searchGeneration ? _self.searchGeneration : searchGeneration // ignore: cast_nullable_to_non_nullable
as int,search: freezed == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as SkillSearchResult?,searching: null == searching ? _self.searching : searching // ignore: cast_nullable_to_non_nullable
as bool,searchError: freezed == searchError ? _self.searchError : searchError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,activeNames: freezed == activeNames ? _self.activeNames : activeNames // ignore: cast_nullable_to_non_nullable
as ActiveSkillNames?,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<SkillsReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SkillsReadField>,cleanupReports: null == cleanupReports ? _self._cleanupReports : cleanupReports // ignore: cast_nullable_to_non_nullable
as List<CloseReport>,cleanupErrors: null == cleanupErrors ? _self._cleanupErrors : cleanupErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,discoverAction: freezed == discoverAction ? _self.discoverAction : discoverAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsStateCopyWith<$Res> get source {

  return $SkillsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillSearchResultCopyWith<$Res>? get search {
    if (_self.search == null) {
    return null;
  }

  return $SkillSearchResultCopyWith<$Res>(_self.search!, (value) {
    return _then(_self.copyWith(search: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get searchError {
    if (_self.searchError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.searchError!, (value) {
    return _then(_self.copyWith(searchError: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveSkillNamesCopyWith<$Res>? get activeNames {
    if (_self.activeNames == null) {
    return null;
  }

  return $ActiveSkillNamesCopyWith<$Res>(_self.activeNames!, (value) {
    return _then(_self.copyWith(activeNames: value));
  });
}/// Create a copy of SkillsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get discoverAction {
    if (_self.discoverAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.discoverAction!, (value) {
    return _then(_self.copyWith(discoverAction: value));
  });
}
}

/// @nodoc
mixin _$SettingsSkillRow {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsSkillRow);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SettingsSkillRowCopyWith<$Res>  {
$SettingsSkillRowCopyWith(SettingsSkillRow _, $Res Function(SettingsSkillRow) __);
}


/// Adds pattern-matching-related methods to [SettingsSkillRow].
extension SettingsSkillRowPatterns on SettingsSkillRow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CatalogSettingsSkillRow value)?  catalog,TResult Function( NameOnlySettingsSkillRow value)?  nameOnly,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CatalogSettingsSkillRow() when catalog != null:
return catalog(_that);case NameOnlySettingsSkillRow() when nameOnly != null:
return nameOnly(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CatalogSettingsSkillRow value)  catalog,required TResult Function( NameOnlySettingsSkillRow value)  nameOnly,}){
final _that = this;
switch (_that) {
case CatalogSettingsSkillRow():
return catalog(_that);case NameOnlySettingsSkillRow():
return nameOnly(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CatalogSettingsSkillRow value)?  catalog,TResult? Function( NameOnlySettingsSkillRow value)?  nameOnly,}){
final _that = this;
switch (_that) {
case CatalogSettingsSkillRow() when catalog != null:
return catalog(_that);case NameOnlySettingsSkillRow() when nameOnly != null:
return nameOnly(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SkillSummary summary)?  catalog,TResult Function( String value)?  nameOnly,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CatalogSettingsSkillRow() when catalog != null:
return catalog(_that.summary);case NameOnlySettingsSkillRow() when nameOnly != null:
return nameOnly(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SkillSummary summary)  catalog,required TResult Function( String value)  nameOnly,}) {final _that = this;
switch (_that) {
case CatalogSettingsSkillRow():
return catalog(_that.summary);case NameOnlySettingsSkillRow():
return nameOnly(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SkillSummary summary)?  catalog,TResult? Function( String value)?  nameOnly,}) {final _that = this;
switch (_that) {
case CatalogSettingsSkillRow() when catalog != null:
return catalog(_that.summary);case NameOnlySettingsSkillRow() when nameOnly != null:
return nameOnly(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class CatalogSettingsSkillRow extends SettingsSkillRow {
  const CatalogSettingsSkillRow({required this.summary}): super._();


 final  SkillSummary summary;

/// Create a copy of SettingsSkillRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogSettingsSkillRowCopyWith<CatalogSettingsSkillRow> get copyWith => _$CatalogSettingsSkillRowCopyWithImpl<CatalogSettingsSkillRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogSettingsSkillRow&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summary);
}



}

/// @nodoc
abstract mixin class $CatalogSettingsSkillRowCopyWith<$Res> implements $SettingsSkillRowCopyWith<$Res> {
  factory $CatalogSettingsSkillRowCopyWith(CatalogSettingsSkillRow value, $Res Function(CatalogSettingsSkillRow) _then) = _$CatalogSettingsSkillRowCopyWithImpl;
@useResult
$Res call({
 SkillSummary summary
});


$SkillSummaryCopyWith<$Res> get summary;

}
/// @nodoc
class _$CatalogSettingsSkillRowCopyWithImpl<$Res>
    implements $CatalogSettingsSkillRowCopyWith<$Res> {
  _$CatalogSettingsSkillRowCopyWithImpl(this._self, this._then);

  final CatalogSettingsSkillRow _self;
  final $Res Function(CatalogSettingsSkillRow) _then;

/// Create a copy of SettingsSkillRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? summary = null,}) {
  return _then(CatalogSettingsSkillRow(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as SkillSummary,
  ));
}

/// Create a copy of SettingsSkillRow
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillSummaryCopyWith<$Res> get summary {

  return $SkillSummaryCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}
}

/// @nodoc


class NameOnlySettingsSkillRow extends SettingsSkillRow {
  const NameOnlySettingsSkillRow({required this.value}): super._();


 final  String value;

/// Create a copy of SettingsSkillRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NameOnlySettingsSkillRowCopyWith<NameOnlySettingsSkillRow> get copyWith => _$NameOnlySettingsSkillRowCopyWithImpl<NameOnlySettingsSkillRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NameOnlySettingsSkillRow&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $NameOnlySettingsSkillRowCopyWith<$Res> implements $SettingsSkillRowCopyWith<$Res> {
  factory $NameOnlySettingsSkillRowCopyWith(NameOnlySettingsSkillRow value, $Res Function(NameOnlySettingsSkillRow) _then) = _$NameOnlySettingsSkillRowCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$NameOnlySettingsSkillRowCopyWithImpl<$Res>
    implements $NameOnlySettingsSkillRowCopyWith<$Res> {
  _$NameOnlySettingsSkillRowCopyWithImpl(this._self, this._then);

  final NameOnlySettingsSkillRow _self;
  final $Res Function(NameOnlySettingsSkillRow) _then;

/// Create a copy of SettingsSkillRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(NameOnlySettingsSkillRow(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
