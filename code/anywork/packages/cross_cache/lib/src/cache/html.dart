import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'base_cache.dart';

/// Web (HTML) implementation of [BaseCache] using IndexedDB.
class Cache extends BaseCache {
  Database? _db;
  Future<Database>? _opening;
  bool _disposed = false;

  void _onUpgradeNeeded(VersionChangeEvent event) {
    final database = event.database;
    if (!database.objectStoreNames.contains('data')) {
      database.createObjectStore('data');
    }
  }

  Future<Database> _open() async {
    try {
      final database = await idbFactoryBrowser.open(
        'cross_cache_db',
        version: 1,
        onUpgradeNeeded: _onUpgradeNeeded,
      );

      if (_disposed) {
        database.close();
        throw StateError('Cache disposed during open');
      }
      _db = database;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _ensureDbOpen() async {
    if (_disposed) throw StateError('Cache disposed');
    // Only a real operation opens the database and owns its possible failure.
    final database = _db ?? await (_opening ??= _open());
    if (_disposed) throw StateError('Cache disposed');
    return database;
  }

  @override
  Future<void> set(String key, Uint8List value) async {
    final database = await _ensureDbOpen();

    final transaction = database.transaction('data', 'readwrite');
    final store = transaction.objectStore('data');
    await store.put(value, key);
    await transaction.completed;
  }

  @override
  Future<Uint8List> get(String key) async {
    final database = await _ensureDbOpen();

    final transaction = database.transaction('data', 'readonly');
    final store = transaction.objectStore('data');
    final data = await store.getObject(key);
    await transaction.completed;

    if (data is Uint8List) {
      return data;
    } else if (data == null) {
      throw Exception('Key not found in cache: $key');
    } else {
      throw Exception('Data is not of type Uint8List');
    }
  }

  @override
  Future<bool> contains(String key) async {
    final database = await _ensureDbOpen();

    final transaction = database.transaction('data', 'readonly');
    final store = transaction.objectStore('data');
    final result = await store.getObject(key);
    await transaction.completed;

    return result != null;
  }

  @override
  Future<void> delete(String key) async {
    final database = await _ensureDbOpen();

    final transaction = database.transaction('data', 'readwrite');
    final store = transaction.objectStore('data');
    await store.delete(key);
    await transaction.completed;
  }

  @override
  Future<void> updateKey(String key, String newKey) async {
    final database = await _ensureDbOpen();

    final transaction = database.transaction('data', 'readwrite');
    final store = transaction.objectStore('data');
    final data = await store.getObject(key);

    if (data == null) {
      await transaction.completed;
      throw Exception('Key not found: $key');
    }

    try {
      await store.put(data, newKey);
      await store.delete(key);
      await transaction.completed;
    } catch (e) {
      transaction.abort();
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _db?.close();
    _db = null;
  }
}
