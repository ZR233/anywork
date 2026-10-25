// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'failures.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ValidationIssue {

 String get code; String get path; String get message;
/// Create a copy of ValidationIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<ValidationIssue> get copyWith => _$ValidationIssueCopyWithImpl<ValidationIssue>(this as ValidationIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ValidationIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ValidationIssue&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ValidationIssue;
  return Object.hash(runtimeType,_this.code,_this.path,_this.message);
}



}

/// @nodoc
abstract mixin class $ValidationIssueCopyWith<$Res>  {
  factory $ValidationIssueCopyWith(ValidationIssue value, $Res Function(ValidationIssue) _then) = _$ValidationIssueCopyWithImpl;
@useResult
$Res call({
 String code, String path, String message
});




}
/// @nodoc
class _$ValidationIssueCopyWithImpl<$Res>
    implements $ValidationIssueCopyWith<$Res> {
  _$ValidationIssueCopyWithImpl(this._self, this._then);

  final ValidationIssue _self;
  final $Res Function(ValidationIssue) _then;

/// Create a copy of ValidationIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? path = null,Object? message = null,}) {
  return _then(ValidationIssue(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ValidationIssue].
extension ValidationIssuePatterns on ValidationIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ValidationIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ValidationIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ValidationIssue value)  $default,){
final _that = this;
switch (_that) {
case _ValidationIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ValidationIssue value)?  $default,){
final _that = this;
switch (_that) {
case _ValidationIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String path,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ValidationIssue() when $default != null:
return $default(_that.code,_that.path,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String path,  String message)  $default,) {final _that = this;
switch (_that) {
case _ValidationIssue():
return $default(_that.code,_that.path,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String path,  String message)?  $default,) {final _that = this;
switch (_that) {
case _ValidationIssue() when $default != null:
return $default(_that.code,_that.path,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _ValidationIssue implements ValidationIssue {
  const _ValidationIssue({required this.code, required this.path, required this.message});


@override final  String code;
@override final  String path;
@override final  String message;

/// Create a copy of ValidationIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ValidationIssueCopyWith<_ValidationIssue> get copyWith => __$ValidationIssueCopyWithImpl<_ValidationIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ValidationIssue&&(identical(other.code, code) || other.code == code)&&(identical(other.path, path) || other.path == path)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,path,message);
}



}

/// @nodoc
abstract mixin class _$ValidationIssueCopyWith<$Res> implements $ValidationIssueCopyWith<$Res> {
  factory _$ValidationIssueCopyWith(_ValidationIssue value, $Res Function(_ValidationIssue) _then) = __$ValidationIssueCopyWithImpl;
@override @useResult
$Res call({
 String code, String path, String message
});




}
/// @nodoc
class __$ValidationIssueCopyWithImpl<$Res>
    implements _$ValidationIssueCopyWith<$Res> {
  __$ValidationIssueCopyWithImpl(this._self, this._then);

  final _ValidationIssue _self;
  final $Res Function(_ValidationIssue) _then;

/// Create a copy of ValidationIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? path = null,Object? message = null,}) {
  return _then(_ValidationIssue(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StudioFailureDetails {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioFailureDetails);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioFailureDetailsCopyWith<$Res>  {
$StudioFailureDetailsCopyWith(StudioFailureDetails _, $Res Function(StudioFailureDetails) __);
}


/// Adds pattern-matching-related methods to [StudioFailureDetails].
extension StudioFailureDetailsPatterns on StudioFailureDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartupFailureDetails value)?  startup,TResult Function( RevisionFailureDetails value)?  revision,TResult Function( SshAuthenticationFailureDetails value)?  sshAuthentication,TResult Function( ReasonFailureDetails value)?  reason,TResult Function( IdentityFailureDetails value)?  identity,TResult Function( TimelineRevisionFailureDetails value)?  timelineRevision,TResult Function( ValidationFailureDetails value)?  validation,TResult Function( ThreadFailureDetails value)?  thread,TResult Function( ResourceLimitFailureDetails value)?  resourceLimit,TResult Function( BotFailureDetails value)?  bot,TResult Function( CatalogRevisionFailureDetails value)?  catalogRevision,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartupFailureDetails() when startup != null:
return startup(_that);case RevisionFailureDetails() when revision != null:
return revision(_that);case SshAuthenticationFailureDetails() when sshAuthentication != null:
return sshAuthentication(_that);case ReasonFailureDetails() when reason != null:
return reason(_that);case IdentityFailureDetails() when identity != null:
return identity(_that);case TimelineRevisionFailureDetails() when timelineRevision != null:
return timelineRevision(_that);case ValidationFailureDetails() when validation != null:
return validation(_that);case ThreadFailureDetails() when thread != null:
return thread(_that);case ResourceLimitFailureDetails() when resourceLimit != null:
return resourceLimit(_that);case BotFailureDetails() when bot != null:
return bot(_that);case CatalogRevisionFailureDetails() when catalogRevision != null:
return catalogRevision(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartupFailureDetails value)  startup,required TResult Function( RevisionFailureDetails value)  revision,required TResult Function( SshAuthenticationFailureDetails value)  sshAuthentication,required TResult Function( ReasonFailureDetails value)  reason,required TResult Function( IdentityFailureDetails value)  identity,required TResult Function( TimelineRevisionFailureDetails value)  timelineRevision,required TResult Function( ValidationFailureDetails value)  validation,required TResult Function( ThreadFailureDetails value)  thread,required TResult Function( ResourceLimitFailureDetails value)  resourceLimit,required TResult Function( BotFailureDetails value)  bot,required TResult Function( CatalogRevisionFailureDetails value)  catalogRevision,}){
final _that = this;
switch (_that) {
case StartupFailureDetails():
return startup(_that);case RevisionFailureDetails():
return revision(_that);case SshAuthenticationFailureDetails():
return sshAuthentication(_that);case ReasonFailureDetails():
return reason(_that);case IdentityFailureDetails():
return identity(_that);case TimelineRevisionFailureDetails():
return timelineRevision(_that);case ValidationFailureDetails():
return validation(_that);case ThreadFailureDetails():
return thread(_that);case ResourceLimitFailureDetails():
return resourceLimit(_that);case BotFailureDetails():
return bot(_that);case CatalogRevisionFailureDetails():
return catalogRevision(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartupFailureDetails value)?  startup,TResult? Function( RevisionFailureDetails value)?  revision,TResult? Function( SshAuthenticationFailureDetails value)?  sshAuthentication,TResult? Function( ReasonFailureDetails value)?  reason,TResult? Function( IdentityFailureDetails value)?  identity,TResult? Function( TimelineRevisionFailureDetails value)?  timelineRevision,TResult? Function( ValidationFailureDetails value)?  validation,TResult? Function( ThreadFailureDetails value)?  thread,TResult? Function( ResourceLimitFailureDetails value)?  resourceLimit,TResult? Function( BotFailureDetails value)?  bot,TResult? Function( CatalogRevisionFailureDetails value)?  catalogRevision,}){
final _that = this;
switch (_that) {
case StartupFailureDetails() when startup != null:
return startup(_that);case RevisionFailureDetails() when revision != null:
return revision(_that);case SshAuthenticationFailureDetails() when sshAuthentication != null:
return sshAuthentication(_that);case ReasonFailureDetails() when reason != null:
return reason(_that);case IdentityFailureDetails() when identity != null:
return identity(_that);case TimelineRevisionFailureDetails() when timelineRevision != null:
return timelineRevision(_that);case ValidationFailureDetails() when validation != null:
return validation(_that);case ThreadFailureDetails() when thread != null:
return thread(_that);case ResourceLimitFailureDetails() when resourceLimit != null:
return resourceLimit(_that);case BotFailureDetails() when bot != null:
return bot(_that);case CatalogRevisionFailureDetails() when catalogRevision != null:
return catalogRevision(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String step,  StartupFailureKind kind)?  startup,TResult Function( int expected,  int actual)?  revision,TResult Function( bool? passwordOffered)?  sshAuthentication,TResult Function( String reason)?  reason,TResult Function( String identity)?  identity,TResult Function( String itemId,  String field,  int revision)?  timelineRevision,TResult Function( List<ValidationIssue> issues)?  validation,TResult Function( String threadId)?  thread,TResult Function( String resource,  int capacity)?  resourceLimit,TResult Function( String code,  String? platformCode,  String? guidance)?  bot,TResult Function( int revision)?  catalogRevision,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartupFailureDetails() when startup != null:
return startup(_that.step,_that.kind);case RevisionFailureDetails() when revision != null:
return revision(_that.expected,_that.actual);case SshAuthenticationFailureDetails() when sshAuthentication != null:
return sshAuthentication(_that.passwordOffered);case ReasonFailureDetails() when reason != null:
return reason(_that.reason);case IdentityFailureDetails() when identity != null:
return identity(_that.identity);case TimelineRevisionFailureDetails() when timelineRevision != null:
return timelineRevision(_that.itemId,_that.field,_that.revision);case ValidationFailureDetails() when validation != null:
return validation(_that.issues);case ThreadFailureDetails() when thread != null:
return thread(_that.threadId);case ResourceLimitFailureDetails() when resourceLimit != null:
return resourceLimit(_that.resource,_that.capacity);case BotFailureDetails() when bot != null:
return bot(_that.code,_that.platformCode,_that.guidance);case CatalogRevisionFailureDetails() when catalogRevision != null:
return catalogRevision(_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String step,  StartupFailureKind kind)  startup,required TResult Function( int expected,  int actual)  revision,required TResult Function( bool? passwordOffered)  sshAuthentication,required TResult Function( String reason)  reason,required TResult Function( String identity)  identity,required TResult Function( String itemId,  String field,  int revision)  timelineRevision,required TResult Function( List<ValidationIssue> issues)  validation,required TResult Function( String threadId)  thread,required TResult Function( String resource,  int capacity)  resourceLimit,required TResult Function( String code,  String? platformCode,  String? guidance)  bot,required TResult Function( int revision)  catalogRevision,}) {final _that = this;
switch (_that) {
case StartupFailureDetails():
return startup(_that.step,_that.kind);case RevisionFailureDetails():
return revision(_that.expected,_that.actual);case SshAuthenticationFailureDetails():
return sshAuthentication(_that.passwordOffered);case ReasonFailureDetails():
return reason(_that.reason);case IdentityFailureDetails():
return identity(_that.identity);case TimelineRevisionFailureDetails():
return timelineRevision(_that.itemId,_that.field,_that.revision);case ValidationFailureDetails():
return validation(_that.issues);case ThreadFailureDetails():
return thread(_that.threadId);case ResourceLimitFailureDetails():
return resourceLimit(_that.resource,_that.capacity);case BotFailureDetails():
return bot(_that.code,_that.platformCode,_that.guidance);case CatalogRevisionFailureDetails():
return catalogRevision(_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String step,  StartupFailureKind kind)?  startup,TResult? Function( int expected,  int actual)?  revision,TResult? Function( bool? passwordOffered)?  sshAuthentication,TResult? Function( String reason)?  reason,TResult? Function( String identity)?  identity,TResult? Function( String itemId,  String field,  int revision)?  timelineRevision,TResult? Function( List<ValidationIssue> issues)?  validation,TResult? Function( String threadId)?  thread,TResult? Function( String resource,  int capacity)?  resourceLimit,TResult? Function( String code,  String? platformCode,  String? guidance)?  bot,TResult? Function( int revision)?  catalogRevision,}) {final _that = this;
switch (_that) {
case StartupFailureDetails() when startup != null:
return startup(_that.step,_that.kind);case RevisionFailureDetails() when revision != null:
return revision(_that.expected,_that.actual);case SshAuthenticationFailureDetails() when sshAuthentication != null:
return sshAuthentication(_that.passwordOffered);case ReasonFailureDetails() when reason != null:
return reason(_that.reason);case IdentityFailureDetails() when identity != null:
return identity(_that.identity);case TimelineRevisionFailureDetails() when timelineRevision != null:
return timelineRevision(_that.itemId,_that.field,_that.revision);case ValidationFailureDetails() when validation != null:
return validation(_that.issues);case ThreadFailureDetails() when thread != null:
return thread(_that.threadId);case ResourceLimitFailureDetails() when resourceLimit != null:
return resourceLimit(_that.resource,_that.capacity);case BotFailureDetails() when bot != null:
return bot(_that.code,_that.platformCode,_that.guidance);case CatalogRevisionFailureDetails() when catalogRevision != null:
return catalogRevision(_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class StartupFailureDetails extends StudioFailureDetails {
  const StartupFailureDetails({required this.step, required this.kind}): super._();


 final  String step;
 final  StartupFailureKind kind;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupFailureDetailsCopyWith<StartupFailureDetails> get copyWith => _$StartupFailureDetailsCopyWithImpl<StartupFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupFailureDetails&&(identical(other.step, step) || other.step == step)&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,step,kind);
}



}

/// @nodoc
abstract mixin class $StartupFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $StartupFailureDetailsCopyWith(StartupFailureDetails value, $Res Function(StartupFailureDetails) _then) = _$StartupFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String step, StartupFailureKind kind
});




}
/// @nodoc
class _$StartupFailureDetailsCopyWithImpl<$Res>
    implements $StartupFailureDetailsCopyWith<$Res> {
  _$StartupFailureDetailsCopyWithImpl(this._self, this._then);

  final StartupFailureDetails _self;
  final $Res Function(StartupFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? step = null,Object? kind = null,}) {
  return _then(StartupFailureDetails(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as StartupFailureKind,
  ));
}


}

/// @nodoc


class RevisionFailureDetails extends StudioFailureDetails {
  const RevisionFailureDetails({required this.expected, required this.actual}): super._();


 final  int expected;
 final  int actual;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RevisionFailureDetailsCopyWith<RevisionFailureDetails> get copyWith => _$RevisionFailureDetailsCopyWithImpl<RevisionFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RevisionFailureDetails&&(identical(other.expected, expected) || other.expected == expected)&&(identical(other.actual, actual) || other.actual == actual));
}


