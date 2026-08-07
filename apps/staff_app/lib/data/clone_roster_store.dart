import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One created clone (Satellite): a display name + its department/posting
/// (shown as the card subtitle). A fleet slot with no record is an empty
/// "Create Clone" slot the master can fill.
class CloneRecord {
  final String name;
  final String department;
  const CloneRecord(this.name, this.department);

  Map<String, dynamic> toJson() => {'name': name, 'department': department};

  static CloneRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.isEmpty) return null;
    final dept = j['department'];
    return CloneRecord(name, dept is String ? dept : '');
  }
}

/// Tiny JSON store for the clone ROSTER — which of the fixed fleet slots have
/// been created and each one's name/department. Best-effort, mirroring
/// [CloneFleetStore]: any read/write failure degrades to "no saved state"
/// rather than throwing.
///
/// Persisted as a fixed-length list (one entry per slot); a null entry is an
/// empty slot. First run / corrupt file / length mismatch → null, which the
/// caller treats as "seed the default roster".
class CloneRosterStore {
  static const _fileName = 'clone_roster.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns the saved roster (length [count]), or null when there's nothing
  /// valid to restore — callers should seed the default roster instead.
  Future<List<CloneRecord?>?> load(int count) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final raw = j['slots'] as List;
      if (raw.length != count) return null;
      return [for (final e in raw) CloneRecord.fromJson(e)];
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<CloneRecord?> slots) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({'slots': [for (final s in slots) s?.toJson()]}),
      );
    } catch (_) {
      // Best-effort — a failed write just means this roster isn't persisted.
    }
  }
}
