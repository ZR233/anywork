// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_conversation_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotConversationThreadBinding {

 String get botId; String get chatId; String get projectId; String? get threadId; int get revision; BotConversationThreadState get state; BotDiagnostic? get diagnostic;
/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConversationThreadBindingCopyWith<BotConversationThreadBinding> get copyWith => _$BotConversationThreadBindingCopyWithImpl<BotConversationThreadBinding>(this as BotConversationThreadBinding, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotConversationThreadBinding;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConversationThreadBinding&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic));
}


@override
int get hashCode {
  final _this = this as BotConversationThreadBinding;
  return Object.hash(runtimeType,_this.botId,_this.chatId,_this.projectId,_this.threadId,_this.revision,_this.state,_this.diagnostic);
}



}

/// @nodoc
abstract mixin class $BotConversationThreadBindingCopyWith<$Res>  {
  factory $BotConversationThreadBindingCopyWith(BotConversationThreadBinding value, $Res Function(BotConversationThreadBinding) _then) = _$BotConversationThreadBindingCopyWithImpl;
@useResult
$Res call({
 String botId, String chatId, String projectId, String? threadId, int revision, BotConversationThreadState state, BotDiagnostic? diagnostic
});


$BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class _$BotConversationThreadBindingCopyWithImpl<$Res>
    implements $BotConversationThreadBindingCopyWith<$Res> {
  _$BotConversationThreadBindingCopyWithImpl(this._self, this._then);

  final BotConversationThreadBinding _self;
  final $Res Function(BotConversationThreadBinding) _then;

/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? chatId = null,Object? projectId = null,Object? threadId = freezed,Object? revision = null,Object? state = null,Object? diagnostic = freezed,}) {
  return _then(BotConversationThreadBinding(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BotConversationThreadState,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,
  ));
}
/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotConversationThreadBinding].
extension BotConversationThreadBindingPatterns on BotConversationThreadBinding {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotConversationThreadBinding value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotConversationThreadBinding() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotConversationThreadBinding value)  $default,){
final _that = this;
switch (_that) {
case _BotConversationThreadBinding():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotConversationThreadBinding value)?  $default,){
final _that = this;
switch (_that) {
case _BotConversationThreadBinding() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String botId,  String chatId,  String projectId,  String? threadId,  int revision,  BotConversationThreadState state,  BotDiagnostic? diagnostic)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotConversationThreadBinding() when $default != null:
return $default(_that.botId,_that.chatId,_that.projectId,_that.threadId,_that.revision,_that.state,_that.diagnostic);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String botId,  String chatId,  String projectId,  String? threadId,  int revision,  BotConversationThreadState state,  BotDiagnostic? diagnostic)  $default,) {final _that = this;
switch (_that) {
case _BotConversationThreadBinding():
return $default(_that.botId,_that.chatId,_that.projectId,_that.threadId,_that.revision,_that.state,_that.diagnostic);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String botId,  String chatId,  String projectId,  String? threadId,  int revision,  BotConversationThreadState state,  BotDiagnostic? diagnostic)?  $default,) {final _that = this;
switch (_that) {
case _BotConversationThreadBinding() when $default != null:
return $default(_that.botId,_that.chatId,_that.projectId,_that.threadId,_that.revision,_that.state,_that.diagnostic);case _:
  return null;

}
}

}

/// @nodoc


class _BotConversationThreadBinding implements BotConversationThreadBinding {
  const _BotConversationThreadBinding({required this.botId, required this.chatId, required this.projectId, required this.threadId, required this.revision, required this.state, required this.diagnostic});


@override final  String botId;
@override final  String chatId;
@override final  String projectId;
@override final  String? threadId;
@override final  int revision;
@override final  BotConversationThreadState state;
@override final  BotDiagnostic? diagnostic;

/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotConversationThreadBindingCopyWith<_BotConversationThreadBinding> get copyWith => __$BotConversationThreadBindingCopyWithImpl<_BotConversationThreadBinding>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotConversationThreadBinding&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state)&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,chatId,projectId,threadId,revision,state,diagnostic);
}



}

