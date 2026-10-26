// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshEditorViewState {

 SshEditorKey get target; SshServerRuntimeEntry? get canonical; String get alias; String get host; String get port; String get username; String get identityFile; String get password; SshSecretIntent get passwordIntent; bool get passwordVisible; bool get dirty; int get draftRevision; Map<SshEditorField, SshValidation> get validation; SettingsAction? get saveAction;
/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshEditorViewStateCopyWith<SshEditorViewState> get copyWith => _$SshEditorViewStateCopyWithImpl<SshEditorViewState>(this as SshEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshEditorViewState&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.host, _this.host) || other.host == _this.host)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.username, _this.username) || other.username == _this.username)&&(identical(other.identityFile, _this.identityFile) || other.identityFile == _this.identityFile)&&(identical(other.password, _this.password) || other.password == _this.password)&&(identical(other.passwordIntent, _this.passwordIntent) || other.passwordIntent == _this.passwordIntent)&&(identical(other.passwordVisible, _this.passwordVisible) || other.passwordVisible == _this.passwordVisible)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&const DeepCollectionEquality().equals(other.validation, _this.validation)&&(identical(other.saveAction, _this.saveAction) || other.saveAction == _this.saveAction));
}


@override
int get hashCode {
  final _this = this as SshEditorViewState;
  return Object.hash(runtimeType,_this.target,_this.canonical,_this.alias,_this.host,_this.port,_this.username,_this.identityFile,_this.password,_this.passwordIntent,_this.passwordVisible,_this.dirty,_this.draftRevision,const DeepCollectionEquality().hash(_this.validation),_this.saveAction);
}



}

/// @nodoc
abstract mixin class $SshEditorViewStateCopyWith<$Res>  {
  factory $SshEditorViewStateCopyWith(SshEditorViewState value, $Res Function(SshEditorViewState) _then) = _$SshEditorViewStateCopyWithImpl;
@useResult
$Res call({
 SshEditorKey target, SshServerRuntimeEntry? canonical, String alias, String host, String port, String username, String identityFile, String password, SshSecretIntent passwordIntent, bool passwordVisible, bool dirty, int draftRevision, Map<SshEditorField, SshValidation> validation, SettingsAction? saveAction
});


$SshEditorKeyCopyWith<$Res> get target;$SshServerRuntimeEntryCopyWith<$Res>? get canonical;$SettingsActionCopyWith<$Res>? get saveAction;

}
/// @nodoc
class _$SshEditorViewStateCopyWithImpl<$Res>
    implements $SshEditorViewStateCopyWith<$Res> {
  _$SshEditorViewStateCopyWithImpl(this._self, this._then);

  final SshEditorViewState _self;
  final $Res Function(SshEditorViewState) _then;

/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? canonical = freezed,Object? alias = null,Object? host = null,Object? port = null,Object? username = null,Object? identityFile = null,Object? password = null,Object? passwordIntent = null,Object? passwordVisible = null,Object? dirty = null,Object? draftRevision = null,Object? validation = null,Object? saveAction = freezed,}) {
  return _then(SshEditorViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as SshEditorKey,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as SshServerRuntimeEntry?,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,identityFile: null == identityFile ? _self.identityFile : identityFile // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,passwordIntent: null == passwordIntent ? _self.passwordIntent : passwordIntent // ignore: cast_nullable_to_non_nullable
as SshSecretIntent,passwordVisible: null == passwordVisible ? _self.passwordVisible : passwordVisible // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,validation: null == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as Map<SshEditorField, SshValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshEditorKeyCopyWith<$Res> get target {

  return $SshEditorKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerRuntimeEntryCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $SshServerRuntimeEntryCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of SshEditorViewState
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
}
}


