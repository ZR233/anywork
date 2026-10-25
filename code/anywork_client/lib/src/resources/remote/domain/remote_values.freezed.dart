// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshPasswordUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordUpdate);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SshPasswordUpdateCopyWith<$Res>  {
$SshPasswordUpdateCopyWith(SshPasswordUpdate _, $Res Function(SshPasswordUpdate) __);
}


/// Adds pattern-matching-related methods to [SshPasswordUpdate].
extension SshPasswordUpdatePatterns on SshPasswordUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PreserveSshPasswordUpdate value)?  preserve,TResult Function( ReplaceSshPasswordUpdate value)?  replace,TResult Function( ClearSshPasswordUpdate value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate() when preserve != null:
return preserve(_that);case ReplaceSshPasswordUpdate() when replace != null:
return replace(_that);case ClearSshPasswordUpdate() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PreserveSshPasswordUpdate value)  preserve,required TResult Function( ReplaceSshPasswordUpdate value)  replace,required TResult Function( ClearSshPasswordUpdate value)  clear,}){
final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate():
return preserve(_that);case ReplaceSshPasswordUpdate():
return replace(_that);case ClearSshPasswordUpdate():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PreserveSshPasswordUpdate value)?  preserve,TResult? Function( ReplaceSshPasswordUpdate value)?  replace,TResult? Function( ClearSshPasswordUpdate value)?  clear,}){
final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate() when preserve != null:
return preserve(_that);case ReplaceSshPasswordUpdate() when replace != null:
return replace(_that);case ClearSshPasswordUpdate() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preserve,TResult Function( String value)?  replace,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate() when preserve != null:
return preserve();case ReplaceSshPasswordUpdate() when replace != null:
return replace(_that.value);case ClearSshPasswordUpdate() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preserve,required TResult Function( String value)  replace,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate():
return preserve();case ReplaceSshPasswordUpdate():
return replace(_that.value);case ClearSshPasswordUpdate():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preserve,TResult? Function( String value)?  replace,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case PreserveSshPasswordUpdate() when preserve != null:
return preserve();case ReplaceSshPasswordUpdate() when replace != null:
return replace(_that.value);case ClearSshPasswordUpdate() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class PreserveSshPasswordUpdate implements SshPasswordUpdate {
  const PreserveSshPasswordUpdate();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PreserveSshPasswordUpdate);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ReplaceSshPasswordUpdate implements SshPasswordUpdate {
  const ReplaceSshPasswordUpdate({required this.value});


 final  String value;

/// Create a copy of SshPasswordUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplaceSshPasswordUpdateCopyWith<ReplaceSshPasswordUpdate> get copyWith => _$ReplaceSshPasswordUpdateCopyWithImpl<ReplaceSshPasswordUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplaceSshPasswordUpdate&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $ReplaceSshPasswordUpdateCopyWith<$Res> implements $SshPasswordUpdateCopyWith<$Res> {
  factory $ReplaceSshPasswordUpdateCopyWith(ReplaceSshPasswordUpdate value, $Res Function(ReplaceSshPasswordUpdate) _then) = _$ReplaceSshPasswordUpdateCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ReplaceSshPasswordUpdateCopyWithImpl<$Res>
    implements $ReplaceSshPasswordUpdateCopyWith<$Res> {
  _$ReplaceSshPasswordUpdateCopyWithImpl(this._self, this._then);

  final ReplaceSshPasswordUpdate _self;
  final $Res Function(ReplaceSshPasswordUpdate) _then;

/// Create a copy of SshPasswordUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(ReplaceSshPasswordUpdate(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ClearSshPasswordUpdate implements SshPasswordUpdate {
  const ClearSshPasswordUpdate();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClearSshPasswordUpdate);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$SshServerProfile {

 String get alias; String get hostName; int get port; String get username; String? get identityFile;
/// Create a copy of SshServerProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshServerProfileCopyWith<SshServerProfile> get copyWith => _$SshServerProfileCopyWithImpl<SshServerProfile>(this as SshServerProfile, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshServerProfile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshServerProfile&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.hostName, _this.hostName) || other.hostName == _this.hostName)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.username, _this.username) || other.username == _this.username)&&(identical(other.identityFile, _this.identityFile) || other.identityFile == _this.identityFile));
}


@override
int get hashCode {
  final _this = this as SshServerProfile;
  return Object.hash(runtimeType,_this.alias,_this.hostName,_this.port,_this.username,_this.identityFile);
}



}

/// @nodoc
abstract mixin class $SshServerProfileCopyWith<$Res>  {
  factory $SshServerProfileCopyWith(SshServerProfile value, $Res Function(SshServerProfile) _then) = _$SshServerProfileCopyWithImpl;
@useResult
$Res call({
 String alias, String hostName, int port, String username, String? identityFile
});




}
/// @nodoc
class _$SshServerProfileCopyWithImpl<$Res>
    implements $SshServerProfileCopyWith<$Res> {
  _$SshServerProfileCopyWithImpl(this._self, this._then);

  final SshServerProfile _self;
  final $Res Function(SshServerProfile) _then;

/// Create a copy of SshServerProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? hostName = null,Object? port = null,Object? username = null,Object? identityFile = freezed,}) {
  return _then(SshServerProfile(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,hostName: null == hostName ? _self.hostName : hostName // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,identityFile: freezed == identityFile ? _self.identityFile : identityFile // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SshServerProfile].
extension SshServerProfilePatterns on SshServerProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshServerProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshServerProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshServerProfile value)  $default,){
final _that = this;
switch (_that) {
case _SshServerProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshServerProfile value)?  $default,){
final _that = this;
switch (_that) {
case _SshServerProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  String hostName,  int port,  String username,  String? identityFile)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshServerProfile() when $default != null:
return $default(_that.alias,_that.hostName,_that.port,_that.username,_that.identityFile);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  String hostName,  int port,  String username,  String? identityFile)  $default,) {final _that = this;
switch (_that) {
case _SshServerProfile():
return $default(_that.alias,_that.hostName,_that.port,_that.username,_that.identityFile);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  String hostName,  int port,  String username,  String? identityFile)?  $default,) {final _that = this;
switch (_that) {
case _SshServerProfile() when $default != null:
return $default(_that.alias,_that.hostName,_that.port,_that.username,_that.identityFile);case _:
  return null;

}
}

}