@override
int get hashCode {
    return Object.hash(runtimeType,expected,actual);
}



}

/// @nodoc
abstract mixin class $RevisionFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $RevisionFailureDetailsCopyWith(RevisionFailureDetails value, $Res Function(RevisionFailureDetails) _then) = _$RevisionFailureDetailsCopyWithImpl;
@useResult
$Res call({
 int expected, int actual
});




}
/// @nodoc
class _$RevisionFailureDetailsCopyWithImpl<$Res>
    implements $RevisionFailureDetailsCopyWith<$Res> {
  _$RevisionFailureDetailsCopyWithImpl(this._self, this._then);

  final RevisionFailureDetails _self;
  final $Res Function(RevisionFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expected = null,Object? actual = null,}) {
  return _then(RevisionFailureDetails(
expected: null == expected ? _self.expected : expected // ignore: cast_nullable_to_non_nullable
as int,actual: null == actual ? _self.actual : actual // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class SshAuthenticationFailureDetails extends StudioFailureDetails {
  const SshAuthenticationFailureDetails({required this.passwordOffered}): super._();


 final  bool? passwordOffered;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshAuthenticationFailureDetailsCopyWith<SshAuthenticationFailureDetails> get copyWith => _$SshAuthenticationFailureDetailsCopyWithImpl<SshAuthenticationFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshAuthenticationFailureDetails&&(identical(other.passwordOffered, passwordOffered) || other.passwordOffered == passwordOffered));
}


@override
int get hashCode {
    return Object.hash(runtimeType,passwordOffered);
}



}

