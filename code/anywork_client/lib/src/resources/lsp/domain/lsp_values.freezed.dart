// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LspActivity {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspActivity);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $LspActivityCopyWith<$Res>  {
$LspActivityCopyWith(LspActivity _, $Res Function(LspActivity) __);
}


/// Adds pattern-matching-related methods to [LspActivity].
extension LspActivityPatterns on LspActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleLspActivity value)?  idle,TResult Function( BusyLspActivity value)?  busy,TResult Function( IndexingLspActivity value)?  indexing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleLspActivity() when idle != null:
return idle(_that);case BusyLspActivity() when busy != null:
return busy(_that);case IndexingLspActivity() when indexing != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleLspActivity value)  idle,required TResult Function( BusyLspActivity value)  busy,required TResult Function( IndexingLspActivity value)  indexing,}){
final _that = this;
switch (_that) {
case IdleLspActivity():
return idle(_that);case BusyLspActivity():
return busy(_that);case IndexingLspActivity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleLspActivity value)?  idle,TResult? Function( BusyLspActivity value)?  busy,TResult? Function( IndexingLspActivity value)?  indexing,}){
final _that = this;
switch (_that) {
case IdleLspActivity() when idle != null:
return idle(_that);case BusyLspActivity() when busy != null:
return busy(_that);case IndexingLspActivity() when indexing != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String? title,  String? message,  int? percentage)?  busy,TResult Function( String? title,  String? message,  int? percentage)?  indexing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleLspActivity() when idle != null:
return idle();case BusyLspActivity() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivity() when indexing != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String? title,  String? message,  int? percentage)  busy,required TResult Function( String? title,  String? message,  int? percentage)  indexing,}) {final _that = this;
switch (_that) {
case IdleLspActivity():
return idle();case BusyLspActivity():
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivity():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String? title,  String? message,  int? percentage)?  busy,TResult? Function( String? title,  String? message,  int? percentage)?  indexing,}) {final _that = this;
switch (_that) {
case IdleLspActivity() when idle != null:
return idle();case BusyLspActivity() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case IndexingLspActivity() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class IdleLspActivity implements LspActivity {
  const IdleLspActivity();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleLspActivity);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BusyLspActivity implements LspActivity {
  const BusyLspActivity({required this.title, required this.message, required this.percentage});


 final  String? title;
 final  String? message;
 final  int? percentage;

/// Create a copy of LspActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusyLspActivityCopyWith<BusyLspActivity> get copyWith => _$BusyLspActivityCopyWithImpl<BusyLspActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BusyLspActivity&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}



}

/// @nodoc
abstract mixin class $BusyLspActivityCopyWith<$Res> implements $LspActivityCopyWith<$Res> {
  factory $BusyLspActivityCopyWith(BusyLspActivity value, $Res Function(BusyLspActivity) _then) = _$BusyLspActivityCopyWithImpl;
@useResult
$Res call({
 String? title, String? message, int? percentage
});




}
/// @nodoc
class _$BusyLspActivityCopyWithImpl<$Res>
    implements $BusyLspActivityCopyWith<$Res> {
  _$BusyLspActivityCopyWithImpl(this._self, this._then);

  final BusyLspActivity _self;
  final $Res Function(BusyLspActivity) _then;

/// Create a copy of LspActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BusyLspActivity(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class IndexingLspActivity implements LspActivity {
  const IndexingLspActivity({required this.title, required this.message, required this.percentage});


 final  String? title;
 final  String? message;
 final  int? percentage;

/// Create a copy of LspActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IndexingLspActivityCopyWith<IndexingLspActivity> get copyWith => _$IndexingLspActivityCopyWithImpl<IndexingLspActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IndexingLspActivity&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}



}

/// @nodoc
abstract mixin class $IndexingLspActivityCopyWith<$Res> implements $LspActivityCopyWith<$Res> {
  factory $IndexingLspActivityCopyWith(IndexingLspActivity value, $Res Function(IndexingLspActivity) _then) = _$IndexingLspActivityCopyWithImpl;
@useResult
$Res call({
 String? title, String? message, int? percentage
});




}
/// @nodoc
class _$IndexingLspActivityCopyWithImpl<$Res>
    implements $IndexingLspActivityCopyWith<$Res> {
  _$IndexingLspActivityCopyWithImpl(this._self, this._then);

  final IndexingLspActivity _self;
  final $Res Function(IndexingLspActivity) _then;

/// Create a copy of LspActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(IndexingLspActivity(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$LspServerState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspServerState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $LspServerStateCopyWith<$Res>  {
$LspServerStateCopyWith(LspServerState _, $Res Function(LspServerState) __);
}


/// Adds pattern-matching-related methods to [LspServerState].
extension LspServerStatePatterns on LspServerState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CheckingLspServerState value)?  checking,TResult Function( DisabledLspServerState value)?  disabled,TResult Function( UnavailableLspServerState value)?  unavailable,TResult Function( AvailableLspServerState value)?  available,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CheckingLspServerState() when checking != null:
return checking(_that);case DisabledLspServerState() when disabled != null:
return disabled(_that);case UnavailableLspServerState() when unavailable != null:
return unavailable(_that);case AvailableLspServerState() when available != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CheckingLspServerState value)  checking,required TResult Function( DisabledLspServerState value)  disabled,required TResult Function( UnavailableLspServerState value)  unavailable,required TResult Function( AvailableLspServerState value)  available,}){
final _that = this;
switch (_that) {
case CheckingLspServerState():
return checking(_that);case DisabledLspServerState():
return disabled(_that);case UnavailableLspServerState():
return unavailable(_that);case AvailableLspServerState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CheckingLspServerState value)?  checking,TResult? Function( DisabledLspServerState value)?  disabled,TResult? Function( UnavailableLspServerState value)?  unavailable,TResult? Function( AvailableLspServerState value)?  available,}){
final _that = this;
switch (_that) {
case CheckingLspServerState() when checking != null:
return checking(_that);case DisabledLspServerState() when disabled != null:
return disabled(_that);case UnavailableLspServerState() when unavailable != null:
return unavailable(_that);case AvailableLspServerState() when available != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  checking,TResult Function( String message)?  disabled,TResult Function( int checkedAt,  SourceStateError error)?  unavailable,TResult Function( int checkedAt,  int diagnosticCount,  LspActivity activity)?  available,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CheckingLspServerState() when checking != null:
return checking(_that.message);case DisabledLspServerState() when disabled != null:
return disabled(_that.message);case UnavailableLspServerState() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerState() when available != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  checking,required TResult Function( String message)  disabled,required TResult Function( int checkedAt,  SourceStateError error)  unavailable,required TResult Function( int checkedAt,  int diagnosticCount,  LspActivity activity)  available,}) {final _that = this;
switch (_that) {
case CheckingLspServerState():
return checking(_that.message);case DisabledLspServerState():
return disabled(_that.message);case UnavailableLspServerState():
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerState():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  checking,TResult? Function( String message)?  disabled,TResult? Function( int checkedAt,  SourceStateError error)?  unavailable,TResult? Function( int checkedAt,  int diagnosticCount,  LspActivity activity)?  available,}) {final _that = this;
switch (_that) {
case CheckingLspServerState() when checking != null:
return checking(_that.message);case DisabledLspServerState() when disabled != null:
return disabled(_that.message);case UnavailableLspServerState() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case AvailableLspServerState() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case _:
  return null;

}
}

}