/// @nodoc


class _SshServerProfile implements SshServerProfile {
  const _SshServerProfile({required this.alias, required this.hostName, required this.port, required this.username, required this.identityFile});


@override final  String alias;
@override final  String hostName;
@override final  int port;
@override final  String username;
@override final  String? identityFile;

/// Create a copy of SshServerProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshServerProfileCopyWith<_SshServerProfile> get copyWith => __$SshServerProfileCopyWithImpl<_SshServerProfile>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshServerProfile&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.hostName, hostName) || other.hostName == hostName)&&(identical(other.port, port) || other.port == port)&&(identical(other.username, username) || other.username == username)&&(identical(other.identityFile, identityFile) || other.identityFile == identityFile));
}


@override
int get hashCode {
    return Object.hash(runtimeType,alias,hostName,port,username,identityFile);
}



}

/// @nodoc
abstract mixin class _$SshServerProfileCopyWith<$Res> implements $SshServerProfileCopyWith<$Res> {
  factory _$SshServerProfileCopyWith(_SshServerProfile value, $Res Function(_SshServerProfile) _then) = __$SshServerProfileCopyWithImpl;
@override @useResult
$Res call({
 String alias, String hostName, int port, String username, String? identityFile
});




}
/// @nodoc
class __$SshServerProfileCopyWithImpl<$Res>
    implements _$SshServerProfileCopyWith<$Res> {
  __$SshServerProfileCopyWithImpl(this._self, this._then);

  final _SshServerProfile _self;
  final $Res Function(_SshServerProfile) _then;

/// Create a copy of SshServerProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? hostName = null,Object? port = null,Object? username = null,Object? identityFile = freezed,}) {
  return _then(_SshServerProfile(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,hostName: null == hostName ? _self.hostName : hostName // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,identityFile: freezed == identityFile ? _self.identityFile : identityFile // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$SshServerRuntimeEntry {

 SshServerProfile get profile; bool get managed; bool get hasPassword;
/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshServerRuntimeEntryCopyWith<SshServerRuntimeEntry> get copyWith => _$SshServerRuntimeEntryCopyWithImpl<SshServerRuntimeEntry>(this as SshServerRuntimeEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshServerRuntimeEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshServerRuntimeEntry&&(identical(other.profile, _this.profile) || other.profile == _this.profile)&&(identical(other.managed, _this.managed) || other.managed == _this.managed)&&(identical(other.hasPassword, _this.hasPassword) || other.hasPassword == _this.hasPassword));
}


@override
int get hashCode {
  final _this = this as SshServerRuntimeEntry;
  return Object.hash(runtimeType,_this.profile,_this.managed,_this.hasPassword);
}



}

/// @nodoc
abstract mixin class $SshServerRuntimeEntryCopyWith<$Res>  {
  factory $SshServerRuntimeEntryCopyWith(SshServerRuntimeEntry value, $Res Function(SshServerRuntimeEntry) _then) = _$SshServerRuntimeEntryCopyWithImpl;
@useResult
$Res call({
 SshServerProfile profile, bool managed, bool hasPassword
});


$SshServerProfileCopyWith<$Res> get profile;

}
/// @nodoc
class _$SshServerRuntimeEntryCopyWithImpl<$Res>
    implements $SshServerRuntimeEntryCopyWith<$Res> {
  _$SshServerRuntimeEntryCopyWithImpl(this._self, this._then);

  final SshServerRuntimeEntry _self;
  final $Res Function(SshServerRuntimeEntry) _then;

/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profile = null,Object? managed = null,Object? hasPassword = null,}) {
  return _then(SshServerRuntimeEntry(
profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as SshServerProfile,managed: null == managed ? _self.managed : managed // ignore: cast_nullable_to_non_nullable
as bool,hasPassword: null == hasPassword ? _self.hasPassword : hasPassword // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerProfileCopyWith<$Res> get profile {

  return $SshServerProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshServerRuntimeEntry].
extension SshServerRuntimeEntryPatterns on SshServerRuntimeEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshServerRuntimeEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshServerRuntimeEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshServerRuntimeEntry value)  $default,){
final _that = this;
switch (_that) {
case _SshServerRuntimeEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshServerRuntimeEntry value)?  $default,){
final _that = this;
switch (_that) {
case _SshServerRuntimeEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SshServerProfile profile,  bool managed,  bool hasPassword)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshServerRuntimeEntry() when $default != null:
return $default(_that.profile,_that.managed,_that.hasPassword);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SshServerProfile profile,  bool managed,  bool hasPassword)  $default,) {final _that = this;
switch (_that) {
case _SshServerRuntimeEntry():
return $default(_that.profile,_that.managed,_that.hasPassword);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SshServerProfile profile,  bool managed,  bool hasPassword)?  $default,) {final _that = this;
switch (_that) {
case _SshServerRuntimeEntry() when $default != null:
return $default(_that.profile,_that.managed,_that.hasPassword);case _:
  return null;

}
}

}