/// @nodoc
abstract mixin class $SshAuthenticationFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $SshAuthenticationFailureDetailsCopyWith(SshAuthenticationFailureDetails value, $Res Function(SshAuthenticationFailureDetails) _then) = _$SshAuthenticationFailureDetailsCopyWithImpl;
@useResult
$Res call({
 bool? passwordOffered
});




}
/// @nodoc
class _$SshAuthenticationFailureDetailsCopyWithImpl<$Res>
    implements $SshAuthenticationFailureDetailsCopyWith<$Res> {
  _$SshAuthenticationFailureDetailsCopyWithImpl(this._self, this._then);

  final SshAuthenticationFailureDetails _self;
  final $Res Function(SshAuthenticationFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? passwordOffered = freezed,}) {
  return _then(SshAuthenticationFailureDetails(
passwordOffered: freezed == passwordOffered ? _self.passwordOffered : passwordOffered // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class ReasonFailureDetails extends StudioFailureDetails {
  const ReasonFailureDetails({required this.reason}): super._();


 final  String reason;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReasonFailureDetailsCopyWith<ReasonFailureDetails> get copyWith => _$ReasonFailureDetailsCopyWithImpl<ReasonFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReasonFailureDetails&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}



}

/// @nodoc
abstract mixin class $ReasonFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $ReasonFailureDetailsCopyWith(ReasonFailureDetails value, $Res Function(ReasonFailureDetails) _then) = _$ReasonFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ReasonFailureDetailsCopyWithImpl<$Res>
    implements $ReasonFailureDetailsCopyWith<$Res> {
  _$ReasonFailureDetailsCopyWithImpl(this._self, this._then);

  final ReasonFailureDetails _self;
  final $Res Function(ReasonFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ReasonFailureDetails(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IdentityFailureDetails extends StudioFailureDetails {
  const IdentityFailureDetails({required this.identity}): super._();


 final  String identity;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdentityFailureDetailsCopyWith<IdentityFailureDetails> get copyWith => _$IdentityFailureDetailsCopyWithImpl<IdentityFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdentityFailureDetails&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity);
}



}

/// @nodoc
abstract mixin class $IdentityFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $IdentityFailureDetailsCopyWith(IdentityFailureDetails value, $Res Function(IdentityFailureDetails) _then) = _$IdentityFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String identity
});




}
/// @nodoc
class _$IdentityFailureDetailsCopyWithImpl<$Res>
    implements $IdentityFailureDetailsCopyWith<$Res> {
  _$IdentityFailureDetailsCopyWithImpl(this._self, this._then);

  final IdentityFailureDetails _self;
  final $Res Function(IdentityFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,}) {
  return _then(IdentityFailureDetails(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TimelineRevisionFailureDetails extends StudioFailureDetails {
  const TimelineRevisionFailureDetails({required this.itemId, required this.field, required this.revision}): super._();


 final  String itemId;
 final  String field;
 final  int revision;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineRevisionFailureDetailsCopyWith<TimelineRevisionFailureDetails> get copyWith => _$TimelineRevisionFailureDetailsCopyWithImpl<TimelineRevisionFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineRevisionFailureDetails&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.field, field) || other.field == field)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId,field,revision);
}



}