/// @nodoc


class CheckingLspServerState implements LspServerState {
  const CheckingLspServerState({required this.message});


 final  String message;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingLspServerStateCopyWith<CheckingLspServerState> get copyWith => _$CheckingLspServerStateCopyWithImpl<CheckingLspServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingLspServerState&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $CheckingLspServerStateCopyWith<$Res> implements $LspServerStateCopyWith<$Res> {
  factory $CheckingLspServerStateCopyWith(CheckingLspServerState value, $Res Function(CheckingLspServerState) _then) = _$CheckingLspServerStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CheckingLspServerStateCopyWithImpl<$Res>
    implements $CheckingLspServerStateCopyWith<$Res> {
  _$CheckingLspServerStateCopyWithImpl(this._self, this._then);

  final CheckingLspServerState _self;
  final $Res Function(CheckingLspServerState) _then;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CheckingLspServerState(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DisabledLspServerState implements LspServerState {
  const DisabledLspServerState({required this.message});


 final  String message;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledLspServerStateCopyWith<DisabledLspServerState> get copyWith => _$DisabledLspServerStateCopyWithImpl<DisabledLspServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledLspServerState&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $DisabledLspServerStateCopyWith<$Res> implements $LspServerStateCopyWith<$Res> {
  factory $DisabledLspServerStateCopyWith(DisabledLspServerState value, $Res Function(DisabledLspServerState) _then) = _$DisabledLspServerStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$DisabledLspServerStateCopyWithImpl<$Res>
    implements $DisabledLspServerStateCopyWith<$Res> {
  _$DisabledLspServerStateCopyWithImpl(this._self, this._then);

  final DisabledLspServerState _self;
  final $Res Function(DisabledLspServerState) _then;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(DisabledLspServerState(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UnavailableLspServerState implements LspServerState {
  const UnavailableLspServerState({required this.checkedAt, required this.error});


 final  int checkedAt;
 final  SourceStateError error;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableLspServerStateCopyWith<UnavailableLspServerState> get copyWith => _$UnavailableLspServerStateCopyWithImpl<UnavailableLspServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableLspServerState&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}



}

/// @nodoc
abstract mixin class $UnavailableLspServerStateCopyWith<$Res> implements $LspServerStateCopyWith<$Res> {
  factory $UnavailableLspServerStateCopyWith(UnavailableLspServerState value, $Res Function(UnavailableLspServerState) _then) = _$UnavailableLspServerStateCopyWithImpl;
@useResult
$Res call({
 int checkedAt, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$UnavailableLspServerStateCopyWithImpl<$Res>
    implements $UnavailableLspServerStateCopyWith<$Res> {
  _$UnavailableLspServerStateCopyWithImpl(this._self, this._then);

  final UnavailableLspServerState _self;
  final $Res Function(UnavailableLspServerState) _then;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(UnavailableLspServerState(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class AvailableLspServerState implements LspServerState {
  const AvailableLspServerState({required this.checkedAt, required this.diagnosticCount, required this.activity});


 final  int checkedAt;
 final  int diagnosticCount;
 final  LspActivity activity;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableLspServerStateCopyWith<AvailableLspServerState> get copyWith => _$AvailableLspServerStateCopyWithImpl<AvailableLspServerState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableLspServerState&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.diagnosticCount, diagnosticCount) || other.diagnosticCount == diagnosticCount)&&(identical(other.activity, activity) || other.activity == activity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,diagnosticCount,activity);
}



}

/// @nodoc
abstract mixin class $AvailableLspServerStateCopyWith<$Res> implements $LspServerStateCopyWith<$Res> {
  factory $AvailableLspServerStateCopyWith(AvailableLspServerState value, $Res Function(AvailableLspServerState) _then) = _$AvailableLspServerStateCopyWithImpl;
@useResult
$Res call({
 int checkedAt, int diagnosticCount, LspActivity activity
});


$LspActivityCopyWith<$Res> get activity;

}
/// @nodoc
class _$AvailableLspServerStateCopyWithImpl<$Res>
    implements $AvailableLspServerStateCopyWith<$Res> {
  _$AvailableLspServerStateCopyWithImpl(this._self, this._then);

  final AvailableLspServerState _self;
  final $Res Function(AvailableLspServerState) _then;

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? diagnosticCount = null,Object? activity = null,}) {
  return _then(AvailableLspServerState(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,diagnosticCount: null == diagnosticCount ? _self.diagnosticCount : diagnosticCount // ignore: cast_nullable_to_non_nullable
as int,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as LspActivity,
  ));
}

/// Create a copy of LspServerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspActivityCopyWith<$Res> get activity {

  return $LspActivityCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}
}

/// @nodoc
mixin _$LspServer {

 String get id; String get displayName; List<String> get extensions; List<String> get languageIds; LspServerState get state;
/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspServerCopyWith<LspServer> get copyWith => _$LspServerCopyWithImpl<LspServer>(this as LspServer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspServer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspServer&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&const DeepCollectionEquality().equals(other.extensions, _this.extensions)&&const DeepCollectionEquality().equals(other.languageIds, _this.languageIds)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as LspServer;
  return Object.hash(runtimeType,_this.id,_this.displayName,const DeepCollectionEquality().hash(_this.extensions),const DeepCollectionEquality().hash(_this.languageIds),_this.state);
}



}

/// @nodoc
abstract mixin class $LspServerCopyWith<$Res>  {
  factory $LspServerCopyWith(LspServer value, $Res Function(LspServer) _then) = _$LspServerCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, List<String> extensions, List<String> languageIds, LspServerState state
});


$LspServerStateCopyWith<$Res> get state;

}
/// @nodoc
class _$LspServerCopyWithImpl<$Res>
    implements $LspServerCopyWith<$Res> {
  _$LspServerCopyWithImpl(this._self, this._then);

  final LspServer _self;
  final $Res Function(LspServer) _then;

/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? extensions = null,Object? languageIds = null,Object? state = null,}) {
  return _then(LspServer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,extensions: null == extensions ? _self.extensions : extensions // ignore: cast_nullable_to_non_nullable
as List<String>,languageIds: null == languageIds ? _self.languageIds : languageIds // ignore: cast_nullable_to_non_nullable
as List<String>,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LspServerState,
  ));
}
/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerStateCopyWith<$Res> get state {

  return $LspServerStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspServer].
extension LspServerPatterns on LspServer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspServer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspServer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspServer value)  $default,){
final _that = this;
switch (_that) {
case _LspServer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspServer value)?  $default,){
final _that = this;
switch (_that) {
case _LspServer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  List<String> extensions,  List<String> languageIds,  LspServerState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspServer() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  List<String> extensions,  List<String> languageIds,  LspServerState state)  $default,) {final _that = this;
switch (_that) {
case _LspServer():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  List<String> extensions,  List<String> languageIds,  LspServerState state)?  $default,) {final _that = this;
switch (_that) {
case _LspServer() when $default != null:
return $default(_that.id,_that.displayName,_that.extensions,_that.languageIds,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _LspServer implements LspServer {
  const _LspServer({required this.id, required this.displayName, required  List<String> extensions, required  List<String> languageIds, required this.state}): _extensions = extensions,_languageIds = languageIds;


@override final  String id;
@override final  String displayName;
 final  List<String> _extensions;
@override List<String> get extensions {
  if (_extensions is EqualUnmodifiableListView) return _extensions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_extensions);
}

 final  List<String> _languageIds;
@override List<String> get languageIds {
  if (_languageIds is EqualUnmodifiableListView) return _languageIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_languageIds);
}

@override final  LspServerState state;

/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspServerCopyWith<_LspServer> get copyWith => __$LspServerCopyWithImpl<_LspServer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspServer&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other.extensions, _extensions)&&const DeepCollectionEquality().equals(other.languageIds, _languageIds)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,const DeepCollectionEquality().hash(_extensions),const DeepCollectionEquality().hash(_languageIds),state);
}



}

