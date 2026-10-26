// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$McpHealthRead {

 TypedListRef get mcpServers; TypedListRef get activeMcpServers;
/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpHealthReadCopyWith<McpHealthRead> get copyWith => _$McpHealthReadCopyWithImpl<McpHealthRead>(this as McpHealthRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpHealthRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpHealthRead&&(identical(other.mcpServers, _this.mcpServers) || other.mcpServers == _this.mcpServers)&&(identical(other.activeMcpServers, _this.activeMcpServers) || other.activeMcpServers == _this.activeMcpServers));
}


@override
int get hashCode {
  final _this = this as McpHealthRead;
  return Object.hash(runtimeType,_this.mcpServers,_this.activeMcpServers);
}

@override
String toString() {
  final _this = this as McpHealthRead;
  return 'McpHealthRead(mcpServers: ${_this.mcpServers}, activeMcpServers: ${_this.activeMcpServers})';
}


}

/// @nodoc
abstract mixin class $McpHealthReadCopyWith<$Res>  {
  factory $McpHealthReadCopyWith(McpHealthRead value, $Res Function(McpHealthRead) _then) = _$McpHealthReadCopyWithImpl;
@useResult
$Res call({
 TypedListRef mcpServers, TypedListRef activeMcpServers
});


$TypedListRefCopyWith<$Res> get mcpServers;$TypedListRefCopyWith<$Res> get activeMcpServers;

}
/// @nodoc
class _$McpHealthReadCopyWithImpl<$Res>
    implements $McpHealthReadCopyWith<$Res> {
  _$McpHealthReadCopyWithImpl(this._self, this._then);

  final McpHealthRead _self;
  final $Res Function(McpHealthRead) _then;

/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mcpServers = null,Object? activeMcpServers = null,}) {
  return _then(McpHealthRead(
mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,activeMcpServers: null == activeMcpServers ? _self.activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mcpServers {

  return $TypedListRefCopyWith<$Res>(_self.mcpServers, (value) {
    return _then(_self.copyWith(mcpServers: value));
  });
}/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get activeMcpServers {

  return $TypedListRefCopyWith<$Res>(_self.activeMcpServers, (value) {
    return _then(_self.copyWith(activeMcpServers: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpHealthRead].
extension McpHealthReadPatterns on McpHealthRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpHealthRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpHealthRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpHealthRead value)  $default,){
final _that = this;
switch (_that) {
case _McpHealthRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpHealthRead value)?  $default,){
final _that = this;
switch (_that) {
case _McpHealthRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef mcpServers,  TypedListRef activeMcpServers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpHealthRead() when $default != null:
return $default(_that.mcpServers,_that.activeMcpServers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef mcpServers,  TypedListRef activeMcpServers)  $default,) {final _that = this;
switch (_that) {
case _McpHealthRead():
return $default(_that.mcpServers,_that.activeMcpServers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef mcpServers,  TypedListRef activeMcpServers)?  $default,) {final _that = this;
switch (_that) {
case _McpHealthRead() when $default != null:
return $default(_that.mcpServers,_that.activeMcpServers);case _:
  return null;

}
}

}

/// @nodoc


class _McpHealthRead implements McpHealthRead {
  const _McpHealthRead({required this.mcpServers, required this.activeMcpServers});


@override final  TypedListRef mcpServers;
@override final  TypedListRef activeMcpServers;

/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpHealthReadCopyWith<_McpHealthRead> get copyWith => __$McpHealthReadCopyWithImpl<_McpHealthRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpHealthRead&&(identical(other.mcpServers, mcpServers) || other.mcpServers == mcpServers)&&(identical(other.activeMcpServers, activeMcpServers) || other.activeMcpServers == activeMcpServers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mcpServers,activeMcpServers);
}

@override
String toString() {
    return 'McpHealthRead(mcpServers: $mcpServers, activeMcpServers: $activeMcpServers)';
}


}

/// @nodoc
abstract mixin class _$McpHealthReadCopyWith<$Res> implements $McpHealthReadCopyWith<$Res> {
  factory _$McpHealthReadCopyWith(_McpHealthRead value, $Res Function(_McpHealthRead) _then) = __$McpHealthReadCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef mcpServers, TypedListRef activeMcpServers
});


@override $TypedListRefCopyWith<$Res> get mcpServers;@override $TypedListRefCopyWith<$Res> get activeMcpServers;

}
/// @nodoc
class __$McpHealthReadCopyWithImpl<$Res>
    implements _$McpHealthReadCopyWith<$Res> {
  __$McpHealthReadCopyWithImpl(this._self, this._then);

  final _McpHealthRead _self;
  final $Res Function(_McpHealthRead) _then;

/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mcpServers = null,Object? activeMcpServers = null,}) {
  return _then(_McpHealthRead(
mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,activeMcpServers: null == activeMcpServers ? _self.activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mcpServers {

  return $TypedListRefCopyWith<$Res>(_self.mcpServers, (value) {
    return _then(_self.copyWith(mcpServers: value));
  });
}/// Create a copy of McpHealthRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get activeMcpServers {

  return $TypedListRefCopyWith<$Res>(_self.activeMcpServers, (value) {
    return _then(_self.copyWith(activeMcpServers: value));
  });
}
}

/// @nodoc
mixin _$McpReadHeader {

 ReadText get desiredConfigFingerprint; ReadText get appliedConfigFingerprint; McpHealthRead get health;
/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpReadHeaderCopyWith<McpReadHeader> get copyWith => _$McpReadHeaderCopyWithImpl<McpReadHeader>(this as McpReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpReadHeader&&(identical(other.desiredConfigFingerprint, _this.desiredConfigFingerprint) || other.desiredConfigFingerprint == _this.desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, _this.appliedConfigFingerprint) || other.appliedConfigFingerprint == _this.appliedConfigFingerprint)&&(identical(other.health, _this.health) || other.health == _this.health));
}


@override
int get hashCode {
  final _this = this as McpReadHeader;
  return Object.hash(runtimeType,_this.desiredConfigFingerprint,_this.appliedConfigFingerprint,_this.health);
}



}

/// @nodoc
abstract mixin class $McpReadHeaderCopyWith<$Res>  {
  factory $McpReadHeaderCopyWith(McpReadHeader value, $Res Function(McpReadHeader) _then) = _$McpReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadText desiredConfigFingerprint, ReadText appliedConfigFingerprint, McpHealthRead health
});


