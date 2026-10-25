// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_navigation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsNavigationRequest {

 int get generation; SettingsTab get from; SettingsTab? get destination;
/// Create a copy of SettingsNavigationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsNavigationRequestCopyWith<SettingsNavigationRequest> get copyWith => _$SettingsNavigationRequestCopyWithImpl<SettingsNavigationRequest>(this as SettingsNavigationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsNavigationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsNavigationRequest&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.destination, _this.destination) || other.destination == _this.destination));
}


@override
int get hashCode {
  final _this = this as SettingsNavigationRequest;
  return Object.hash(runtimeType,_this.generation,_this.from,_this.destination);
}

@override
String toString() {
  final _this = this as SettingsNavigationRequest;
  return 'SettingsNavigationRequest(generation: ${_this.generation}, from: ${_this.from}, destination: ${_this.destination})';
}


}

/// @nodoc
abstract mixin class $SettingsNavigationRequestCopyWith<$Res>  {
  factory $SettingsNavigationRequestCopyWith(SettingsNavigationRequest value, $Res Function(SettingsNavigationRequest) _then) = _$SettingsNavigationRequestCopyWithImpl;
@useResult
$Res call({
 int generation, SettingsTab from, SettingsTab? destination
});




}
/// @nodoc
class _$SettingsNavigationRequestCopyWithImpl<$Res>
    implements $SettingsNavigationRequestCopyWith<$Res> {
  _$SettingsNavigationRequestCopyWithImpl(this._self, this._then);

  final SettingsNavigationRequest _self;
  final $Res Function(SettingsNavigationRequest) _then;

/// Create a copy of SettingsNavigationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? from = null,Object? destination = freezed,}) {
  return _then(SettingsNavigationRequest(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as SettingsTab,destination: freezed == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as SettingsTab?,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsNavigationRequest].
extension SettingsNavigationRequestPatterns on SettingsNavigationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsNavigationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsNavigationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsNavigationRequest value)  $default,){
final _that = this;
switch (_that) {
case _SettingsNavigationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsNavigationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsNavigationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  SettingsTab from,  SettingsTab? destination)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsNavigationRequest() when $default != null:
return $default(_that.generation,_that.from,_that.destination);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  SettingsTab from,  SettingsTab? destination)  $default,) {final _that = this;
switch (_that) {
case _SettingsNavigationRequest():
return $default(_that.generation,_that.from,_that.destination);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  SettingsTab from,  SettingsTab? destination)?  $default,) {final _that = this;
switch (_that) {
case _SettingsNavigationRequest() when $default != null:
return $default(_that.generation,_that.from,_that.destination);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsNavigationRequest implements SettingsNavigationRequest {
  const _SettingsNavigationRequest({required this.generation, required this.from, required this.destination});


@override final  int generation;
@override final  SettingsTab from;
@override final  SettingsTab? destination;

/// Create a copy of SettingsNavigationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsNavigationRequestCopyWith<_SettingsNavigationRequest> get copyWith => __$SettingsNavigationRequestCopyWithImpl<_SettingsNavigationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsNavigationRequest&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.from, from) || other.from == from)&&(identical(other.destination, destination) || other.destination == destination));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,from,destination);
}

@override
String toString() {
    return 'SettingsNavigationRequest(generation: $generation, from: $from, destination: $destination)';
}


}

/// @nodoc
abstract mixin class _$SettingsNavigationRequestCopyWith<$Res> implements $SettingsNavigationRequestCopyWith<$Res> {
  factory _$SettingsNavigationRequestCopyWith(_SettingsNavigationRequest value, $Res Function(_SettingsNavigationRequest) _then) = __$SettingsNavigationRequestCopyWithImpl;
@override @useResult
$Res call({
 int generation, SettingsTab from, SettingsTab? destination
});




}
/// @nodoc
class __$SettingsNavigationRequestCopyWithImpl<$Res>
    implements _$SettingsNavigationRequestCopyWith<$Res> {
  __$SettingsNavigationRequestCopyWithImpl(this._self, this._then);

  final _SettingsNavigationRequest _self;
  final $Res Function(_SettingsNavigationRequest) _then;

/// Create a copy of SettingsNavigationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? from = null,Object? destination = freezed,}) {
  return _then(_SettingsNavigationRequest(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as SettingsTab,destination: freezed == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as SettingsTab?,
  ));
}


}

/// @nodoc
mixin _$SettingsNavigationState {

 SettingsTab get tab; bool get visible; Set<SettingsTab> get visited; int get generation; bool get leaving; SettingsNavigationRequest? get request; StudioFailure? get error;
/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsNavigationStateCopyWith<SettingsNavigationState> get copyWith => _$SettingsNavigationStateCopyWithImpl<SettingsNavigationState>(this as SettingsNavigationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsNavigationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsNavigationState&&(identical(other.tab, _this.tab) || other.tab == _this.tab)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&const DeepCollectionEquality().equals(other.visited, _this.visited)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.leaving, _this.leaving) || other.leaving == _this.leaving)&&(identical(other.request, _this.request) || other.request == _this.request)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as SettingsNavigationState;
  return Object.hash(runtimeType,_this.tab,_this.visible,const DeepCollectionEquality().hash(_this.visited),_this.generation,_this.leaving,_this.request,_this.error);
}

