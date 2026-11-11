// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'start_backend_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartBackendServiceItem {

 String get id; String get name; String? get brandKey; bool get enabled;
/// Create a copy of StartBackendServiceItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartBackendServiceItemCopyWith<StartBackendServiceItem> get copyWith => _$StartBackendServiceItemCopyWithImpl<StartBackendServiceItem>(this as StartBackendServiceItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartBackendServiceItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartBackendServiceItem&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.brandKey, _this.brandKey) || other.brandKey == _this.brandKey)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled));
}


@override
int get hashCode {
  final _this = this as StartBackendServiceItem;
  return Object.hash(runtimeType,_this.id,_this.name,_this.brandKey,_this.enabled);
}

@override
String toString() {
  final _this = this as StartBackendServiceItem;
  return 'StartBackendServiceItem(id: ${_this.id}, name: ${_this.name}, brandKey: ${_this.brandKey}, enabled: ${_this.enabled})';
}


}

/// @nodoc
abstract mixin class $StartBackendServiceItemCopyWith<$Res>  {
  factory $StartBackendServiceItemCopyWith(StartBackendServiceItem value, $Res Function(StartBackendServiceItem) _then) = _$StartBackendServiceItemCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? brandKey, bool enabled
});




}
/// @nodoc
class _$StartBackendServiceItemCopyWithImpl<$Res>
    implements $StartBackendServiceItemCopyWith<$Res> {
  _$StartBackendServiceItemCopyWithImpl(this._self, this._then);

  final StartBackendServiceItem _self;
  final $Res Function(StartBackendServiceItem) _then;

/// Create a copy of StartBackendServiceItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? brandKey = freezed,Object? enabled = null,}) {
  return _then(StartBackendServiceItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brandKey: freezed == brandKey ? _self.brandKey : brandKey // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [StartBackendServiceItem].
extension StartBackendServiceItemPatterns on StartBackendServiceItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartBackendServiceItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartBackendServiceItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartBackendServiceItem value)  $default,){
final _that = this;
switch (_that) {
case _StartBackendServiceItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartBackendServiceItem value)?  $default,){
final _that = this;
switch (_that) {
case _StartBackendServiceItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? brandKey,  bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartBackendServiceItem() when $default != null:
return $default(_that.id,_that.name,_that.brandKey,_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? brandKey,  bool enabled)  $default,) {final _that = this;
switch (_that) {
case _StartBackendServiceItem():
return $default(_that.id,_that.name,_that.brandKey,_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? brandKey,  bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _StartBackendServiceItem() when $default != null:
return $default(_that.id,_that.name,_that.brandKey,_that.enabled);case _:
  return null;

}
}

}

/// @nodoc


class _StartBackendServiceItem implements StartBackendServiceItem {
  const _StartBackendServiceItem({required this.id, required this.name, this.brandKey, required this.enabled});


@override final  String id;
@override final  String name;
@override final  String? brandKey;
@override final  bool enabled;

/// Create a copy of StartBackendServiceItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartBackendServiceItemCopyWith<_StartBackendServiceItem> get copyWith => __$StartBackendServiceItemCopyWithImpl<_StartBackendServiceItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartBackendServiceItem&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.brandKey, brandKey) || other.brandKey == brandKey)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,brandKey,enabled);
}

@override
String toString() {
    return 'StartBackendServiceItem(id: $id, name: $name, brandKey: $brandKey, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$StartBackendServiceItemCopyWith<$Res> implements $StartBackendServiceItemCopyWith<$Res> {
  factory _$StartBackendServiceItemCopyWith(_StartBackendServiceItem value, $Res Function(_StartBackendServiceItem) _then) = __$StartBackendServiceItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? brandKey, bool enabled
});




}
/// @nodoc
class __$StartBackendServiceItemCopyWithImpl<$Res>
    implements _$StartBackendServiceItemCopyWith<$Res> {
  __$StartBackendServiceItemCopyWithImpl(this._self, this._then);

  final _StartBackendServiceItem _self;
  final $Res Function(_StartBackendServiceItem) _then;

/// Create a copy of StartBackendServiceItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? brandKey = freezed,Object? enabled = null,}) {
  return _then(_StartBackendServiceItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brandKey: freezed == brandKey ? _self.brandKey : brandKey // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$StartBackendDiagnosticItem {

 String get fileName; String get message;
/// Create a copy of StartBackendDiagnosticItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartBackendDiagnosticItemCopyWith<StartBackendDiagnosticItem> get copyWith => _$StartBackendDiagnosticItemCopyWithImpl<StartBackendDiagnosticItem>(this as StartBackendDiagnosticItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartBackendDiagnosticItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartBackendDiagnosticItem&&(identical(other.fileName, _this.fileName) || other.fileName == _this.fileName)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as StartBackendDiagnosticItem;
  return Object.hash(runtimeType,_this.fileName,_this.message);
}

@override
String toString() {
  final _this = this as StartBackendDiagnosticItem;
  return 'StartBackendDiagnosticItem(fileName: ${_this.fileName}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $StartBackendDiagnosticItemCopyWith<$Res>  {
  factory $StartBackendDiagnosticItemCopyWith(StartBackendDiagnosticItem value, $Res Function(StartBackendDiagnosticItem) _then) = _$StartBackendDiagnosticItemCopyWithImpl;
@useResult
$Res call({
 String fileName, String message
});




}
/// @nodoc
class _$StartBackendDiagnosticItemCopyWithImpl<$Res>
    implements $StartBackendDiagnosticItemCopyWith<$Res> {
  _$StartBackendDiagnosticItemCopyWithImpl(this._self, this._then);

  final StartBackendDiagnosticItem _self;
  final $Res Function(StartBackendDiagnosticItem) _then;

/// Create a copy of StartBackendDiagnosticItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fileName = null,Object? message = null,}) {
  return _then(StartBackendDiagnosticItem(
fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StartBackendDiagnosticItem].
extension StartBackendDiagnosticItemPatterns on StartBackendDiagnosticItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartBackendDiagnosticItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartBackendDiagnosticItem value)  $default,){
final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartBackendDiagnosticItem value)?  $default,){
final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String fileName,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem() when $default != null:
return $default(_that.fileName,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String fileName,  String message)  $default,) {final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem():
return $default(_that.fileName,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String fileName,  String message)?  $default,) {final _that = this;
switch (_that) {
case _StartBackendDiagnosticItem() when $default != null:
return $default(_that.fileName,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _StartBackendDiagnosticItem implements StartBackendDiagnosticItem {
  const _StartBackendDiagnosticItem({required this.fileName, required this.message});


@override final  String fileName;
@override final  String message;

/// Create a copy of StartBackendDiagnosticItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartBackendDiagnosticItemCopyWith<_StartBackendDiagnosticItem> get copyWith => __$StartBackendDiagnosticItemCopyWithImpl<_StartBackendDiagnosticItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartBackendDiagnosticItem&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fileName,message);
}

@override
String toString() {
    return 'StartBackendDiagnosticItem(fileName: $fileName, message: $message)';
}


}

/// @nodoc
abstract mixin class _$StartBackendDiagnosticItemCopyWith<$Res> implements $StartBackendDiagnosticItemCopyWith<$Res> {
  factory _$StartBackendDiagnosticItemCopyWith(_StartBackendDiagnosticItem value, $Res Function(_StartBackendDiagnosticItem) _then) = __$StartBackendDiagnosticItemCopyWithImpl;
@override @useResult
$Res call({
 String fileName, String message
});




}
/// @nodoc
class __$StartBackendDiagnosticItemCopyWithImpl<$Res>
    implements _$StartBackendDiagnosticItemCopyWith<$Res> {
  __$StartBackendDiagnosticItemCopyWithImpl(this._self, this._then);

  final _StartBackendDiagnosticItem _self;
  final $Res Function(_StartBackendDiagnosticItem) _then;

/// Create a copy of StartBackendDiagnosticItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fileName = null,Object? message = null,}) {
  return _then(_StartBackendDiagnosticItem(
fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StartBackendViewState {

 List<StartBackendServiceItem> get services; List<StartBackendDiagnosticItem> get diagnostics; String? get accountId; bool get enabled; bool get loading; String? get failure;
/// Create a copy of StartBackendViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartBackendViewStateCopyWith<StartBackendViewState> get copyWith => _$StartBackendViewStateCopyWithImpl<StartBackendViewState>(this as StartBackendViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartBackendViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartBackendViewState&&const DeepCollectionEquality().equals(other.services, _this.services)&&const DeepCollectionEquality().equals(other.diagnostics, _this.diagnostics)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.failure, _this.failure) || other.failure == _this.failure));
}


@override
int get hashCode {
  final _this = this as StartBackendViewState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.services),const DeepCollectionEquality().hash(_this.diagnostics),_this.accountId,_this.enabled,_this.loading,_this.failure);
}

@override
String toString() {
  final _this = this as StartBackendViewState;
  return 'StartBackendViewState(services: ${_this.services}, diagnostics: ${_this.diagnostics}, accountId: ${_this.accountId}, enabled: ${_this.enabled}, loading: ${_this.loading}, failure: ${_this.failure})';
}


}

/// @nodoc
abstract mixin class $StartBackendViewStateCopyWith<$Res>  {
  factory $StartBackendViewStateCopyWith(StartBackendViewState value, $Res Function(StartBackendViewState) _then) = _$StartBackendViewStateCopyWithImpl;
@useResult
$Res call({
 List<StartBackendServiceItem> services, List<StartBackendDiagnosticItem> diagnostics, String? accountId, bool enabled, bool loading, String? failure
});




}
/// @nodoc
class _$StartBackendViewStateCopyWithImpl<$Res>
    implements $StartBackendViewStateCopyWith<$Res> {
  _$StartBackendViewStateCopyWithImpl(this._self, this._then);

  final StartBackendViewState _self;
  final $Res Function(StartBackendViewState) _then;

/// Create a copy of StartBackendViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? services = null,Object? diagnostics = null,Object? accountId = freezed,Object? enabled = null,Object? loading = null,Object? failure = freezed,}) {
  return _then(StartBackendViewState(
services: null == services ? _self.services : services // ignore: cast_nullable_to_non_nullable
as List<StartBackendServiceItem>,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<StartBackendDiagnosticItem>,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StartBackendViewState].
extension StartBackendViewStatePatterns on StartBackendViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartBackendViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartBackendViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartBackendViewState value)  $default,){
final _that = this;
switch (_that) {
case _StartBackendViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartBackendViewState value)?  $default,){
final _that = this;
switch (_that) {
case _StartBackendViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<StartBackendServiceItem> services,  List<StartBackendDiagnosticItem> diagnostics,  String? accountId,  bool enabled,  bool loading,  String? failure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartBackendViewState() when $default != null:
return $default(_that.services,_that.diagnostics,_that.accountId,_that.enabled,_that.loading,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<StartBackendServiceItem> services,  List<StartBackendDiagnosticItem> diagnostics,  String? accountId,  bool enabled,  bool loading,  String? failure)  $default,) {final _that = this;
switch (_that) {
case _StartBackendViewState():
return $default(_that.services,_that.diagnostics,_that.accountId,_that.enabled,_that.loading,_that.failure);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<StartBackendServiceItem> services,  List<StartBackendDiagnosticItem> diagnostics,  String? accountId,  bool enabled,  bool loading,  String? failure)?  $default,) {final _that = this;
switch (_that) {
case _StartBackendViewState() when $default != null:
return $default(_that.services,_that.diagnostics,_that.accountId,_that.enabled,_that.loading,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class _StartBackendViewState extends StartBackendViewState {
  const _StartBackendViewState({ List<StartBackendServiceItem> services = const <StartBackendServiceItem>[],  List<StartBackendDiagnosticItem> diagnostics = const <StartBackendDiagnosticItem>[], this.accountId, this.enabled = false, this.loading = true, this.failure}): _services = services,_diagnostics = diagnostics,super._();


 final  List<StartBackendServiceItem> _services;
@override@JsonKey() List<StartBackendServiceItem> get services {
  if (_services is EqualUnmodifiableListView) return _services;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_services);
}

 final  List<StartBackendDiagnosticItem> _diagnostics;
@override@JsonKey() List<StartBackendDiagnosticItem> get diagnostics {
  if (_diagnostics is EqualUnmodifiableListView) return _diagnostics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diagnostics);
}

@override final  String? accountId;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool loading;
@override final  String? failure;

/// Create a copy of StartBackendViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartBackendViewStateCopyWith<_StartBackendViewState> get copyWith => __$StartBackendViewStateCopyWithImpl<_StartBackendViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartBackendViewState&&const DeepCollectionEquality().equals(other.services, _services)&&const DeepCollectionEquality().equals(other.diagnostics, _diagnostics)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_services),const DeepCollectionEquality().hash(_diagnostics),accountId,enabled,loading,failure);
}

@override
String toString() {
    return 'StartBackendViewState(services: $services, diagnostics: $diagnostics, accountId: $accountId, enabled: $enabled, loading: $loading, failure: $failure)';
}


}

/// @nodoc
abstract mixin class _$StartBackendViewStateCopyWith<$Res> implements $StartBackendViewStateCopyWith<$Res> {
  factory _$StartBackendViewStateCopyWith(_StartBackendViewState value, $Res Function(_StartBackendViewState) _then) = __$StartBackendViewStateCopyWithImpl;
@override @useResult
$Res call({
 List<StartBackendServiceItem> services, List<StartBackendDiagnosticItem> diagnostics, String? accountId, bool enabled, bool loading, String? failure
});




}
/// @nodoc
class __$StartBackendViewStateCopyWithImpl<$Res>
    implements _$StartBackendViewStateCopyWith<$Res> {
  __$StartBackendViewStateCopyWithImpl(this._self, this._then);

  final _StartBackendViewState _self;
  final $Res Function(_StartBackendViewState) _then;

/// Create a copy of StartBackendViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? services = null,Object? diagnostics = null,Object? accountId = freezed,Object? enabled = null,Object? loading = null,Object? failure = freezed,}) {
  return _then(_StartBackendViewState(
services: null == services ? _self._services : services // ignore: cast_nullable_to_non_nullable
as List<StartBackendServiceItem>,diagnostics: null == diagnostics ? _self._diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<StartBackendDiagnosticItem>,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
