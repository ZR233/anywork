// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeLspActivityRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivityRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspActivityRead()';
}


}

/// @nodoc
class $BridgeLspActivityReadCopyWith<$Res>  {
$BridgeLspActivityReadCopyWith(BridgeLspActivityRead _, $Res Function(BridgeLspActivityRead) __);
}


/// Adds pattern-matching-related methods to [BridgeLspActivityRead].
extension BridgeLspActivityReadPatterns on BridgeLspActivityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspActivityRead_Idle value)?  idle,TResult Function( BridgeLspActivityRead_Busy value)?  busy,TResult Function( BridgeLspActivityRead_Indexing value)?  indexing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle() when idle != null:
return idle(_that);case BridgeLspActivityRead_Busy() when busy != null:
return busy(_that);case BridgeLspActivityRead_Indexing() when indexing != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspActivityRead_Idle value)  idle,required TResult Function( BridgeLspActivityRead_Busy value)  busy,required TResult Function( BridgeLspActivityRead_Indexing value)  indexing,}){
final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle():
return idle(_that);case BridgeLspActivityRead_Busy():
return busy(_that);case BridgeLspActivityRead_Indexing():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspActivityRead_Idle value)?  idle,TResult? Function( BridgeLspActivityRead_Busy value)?  busy,TResult? Function( BridgeLspActivityRead_Indexing value)?  indexing,}){
final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle() when idle != null:
return idle(_that);case BridgeLspActivityRead_Busy() when busy != null:
return busy(_that);case BridgeLspActivityRead_Indexing() when indexing != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)?  busy,TResult Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)?  indexing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle() when idle != null:
return idle();case BridgeLspActivityRead_Busy() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivityRead_Indexing() when indexing != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)  busy,required TResult Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)  indexing,}) {final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle():
return idle();case BridgeLspActivityRead_Busy():
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivityRead_Indexing():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)?  busy,TResult? Function( BridgeReadText? title,  BridgeReadText? message,  int? percentage)?  indexing,}) {final _that = this;
switch (_that) {
case BridgeLspActivityRead_Idle() when idle != null:
return idle();case BridgeLspActivityRead_Busy() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivityRead_Indexing() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspActivityRead_Idle extends BridgeLspActivityRead {
  const BridgeLspActivityRead_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivityRead_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspActivityRead.idle()';
}


}




/// @nodoc


class BridgeLspActivityRead_Busy extends BridgeLspActivityRead {
  const BridgeLspActivityRead_Busy({this.title, this.message, this.percentage}): super._();


 final  BridgeReadText? title;
 final  BridgeReadText? message;
 final  int? percentage;

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspActivityRead_BusyCopyWith<BridgeLspActivityRead_Busy> get copyWith => _$BridgeLspActivityRead_BusyCopyWithImpl<BridgeLspActivityRead_Busy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivityRead_Busy&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}

@override
String toString() {
    return 'BridgeLspActivityRead.busy(title: $title, message: $message, percentage: $percentage)';
}


}