/// @nodoc
abstract mixin class _$LspServerCopyWith<$Res> implements $LspServerCopyWith<$Res> {
  factory _$LspServerCopyWith(_LspServer value, $Res Function(_LspServer) _then) = __$LspServerCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, List<String> extensions, List<String> languageIds, LspServerState state
});


@override $LspServerStateCopyWith<$Res> get state;

}
/// @nodoc
class __$LspServerCopyWithImpl<$Res>
    implements _$LspServerCopyWith<$Res> {
  __$LspServerCopyWithImpl(this._self, this._then);

  final _LspServer _self;
  final $Res Function(_LspServer) _then;

/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? extensions = null,Object? languageIds = null,Object? state = null,}) {
  return _then(_LspServer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,extensions: null == extensions ? _self._extensions : extensions // ignore: cast_nullable_to_non_nullable
as List<String>,languageIds: null == languageIds ? _self._languageIds : languageIds // ignore: cast_nullable_to_non_nullable
as List<String>,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LspServerState,
  ));
}

/// Create a copy of LspServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspServerStateCopyWith<$Res> get state {

  return $LspServerStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$LspHealth {

 List<LspServer> get lspServers; List<String> get activeLspServers;
/// Create a copy of LspHealth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspHealthCopyWith<LspHealth> get copyWith => _$LspHealthCopyWithImpl<LspHealth>(this as LspHealth, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspHealth;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspHealth&&const DeepCollectionEquality().equals(other.lspServers, _this.lspServers)&&const DeepCollectionEquality().equals(other.activeLspServers, _this.activeLspServers));
}