/// Adds pattern-matching-related methods to [SshEditorViewState].
extension SshEditorViewStatePatterns on SshEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _SshEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _SshEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SshEditorKey target,  SshServerRuntimeEntry? canonical,  String alias,  String host,  String port,  String username,  String identityFile,  String password,  SshSecretIntent passwordIntent,  bool passwordVisible,  bool dirty,  int draftRevision,  Map<SshEditorField, SshValidation> validation,  SettingsAction? saveAction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshEditorViewState() when $default != null:
return $default(_that.target,_that.canonical,_that.alias,_that.host,_that.port,_that.username,_that.identityFile,_that.password,_that.passwordIntent,_that.passwordVisible,_that.dirty,_that.draftRevision,_that.validation,_that.saveAction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SshEditorKey target,  SshServerRuntimeEntry? canonical,  String alias,  String host,  String port,  String username,  String identityFile,  String password,  SshSecretIntent passwordIntent,  bool passwordVisible,  bool dirty,  int draftRevision,  Map<SshEditorField, SshValidation> validation,  SettingsAction? saveAction)  $default,) {final _that = this;
switch (_that) {
case _SshEditorViewState():
return $default(_that.target,_that.canonical,_that.alias,_that.host,_that.port,_that.username,_that.identityFile,_that.password,_that.passwordIntent,_that.passwordVisible,_that.dirty,_that.draftRevision,_that.validation,_that.saveAction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SshEditorKey target,  SshServerRuntimeEntry? canonical,  String alias,  String host,  String port,  String username,  String identityFile,  String password,  SshSecretIntent passwordIntent,  bool passwordVisible,  bool dirty,  int draftRevision,  Map<SshEditorField, SshValidation> validation,  SettingsAction? saveAction)?  $default,) {final _that = this;
switch (_that) {
case _SshEditorViewState() when $default != null:
return $default(_that.target,_that.canonical,_that.alias,_that.host,_that.port,_that.username,_that.identityFile,_that.password,_that.passwordIntent,_that.passwordVisible,_that.dirty,_that.draftRevision,_that.validation,_that.saveAction);case _:
  return null;

}
}

}

/// @nodoc


class _SshEditorViewState extends SshEditorViewState {
  const _SshEditorViewState({required this.target, this.canonical, this.alias = '', this.host = '', this.port = '22', this.username = '', this.identityFile = '', this.password = '', this.passwordIntent = SshSecretIntent.preserve, this.passwordVisible = false, this.dirty = false, this.draftRevision = 0,  Map<SshEditorField, SshValidation> validation = const {}, this.saveAction}): _validation = validation,super._();


@override final  SshEditorKey target;
@override final  SshServerRuntimeEntry? canonical;
@override@JsonKey() final  String alias;
@override@JsonKey() final  String host;
@override@JsonKey() final  String port;
@override@JsonKey() final  String username;
@override@JsonKey() final  String identityFile;
@override@JsonKey() final  String password;
@override@JsonKey() final  SshSecretIntent passwordIntent;
@override@JsonKey() final  bool passwordVisible;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  int draftRevision;
 final  Map<SshEditorField, SshValidation> _validation;
@override@JsonKey() Map<SshEditorField, SshValidation> get validation {
  if (_validation is EqualUnmodifiableMapView) return _validation;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_validation);
}

@override final  SettingsAction? saveAction;

/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshEditorViewStateCopyWith<_SshEditorViewState> get copyWith => __$SshEditorViewStateCopyWithImpl<_SshEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshEditorViewState&&(identical(other.target, target) || other.target == target)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.username, username) || other.username == username)&&(identical(other.identityFile, identityFile) || other.identityFile == identityFile)&&(identical(other.password, password) || other.password == password)&&(identical(other.passwordIntent, passwordIntent) || other.passwordIntent == passwordIntent)&&(identical(other.passwordVisible, passwordVisible) || other.passwordVisible == passwordVisible)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.draftRevision, draftRevision) || other.draftRevision == draftRevision)&&const DeepCollectionEquality().equals(other.validation, _validation)&&(identical(other.saveAction, saveAction) || other.saveAction == saveAction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,canonical,alias,host,port,username,identityFile,password,passwordIntent,passwordVisible,dirty,draftRevision,const DeepCollectionEquality().hash(_validation),saveAction);
}



}

/// @nodoc
abstract mixin class _$SshEditorViewStateCopyWith<$Res> implements $SshEditorViewStateCopyWith<$Res> {
  factory _$SshEditorViewStateCopyWith(_SshEditorViewState value, $Res Function(_SshEditorViewState) _then) = __$SshEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 SshEditorKey target, SshServerRuntimeEntry? canonical, String alias, String host, String port, String username, String identityFile, String password, SshSecretIntent passwordIntent, bool passwordVisible, bool dirty, int draftRevision, Map<SshEditorField, SshValidation> validation, SettingsAction? saveAction
});