$ReadTextCopyWith<$Res> get desiredConfigFingerprint;$ReadTextCopyWith<$Res> get appliedConfigFingerprint;$McpHealthReadCopyWith<$Res> get health;

}
/// @nodoc
class _$McpReadHeaderCopyWithImpl<$Res>
    implements $McpReadHeaderCopyWith<$Res> {
  _$McpReadHeaderCopyWithImpl(this._self, this._then);

  final McpReadHeader _self;
  final $Res Function(McpReadHeader) _then;

/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? desiredConfigFingerprint = null,Object? appliedConfigFingerprint = null,Object? health = null,}) {
  return _then(McpReadHeader(
desiredConfigFingerprint: null == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,appliedConfigFingerprint: null == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,health: null == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as McpHealthRead,
  ));
}
/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get desiredConfigFingerprint {

  return $ReadTextCopyWith<$Res>(_self.desiredConfigFingerprint, (value) {
    return _then(_self.copyWith(desiredConfigFingerprint: value));
  });
}/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get appliedConfigFingerprint {

  return $ReadTextCopyWith<$Res>(_self.appliedConfigFingerprint, (value) {
    return _then(_self.copyWith(appliedConfigFingerprint: value));
  });
}/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpHealthReadCopyWith<$Res> get health {

  return $McpHealthReadCopyWith<$Res>(_self.health, (value) {
    return _then(_self.copyWith(health: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpReadHeader].
extension McpReadHeaderPatterns on McpReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _McpReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _McpReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText desiredConfigFingerprint,  ReadText appliedConfigFingerprint,  McpHealthRead health)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpReadHeader() when $default != null:
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText desiredConfigFingerprint,  ReadText appliedConfigFingerprint,  McpHealthRead health)  $default,) {final _that = this;
switch (_that) {
case _McpReadHeader():
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText desiredConfigFingerprint,  ReadText appliedConfigFingerprint,  McpHealthRead health)?  $default,) {final _that = this;
switch (_that) {
case _McpReadHeader() when $default != null:
return $default(_that.desiredConfigFingerprint,_that.appliedConfigFingerprint,_that.health);case _:
  return null;

}
}

}

