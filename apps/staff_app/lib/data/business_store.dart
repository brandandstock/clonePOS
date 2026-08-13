import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Unambiguous code alphabet — no I/L/O/0/1 so IDs are easy to read aloud and
/// type on the satellite's login screen.
const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A short human-typable code, optionally prefixed (e.g. `BIZ-K7M4PQ`).
String randomCode(int length, {String prefix = ''}) {
  final r = Random();
  final body = List.generate(
    length,
    (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)],
  ).join();
  return prefix.isEmpty ? body : '$prefix-$body';
}

/// Persisted identity of this master's business. Every satellite in the fleet
/// signs in with this Business ID plus its own Clone ID; together they pair the
/// device to a clone slot (and its granted permissions). Generated once on
/// first run and kept stable thereafter.
class BusinessStore {
  static const _fileName = 'business_id.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final id = (await f.readAsString()).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String id) async {
    try {
      await (await _file()).writeAsString(id);
    } catch (_) {
      // Best-effort.
    }
  }
}
