import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/configuration_state.dart';
import 'configuration_port.dart';

typedef ConfigurationDemand = ({ProductReadOrigin? origin, ConfigurationReadRef? reference, ProductCollectionRef? collection, Object? opening});
typedef ConfigurationBinding = ({ConfigurationReadTarget target, ProductCollectionRef collection, int revision});

/// Private implementation boundary inside this domain, never a public SDK API.
abstract interface class ConfigurationReadAccess {
  ResourceLifetime get lifetime;
  ResourceSource<ConfigurationState> get source;
  ConfigurationDemand capture();
  Future<ConfigurationBinding> bind(ConfigurationDemand demand);
  PinnedReadOwner<ConfigurationReadConnection> pin(ConfigurationReadTarget target);
  bool current(ConfigurationReadTarget target);
}