/// @nodoc
abstract mixin class $TimelineRevisionFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $TimelineRevisionFailureDetailsCopyWith(TimelineRevisionFailureDetails value, $Res Function(TimelineRevisionFailureDetails) _then) = _$TimelineRevisionFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String itemId, String field, int revision
});




}
/// @nodoc
class _$TimelineRevisionFailureDetailsCopyWithImpl<$Res>
    implements $TimelineRevisionFailureDetailsCopyWith<$Res> {
  _$TimelineRevisionFailureDetailsCopyWithImpl(this._self, this._then);

  final TimelineRevisionFailureDetails _self;
  final $Res Function(TimelineRevisionFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,Object? field = null,Object? revision = null,}) {
  return _then(TimelineRevisionFailureDetails(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc


class ThreadFailureDetails extends StudioFailureDetails {
  const ThreadFailureDetails({required this.threadId}): super._();


 final  String threadId;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadFailureDetailsCopyWith<ThreadFailureDetails> get copyWith => _$ThreadFailureDetailsCopyWithImpl<ThreadFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFailureDetails&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}



}

/// @nodoc
abstract mixin class $ThreadFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $ThreadFailureDetailsCopyWith(ThreadFailureDetails value, $Res Function(ThreadFailureDetails) _then) = _$ThreadFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$ThreadFailureDetailsCopyWithImpl<$Res>
    implements $ThreadFailureDetailsCopyWith<$Res> {
  _$ThreadFailureDetailsCopyWithImpl(this._self, this._then);

  final ThreadFailureDetails _self;
  final $Res Function(ThreadFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(ThreadFailureDetails(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ResourceLimitFailureDetails extends StudioFailureDetails {
  const ResourceLimitFailureDetails({required this.resource, required this.capacity}): super._();


 final  String resource;
 final  int capacity;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceLimitFailureDetailsCopyWith<ResourceLimitFailureDetails> get copyWith => _$ResourceLimitFailureDetailsCopyWithImpl<ResourceLimitFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceLimitFailureDetails&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.capacity, capacity) || other.capacity == capacity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,resource,capacity);
}



}

/// @nodoc
abstract mixin class $ResourceLimitFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $ResourceLimitFailureDetailsCopyWith(ResourceLimitFailureDetails value, $Res Function(ResourceLimitFailureDetails) _then) = _$ResourceLimitFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String resource, int capacity
});




}
/// @nodoc
class _$ResourceLimitFailureDetailsCopyWithImpl<$Res>
    implements $ResourceLimitFailureDetailsCopyWith<$Res> {
  _$ResourceLimitFailureDetailsCopyWithImpl(this._self, this._then);

  final ResourceLimitFailureDetails _self;
  final $Res Function(ResourceLimitFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? capacity = null,}) {
  return _then(ResourceLimitFailureDetails(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as String,capacity: null == capacity ? _self.capacity : capacity // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BotFailureDetails extends StudioFailureDetails {
  const BotFailureDetails({required this.code, required this.platformCode, required this.guidance}): super._();


 final  String code;
 final  String? platformCode;
 final  String? guidance;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotFailureDetailsCopyWith<BotFailureDetails> get copyWith => _$BotFailureDetailsCopyWithImpl<BotFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotFailureDetails&&(identical(other.code, code) || other.code == code)&&(identical(other.platformCode, platformCode) || other.platformCode == platformCode)&&(identical(other.guidance, guidance) || other.guidance == guidance));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,platformCode,guidance);
}



}