@override
int get hashCode {
  final _this = this as LspHealth;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.lspServers),const DeepCollectionEquality().hash(_this.activeLspServers));
}

@override
String toString() {
  final _this = this as LspHealth;
  return 'LspHealth(lspServers: ${_this.lspServers}, activeLspServers: ${_this.activeLspServers})';
}


}

/// @nodoc
abstract mixin class $LspHealthCopyWith<$Res>  {
  factory $LspHealthCopyWith(LspHealth value, $Res Function(LspHealth) _then) = _$LspHealthCopyWithImpl;
@useResult
$Res call({
 List<LspServer> lspServers, List<String> activeLspServers
});




}
/// @nodoc
class _$LspHealthCopyWithImpl<$Res>
    implements $LspHealthCopyWith<$Res> {
  _$LspHealthCopyWithImpl(this._self, this._then);

  final LspHealth _self;
  final $Res Function(LspHealth) _then;

/// Create a copy of LspHealth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lspServers = null,Object? activeLspServers = null,}) {
  return _then(LspHealth(
lspServers: null == lspServers ? _self.lspServers : lspServers // ignore: cast_nullable_to_non_nullable
as List<LspServer>,activeLspServers: null == activeLspServers ? _self.activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [LspHealth].
extension LspHealthPatterns on LspHealth {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspHealth value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspHealth() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspHealth value)  $default,){
final _that = this;
switch (_that) {
case _LspHealth():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspHealth value)?  $default,){
final _that = this;
switch (_that) {
case _LspHealth() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LspServer> lspServers,  List<String> activeLspServers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspHealth() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LspServer> lspServers,  List<String> activeLspServers)  $default,) {final _that = this;
switch (_that) {
case _LspHealth():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LspServer> lspServers,  List<String> activeLspServers)?  $default,) {final _that = this;
switch (_that) {
case _LspHealth() when $default != null:
return $default(_that.lspServers,_that.activeLspServers);case _:
  return null;

}
}

}

/// @nodoc


class _LspHealth implements LspHealth {
  const _LspHealth({required  List<LspServer> lspServers, required  List<String> activeLspServers}): _lspServers = lspServers,_activeLspServers = activeLspServers;


 final  List<LspServer> _lspServers;
@override List<LspServer> get lspServers {
  if (_lspServers is EqualUnmodifiableListView) return _lspServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lspServers);
}

 final  List<String> _activeLspServers;
@override List<String> get activeLspServers {
  if (_activeLspServers is EqualUnmodifiableListView) return _activeLspServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeLspServers);
}