/// @nodoc


class _McpReadHeader implements McpReadHeader {
  const _McpReadHeader({required this.desiredConfigFingerprint, required this.appliedConfigFingerprint, required this.health});


@override final  ReadText desiredConfigFingerprint;
@override final  ReadText appliedConfigFingerprint;
@override final  McpHealthRead health;

/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpReadHeaderCopyWith<_McpReadHeader> get copyWith => __$McpReadHeaderCopyWithImpl<_McpReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpReadHeader&&(identical(other.desiredConfigFingerprint, desiredConfigFingerprint) || other.desiredConfigFingerprint == desiredConfigFingerprint)&&(identical(other.appliedConfigFingerprint, appliedConfigFingerprint) || other.appliedConfigFingerprint == appliedConfigFingerprint)&&(identical(other.health, health) || other.health == health));
}


@override
int get hashCode {
    return Object.hash(runtimeType,desiredConfigFingerprint,appliedConfigFingerprint,health);
}



}

/// @nodoc
abstract mixin class _$McpReadHeaderCopyWith<$Res> implements $McpReadHeaderCopyWith<$Res> {
  factory _$McpReadHeaderCopyWith(_McpReadHeader value, $Res Function(_McpReadHeader) _then) = __$McpReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadText desiredConfigFingerprint, ReadText appliedConfigFingerprint, McpHealthRead health
});


@override $ReadTextCopyWith<$Res> get desiredConfigFingerprint;@override $ReadTextCopyWith<$Res> get appliedConfigFingerprint;@override $McpHealthReadCopyWith<$Res> get health;

}
/// @nodoc
class __$McpReadHeaderCopyWithImpl<$Res>
    implements _$McpReadHeaderCopyWith<$Res> {
  __$McpReadHeaderCopyWithImpl(this._self, this._then);

  final _McpReadHeader _self;
  final $Res Function(_McpReadHeader) _then;

/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? desiredConfigFingerprint = null,Object? appliedConfigFingerprint = null,Object? health = null,}) {
  return _then(_McpReadHeader(
desiredConfigFingerprint: null == desiredConfigFingerprint ? _self.desiredConfigFingerprint : desiredConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,appliedConfigFingerprint: null == appliedConfigFingerprint ? _self.appliedConfigFingerprint : appliedConfigFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,health: null == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as McpHealthRead,
  ));
}

/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get desiredConfigFingerprint {

  return $ReadTextCopyWith<$Res>(_self.desiredConfigFingerprint, (value) {
    return _then(_self.copyWith(desiredConfigFingerprint: value));
  });
}/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get appliedConfigFingerprint {

  return $ReadTextCopyWith<$Res>(_self.appliedConfigFingerprint, (value) {
    return _then(_self.copyWith(appliedConfigFingerprint: value));
  });
}/// Create a copy of McpReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpHealthReadCopyWith<$Res> get health {

  return $McpHealthReadCopyWith<$Res>(_self.health, (value) {
    return _then(_self.copyWith(health: value));
  });
}
}

/// @nodoc
mixin _$McpServerStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerStateRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $McpServerStateReadCopyWith<$Res>  {
$McpServerStateReadCopyWith(McpServerStateRead _, $Res Function(McpServerStateRead) __);
}