@override
String toString() {
  final _this = this as SettingsNavigationState;
  return 'SettingsNavigationState(tab: ${_this.tab}, visible: ${_this.visible}, visited: ${_this.visited}, generation: ${_this.generation}, leaving: ${_this.leaving}, request: ${_this.request}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $SettingsNavigationStateCopyWith<$Res>  {
  factory $SettingsNavigationStateCopyWith(SettingsNavigationState value, $Res Function(SettingsNavigationState) _then) = _$SettingsNavigationStateCopyWithImpl;
@useResult
$Res call({
 SettingsTab tab, bool visible, Set<SettingsTab> visited, int generation, bool leaving, SettingsNavigationRequest? request, StudioFailure? error
});


$SettingsNavigationRequestCopyWith<$Res>? get request;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$SettingsNavigationStateCopyWithImpl<$Res>
    implements $SettingsNavigationStateCopyWith<$Res> {
  _$SettingsNavigationStateCopyWithImpl(this._self, this._then);

  final SettingsNavigationState _self;
  final $Res Function(SettingsNavigationState) _then;

/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tab = null,Object? visible = null,Object? visited = null,Object? generation = null,Object? leaving = null,Object? request = freezed,Object? error = freezed,}) {
  return _then(SettingsNavigationState(
tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as SettingsTab,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,visited: null == visited ? _self.visited : visited // ignore: cast_nullable_to_non_nullable
as Set<SettingsTab>,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,leaving: null == leaving ? _self.leaving : leaving // ignore: cast_nullable_to_non_nullable
as bool,request: freezed == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as SettingsNavigationRequest?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsNavigationRequestCopyWith<$Res>? get request {
    if (_self.request == null) {
    return null;
  }

  return $SettingsNavigationRequestCopyWith<$Res>(_self.request!, (value) {
    return _then(_self.copyWith(request: value));
  });
}/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsNavigationState].
extension SettingsNavigationStatePatterns on SettingsNavigationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsNavigationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsNavigationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsNavigationState value)  $default,){
final _that = this;
switch (_that) {
case _SettingsNavigationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsNavigationState value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsNavigationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SettingsTab tab,  bool visible,  Set<SettingsTab> visited,  int generation,  bool leaving,  SettingsNavigationRequest? request,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsNavigationState() when $default != null:
return $default(_that.tab,_that.visible,_that.visited,_that.generation,_that.leaving,_that.request,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SettingsTab tab,  bool visible,  Set<SettingsTab> visited,  int generation,  bool leaving,  SettingsNavigationRequest? request,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _SettingsNavigationState():
return $default(_that.tab,_that.visible,_that.visited,_that.generation,_that.leaving,_that.request,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SettingsTab tab,  bool visible,  Set<SettingsTab> visited,  int generation,  bool leaving,  SettingsNavigationRequest? request,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _SettingsNavigationState() when $default != null:
return $default(_that.tab,_that.visible,_that.visited,_that.generation,_that.leaving,_that.request,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsNavigationState implements SettingsNavigationState {
  const _SettingsNavigationState({this.tab = SettingsTab.accounts, this.visible = false,  Set<SettingsTab> visited = const {}, this.generation = 0, this.leaving = false, this.request, this.error}): _visited = visited;


@override@JsonKey() final  SettingsTab tab;
@override@JsonKey() final  bool visible;
 final  Set<SettingsTab> _visited;
@override@JsonKey() Set<SettingsTab> get visited {
  if (_visited is EqualUnmodifiableSetView) return _visited;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_visited);
}

@override@JsonKey() final  int generation;
@override@JsonKey() final  bool leaving;
@override final  SettingsNavigationRequest? request;
@override final  StudioFailure? error;

/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsNavigationStateCopyWith<_SettingsNavigationState> get copyWith => __$SettingsNavigationStateCopyWithImpl<_SettingsNavigationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsNavigationState&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.visible, visible) || other.visible == visible)&&const DeepCollectionEquality().equals(other.visited, _visited)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.leaving, leaving) || other.leaving == leaving)&&(identical(other.request, request) || other.request == request)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,tab,visible,const DeepCollectionEquality().hash(_visited),generation,leaving,request,error);
}

@override
String toString() {
    return 'SettingsNavigationState(tab: $tab, visible: $visible, visited: $visited, generation: $generation, leaving: $leaving, request: $request, error: $error)';
}


}

/// @nodoc
abstract mixin class _$SettingsNavigationStateCopyWith<$Res> implements $SettingsNavigationStateCopyWith<$Res> {
  factory _$SettingsNavigationStateCopyWith(_SettingsNavigationState value, $Res Function(_SettingsNavigationState) _then) = __$SettingsNavigationStateCopyWithImpl;
@override @useResult
$Res call({
 SettingsTab tab, bool visible, Set<SettingsTab> visited, int generation, bool leaving, SettingsNavigationRequest? request, StudioFailure? error
});


@override $SettingsNavigationRequestCopyWith<$Res>? get request;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$SettingsNavigationStateCopyWithImpl<$Res>
    implements _$SettingsNavigationStateCopyWith<$Res> {
  __$SettingsNavigationStateCopyWithImpl(this._self, this._then);

  final _SettingsNavigationState _self;
  final $Res Function(_SettingsNavigationState) _then;

/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tab = null,Object? visible = null,Object? visited = null,Object? generation = null,Object? leaving = null,Object? request = freezed,Object? error = freezed,}) {
  return _then(_SettingsNavigationState(
tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as SettingsTab,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,visited: null == visited ? _self._visited : visited // ignore: cast_nullable_to_non_nullable
as Set<SettingsTab>,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,leaving: null == leaving ? _self.leaving : leaving // ignore: cast_nullable_to_non_nullable
as bool,request: freezed == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as SettingsNavigationRequest?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsNavigationRequestCopyWith<$Res>? get request {
    if (_self.request == null) {
    return null;
  }

  return $SettingsNavigationRequestCopyWith<$Res>(_self.request!, (value) {
    return _then(_self.copyWith(request: value));
  });
}/// Create a copy of SettingsNavigationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
