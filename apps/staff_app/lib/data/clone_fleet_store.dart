import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted snapshot of the clone fleet: which clones are online and each
/// one's session seconds. Restored on launch so the fleet survives a restart.
class CloneFleetSnapshot {
  final List<bool> online;
  final List<int> elapsed;
  const CloneFleetSnapshot(this.online, this.elapsed);
}

/// Tiny JSON store for the simulated clone fleet (Clones tab). Best-effort:
/// any read/write failure degrades to "no saved state" rather than throwing.
class CloneFleetStore {
  static const _fileName = 'clone_fleet.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns the saved snapshot, or null when there's nothing valid to
  /// restore (first run, corrupt file, or a length mismatch with [count]).
  Future<CloneFleetSnapshot?> load(int count) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final online = (j['online'] as List).map((e) => e == true).toList();
      final elapsed =
          (j['elapsed'] as List).map((e) => (e as num).toInt()).toList();
      if (online.length != count || elapsed.length != count) return null;
      return CloneFleetSnapshot(online, elapsed);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<bool> online, List<int> elapsed) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({'online': online, 'elapsed': elapsed}),
      );
    } catch (_) {
      // Best-effort — a failed write just means this state isn't persisted.
    }
  }
}
