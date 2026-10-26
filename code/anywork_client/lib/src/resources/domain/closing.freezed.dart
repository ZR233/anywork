// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'closing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StudioShutdownIssue {

 String get stage; String get code; String get message; bool get retryable; String get correlationId;
/// Create a copy of StudioShutdownIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioShutdownIssueCopyWith<StudioShutdownIssue> get copyWith => _$StudioShutdownIssueCopyWithImpl<StudioShutdownIssue>(this as StudioShutdownIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioShutdownIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioShutdownIssue&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable)&&(identical(other.correlationId, _this.correlationId) || other.correlationId == _this.correlationId));
}


@override
int get hashCode {
  final _this = this as StudioShutdownIssue;
  return Object.hash(runtimeType,_this.stage,_this.code,_this.message,_this.retryable,_this.correlationId);
}



}

/// @nodoc
abstract mixin class $StudioShutdownIssueCopyWith<$Res>  {
  factory $StudioShutdownIssueCopyWith(StudioShutdownIssue value, $Res Function(StudioShutdownIssue) _then) = _$StudioShutdownIssueCopyWithImpl;
@useResult
$Res call({
 String stage, String code, String message, bool retryable, String correlationId
});




}
/// @nodoc
class _$StudioShutdownIssueCopyWithImpl<$Res>
    implements $StudioShutdownIssueCopyWith<$Res> {
  _$StudioShutdownIssueCopyWithImpl(this._self, this._then);

  final StudioShutdownIssue _self;
  final $Res Function(StudioShutdownIssue) _then;

/// Create a copy of StudioShutdownIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stage = null,Object? code = null,Object? message = null,Object? retryable = null,Object? correlationId = null,}) {
  return _then(StudioShutdownIssue(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,correlationId: null == correlationId ? _self.correlationId : correlationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioShutdownIssue].
extension StudioShutdownIssuePatterns on StudioShutdownIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioShutdownIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioShutdownIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioShutdownIssue value)  $default,){
final _that = this;
switch (_that) {
case _StudioShutdownIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioShutdownIssue value)?  $default,){
final _that = this;
switch (_that) {
case _StudioShutdownIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String stage,  String code,  String message,  bool retryable,  String correlationId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioShutdownIssue() when $default != null:
return $default(_that.stage,_that.code,_that.message,_that.retryable,_that.correlationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String stage,  String code,  String message,  bool retryable,  String correlationId)  $default,) {final _that = this;
switch (_that) {
case _StudioShutdownIssue():
return $default(_that.stage,_that.code,_that.message,_that.retryable,_that.correlationId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String stage,  String code,  String message,  bool retryable,  String correlationId)?  $default,) {final _that = this;
switch (_that) {
case _StudioShutdownIssue() when $default != null:
return $default(_that.stage,_that.code,_that.message,_that.retryable,_that.correlationId);case _:
  return null;

}
}

}

/// @nodoc


class _StudioShutdownIssue implements StudioShutdownIssue {
  const _StudioShutdownIssue({required this.stage, required this.code, required this.message, required this.retryable, required this.correlationId});


@override final  String stage;
@override final  String code;
@override final  String message;
@override final  bool retryable;
@override final  String correlationId;

/// Create a copy of StudioShutdownIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioShutdownIssueCopyWith<_StudioShutdownIssue> get copyWith => __$StudioShutdownIssueCopyWithImpl<_StudioShutdownIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioShutdownIssue&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable)&&(identical(other.correlationId, correlationId) || other.correlationId == correlationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stage,code,message,retryable,correlationId);
}



}