/// Adds pattern-matching-related methods to [McpServerStateRead].
extension McpServerStateReadPatterns on McpServerStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisabledMcpServerStateRead value)?  disabled,TResult Function( MissingCredentialMcpServerStateRead value)?  missingCredential,TResult Function( CheckingMcpServerStateRead value)?  checking,TResult Function( AvailableMcpServerStateRead value)?  available,TResult Function( UnavailableMcpServerStateRead value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisabledMcpServerStateRead() when disabled != null:
return disabled(_that);case MissingCredentialMcpServerStateRead() when missingCredential != null:
return missingCredential(_that);case CheckingMcpServerStateRead() when checking != null:
return checking(_that);case AvailableMcpServerStateRead() when available != null:
return available(_that);case UnavailableMcpServerStateRead() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisabledMcpServerStateRead value)  disabled,required TResult Function( MissingCredentialMcpServerStateRead value)  missingCredential,required TResult Function( CheckingMcpServerStateRead value)  checking,required TResult Function( AvailableMcpServerStateRead value)  available,required TResult Function( UnavailableMcpServerStateRead value)  unavailable,}){
final _that = this;
switch (_that) {
case DisabledMcpServerStateRead():
return disabled(_that);case MissingCredentialMcpServerStateRead():
return missingCredential(_that);case CheckingMcpServerStateRead():
return checking(_that);case AvailableMcpServerStateRead():
return available(_that);case UnavailableMcpServerStateRead():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisabledMcpServerStateRead value)?  disabled,TResult? Function( MissingCredentialMcpServerStateRead value)?  missingCredential,TResult? Function( CheckingMcpServerStateRead value)?  checking,TResult? Function( AvailableMcpServerStateRead value)?  available,TResult? Function( UnavailableMcpServerStateRead value)?  unavailable,}){
final _that = this;
switch (_that) {
case DisabledMcpServerStateRead() when disabled != null:
return disabled(_that);case MissingCredentialMcpServerStateRead() when missingCredential != null:
return missingCredential(_that);case CheckingMcpServerStateRead() when checking != null:
return checking(_that);case AvailableMcpServerStateRead() when available != null:
return available(_that);case UnavailableMcpServerStateRead() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ReadText message)?  disabled,TResult Function( ReadText message)?  missingCredential,TResult Function( ReadText message)?  checking,TResult Function( int checkedAt,  int toolCount)?  available,TResult Function( int checkedAt,  SourceStateErrorRead error)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisabledMcpServerStateRead() when disabled != null:
return disabled(_that.message);case MissingCredentialMcpServerStateRead() when missingCredential != null:
return missingCredential(_that.message);case CheckingMcpServerStateRead() when checking != null:
return checking(_that.message);case AvailableMcpServerStateRead() when available != null:
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerStateRead() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ReadText message)  disabled,required TResult Function( ReadText message)  missingCredential,required TResult Function( ReadText message)  checking,required TResult Function( int checkedAt,  int toolCount)  available,required TResult Function( int checkedAt,  SourceStateErrorRead error)  unavailable,}) {final _that = this;
switch (_that) {
case DisabledMcpServerStateRead():
return disabled(_that.message);case MissingCredentialMcpServerStateRead():
return missingCredential(_that.message);case CheckingMcpServerStateRead():
return checking(_that.message);case AvailableMcpServerStateRead():
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerStateRead():
return unavailable(_that.checkedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ReadText message)?  disabled,TResult? Function( ReadText message)?  missingCredential,TResult? Function( ReadText message)?  checking,TResult? Function( int checkedAt,  int toolCount)?  available,TResult? Function( int checkedAt,  SourceStateErrorRead error)?  unavailable,}) {final _that = this;
switch (_that) {
case DisabledMcpServerStateRead() when disabled != null:
return disabled(_that.message);case MissingCredentialMcpServerStateRead() when missingCredential != null:
return missingCredential(_that.message);case CheckingMcpServerStateRead() when checking != null:
return checking(_that.message);case AvailableMcpServerStateRead() when available != null:
return available(_that.checkedAt,_that.toolCount);case UnavailableMcpServerStateRead() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class DisabledMcpServerStateRead implements McpServerStateRead {
  const DisabledMcpServerStateRead({required this.message});


 final  ReadText message;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledMcpServerStateReadCopyWith<DisabledMcpServerStateRead> get copyWith => _$DisabledMcpServerStateReadCopyWithImpl<DisabledMcpServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledMcpServerStateRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $DisabledMcpServerStateReadCopyWith<$Res> implements $McpServerStateReadCopyWith<$Res> {
  factory $DisabledMcpServerStateReadCopyWith(DisabledMcpServerStateRead value, $Res Function(DisabledMcpServerStateRead) _then) = _$DisabledMcpServerStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$DisabledMcpServerStateReadCopyWithImpl<$Res>
    implements $DisabledMcpServerStateReadCopyWith<$Res> {
  _$DisabledMcpServerStateReadCopyWithImpl(this._self, this._then);

  final DisabledMcpServerStateRead _self;
  final $Res Function(DisabledMcpServerStateRead) _then;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(DisabledMcpServerStateRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class MissingCredentialMcpServerStateRead implements McpServerStateRead {
  const MissingCredentialMcpServerStateRead({required this.message});


 final  ReadText message;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MissingCredentialMcpServerStateReadCopyWith<MissingCredentialMcpServerStateRead> get copyWith => _$MissingCredentialMcpServerStateReadCopyWithImpl<MissingCredentialMcpServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MissingCredentialMcpServerStateRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $MissingCredentialMcpServerStateReadCopyWith<$Res> implements $McpServerStateReadCopyWith<$Res> {
  factory $MissingCredentialMcpServerStateReadCopyWith(MissingCredentialMcpServerStateRead value, $Res Function(MissingCredentialMcpServerStateRead) _then) = _$MissingCredentialMcpServerStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$MissingCredentialMcpServerStateReadCopyWithImpl<$Res>
    implements $MissingCredentialMcpServerStateReadCopyWith<$Res> {
  _$MissingCredentialMcpServerStateReadCopyWithImpl(this._self, this._then);

  final MissingCredentialMcpServerStateRead _self;
  final $Res Function(MissingCredentialMcpServerStateRead) _then;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MissingCredentialMcpServerStateRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class CheckingMcpServerStateRead implements McpServerStateRead {
  const CheckingMcpServerStateRead({required this.message});


 final  ReadText message;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingMcpServerStateReadCopyWith<CheckingMcpServerStateRead> get copyWith => _$CheckingMcpServerStateReadCopyWithImpl<CheckingMcpServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingMcpServerStateRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $CheckingMcpServerStateReadCopyWith<$Res> implements $McpServerStateReadCopyWith<$Res> {
  factory $CheckingMcpServerStateReadCopyWith(CheckingMcpServerStateRead value, $Res Function(CheckingMcpServerStateRead) _then) = _$CheckingMcpServerStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$CheckingMcpServerStateReadCopyWithImpl<$Res>
    implements $CheckingMcpServerStateReadCopyWith<$Res> {
  _$CheckingMcpServerStateReadCopyWithImpl(this._self, this._then);

  final CheckingMcpServerStateRead _self;
  final $Res Function(CheckingMcpServerStateRead) _then;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CheckingMcpServerStateRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class AvailableMcpServerStateRead implements McpServerStateRead {
  const AvailableMcpServerStateRead({required this.checkedAt, required this.toolCount});


 final  int checkedAt;
 final  int toolCount;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableMcpServerStateReadCopyWith<AvailableMcpServerStateRead> get copyWith => _$AvailableMcpServerStateReadCopyWithImpl<AvailableMcpServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableMcpServerStateRead&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.toolCount, toolCount) || other.toolCount == toolCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,toolCount);
}



}

/// @nodoc
abstract mixin class $AvailableMcpServerStateReadCopyWith<$Res> implements $McpServerStateReadCopyWith<$Res> {
  factory $AvailableMcpServerStateReadCopyWith(AvailableMcpServerStateRead value, $Res Function(AvailableMcpServerStateRead) _then) = _$AvailableMcpServerStateReadCopyWithImpl;
@useResult
$Res call({
 int checkedAt, int toolCount
});




}
/// @nodoc
class _$AvailableMcpServerStateReadCopyWithImpl<$Res>
    implements $AvailableMcpServerStateReadCopyWith<$Res> {
  _$AvailableMcpServerStateReadCopyWithImpl(this._self, this._then);

  final AvailableMcpServerStateRead _self;
  final $Res Function(AvailableMcpServerStateRead) _then;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? toolCount = null,}) {
  return _then(AvailableMcpServerStateRead(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,toolCount: null == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class UnavailableMcpServerStateRead implements McpServerStateRead {
  const UnavailableMcpServerStateRead({required this.checkedAt, required this.error});


 final  int checkedAt;
 final  SourceStateErrorRead error;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableMcpServerStateReadCopyWith<UnavailableMcpServerStateRead> get copyWith => _$UnavailableMcpServerStateReadCopyWithImpl<UnavailableMcpServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableMcpServerStateRead&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}



}

/// @nodoc
abstract mixin class $UnavailableMcpServerStateReadCopyWith<$Res> implements $McpServerStateReadCopyWith<$Res> {
  factory $UnavailableMcpServerStateReadCopyWith(UnavailableMcpServerStateRead value, $Res Function(UnavailableMcpServerStateRead) _then) = _$UnavailableMcpServerStateReadCopyWithImpl;
@useResult
$Res call({
 int checkedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$UnavailableMcpServerStateReadCopyWithImpl<$Res>
    implements $UnavailableMcpServerStateReadCopyWith<$Res> {
  _$UnavailableMcpServerStateReadCopyWithImpl(this._self, this._then);

  final UnavailableMcpServerStateRead _self;
  final $Res Function(UnavailableMcpServerStateRead) _then;

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(UnavailableMcpServerStateRead(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of McpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$McpServerRead {

 ReadText get id; ReadText get transport; ReadText get endpoint; ReadText get sourceKind; ReadText get mutationPolicy; McpServerStateRead get state;
/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerReadCopyWith<McpServerRead> get copyWith => _$McpServerReadCopyWithImpl<McpServerRead>(this as McpServerRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpServerRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.sourceKind, _this.sourceKind) || other.sourceKind == _this.sourceKind)&&(identical(other.mutationPolicy, _this.mutationPolicy) || other.mutationPolicy == _this.mutationPolicy)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as McpServerRead;
  return Object.hash(runtimeType,_this.id,_this.transport,_this.endpoint,_this.sourceKind,_this.mutationPolicy,_this.state);
}



}

/// @nodoc
abstract mixin class $McpServerReadCopyWith<$Res>  {
  factory $McpServerReadCopyWith(McpServerRead value, $Res Function(McpServerRead) _then) = _$McpServerReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText transport, ReadText endpoint, ReadText sourceKind, ReadText mutationPolicy, McpServerStateRead state
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get transport;$ReadTextCopyWith<$Res> get endpoint;$ReadTextCopyWith<$Res> get sourceKind;$ReadTextCopyWith<$Res> get mutationPolicy;$McpServerStateReadCopyWith<$Res> get state;

}
/// @nodoc
class _$McpServerReadCopyWithImpl<$Res>
    implements $McpServerReadCopyWith<$Res> {
  _$McpServerReadCopyWithImpl(this._self, this._then);

  final McpServerRead _self;
  final $Res Function(McpServerRead) _then;

/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? sourceKind = null,Object? mutationPolicy = null,Object? state = null,}) {
  return _then(McpServerRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ReadText,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as ReadText,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as ReadText,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as ReadText,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as McpServerStateRead,
  ));
}
/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get transport {

  return $ReadTextCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get endpoint {

  return $ReadTextCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sourceKind {

  return $ReadTextCopyWith<$Res>(_self.sourceKind, (value) {
    return _then(_self.copyWith(sourceKind: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mutationPolicy {

  return $ReadTextCopyWith<$Res>(_self.mutationPolicy, (value) {
    return _then(_self.copyWith(mutationPolicy: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerStateReadCopyWith<$Res> get state {

  return $McpServerStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpServerRead].
extension McpServerReadPatterns on McpServerRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpServerRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpServerRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpServerRead value)  $default,){
final _that = this;
switch (_that) {
case _McpServerRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpServerRead value)?  $default,){
final _that = this;
switch (_that) {
case _McpServerRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText transport,  ReadText endpoint,  ReadText sourceKind,  ReadText mutationPolicy,  McpServerStateRead state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpServerRead() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText transport,  ReadText endpoint,  ReadText sourceKind,  ReadText mutationPolicy,  McpServerStateRead state)  $default,) {final _that = this;
switch (_that) {
case _McpServerRead():
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText transport,  ReadText endpoint,  ReadText sourceKind,  ReadText mutationPolicy,  McpServerStateRead state)?  $default,) {final _that = this;
switch (_that) {
case _McpServerRead() when $default != null:
return $default(_that.id,_that.transport,_that.endpoint,_that.sourceKind,_that.mutationPolicy,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _McpServerRead implements McpServerRead {
  const _McpServerRead({required this.id, required this.transport, required this.endpoint, required this.sourceKind, required this.mutationPolicy, required this.state});


@override final  ReadText id;
@override final  ReadText transport;
@override final  ReadText endpoint;
@override final  ReadText sourceKind;
@override final  ReadText mutationPolicy;
@override final  McpServerStateRead state;

/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpServerReadCopyWith<_McpServerRead> get copyWith => __$McpServerReadCopyWithImpl<_McpServerRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServerRead&&(identical(other.id, id) || other.id == id)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.sourceKind, sourceKind) || other.sourceKind == sourceKind)&&(identical(other.mutationPolicy, mutationPolicy) || other.mutationPolicy == mutationPolicy)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,transport,endpoint,sourceKind,mutationPolicy,state);
}



}

/// @nodoc
abstract mixin class _$McpServerReadCopyWith<$Res> implements $McpServerReadCopyWith<$Res> {
  factory _$McpServerReadCopyWith(_McpServerRead value, $Res Function(_McpServerRead) _then) = __$McpServerReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText transport, ReadText endpoint, ReadText sourceKind, ReadText mutationPolicy, McpServerStateRead state
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get transport;@override $ReadTextCopyWith<$Res> get endpoint;@override $ReadTextCopyWith<$Res> get sourceKind;@override $ReadTextCopyWith<$Res> get mutationPolicy;@override $McpServerStateReadCopyWith<$Res> get state;

}
/// @nodoc
class __$McpServerReadCopyWithImpl<$Res>
    implements _$McpServerReadCopyWith<$Res> {
  __$McpServerReadCopyWithImpl(this._self, this._then);

  final _McpServerRead _self;
  final $Res Function(_McpServerRead) _then;

/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transport = null,Object? endpoint = null,Object? sourceKind = null,Object? mutationPolicy = null,Object? state = null,}) {
  return _then(_McpServerRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ReadText,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as ReadText,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as ReadText,mutationPolicy: null == mutationPolicy ? _self.mutationPolicy : mutationPolicy // ignore: cast_nullable_to_non_nullable
as ReadText,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as McpServerStateRead,
  ));
}

/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get transport {

  return $ReadTextCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get endpoint {

  return $ReadTextCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sourceKind {

  return $ReadTextCopyWith<$Res>(_self.sourceKind, (value) {
    return _then(_self.copyWith(sourceKind: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mutationPolicy {

  return $ReadTextCopyWith<$Res>(_self.mutationPolicy, (value) {
    return _then(_self.copyWith(mutationPolicy: value));
  });
}/// Create a copy of McpServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerStateReadCopyWith<$Res> get state {

  return $McpServerStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$McpEntityRead {

 ProductEntityRef get reference; McpServerRead get value;
/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpEntityReadCopyWith<McpEntityRead> get copyWith => _$McpEntityReadCopyWithImpl<McpEntityRead>(this as McpEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as McpEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $McpEntityReadCopyWith<$Res>  {
  factory $McpEntityReadCopyWith(McpEntityRead value, $Res Function(McpEntityRead) _then) = _$McpEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, McpServerRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$McpServerReadCopyWith<$Res> get value;

}
/// @nodoc
class _$McpEntityReadCopyWithImpl<$Res>
    implements $McpEntityReadCopyWith<$Res> {
  _$McpEntityReadCopyWithImpl(this._self, this._then);

  final McpEntityRead _self;
  final $Res Function(McpEntityRead) _then;

/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(McpEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as McpServerRead,
  ));
}
/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerReadCopyWith<$Res> get value {

  return $McpServerReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpEntityRead].
extension McpEntityReadPatterns on McpEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _McpEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _McpEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  McpServerRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  McpServerRead value)  $default,) {final _that = this;
switch (_that) {
case _McpEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  McpServerRead value)?  $default,) {final _that = this;
switch (_that) {
case _McpEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _McpEntityRead implements McpEntityRead {
  const _McpEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  McpServerRead value;

/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpEntityReadCopyWith<_McpEntityRead> get copyWith => __$McpEntityReadCopyWithImpl<_McpEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$McpEntityReadCopyWith<$Res> implements $McpEntityReadCopyWith<$Res> {
  factory _$McpEntityReadCopyWith(_McpEntityRead value, $Res Function(_McpEntityRead) _then) = __$McpEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, McpServerRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $McpServerReadCopyWith<$Res> get value;

}
/// @nodoc
class __$McpEntityReadCopyWithImpl<$Res>
    implements _$McpEntityReadCopyWith<$Res> {
  __$McpEntityReadCopyWithImpl(this._self, this._then);

  final _McpEntityRead _self;
  final $Res Function(_McpEntityRead) _then;

/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_McpEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as McpServerRead,
  ));
}

/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of McpEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpServerReadCopyWith<$Res> get value {

  return $McpServerReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$McpEntryPage {


/// Create a copy of McpEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpEntryPageCopyWith<McpEntryPage> get copyWith => _$McpEntryPageCopyWithImpl<McpEntryPage>(this as McpEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as McpEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as McpEntryPage;
  return 'McpEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $McpEntryPageCopyWith<$Res>  {
  factory $McpEntryPageCopyWith(McpEntryPage value, $Res Function(McpEntryPage) _then) = _$McpEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$McpEntryPageCopyWithImpl<$Res>
    implements $McpEntryPageCopyWith<$Res> {
  _$McpEntryPageCopyWithImpl(this._self, this._then);

  final McpEntryPage _self;
  final $Res Function(McpEntryPage) _then;

/// Create a copy of McpEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(McpEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of McpEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpEntryPage].
extension McpEntryPagePatterns on McpEntryPage {
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
mixin _$McpServerReadPage {


/// Create a copy of McpServerReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerReadPageCopyWith<McpServerReadPage> get copyWith => _$McpServerReadPageCopyWithImpl<McpServerReadPage>(this as McpServerReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpServerReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as McpServerReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $McpServerReadPageCopyWith<$Res>  {
  factory $McpServerReadPageCopyWith(McpServerReadPage value, $Res Function(McpServerReadPage) _then) = _$McpServerReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<McpServerRead> items, int? nextOffset
});




}
/// @nodoc
class _$McpServerReadPageCopyWithImpl<$Res>
    implements $McpServerReadPageCopyWith<$Res> {
  _$McpServerReadPageCopyWithImpl(this._self, this._then);

  final McpServerReadPage _self;
  final $Res Function(McpServerReadPage) _then;

/// Create a copy of McpServerReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(McpServerReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<McpServerRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpServerReadPage].
extension McpServerReadPagePatterns on McpServerReadPage {
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

// dart format on
