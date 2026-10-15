import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';

/// Reveals a saved Thread through the visible sidebar search. Reopened homes
/// need not have a selected/expanded project. This reads diagnostics to identify
/// the title, then uses ordinary UI input; it never changes Client state itself.
Future<void> revealSidebarThread(
  FlutterDriverSession driver,
  String threadId,
) async {
  await driver.waitFor(
    find.byValueKey('sidebar-search'),
    timeout: const Duration(seconds: 60),
  );
  final snapshot = await driver.readSnapshot();
  final title = snapshot['sidebarDirectory']?['titles']?[threadId] as String?;
  if (title == null || title.isEmpty) {
    throw StateError(
      'Saved Thread $threadId is absent from the restored directory',
    );
  }
  await driver.rawTap(find.byValueKey('sidebar-search'));
  await driver.enterText(title);
  await driver.waitFor(
    find.byValueKey('thread-row-$threadId'),
    timeout: const Duration(seconds: 60),
  );
}

Future<void> clearSidebarSearch(FlutterDriverSession driver) async {
  await driver.rawTap(find.byValueKey('sidebar-search'));
  await driver.enterText('');
}