/// @nodoc
abstract mixin class _$StudioShutdownIssueCopyWith<$Res> implements $StudioShutdownIssueCopyWith<$Res> {
  factory _$StudioShutdownIssueCopyWith(_StudioShutdownIssue value, $Res Function(_StudioShutdownIssue) _then) = __$StudioShutdownIssueCopyWithImpl;
@override @useResult
$Res call({
 String stage, String code, String message, bool retryable, String correlationId
});




}
/// @nodoc
class __$StudioShutdownIssueCopyWithImpl<$Res>
    implements _$StudioShutdownIssueCopyWith<$Res> {
  __$StudioShutdownIssueCopyWithImpl(this._self, this._then);

  final _StudioShutdownIssue _self;
  final $Res Function(_StudioShutdownIssue) _then;

/// Create a copy of StudioShutdownIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stage = null,Object? code = null,Object? message = null,Object? retryable = null,Object? correlationId = null,}) {
  return _then(_StudioShutdownIssue(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,correlationId: null == correlationId ? _self.correlationId : correlationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FeedCloseIssue {

 StudioShutdownIssue get diagnostic; CleanupRecovery get recovery;
/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeedCloseIssueCopyWith<FeedCloseIssue> get copyWith => _$FeedCloseIssueCopyWithImpl<FeedCloseIssue>(this as FeedCloseIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FeedCloseIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeedCloseIssue&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic)&&(identical(other.recovery, _this.recovery) || other.recovery == _this.recovery));
}


@override
int get hashCode {
  final _this = this as FeedCloseIssue;
  return Object.hash(runtimeType,_this.diagnostic,_this.recovery);
}



}

/// @nodoc
abstract mixin class $FeedCloseIssueCopyWith<$Res>  {
  factory $FeedCloseIssueCopyWith(FeedCloseIssue value, $Res Function(FeedCloseIssue) _then) = _$FeedCloseIssueCopyWithImpl;
@useResult
$Res call({
 StudioShutdownIssue diagnostic, CleanupRecovery recovery
});


$StudioShutdownIssueCopyWith<$Res> get diagnostic;

}
/// @nodoc
class _$FeedCloseIssueCopyWithImpl<$Res>
    implements $FeedCloseIssueCopyWith<$Res> {
  _$FeedCloseIssueCopyWithImpl(this._self, this._then);

  final FeedCloseIssue _self;
  final $Res Function(FeedCloseIssue) _then;

/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? diagnostic = null,Object? recovery = null,}) {
  return _then(FeedCloseIssue(
diagnostic: null == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as StudioShutdownIssue,recovery: null == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as CleanupRecovery,
  ));
}
/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownIssueCopyWith<$Res> get diagnostic {

  return $StudioShutdownIssueCopyWith<$Res>(_self.diagnostic, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}


/// Adds pattern-matching-related methods to [FeedCloseIssue].
extension FeedCloseIssuePatterns on FeedCloseIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FeedCloseIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FeedCloseIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FeedCloseIssue value)  $default,){
final _that = this;
switch (_that) {
case _FeedCloseIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FeedCloseIssue value)?  $default,){
final _that = this;
switch (_that) {
case _FeedCloseIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StudioShutdownIssue diagnostic,  CleanupRecovery recovery)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FeedCloseIssue() when $default != null:
return $default(_that.diagnostic,_that.recovery);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StudioShutdownIssue diagnostic,  CleanupRecovery recovery)  $default,) {final _that = this;
switch (_that) {
case _FeedCloseIssue():
return $default(_that.diagnostic,_that.recovery);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StudioShutdownIssue diagnostic,  CleanupRecovery recovery)?  $default,) {final _that = this;
switch (_that) {
case _FeedCloseIssue() when $default != null:
return $default(_that.diagnostic,_that.recovery);case _:
  return null;

}
}

}

/// @nodoc


class _FeedCloseIssue implements FeedCloseIssue {
  const _FeedCloseIssue({required this.diagnostic, required this.recovery});


@override final  StudioShutdownIssue diagnostic;
@override final  CleanupRecovery recovery;

/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FeedCloseIssueCopyWith<_FeedCloseIssue> get copyWith => __$FeedCloseIssueCopyWithImpl<_FeedCloseIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FeedCloseIssue&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic)&&(identical(other.recovery, recovery) || other.recovery == recovery));
}


@override
int get hashCode {
    return Object.hash(runtimeType,diagnostic,recovery);
}



}