@override $SshEditorKeyCopyWith<$Res> get target;@override $SshServerRuntimeEntryCopyWith<$Res>? get canonical;@override $SettingsActionCopyWith<$Res>? get saveAction;

}
/// @nodoc
class __$SshEditorViewStateCopyWithImpl<$Res>
    implements _$SshEditorViewStateCopyWith<$Res> {
  __$SshEditorViewStateCopyWithImpl(this._self, this._then);

  final _SshEditorViewState _self;
  final $Res Function(_SshEditorViewState) _then;

/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? canonical = freezed,Object? alias = null,Object? host = null,Object? port = null,Object? username = null,Object? identityFile = null,Object? password = null,Object? passwordIntent = null,Object? passwordVisible = null,Object? dirty = null,Object? draftRevision = null,Object? validation = null,Object? saveAction = freezed,}) {
  return _then(_SshEditorViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as SshEditorKey,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as SshServerRuntimeEntry?,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,identityFile: null == identityFile ? _self.identityFile : identityFile // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,passwordIntent: null == passwordIntent ? _self.passwordIntent : passwordIntent // ignore: cast_nullable_to_non_nullable
as SshSecretIntent,passwordVisible: null == passwordVisible ? _self.passwordVisible : passwordVisible // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,validation: null == validation ? _self._validation : validation // ignore: cast_nullable_to_non_nullable
as Map<SshEditorField, SshValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshEditorKeyCopyWith<$Res> get target {

  return $SshEditorKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of SshEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerRuntimeEntryCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $SshServerRuntimeEntryCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of SshEditorViewState
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
}
}

/// @nodoc
mixin _$SshPasswordViewState {

 String get alias; String get password; bool get rememberPassword; bool get passwordVisible; bool get requiredError; SshConnectionSnapshot? get connection; SettingsAction? get action;
/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshPasswordViewStateCopyWith<SshPasswordViewState> get copyWith => _$SshPasswordViewStateCopyWithImpl<SshPasswordViewState>(this as SshPasswordViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshPasswordViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordViewState&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.password, _this.password) || other.password == _this.password)&&(identical(other.rememberPassword, _this.rememberPassword) || other.rememberPassword == _this.rememberPassword)&&(identical(other.passwordVisible, _this.passwordVisible) || other.passwordVisible == _this.passwordVisible)&&(identical(other.requiredError, _this.requiredError) || other.requiredError == _this.requiredError)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as SshPasswordViewState;
  return Object.hash(runtimeType,_this.alias,_this.password,_this.rememberPassword,_this.passwordVisible,_this.requiredError,_this.connection,_this.action);
}



}

