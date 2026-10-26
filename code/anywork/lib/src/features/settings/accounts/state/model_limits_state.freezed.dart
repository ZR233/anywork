// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_limits_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountFieldBinding {

 ProductReadOrigin get configurationOrigin; int get accountEntry; ProductReadOrigin get catalogOrigin; int get catalogEntry;
/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<AccountFieldBinding> get copyWith => _$AccountFieldBindingCopyWithImpl<AccountFieldBinding>(this as AccountFieldBinding, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountFieldBinding;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountFieldBinding&&(identical(other.configurationOrigin, _this.configurationOrigin) || other.configurationOrigin == _this.configurationOrigin)&&(identical(other.accountEntry, _this.accountEntry) || other.accountEntry == _this.accountEntry)&&(identical(other.catalogOrigin, _this.catalogOrigin) || other.catalogOrigin == _this.catalogOrigin)&&(identical(other.catalogEntry, _this.catalogEntry) || other.catalogEntry == _this.catalogEntry));
}


@override
int get hashCode {
  final _this = this as AccountFieldBinding;
  return Object.hash(runtimeType,_this.configurationOrigin,_this.accountEntry,_this.catalogOrigin,_this.catalogEntry);
}

@override
String toString() {
  final _this = this as AccountFieldBinding;
  return 'AccountFieldBinding(configurationOrigin: ${_this.configurationOrigin}, accountEntry: ${_this.accountEntry}, catalogOrigin: ${_this.catalogOrigin}, catalogEntry: ${_this.catalogEntry})';
}


}

/// @nodoc
abstract mixin class $AccountFieldBindingCopyWith<$Res>  {
  factory $AccountFieldBindingCopyWith(AccountFieldBinding value, $Res Function(AccountFieldBinding) _then) = _$AccountFieldBindingCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin configurationOrigin, int accountEntry, ProductReadOrigin catalogOrigin, int catalogEntry
});