/// @nodoc
abstract mixin class $BotFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $BotFailureDetailsCopyWith(BotFailureDetails value, $Res Function(BotFailureDetails) _then) = _$BotFailureDetailsCopyWithImpl;
@useResult
$Res call({
 String code, String? platformCode, String? guidance
});




}
/// @nodoc
class _$BotFailureDetailsCopyWithImpl<$Res>
    implements $BotFailureDetailsCopyWith<$Res> {
  _$BotFailureDetailsCopyWithImpl(this._self, this._then);

  final BotFailureDetails _self;
  final $Res Function(BotFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? platformCode = freezed,Object? guidance = freezed,}) {
  return _then(BotFailureDetails(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,platformCode: freezed == platformCode ? _self.platformCode : platformCode // ignore: cast_nullable_to_non_nullable
as String?,guidance: freezed == guidance ? _self.guidance : guidance // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class CatalogRevisionFailureDetails extends StudioFailureDetails {
  const CatalogRevisionFailureDetails({required this.revision}): super._();


 final  int revision;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogRevisionFailureDetailsCopyWith<CatalogRevisionFailureDetails> get copyWith => _$CatalogRevisionFailureDetailsCopyWithImpl<CatalogRevisionFailureDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogRevisionFailureDetails&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision);
}



}