/// @nodoc
abstract mixin class $SshPasswordViewStateCopyWith<$Res>  {
  factory $SshPasswordViewStateCopyWith(SshPasswordViewState value, $Res Function(SshPasswordViewState) _then) = _$SshPasswordViewStateCopyWithImpl;
@useResult
$Res call({
 String alias, String password, bool rememberPassword, bool passwordVisible, bool requiredError, SshConnectionSnapshot? connection, SettingsAction? action
});


$SshConnectionSnapshotCopyWith<$Res>? get connection;$SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class _$SshPasswordViewStateCopyWithImpl<$Res>
    implements $SshPasswordViewStateCopyWith<$Res> {
  _$SshPasswordViewStateCopyWithImpl(this._self, this._then);

  final SshPasswordViewState _self;
  final $Res Function(SshPasswordViewState) _then;

/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? password = null,Object? rememberPassword = null,Object? passwordVisible = null,Object? requiredError = null,Object? connection = freezed,Object? action = freezed,}) {
  return _then(SshPasswordViewState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,rememberPassword: null == rememberPassword ? _self.rememberPassword : rememberPassword // ignore: cast_nullable_to_non_nullable
as bool,passwordVisible: null == passwordVisible ? _self.passwordVisible : passwordVisible // ignore: cast_nullable_to_non_nullable
as bool,requiredError: null == requiredError ? _self.requiredError : requiredError // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as SshConnectionSnapshot?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionSnapshotCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $SshConnectionSnapshotCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshPasswordViewState].
extension SshPasswordViewStatePatterns on SshPasswordViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshPasswordViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshPasswordViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshPasswordViewState value)  $default,){
final _that = this;
switch (_that) {
case _SshPasswordViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshPasswordViewState value)?  $default,){
final _that = this;
switch (_that) {
case _SshPasswordViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  String password,  bool rememberPassword,  bool passwordVisible,  bool requiredError,  SshConnectionSnapshot? connection,  SettingsAction? action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshPasswordViewState() when $default != null:
return $default(_that.alias,_that.password,_that.rememberPassword,_that.passwordVisible,_that.requiredError,_that.connection,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  String password,  bool rememberPassword,  bool passwordVisible,  bool requiredError,  SshConnectionSnapshot? connection,  SettingsAction? action)  $default,) {final _that = this;
switch (_that) {
case _SshPasswordViewState():
return $default(_that.alias,_that.password,_that.rememberPassword,_that.passwordVisible,_that.requiredError,_that.connection,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  String password,  bool rememberPassword,  bool passwordVisible,  bool requiredError,  SshConnectionSnapshot? connection,  SettingsAction? action)?  $default,) {final _that = this;
switch (_that) {
case _SshPasswordViewState() when $default != null:
return $default(_that.alias,_that.password,_that.rememberPassword,_that.passwordVisible,_that.requiredError,_that.connection,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _SshPasswordViewState implements SshPasswordViewState {
  const _SshPasswordViewState({required this.alias, this.password = '', this.rememberPassword = true, this.passwordVisible = false, this.requiredError = false, this.connection, this.action});


@override final  String alias;
@override@JsonKey() final  String password;
@override@JsonKey() final  bool rememberPassword;
@override@JsonKey() final  bool passwordVisible;
@override@JsonKey() final  bool requiredError;
@override final  SshConnectionSnapshot? connection;
@override final  SettingsAction? action;

/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshPasswordViewStateCopyWith<_SshPasswordViewState> get copyWith => __$SshPasswordViewStateCopyWithImpl<_SshPasswordViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshPasswordViewState&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.password, password) || other.password == password)&&(identical(other.rememberPassword, rememberPassword) || other.rememberPassword == rememberPassword)&&(identical(other.passwordVisible, passwordVisible) || other.passwordVisible == passwordVisible)&&(identical(other.requiredError, requiredError) || other.requiredError == requiredError)&&(identical(other.connection, connection) || other.connection == connection)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,alias,password,rememberPassword,passwordVisible,requiredError,connection,action);
}



}

/// @nodoc
abstract mixin class _$SshPasswordViewStateCopyWith<$Res> implements $SshPasswordViewStateCopyWith<$Res> {
  factory _$SshPasswordViewStateCopyWith(_SshPasswordViewState value, $Res Function(_SshPasswordViewState) _then) = __$SshPasswordViewStateCopyWithImpl;
@override @useResult
$Res call({
 String alias, String password, bool rememberPassword, bool passwordVisible, bool requiredError, SshConnectionSnapshot? connection, SettingsAction? action
});


@override $SshConnectionSnapshotCopyWith<$Res>? get connection;@override $SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class __$SshPasswordViewStateCopyWithImpl<$Res>
    implements _$SshPasswordViewStateCopyWith<$Res> {
  __$SshPasswordViewStateCopyWithImpl(this._self, this._then);

  final _SshPasswordViewState _self;
  final $Res Function(_SshPasswordViewState) _then;

/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? password = null,Object? rememberPassword = null,Object? passwordVisible = null,Object? requiredError = null,Object? connection = freezed,Object? action = freezed,}) {
  return _then(_SshPasswordViewState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,rememberPassword: null == rememberPassword ? _self.rememberPassword : rememberPassword // ignore: cast_nullable_to_non_nullable
as bool,passwordVisible: null == passwordVisible ? _self.passwordVisible : passwordVisible // ignore: cast_nullable_to_non_nullable
as bool,requiredError: null == requiredError ? _self.requiredError : requiredError // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as SshConnectionSnapshot?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionSnapshotCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $SshConnectionSnapshotCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of SshPasswordViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

// dart format on
