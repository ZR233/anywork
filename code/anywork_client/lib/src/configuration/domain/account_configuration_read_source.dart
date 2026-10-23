import '../../../resources.dart';
import 'configuration_state.dart';
import 'configuration_values.dart';

/// Borrowed account identity input. It grants no Configuration write or close
/// authority and is implemented by the actual ConfigurationRepository itself.
abstract interface class AccountConfigurationReadSource {
  ReadonlyLatestValue<ConfigurationState> get state;
  Future<AccountConfiguration> loadAccount(String accountId);
}
