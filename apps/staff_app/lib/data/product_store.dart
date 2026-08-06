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

  /// Overwrites the stored catalog with [products]. Fire-and-forget from the
  /// UI after every mutation.
  Future<void> save(List<Product> products) async {
    try {
      await _write(await _file(), products);
    } catch (_) {
      // Best-effort — a failed write just means this edit isn't persisted.
    }
  }

  Future<void> _write(File f, List<Product> products) async {
    final data = jsonEncode([for (final p in products) p.toJson()]);
    await f.writeAsString(data, flush: true);
  }
}