/// @nodoc
abstract mixin class $BridgeLspActivityRead_BusyCopyWith<$Res> implements $BridgeLspActivityReadCopyWith<$Res> {
  factory $BridgeLspActivityRead_BusyCopyWith(BridgeLspActivityRead_Busy value, $Res Function(BridgeLspActivityRead_Busy) _then) = _$BridgeLspActivityRead_BusyCopyWithImpl;
@useResult
$Res call({
 BridgeReadText? title, BridgeReadText? message, int? percentage
});


$BridgeReadTextCopyWith<$Res>? get title;$BridgeReadTextCopyWith<$Res>? get message;

}
/// @nodoc
class _$BridgeLspActivityRead_BusyCopyWithImpl<$Res>
    implements $BridgeLspActivityRead_BusyCopyWith<$Res> {
  _$BridgeLspActivityRead_BusyCopyWithImpl(this._self, this._then);

  final BridgeLspActivityRead_Busy _self;
  final $Res Function(BridgeLspActivityRead_Busy) _then;

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BridgeLspActivityRead_Busy(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get title {
    if (_self.title == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.title!, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get message {
    if (_self.message == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.message!, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeLspActivityRead_Indexing extends BridgeLspActivityRead {
  const BridgeLspActivityRead_Indexing({this.title, this.message, this.percentage}): super._();


 final  BridgeReadText? title;
 final  BridgeReadText? message;
 final  int? percentage;

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspActivityRead_IndexingCopyWith<BridgeLspActivityRead_Indexing> get copyWith => _$BridgeLspActivityRead_IndexingCopyWithImpl<BridgeLspActivityRead_Indexing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivityRead_Indexing&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}

@override
String toString() {
    return 'BridgeLspActivityRead.indexing(title: $title, message: $message, percentage: $percentage)';
}


}

/// @nodoc
abstract mixin class $BridgeLspActivityRead_IndexingCopyWith<$Res> implements $BridgeLspActivityReadCopyWith<$Res> {
  factory $BridgeLspActivityRead_IndexingCopyWith(BridgeLspActivityRead_Indexing value, $Res Function(BridgeLspActivityRead_Indexing) _then) = _$BridgeLspActivityRead_IndexingCopyWithImpl;
@useResult
$Res call({
 BridgeReadText? title, BridgeReadText? message, int? percentage
});


$BridgeReadTextCopyWith<$Res>? get title;$BridgeReadTextCopyWith<$Res>? get message;

}
/// @nodoc
class _$BridgeLspActivityRead_IndexingCopyWithImpl<$Res>
    implements $BridgeLspActivityRead_IndexingCopyWith<$Res> {
  _$BridgeLspActivityRead_IndexingCopyWithImpl(this._self, this._then);

  final BridgeLspActivityRead_Indexing _self;
  final $Res Function(BridgeLspActivityRead_Indexing) _then;

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BridgeLspActivityRead_Indexing(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get title {
    if (_self.title == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.title!, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of BridgeLspActivityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get message {
    if (_self.message == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.message!, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc
mixin _$BridgeLspServerStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerStateRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspServerStateRead()';
}


}

/// @nodoc
class $BridgeLspServerStateReadCopyWith<$Res>  {
$BridgeLspServerStateReadCopyWith(BridgeLspServerStateRead _, $Res Function(BridgeLspServerStateRead) __);
}


/// Adds pattern-matching-related methods to [BridgeLspServerStateRead].
extension BridgeLspServerStateReadPatterns on BridgeLspServerStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspServerStateRead_Checking value)?  checking,TResult Function( BridgeLspServerStateRead_Disabled value)?  disabled,TResult Function( BridgeLspServerStateRead_Unavailable value)?  unavailable,TResult Function( BridgeLspServerStateRead_Available value)?  available,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking() when checking != null:
return checking(_that);case BridgeLspServerStateRead_Disabled() when disabled != null:
return disabled(_that);case BridgeLspServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLspServerStateRead_Available() when available != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspServerStateRead_Checking value)  checking,required TResult Function( BridgeLspServerStateRead_Disabled value)  disabled,required TResult Function( BridgeLspServerStateRead_Unavailable value)  unavailable,required TResult Function( BridgeLspServerStateRead_Available value)  available,}){
final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking():
return checking(_that);case BridgeLspServerStateRead_Disabled():
return disabled(_that);case BridgeLspServerStateRead_Unavailable():
return unavailable(_that);case BridgeLspServerStateRead_Available():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspServerStateRead_Checking value)?  checking,TResult? Function( BridgeLspServerStateRead_Disabled value)?  disabled,TResult? Function( BridgeLspServerStateRead_Unavailable value)?  unavailable,TResult? Function( BridgeLspServerStateRead_Available value)?  available,}){
final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking() when checking != null:
return checking(_that);case BridgeLspServerStateRead_Disabled() when disabled != null:
return disabled(_that);case BridgeLspServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLspServerStateRead_Available() when available != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeReadText message)?  checking,TResult Function( BridgeReadText message)?  disabled,TResult Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)?  unavailable,TResult Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivityRead activity)?  available,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking() when checking != null:
return checking(_that.message);case BridgeLspServerStateRead_Disabled() when disabled != null:
return disabled(_that.message);case BridgeLspServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerStateRead_Available() when available != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeReadText message)  checking,required TResult Function( BridgeReadText message)  disabled,required TResult Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)  unavailable,required TResult Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivityRead activity)  available,}) {final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking():
return checking(_that.message);case BridgeLspServerStateRead_Disabled():
return disabled(_that.message);case BridgeLspServerStateRead_Unavailable():
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerStateRead_Available():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeReadText message)?  checking,TResult? Function( BridgeReadText message)?  disabled,TResult? Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)?  unavailable,TResult? Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivityRead activity)?  available,}) {final _that = this;
switch (_that) {
case BridgeLspServerStateRead_Checking() when checking != null:
return checking(_that.message);case BridgeLspServerStateRead_Disabled() when disabled != null:
return disabled(_that.message);case BridgeLspServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerStateRead_Available() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspServerStateRead_Checking extends BridgeLspServerStateRead {
  const BridgeLspServerStateRead_Checking({required this.message}): super._();


 final  BridgeReadText message;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerStateRead_CheckingCopyWith<BridgeLspServerStateRead_Checking> get copyWith => _$BridgeLspServerStateRead_CheckingCopyWithImpl<BridgeLspServerStateRead_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerStateRead_Checking&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeLspServerStateRead.checking(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerStateRead_CheckingCopyWith<$Res> implements $BridgeLspServerStateReadCopyWith<$Res> {
  factory $BridgeLspServerStateRead_CheckingCopyWith(BridgeLspServerStateRead_Checking value, $Res Function(BridgeLspServerStateRead_Checking) _then) = _$BridgeLspServerStateRead_CheckingCopyWithImpl;
@useResult
$Res call({
 BridgeReadText message
});


$BridgeReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeLspServerStateRead_CheckingCopyWithImpl<$Res>
    implements $BridgeLspServerStateRead_CheckingCopyWith<$Res> {
  _$BridgeLspServerStateRead_CheckingCopyWithImpl(this._self, this._then);

  final BridgeLspServerStateRead_Checking _self;
  final $Res Function(BridgeLspServerStateRead_Checking) _then;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeLspServerStateRead_Checking(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get message {

  return $BridgeReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeLspServerStateRead_Disabled extends BridgeLspServerStateRead {
  const BridgeLspServerStateRead_Disabled({required this.message}): super._();


 final  BridgeReadText message;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerStateRead_DisabledCopyWith<BridgeLspServerStateRead_Disabled> get copyWith => _$BridgeLspServerStateRead_DisabledCopyWithImpl<BridgeLspServerStateRead_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerStateRead_Disabled&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeLspServerStateRead.disabled(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerStateRead_DisabledCopyWith<$Res> implements $BridgeLspServerStateReadCopyWith<$Res> {
  factory $BridgeLspServerStateRead_DisabledCopyWith(BridgeLspServerStateRead_Disabled value, $Res Function(BridgeLspServerStateRead_Disabled) _then) = _$BridgeLspServerStateRead_DisabledCopyWithImpl;
@useResult
$Res call({
 BridgeReadText message
});


$BridgeReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeLspServerStateRead_DisabledCopyWithImpl<$Res>
    implements $BridgeLspServerStateRead_DisabledCopyWith<$Res> {
  _$BridgeLspServerStateRead_DisabledCopyWithImpl(this._self, this._then);

  final BridgeLspServerStateRead_Disabled _self;
  final $Res Function(BridgeLspServerStateRead_Disabled) _then;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeLspServerStateRead_Disabled(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get message {

  return $BridgeReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeLspServerStateRead_Unavailable extends BridgeLspServerStateRead {
  const BridgeLspServerStateRead_Unavailable({required this.checkedAt, required this.error}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerStateRead_UnavailableCopyWith<BridgeLspServerStateRead_Unavailable> get copyWith => _$BridgeLspServerStateRead_UnavailableCopyWithImpl<BridgeLspServerStateRead_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerStateRead_Unavailable&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}

@override
String toString() {
    return 'BridgeLspServerStateRead.unavailable(checkedAt: $checkedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerStateRead_UnavailableCopyWith<$Res> implements $BridgeLspServerStateReadCopyWith<$Res> {
  factory $BridgeLspServerStateRead_UnavailableCopyWith(BridgeLspServerStateRead_Unavailable value, $Res Function(BridgeLspServerStateRead_Unavailable) _then) = _$BridgeLspServerStateRead_UnavailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeLspServerStateRead_UnavailableCopyWithImpl<$Res>
    implements $BridgeLspServerStateRead_UnavailableCopyWith<$Res> {
  _$BridgeLspServerStateRead_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeLspServerStateRead_Unavailable _self;
  final $Res Function(BridgeLspServerStateRead_Unavailable) _then;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(BridgeLspServerStateRead_Unavailable(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

/// @nodoc


class BridgeLspServerStateRead_Available extends BridgeLspServerStateRead {
  const BridgeLspServerStateRead_Available({required this.checkedAt, required this.diagnosticCount, required this.activity}): super._();


 final  PlatformInt64 checkedAt;
 final  BigInt diagnosticCount;
 final  BridgeLspActivityRead activity;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerStateRead_AvailableCopyWith<BridgeLspServerStateRead_Available> get copyWith => _$BridgeLspServerStateRead_AvailableCopyWithImpl<BridgeLspServerStateRead_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerStateRead_Available&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.diagnosticCount, diagnosticCount) || other.diagnosticCount == diagnosticCount)&&(identical(other.activity, activity) || other.activity == activity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,diagnosticCount,activity);
}

@override
String toString() {
    return 'BridgeLspServerStateRead.available(checkedAt: $checkedAt, diagnosticCount: $diagnosticCount, activity: $activity)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerStateRead_AvailableCopyWith<$Res> implements $BridgeLspServerStateReadCopyWith<$Res> {
  factory $BridgeLspServerStateRead_AvailableCopyWith(BridgeLspServerStateRead_Available value, $Res Function(BridgeLspServerStateRead_Available) _then) = _$BridgeLspServerStateRead_AvailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BigInt diagnosticCount, BridgeLspActivityRead activity
});


$BridgeLspActivityReadCopyWith<$Res> get activity;

}
/// @nodoc
class _$BridgeLspServerStateRead_AvailableCopyWithImpl<$Res>
    implements $BridgeLspServerStateRead_AvailableCopyWith<$Res> {
  _$BridgeLspServerStateRead_AvailableCopyWithImpl(this._self, this._then);

  final BridgeLspServerStateRead_Available _self;
  final $Res Function(BridgeLspServerStateRead_Available) _then;

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? diagnosticCount = null,Object? activity = null,}) {
  return _then(BridgeLspServerStateRead_Available(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,diagnosticCount: null == diagnosticCount ? _self.diagnosticCount : diagnosticCount // ignore: cast_nullable_to_non_nullable
as BigInt,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as BridgeLspActivityRead,
  ));
}

/// Create a copy of BridgeLspServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeLspActivityReadCopyWith<$Res> get activity {

  return $BridgeLspActivityReadCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}
}

// dart format on
