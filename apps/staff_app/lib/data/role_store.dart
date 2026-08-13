import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// What this physical device has been set up as. A device commits to a role at
/// first launch (from the role chooser) and keeps it until it signs out.
enum DeviceRole { unset, master, clone }

/// The persisted role + (for a clone) the sign-in credentials it uses to pair
/// with the master over the LAN.
class RoleConfig {
  final DeviceRole role;
  final String businessId; // clone only
  final String cloneId; // clone only
  const RoleConfig(this.role, {this.businessId = '', this.cloneId = ''});

  static const unset = RoleConfig(DeviceRole.unset);
}

/// Best-effort JSON store for this device's role. Any failure degrades to
/// "unset" so the role chooser is shown.
class RoleStore {
  static const _fileName = 'device_role.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<RoleConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return RoleConfig.unset;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final role = switch (j['role']) {
        'master' => DeviceRole.master,
        'clone' => DeviceRole.clone,
        _ => DeviceRole.unset,
      };
      return RoleConfig(
        role,
        businessId: (j['businessId'] as String?) ?? '',
        cloneId: (j['cloneId'] as String?) ?? '',
      );
    } catch (_) {
      return RoleConfig.unset;
    }
  }

  Future<void> saveMaster() => _save(const RoleConfig(DeviceRole.master));

  Future<void> saveClone(String businessId, String cloneId) => _save(
        RoleConfig(DeviceRole.clone,
            businessId: businessId, cloneId: cloneId),
      );

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _save(RoleConfig c) async {
    try {
      await (await _file()).writeAsString(jsonEncode({
        'role': c.role.name,
        'businessId': c.businessId,
        'cloneId': c.cloneId,
      }));
    } catch (_) {}
  }
}