/// @nodoc
abstract mixin class _$FeedCloseIssueCopyWith<$Res> implements $FeedCloseIssueCopyWith<$Res> {
  factory _$FeedCloseIssueCopyWith(_FeedCloseIssue value, $Res Function(_FeedCloseIssue) _then) = __$FeedCloseIssueCopyWithImpl;
@override @useResult
$Res call({
 StudioShutdownIssue diagnostic, CleanupRecovery recovery
});


@override $StudioShutdownIssueCopyWith<$Res> get diagnostic;

}
/// @nodoc
class __$FeedCloseIssueCopyWithImpl<$Res>
    implements _$FeedCloseIssueCopyWith<$Res> {
  __$FeedCloseIssueCopyWithImpl(this._self, this._then);

  final _FeedCloseIssue _self;
  final $Res Function(_FeedCloseIssue) _then;

/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? diagnostic = null,Object? recovery = null,}) {
  return _then(_FeedCloseIssue(
diagnostic: null == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as StudioShutdownIssue,recovery: null == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as CleanupRecovery,
  ));
}

/// Create a copy of FeedCloseIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownIssueCopyWith<$Res> get diagnostic {

  return $StudioShutdownIssueCopyWith<$Res>(_self.diagnostic, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}

/// @nodoc
mixin _$FeedCloseOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FeedCloseOutcome);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $FeedCloseOutcomeCopyWith<$Res>  {
$FeedCloseOutcomeCopyWith(FeedCloseOutcome _, $Res Function(FeedCloseOutcome) __);
}


/// Adds pattern-matching-related methods to [FeedCloseOutcome].
extension FeedCloseOutcomePatterns on FeedCloseOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CleanFeedCloseOutcome value)?  clean,TResult Function( UnresolvedFeedCloseOutcome value)?  unresolved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CleanFeedCloseOutcome() when clean != null:
return clean(_that);case UnresolvedFeedCloseOutcome() when unresolved != null:
return unresolved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CleanFeedCloseOutcome value)  clean,required TResult Function( UnresolvedFeedCloseOutcome value)  unresolved,}){
final _that = this;
switch (_that) {
case CleanFeedCloseOutcome():
return clean(_that);case UnresolvedFeedCloseOutcome():
return unresolved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CleanFeedCloseOutcome value)?  clean,TResult? Function( UnresolvedFeedCloseOutcome value)?  unresolved,}){
final _that = this;
switch (_that) {
case CleanFeedCloseOutcome() when clean != null:
return clean(_that);case UnresolvedFeedCloseOutcome() when unresolved != null:
return unresolved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  clean,TResult Function( List<FeedCloseIssue> issues)?  unresolved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CleanFeedCloseOutcome() when clean != null:
return clean();case UnresolvedFeedCloseOutcome() when unresolved != null:
return unresolved(_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  clean,required TResult Function( List<FeedCloseIssue> issues)  unresolved,}) {final _that = this;
switch (_that) {
case CleanFeedCloseOutcome():
return clean();case UnresolvedFeedCloseOutcome():
return unresolved(_that.issues);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  clean,TResult? Function( List<FeedCloseIssue> issues)?  unresolved,}) {final _that = this;
switch (_that) {
case CleanFeedCloseOutcome() when clean != null:
return clean();case UnresolvedFeedCloseOutcome() when unresolved != null:
return unresolved(_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class CleanFeedCloseOutcome extends FeedCloseOutcome {
  const CleanFeedCloseOutcome(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CleanFeedCloseOutcome);
}


@override
int get hashCode => runtimeType.hashCode;



}





/// @nodoc
mixin _$UnresolvedFeedCloseOutcome {


/// Create a copy of UnresolvedFeedCloseOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnresolvedFeedCloseOutcomeCopyWith<UnresolvedFeedCloseOutcome> get copyWith => _$UnresolvedFeedCloseOutcomeCopyWithImpl<UnresolvedFeedCloseOutcome>(this as UnresolvedFeedCloseOutcome, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UnresolvedFeedCloseOutcome;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnresolvedFeedCloseOutcome&&const DeepCollectionEquality().equals(other.issues, _this.issues));
}


@override
int get hashCode {
  final _this = this as UnresolvedFeedCloseOutcome;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.issues));
}



}