/// @nodoc


class _SshServerRuntimeEntry implements SshServerRuntimeEntry {
  const _SshServerRuntimeEntry({required this.profile, required this.managed, required this.hasPassword});


@override final  SshServerProfile profile;
@override final  bool managed;
@override final  bool hasPassword;

/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshServerRuntimeEntryCopyWith<_SshServerRuntimeEntry> get copyWith => __$SshServerRuntimeEntryCopyWithImpl<_SshServerRuntimeEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshServerRuntimeEntry&&(identical(other.profile, profile) || other.profile == profile)&&(identical(other.managed, managed) || other.managed == managed)&&(identical(other.hasPassword, hasPassword) || other.hasPassword == hasPassword));
}


@override
int get hashCode {
    return Object.hash(runtimeType,profile,managed,hasPassword);
}



}

/// @nodoc
abstract mixin class _$SshServerRuntimeEntryCopyWith<$Res> implements $SshServerRuntimeEntryCopyWith<$Res> {
  factory _$SshServerRuntimeEntryCopyWith(_SshServerRuntimeEntry value, $Res Function(_SshServerRuntimeEntry) _then) = __$SshServerRuntimeEntryCopyWithImpl;
@override @useResult
$Res call({
 SshServerProfile profile, bool managed, bool hasPassword
});


@override $SshServerProfileCopyWith<$Res> get profile;

}
/// @nodoc
class __$SshServerRuntimeEntryCopyWithImpl<$Res>
    implements _$SshServerRuntimeEntryCopyWith<$Res> {
  __$SshServerRuntimeEntryCopyWithImpl(this._self, this._then);

  final _SshServerRuntimeEntry _self;
  final $Res Function(_SshServerRuntimeEntry) _then;

/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profile = null,Object? managed = null,Object? hasPassword = null,}) {
  return _then(_SshServerRuntimeEntry(
profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as SshServerProfile,managed: null == managed ? _self.managed : managed // ignore: cast_nullable_to_non_nullable
as bool,hasPassword: null == hasPassword ? _self.hasPassword : hasPassword // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SshServerRuntimeEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerProfileCopyWith<$Res> get profile {

  return $SshServerProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}

/// @nodoc
mixin _$SshConnectionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SshConnectionStateCopyWith<$Res>  {
$SshConnectionStateCopyWith(SshConnectionState _, $Res Function(SshConnectionState) __);
}


/// Adds pattern-matching-related methods to [SshConnectionState].
extension SshConnectionStatePatterns on SshConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisconnectedSshConnectionState value)?  disconnected,TResult Function( ConnectingSshConnectionState value)?  connecting,TResult Function( ReadySshConnectionState value)?  ready,TResult Function( ReconnectingSshConnectionState value)?  reconnecting,TResult Function( FailedSshConnectionState value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisconnectedSshConnectionState() when disconnected != null:
return disconnected(_that);case ConnectingSshConnectionState() when connecting != null:
return connecting(_that);case ReadySshConnectionState() when ready != null:
return ready(_that);case ReconnectingSshConnectionState() when reconnecting != null:
return reconnecting(_that);case FailedSshConnectionState() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisconnectedSshConnectionState value)  disconnected,required TResult Function( ConnectingSshConnectionState value)  connecting,required TResult Function( ReadySshConnectionState value)  ready,required TResult Function( ReconnectingSshConnectionState value)  reconnecting,required TResult Function( FailedSshConnectionState value)  failed,}){
final _that = this;
switch (_that) {
case DisconnectedSshConnectionState():
return disconnected(_that);case ConnectingSshConnectionState():
return connecting(_that);case ReadySshConnectionState():
return ready(_that);case ReconnectingSshConnectionState():
return reconnecting(_that);case FailedSshConnectionState():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisconnectedSshConnectionState value)?  disconnected,TResult? Function( ConnectingSshConnectionState value)?  connecting,TResult? Function( ReadySshConnectionState value)?  ready,TResult? Function( ReconnectingSshConnectionState value)?  reconnecting,TResult? Function( FailedSshConnectionState value)?  failed,}){
final _that = this;
switch (_that) {
case DisconnectedSshConnectionState() when disconnected != null:
return disconnected(_that);case ConnectingSshConnectionState() when connecting != null:
return connecting(_that);case ReadySshConnectionState() when ready != null:
return ready(_that);case ReconnectingSshConnectionState() when reconnecting != null:
return reconnecting(_that);case FailedSshConnectionState() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( String helperVersion,  String architecture)?  ready,TResult Function( int attempt,  int delaySeconds)?  reconnecting,TResult Function( String code,  String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisconnectedSshConnectionState() when disconnected != null:
return disconnected();case ConnectingSshConnectionState() when connecting != null:
return connecting();case ReadySshConnectionState() when ready != null:
return ready(_that.helperVersion,_that.architecture);case ReconnectingSshConnectionState() when reconnecting != null:
return reconnecting(_that.attempt,_that.delaySeconds);case FailedSshConnectionState() when failed != null:
return failed(_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( String helperVersion,  String architecture)  ready,required TResult Function( int attempt,  int delaySeconds)  reconnecting,required TResult Function( String code,  String message)  failed,}) {final _that = this;
switch (_that) {
case DisconnectedSshConnectionState():
return disconnected();case ConnectingSshConnectionState():
return connecting();case ReadySshConnectionState():
return ready(_that.helperVersion,_that.architecture);case ReconnectingSshConnectionState():
return reconnecting(_that.attempt,_that.delaySeconds);case FailedSshConnectionState():
return failed(_that.code,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( String helperVersion,  String architecture)?  ready,TResult? Function( int attempt,  int delaySeconds)?  reconnecting,TResult? Function( String code,  String message)?  failed,}) {final _that = this;
switch (_that) {
case DisconnectedSshConnectionState() when disconnected != null:
return disconnected();case ConnectingSshConnectionState() when connecting != null:
return connecting();case ReadySshConnectionState() when ready != null:
return ready(_that.helperVersion,_that.architecture);case ReconnectingSshConnectionState() when reconnecting != null:
return reconnecting(_that.attempt,_that.delaySeconds);case FailedSshConnectionState() when failed != null:
return failed(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class DisconnectedSshConnectionState implements SshConnectionState {
  const DisconnectedSshConnectionState();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisconnectedSshConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ConnectingSshConnectionState implements SshConnectionState {
  const ConnectingSshConnectionState();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectingSshConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ReadySshConnectionState implements SshConnectionState {
  const ReadySshConnectionState({required this.helperVersion, required this.architecture});


 final  String helperVersion;
 final  String architecture;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadySshConnectionStateCopyWith<ReadySshConnectionState> get copyWith => _$ReadySshConnectionStateCopyWithImpl<ReadySshConnectionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadySshConnectionState&&(identical(other.helperVersion, helperVersion) || other.helperVersion == helperVersion)&&(identical(other.architecture, architecture) || other.architecture == architecture));
}


@override
int get hashCode {
    return Object.hash(runtimeType,helperVersion,architecture);
}



}

/// @nodoc
abstract mixin class $ReadySshConnectionStateCopyWith<$Res> implements $SshConnectionStateCopyWith<$Res> {
  factory $ReadySshConnectionStateCopyWith(ReadySshConnectionState value, $Res Function(ReadySshConnectionState) _then) = _$ReadySshConnectionStateCopyWithImpl;
@useResult
$Res call({
 String helperVersion, String architecture
});




}
/// @nodoc
class _$ReadySshConnectionStateCopyWithImpl<$Res>
    implements $ReadySshConnectionStateCopyWith<$Res> {
  _$ReadySshConnectionStateCopyWithImpl(this._self, this._then);

  final ReadySshConnectionState _self;
  final $Res Function(ReadySshConnectionState) _then;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? helperVersion = null,Object? architecture = null,}) {
  return _then(ReadySshConnectionState(
helperVersion: null == helperVersion ? _self.helperVersion : helperVersion // ignore: cast_nullable_to_non_nullable
as String,architecture: null == architecture ? _self.architecture : architecture // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReconnectingSshConnectionState implements SshConnectionState {
  const ReconnectingSshConnectionState({required this.attempt, required this.delaySeconds});


 final  int attempt;
 final  int delaySeconds;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconnectingSshConnectionStateCopyWith<ReconnectingSshConnectionState> get copyWith => _$ReconnectingSshConnectionStateCopyWithImpl<ReconnectingSshConnectionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconnectingSshConnectionState&&(identical(other.attempt, attempt) || other.attempt == attempt)&&(identical(other.delaySeconds, delaySeconds) || other.delaySeconds == delaySeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attempt,delaySeconds);
}



}

/// @nodoc
abstract mixin class $ReconnectingSshConnectionStateCopyWith<$Res> implements $SshConnectionStateCopyWith<$Res> {
  factory $ReconnectingSshConnectionStateCopyWith(ReconnectingSshConnectionState value, $Res Function(ReconnectingSshConnectionState) _then) = _$ReconnectingSshConnectionStateCopyWithImpl;
@useResult
$Res call({
 int attempt, int delaySeconds
});




}
/// @nodoc
class _$ReconnectingSshConnectionStateCopyWithImpl<$Res>
    implements $ReconnectingSshConnectionStateCopyWith<$Res> {
  _$ReconnectingSshConnectionStateCopyWithImpl(this._self, this._then);

  final ReconnectingSshConnectionState _self;
  final $Res Function(ReconnectingSshConnectionState) _then;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attempt = null,Object? delaySeconds = null,}) {
  return _then(ReconnectingSshConnectionState(
attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,delaySeconds: null == delaySeconds ? _self.delaySeconds : delaySeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FailedSshConnectionState implements SshConnectionState {
  const FailedSshConnectionState({required this.code, required this.message});


 final  String code;
 final  String message;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedSshConnectionStateCopyWith<FailedSshConnectionState> get copyWith => _$FailedSshConnectionStateCopyWithImpl<FailedSshConnectionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedSshConnectionState&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message);
}



}

/// @nodoc
abstract mixin class $FailedSshConnectionStateCopyWith<$Res> implements $SshConnectionStateCopyWith<$Res> {
  factory $FailedSshConnectionStateCopyWith(FailedSshConnectionState value, $Res Function(FailedSshConnectionState) _then) = _$FailedSshConnectionStateCopyWithImpl;
@useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$FailedSshConnectionStateCopyWithImpl<$Res>
    implements $FailedSshConnectionStateCopyWith<$Res> {
  _$FailedSshConnectionStateCopyWithImpl(this._self, this._then);

  final FailedSshConnectionState _self;
  final $Res Function(FailedSshConnectionState) _then;

/// Create a copy of SshConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(FailedSshConnectionState(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SshConnectionSnapshot {

 String get alias; SshConnectionState get state;
/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshConnectionSnapshotCopyWith<SshConnectionSnapshot> get copyWith => _$SshConnectionSnapshotCopyWithImpl<SshConnectionSnapshot>(this as SshConnectionSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshConnectionSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshConnectionSnapshot&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as SshConnectionSnapshot;
  return Object.hash(runtimeType,_this.alias,_this.state);
}



}

/// @nodoc
abstract mixin class $SshConnectionSnapshotCopyWith<$Res>  {
  factory $SshConnectionSnapshotCopyWith(SshConnectionSnapshot value, $Res Function(SshConnectionSnapshot) _then) = _$SshConnectionSnapshotCopyWithImpl;
@useResult
$Res call({
 String alias, SshConnectionState state
});


$SshConnectionStateCopyWith<$Res> get state;

}
/// @nodoc
class _$SshConnectionSnapshotCopyWithImpl<$Res>
    implements $SshConnectionSnapshotCopyWith<$Res> {
  _$SshConnectionSnapshotCopyWithImpl(this._self, this._then);

  final SshConnectionSnapshot _self;
  final $Res Function(SshConnectionSnapshot) _then;

/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? state = null,}) {
  return _then(SshConnectionSnapshot(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SshConnectionState,
  ));
}
/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionStateCopyWith<$Res> get state {

  return $SshConnectionStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshConnectionSnapshot].
extension SshConnectionSnapshotPatterns on SshConnectionSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshConnectionSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshConnectionSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshConnectionSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _SshConnectionSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshConnectionSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _SshConnectionSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  SshConnectionState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshConnectionSnapshot() when $default != null:
return $default(_that.alias,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  SshConnectionState state)  $default,) {final _that = this;
switch (_that) {
case _SshConnectionSnapshot():
return $default(_that.alias,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  SshConnectionState state)?  $default,) {final _that = this;
switch (_that) {
case _SshConnectionSnapshot() when $default != null:
return $default(_that.alias,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _SshConnectionSnapshot implements SshConnectionSnapshot {
  const _SshConnectionSnapshot({required this.alias, required this.state});


@override final  String alias;
@override final  SshConnectionState state;

/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshConnectionSnapshotCopyWith<_SshConnectionSnapshot> get copyWith => __$SshConnectionSnapshotCopyWithImpl<_SshConnectionSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshConnectionSnapshot&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,alias,state);
}



}

/// @nodoc
abstract mixin class _$SshConnectionSnapshotCopyWith<$Res> implements $SshConnectionSnapshotCopyWith<$Res> {
  factory _$SshConnectionSnapshotCopyWith(_SshConnectionSnapshot value, $Res Function(_SshConnectionSnapshot) _then) = __$SshConnectionSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String alias, SshConnectionState state
});


@override $SshConnectionStateCopyWith<$Res> get state;

}
/// @nodoc
class __$SshConnectionSnapshotCopyWithImpl<$Res>
    implements _$SshConnectionSnapshotCopyWith<$Res> {
  __$SshConnectionSnapshotCopyWithImpl(this._self, this._then);

  final _SshConnectionSnapshot _self;
  final $Res Function(_SshConnectionSnapshot) _then;

/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? state = null,}) {
  return _then(_SshConnectionSnapshot(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SshConnectionState,
  ));
}

/// Create a copy of SshConnectionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionStateCopyWith<$Res> get state {

  return $SshConnectionStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$RemoteDirectoryEntry {

 String get name; String get path; bool get isDirectory; bool get isSymlink;
/// Create a copy of RemoteDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryEntryCopyWith<RemoteDirectoryEntry> get copyWith => _$RemoteDirectoryEntryCopyWithImpl<RemoteDirectoryEntry>(this as RemoteDirectoryEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryEntry&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.isDirectory, _this.isDirectory) || other.isDirectory == _this.isDirectory)&&(identical(other.isSymlink, _this.isSymlink) || other.isSymlink == _this.isSymlink));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryEntry;
  return Object.hash(runtimeType,_this.name,_this.path,_this.isDirectory,_this.isSymlink);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryEntryCopyWith<$Res>  {
  factory $RemoteDirectoryEntryCopyWith(RemoteDirectoryEntry value, $Res Function(RemoteDirectoryEntry) _then) = _$RemoteDirectoryEntryCopyWithImpl;
@useResult
$Res call({
 String name, String path, bool isDirectory, bool isSymlink
});




}
/// @nodoc
class _$RemoteDirectoryEntryCopyWithImpl<$Res>
    implements $RemoteDirectoryEntryCopyWith<$Res> {
  _$RemoteDirectoryEntryCopyWithImpl(this._self, this._then);

  final RemoteDirectoryEntry _self;
  final $Res Function(RemoteDirectoryEntry) _then;

/// Create a copy of RemoteDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? path = null,Object? isDirectory = null,Object? isSymlink = null,}) {
  return _then(RemoteDirectoryEntry(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RemoteDirectoryEntry].
extension RemoteDirectoryEntryPatterns on RemoteDirectoryEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryEntry value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryEntry value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String path,  bool isDirectory,  bool isSymlink)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntry() when $default != null:
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String path,  bool isDirectory,  bool isSymlink)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntry():
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String path,  bool isDirectory,  bool isSymlink)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntry() when $default != null:
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryEntry implements RemoteDirectoryEntry {
  const _RemoteDirectoryEntry({required this.name, required this.path, required this.isDirectory, required this.isSymlink});


@override final  String name;
@override final  String path;
@override final  bool isDirectory;
@override final  bool isSymlink;

/// Create a copy of RemoteDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryEntryCopyWith<_RemoteDirectoryEntry> get copyWith => __$RemoteDirectoryEntryCopyWithImpl<_RemoteDirectoryEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryEntry&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.isDirectory, isDirectory) || other.isDirectory == isDirectory)&&(identical(other.isSymlink, isSymlink) || other.isSymlink == isSymlink));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,path,isDirectory,isSymlink);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryEntryCopyWith<$Res> implements $RemoteDirectoryEntryCopyWith<$Res> {
  factory _$RemoteDirectoryEntryCopyWith(_RemoteDirectoryEntry value, $Res Function(_RemoteDirectoryEntry) _then) = __$RemoteDirectoryEntryCopyWithImpl;
@override @useResult
$Res call({
 String name, String path, bool isDirectory, bool isSymlink
});




}
/// @nodoc
class __$RemoteDirectoryEntryCopyWithImpl<$Res>
    implements _$RemoteDirectoryEntryCopyWith<$Res> {
  __$RemoteDirectoryEntryCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryEntry _self;
  final $Res Function(_RemoteDirectoryEntry) _then;

/// Create a copy of RemoteDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? path = null,Object? isDirectory = null,Object? isSymlink = null,}) {
  return _then(_RemoteDirectoryEntry(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$RemoteDirectoryListing {

 String get path; String? get parent; List<RemoteDirectoryEntry> get entries; String? get nextCursor;
/// Create a copy of RemoteDirectoryListing
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryListingCopyWith<RemoteDirectoryListing> get copyWith => _$RemoteDirectoryListingCopyWithImpl<RemoteDirectoryListing>(this as RemoteDirectoryListing, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryListing;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryListing&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryListing;
  return Object.hash(runtimeType,_this.path,_this.parent,const DeepCollectionEquality().hash(_this.entries),_this.nextCursor);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryListingCopyWith<$Res>  {
  factory $RemoteDirectoryListingCopyWith(RemoteDirectoryListing value, $Res Function(RemoteDirectoryListing) _then) = _$RemoteDirectoryListingCopyWithImpl;
@useResult
$Res call({
 String path, String? parent, List<RemoteDirectoryEntry> entries, String? nextCursor
});




}
/// @nodoc
class _$RemoteDirectoryListingCopyWithImpl<$Res>
    implements $RemoteDirectoryListingCopyWith<$Res> {
  _$RemoteDirectoryListingCopyWithImpl(this._self, this._then);

  final RemoteDirectoryListing _self;
  final $Res Function(RemoteDirectoryListing) _then;

/// Create a copy of RemoteDirectoryListing
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? parent = freezed,Object? entries = null,Object? nextCursor = freezed,}) {
  return _then(RemoteDirectoryListing(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RemoteDirectoryListing].
extension RemoteDirectoryListingPatterns on RemoteDirectoryListing {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryListing value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryListing() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryListing value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryListing():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryListing value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryListing() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryListing() when $default != null:
return $default(_that.path,_that.parent,_that.entries,_that.nextCursor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryListing():
return $default(_that.path,_that.parent,_that.entries,_that.nextCursor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryListing() when $default != null:
return $default(_that.path,_that.parent,_that.entries,_that.nextCursor);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryListing implements RemoteDirectoryListing {
  const _RemoteDirectoryListing({required this.path, required this.parent, required  List<RemoteDirectoryEntry> entries, required this.nextCursor}): _entries = entries;


@override final  String path;
@override final  String? parent;
 final  List<RemoteDirectoryEntry> _entries;
@override List<RemoteDirectoryEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override final  String? nextCursor;

/// Create a copy of RemoteDirectoryListing
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryListingCopyWith<_RemoteDirectoryListing> get copyWith => __$RemoteDirectoryListingCopyWithImpl<_RemoteDirectoryListing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryListing&&(identical(other.path, path) || other.path == path)&&(identical(other.parent, parent) || other.parent == parent)&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,parent,const DeepCollectionEquality().hash(_entries),nextCursor);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryListingCopyWith<$Res> implements $RemoteDirectoryListingCopyWith<$Res> {
  factory _$RemoteDirectoryListingCopyWith(_RemoteDirectoryListing value, $Res Function(_RemoteDirectoryListing) _then) = __$RemoteDirectoryListingCopyWithImpl;
@override @useResult
$Res call({
 String path, String? parent, List<RemoteDirectoryEntry> entries, String? nextCursor
});




}
/// @nodoc
class __$RemoteDirectoryListingCopyWithImpl<$Res>
    implements _$RemoteDirectoryListingCopyWith<$Res> {
  __$RemoteDirectoryListingCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryListing _self;
  final $Res Function(_RemoteDirectoryListing) _then;

/// Create a copy of RemoteDirectoryListing
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? parent = freezed,Object? entries = null,Object? nextCursor = freezed,}) {
  return _then(_RemoteDirectoryListing(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