/// @nodoc
abstract mixin class $CatalogRevisionFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $CatalogRevisionFailureDetailsCopyWith(CatalogRevisionFailureDetails value, $Res Function(CatalogRevisionFailureDetails) _then) = _$CatalogRevisionFailureDetailsCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$CatalogRevisionFailureDetailsCopyWithImpl<$Res>
    implements $CatalogRevisionFailureDetailsCopyWith<$Res> {
  _$CatalogRevisionFailureDetailsCopyWithImpl(this._self, this._then);

  final CatalogRevisionFailureDetails _self;
  final $Res Function(CatalogRevisionFailureDetails) _then;

/// Create a copy of StudioFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,}) {
  return _then(CatalogRevisionFailureDetails(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ValidationFailureDetails {


/// Create a copy of ValidationFailureDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ValidationFailureDetailsCopyWith<ValidationFailureDetails> get copyWith => _$ValidationFailureDetailsCopyWithImpl<ValidationFailureDetails>(this as ValidationFailureDetails, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ValidationFailureDetails;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ValidationFailureDetails&&const DeepCollectionEquality().equals(other.issues, _this.issues));
}


@override
int get hashCode {
  final _this = this as ValidationFailureDetails;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.issues));
}



}

/// @nodoc
abstract mixin class $ValidationFailureDetailsCopyWith<$Res> implements $StudioFailureDetailsCopyWith<$Res> {
  factory $ValidationFailureDetailsCopyWith(ValidationFailureDetails value, $Res Function(ValidationFailureDetails) _then) = _$ValidationFailureDetailsCopyWithImpl;
@useResult
$Res call({
 List<ValidationIssue> issues
});




}
/// @nodoc
class _$ValidationFailureDetailsCopyWithImpl<$Res>
    implements $ValidationFailureDetailsCopyWith<$Res> {
  _$ValidationFailureDetailsCopyWithImpl(this._self, this._then);

  final ValidationFailureDetails _self;
  final $Res Function(ValidationFailureDetails) _then;

/// Create a copy of ValidationFailureDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? issues = null,}) {
  return _then(ValidationFailureDetails(
issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<ValidationIssue>,
  ));
}

}


