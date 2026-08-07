import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The eight app features the master can grant a clone access to. Order and
/// labels mirror the landing tiles (Carts … Data) so the permission editor
/// reads the same as the dashboard grid.
const List<String> kCloneAccessFeatures = [
  'Carts',
  'Clones',
  'Inventory',
  'Logistics',
  'Analytics',
  'Accounts',
  'Sales Kit',
  'Data',
];

/// Tiny JSON store for the PER-CLONE access grants — for each satellite the
/// master has created, the set of feature labels it is permitted to open.
/// Best-effort, mirroring [CloneFleetStore]: any read/write failure degrades
/// to "no saved state" rather than throwing.
///
/// Persisted as a list of feature-lists, one entry per clone (index-aligned
/// with the fleet). First run / corrupt file / length mismatch → null, which
/// callers treat as "grant every feature to every clone".
class CloneAccessStore {
  static const _fileName = 'clone_access.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns each clone's granted feature set (index-aligned to the fleet),
  /// or null when there's nothing valid to restore for [count] clones —
  /// callers should treat null as "grant all to all".
  Future<List<Set<String>>?> load(int count) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final raw = j['grants'] as List;
      if (raw.length != count) return null;
      return [
        for (final entry in raw)
          (entry as List)
              .map((e) => e.toString())
              .where(kCloneAccessFeatures.contains)
              .toSet(),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<Set<String>> grants) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({'grants': [for (final g in grants) g.toList()]}),
      );
    } catch (_) {
      // Best-effort — a failed write just means this grant isn't persisted.
    }
  }
}
