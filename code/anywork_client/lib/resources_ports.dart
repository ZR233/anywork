/// Repository and composition-root capabilities; not a feature/Widget API.
library;

export 'resources.dart';
export 'src/resources/data/feed_connection.dart';
export 'src/resources/data/latest_value.dart';
export 'src/resources/data/pinned_read_owner.dart';
export 'src/resources/data/product_feed_owner.dart';
export 'src/resources/data/product_source_read_connection.dart';
export 'src/resources/data/read_materialization.dart'
    show materializeReadText, materializeProductSourceStatus;
export 'src/resources/data/resource_budget.dart';
export 'src/resources/data/resource_errors.dart';
export 'src/resources/data/resource_lifetime.dart';
export 'src/resources/data/resource_source.dart';