/// @nodoc
abstract mixin class _$BotConversationThreadBindingCopyWith<$Res> implements $BotConversationThreadBindingCopyWith<$Res> {
  factory _$BotConversationThreadBindingCopyWith(_BotConversationThreadBinding value, $Res Function(_BotConversationThreadBinding) _then) = __$BotConversationThreadBindingCopyWithImpl;
@override @useResult
$Res call({
 String botId, String chatId, String projectId, String? threadId, int revision, BotConversationThreadState state, BotDiagnostic? diagnostic
});


@override $BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class __$BotConversationThreadBindingCopyWithImpl<$Res>
    implements _$BotConversationThreadBindingCopyWith<$Res> {
  __$BotConversationThreadBindingCopyWithImpl(this._self, this._then);

  final _BotConversationThreadBinding _self;
  final $Res Function(_BotConversationThreadBinding) _then;

/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = null,Object? chatId = null,Object? projectId = null,Object? threadId = freezed,Object? revision = null,Object? state = null,Object? diagnostic = freezed,}) {
  return _then(_BotConversationThreadBinding(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BotConversationThreadState,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,
  ));
}

/// Create a copy of BotConversationThreadBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}

/// @nodoc
mixin _$BotConversation {

 String get chatId; BotConversationKind get kind; BotConversationSource get source; String? get name; int? get lastObservedAt; BotConversationThreadBinding? get threadBinding;
/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConversationCopyWith<BotConversation> get copyWith => _$BotConversationCopyWithImpl<BotConversation>(this as BotConversation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotConversation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConversation&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.lastObservedAt, _this.lastObservedAt) || other.lastObservedAt == _this.lastObservedAt)&&(identical(other.threadBinding, _this.threadBinding) || other.threadBinding == _this.threadBinding));
}


@override
int get hashCode {
  final _this = this as BotConversation;
  return Object.hash(runtimeType,_this.chatId,_this.kind,_this.source,_this.name,_this.lastObservedAt,_this.threadBinding);
}



}

/// @nodoc
abstract mixin class $BotConversationCopyWith<$Res>  {
  factory $BotConversationCopyWith(BotConversation value, $Res Function(BotConversation) _then) = _$BotConversationCopyWithImpl;
@useResult
$Res call({
 String chatId, BotConversationKind kind, BotConversationSource source, String? name, int? lastObservedAt, BotConversationThreadBinding? threadBinding
});


$BotConversationThreadBindingCopyWith<$Res>? get threadBinding;

}
/// @nodoc
class _$BotConversationCopyWithImpl<$Res>
    implements $BotConversationCopyWith<$Res> {
  _$BotConversationCopyWithImpl(this._self, this._then);

  final BotConversation _self;
  final $Res Function(BotConversation) _then;

/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? chatId = null,Object? kind = null,Object? source = null,Object? name = freezed,Object? lastObservedAt = freezed,Object? threadBinding = freezed,}) {
  return _then(BotConversation(
chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BotConversationKind,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BotConversationSource,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lastObservedAt: freezed == lastObservedAt ? _self.lastObservedAt : lastObservedAt // ignore: cast_nullable_to_non_nullable
as int?,threadBinding: freezed == threadBinding ? _self.threadBinding : threadBinding // ignore: cast_nullable_to_non_nullable
as BotConversationThreadBinding?,
  ));
}
/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationThreadBindingCopyWith<$Res>? get threadBinding {
    if (_self.threadBinding == null) {
    return null;
  }

  return $BotConversationThreadBindingCopyWith<$Res>(_self.threadBinding!, (value) {
    return _then(_self.copyWith(threadBinding: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotConversation].
extension BotConversationPatterns on BotConversation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotConversation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotConversation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotConversation value)  $default,){
final _that = this;
switch (_that) {
case _BotConversation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotConversation value)?  $default,){
final _that = this;
switch (_that) {
case _BotConversation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String chatId,  BotConversationKind kind,  BotConversationSource source,  String? name,  int? lastObservedAt,  BotConversationThreadBinding? threadBinding)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotConversation() when $default != null:
return $default(_that.chatId,_that.kind,_that.source,_that.name,_that.lastObservedAt,_that.threadBinding);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String chatId,  BotConversationKind kind,  BotConversationSource source,  String? name,  int? lastObservedAt,  BotConversationThreadBinding? threadBinding)  $default,) {final _that = this;
switch (_that) {
case _BotConversation():
return $default(_that.chatId,_that.kind,_that.source,_that.name,_that.lastObservedAt,_that.threadBinding);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String chatId,  BotConversationKind kind,  BotConversationSource source,  String? name,  int? lastObservedAt,  BotConversationThreadBinding? threadBinding)?  $default,) {final _that = this;
switch (_that) {
case _BotConversation() when $default != null:
return $default(_that.chatId,_that.kind,_that.source,_that.name,_that.lastObservedAt,_that.threadBinding);case _:
  return null;

}
}

}

