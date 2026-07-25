enum DeviceRole { master, satellite, cloneposClient }

/// A single paired device instance. Master and Satellite share the same
/// underlying Staff App — role is assigned at pairing time, not by
/// separate codebases.
class Device {
  final String id;
  final DeviceRole role;
  final String storeId;
  final bool isOnline;

  const Device({
    required this.id,
    required this.role,
    required this.storeId,
    this.isOnline = false,
  });

  Device copyWith({bool? isOnline}) {
    return Device(
      id: id,
      role: role,
      storeId: storeId,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