/// @nodoc
abstract mixin class $UnresolvedFeedCloseOutcomeCopyWith<$Res> implements $FeedCloseOutcomeCopyWith<$Res> {
  factory $UnresolvedFeedCloseOutcomeCopyWith(UnresolvedFeedCloseOutcome value, $Res Function(UnresolvedFeedCloseOutcome) _then) = _$UnresolvedFeedCloseOutcomeCopyWithImpl;
@useResult
$Res call({
 List<FeedCloseIssue> issues
});




}
/// @nodoc
class _$UnresolvedFeedCloseOutcomeCopyWithImpl<$Res>
    implements $UnresolvedFeedCloseOutcomeCopyWith<$Res> {
  _$UnresolvedFeedCloseOutcomeCopyWithImpl(this._self, this._then);

  final UnresolvedFeedCloseOutcome _self;
  final $Res Function(UnresolvedFeedCloseOutcome) _then;

/// Create a copy of UnresolvedFeedCloseOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? issues = null,}) {
  return _then(UnresolvedFeedCloseOutcome(
issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<FeedCloseIssue>,
  ));
}

}


/// Adds pattern-matching-related methods to [UnresolvedFeedCloseOutcome].
extension UnresolvedFeedCloseOutcomePatterns on UnresolvedFeedCloseOutcome {
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
mixin _$FeedCloseReport {

 String get feedId; FeedCloseOutcome get outcome;
/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeedCloseReportCopyWith<FeedCloseReport> get copyWith => _$FeedCloseReportCopyWithImpl<FeedCloseReport>(this as FeedCloseReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FeedCloseReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeedCloseReport&&(identical(other.feedId, _this.feedId) || other.feedId == _this.feedId)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome));
}


@override
int get hashCode {
  final _this = this as FeedCloseReport;
  return Object.hash(runtimeType,_this.feedId,_this.outcome);
}



}

/// @nodoc
abstract mixin class $FeedCloseReportCopyWith<$Res>  {
  factory $FeedCloseReportCopyWith(FeedCloseReport value, $Res Function(FeedCloseReport) _then) = _$FeedCloseReportCopyWithImpl;
@useResult
$Res call({
 String feedId, FeedCloseOutcome outcome
});


$FeedCloseOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$FeedCloseReportCopyWithImpl<$Res>
    implements $FeedCloseReportCopyWith<$Res> {
  _$FeedCloseReportCopyWithImpl(this._self, this._then);

  final FeedCloseReport _self;
  final $Res Function(FeedCloseReport) _then;

/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? feedId = null,Object? outcome = null,}) {
  return _then(FeedCloseReport(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as FeedCloseOutcome,
  ));
}
/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FeedCloseOutcomeCopyWith<$Res> get outcome {

  return $FeedCloseOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}


/// Adds pattern-matching-related methods to [FeedCloseReport].
extension FeedCloseReportPatterns on FeedCloseReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FeedCloseReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FeedCloseReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FeedCloseReport value)  $default,){
final _that = this;
switch (_that) {
case _FeedCloseReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FeedCloseReport value)?  $default,){
final _that = this;
switch (_that) {
case _FeedCloseReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String feedId,  FeedCloseOutcome outcome)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FeedCloseReport() when $default != null:
return $default(_that.feedId,_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String feedId,  FeedCloseOutcome outcome)  $default,) {final _that = this;
switch (_that) {
case _FeedCloseReport():
return $default(_that.feedId,_that.outcome);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String feedId,  FeedCloseOutcome outcome)?  $default,) {final _that = this;
switch (_that) {
case _FeedCloseReport() when $default != null:
return $default(_that.feedId,_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class _FeedCloseReport extends FeedCloseReport {
   _FeedCloseReport({required this.feedId, required this.outcome}): super._(feedId: feedId);


@override final  String feedId;
@override final  FeedCloseOutcome outcome;

/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FeedCloseReportCopyWith<_FeedCloseReport> get copyWith => __$FeedCloseReportCopyWithImpl<_FeedCloseReport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FeedCloseReport&&(identical(other.feedId, feedId) || other.feedId == feedId)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,feedId,outcome);
}



}

/// @nodoc
abstract mixin class _$FeedCloseReportCopyWith<$Res> implements $FeedCloseReportCopyWith<$Res> {
  factory _$FeedCloseReportCopyWith(_FeedCloseReport value, $Res Function(_FeedCloseReport) _then) = __$FeedCloseReportCopyWithImpl;
@override @useResult
$Res call({
 String feedId, FeedCloseOutcome outcome
});


@override $FeedCloseOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class __$FeedCloseReportCopyWithImpl<$Res>
    implements _$FeedCloseReportCopyWith<$Res> {
  __$FeedCloseReportCopyWithImpl(this._self, this._then);

  final _FeedCloseReport _self;
  final $Res Function(_FeedCloseReport) _then;

/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? feedId = null,Object? outcome = null,}) {
  return _then(_FeedCloseReport(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as FeedCloseOutcome,
  ));
}

/// Create a copy of FeedCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FeedCloseOutcomeCopyWith<$Res> get outcome {

  return $FeedCloseOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

/// @nodoc
mixin _$UnresolvedResource {


/// Create a copy of UnresolvedResource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnresolvedResourceCopyWith<UnresolvedResource> get copyWith => _$UnresolvedResourceCopyWithImpl<UnresolvedResource>(this as UnresolvedResource, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UnresolvedResource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnresolvedResource&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&const DeepCollectionEquality().equals(other.issues, _this.issues));
}


@override
int get hashCode {
  final _this = this as UnresolvedResource;
  return Object.hash(runtimeType,_this.owner,_this.attemptId,const DeepCollectionEquality().hash(_this.issues));
}



}

