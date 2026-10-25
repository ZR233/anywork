// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LspReadHeader {

 TypedListRef get lspServers; TypedListRef get activeLspServers;
/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspReadHeaderCopyWith<LspReadHeader> get copyWith => _$LspReadHeaderCopyWithImpl<LspReadHeader>(this as LspReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspReadHeader&&(identical(other.lspServers, _this.lspServers) || other.lspServers == _this.lspServers)&&(identical(other.activeLspServers, _this.activeLspServers) || other.activeLspServers == _this.activeLspServers));
}


@override
int get hashCode {
  final _this = this as LspReadHeader;
  return Object.hash(runtimeType,_this.lspServers,_this.activeLspServers);
}

@override
String toString() {
  final _this = this as LspReadHeader;
  return 'LspReadHeader(lspServers: ${_this.lspServers}, activeLspServers: ${_this.activeLspServers})';
}


}

/// @nodoc
abstract mixin class $LspReadHeaderCopyWith<$Res>  {
  factory $LspReadHeaderCopyWith(LspReadHeader value, $Res Function(LspReadHeader) _then) = _$LspReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef lspServers, TypedListRef activeLspServers
});


$TypedListRefCopyWith<$Res> get lspServers;$TypedListRefCopyWith<$Res> get activeLspServers;

}
/// @nodoc
class _$LspReadHeaderCopyWithImpl<$Res>
    implements $LspReadHeaderCopyWith<$Res> {
  _$LspReadHeaderCopyWithImpl(this._self, this._then);

  final LspReadHeader _self;
  final $Res Function(LspReadHeader) _then;

/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lspServers = null,Object? activeLspServers = null,}) {
  return _then(LspReadHeader(
lspServers: null == lspServers ? _self.lspServers : lspServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,activeLspServers: null == activeLspServers ? _self.activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get lspServers {

  return $TypedListRefCopyWith<$Res>(_self.lspServers, (value) {
    return _then(_self.copyWith(lspServers: value));
  });
}/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get activeLspServers {

  return $TypedListRefCopyWith<$Res>(_self.activeLspServers, (value) {
    return _then(_self.copyWith(activeLspServers: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspReadHeader].
extension LspReadHeaderPatterns on LspReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _LspReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _LspReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef lspServers,  TypedListRef activeLspServers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspReadHeader() when $default != null:
return $default(_that.lspServers,_that.activeLspServers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef lspServers,  TypedListRef activeLspServers)  $default,) {final _that = this;
switch (_that) {
case _LspReadHeader():
return $default(_that.lspServers,_that.activeLspServers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef lspServers,  TypedListRef activeLspServers)?  $default,) {final _that = this;
switch (_that) {
case _LspReadHeader() when $default != null:
return $default(_that.lspServers,_that.activeLspServers);case _:
  return null;

}
}

}

/// @nodoc


class _LspReadHeader implements LspReadHeader {
  const _LspReadHeader({required this.lspServers, required this.activeLspServers});


@override final  TypedListRef lspServers;
@override final  TypedListRef activeLspServers;

/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspReadHeaderCopyWith<_LspReadHeader> get copyWith => __$LspReadHeaderCopyWithImpl<_LspReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspReadHeader&&(identical(other.lspServers, lspServers) || other.lspServers == lspServers)&&(identical(other.activeLspServers, activeLspServers) || other.activeLspServers == activeLspServers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lspServers,activeLspServers);
}

@override
String toString() {
    return 'LspReadHeader(lspServers: $lspServers, activeLspServers: $activeLspServers)';
}


}

/// @nodoc
abstract mixin class _$LspReadHeaderCopyWith<$Res> implements $LspReadHeaderCopyWith<$Res> {
  factory _$LspReadHeaderCopyWith(_LspReadHeader value, $Res Function(_LspReadHeader) _then) = __$LspReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef lspServers, TypedListRef activeLspServers
});


@override $TypedListRefCopyWith<$Res> get lspServers;@override $TypedListRefCopyWith<$Res> get activeLspServers;

}
/// @nodoc
class __$LspReadHeaderCopyWithImpl<$Res>
    implements _$LspReadHeaderCopyWith<$Res> {
  __$LspReadHeaderCopyWithImpl(this._self, this._then);

  final _LspReadHeader _self;
  final $Res Function(_LspReadHeader) _then;

/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lspServers = null,Object? activeLspServers = null,}) {
  return _then(_LspReadHeader(
lspServers: null == lspServers ? _self.lspServers : lspServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,activeLspServers: null == activeLspServers ? _self.activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get lspServers {

  return $TypedListRefCopyWith<$Res>(_self.lspServers, (value) {
    return _then(_self.copyWith(lspServers: value));
  });
}/// Create a copy of LspReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get activeLspServers {

  return $TypedListRefCopyWith<$Res>(_self.activeLspServers, (value) {
    return _then(_self.copyWith(activeLspServers: value));
  });
}
}

/// @nodoc
mixin _$LspActivityRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspActivityRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $LspActivityReadCopyWith<$Res>  {
$LspActivityReadCopyWith(LspActivityRead _, $Res Function(LspActivityRead) __);
}


/// Adds pattern-matching-related methods to [LspActivityRead].
extension LspActivityReadPatterns on LspActivityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleLspActivityRead value)?  idle,TResult Function( BusyLspActivityRead value)?  busy,TResult Function( IndexingLspActivityRead value)?  indexing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleLspActivityRead() when idle != null:
return idle(_that);case BusyLspActivityRead() when busy != null:
return busy(_that);case IndexingLspActivityRead() when indexing != null:
return indexing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleLspActivityRead value)  idle,required TResult Function( BusyLspActivityRead value)  busy,required TResult Function( IndexingLspActivityRead value)  indexing,}){
final _that = this;
switch (_that) {
case IdleLspActivityRead():
return idle(_that);case BusyLspActivityRead():
return busy(_that);case IndexingLspActivityRead():
return indexing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleLspActivityRead value)?  idle,TResult? Function( BusyLspActivityRead value)?  busy,TResult? Function( IndexingLspActivityRead value)?  indexing,}){
final _that = this;
switch (_that) {
case IdleLspActivityRead() when idle != null:
return idle(_that);case BusyLspActivityRead() when busy != null:
return busy(_that);case IndexingLspActivityRead() when indexing != null:
return indexing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( ReadText? title,  ReadText? message,  int? percentage)?  busy,TResult Function( ReadText? title,  ReadText? message,  int? percentage)?  indexing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleLspActivityRead() when idle != null:
return idle();case BusyLspActivityRead() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivityRead() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( ReadText? title,  ReadText? message,  int? percentage)  busy,required TResult Function( ReadText? title,  ReadText? message,  int? percentage)  indexing,}) {final _that = this;
switch (_that) {
case IdleLspActivityRead():
return idle();case BusyLspActivityRead():
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivityRead():
return indexing(_that.title,_that.message,_that.percentage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( ReadText? title,  ReadText? message,  int? percentage)?  busy,TResult? Function( ReadText? title,  ReadText? message,  int? percentage)?  indexing,}) {final _that = this;
switch (_that) {
case IdleLspActivityRead() when idle != null:
return idle();case BusyLspActivityRead() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivityRead() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class IdleLspActivityRead implements LspActivityRead {
  const IdleLspActivityRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleLspActivityRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BusyLspActivityRead implements LspActivityRead {
  const BusyLspActivityRead({required this.title, required this.message, required this.percentage});


 final  ReadText? title;
 final  ReadText? message;
 final  int? percentage;

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusyLspActivityReadCopyWith<BusyLspActivityRead> get copyWith => _$BusyLspActivityReadCopyWithImpl<BusyLspActivityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BusyLspActivityRead&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}



}

/// @nodoc
abstract mixin class $BusyLspActivityReadCopyWith<$Res> implements $LspActivityReadCopyWith<$Res> {
  factory $BusyLspActivityReadCopyWith(BusyLspActivityRead value, $Res Function(BusyLspActivityRead) _then) = _$BusyLspActivityReadCopyWithImpl;
@useResult
$Res call({
 ReadText? title, ReadText? message, int? percentage
});


$ReadTextCopyWith<$Res>? get title;$ReadTextCopyWith<$Res>? get message;

}
/// @nodoc
class _$BusyLspActivityReadCopyWithImpl<$Res>
    implements $BusyLspActivityReadCopyWith<$Res> {
  _$BusyLspActivityReadCopyWithImpl(this._self, this._then);

  final BusyLspActivityRead _self;
  final $Res Function(BusyLspActivityRead) _then;

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BusyLspActivityRead(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as ReadText?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get title {
    if (_self.title == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.title!, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get message {
    if (_self.message == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.message!, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class IndexingLspActivityRead implements LspActivityRead {
  const IndexingLspActivityRead({required this.title, required this.message, required this.percentage});


 final  ReadText? title;
 final  ReadText? message;
 final  int? percentage;

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IndexingLspActivityReadCopyWith<IndexingLspActivityRead> get copyWith => _$IndexingLspActivityReadCopyWithImpl<IndexingLspActivityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IndexingLspActivityRead&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}



}

/// @nodoc
abstract mixin class $IndexingLspActivityReadCopyWith<$Res> implements $LspActivityReadCopyWith<$Res> {
  factory $IndexingLspActivityReadCopyWith(IndexingLspActivityRead value, $Res Function(IndexingLspActivityRead) _then) = _$IndexingLspActivityReadCopyWithImpl;
@useResult
$Res call({
 ReadText? title, ReadText? message, int? percentage
});


$ReadTextCopyWith<$Res>? get title;$ReadTextCopyWith<$Res>? get message;

}
/// @nodoc
class _$IndexingLspActivityReadCopyWithImpl<$Res>
    implements $IndexingLspActivityReadCopyWith<$Res> {
  _$IndexingLspActivityReadCopyWithImpl(this._self, this._then);

  final IndexingLspActivityRead _self;
  final $Res Function(IndexingLspActivityRead) _then;

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(IndexingLspActivityRead(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as ReadText?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get title {
    if (_self.title == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.title!, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of LspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get message {
    if (_self.message == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.message!, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc
mixin _$LspServerStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspServerStateRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $LspServerStateReadCopyWith<$Res>  {
$LspServerStateReadCopyWith(LspServerStateRead _, $Res Function(LspServerStateRead) __);
}


/// Adds pattern-matching-related methods to [LspServerStateRead].
extension LspServerStateReadPatterns on LspServerStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CheckingLspServerStateRead value)?  checking,TResult Function( DisabledLspServerStateRead value)?  disabled,TResult Function( UnavailableLspServerStateRead value)?  unavailable,TResult Function( AvailableLspServerStateRead value)?  available,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CheckingLspServerStateRead() when checking != null:
return checking(_that);case DisabledLspServerStateRead() when disabled != null:
return disabled(_that);case UnavailableLspServerStateRead() when unavailable != null:
return unavailable(_that);case AvailableLspServerStateRead() when available != null:
return available(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CheckingLspServerStateRead value)  checking,required TResult Function( DisabledLspServerStateRead value)  disabled,required TResult Function( UnavailableLspServerStateRead value)  unavailable,required TResult Function( AvailableLspServerStateRead value)  available,}){
final _that = this;
switch (_that) {
case CheckingLspServerStateRead():
return checking(_that);case DisabledLspServerStateRead():
return disabled(_that);case UnavailableLspServerStateRead():
return unavailable(_that);case AvailableLspServerStateRead():
return available(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CheckingLspServerStateRead value)?  checking,TResult? Function( DisabledLspServerStateRead value)?  disabled,TResult? Function( UnavailableLspServerStateRead value)?  unavailable,TResult? Function( AvailableLspServerStateRead value)?  available,}){
final _that = this;
switch (_that) {
case CheckingLspServerStateRead() when checking != null:
return checking(_that);case DisabledLspServerStateRead() when disabled != null:
return disabled(_that);case UnavailableLspServerStateRead() when unavailable != null:
return unavailable(_that);case AvailableLspServerStateRead() when available != null:
return available(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ReadText message)?  checking,TResult Function( ReadText message)?  disabled,TResult Function( int checkedAt,  SourceStateErrorRead error)?  unavailable,TResult Function( int checkedAt,  int diagnosticCount,  LspActivityRead activity)?  available,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CheckingLspServerStateRead() when checking != null:
return checking(_that.message);case DisabledLspServerStateRead() when disabled != null:
return disabled(_that.message);case UnavailableLspServerStateRead() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerStateRead() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ReadText message)  checking,required TResult Function( ReadText message)  disabled,required TResult Function( int checkedAt,  SourceStateErrorRead error)  unavailable,required TResult Function( int checkedAt,  int diagnosticCount,  LspActivityRead activity)  available,}) {final _that = this;
switch (_that) {
case CheckingLspServerStateRead():
return checking(_that.message);case DisabledLspServerStateRead():
return disabled(_that.message);case UnavailableLspServerStateRead():
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerStateRead():
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ReadText message)?  checking,TResult? Function( ReadText message)?  disabled,TResult? Function( int checkedAt,  SourceStateErrorRead error)?  unavailable,TResult? Function( int checkedAt,  int diagnosticCount,  LspActivityRead activity)?  available,}) {final _that = this;
switch (_that) {
case CheckingLspServerStateRead() when checking != null:
return checking(_that.message);case DisabledLspServerStateRead() when disabled != null:
return disabled(_that.message);case UnavailableLspServerStateRead() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerStateRead() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case _:
  return null;

}
}

}

/// @nodoc


class CheckingLspServerStateRead implements LspServerStateRead {
  const CheckingLspServerStateRead({required this.message});


 final  ReadText message;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingLspServerStateReadCopyWith<CheckingLspServerStateRead> get copyWith => _$CheckingLspServerStateReadCopyWithImpl<CheckingLspServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingLspServerStateRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $CheckingLspServerStateReadCopyWith<$Res> implements $LspServerStateReadCopyWith<$Res> {
  factory $CheckingLspServerStateReadCopyWith(CheckingLspServerStateRead value, $Res Function(CheckingLspServerStateRead) _then) = _$CheckingLspServerStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$CheckingLspServerStateReadCopyWithImpl<$Res>
    implements $CheckingLspServerStateReadCopyWith<$Res> {
  _$CheckingLspServerStateReadCopyWithImpl(this._self, this._then);

  final CheckingLspServerStateRead _self;
  final $Res Function(CheckingLspServerStateRead) _then;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CheckingLspServerStateRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of LspServerStateRead
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


class DisabledLspServerStateRead implements LspServerStateRead {
  const DisabledLspServerStateRead({required this.message});


 final  ReadText message;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledLspServerStateReadCopyWith<DisabledLspServerStateRead> get copyWith => _$DisabledLspServerStateReadCopyWithImpl<DisabledLspServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledLspServerStateRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $DisabledLspServerStateReadCopyWith<$Res> implements $LspServerStateReadCopyWith<$Res> {
  factory $DisabledLspServerStateReadCopyWith(DisabledLspServerStateRead value, $Res Function(DisabledLspServerStateRead) _then) = _$DisabledLspServerStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$DisabledLspServerStateReadCopyWithImpl<$Res>
    implements $DisabledLspServerStateReadCopyWith<$Res> {
  _$DisabledLspServerStateReadCopyWithImpl(this._self, this._then);

  final DisabledLspServerStateRead _self;
  final $Res Function(DisabledLspServerStateRead) _then;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(DisabledLspServerStateRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of LspServerStateRead
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


class UnavailableLspServerStateRead implements LspServerStateRead {
  const UnavailableLspServerStateRead({required this.checkedAt, required this.error});


 final  int checkedAt;
 final  SourceStateErrorRead error;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableLspServerStateReadCopyWith<UnavailableLspServerStateRead> get copyWith => _$UnavailableLspServerStateReadCopyWithImpl<UnavailableLspServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableLspServerStateRead&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}



}

/// @nodoc
abstract mixin class $UnavailableLspServerStateReadCopyWith<$Res> implements $LspServerStateReadCopyWith<$Res> {
  factory $UnavailableLspServerStateReadCopyWith(UnavailableLspServerStateRead value, $Res Function(UnavailableLspServerStateRead) _then) = _$UnavailableLspServerStateReadCopyWithImpl;
@useResult
$Res call({
 int checkedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$UnavailableLspServerStateReadCopyWithImpl<$Res>
    implements $UnavailableLspServerStateReadCopyWith<$Res> {
  _$UnavailableLspServerStateReadCopyWithImpl(this._self, this._then);

  final UnavailableLspServerStateRead _self;
  final $Res Function(UnavailableLspServerStateRead) _then;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(UnavailableLspServerStateRead(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of LspServerStateRead
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


class AvailableLspServerStateRead implements LspServerStateRead {
  const AvailableLspServerStateRead({required this.checkedAt, required this.diagnosticCount, required this.activity});


 final  int checkedAt;
 final  int diagnosticCount;
 final  LspActivityRead activity;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableLspServerStateReadCopyWith<AvailableLspServerStateRead> get copyWith => _$AvailableLspServerStateReadCopyWithImpl<AvailableLspServerStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableLspServerStateRead&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.diagnosticCount, diagnosticCount) || other.diagnosticCount == diagnosticCount)&&(identical(other.activity, activity) || other.activity == activity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,diagnosticCount,activity);
}



}

/// @nodoc
abstract mixin class $AvailableLspServerStateReadCopyWith<$Res> implements $LspServerStateReadCopyWith<$Res> {
  factory $AvailableLspServerStateReadCopyWith(AvailableLspServerStateRead value, $Res Function(AvailableLspServerStateRead) _then) = _$AvailableLspServerStateReadCopyWithImpl;
@useResult
$Res call({
 int checkedAt, int diagnosticCount, LspActivityRead activity
});


$LspActivityReadCopyWith<$Res> get activity;

}
/// @nodoc
class _$AvailableLspServerStateReadCopyWithImpl<$Res>
    implements $AvailableLspServerStateReadCopyWith<$Res> {
  _$AvailableLspServerStateReadCopyWithImpl(this._self, this._then);

  final AvailableLspServerStateRead _self;
  final $Res Function(AvailableLspServerStateRead) _then;

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? diagnosticCount = null,Object? activity = null,}) {
  return _then(AvailableLspServerStateRead(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,diagnosticCount: null == diagnosticCount ? _self.diagnosticCount : diagnosticCount // ignore: cast_nullable_to_non_nullable
as int,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as LspActivityRead,
  ));
}

/// Create a copy of LspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspActivityReadCopyWith<$Res> get activity {

  return $LspActivityReadCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}
}

/// @nodoc
mixin _$LspServerRead {

 ReadText get id; ReadText get displayName; TypedListRef get extensions; TypedListRef get languageIds; LspServerStateRead get state;
/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspServerReadCopyWith<LspServerRead> get copyWith => _$LspServerReadCopyWithImpl<LspServerRead>(this as LspServerRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspServerRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspServerRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.extensions, _this.extensions) || other.extensions == _this.extensions)&&(identical(other.languageIds, _this.languageIds) || other.languageIds == _this.languageIds)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as LspServerRead;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.extensions,_this.languageIds,_this.state);
}



}

/// @nodoc
abstract mixin class $LspServerReadCopyWith<$Res>  {
  factory $LspServerReadCopyWith(LspServerRead value, $Res Function(LspServerRead) _then) = _$LspServerReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText displayName, TypedListRef extensions, TypedListRef languageIds, LspServerStateRead state
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get displayName;$TypedListRefCopyWith<$Res> get extensions;$TypedListRefCopyWith<$Res> get languageIds;$LspServerStateReadCopyWith<$Res> get state;

}
/// @nodoc
class _$LspServerReadCopyWithImpl<$Res>
    implements $LspServerReadCopyWith<$Res> {
  _$LspServerReadCopyWithImpl(this._self, this._then);

  final LspServerRead _self;
  final $Res Function(LspServerRead) _then;

/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? extensions = null,Object? languageIds = null,Object? state = null,}) {
  return _then(LspServerRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,extensions: null == extensions ? _self.extensions : extensions // ignore: cast_nullable_to_non_nullable
as TypedListRef,languageIds: null == languageIds ? _self.languageIds : languageIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LspServerStateRead,
  ));
}
/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get extensions {

  return $TypedListRefCopyWith<$Res>(_self.extensions, (value) {
    return _then(_self.copyWith(extensions: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get languageIds {

  return $TypedListRefCopyWith<$Res>(_self.languageIds, (value) {
    return _then(_self.copyWith(languageIds: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerStateReadCopyWith<$Res> get state {

  return $LspServerStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspServerRead].
extension LspServerReadPatterns on LspServerRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspServerRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspServerRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspServerRead value)  $default,){
final _that = this;
switch (_that) {
case _LspServerRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspServerRead value)?  $default,){
final _that = this;
switch (_that) {
case _LspServerRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName,  TypedListRef extensions,  TypedListRef languageIds,  LspServerStateRead state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspServerRead() when $default != null:
return $default(_that.id,_that.displayName,_that.extensions,_that.languageIds,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName,  TypedListRef extensions,  TypedListRef languageIds,  LspServerStateRead state)  $default,) {final _that = this;
switch (_that) {
case _LspServerRead():
return $default(_that.id,_that.displayName,_that.extensions,_that.languageIds,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText displayName,  TypedListRef extensions,  TypedListRef languageIds,  LspServerStateRead state)?  $default,) {final _that = this;
switch (_that) {
case _LspServerRead() when $default != null:
return $default(_that.id,_that.displayName,_that.extensions,_that.languageIds,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _LspServerRead implements LspServerRead {
  const _LspServerRead({required this.id, required this.displayName, required this.extensions, required this.languageIds, required this.state});


@override final  ReadText id;
@override final  ReadText displayName;
@override final  TypedListRef extensions;
@override final  TypedListRef languageIds;
@override final  LspServerStateRead state;

/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspServerReadCopyWith<_LspServerRead> get copyWith => __$LspServerReadCopyWithImpl<_LspServerRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspServerRead&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.extensions, extensions) || other.extensions == extensions)&&(identical(other.languageIds, languageIds) || other.languageIds == languageIds)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,extensions,languageIds,state);
}



}

/// @nodoc
abstract mixin class _$LspServerReadCopyWith<$Res> implements $LspServerReadCopyWith<$Res> {
  factory _$LspServerReadCopyWith(_LspServerRead value, $Res Function(_LspServerRead) _then) = __$LspServerReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText displayName, TypedListRef extensions, TypedListRef languageIds, LspServerStateRead state
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get displayName;@override $TypedListRefCopyWith<$Res> get extensions;@override $TypedListRefCopyWith<$Res> get languageIds;@override $LspServerStateReadCopyWith<$Res> get state;

}
/// @nodoc
class __$LspServerReadCopyWithImpl<$Res>
    implements _$LspServerReadCopyWith<$Res> {
  __$LspServerReadCopyWithImpl(this._self, this._then);

  final _LspServerRead _self;
  final $Res Function(_LspServerRead) _then;

/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? extensions = null,Object? languageIds = null,Object? state = null,}) {
  return _then(_LspServerRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,extensions: null == extensions ? _self.extensions : extensions // ignore: cast_nullable_to_non_nullable
as TypedListRef,languageIds: null == languageIds ? _self.languageIds : languageIds // ignore: cast_nullable_to_non_nullable
as TypedListRef,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LspServerStateRead,
  ));
}

/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get extensions {

  return $TypedListRefCopyWith<$Res>(_self.extensions, (value) {
    return _then(_self.copyWith(extensions: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get languageIds {

  return $TypedListRefCopyWith<$Res>(_self.languageIds, (value) {
    return _then(_self.copyWith(languageIds: value));
  });
}/// Create a copy of LspServerRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerStateReadCopyWith<$Res> get state {

  return $LspServerStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$LspEntityRead {

 ProductEntityRef get reference; LspServerRead get value;
/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspEntityReadCopyWith<LspEntityRead> get copyWith => _$LspEntityReadCopyWithImpl<LspEntityRead>(this as LspEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as LspEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $LspEntityReadCopyWith<$Res>  {
  factory $LspEntityReadCopyWith(LspEntityRead value, $Res Function(LspEntityRead) _then) = _$LspEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, LspServerRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$LspServerReadCopyWith<$Res> get value;

}
/// @nodoc
class _$LspEntityReadCopyWithImpl<$Res>
    implements $LspEntityReadCopyWith<$Res> {
  _$LspEntityReadCopyWithImpl(this._self, this._then);

  final LspEntityRead _self;
  final $Res Function(LspEntityRead) _then;

/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(LspEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as LspServerRead,
  ));
}
/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerReadCopyWith<$Res> get value {

  return $LspServerReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspEntityRead].
extension LspEntityReadPatterns on LspEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _LspEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _LspEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  LspServerRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspEntityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  LspServerRead value)  $default,) {final _that = this;
switch (_that) {
case _LspEntityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  LspServerRead value)?  $default,) {final _that = this;
switch (_that) {
case _LspEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _LspEntityRead implements LspEntityRead {
  const _LspEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  LspServerRead value;

/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspEntityReadCopyWith<_LspEntityRead> get copyWith => __$LspEntityReadCopyWithImpl<_LspEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$LspEntityReadCopyWith<$Res> implements $LspEntityReadCopyWith<$Res> {
  factory _$LspEntityReadCopyWith(_LspEntityRead value, $Res Function(_LspEntityRead) _then) = __$LspEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, LspServerRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $LspServerReadCopyWith<$Res> get value;

}
/// @nodoc
class __$LspEntityReadCopyWithImpl<$Res>
    implements _$LspEntityReadCopyWith<$Res> {
  __$LspEntityReadCopyWithImpl(this._self, this._then);

  final _LspEntityRead _self;
  final $Res Function(_LspEntityRead) _then;

/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_LspEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as LspServerRead,
  ));
}

/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of LspEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerReadCopyWith<$Res> get value {

  return $LspServerReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$LspEntryPage {


/// Create a copy of LspEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspEntryPageCopyWith<LspEntryPage> get copyWith => _$LspEntryPageCopyWithImpl<LspEntryPage>(this as LspEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as LspEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as LspEntryPage;
  return 'LspEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $LspEntryPageCopyWith<$Res>  {
  factory $LspEntryPageCopyWith(LspEntryPage value, $Res Function(LspEntryPage) _then) = _$LspEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$LspEntryPageCopyWithImpl<$Res>
    implements $LspEntryPageCopyWith<$Res> {
  _$LspEntryPageCopyWithImpl(this._self, this._then);

  final LspEntryPage _self;
  final $Res Function(LspEntryPage) _then;

/// Create a copy of LspEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(LspEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of LspEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspEntryPage].
extension LspEntryPagePatterns on LspEntryPage {
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
mixin _$LspServerReadPage {


/// Create a copy of LspServerReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspServerReadPageCopyWith<LspServerReadPage> get copyWith => _$LspServerReadPageCopyWithImpl<LspServerReadPage>(this as LspServerReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspServerReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspServerReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as LspServerReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $LspServerReadPageCopyWith<$Res>  {
  factory $LspServerReadPageCopyWith(LspServerReadPage value, $Res Function(LspServerReadPage) _then) = _$LspServerReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<LspServerRead> items, int? nextOffset
});




}
/// @nodoc
class _$LspServerReadPageCopyWithImpl<$Res>
    implements $LspServerReadPageCopyWith<$Res> {
  _$LspServerReadPageCopyWithImpl(this._self, this._then);

  final LspServerReadPage _self;
  final $Res Function(LspServerReadPage) _then;

/// Create a copy of LspServerReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(LspServerReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<LspServerRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [LspServerReadPage].
extension LspServerReadPagePatterns on LspServerReadPage {
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