$ProductReadOriginCopyWith<$Res> get configurationOrigin;$ProductReadOriginCopyWith<$Res> get catalogOrigin;

}
/// @nodoc
class _$AccountFieldBindingCopyWithImpl<$Res>
    implements $AccountFieldBindingCopyWith<$Res> {
  _$AccountFieldBindingCopyWithImpl(this._self, this._then);

  final AccountFieldBinding _self;
  final $Res Function(AccountFieldBinding) _then;

/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configurationOrigin = null,Object? accountEntry = null,Object? catalogOrigin = null,Object? catalogEntry = null,}) {
  return _then(AccountFieldBinding(
configurationOrigin: null == configurationOrigin ? _self.configurationOrigin : configurationOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,accountEntry: null == accountEntry ? _self.accountEntry : accountEntry // ignore: cast_nullable_to_non_nullable
as int,catalogOrigin: null == catalogOrigin ? _self.catalogOrigin : catalogOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,catalogEntry: null == catalogEntry ? _self.catalogEntry : catalogEntry // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get configurationOrigin {

  return $ProductReadOriginCopyWith<$Res>(_self.configurationOrigin, (value) {
    return _then(_self.copyWith(configurationOrigin: value));
  });
}/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get catalogOrigin {

  return $ProductReadOriginCopyWith<$Res>(_self.catalogOrigin, (value) {
    return _then(_self.copyWith(catalogOrigin: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountFieldBinding].
extension AccountFieldBindingPatterns on AccountFieldBinding {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountFieldBinding value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountFieldBinding() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountFieldBinding value)  $default,){
final _that = this;
switch (_that) {
case _AccountFieldBinding():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountFieldBinding value)?  $default,){
final _that = this;
switch (_that) {
case _AccountFieldBinding() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin configurationOrigin,  int accountEntry,  ProductReadOrigin catalogOrigin,  int catalogEntry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountFieldBinding() when $default != null:
return $default(_that.configurationOrigin,_that.accountEntry,_that.catalogOrigin,_that.catalogEntry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin configurationOrigin,  int accountEntry,  ProductReadOrigin catalogOrigin,  int catalogEntry)  $default,) {final _that = this;
switch (_that) {
case _AccountFieldBinding():
return $default(_that.configurationOrigin,_that.accountEntry,_that.catalogOrigin,_that.catalogEntry);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin configurationOrigin,  int accountEntry,  ProductReadOrigin catalogOrigin,  int catalogEntry)?  $default,) {final _that = this;
switch (_that) {
case _AccountFieldBinding() when $default != null:
return $default(_that.configurationOrigin,_that.accountEntry,_that.catalogOrigin,_that.catalogEntry);case _:
  return null;

}
}

}

/// @nodoc


class _AccountFieldBinding implements AccountFieldBinding {
  const _AccountFieldBinding({required this.configurationOrigin, required this.accountEntry, required this.catalogOrigin, required this.catalogEntry});


@override final  ProductReadOrigin configurationOrigin;
@override final  int accountEntry;
@override final  ProductReadOrigin catalogOrigin;
@override final  int catalogEntry;

/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountFieldBindingCopyWith<_AccountFieldBinding> get copyWith => __$AccountFieldBindingCopyWithImpl<_AccountFieldBinding>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountFieldBinding&&(identical(other.configurationOrigin, configurationOrigin) || other.configurationOrigin == configurationOrigin)&&(identical(other.accountEntry, accountEntry) || other.accountEntry == accountEntry)&&(identical(other.catalogOrigin, catalogOrigin) || other.catalogOrigin == catalogOrigin)&&(identical(other.catalogEntry, catalogEntry) || other.catalogEntry == catalogEntry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configurationOrigin,accountEntry,catalogOrigin,catalogEntry);
}

@override
String toString() {
    return 'AccountFieldBinding(configurationOrigin: $configurationOrigin, accountEntry: $accountEntry, catalogOrigin: $catalogOrigin, catalogEntry: $catalogEntry)';
}


}

/// @nodoc
abstract mixin class _$AccountFieldBindingCopyWith<$Res> implements $AccountFieldBindingCopyWith<$Res> {
  factory _$AccountFieldBindingCopyWith(_AccountFieldBinding value, $Res Function(_AccountFieldBinding) _then) = __$AccountFieldBindingCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin configurationOrigin, int accountEntry, ProductReadOrigin catalogOrigin, int catalogEntry
});


@override $ProductReadOriginCopyWith<$Res> get configurationOrigin;@override $ProductReadOriginCopyWith<$Res> get catalogOrigin;

}
/// @nodoc
class __$AccountFieldBindingCopyWithImpl<$Res>
    implements _$AccountFieldBindingCopyWith<$Res> {
  __$AccountFieldBindingCopyWithImpl(this._self, this._then);

  final _AccountFieldBinding _self;
  final $Res Function(_AccountFieldBinding) _then;

/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configurationOrigin = null,Object? accountEntry = null,Object? catalogOrigin = null,Object? catalogEntry = null,}) {
  return _then(_AccountFieldBinding(
configurationOrigin: null == configurationOrigin ? _self.configurationOrigin : configurationOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,accountEntry: null == accountEntry ? _self.accountEntry : accountEntry // ignore: cast_nullable_to_non_nullable
as int,catalogOrigin: null == catalogOrigin ? _self.catalogOrigin : catalogOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,catalogEntry: null == catalogEntry ? _self.catalogEntry : catalogEntry // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get configurationOrigin {

  return $ProductReadOriginCopyWith<$Res>(_self.configurationOrigin, (value) {
    return _then(_self.copyWith(configurationOrigin: value));
  });
}/// Create a copy of AccountFieldBinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get catalogOrigin {

  return $ProductReadOriginCopyWith<$Res>(_self.catalogOrigin, (value) {
    return _then(_self.copyWith(catalogOrigin: value));
  });
}
}

/// @nodoc
mixin _$AccountModelEnabledAction {

 AccountFieldBinding get binding; bool get enabled; SettingsAction get action;
/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelEnabledActionCopyWith<AccountModelEnabledAction> get copyWith => _$AccountModelEnabledActionCopyWithImpl<AccountModelEnabledAction>(this as AccountModelEnabledAction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelEnabledAction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelEnabledAction&&(identical(other.binding, _this.binding) || other.binding == _this.binding)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as AccountModelEnabledAction;
  return Object.hash(runtimeType,_this.binding,_this.enabled,_this.action);
}

@override
String toString() {
  final _this = this as AccountModelEnabledAction;
  return 'AccountModelEnabledAction(binding: ${_this.binding}, enabled: ${_this.enabled}, action: ${_this.action})';
}


}

/// @nodoc
abstract mixin class $AccountModelEnabledActionCopyWith<$Res>  {
  factory $AccountModelEnabledActionCopyWith(AccountModelEnabledAction value, $Res Function(AccountModelEnabledAction) _then) = _$AccountModelEnabledActionCopyWithImpl;
@useResult
$Res call({
 AccountFieldBinding binding, bool enabled, SettingsAction action
});


$AccountFieldBindingCopyWith<$Res> get binding;$SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class _$AccountModelEnabledActionCopyWithImpl<$Res>
    implements $AccountModelEnabledActionCopyWith<$Res> {
  _$AccountModelEnabledActionCopyWithImpl(this._self, this._then);

  final AccountModelEnabledAction _self;
  final $Res Function(AccountModelEnabledAction) _then;

/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? binding = null,Object? enabled = null,Object? action = null,}) {
  return _then(AccountModelEnabledAction(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}
/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res> get binding {

  return $AccountFieldBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelEnabledAction].
extension AccountModelEnabledActionPatterns on AccountModelEnabledAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelEnabledAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelEnabledAction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelEnabledAction value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelEnabledAction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelEnabledAction value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelEnabledAction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountFieldBinding binding,  bool enabled,  SettingsAction action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelEnabledAction() when $default != null:
return $default(_that.binding,_that.enabled,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountFieldBinding binding,  bool enabled,  SettingsAction action)  $default,) {final _that = this;
switch (_that) {
case _AccountModelEnabledAction():
return $default(_that.binding,_that.enabled,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountFieldBinding binding,  bool enabled,  SettingsAction action)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelEnabledAction() when $default != null:
return $default(_that.binding,_that.enabled,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelEnabledAction implements AccountModelEnabledAction {
  const _AccountModelEnabledAction({required this.binding, required this.enabled, required this.action});


@override final  AccountFieldBinding binding;
@override final  bool enabled;
@override final  SettingsAction action;

/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelEnabledActionCopyWith<_AccountModelEnabledAction> get copyWith => __$AccountModelEnabledActionCopyWithImpl<_AccountModelEnabledAction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelEnabledAction&&(identical(other.binding, binding) || other.binding == binding)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,binding,enabled,action);
}

@override
String toString() {
    return 'AccountModelEnabledAction(binding: $binding, enabled: $enabled, action: $action)';
}


}

/// @nodoc
abstract mixin class _$AccountModelEnabledActionCopyWith<$Res> implements $AccountModelEnabledActionCopyWith<$Res> {
  factory _$AccountModelEnabledActionCopyWith(_AccountModelEnabledAction value, $Res Function(_AccountModelEnabledAction) _then) = __$AccountModelEnabledActionCopyWithImpl;
@override @useResult
$Res call({
 AccountFieldBinding binding, bool enabled, SettingsAction action
});


@override $AccountFieldBindingCopyWith<$Res> get binding;@override $SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class __$AccountModelEnabledActionCopyWithImpl<$Res>
    implements _$AccountModelEnabledActionCopyWith<$Res> {
  __$AccountModelEnabledActionCopyWithImpl(this._self, this._then);

  final _AccountModelEnabledAction _self;
  final $Res Function(_AccountModelEnabledAction) _then;

/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? binding = null,Object? enabled = null,Object? action = null,}) {
  return _then(_AccountModelEnabledAction(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}

/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res> get binding {

  return $AccountFieldBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountModelEnabledAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$AccountBillingAction {

 AccountFieldBinding get binding; BillingKind? get requestedOverride; SettingsAction get action;
/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountBillingActionCopyWith<AccountBillingAction> get copyWith => _$AccountBillingActionCopyWithImpl<AccountBillingAction>(this as AccountBillingAction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountBillingAction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountBillingAction&&(identical(other.binding, _this.binding) || other.binding == _this.binding)&&(identical(other.requestedOverride, _this.requestedOverride) || other.requestedOverride == _this.requestedOverride)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as AccountBillingAction;
  return Object.hash(runtimeType,_this.binding,_this.requestedOverride,_this.action);
}

@override
String toString() {
  final _this = this as AccountBillingAction;
  return 'AccountBillingAction(binding: ${_this.binding}, requestedOverride: ${_this.requestedOverride}, action: ${_this.action})';
}


}

/// @nodoc
abstract mixin class $AccountBillingActionCopyWith<$Res>  {
  factory $AccountBillingActionCopyWith(AccountBillingAction value, $Res Function(AccountBillingAction) _then) = _$AccountBillingActionCopyWithImpl;
@useResult
$Res call({
 AccountFieldBinding binding, BillingKind? requestedOverride, SettingsAction action
});


$AccountFieldBindingCopyWith<$Res> get binding;$SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class _$AccountBillingActionCopyWithImpl<$Res>
    implements $AccountBillingActionCopyWith<$Res> {
  _$AccountBillingActionCopyWithImpl(this._self, this._then);

  final AccountBillingAction _self;
  final $Res Function(AccountBillingAction) _then;

/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? binding = null,Object? requestedOverride = freezed,Object? action = null,}) {
  return _then(AccountBillingAction(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding,requestedOverride: freezed == requestedOverride ? _self.requestedOverride : requestedOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}
/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res> get binding {

  return $AccountFieldBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountBillingAction].
extension AccountBillingActionPatterns on AccountBillingAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountBillingAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountBillingAction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountBillingAction value)  $default,){
final _that = this;
switch (_that) {
case _AccountBillingAction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountBillingAction value)?  $default,){
final _that = this;
switch (_that) {
case _AccountBillingAction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountFieldBinding binding,  BillingKind? requestedOverride,  SettingsAction action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountBillingAction() when $default != null:
return $default(_that.binding,_that.requestedOverride,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountFieldBinding binding,  BillingKind? requestedOverride,  SettingsAction action)  $default,) {final _that = this;
switch (_that) {
case _AccountBillingAction():
return $default(_that.binding,_that.requestedOverride,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountFieldBinding binding,  BillingKind? requestedOverride,  SettingsAction action)?  $default,) {final _that = this;
switch (_that) {
case _AccountBillingAction() when $default != null:
return $default(_that.binding,_that.requestedOverride,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _AccountBillingAction implements AccountBillingAction {
  const _AccountBillingAction({required this.binding, required this.requestedOverride, required this.action});


@override final  AccountFieldBinding binding;
@override final  BillingKind? requestedOverride;
@override final  SettingsAction action;

/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountBillingActionCopyWith<_AccountBillingAction> get copyWith => __$AccountBillingActionCopyWithImpl<_AccountBillingAction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountBillingAction&&(identical(other.binding, binding) || other.binding == binding)&&(identical(other.requestedOverride, requestedOverride) || other.requestedOverride == requestedOverride)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,binding,requestedOverride,action);
}

@override
String toString() {
    return 'AccountBillingAction(binding: $binding, requestedOverride: $requestedOverride, action: $action)';
}


}

/// @nodoc
abstract mixin class _$AccountBillingActionCopyWith<$Res> implements $AccountBillingActionCopyWith<$Res> {
  factory _$AccountBillingActionCopyWith(_AccountBillingAction value, $Res Function(_AccountBillingAction) _then) = __$AccountBillingActionCopyWithImpl;
@override @useResult
$Res call({
 AccountFieldBinding binding, BillingKind? requestedOverride, SettingsAction action
});


@override $AccountFieldBindingCopyWith<$Res> get binding;@override $SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class __$AccountBillingActionCopyWithImpl<$Res>
    implements _$AccountBillingActionCopyWith<$Res> {
  __$AccountBillingActionCopyWithImpl(this._self, this._then);

  final _AccountBillingAction _self;
  final $Res Function(_AccountBillingAction) _then;

/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? binding = null,Object? requestedOverride = freezed,Object? action = null,}) {
  return _then(_AccountBillingAction(
binding: null == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding,requestedOverride: freezed == requestedOverride ? _self.requestedOverride : requestedOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}

/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res> get binding {

  return $AccountFieldBindingCopyWith<$Res>(_self.binding, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountBillingAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$ModelLimitDraft {

 String get raw; int get intent; bool get restoreDefault; bool get dirty; bool get composing; ModelLimitValidation? get validation; SettingsAction? get action;
/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelLimitDraftCopyWith<ModelLimitDraft> get copyWith => _$ModelLimitDraftCopyWithImpl<ModelLimitDraft>(this as ModelLimitDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelLimitDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelLimitDraft&&(identical(other.raw, _this.raw) || other.raw == _this.raw)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.restoreDefault, _this.restoreDefault) || other.restoreDefault == _this.restoreDefault)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.composing, _this.composing) || other.composing == _this.composing)&&(identical(other.validation, _this.validation) || other.validation == _this.validation)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as ModelLimitDraft;
  return Object.hash(runtimeType,_this.raw,_this.intent,_this.restoreDefault,_this.dirty,_this.composing,_this.validation,_this.action);
}

@override
String toString() {
  final _this = this as ModelLimitDraft;
  return 'ModelLimitDraft(raw: ${_this.raw}, intent: ${_this.intent}, restoreDefault: ${_this.restoreDefault}, dirty: ${_this.dirty}, composing: ${_this.composing}, validation: ${_this.validation}, action: ${_this.action})';
}


}

/// @nodoc
abstract mixin class $ModelLimitDraftCopyWith<$Res>  {
  factory $ModelLimitDraftCopyWith(ModelLimitDraft value, $Res Function(ModelLimitDraft) _then) = _$ModelLimitDraftCopyWithImpl;
@useResult
$Res call({
 String raw, int intent, bool restoreDefault, bool dirty, bool composing, ModelLimitValidation? validation, SettingsAction? action
});


$SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class _$ModelLimitDraftCopyWithImpl<$Res>
    implements $ModelLimitDraftCopyWith<$Res> {
  _$ModelLimitDraftCopyWithImpl(this._self, this._then);

  final ModelLimitDraft _self;
  final $Res Function(ModelLimitDraft) _then;

/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,Object? intent = null,Object? restoreDefault = null,Object? dirty = null,Object? composing = null,Object? validation = freezed,Object? action = freezed,}) {
  return _then(ModelLimitDraft(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,restoreDefault: null == restoreDefault ? _self.restoreDefault : restoreDefault // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,composing: null == composing ? _self.composing : composing // ignore: cast_nullable_to_non_nullable
as bool,validation: freezed == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as ModelLimitValidation?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelLimitDraft].
extension ModelLimitDraftPatterns on ModelLimitDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelLimitDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelLimitDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelLimitDraft value)  $default,){
final _that = this;
switch (_that) {
case _ModelLimitDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelLimitDraft value)?  $default,){
final _that = this;
switch (_that) {
case _ModelLimitDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String raw,  int intent,  bool restoreDefault,  bool dirty,  bool composing,  ModelLimitValidation? validation,  SettingsAction? action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelLimitDraft() when $default != null:
return $default(_that.raw,_that.intent,_that.restoreDefault,_that.dirty,_that.composing,_that.validation,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String raw,  int intent,  bool restoreDefault,  bool dirty,  bool composing,  ModelLimitValidation? validation,  SettingsAction? action)  $default,) {final _that = this;
switch (_that) {
case _ModelLimitDraft():
return $default(_that.raw,_that.intent,_that.restoreDefault,_that.dirty,_that.composing,_that.validation,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String raw,  int intent,  bool restoreDefault,  bool dirty,  bool composing,  ModelLimitValidation? validation,  SettingsAction? action)?  $default,) {final _that = this;
switch (_that) {
case _ModelLimitDraft() when $default != null:
return $default(_that.raw,_that.intent,_that.restoreDefault,_that.dirty,_that.composing,_that.validation,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _ModelLimitDraft implements ModelLimitDraft {
  const _ModelLimitDraft({required this.raw, required this.intent, this.restoreDefault = false, this.dirty = false, this.composing = false, this.validation, this.action});


@override final  String raw;
@override final  int intent;
@override@JsonKey() final  bool restoreDefault;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool composing;
@override final  ModelLimitValidation? validation;
@override final  SettingsAction? action;

/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelLimitDraftCopyWith<_ModelLimitDraft> get copyWith => __$ModelLimitDraftCopyWithImpl<_ModelLimitDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelLimitDraft&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.restoreDefault, restoreDefault) || other.restoreDefault == restoreDefault)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.composing, composing) || other.composing == composing)&&(identical(other.validation, validation) || other.validation == validation)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,raw,intent,restoreDefault,dirty,composing,validation,action);
}

@override
String toString() {
    return 'ModelLimitDraft(raw: $raw, intent: $intent, restoreDefault: $restoreDefault, dirty: $dirty, composing: $composing, validation: $validation, action: $action)';
}


}

/// @nodoc
abstract mixin class _$ModelLimitDraftCopyWith<$Res> implements $ModelLimitDraftCopyWith<$Res> {
  factory _$ModelLimitDraftCopyWith(_ModelLimitDraft value, $Res Function(_ModelLimitDraft) _then) = __$ModelLimitDraftCopyWithImpl;
@override @useResult
$Res call({
 String raw, int intent, bool restoreDefault, bool dirty, bool composing, ModelLimitValidation? validation, SettingsAction? action
});


@override $SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class __$ModelLimitDraftCopyWithImpl<$Res>
    implements _$ModelLimitDraftCopyWith<$Res> {
  __$ModelLimitDraftCopyWithImpl(this._self, this._then);

  final _ModelLimitDraft _self;
  final $Res Function(_ModelLimitDraft) _then;

/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,Object? intent = null,Object? restoreDefault = null,Object? dirty = null,Object? composing = null,Object? validation = freezed,Object? action = freezed,}) {
  return _then(_ModelLimitDraft(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,restoreDefault: null == restoreDefault ? _self.restoreDefault : restoreDefault // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,composing: null == composing ? _self.composing : composing // ignore: cast_nullable_to_non_nullable
as bool,validation: freezed == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as ModelLimitValidation?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of ModelLimitDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$AccountModelLimitsViewState {

 String get accountId; ConfigurationState get source; ModelsState get modelSource; AccountConfiguration get canonical; AccountCatalogEntry get catalog; AccountFieldBinding? get binding; Map<String, AccountModelEnabledAction> get enabledActions; AccountBillingAction? get billingAction; Map<String, ModelLimitDraft> get drafts; Map<ModelLimitsReadField, StudioFailure> get readIssues; bool get readPending;
/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelLimitsViewStateCopyWith<AccountModelLimitsViewState> get copyWith => _$AccountModelLimitsViewStateCopyWithImpl<AccountModelLimitsViewState>(this as AccountModelLimitsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelLimitsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelLimitsViewState&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.modelSource, _this.modelSource) || other.modelSource == _this.modelSource)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.binding, _this.binding) || other.binding == _this.binding)&&const DeepCollectionEquality().equals(other.enabledActions, _this.enabledActions)&&(identical(other.billingAction, _this.billingAction) || other.billingAction == _this.billingAction)&&const DeepCollectionEquality().equals(other.drafts, _this.drafts)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&(identical(other.readPending, _this.readPending) || other.readPending == _this.readPending));
}


@override
int get hashCode {
  final _this = this as AccountModelLimitsViewState;
  return Object.hash(runtimeType,_this.accountId,_this.source,_this.modelSource,_this.canonical,_this.catalog,_this.binding,const DeepCollectionEquality().hash(_this.enabledActions),_this.billingAction,const DeepCollectionEquality().hash(_this.drafts),const DeepCollectionEquality().hash(_this.readIssues),_this.readPending);
}

@override
String toString() {
  final _this = this as AccountModelLimitsViewState;
  return 'AccountModelLimitsViewState(accountId: ${_this.accountId}, source: ${_this.source}, modelSource: ${_this.modelSource}, canonical: ${_this.canonical}, catalog: ${_this.catalog}, binding: ${_this.binding}, enabledActions: ${_this.enabledActions}, billingAction: ${_this.billingAction}, drafts: ${_this.drafts}, readIssues: ${_this.readIssues}, readPending: ${_this.readPending})';
}


}

/// @nodoc
abstract mixin class $AccountModelLimitsViewStateCopyWith<$Res>  {
  factory $AccountModelLimitsViewStateCopyWith(AccountModelLimitsViewState value, $Res Function(AccountModelLimitsViewState) _then) = _$AccountModelLimitsViewStateCopyWithImpl;
@useResult
$Res call({
 String accountId, ConfigurationState source, ModelsState modelSource, AccountConfiguration canonical, AccountCatalogEntry catalog, AccountFieldBinding? binding, Map<String, AccountModelEnabledAction> enabledActions, AccountBillingAction? billingAction, Map<String, ModelLimitDraft> drafts, Map<ModelLimitsReadField, StudioFailure> readIssues, bool readPending
});


$ConfigurationStateCopyWith<$Res> get source;$ModelsStateCopyWith<$Res> get modelSource;$AccountConfigurationCopyWith<$Res> get canonical;$AccountCatalogEntryCopyWith<$Res> get catalog;$AccountFieldBindingCopyWith<$Res>? get binding;$AccountBillingActionCopyWith<$Res>? get billingAction;

}
/// @nodoc
class _$AccountModelLimitsViewStateCopyWithImpl<$Res>
    implements $AccountModelLimitsViewStateCopyWith<$Res> {
  _$AccountModelLimitsViewStateCopyWithImpl(this._self, this._then);

  final AccountModelLimitsViewState _self;
  final $Res Function(AccountModelLimitsViewState) _then;

/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? source = null,Object? modelSource = null,Object? canonical = null,Object? catalog = null,Object? binding = freezed,Object? enabledActions = null,Object? billingAction = freezed,Object? drafts = null,Object? readIssues = null,Object? readPending = null,}) {
  return _then(AccountModelLimitsViewState(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,canonical: null == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AccountConfiguration,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogEntry,binding: freezed == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding?,enabledActions: null == enabledActions ? _self.enabledActions : enabledActions // ignore: cast_nullable_to_non_nullable
as Map<String, AccountModelEnabledAction>,billingAction: freezed == billingAction ? _self.billingAction : billingAction // ignore: cast_nullable_to_non_nullable
as AccountBillingAction?,drafts: null == drafts ? _self.drafts : drafts // ignore: cast_nullable_to_non_nullable
as Map<String, ModelLimitDraft>,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<ModelLimitsReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res> get canonical {

  return $AccountConfigurationCopyWith<$Res>(_self.canonical, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogEntryCopyWith<$Res> get catalog {

  return $AccountCatalogEntryCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res>? get binding {
    if (_self.binding == null) {
    return null;
  }

  return $AccountFieldBindingCopyWith<$Res>(_self.binding!, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingActionCopyWith<$Res>? get billingAction {
    if (_self.billingAction == null) {
    return null;
  }

  return $AccountBillingActionCopyWith<$Res>(_self.billingAction!, (value) {
    return _then(_self.copyWith(billingAction: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelLimitsViewState].
extension AccountModelLimitsViewStatePatterns on AccountModelLimitsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelLimitsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelLimitsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelLimitsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelLimitsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelLimitsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelLimitsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  ConfigurationState source,  ModelsState modelSource,  AccountConfiguration canonical,  AccountCatalogEntry catalog,  AccountFieldBinding? binding,  Map<String, AccountModelEnabledAction> enabledActions,  AccountBillingAction? billingAction,  Map<String, ModelLimitDraft> drafts,  Map<ModelLimitsReadField, StudioFailure> readIssues,  bool readPending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelLimitsViewState() when $default != null:
return $default(_that.accountId,_that.source,_that.modelSource,_that.canonical,_that.catalog,_that.binding,_that.enabledActions,_that.billingAction,_that.drafts,_that.readIssues,_that.readPending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  ConfigurationState source,  ModelsState modelSource,  AccountConfiguration canonical,  AccountCatalogEntry catalog,  AccountFieldBinding? binding,  Map<String, AccountModelEnabledAction> enabledActions,  AccountBillingAction? billingAction,  Map<String, ModelLimitDraft> drafts,  Map<ModelLimitsReadField, StudioFailure> readIssues,  bool readPending)  $default,) {final _that = this;
switch (_that) {
case _AccountModelLimitsViewState():
return $default(_that.accountId,_that.source,_that.modelSource,_that.canonical,_that.catalog,_that.binding,_that.enabledActions,_that.billingAction,_that.drafts,_that.readIssues,_that.readPending);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  ConfigurationState source,  ModelsState modelSource,  AccountConfiguration canonical,  AccountCatalogEntry catalog,  AccountFieldBinding? binding,  Map<String, AccountModelEnabledAction> enabledActions,  AccountBillingAction? billingAction,  Map<String, ModelLimitDraft> drafts,  Map<ModelLimitsReadField, StudioFailure> readIssues,  bool readPending)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelLimitsViewState() when $default != null:
return $default(_that.accountId,_that.source,_that.modelSource,_that.canonical,_that.catalog,_that.binding,_that.enabledActions,_that.billingAction,_that.drafts,_that.readIssues,_that.readPending);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelLimitsViewState implements AccountModelLimitsViewState {
  const _AccountModelLimitsViewState({required this.accountId, required this.source, required this.modelSource, required this.canonical, required this.catalog, this.binding,  Map<String, AccountModelEnabledAction> enabledActions = const {}, this.billingAction,  Map<String, ModelLimitDraft> drafts = const {},  Map<ModelLimitsReadField, StudioFailure> readIssues = const {}, this.readPending = false}): _enabledActions = enabledActions,_drafts = drafts,_readIssues = readIssues;


@override final  String accountId;
@override final  ConfigurationState source;
@override final  ModelsState modelSource;
@override final  AccountConfiguration canonical;
@override final  AccountCatalogEntry catalog;
@override final  AccountFieldBinding? binding;
 final  Map<String, AccountModelEnabledAction> _enabledActions;
@override@JsonKey() Map<String, AccountModelEnabledAction> get enabledActions {
  if (_enabledActions is EqualUnmodifiableMapView) return _enabledActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_enabledActions);
}

@override final  AccountBillingAction? billingAction;
 final  Map<String, ModelLimitDraft> _drafts;
@override@JsonKey() Map<String, ModelLimitDraft> get drafts {
  if (_drafts is EqualUnmodifiableMapView) return _drafts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_drafts);
}

 final  Map<ModelLimitsReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<ModelLimitsReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

@override@JsonKey() final  bool readPending;

/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelLimitsViewStateCopyWith<_AccountModelLimitsViewState> get copyWith => __$AccountModelLimitsViewStateCopyWithImpl<_AccountModelLimitsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelLimitsViewState&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.source, source) || other.source == source)&&(identical(other.modelSource, modelSource) || other.modelSource == modelSource)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.binding, binding) || other.binding == binding)&&const DeepCollectionEquality().equals(other.enabledActions, _enabledActions)&&(identical(other.billingAction, billingAction) || other.billingAction == billingAction)&&const DeepCollectionEquality().equals(other.drafts, _drafts)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&(identical(other.readPending, readPending) || other.readPending == readPending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,source,modelSource,canonical,catalog,binding,const DeepCollectionEquality().hash(_enabledActions),billingAction,const DeepCollectionEquality().hash(_drafts),const DeepCollectionEquality().hash(_readIssues),readPending);
}

@override
String toString() {
    return 'AccountModelLimitsViewState(accountId: $accountId, source: $source, modelSource: $modelSource, canonical: $canonical, catalog: $catalog, binding: $binding, enabledActions: $enabledActions, billingAction: $billingAction, drafts: $drafts, readIssues: $readIssues, readPending: $readPending)';
}


}

/// @nodoc
abstract mixin class _$AccountModelLimitsViewStateCopyWith<$Res> implements $AccountModelLimitsViewStateCopyWith<$Res> {
  factory _$AccountModelLimitsViewStateCopyWith(_AccountModelLimitsViewState value, $Res Function(_AccountModelLimitsViewState) _then) = __$AccountModelLimitsViewStateCopyWithImpl;
@override @useResult
$Res call({
 String accountId, ConfigurationState source, ModelsState modelSource, AccountConfiguration canonical, AccountCatalogEntry catalog, AccountFieldBinding? binding, Map<String, AccountModelEnabledAction> enabledActions, AccountBillingAction? billingAction, Map<String, ModelLimitDraft> drafts, Map<ModelLimitsReadField, StudioFailure> readIssues, bool readPending
});


@override $ConfigurationStateCopyWith<$Res> get source;@override $ModelsStateCopyWith<$Res> get modelSource;@override $AccountConfigurationCopyWith<$Res> get canonical;@override $AccountCatalogEntryCopyWith<$Res> get catalog;@override $AccountFieldBindingCopyWith<$Res>? get binding;@override $AccountBillingActionCopyWith<$Res>? get billingAction;

}
/// @nodoc
class __$AccountModelLimitsViewStateCopyWithImpl<$Res>
    implements _$AccountModelLimitsViewStateCopyWith<$Res> {
  __$AccountModelLimitsViewStateCopyWithImpl(this._self, this._then);

  final _AccountModelLimitsViewState _self;
  final $Res Function(_AccountModelLimitsViewState) _then;

/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? source = null,Object? modelSource = null,Object? canonical = null,Object? catalog = null,Object? binding = freezed,Object? enabledActions = null,Object? billingAction = freezed,Object? drafts = null,Object? readIssues = null,Object? readPending = null,}) {
  return _then(_AccountModelLimitsViewState(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,modelSource: null == modelSource ? _self.modelSource : modelSource // ignore: cast_nullable_to_non_nullable
as ModelsState,canonical: null == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as AccountConfiguration,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogEntry,binding: freezed == binding ? _self.binding : binding // ignore: cast_nullable_to_non_nullable
as AccountFieldBinding?,enabledActions: null == enabledActions ? _self._enabledActions : enabledActions // ignore: cast_nullable_to_non_nullable
as Map<String, AccountModelEnabledAction>,billingAction: freezed == billingAction ? _self.billingAction : billingAction // ignore: cast_nullable_to_non_nullable
as AccountBillingAction?,drafts: null == drafts ? _self._drafts : drafts // ignore: cast_nullable_to_non_nullable
as Map<String, ModelLimitDraft>,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<ModelLimitsReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get modelSource {

  return $ModelsStateCopyWith<$Res>(_self.modelSource, (value) {
    return _then(_self.copyWith(modelSource: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res> get canonical {

  return $AccountConfigurationCopyWith<$Res>(_self.canonical, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogEntryCopyWith<$Res> get catalog {

  return $AccountCatalogEntryCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountFieldBindingCopyWith<$Res>? get binding {
    if (_self.binding == null) {
    return null;
  }

  return $AccountFieldBindingCopyWith<$Res>(_self.binding!, (value) {
    return _then(_self.copyWith(binding: value));
  });
}/// Create a copy of AccountModelLimitsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingActionCopyWith<$Res>? get billingAction {
    if (_self.billingAction == null) {
    return null;
  }

  return $AccountBillingActionCopyWith<$Res>(_self.billingAction!, (value) {
    return _then(_self.copyWith(billingAction: value));
  });
}
}

// dart format on