/// Adds pattern-matching-related methods to [ValidationFailureDetails].
extension ValidationFailureDetailsPatterns on ValidationFailureDetails {
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
mixin _$StudioFailure {

 StudioFailureCode get code; String get message; bool get retryable; String get correlationId; StudioFailureDetails? get details;
/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<StudioFailure> get copyWith => _$StudioFailureCopyWithImpl<StudioFailure>(this as StudioFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable)&&(identical(other.correlationId, _this.correlationId) || other.correlationId == _this.correlationId)&&(identical(other.details, _this.details) || other.details == _this.details));
}


@override
int get hashCode {
  final _this = this as StudioFailure;
  return Object.hash(runtimeType,_this.code,_this.message,_this.retryable,_this.correlationId,_this.details);
}



}

/// @nodoc
abstract mixin class $StudioFailureCopyWith<$Res>  {
  factory $StudioFailureCopyWith(StudioFailure value, $Res Function(StudioFailure) _then) = _$StudioFailureCopyWithImpl;
@useResult
$Res call({
 StudioFailureCode code, String message, bool retryable, String correlationId, StudioFailureDetails? details
});


$StudioFailureDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class _$StudioFailureCopyWithImpl<$Res>
    implements $StudioFailureCopyWith<$Res> {
  _$StudioFailureCopyWithImpl(this._self, this._then);

  final StudioFailure _self;
  final $Res Function(StudioFailure) _then;

/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? correlationId = null,Object? details = freezed,}) {
  return _then(StudioFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as StudioFailureCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,correlationId: null == correlationId ? _self.correlationId : correlationId // ignore: cast_nullable_to_non_nullable
as String,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as StudioFailureDetails?,
  ));
}
/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureDetailsCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $StudioFailureDetailsCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioFailure].
extension StudioFailurePatterns on StudioFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioFailure value)  $default,){
final _that = this;
switch (_that) {
case _StudioFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioFailure value)?  $default,){
final _that = this;
switch (_that) {
case _StudioFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StudioFailureCode code,  String message,  bool retryable,  String correlationId,  StudioFailureDetails? details)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioFailure() when $default != null:
return $default(_that.code,_that.message,_that.retryable,_that.correlationId,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StudioFailureCode code,  String message,  bool retryable,  String correlationId,  StudioFailureDetails? details)  $default,) {final _that = this;
switch (_that) {
case _StudioFailure():
return $default(_that.code,_that.message,_that.retryable,_that.correlationId,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StudioFailureCode code,  String message,  bool retryable,  String correlationId,  StudioFailureDetails? details)?  $default,) {final _that = this;
switch (_that) {
case _StudioFailure() when $default != null:
return $default(_that.code,_that.message,_that.retryable,_that.correlationId,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _StudioFailure extends StudioFailure {
  const _StudioFailure({required this.code, required this.message, required this.retryable, required this.correlationId, this.details}): super._();


@override final  StudioFailureCode code;
@override final  String message;
@override final  bool retryable;
@override final  String correlationId;
@override final  StudioFailureDetails? details;

/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioFailureCopyWith<_StudioFailure> get copyWith => __$StudioFailureCopyWithImpl<_StudioFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable)&&(identical(other.correlationId, correlationId) || other.correlationId == correlationId)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable,correlationId,details);
}



}

/// @nodoc
abstract mixin class _$StudioFailureCopyWith<$Res> implements $StudioFailureCopyWith<$Res> {
  factory _$StudioFailureCopyWith(_StudioFailure value, $Res Function(_StudioFailure) _then) = __$StudioFailureCopyWithImpl;
@override @useResult
$Res call({
 StudioFailureCode code, String message, bool retryable, String correlationId, StudioFailureDetails? details
});


@override $StudioFailureDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class __$StudioFailureCopyWithImpl<$Res>
    implements _$StudioFailureCopyWith<$Res> {
  __$StudioFailureCopyWithImpl(this._self, this._then);

  final _StudioFailure _self;
  final $Res Function(_StudioFailure) _then;

/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? correlationId = null,Object? details = freezed,}) {
  return _then(_StudioFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as StudioFailureCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,correlationId: null == correlationId ? _self.correlationId : correlationId // ignore: cast_nullable_to_non_nullable
as String,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as StudioFailureDetails?,
  ));
}

/// Create a copy of StudioFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureDetailsCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $StudioFailureDetailsCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

// dart format on
