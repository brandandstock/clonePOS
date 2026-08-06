import 'dart:convert';
import 'dart:io';

import 'package:clone_pos_core/models/product.dart';
import 'package:path_provider/path_provider.dart';

import 'seed_products_cybergic_500.dart';

/// Persists the Inventory catalog to a JSON file in the app's documents
/// directory so runtime edits — products added via "Add product", uploaded
/// images, and deletions (of both added and seed items) — survive an app
/// restart. On first run the file doesn't exist yet, so it's seeded from the
/// bundled 500-product Cybergic list and written out.
///
/// All I/O is best-effort: any read/parse failure falls back to the seed and
/// any write failure is swallowed, so a storage hiccup never takes down the
/// Inventory tab.
class ProductStore {
  static const _fileName = 'inventory_catalog.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the persisted catalog, seeding + writing it on first run.
  Future<List<Product>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        final seed = List<Product>.of(seedProductsCybergic500());
        await _write(f, seed);
        return seed;
      }
      final decoded = jsonDecode(await f.readAsString()) as List<dynamic>;
      return decoded
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt/unreadable file → don't crash; fall back to the seed.
      return List<Product>.of(seedProductsCybergic500());
    }
  }

  // Serialised writer: the UI calls save() fire-and-forget after every edit,
  // so bursts (e.g. an import, or rapid deletes) must not run overlapping
  // writeAsString calls against the same file. We keep only the latest
  // snapshot pending and drain it with a single active writer.
  List<Product>? _pending;
  bool _writing = false;

  /// Persists [products]. Takes an immediate snapshot so a later mutation of
  /// the caller's list can't corrupt the in-flight encode, and coalesces
  /// bursts into the most recent state.
  Future<void> save(List<Product> products) async {
    _pending = List<Product>.of(products); // shallow snapshot; Products immutable
    if (_writing) return;
    _writing = true;
    try {
      final f = await _file();
      while (_pending != null) {
        final batch = _pending!;
        _pending = null;
        try {
          await _write(f, batch);
        } catch (_) {
          // Best-effort — a failed write just means this edit isn't persisted.
        }
      }
    } finally {
      _writing = false;
    }
  }

  Future<void> _write(File f, List<Product> products) async {
    final data = jsonEncode([for (final p in products) p.toJson()]);
    await f.writeAsString(data, flush: true);
  }
}