/// Create a copy of LspHealth
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspHealthCopyWith<_LspHealth> get copyWith => __$LspHealthCopyWithImpl<_LspHealth>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspHealth&&const DeepCollectionEquality().equals(other.lspServers, _lspServers)&&const DeepCollectionEquality().equals(other.activeLspServers, _activeLspServers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_lspServers),const DeepCollectionEquality().hash(_activeLspServers));
}

@override
String toString() {
    return 'LspHealth(lspServers: $lspServers, activeLspServers: $activeLspServers)';
}


}

/// @nodoc
abstract mixin class _$LspHealthCopyWith<$Res> implements $LspHealthCopyWith<$Res> {
  factory _$LspHealthCopyWith(_LspHealth value, $Res Function(_LspHealth) _then) = __$LspHealthCopyWithImpl;
@override @useResult
$Res call({
 List<LspServer> lspServers, List<String> activeLspServers
});




}
/// @nodoc
class __$LspHealthCopyWithImpl<$Res>
    implements _$LspHealthCopyWith<$Res> {
  __$LspHealthCopyWithImpl(this._self, this._then);

  final _LspHealth _self;
  final $Res Function(_LspHealth) _then;

/// Create a copy of LspHealth
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lspServers = null,Object? activeLspServers = null,}) {
  return _then(_LspHealth(
lspServers: null == lspServers ? _self._lspServers : lspServers // ignore: cast_nullable_to_non_nullable
as List<LspServer>,activeLspServers: null == activeLspServers ? _self._activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
