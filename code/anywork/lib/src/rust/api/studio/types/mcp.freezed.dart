// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMcpExecutionLocation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpExecutionLocation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpExecutionLocation()';
}


}

/// @nodoc
class $BridgeMcpExecutionLocationCopyWith<$Res>  {
$BridgeMcpExecutionLocationCopyWith(BridgeMcpExecutionLocation _, $Res Function(BridgeMcpExecutionLocation) __);
}


/// Adds pattern-matching-related methods to [BridgeMcpExecutionLocation].
extension BridgeMcpExecutionLocationPatterns on BridgeMcpExecutionLocation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMcpExecutionLocation_HostLocal value)?  hostLocal,TResult Function( BridgeMcpExecutionLocation_HostRemoteStreamableHttp value)?  hostRemoteStreamableHttp,TResult Function( BridgeMcpExecutionLocation_SshRemote value)?  sshRemote,TResult Function( BridgeMcpExecutionLocation_SshRemoteStreamableHttp value)?  sshRemoteStreamableHttp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal() when hostLocal != null:
return hostLocal(_that);case BridgeMcpExecutionLocation_HostRemoteStreamableHttp() when hostRemoteStreamableHttp != null:
return hostRemoteStreamableHttp(_that);case BridgeMcpExecutionLocation_SshRemote() when sshRemote != null:
return sshRemote(_that);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp() when sshRemoteStreamableHttp != null:
return sshRemoteStreamableHttp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMcpExecutionLocation_HostLocal value)  hostLocal,required TResult Function( BridgeMcpExecutionLocation_HostRemoteStreamableHttp value)  hostRemoteStreamableHttp,required TResult Function( BridgeMcpExecutionLocation_SshRemote value)  sshRemote,required TResult Function( BridgeMcpExecutionLocation_SshRemoteStreamableHttp value)  sshRemoteStreamableHttp,}){
final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal():
return hostLocal(_that);case BridgeMcpExecutionLocation_HostRemoteStreamableHttp():
return hostRemoteStreamableHttp(_that);case BridgeMcpExecutionLocation_SshRemote():
return sshRemote(_that);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp():
return sshRemoteStreamableHttp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMcpExecutionLocation_HostLocal value)?  hostLocal,TResult? Function( BridgeMcpExecutionLocation_HostRemoteStreamableHttp value)?  hostRemoteStreamableHttp,TResult? Function( BridgeMcpExecutionLocation_SshRemote value)?  sshRemote,TResult? Function( BridgeMcpExecutionLocation_SshRemoteStreamableHttp value)?  sshRemoteStreamableHttp,}){
final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal() when hostLocal != null:
return hostLocal(_that);case BridgeMcpExecutionLocation_HostRemoteStreamableHttp() when hostRemoteStreamableHttp != null:
return hostRemoteStreamableHttp(_that);case BridgeMcpExecutionLocation_SshRemote() when sshRemote != null:
return sshRemote(_that);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp() when sshRemoteStreamableHttp != null:
return sshRemoteStreamableHttp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  hostLocal,TResult Function()?  hostRemoteStreamableHttp,TResult Function( String sshAlias)?  sshRemote,TResult Function( String sshAlias)?  sshRemoteStreamableHttp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal() when hostLocal != null:
return hostLocal();case BridgeMcpExecutionLocation_HostRemoteStreamableHttp() when hostRemoteStreamableHttp != null:
return hostRemoteStreamableHttp();case BridgeMcpExecutionLocation_SshRemote() when sshRemote != null:
return sshRemote(_that.sshAlias);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp() when sshRemoteStreamableHttp != null:
return sshRemoteStreamableHttp(_that.sshAlias);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  hostLocal,required TResult Function()  hostRemoteStreamableHttp,required TResult Function( String sshAlias)  sshRemote,required TResult Function( String sshAlias)  sshRemoteStreamableHttp,}) {final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal():
return hostLocal();case BridgeMcpExecutionLocation_HostRemoteStreamableHttp():
return hostRemoteStreamableHttp();case BridgeMcpExecutionLocation_SshRemote():
return sshRemote(_that.sshAlias);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp():
return sshRemoteStreamableHttp(_that.sshAlias);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  hostLocal,TResult? Function()?  hostRemoteStreamableHttp,TResult? Function( String sshAlias)?  sshRemote,TResult? Function( String sshAlias)?  sshRemoteStreamableHttp,}) {final _that = this;
switch (_that) {
case BridgeMcpExecutionLocation_HostLocal() when hostLocal != null:
return hostLocal();case BridgeMcpExecutionLocation_HostRemoteStreamableHttp() when hostRemoteStreamableHttp != null:
return hostRemoteStreamableHttp();case BridgeMcpExecutionLocation_SshRemote() when sshRemote != null:
return sshRemote(_that.sshAlias);case BridgeMcpExecutionLocation_SshRemoteStreamableHttp() when sshRemoteStreamableHttp != null:
return sshRemoteStreamableHttp(_that.sshAlias);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMcpExecutionLocation_HostLocal extends BridgeMcpExecutionLocation {
  const BridgeMcpExecutionLocation_HostLocal(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpExecutionLocation_HostLocal);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpExecutionLocation.hostLocal()';
}


}




/// @nodoc


class BridgeMcpExecutionLocation_HostRemoteStreamableHttp extends BridgeMcpExecutionLocation {
  const BridgeMcpExecutionLocation_HostRemoteStreamableHttp(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpExecutionLocation_HostRemoteStreamableHttp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpExecutionLocation.hostRemoteStreamableHttp()';
}


}




/// @nodoc


class BridgeMcpExecutionLocation_SshRemote extends BridgeMcpExecutionLocation {
  const BridgeMcpExecutionLocation_SshRemote({required this.sshAlias}): super._();


 final  String sshAlias;

/// Create a copy of BridgeMcpExecutionLocation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpExecutionLocation_SshRemoteCopyWith<BridgeMcpExecutionLocation_SshRemote> get copyWith => _$BridgeMcpExecutionLocation_SshRemoteCopyWithImpl<BridgeMcpExecutionLocation_SshRemote>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpExecutionLocation_SshRemote&&(identical(other.sshAlias, sshAlias) || other.sshAlias == sshAlias));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sshAlias);
}

@override
String toString() {
    return 'BridgeMcpExecutionLocation.sshRemote(sshAlias: $sshAlias)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpExecutionLocation_SshRemoteCopyWith<$Res> implements $BridgeMcpExecutionLocationCopyWith<$Res> {
  factory $BridgeMcpExecutionLocation_SshRemoteCopyWith(BridgeMcpExecutionLocation_SshRemote value, $Res Function(BridgeMcpExecutionLocation_SshRemote) _then) = _$BridgeMcpExecutionLocation_SshRemoteCopyWithImpl;
@useResult
$Res call({
 String sshAlias
});




}
/// @nodoc
class _$BridgeMcpExecutionLocation_SshRemoteCopyWithImpl<$Res>
    implements $BridgeMcpExecutionLocation_SshRemoteCopyWith<$Res> {
  _$BridgeMcpExecutionLocation_SshRemoteCopyWithImpl(this._self, this._then);

  final BridgeMcpExecutionLocation_SshRemote _self;
  final $Res Function(BridgeMcpExecutionLocation_SshRemote) _then;

/// Create a copy of BridgeMcpExecutionLocation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sshAlias = null,}) {
  return _then(BridgeMcpExecutionLocation_SshRemote(
sshAlias: null == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeMcpExecutionLocation_SshRemoteStreamableHttp extends BridgeMcpExecutionLocation {
  const BridgeMcpExecutionLocation_SshRemoteStreamableHttp({required this.sshAlias}): super._();


 final  String sshAlias;

/// Create a copy of BridgeMcpExecutionLocation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWith<BridgeMcpExecutionLocation_SshRemoteStreamableHttp> get copyWith => _$BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWithImpl<BridgeMcpExecutionLocation_SshRemoteStreamableHttp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpExecutionLocation_SshRemoteStreamableHttp&&(identical(other.sshAlias, sshAlias) || other.sshAlias == sshAlias));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sshAlias);
}

@override
String toString() {
    return 'BridgeMcpExecutionLocation.sshRemoteStreamableHttp(sshAlias: $sshAlias)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWith<$Res> implements $BridgeMcpExecutionLocationCopyWith<$Res> {
  factory $BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWith(BridgeMcpExecutionLocation_SshRemoteStreamableHttp value, $Res Function(BridgeMcpExecutionLocation_SshRemoteStreamableHttp) _then) = _$BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWithImpl;
@useResult
$Res call({
 String sshAlias
});




}
/// @nodoc
class _$BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWithImpl<$Res>
    implements $BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWith<$Res> {
  _$BridgeMcpExecutionLocation_SshRemoteStreamableHttpCopyWithImpl(this._self, this._then);

  final BridgeMcpExecutionLocation_SshRemoteStreamableHttp _self;
  final $Res Function(BridgeMcpExecutionLocation_SshRemoteStreamableHttp) _then;

/// Create a copy of BridgeMcpExecutionLocation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sshAlias = null,}) {
  return _then(BridgeMcpExecutionLocation_SshRemoteStreamableHttp(
sshAlias: null == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeMcpScope {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpScope);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpScope()';
}


}

/// @nodoc
class $BridgeMcpScopeCopyWith<$Res>  {
$BridgeMcpScopeCopyWith(BridgeMcpScope _, $Res Function(BridgeMcpScope) __);
}


/// Adds pattern-matching-related methods to [BridgeMcpScope].
extension BridgeMcpScopePatterns on BridgeMcpScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMcpScope_Host value)?  host,TResult Function( BridgeMcpScope_Ssh value)?  ssh,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMcpScope_Host() when host != null:
return host(_that);case BridgeMcpScope_Ssh() when ssh != null:
return ssh(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMcpScope_Host value)  host,required TResult Function( BridgeMcpScope_Ssh value)  ssh,}){
final _that = this;
switch (_that) {
case BridgeMcpScope_Host():
return host(_that);case BridgeMcpScope_Ssh():
return ssh(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMcpScope_Host value)?  host,TResult? Function( BridgeMcpScope_Ssh value)?  ssh,}){
final _that = this;
switch (_that) {
case BridgeMcpScope_Host() when host != null:
return host(_that);case BridgeMcpScope_Ssh() when ssh != null:
return ssh(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  host,TResult Function( String sshAlias)?  ssh,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMcpScope_Host() when host != null:
return host();case BridgeMcpScope_Ssh() when ssh != null:
return ssh(_that.sshAlias);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  host,required TResult Function( String sshAlias)  ssh,}) {final _that = this;
switch (_that) {
case BridgeMcpScope_Host():
return host();case BridgeMcpScope_Ssh():
return ssh(_that.sshAlias);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  host,TResult? Function( String sshAlias)?  ssh,}) {final _that = this;
switch (_that) {
case BridgeMcpScope_Host() when host != null:
return host();case BridgeMcpScope_Ssh() when ssh != null:
return ssh(_that.sshAlias);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMcpScope_Host extends BridgeMcpScope {
  const BridgeMcpScope_Host(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpScope_Host);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpScope.host()';
}


}




/// @nodoc


class BridgeMcpScope_Ssh extends BridgeMcpScope {
  const BridgeMcpScope_Ssh({required this.sshAlias}): super._();


 final  String sshAlias;

/// Create a copy of BridgeMcpScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpScope_SshCopyWith<BridgeMcpScope_Ssh> get copyWith => _$BridgeMcpScope_SshCopyWithImpl<BridgeMcpScope_Ssh>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpScope_Ssh&&(identical(other.sshAlias, sshAlias) || other.sshAlias == sshAlias));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sshAlias);
}

@override
String toString() {
    return 'BridgeMcpScope.ssh(sshAlias: $sshAlias)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpScope_SshCopyWith<$Res> implements $BridgeMcpScopeCopyWith<$Res> {
  factory $BridgeMcpScope_SshCopyWith(BridgeMcpScope_Ssh value, $Res Function(BridgeMcpScope_Ssh) _then) = _$BridgeMcpScope_SshCopyWithImpl;
@useResult
$Res call({
 String sshAlias
});




}
/// @nodoc
class _$BridgeMcpScope_SshCopyWithImpl<$Res>
    implements $BridgeMcpScope_SshCopyWith<$Res> {
  _$BridgeMcpScope_SshCopyWithImpl(this._self, this._then);

  final BridgeMcpScope_Ssh _self;
  final $Res Function(BridgeMcpScope_Ssh) _then;

/// Create a copy of BridgeMcpScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sshAlias = null,}) {
  return _then(BridgeMcpScope_Ssh(
sshAlias: null == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