/// @nodoc
abstract mixin class $UnresolvedResourceCopyWith<$Res>  {
  factory $UnresolvedResourceCopyWith(UnresolvedResource value, $Res Function(UnresolvedResource) _then) = _$UnresolvedResourceCopyWithImpl;
@useResult
$Res call({
 String owner, AttemptId attemptId, List<FeedCloseIssue> issues
});


$AttemptIdCopyWith<$Res> get attemptId;

}
/// @nodoc
class _$UnresolvedResourceCopyWithImpl<$Res>
    implements $UnresolvedResourceCopyWith<$Res> {
  _$UnresolvedResourceCopyWithImpl(this._self, this._then);

  final UnresolvedResource _self;
  final $Res Function(UnresolvedResource) _then;

/// Create a copy of UnresolvedResource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? owner = null,Object? attemptId = null,Object? issues = null,}) {
  return _then(UnresolvedResource(
owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as AttemptId,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<FeedCloseIssue>,
  ));
}
/// Create a copy of UnresolvedResource
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttemptIdCopyWith<$Res> get attemptId {

  return $AttemptIdCopyWith<$Res>(_self.attemptId, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}
}


/// Adds pattern-matching-related methods to [UnresolvedResource].
extension UnresolvedResourcePatterns on UnresolvedResource {
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
mixin _$CloseReport {


/// Create a copy of CloseReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CloseReportCopyWith<CloseReport> get copyWith => _$CloseReportCopyWithImpl<CloseReport>(this as CloseReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CloseReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CloseReport&&const DeepCollectionEquality().equals(other.unresolved, _this.unresolved));
}


@override
int get hashCode {
  final _this = this as CloseReport;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.unresolved));
}



}

/// @nodoc
abstract mixin class $CloseReportCopyWith<$Res>  {
  factory $CloseReportCopyWith(CloseReport value, $Res Function(CloseReport) _then) = _$CloseReportCopyWithImpl;
@useResult
$Res call({
 List<UnresolvedResource> unresolved
});




}
/// @nodoc
class _$CloseReportCopyWithImpl<$Res>
    implements $CloseReportCopyWith<$Res> {
  _$CloseReportCopyWithImpl(this._self, this._then);

  final CloseReport _self;
  final $Res Function(CloseReport) _then;

/// Create a copy of CloseReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? unresolved = null,}) {
  return _then(CloseReport(
unresolved: null == unresolved ? _self.unresolved : unresolved // ignore: cast_nullable_to_non_nullable
as List<UnresolvedResource>,
  ));
}

}


/// Adds pattern-matching-related methods to [CloseReport].
extension CloseReportPatterns on CloseReport {
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
