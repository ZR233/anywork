// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_directory_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RemoteDirectoryViewState {

 String get alias; String get pathRaw; bool get showProjectNameField; String get nameRaw; bool get nameEdited; bool get nameRequired; RemoteDirectoryState? get directory; int get generation; bool get browsing; bool get opening; bool get closing; bool get verified; RemotePathIssue? get pathIssue; StudioFailure? get error; StudioFailure? get observationError; List<CloseReport> get cleanupReports; WorkspaceOpenResult? get openResult; bool get openUncertain; String? get completedPath;
/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryViewStateCopyWith<RemoteDirectoryViewState> get copyWith => _$RemoteDirectoryViewStateCopyWithImpl<RemoteDirectoryViewState>(this as RemoteDirectoryViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryViewState&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.pathRaw, _this.pathRaw) || other.pathRaw == _this.pathRaw)&&(identical(other.showProjectNameField, _this.showProjectNameField) || other.showProjectNameField == _this.showProjectNameField)&&(identical(other.nameRaw, _this.nameRaw) || other.nameRaw == _this.nameRaw)&&(identical(other.nameEdited, _this.nameEdited) || other.nameEdited == _this.nameEdited)&&(identical(other.nameRequired, _this.nameRequired) || other.nameRequired == _this.nameRequired)&&(identical(other.directory, _this.directory) || other.directory == _this.directory)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.browsing, _this.browsing) || other.browsing == _this.browsing)&&(identical(other.opening, _this.opening) || other.opening == _this.opening)&&(identical(other.closing, _this.closing) || other.closing == _this.closing)&&(identical(other.verified, _this.verified) || other.verified == _this.verified)&&(identical(other.pathIssue, _this.pathIssue) || other.pathIssue == _this.pathIssue)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError)&&const DeepCollectionEquality().equals(other.cleanupReports, _this.cleanupReports)&&(identical(other.openResult, _this.openResult) || other.openResult == _this.openResult)&&(identical(other.openUncertain, _this.openUncertain) || other.openUncertain == _this.openUncertain)&&(identical(other.completedPath, _this.completedPath) || other.completedPath == _this.completedPath));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryViewState;
  return Object.hashAll([runtimeType,_this.alias,_this.pathRaw,_this.showProjectNameField,_this.nameRaw,_this.nameEdited,_this.nameRequired,_this.directory,_this.generation,_this.browsing,_this.opening,_this.closing,_this.verified,_this.pathIssue,_this.error,_this.observationError,const DeepCollectionEquality().hash(_this.cleanupReports),_this.openResult,_this.openUncertain,_this.completedPath]);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryViewStateCopyWith<$Res>  {
  factory $RemoteDirectoryViewStateCopyWith(RemoteDirectoryViewState value, $Res Function(RemoteDirectoryViewState) _then) = _$RemoteDirectoryViewStateCopyWithImpl;
@useResult
$Res call({
 String alias, String pathRaw, bool showProjectNameField, String nameRaw, bool nameEdited, bool nameRequired, RemoteDirectoryState? directory, int generation, bool browsing, bool opening, bool closing, bool verified, RemotePathIssue? pathIssue, StudioFailure? error, StudioFailure? observationError, List<CloseReport> cleanupReports, WorkspaceOpenResult? openResult, bool openUncertain, String? completedPath
});


$RemoteDirectoryStateCopyWith<$Res>? get directory;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get observationError;$WorkspaceOpenResultCopyWith<$Res>? get openResult;

}
/// @nodoc
class _$RemoteDirectoryViewStateCopyWithImpl<$Res>
    implements $RemoteDirectoryViewStateCopyWith<$Res> {
  _$RemoteDirectoryViewStateCopyWithImpl(this._self, this._then);

  final RemoteDirectoryViewState _self;
  final $Res Function(RemoteDirectoryViewState) _then;

/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? pathRaw = null,Object? showProjectNameField = null,Object? nameRaw = null,Object? nameEdited = null,Object? nameRequired = null,Object? directory = freezed,Object? generation = null,Object? browsing = null,Object? opening = null,Object? closing = null,Object? verified = null,Object? pathIssue = freezed,Object? error = freezed,Object? observationError = freezed,Object? cleanupReports = null,Object? openResult = freezed,Object? openUncertain = null,Object? completedPath = freezed,}) {
  return _then(RemoteDirectoryViewState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,pathRaw: null == pathRaw ? _self.pathRaw : pathRaw // ignore: cast_nullable_to_non_nullable
as String,showProjectNameField: null == showProjectNameField ? _self.showProjectNameField : showProjectNameField // ignore: cast_nullable_to_non_nullable
as bool,nameRaw: null == nameRaw ? _self.nameRaw : nameRaw // ignore: cast_nullable_to_non_nullable
as String,nameEdited: null == nameEdited ? _self.nameEdited : nameEdited // ignore: cast_nullable_to_non_nullable
as bool,nameRequired: null == nameRequired ? _self.nameRequired : nameRequired // ignore: cast_nullable_to_non_nullable
as bool,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as RemoteDirectoryState?,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,browsing: null == browsing ? _self.browsing : browsing // ignore: cast_nullable_to_non_nullable
as bool,opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,pathIssue: freezed == pathIssue ? _self.pathIssue : pathIssue // ignore: cast_nullable_to_non_nullable
as RemotePathIssue?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,cleanupReports: null == cleanupReports ? _self.cleanupReports : cleanupReports // ignore: cast_nullable_to_non_nullable
as List<CloseReport>,openResult: freezed == openResult ? _self.openResult : openResult // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,openUncertain: null == openUncertain ? _self.openUncertain : openUncertain // ignore: cast_nullable_to_non_nullable
as bool,completedPath: freezed == completedPath ? _self.completedPath : completedPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteDirectoryStateCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $RemoteDirectoryStateCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}/// Create a copy of RemoteDirectoryViewState
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
}/// Create a copy of RemoteDirectoryViewState
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
}/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get openResult {
    if (_self.openResult == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.openResult!, (value) {
    return _then(_self.copyWith(openResult: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoteDirectoryViewState].
extension RemoteDirectoryViewStatePatterns on RemoteDirectoryViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryViewState value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryViewState value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  String pathRaw,  bool showProjectNameField,  String nameRaw,  bool nameEdited,  bool nameRequired,  RemoteDirectoryState? directory,  int generation,  bool browsing,  bool opening,  bool closing,  bool verified,  RemotePathIssue? pathIssue,  StudioFailure? error,  StudioFailure? observationError,  List<CloseReport> cleanupReports,  WorkspaceOpenResult? openResult,  bool openUncertain,  String? completedPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryViewState() when $default != null:
return $default(_that.alias,_that.pathRaw,_that.showProjectNameField,_that.nameRaw,_that.nameEdited,_that.nameRequired,_that.directory,_that.generation,_that.browsing,_that.opening,_that.closing,_that.verified,_that.pathIssue,_that.error,_that.observationError,_that.cleanupReports,_that.openResult,_that.openUncertain,_that.completedPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  String pathRaw,  bool showProjectNameField,  String nameRaw,  bool nameEdited,  bool nameRequired,  RemoteDirectoryState? directory,  int generation,  bool browsing,  bool opening,  bool closing,  bool verified,  RemotePathIssue? pathIssue,  StudioFailure? error,  StudioFailure? observationError,  List<CloseReport> cleanupReports,  WorkspaceOpenResult? openResult,  bool openUncertain,  String? completedPath)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryViewState():
return $default(_that.alias,_that.pathRaw,_that.showProjectNameField,_that.nameRaw,_that.nameEdited,_that.nameRequired,_that.directory,_that.generation,_that.browsing,_that.opening,_that.closing,_that.verified,_that.pathIssue,_that.error,_that.observationError,_that.cleanupReports,_that.openResult,_that.openUncertain,_that.completedPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  String pathRaw,  bool showProjectNameField,  String nameRaw,  bool nameEdited,  bool nameRequired,  RemoteDirectoryState? directory,  int generation,  bool browsing,  bool opening,  bool closing,  bool verified,  RemotePathIssue? pathIssue,  StudioFailure? error,  StudioFailure? observationError,  List<CloseReport> cleanupReports,  WorkspaceOpenResult? openResult,  bool openUncertain,  String? completedPath)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryViewState() when $default != null:
return $default(_that.alias,_that.pathRaw,_that.showProjectNameField,_that.nameRaw,_that.nameEdited,_that.nameRequired,_that.directory,_that.generation,_that.browsing,_that.opening,_that.closing,_that.verified,_that.pathIssue,_that.error,_that.observationError,_that.cleanupReports,_that.openResult,_that.openUncertain,_that.completedPath);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryViewState extends RemoteDirectoryViewState {
  const _RemoteDirectoryViewState({required this.alias, this.pathRaw = '', this.showProjectNameField = false, this.nameRaw = '', this.nameEdited = false, this.nameRequired = false, this.directory, this.generation = 0, this.browsing = false, this.opening = false, this.closing = false, this.verified = false, this.pathIssue, this.error, this.observationError,  List<CloseReport> cleanupReports = const [], this.openResult, this.openUncertain = false, this.completedPath}): _cleanupReports = cleanupReports,super._();


@override final  String alias;
@override@JsonKey() final  String pathRaw;
@override@JsonKey() final  bool showProjectNameField;
@override@JsonKey() final  String nameRaw;
@override@JsonKey() final  bool nameEdited;
@override@JsonKey() final  bool nameRequired;
@override final  RemoteDirectoryState? directory;
@override@JsonKey() final  int generation;
@override@JsonKey() final  bool browsing;
@override@JsonKey() final  bool opening;
@override@JsonKey() final  bool closing;
@override@JsonKey() final  bool verified;
@override final  RemotePathIssue? pathIssue;
@override final  StudioFailure? error;
@override final  StudioFailure? observationError;
 final  List<CloseReport> _cleanupReports;
@override@JsonKey() List<CloseReport> get cleanupReports {
  if (_cleanupReports is EqualUnmodifiableListView) return _cleanupReports;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_cleanupReports);
}

@override final  WorkspaceOpenResult? openResult;
@override@JsonKey() final  bool openUncertain;
@override final  String? completedPath;

/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryViewStateCopyWith<_RemoteDirectoryViewState> get copyWith => __$RemoteDirectoryViewStateCopyWithImpl<_RemoteDirectoryViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryViewState&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.pathRaw, pathRaw) || other.pathRaw == pathRaw)&&(identical(other.showProjectNameField, showProjectNameField) || other.showProjectNameField == showProjectNameField)&&(identical(other.nameRaw, nameRaw) || other.nameRaw == nameRaw)&&(identical(other.nameEdited, nameEdited) || other.nameEdited == nameEdited)&&(identical(other.nameRequired, nameRequired) || other.nameRequired == nameRequired)&&(identical(other.directory, directory) || other.directory == directory)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.browsing, browsing) || other.browsing == browsing)&&(identical(other.opening, opening) || other.opening == opening)&&(identical(other.closing, closing) || other.closing == closing)&&(identical(other.verified, verified) || other.verified == verified)&&(identical(other.pathIssue, pathIssue) || other.pathIssue == pathIssue)&&(identical(other.error, error) || other.error == error)&&(identical(other.observationError, observationError) || other.observationError == observationError)&&const DeepCollectionEquality().equals(other.cleanupReports, _cleanupReports)&&(identical(other.openResult, openResult) || other.openResult == openResult)&&(identical(other.openUncertain, openUncertain) || other.openUncertain == openUncertain)&&(identical(other.completedPath, completedPath) || other.completedPath == completedPath));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,alias,pathRaw,showProjectNameField,nameRaw,nameEdited,nameRequired,directory,generation,browsing,opening,closing,verified,pathIssue,error,observationError,const DeepCollectionEquality().hash(_cleanupReports),openResult,openUncertain,completedPath]);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryViewStateCopyWith<$Res> implements $RemoteDirectoryViewStateCopyWith<$Res> {
  factory _$RemoteDirectoryViewStateCopyWith(_RemoteDirectoryViewState value, $Res Function(_RemoteDirectoryViewState) _then) = __$RemoteDirectoryViewStateCopyWithImpl;
@override @useResult
$Res call({
 String alias, String pathRaw, bool showProjectNameField, String nameRaw, bool nameEdited, bool nameRequired, RemoteDirectoryState? directory, int generation, bool browsing, bool opening, bool closing, bool verified, RemotePathIssue? pathIssue, StudioFailure? error, StudioFailure? observationError, List<CloseReport> cleanupReports, WorkspaceOpenResult? openResult, bool openUncertain, String? completedPath
});


@override $RemoteDirectoryStateCopyWith<$Res>? get directory;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get observationError;@override $WorkspaceOpenResultCopyWith<$Res>? get openResult;

}
/// @nodoc
class __$RemoteDirectoryViewStateCopyWithImpl<$Res>
    implements _$RemoteDirectoryViewStateCopyWith<$Res> {
  __$RemoteDirectoryViewStateCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryViewState _self;
  final $Res Function(_RemoteDirectoryViewState) _then;

/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? pathRaw = null,Object? showProjectNameField = null,Object? nameRaw = null,Object? nameEdited = null,Object? nameRequired = null,Object? directory = freezed,Object? generation = null,Object? browsing = null,Object? opening = null,Object? closing = null,Object? verified = null,Object? pathIssue = freezed,Object? error = freezed,Object? observationError = freezed,Object? cleanupReports = null,Object? openResult = freezed,Object? openUncertain = null,Object? completedPath = freezed,}) {
  return _then(_RemoteDirectoryViewState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,pathRaw: null == pathRaw ? _self.pathRaw : pathRaw // ignore: cast_nullable_to_non_nullable
as String,showProjectNameField: null == showProjectNameField ? _self.showProjectNameField : showProjectNameField // ignore: cast_nullable_to_non_nullable
as bool,nameRaw: null == nameRaw ? _self.nameRaw : nameRaw // ignore: cast_nullable_to_non_nullable
as String,nameEdited: null == nameEdited ? _self.nameEdited : nameEdited // ignore: cast_nullable_to_non_nullable
as bool,nameRequired: null == nameRequired ? _self.nameRequired : nameRequired // ignore: cast_nullable_to_non_nullable
as bool,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as RemoteDirectoryState?,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,browsing: null == browsing ? _self.browsing : browsing // ignore: cast_nullable_to_non_nullable
as bool,opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,pathIssue: freezed == pathIssue ? _self.pathIssue : pathIssue // ignore: cast_nullable_to_non_nullable
as RemotePathIssue?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,cleanupReports: null == cleanupReports ? _self._cleanupReports : cleanupReports // ignore: cast_nullable_to_non_nullable
as List<CloseReport>,openResult: freezed == openResult ? _self.openResult : openResult // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,openUncertain: null == openUncertain ? _self.openUncertain : openUncertain // ignore: cast_nullable_to_non_nullable
as bool,completedPath: freezed == completedPath ? _self.completedPath : completedPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteDirectoryStateCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $RemoteDirectoryStateCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}/// Create a copy of RemoteDirectoryViewState
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
}/// Create a copy of RemoteDirectoryViewState
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
}/// Create a copy of RemoteDirectoryViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get openResult {
    if (_self.openResult == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.openResult!, (value) {
    return _then(_self.copyWith(openResult: value));
  });
}
}

// dart format on