/// @nodoc


class _BotConversation implements BotConversation {
  const _BotConversation({required this.chatId, required this.kind, required this.source, required this.name, required this.lastObservedAt, required this.threadBinding});


@override final  String chatId;
@override final  BotConversationKind kind;
@override final  BotConversationSource source;
@override final  String? name;
@override final  int? lastObservedAt;
@override final  BotConversationThreadBinding? threadBinding;

/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotConversationCopyWith<_BotConversation> get copyWith => __$BotConversationCopyWithImpl<_BotConversation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotConversation&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.source, source) || other.source == source)&&(identical(other.name, name) || other.name == name)&&(identical(other.lastObservedAt, lastObservedAt) || other.lastObservedAt == lastObservedAt)&&(identical(other.threadBinding, threadBinding) || other.threadBinding == threadBinding));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chatId,kind,source,name,lastObservedAt,threadBinding);
}



}

/// @nodoc
abstract mixin class _$BotConversationCopyWith<$Res> implements $BotConversationCopyWith<$Res> {
  factory _$BotConversationCopyWith(_BotConversation value, $Res Function(_BotConversation) _then) = __$BotConversationCopyWithImpl;
@override @useResult
$Res call({
 String chatId, BotConversationKind kind, BotConversationSource source, String? name, int? lastObservedAt, BotConversationThreadBinding? threadBinding
});


@override $BotConversationThreadBindingCopyWith<$Res>? get threadBinding;

}
/// @nodoc
class __$BotConversationCopyWithImpl<$Res>
    implements _$BotConversationCopyWith<$Res> {
  __$BotConversationCopyWithImpl(this._self, this._then);

  final _BotConversation _self;
  final $Res Function(_BotConversation) _then;

/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? chatId = null,Object? kind = null,Object? source = null,Object? name = freezed,Object? lastObservedAt = freezed,Object? threadBinding = freezed,}) {
  return _then(_BotConversation(
chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BotConversationKind,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BotConversationSource,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lastObservedAt: freezed == lastObservedAt ? _self.lastObservedAt : lastObservedAt // ignore: cast_nullable_to_non_nullable
as int?,threadBinding: freezed == threadBinding ? _self.threadBinding : threadBinding // ignore: cast_nullable_to_non_nullable
as BotConversationThreadBinding?,
  ));
}

/// Create a copy of BotConversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationThreadBindingCopyWith<$Res>? get threadBinding {
    if (_self.threadBinding == null) {
    return null;
  }

  return $BotConversationThreadBindingCopyWith<$Res>(_self.threadBinding!, (value) {
    return _then(_self.copyWith(threadBinding: value));
  });
}
}

/// @nodoc
mixin _$BotConversationPage {


/// Create a copy of BotConversationPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConversationPageCopyWith<BotConversationPage> get copyWith => _$BotConversationPageCopyWithImpl<BotConversationPage>(this as BotConversationPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotConversationPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConversationPage&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&const DeepCollectionEquality().equals(other.conversations, _this.conversations)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}


@override
int get hashCode {
  final _this = this as BotConversationPage;
  return Object.hash(runtimeType,_this.botId,const DeepCollectionEquality().hash(_this.conversations),_this.nextCursor);
}



}

/// @nodoc
abstract mixin class $BotConversationPageCopyWith<$Res>  {
  factory $BotConversationPageCopyWith(BotConversationPage value, $Res Function(BotConversationPage) _then) = _$BotConversationPageCopyWithImpl;
@useResult
$Res call({
 String botId, List<BotConversation> conversations, String? nextCursor
});




}
/// @nodoc
class _$BotConversationPageCopyWithImpl<$Res>
    implements $BotConversationPageCopyWith<$Res> {
  _$BotConversationPageCopyWithImpl(this._self, this._then);

  final BotConversationPage _self;
  final $Res Function(BotConversationPage) _then;

/// Create a copy of BotConversationPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? conversations = null,Object? nextCursor = freezed,}) {
  return _then(BotConversationPage(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,conversations: null == conversations ? _self.conversations : conversations // ignore: cast_nullable_to_non_nullable
as List<BotConversation>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotConversationPage].
extension BotConversationPagePatterns on BotConversationPage {
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
